# =========================================================
#  AudioQuickSwitch — трей-приложение для Windows
#  ЛКМ по значку   -> вкл/выкл "Прослушивать с данного устройства"
#                     для микрофона по умолчанию
#  ПКМ по значку    -> меню выбора устройства воспроизведения
#                     по умолчанию (один клик = переключение)
# =========================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -ReferencedAssemblies "System.Windows.Forms", "System.Drawing" -TypeDefinition @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class DwmHelper {
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
    // Рамку скруглённого окна Windows 11 рисует сама и по умолчанию полупрозрачной -
    // сквозь неё просвечивало то, что под окном. Красим её сплошным цветом.
    public static void SetBorder(IntPtr h, Color c) {
        int v = c.R | (c.G << 8) | (c.B << 16);   // COLORREF
        try { DwmSetWindowAttribute(h, 34, ref v, 4); } catch { }   // DWMWA_BORDER_COLOR
    }

    // Запуск без курсора "запуск приложения" (стрелка с колёсиком). Его Windows
    // показывает, когда программу запускает процесс с окнами - а утилита с 1.2.0
    // это AudioQuickSwitch.exe (до этого консольный powershell.exe, колёсика не было).
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct StartupInfo { public int cb; public string reserved, desktop, title; public int x, y, xSize, ySize, xChars, yChars, fill, flags; public short show, reserved2; public IntPtr reserved3, stdIn, stdOut, stdErr; }
    [StructLayout(LayoutKind.Sequential)]
    struct ProcInfo { public IntPtr hProcess, hThread; public int pid, tid; }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern bool CreateProcess(string app, string cmd, IntPtr pa, IntPtr ta, bool inherit, int flags, IntPtr env, string dir, ref StartupInfo si, out ProcInfo pi);
    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr h);
    public static void StartNoFeedback(string cmdLine, short showCmd) {
        StartupInfo si = new StartupInfo();
        si.cb = Marshal.SizeOf(si);
        si.flags = 0x80 | 0x1;   // STARTF_FORCEOFFFEEDBACK | STARTF_USESHOWWINDOW
        si.show = showCmd;
        ProcInfo pi;
        if (CreateProcess(null, cmdLine, IntPtr.Zero, IntPtr.Zero, false, 0, IntPtr.Zero, null, ref si, out pi)) {
            CloseHandle(pi.hProcess); CloseHandle(pi.hThread);
        }
    }
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hwnd);

    // Левый край значка в трее (экранные координаты), -1 если Windows не отдала.
    [StructLayout(LayoutKind.Sequential)]
    struct NotifyIconId { public int cbSize; public IntPtr hWnd; public uint uID; public Guid guidItem; }
    [StructLayout(LayoutKind.Sequential)]
    struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("shell32.dll")]
    static extern int Shell_NotifyIconGetRect(ref NotifyIconId id, out Rect r);
    public static int TrayIconLeft(IntPtr hwnd, int id) {
        NotifyIconId n = new NotifyIconId();
        n.cbSize = Marshal.SizeOf(n); n.hWnd = hwnd; n.uID = (uint)id;
        Rect r;
        return Shell_NotifyIconGetRect(ref n, out r) == 0 ? r.Left : -1;
    }
}

// Подсветку пункта рисуем сами. Штатная: без EnableVisualStyles (PowerShell его не
// зовёт) берёт системный светло-голубой вместо цветов таблицы - белый текст на нём
// не читается; прямоугольник до самых краёв давал острые углы у скруглённого меню;
// неактивные заголовки обводила рамкой. Здесь - как в Windows 11: скруглённая
// плашка с отступом от краёв, у неактивных пунктов ничего.
public class Win11Renderer : ToolStripProfessionalRenderer {
    public Win11Renderer(ProfessionalColorTable t) : base(t) { }
    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e) {
        if (!e.Item.Enabled || !e.Item.Selected || AqsMenu.Dragged(e.Item)) return;
        using (System.Drawing.Drawing2D.GraphicsPath p = Round(Plate(e.Item), 8))
        using (Brush b = new SolidBrush(ColorTable.MenuItemSelected)) {
            e.Graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            e.Graphics.FillPath(b, p);
        }
    }
    // плашка подсветки в координатах пункта. Пункты-устройства у WinForms шире видимой
    // части меню (свой Padding) - без ограничения правое скругление уходило за рамку
    public static Rectangle Plate(ToolStripItem i) {
        int w = Math.Min(i.Width, i.Owner.DisplayRectangle.Right - i.Bounds.X);
        return new Rectangle(4, 1, w - 8, i.Height - 2);
    }
    public static System.Drawing.Drawing2D.GraphicsPath Round(Rectangle r, int d) {   // d - диаметр скругления
        System.Drawing.Drawing2D.GraphicsPath p = new System.Drawing.Drawing2D.GraphicsPath();
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    // Заряд беспроводного устройства после названия: "realme Buds Air8 Pro ● 100".
    // Точка со свечением - цвет плавно зелёный -> жёлтый (50) -> красный; число
    // жирным, обычным цветом текста меню. Уровень - Tag[4] пункта (-1 - не рисуем),
    // ширину меню под это считает Build-Menu (ContentWidth).
    const int D = 8;   // диаметр точки
    const TextFormatFlags NoPad = TextFormatFlags.NoPadding;
    // Видимая ширина подписи пункта (с " ● 100", если battery) - для расчёта ширины меню.
    // Меряем на настоящем Graphics: без него MeasureText флаг NoPadding игнорирует и
    // прибавляет поля вокруг букв (на "100" - почти вдвое).
    public static int ContentWidth(string text, Font f, int level) {   // level < 0 - без заряда
        using (Bitmap bmp = new Bitmap(1, 1))
        using (Graphics g = Graphics.FromImage(bmp))
        using (Font b = new Font(f, FontStyle.Bold)) {
            int w = TextRenderer.MeasureText(g, text, f, Size.Empty, NoPad).Width;
            // -3: у жирных цифр справа пустой "хвост" глифа, без вычета отступ справа
            // от числа выходил на 3 px больше, чем слева от текста (замерено по пикселям)
            return level >= 0 ? w + 6 + D + 5 + TextRenderer.MeasureText(g, level.ToString(), b, Size.Empty, NoPad).Width - 3 : w;
        }
    }
    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e) {
        if (AqsMenu.Dragged(e.Item)) return;   // место перетаскиваемого пункта пустое
        // "Мониторинг: ВКЛ" (Tag = "boldTail") - состояние после двоеточия жирным
        int colon = e.Item.Tag as string == "boldTail" ? e.Text.IndexOf(':') : -1;
        if (colon >= 0) {
            string head = e.Text.Substring(0, colon + 1);
            Color tc = e.Item.Enabled ? e.TextColor : SystemColors.GrayText;
            Rectangle r = e.TextRectangle;
            TextRenderer.DrawText(e.Graphics, head, e.TextFont, r, tc, e.TextFormat);
            // конец видимого head: DrawText рисует его с полями вокруг букв
            int hx = r.X + (TextRenderer.MeasureText(e.Graphics, head, e.TextFont, Size.Empty, e.TextFormat).Width
                          + TextRenderer.MeasureText(e.Graphics, head, e.TextFont, Size.Empty, e.TextFormat | NoPad).Width) / 2;
            using (Font bold = new Font(e.TextFont, FontStyle.Bold))
                TextRenderer.DrawText(e.Graphics, e.Text.Substring(colon + 1), bold, new Rectangle(hx, r.Y, r.Right - hx, r.Height), tc, e.TextFormat | NoPad);
            return;
        }
        object[] tag = e.Item.Tag as object[];
        // активное устройство - с мягким свечением своего (акцентного) цвета
        if (tag != null && tag.Length > 2 && tag[2] is bool && (bool)tag[2] && e.Text == tag[1] as string) {
            Glow(e.Graphics, e.Text, e.TextFont, e.TextRectangle, e.TextFormat, e.TextColor);
        }
        base.OnRenderItemText(e);
        // WinForms зовёт это и для пустого поля горячей клавиши - рисуем только у названия
        if (tag == null || tag.Length < 5 || !(tag[4] is int) || (int)tag[4] < 0 || e.Text != tag[1] as string) return;
        int level = Math.Min(100, (int)tag[4]);
        Color c = level >= 50 ? Lerp(Color.FromArgb(215, 175, 40), Color.FromArgb(40, 200, 90), (level - 50) / 50f)
                              : Lerp(Color.FromArgb(225, 60, 60), Color.FromArgb(215, 175, 40), level / 50f);
        Rectangle t = e.TextRectangle;
        // конец видимого текста: base рисует его с полями вокруг букв - вычитаем правое поле
        int full = TextRenderer.MeasureText(e.Graphics, e.Text, e.TextFont, Size.Empty, e.TextFormat).Width;
        int bare = TextRenderer.MeasureText(e.Graphics, e.Text, e.TextFont, Size.Empty, e.TextFormat | NoPad).Width;
        int x = t.X + (full + bare) / 2 + 6;
        int y = t.Y + (t.Height - D) / 2;
        e.Graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        // Свечение: круг радиусом 9 px с тем же центром, радиальный градиент того же
        // цвета - к краю 0, спад неравномерный (на середине радиуса 35% центральной
        // плотности): мягко снаружи, плотно у точки. В центре альфа 0xA0 на полном
        // заряде и слабее к нулю (0x50) - иначе разряженная красная точка "горит".
        const int G = 9;
        float cx = x + D / 2f, cy = y + D / 2f;
        using (System.Drawing.Drawing2D.GraphicsPath gp = new System.Drawing.Drawing2D.GraphicsPath()) {
            gp.AddEllipse(cx - G, cy - G, 2 * G, 2 * G);
            using (System.Drawing.Drawing2D.PathGradientBrush glow = new System.Drawing.Drawing2D.PathGradientBrush(gp)) {
                glow.CenterColor = Color.FromArgb(0x50 + (0xA0 - 0x50) * level / 100, c);
                glow.SurroundColors = new Color[] { Color.FromArgb(0, c) };
                System.Drawing.Drawing2D.Blend bl = new System.Drawing.Drawing2D.Blend(3);
                bl.Positions = new float[] { 0f, 0.5f, 1f };   // 0 - край, 1 - центр
                bl.Factors = new float[] { 0f, 0.35f, 1f };
                glow.Blend = bl;
                e.Graphics.FillPath(glow, gp);
            }
        }
        using (Brush b = new SolidBrush(c)) e.Graphics.FillEllipse(b, x, y, D, D);
        using (Font bold = new Font(e.TextFont, FontStyle.Bold))
            TextRenderer.DrawText(e.Graphics, level.ToString(), bold, new Rectangle(x + D + 5, t.Y, 60, t.Height), e.ToolStrip.ForeColor, e.TextFormat | NoPad);   // обычным цветом текста меню, не акцентным
    }
    // Свечение под текстом по форме букв, мягкое, как у точки заряда. Буквы для него
    // рисуются тем же TextRenderer'ом и с теми же r/flags, что и сам текст (контур
    // через GDI+ шире и ниже - на длинной строке ореол уезжал на 3 px), белым по
    // чёрному; ColorMatrix делает из этого маску цвета c (яркость -> прозрачность),
    // и она накладывается со сдвигами по кругу на 1..R px: ближние кольца плотнее.
    public static void Glow(Graphics g, string text, Font f, Rectangle r, TextFormatFlags flags, Color c) {
        const int R = 4;
        using (Bitmap m = new Bitmap(r.Width + 2 * R, r.Height + 2 * R))
        using (System.Drawing.Imaging.ImageAttributes ia = new System.Drawing.Imaging.ImageAttributes()) {
            using (Graphics mg = Graphics.FromImage(m)) {
                mg.Clear(Color.Black);
                TextRenderer.DrawText(mg, text, f, new Rectangle(R, R, r.Width, r.Height), Color.White, flags);
            }
            System.Drawing.Imaging.ColorMatrix cm = new System.Drawing.Imaging.ColorMatrix();
            cm.Matrix00 = cm.Matrix11 = cm.Matrix22 = cm.Matrix33 = 0;   // цвет - постоянный c,
            cm.Matrix40 = c.R / 255f; cm.Matrix41 = c.G / 255f; cm.Matrix42 = c.B / 255f;
            for (int k = R; k >= 1; k--) {
                cm.Matrix03 = (3 + 2 * (R - k)) / 255f;   // прозрачность - из яркости букв; k=R: 3 ... k=1: 9
                ia.SetColorMatrix(cm);
                for (int i = 0; i < 12; i++) {
                    int dx = (int)Math.Round(k * Math.Cos(i * Math.PI / 6)), dy = (int)Math.Round(k * Math.Sin(i * Math.PI / 6));
                    g.DrawImage(m, new Rectangle(r.X - R + dx, r.Y - R + dy, m.Width, m.Height), 0, 0, m.Width, m.Height, GraphicsUnit.Pixel, ia);
                }
            }
        }
    }
    static Color Lerp(Color a, Color b, float t) {
        return Color.FromArgb((int)(a.R + (b.R - a.R) * t), (int)(a.G + (b.G - a.G) * t), (int)(a.B + (b.B - a.B) * t));
    }
}

public class Win11ColorTable : ProfessionalColorTable {
    private Color bg, hover, border;
    public Win11ColorTable(Color bg, Color hover, Color border) {
        this.bg = bg; this.hover = hover; this.border = border;
    }
    public override Color ToolStripDropDownBackground { get { return bg; } }
    public override Color ImageMarginGradientBegin { get { return bg; } }
    public override Color ImageMarginGradientMiddle { get { return bg; } }
    public override Color ImageMarginGradientEnd { get { return bg; } }
    public override Color MenuBorder { get { return border; } }
    public override Color MenuItemBorder { get { return hover; } }
    public override Color MenuItemSelected { get { return hover; } }
    public override Color MenuItemSelectedGradientBegin { get { return hover; } }
    public override Color MenuItemSelectedGradientEnd { get { return hover; } }
    public override Color SeparatorDark { get { return border; } }
    public override Color SeparatorLight { get { return border; } }
}

// Core Audio: громкость устройства вывода по умолчанию напрямую, без svcl.exe.
// Методы объявлены строго в порядке vtable - пропускать или менять местами нельзя.
[ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAqsEndpointVolume {
    void RegisterControlChangeNotify(IntPtr notify);
    void UnregisterControlChangeNotify(IntPtr notify);
    void GetChannelCount(out uint count);
    void SetMasterVolumeLevel(float levelDb, ref Guid context);
    void SetMasterVolumeLevelScalar(float level, ref Guid context);
    void GetMasterVolumeLevel(out float levelDb);
    void GetMasterVolumeLevelScalar(out float level);
}

[ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAqsMMDevice {
    void Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
}

[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAqsMMDeviceEnumerator {
    void EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
    void GetDefaultAudioEndpoint(int dataFlow, int role, out IAqsMMDevice device);
    void GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IAqsMMDevice device);   // не зовём - место в vtable
    void RegisterEndpointNotificationCallback(IAqsMMNotificationClient client);
}

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
public class AqsMMDeviceEnumerator { }

[StructLayout(LayoutKind.Sequential)]
public struct AqsPropertyKey { public Guid fmtid; public int pid; }

[Guid("7991EEC9-7E89-4D85-8390-6C703CEC60C0"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAqsMMNotificationClient {
    void OnDeviceStateChanged([MarshalAs(UnmanagedType.LPWStr)] string id, int state);
    void OnDeviceAdded([MarshalAs(UnmanagedType.LPWStr)] string id);
    void OnDeviceRemoved([MarshalAs(UnmanagedType.LPWStr)] string id);
    void OnDefaultDeviceChanged(int flow, int role, [MarshalAs(UnmanagedType.LPWStr)] string id);
    void OnPropertyValueChanged([MarshalAs(UnmanagedType.LPWStr)] string id, AqsPropertyKey key);
}

// Уведомления Windows о звуковых устройствах: подключили/отключили (Bluetooth и т.п.),
// сменили устройство по умолчанию мимо утилиты. Приходят на чужом потоке и пачками
// (смена по умолчанию - по разу на каждую роль), поэтому Changed - на потоке
// интерфейса и один раз на пачку (через 300 мс тишины). Свойства устройств
// (OnPropertyValueChanged) не слушаем - они меняются постоянно.
public class AqsDeviceWatch : IAqsMMNotificationClient {
    public static event EventHandler Changed;
    // Оба держим сами: Windows на подписчика ссылку НЕ берёт (AddRef не делает) -
    // без поля сборщик мусора его удалял, и первое же уведомление (например, при
    // включении мониторинга) роняло процесс в clr.dll (0xc0000005).
    static AqsDeviceWatch inst;
    static IAqsMMDeviceEnumerator en;
    static Control ui;
    static Timer quiet;
    public static void Start() {   // звать с потока интерфейса
        ui = new Control(); ui.CreateControl();
        quiet = new Timer(); quiet.Interval = 300;
        quiet.Tick += delegate { quiet.Stop(); if (Changed != null) Changed(null, EventArgs.Empty); };
        en = (IAqsMMDeviceEnumerator)new AqsMMDeviceEnumerator();
        inst = new AqsDeviceWatch();
        en.RegisterEndpointNotificationCallback(inst);
    }
    static void Poke() { ui.BeginInvoke((MethodInvoker)delegate { quiet.Stop(); quiet.Start(); }); }
    public void OnDeviceStateChanged(string id, int state) { Poke(); }
    public void OnDeviceAdded(string id) { Poke(); }
    public void OnDeviceRemoved(string id) { Poke(); }
    public void OnDefaultDeviceChanged(int flow, int role, string id) { Poke(); }
    public void OnPropertyValueChanged(string id, AqsPropertyKey key) { }
}

// Меню, где устройства (пункты с Tag-массивом) переставляются мышью: зажатый пункт
// "парит" под курсором (его плашка с тенью и "дышащим" свечением поверх меню), его место пустое
// и переезжает между соседями на лету. После отпускания - Reordered (порядок
// сохраняет скрипт). Отпускание после перетаскивания до пунктов не доходит: иначе оно
// было бы кликом - включилось бы устройство (или "Выход", если отпустить над ним).
public class AqsMenu : ContextMenuStrip {
    public event EventHandler Reordered;
    public Color Glow = Color.Gray;   // свечение плашки - акцент Windows, ставит Set-MenuTheme
    const int M = 16;                 // поля спрайта под тень и свечение
    ToolStripItem pressed, drag;
    int downY, grabDY, dragY, grabTick;
    Bitmap sprite, glow; Point spriteOff;   // плашка с тенью, свечение; сдвиг от угла пункта
    System.Windows.Forms.Timer pulse;       // дыхание свечения, пока тащим

    public bool Dragging { get { return drag != null; } }
    public static bool Dragged(ToolStripItem i) { AqsMenu m = i.Owner as AqsMenu; return m != null && m.drag == i; }
    static bool IsDevice(ToolStripItem i) { return i != null && i.Tag is object[]; }

    protected override void OnMouseDown(MouseEventArgs e) {
        ToolStripItem i = GetItemAt(e.Location);
        pressed = e.Button == MouseButtons.Left && IsDevice(i) ? i : null;
        downY = e.Y;
        base.OnMouseDown(e);
    }
    protected override void OnMouseMove(MouseEventArgs e) {
        if (pressed != null && drag == null && Math.Abs(e.Y - downY) > 4) {
            MakeSprite(pressed);
            drag = pressed; grabDY = downY - pressed.Bounds.Y; grabTick = Environment.TickCount;
            pulse = new System.Windows.Forms.Timer();
            pulse.Interval = 30;
            pulse.Tick += delegate { Invalidate(SpriteRect()); };
            pulse.Start();
        }
        if (drag == null) { base.OnMouseMove(e); return; }
        // плашка ходит только в пределах блока устройств
        int top = int.MaxValue, bottom = 0;
        foreach (ToolStripItem i in Items) if (IsDevice(i)) { top = Math.Min(top, i.Bounds.Top); bottom = Math.Max(bottom, i.Bounds.Bottom); }
        dragY = Math.Max(top, Math.Min(bottom - drag.Height, e.Y - grabDY));
        int mid = dragY + drag.Height / 2;
        foreach (ToolStripItem i in Items) {
            if (i == drag || !IsDevice(i) || mid < i.Bounds.Top || mid >= i.Bounds.Bottom) continue;
            int to = Items.IndexOf(i);   // вниз - встаёт после соседа, вверх - перед ним
            // одна раскладка на перестановку: иначе после Remove ползунок (дочернее окно)
            // успевал съехать на строку вверх и вернуться - оставлял артефакты
            SuspendLayout();
            Items.Remove(drag);
            Items.Insert(to, drag);
            ResumeLayout();
            break;
        }
        Invalidate();   // без base: подсветка не бегает за курсором по пунктам
    }
    protected override void OnMouseUp(MouseEventArgs e) {
        pressed = null;
        if (drag == null) { base.OnMouseUp(e); return; }
        pulse.Dispose(); sprite.Dispose(); glow.Dispose();
        drag = null;
        Invalidate();
        if (Reordered != null) Reordered(this, EventArgs.Empty);
    }
    protected override void OnPaint(PaintEventArgs e) {
        base.OnPaint(e);
        if (drag == null) return;
        Rectangle r = SpriteRect();
        // дыхание: свечение плавно 100% -> 35% -> 100% за 2.4 с, с пика в момент захвата
        double t = (Environment.TickCount - grabTick) * 2 * Math.PI / 2400;
        System.Drawing.Imaging.ColorMatrix cm = new System.Drawing.Imaging.ColorMatrix();
        cm.Matrix33 = (float)(0.35 + 0.65 * (0.5 + 0.5 * Math.Cos(t)));
        using (System.Drawing.Imaging.ImageAttributes ia = new System.Drawing.Imaging.ImageAttributes()) {
            ia.SetColorMatrix(cm);
            e.Graphics.DrawImage(glow, r, 0, 0, r.Width, r.Height, GraphicsUnit.Pixel, ia);
        }
        e.Graphics.DrawImage(sprite, r.X, r.Y);
    }
    Rectangle SpriteRect() { return new Rectangle(drag.Bounds.X + spriteOff.X, dragY + spriteOff.Y, sprite.Width, sprite.Height); }

    // Спрайты собираются раз при захвате (дальше на каждый кадр - только DrawImage):
    // свечение отдельно (ему кадр за кадром меняется прозрачность), и плашка - тень
    // чуть ниже и сама плашка из снимка меню вместе с подсветкой (кисть-текстура по
    // скруглённому контуру: края сглажены, в отличие от SetClip).
    void MakeSprite(ToolStripItem it) {
        Rectangle pl = Win11Renderer.Plate(it);
        spriteOff = new Point(pl.X - M, pl.Y - M);
        sprite = new Bitmap(pl.Width + 2 * M, pl.Height + 2 * M);
        glow = new Bitmap(sprite.Width, sprite.Height);
        Rectangle r = new Rectangle(M, M, pl.Width, pl.Height);
        using (Graphics g = Graphics.FromImage(glow)) {
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            Halo(g, r, Color.FromArgb(12, Glow), 6, 0);   // к краю реже,
            Halo(g, r, Color.FromArgb(16, Glow), 3, 0);   // у плашки плотнее
        }
        using (Bitmap all = new Bitmap(Width, Height))
        using (Graphics g = Graphics.FromImage(sprite)) {
            DrawToBitmap(all, new Rectangle(0, 0, Width, Height));
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            Halo(g, r, Color.FromArgb(13, 0, 0, 0), 8, 7);   // тень - мягкая, ниже плашки
            using (System.Drawing.Drawing2D.GraphicsPath p = Win11Renderer.Round(r, 8))
            using (TextureBrush tb = new TextureBrush(all)) {
                tb.TranslateTransform(M - it.Bounds.X - pl.X, M - it.Bounds.Y - pl.Y);
                g.FillPath(tb, p);
            }
        }
    }
    // мягкий ореол вокруг r: n слоёв, каждый шире и прозрачнее, со сдвигом вниз dy
    static void Halo(Graphics g, Rectangle r, Color c, int n, int dy) {
        using (Brush b = new SolidBrush(c))
            for (int i = n; i >= 1; i--) {
                Rectangle l = r; l.Inflate(i, i); l.Offset(0, dy);
                using (System.Drawing.Drawing2D.GraphicsPath p = Win11Renderer.Round(l, 8 + 2 * i)) g.FillPath(b, p);
            }
    }
}

// Заряд Bluetooth-гарнитуры. Windows узнаёт его по Hands-Free (HFP) и хранит в
// свойстве узла этой службы; читаем напрямую через cfgmgr32 - Get-PnpDeviceProperty
// на то же свойство стоит ~600 мс. -1: Windows заряд не знает или узла нет.
public static class AqsBattery {
    [StructLayout(LayoutKind.Sequential)]
    struct DevPropKey { public Guid fmtid; public uint pid; }
    [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
    static extern int CM_Locate_DevNodeW(out uint devInst, string deviceId, int flags);
    [DllImport("cfgmgr32.dll")]
    static extern int CM_Get_DevNode_PropertyW(uint devInst, ref DevPropKey key, out uint type, byte[] buf, ref int size, int flags);
    public static int Get(string instanceId) {
        uint dn;
        if (CM_Locate_DevNodeW(out dn, instanceId, 0) != 0) return -1;
        DevPropKey k = new DevPropKey();
        k.fmtid = new Guid("104EA319-6EE2-4701-BD47-8DDBF425BBE5"); k.pid = 2;
        byte[] b = new byte[4]; int size = b.Length; uint type;
        if (CM_Get_DevNode_PropertyW(dn, ref k, out type, b, ref size, 0) != 0 || size < 1) return -1;
        return b[0];
    }
}

public static class AqsVolume {
    // Устройство берём заново на каждый вызов: после переключения вывода
    // закешированное указывало бы на старое. Стоит это микросекунды.
    static IAqsEndpointVolume Endpoint() {
        IAqsMMDeviceEnumerator en = (IAqsMMDeviceEnumerator)new AqsMMDeviceEnumerator();
        IAqsMMDevice dev;
        en.GetDefaultAudioEndpoint(0, 1, out dev);            // eRender, eMultimedia
        Guid iid = typeof(IAqsEndpointVolume).GUID;
        object o;
        dev.Activate(ref iid, 23, IntPtr.Zero, out o);       // CLSCTX_ALL
        return (IAqsEndpointVolume)o;
    }
    public static int Get() {
        float v;
        Endpoint().GetMasterVolumeLevelScalar(out v);
        return (int)Math.Round(v * 100);
    }
    public static void Set(int percent) {
        Guid ctx = Guid.Empty;
        Endpoint().SetMasterVolumeLevelScalar(percent / 100f, ref ctx);
    }

    // Реальное изменение громкости стоит ~8 мс: Windows синхронно рассылает
    // уведомление всем, кто за ней следит. На потоке интерфейса ползунок из-за
    // этого шёл рывками, поэтому ставим в фоне и только последнее значение -
    // промежуточные при быстром движении мыши пропускаются.
    static volatile int pending;
    static int busy;
    public static void SetAsync(int percent) {
        pending = percent;
        if (System.Threading.Interlocked.Exchange(ref busy, 1) == 0)
            System.Threading.ThreadPool.QueueUserWorkItem(ApplyPending);
    }
    static void ApplyPending(object unused) {
        while (true) {
            int v = pending;
            try { Set(v); } catch { }
            System.Threading.Interlocked.Exchange(ref busy, 0);
            if (pending == v) return;                                              // новых значений не пришло
            if (System.Threading.Interlocked.Exchange(ref busy, 1) != 0) return;   // их уже подхватил другой поток
        }
    }
}

// Ползунок в стиле Windows 11: скруглённая дорожка, заполнение акцентным цветом,
// круглый бегунок с точкой. Штатный TrackBar рисует сама Windows - его не перекрасить.
public class AqsSlider : Control {
    public Color Accent = Color.FromArgb(0, 120, 215);
    public bool Dark;
    int val;
    bool dragging, hover;
    const int R = 10;      // радиус бегунка
    // Дорожка - ровно по краям текста пунктов меню (отступ LineIn от краёв контрола),
    // бегунок ходит внутри неё и за её концы не вылезает: слева и справа поровну.
    const int LineIn = 4;
    const int LabelH = 22; // строка подписи "Громкость: N" над дорожкой
    // Подпись рисуем сами, внутри контрола: отдельный пункт меню с меняющимся
    // текстом при каждом шаге заставлял всё меню пересчитывать раскладку.
    const string Label = "Громкость:";
    const int LabelX = 3;  // замерено: так текст встаёт ровно под текстом пунктов меню

    public AqsSlider() {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
    }

    // Value только показывает значение (при сборке меню и при его открытии).
    // Громкость меняет лишь действие пользователя - UserSet, иначе пересборка меню
    // могла бы затереть последнее движение ползунка, ещё не применённое в фоне.
    public int Value {
        get { return val; }
        set { val = value; Invalidate(); }
    }

    // Громкость ставится прямо отсюда, в C#: обработчик на PowerShell на каждый
    // пиксель движения стоил ~15 мс и давал рывки.
    void UserSet(int v) {
        v = Math.Max(0, Math.Min(100, v));
        if (v == val) return;
        val = v;
        Invalidate();
        AqsVolume.SetAsync(val);
    }

    int X0 { get { return LineIn + R; } }
    int X1 { get { return Width - LineIn - R; } }
    int XOf(int v) { return X0 + (X1 - X0) * v / 100; }
    int ValueAt(int x) { return (int)Math.Round((x - X0) * 100.0 / Math.Max(1, X1 - X0)); }

    static Pen RoundPen(Color c) {
        Pen p = new Pen(c, 4);
        p.StartCap = System.Drawing.Drawing2D.LineCap.Round;
        p.EndCap = System.Drawing.Drawing2D.LineCap.Round;
        return p;
    }

    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        g.Clear(BackColor);
        int cy = LabelH + (Height - LabelH) / 2, x = XOf(val);
        using (Pen p = RoundPen(Dark ? Color.FromArgb(153, 153, 153) : Color.FromArgb(138, 138, 138))) g.DrawLine(p, LineIn + 2, cy, Width - LineIn - 2, cy);   // +2 - круглый конец пера
        using (Pen p = RoundPen(Accent)) g.DrawLine(p, LineIn + 2, cy, x, cy);
        using (Brush b = new SolidBrush(Dark ? Color.FromArgb(69, 69, 69) : Color.White)) g.FillEllipse(b, x - R, cy - R, 2 * R, 2 * R);
        using (Pen p = new Pen(Dark ? Color.FromArgb(84, 84, 84) : Color.FromArgb(229, 229, 229))) g.DrawEllipse(p, x - R, cy - R, 2 * R, 2 * R);
        int r = (hover || dragging) ? 7 : 6;
        using (Brush b = new SolidBrush(Accent)) g.FillEllipse(b, x - r, cy - r, 2 * r, 2 * r);
        TextFormatFlags f = TextFormatFlags.NoPadding | TextFormatFlags.VerticalCenter;
        using (Font bold = new Font(Font, FontStyle.Bold)) {
            TextRenderer.DrawText(g, Label, bold, new Rectangle(LabelX, 0, Width, LabelH), SystemColors.GrayText, f);
            int nx = LabelX + TextRenderer.MeasureText(g, Label, bold, Size.Empty, f).Width + 4;
            TextRenderer.DrawText(g, val.ToString(), bold, new Rectangle(nx, 0, Width, LabelH), ForeColor, f);
        }
    }

    protected override void OnMouseDown(MouseEventArgs e) {
        if (e.Button == MouseButtons.Left) { dragging = true; Capture = true; UserSet(ValueAt(e.X)); }
        base.OnMouseDown(e);
    }
    protected override void OnMouseMove(MouseEventArgs e) { if (dragging) UserSet(ValueAt(e.X)); base.OnMouseMove(e); }
    protected override void OnMouseUp(MouseEventArgs e) { dragging = false; Capture = false; Invalidate(); base.OnMouseUp(e); }
    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseWheel(MouseEventArgs e) { UserSet(val + (e.Delta > 0 ? 2 : -2)); base.OnMouseWheel(e); }
}

// Своё уведомление вместо ShowBalloonTip. Системное облачко подписано "Windows
// PowerShell" (процесс - powershell.exe), а со своим именем Windows не даёт ему
// иконку; тосты WinRT со своим AppUserModelID не показываются вовсе (проверено
// реестром, ярлыком с AUMID, ShowInActionCenter). Окно без активации и без
// кнопки на панели задач, над треем, закрывается само или по клику.
public class AqsToast : Form {
    static AqsToast current;
    Icon logo; string title, head, tail; bool dark; Font bold; Color accent;
    Timer timer = new Timer();
    const int Pad = 16, LogoSize = 32;
    const TextFormatFlags NoPad = TextFormatFlags.NoPadding;

    AqsToast(Icon logo, string title, string text, bool dark, Color accent) {
        this.logo = logo; this.title = title; this.dark = dark; this.accent = accent;
        // "Устройство: realme Buds Air8 Pro" - то, что после двоеточия, жирным и акцентным цветом
        int c = text.IndexOf(':');
        head = c < 0 ? text : text.Substring(0, c + 1);
        tail = c < 0 ? "" : text.Substring(c + 1);
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        // фон и текст - одним кадром (без отдельной заливки фона до OnPaint)
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);
        StartPosition = FormStartPosition.Manual;
        Font = SystemFonts.MessageBoxFont;
        bold = new Font(Font, FontStyle.Bold);
        BackColor = dark ? Color.FromArgb(32, 32, 32) : Color.FromArgb(249, 249, 249);
        int textW = Math.Max(TextRenderer.MeasureText(title, bold, Size.Empty, NoPad).Width,
                             TextRenderer.MeasureText(head, Font, Size.Empty, NoPad).Width + TextRenderer.MeasureText(tail, bold, Size.Empty, NoPad).Width);
        ClientSize = new Size(Pad + LogoSize + 12 + textW + Pad, 64);
        timer.Interval = 2000;
        timer.Tick += delegate { Close(); };
        Click += delegate { Close(); };
    }

    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x08000000 | 0x80 | 0x8;   // NOACTIVATE | TOOLWINDOW | TOPMOST
            cp.ClassStyle |= 0x20000;                // CS_DROPSHADOW
            return cp;
        }
    }
    protected override void OnHandleCreated(EventArgs e) {
        base.OnHandleCreated(e);
        int round = 2;   // DWMWCP_ROUND, только Windows 11
        try { DwmHelper.DwmSetWindowAttribute(Handle, 33, ref round, sizeof(int)); } catch { }
        DwmHelper.SetBorder(Handle, dark ? Color.FromArgb(50, 50, 50) : Color.FromArgb(220, 220, 220));
    }
    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        int cy = ClientSize.Height / 2;
        // DrawIcon, а не Icon.ToBitmap(): ToBitmap отдаёт на месте этой иконки шум
        if (logo != null) g.DrawIcon(logo, new Rectangle(Pad, cy - LogoSize / 2, LogoSize, LogoSize));
        int x = Pad + LogoSize + 12;
        TextRenderer.DrawText(g, title, bold, new Point(x, cy - 19), dark ? Color.White : Color.Black, NoPad);
        Color tc = dark ? Color.FromArgb(200, 200, 200) : Color.FromArgb(90, 90, 90);
        TextRenderer.DrawText(g, head, Font, new Point(x, cy + 1), tc, NoPad);
        int tx = x + TextRenderer.MeasureText(g, head, Font, Size.Empty, NoPad).Width;
        Win11Renderer.Glow(g, tail, bold, new Rectangle(new Point(tx, cy + 1), TextRenderer.MeasureText(g, tail, bold, Size.Empty, NoPad)), NoPad, accent);
        TextRenderer.DrawText(g, tail, bold, new Point(tx, cy + 1), accent, NoPad);
        using (Pen p = new Pen(dark ? Color.FromArgb(50, 50, 50) : Color.FromArgb(220, 220, 220)))
            g.DrawRectangle(p, 0, 0, ClientSize.Width - 1, ClientSize.Height - 1);
    }
    protected override void OnFormClosed(FormClosedEventArgs e) { timer.Dispose(); bold.Dispose(); base.OnFormClosed(e); }

    public static void Pop(Icon logo, string title, string text, bool dark, Color accent) {
        if (current != null && !current.IsDisposed) current.Close();
        current = new AqsToast(logo, title, text, dark, accent);
        Rectangle wa = Screen.PrimaryScreen.WorkingArea;
        current.Location = new Point(wa.Right - current.Width - 12, wa.Bottom - current.Height - 12);
        current.Show();
        // Рисуем сразу, а не когда дойдёт очередь сообщений: уведомление показывается
        // посреди переключения (дальше svcl и пересборка меню, ~0.3 с), и всё это
        // время плашка висела пустой - текст появлялся следом.
        current.Update();
        current.timer.Start();
    }
}
"@

# ---------- НАСТРОЙКИ ----------
# Править руками ничего не нужно: всё определяется относительно самого скрипта,
# поэтому папку установки можно выбрать любую.
$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$svcl        = Join-Path $scriptDir "svcl.exe"
$iconOnPath  = Join-Path $scriptDir "mic_icon_on.ico"
$iconOffPath = Join-Path $scriptDir "mic_icon_off.ico"

# Voicemeeter ищем сами: каталог установки и имя exe отличаются от машины к
# машине (Standard / Banana / Potato). Если его нет - не страшно, утилита
# работает и без него, просто не будет поднимать и гасить его при переключении.
$voicemeeterExe = $null
$voicemeeterProcessName = $null
$vmDir = $null
try {
    $vmDir = Get-ChildItem "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction Stop |
        ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
        Where-Object { $_.DisplayName -match "Voicemeeter" } |
        Select-Object -First 1 -ExpandProperty UninstallString
    if ($vmDir) { $vmDir = Split-Path -Parent ($vmDir -replace '^"|"$', '') }
} catch {}
if (-not $vmDir) { $vmDir = Join-Path ${env:ProgramFiles(x86)} "VB\Voicemeeter" }

foreach ($exe in "voicemeeter.exe", "voicemeeterpro.exe", "voicemeeter8.exe") {
    $candidate = Join-Path $vmDir $exe
    if (Test-Path $candidate) {
        $voicemeeterExe = $candidate
        $voicemeeterProcessName = [IO.Path]::GetFileNameWithoutExtension($exe)
        break
    }
}
# -------------------------------------------------------------

if (-not (Test-Path $svcl)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Рядом со скриптом нет svcl.exe.`n`nОжидался здесь:`n$svcl`n`nПереустанови AudioQuickSwitch - установщик докачивает svcl.exe с nirsoft.net сам.",
        "AudioQuickSwitch", "OK", "Error") | Out-Null
    exit
}

$stateFile = Join-Path $env:APPDATA "AudioQuickSwitch\state.json"
New-Item -ItemType Directory -Force -Path (Split-Path $stateFile) | Out-Null

function Get-State {
    if (Test-Path $stateFile) {
        try { return (Get-Content $stateFile -Raw | ConvertFrom-Json) } catch {}
    }
    return [PSCustomObject]@{ ListenOn = $false }
}
function Save-State($state) {
    $state | ConvertTo-Json | Set-Content -Path $stateFile -Encoding UTF8
}

$script:state = Get-State

# Мониторинг всегда выключаем на старте, безусловно.
# Флаг "Прослушивать с данного устройства" хранится в реестре Windows и
# переживает перезагрузку, а выключение при завершении процесса негарантированно:
# при shutdown/reboot Windows может убить процесс раньше, чем тот успеет
# запустить svcl, а при "Снять задачу" cleanup-код не выполняется вообще.
# Поэтому единственная надёжная точка - запуск: здесь состояние реальное
# железо и state.json приводятся к одному знаменателю.
& $svcl /SetListenToThisDevice DefaultCaptureDevice 0
$script:state.ListenOn = $false
Save-State $script:state

function Get-IsDarkTheme {
    try {
        $v = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -ErrorAction Stop
        return ($v -eq 0)
    } catch {
        return $false
    }
}

# Акцентный цвет Windows. Берём из палитры оттенков, как это делает сама система:
# в тёмной теме элементы заливаются светлым оттенком (Light2), в светлой - тёмным (Dark1).
# AccentPalette - 8 оттенков по 4 байта R,G,B,A: 0-2 светлые, 3 основной, 4-6 тёмные.
function Get-AccentColor($isDark) {
    try {
        $p = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent" -Name AccentPalette -ErrorAction Stop).AccentPalette
        $i = if ($isDark) { 1 } else { 4 }
        return [System.Drawing.Color]::FromArgb(255, $p[$i * 4], $p[$i * 4 + 1], $p[$i * 4 + 2])
    } catch {
        return [System.Drawing.Color]::FromArgb(255, 0, 120, 215)
    }
}

function Set-RoundedCorners($ctrl) {
    $ctrl.Add_HandleCreated({
        param($s, $e)
        try {
            $pref = 2  # DWMWCP_ROUND
            [DwmHelper]::DwmSetWindowAttribute($s.Handle, 33, [ref]$pref, 4) | Out-Null
        } catch {}
        [DwmHelper]::SetBorder($s.Handle, $script:menuBorder)   # цвет - из Set-MenuTheme
    })
}

function Set-MenuTheme($menu) {
    $isDark = Get-IsDarkTheme
    $script:menuDark = $isDark
    if ($isDark) {
        $bg     = [System.Drawing.Color]::FromArgb(255, 32, 32, 32)
        $hover  = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
        $border = [System.Drawing.Color]::FromArgb(255, 50, 50, 50)
        $fg     = [System.Drawing.Color]::White
    } else {
        $bg     = [System.Drawing.Color]::FromArgb(255, 249, 249, 249)
        $hover  = [System.Drawing.Color]::FromArgb(255, 229, 229, 229)
        $border = [System.Drawing.Color]::FromArgb(255, 220, 220, 220)
        $fg     = [System.Drawing.Color]::Black
    }
    $accent = Get-AccentColor $isDark
    $colorTable = New-Object Win11ColorTable($bg, $hover, $border)
    $menu.Renderer = New-Object Win11Renderer($colorTable)
    $menu.BackColor = $bg
    $script:menuBorder = $border   # рамка окна Windows 11 - тем же цветом (Set-RoundedCorners)
    if ($menu.IsHandleCreated) { [DwmHelper]::SetBorder($menu.Handle, $border) }
    $menu.ForeColor = $fg
    foreach ($it in $menu.Items) {
        if ($it -is [System.Windows.Forms.ToolStripMenuItem]) {
            # устройство вывода: текущее - акцентным цветом, остальные затенены (но кликабельны)
            $it.ForeColor = if ($it.Tag -isnot [array]) { $fg } elseif ($it.Tag[2]) { $accent } else { [System.Drawing.SystemColors]::GrayText }
        }
        if ($it.Control -is [AqsSlider]) {
            $s = $it.Control
            $s.BackColor = $bg; $s.ForeColor = $fg; $s.Dark = $isDark
            $s.Accent = $accent
        }
    }
    $menu.Glow = $accent
}

function New-MicIcon([System.Drawing.Color]$bg) {
    $bmp = New-Object System.Drawing.Bitmap(32,32)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    # цветной круглый фон
    $bgBrush = New-Object System.Drawing.SolidBrush($bg)
    $g.FillEllipse($bgBrush, 1, 1, 30, 30)

    # белый силуэт микрофона поверх фона
    $white = [System.Drawing.Color]::White
    $whiteBrush = New-Object System.Drawing.SolidBrush($white)
    $whitePen = New-Object System.Drawing.Pen($white, 2)
    $whitePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $whitePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round

    # капсула микрофона (скруглённый прямоугольник)
    $capX = 12; $capY = 6; $capW = 8; $capH = 12
    $g.FillEllipse($whiteBrush, $capX, $capY, $capW, $capW)
    $g.FillEllipse($whiteBrush, $capX, ($capY + $capH - $capW), $capW, $capW)
    $g.FillRectangle($whiteBrush, $capX, ($capY + $capW / 2), $capW, ($capH - $capW))

    # дуга-держатель под капсулой
    $g.DrawArc($whitePen, 8, 13, 16, 12, 20, 140)

    # ножка и подставка
    $g.DrawLine($whitePen, 16, 23, 16, 27)
    $g.DrawLine($whitePen, 11, 27, 21, 27)

    $g.Dispose()
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

if ((Test-Path $iconOnPath) -and (Test-Path $iconOffPath)) {
    $iconOn  = New-Object System.Drawing.Icon($iconOnPath)
    $iconOff = New-Object System.Drawing.Icon($iconOffPath)
} else {
    # запасной вариант, если .ico файлы не найдены рядом со скриптом
    $iconOn  = New-MicIcon ([System.Drawing.Color]::LimeGreen)
    $iconOff = New-MicIcon ([System.Drawing.Color]::Gray)
}

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Visible = $true

# Уведомления - своё окно AqsToast (почему не системные - см. комментарий у класса)
$toastLogo = $null
try { $toastLogo = New-Object System.Drawing.Icon((Join-Path $scriptDir "app_icon.ico"), 32, 32) } catch {}

function Show-Toast($text) {
    $dark = Get-IsDarkTheme
    try { [AqsToast]::Pop($toastLogo, "AudioQuickSwitch", $text, $dark, (Get-AccentColor $dark)) } catch {}   # уведомление - не повод ронять переключение
}

function Update-Icon {
    $notifyIcon.Icon = if ($script:state.ListenOn) { $iconOn } else { $iconOff }
    $status = if ($script:state.ListenOn) { "ВКЛ" } else { "ВЫКЛ" }
    $notifyIcon.Text = "Прослушивание: $status"
    if ($script:toggleItem) { $script:toggleItem.Text = "Мониторинг: $status" }
}

function Toggle-Listen {
    # С Voicemeeter мониторинг не включаем - выключить можно всегда.
    # ponytail: устройство берётся из последней сборки меню; если вывод переключили
    # мимо утилиты, блокировка заработает после следующего открытия меню.
    if (-not $script:state.ListenOn -and $script:defaultOutput -match "Voicemeeter") {
        Show-Toast "Мониторинг недоступен, пока вывод на Voicemeeter"
        return
    }
    $script:state.ListenOn = -not $script:state.ListenOn
    # Значок и пункт меню меняем ДО svcl: сам вызов стоит ~180 мс, и раньше значок
    # переключался с этой задержкой. Пересобирать всё меню (~200 мс, svcl /sjson)
    # ради одной надписи тоже незачем - Update-Icon правит её сам.
    Update-Icon
    $val = if ($script:state.ListenOn) { 1 } else { 0 }
    & $svcl /SetListenToThisDevice DefaultCaptureDevice $val
    Save-State $script:state
    # уведомления нет: состояние и так видно по значку
}

function Disable-Listening-Silently {
    try {
        if ($script:state.ListenOn) {
            & $svcl /SetListenToThisDevice DefaultCaptureDevice 0
            $script:state.ListenOn = $false
            Save-State $script:state
        }
    } catch {}
}

# Гарантируем выключение мониторинга при любом штатном завершении процесса:
# обычный выход, закрытие сессии, выход из Windows / перезагрузка.
# Насильственное завершение через "Снять задачу" в диспетчере задач перехватить нельзя -
# это ограничение Windows, а не скрипта: forced kill не даёт процессу время на очистку.
[System.AppDomain]::CurrentDomain.add_ProcessExit({ Disable-Listening-Silently })
[Microsoft.Win32.SystemEvents]::add_SessionEnding({ Disable-Listening-Silently })

# Поднимает Voicemeeter, если он не запущен. Возвращает $true, если пришлось запускать.
# Запускаем свёрнутым: если в самом Voicemeeter включён режим System Tray, он уходит
# сразу в трей, а не выскакивает окном.
function Start-Voicemeeter {
    if (-not $voicemeeterExe -or -not (Test-Path $voicemeeterExe)) {
        Show-Toast "Voicemeeter не найден на этом компьютере"
        return $false
    }
    if (Get-Process -Name $voicemeeterProcessName -ErrorAction SilentlyContinue) { return $false }
    [DwmHelper]::StartNoFeedback("`"$voicemeeterExe`"", 2)   # 2 = SW_SHOWMINIMIZED
    return $true
}

function Set-OutputDevice($deviceId, $deviceName, $isBT) {
    # Сразу, а не при пересборке меню: по нему Toggle-Listen запрещает мониторинг
    # с Voicemeeter, а клик по значку сразу после выбора Voicemeeter (пока тот
    # запускается) иначе видел старое устройство и мониторинг включался.
    $script:defaultOutput = $deviceName
    # История выбранных устройств, свежее первым: куда вернуть звук, если текущее
    # отключится. Только наши переключения - не то, что подставила Windows. В
    # state.json, чтобы пережила перезапуск.
    $script:state | Add-Member -Force NoteProperty Recent @((@($deviceId) + @($script:state.Recent | Where-Object { $_ -and $_ -ne $deviceId })) | Select-Object -First 10)
    Save-State $script:state

    # Громкость общая на все устройства: новое получает уровень текущего. Windows
    # держит у каждого устройства свою, и ползунок "прыгал" при переключении.
    # Кроме беспроводных: у наушников своя громкость - с них и на них не переносим.
    # Читаем до переключения: после него прочиталась бы громкость уже нового.
    $vol = $null
    if (-not $isBT -and -not $script:defaultBT) { try { $vol = [AqsVolume]::Get() } catch {} }

    if ($deviceName -match "Voicemeeter") {
        Disable-Listening-Silently; Update-Icon   # с Voicemeeter мониторинг запрещён
        # даём Voicemeeter время создать свои аудио-эндпоинты перед переключением
        if (Start-Voicemeeter) { Start-Sleep -Milliseconds 1500 }
    }   # уход с Voicemeeter гасит его обработчик AqsDeviceWatch.Changed

    # Ждать подтверждения не нужно: замерено, что первый же /sjson после
    # /SetDefault уже отдаёт новое устройство. Прежний поллинг только добавлял
    # лишнюю секунду на каждое переключение.
    & $svcl /SetDefault $deviceId all
    if ($null -ne $vol) { try { [AqsVolume]::Set($vol) } catch {} }
    Show-Toast "Устройство: $deviceName"
    # меню пересоберётся само после клика (отложенный Closed в Refresh-Menu)
}

# Собирает пункты во временное меню - Refresh-Menu переносит их в постоянное.
function Build-Menu {
    $menu = New-Object System.Windows.Forms.ContextMenuStrip

    $tmp = Join-Path $env:TEMP "aqs_devices_$PID.json"   # свой на процесс: два экземпляра не пишут в один файл
    Remove-Item $tmp -ErrorAction SilentlyContinue


    try {
        # Прямой вызов, а НЕ Start-Process -Wait: замерено 156мс против 1023мс.
        # Вся задержка открытия меню сидела в Start-Process, а не в svcl.exe.
        & $svcl /sjson $tmp

        if (-not (Test-Path $tmp)) {
            throw "svcl.exe не создал файл экспорта (код завершения: $LASTEXITCODE). Проверь путь к svcl.exe и что /sjson поддерживается твоей версией (запусти вручную: `"$svcl`" /? и поищи /sjson в списке команд)."
        }

        $raw = Get-Content $tmp -Raw
        # PowerShell 5.1: ConvertFrom-Json падает, если в JSON встречается пустой ключ "" - чиним это заранее
        $raw = $raw -replace '""\s*:', '"_empty":'
        if ([string]::IsNullOrWhiteSpace($raw)) {
            throw "Файл экспорта пустой."
        }

        $devices = $raw | ConvertFrom-Json
        $playback = $devices | Where-Object { $_.Type -eq "Device" -and $_.Direction -eq "Render" }

        if (-not $playback -or $playback.Count -eq 0) {
            throw "JSON распарсился, но устройств вывода (Type=Device, Direction=Render) не найдено. Возможно, названия полей в твоей версии svcl.exe другие. Первые 300 символов сырого файла: $($raw.Substring(0, [Math]::Min(300, $raw.Length)))"
        }

        $devItems = foreach ($d in $playback) {
            # Беспроводные (Bluetooth: путь устройства {1}.BTHENUM / BTHLE...) подписываем
            # моделью из скобок Windows ("realme Buds Air8 Pro") - своё имя у них безликое
            # ("Наушники") и совпадает с проводными. Остальные - своим именем.
            # Переключаем по Item ID - он уникален (по имени svcl взял бы первое попавшееся).
            $props = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render\$($d.'Item ID' -replace '^.*\}\.', '')\Properties"
            $devPath = (Get-ItemProperty $props -ErrorAction SilentlyContinue).'{b3f8fa53-0004-438e-9003-51a46e139bfc},2'
            $model = ("$($d.'Device Name')" -replace '\s+', ' ').Trim()
            $isBT = $devPath -match '^\{1\}\.BTH'
            $label = if ($isBT -and $model) { $model } else { $d.Name }
            $isDefault = ($d.Default -eq "Render")
            if ($isDefault) {
                $script:defaultOutput = $label; $script:defaultBT = $isBT; $script:defaultId = $d.'Item ID'
            }
            # узел Hands-Free той же гарнитуры (для заряда): тот же путь, служба 0000111E вместо аудио
            $hf = if ($devPath -match '^\{1\}\.BTHENUM') { ($devPath -replace '^\{1\}\.', '') -replace '^BTHENUM\\{[0-9A-Fa-f-]+\}', 'BTHENUM\{0000111E-0000-1000-8000-00805F9B34FB}' }
            $item = New-Object System.Windows.Forms.ToolStripMenuItem($label)
            if ($isDefault) { $item.Font = New-Object System.Drawing.Font($menu.Font, [System.Drawing.FontStyle]::Bold) }
            $item.Padding = New-Object System.Windows.Forms.Padding(4, 0, 2, 0)
            $item.Tag = @($d.'Item ID', $label, $isDefault, $hf, -1, $isBT)   # цвет по $isDefault - в Set-MenuTheme; [4] - заряд
            $item.Add_Click({ param($s,$e) Set-OutputDevice $s.Tag[0] $s.Tag[1] $s.Tag[5] })
            $item
        }
        # порядок, расставленный перетаскиванием (Item ID в state.json); новые - в конце,
        # по алфавиту: сначала латинские названия, потом кириллические
        $order = @($script:state.Order)
        $devItems | Sort-Object { $i = [array]::IndexOf($order, $_.Tag[0]); if ($i -lt 0) { $order.Count } else { $i } },
            { $_.Tag[1] -notmatch '^[A-Za-z]' }, { $_.Tag[1] } | ForEach-Object { $menu.Items.Add($_) | Out-Null }
    } catch {
        # Показываем реальную причину прямо в меню, чтобы было видно на скриншоте
        $msg = "[$($_.Exception.GetType().Name), строка $($_.InvocationInfo.ScriptLineNumber)] $($_.Exception.Message)"
        $chunks = [regex]::Matches($msg, ".{1,60}")
        foreach ($c in $chunks) {
            $errItem = New-Object System.Windows.Forms.ToolStripMenuItem($c.Value)
            $errItem.Enabled = $false
            $menu.Items.Add($errItem) | Out-Null
        }
    }

    $menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

    # Громкость устройства по умолчанию - ползунок прямо в меню. Через Core Audio
    # (класс AqsVolume выше), а не svcl.exe: ~2 мс на изменение против ~150 мс на
    # запуск процесса, иначе ползунок дёргался бы при перетаскивании.
    try {
        $vol = [AqsVolume]::Get()
        $track = New-Object AqsSlider
        $track.Size = New-Object System.Drawing.Size(100, 50)   # ширину ставит Update-MenuBattery
        $track.Value = $vol
        $menu.Items.Add((New-Object System.Windows.Forms.ToolStripControlHost($track))) | Out-Null

        $menu.Tag = $track   # для Opening постоянного меню

        $menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
    } catch {}   # нет устройства вывода - просто без ползунка

    $toggle = New-Object System.Windows.Forms.ToolStripMenuItem   # надпись ставит Update-Icon
    $toggle.Tag = "boldTail"   # ВКЛ/ВЫКЛ жирным - Win11Renderer; по нему же его находит Refresh-Menu
    $toggle.Enabled = $script:state.ListenOn -or $script:defaultOutput -notmatch "Voicemeeter"
    $toggle.Add_Click({ Toggle-Listen })
    $menu.Items.Add($toggle) | Out-Null

    # Штатный список устройств Windows (mmsys.cpl, вкладка "Воспроизведение") -
    # в Windows 11 он спрятан глубоко в параметрах, отсюда до него один клик.
    $panelItem = New-Object System.Windows.Forms.ToolStripMenuItem("Настройки звука Windows")
    # сразу rundll32, а не control.exe: тот запускает его сам и снова включил бы колёсико
    $panelItem.Add_Click({ [DwmHelper]::StartNoFeedback("rundll32.exe shell32.dll,Control_RunDLL mmsys.cpl,,0", 1) })
    $menu.Items.Add($panelItem) | Out-Null

    $exitItem = New-Object System.Windows.Forms.ToolStripMenuItem("Выход")
    $exitItem.Add_Click({
        Disable-Listening-Silently
        $notifyIcon.Visible = $false
        [System.Windows.Forms.Application]::Exit()
    })
    $menu.Items.Add($exitItem) | Out-Null
    return $menu
}

# Перед каждым показом (меню собрано заранее, цифры устарели бы): заряд беспроводных
# (~5 мс) и ширина меню - самый длинный текст (у беспроводных вместе с "● 90") и
# справа тот же отступ, что слева (12 px). Ширину считаем сами и фиксируем
# (AutoSize off): WinForms прибавлял запас под стрелку подменю, а подменю у нас
# нет. Ползунок растягиваем на эту ширину.
function Update-MenuBattery($menu) {
    $w = 0; $vh = $null
    foreach ($i in $menu.Items) {
        if ($i -is [System.Windows.Forms.ToolStripControlHost]) { $vh = $i; continue }
        if ($i -isnot [System.Windows.Forms.ToolStripMenuItem]) { continue }
        if ($i.Tag -is [array] -and $i.Tag[3]) { $i.Tag[4] = [AqsBattery]::Get($i.Tag[3]) }
        $lvl = if ($i.Tag -is [array]) { $i.Tag[4] } else { -1 }
        $w = [Math]::Max($w, [Win11Renderer]::ContentWidth($i.Text, $i.Font, $lvl))
    }
    $menu.Width = 12 + $w + 12
    if ($vh) { $vh.Control.Width = $menu.Width - 2 * $vh.Bounds.X }
}

# Меню собирается ЗАРАНЕЕ, а не по правому клику. Сборка стоит ~180мс (запуск
# svcl /sjson), и раньше эти 180мс висели ровно между нажатием кнопки и
# появлением меню - именно это и ощущалось как задержка. Теперь клик показывает
# уже готовое меню, а пересборка идёт после его закрытия, когда её не видно.
# Меню одно на всё время работы: пересборка собирает пункты заново (Build-Menu) и
# переносит их в него - так же и в открытое меню, если устройства сменились, пока
# оно на экране (вместе с пунктами переезжают $script:toggleItem и ползунок).
$script:menu = New-Object AqsMenu
$script:menu.ShowImageMargin = $false
$script:menu.Padding = New-Object System.Windows.Forms.Padding(1)
$script:menu.AutoSize = $false   # ширину ставит Update-MenuBattery, высоту - Refresh-Menu
Set-RoundedCorners $script:menu
# internal-свойство; почему выключено - см. показ меню по правому клику
$script:menu.GetType().GetProperty('WorkingAreaConstrained', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($script:menu, $false)
# При клике по пункту WinForms сначала закрывает меню (Closed), и только потом
# вызывает Click. Синхронная пересборка тут (~200 мс) задерживала сам клик:
# мониторинг выключался через ~420 мс. BeginInvoke откладывает её до конца клика.
$script:menu.Add_Closed({ param($s) $s.BeginInvoke([Action]{ Refresh-Menu }) | Out-Null })
$script:menu.Add_Opening({ param($s, $e)
    # тему Windows могли переключить после сборки - перекрашиваем (без svcl, пара мс);
    # громкость могли поменять клавишами или в другом приложении
    if ((Get-IsDarkTheme) -ne $script:menuDark) { Set-MenuTheme $s }
    try { $s.Tag.Value = [AqsVolume]::Get() } catch {}
})
# сейчас не подключённые устройства сохраняют место в списке - в его конце
$script:menu.Add_Reordered({ param($s)
    $ids = @($s.Items | Where-Object { $_.Tag -is [array] } | ForEach-Object { $_.Tag[0] })
    $script:state | Add-Member -Force NoteProperty Order @($ids + @($script:state.Order | Where-Object { $_ -and $ids -notcontains $_ }))
    Save-State $script:state
})

function Refresh-Menu {
    $m = $script:menu
    $bottom = $m.Bottom
    $wasDefault = $script:defaultId
    $new = Build-Menu
    # Открытое меню с теми же устройствами и тем же выбранным (уведомление о нашем же
    # переключении и т.п.) не трогаем: замена пунктов пересоздаёт окно ползунка, и
    # меню заметно моргало.
    $ids = @($new.Items | Where-Object { $_.Tag -is [array] } | ForEach-Object { $_.Tag[0] })
    if ($m.Visible -and "$ids" -eq "$script:devIds" -and $script:defaultId -eq $wasDefault) { $new.Dispose(); return }
    $script:devIds = $ids
    $old = @($m.Items)
    $m.SuspendLayout()
    $m.Items.Clear()
    foreach ($i in @($new.Items)) { $m.Items.Add($i) | Out-Null }
    $m.ResumeLayout()
    $old | ForEach-Object { $_.Dispose() }   # у ползунка своё окно - не копим
    $m.Tag = $new.Tag
    # -is [string]: у устройств Tag - массив с $true, а $true -eq "boldTail" в PowerShell истина
    $script:toggleItem = $m.Items | Where-Object { $_.Tag -is [string] -and $_.Tag -eq "boldTail" }
    Update-Icon   # надпись "Мониторинг: ..." (заодно переставляет тот же значок)
    $new.Dispose()
    Set-MenuTheme $m
    Update-MenuBattery $m
    $m.Height = $m.GetPreferredSize([System.Drawing.Size]::Empty).Height
    if ($m.Visible) { $m.Top = $bottom - $m.Height }   # низ - у панели задач
}

Refresh-Menu

# Если ПК выключили, оставив устройством вывода Voicemeeter, после загрузки звук
# уходит в его виртуальный вход, а сам Voicemeeter никто не запустил - тишина.
# Build-Menu уже узнал текущее устройство, поднимаем Voicemeeter сразу.
if ($script:defaultOutput -match "Voicemeeter") { Start-Voicemeeter | Out-Null }

# Устройство подключили/отключили или сменили мимо утилиты - пересобираем меню сразу,
# а не при следующем закрытии (иначе свежеподключённых Bluetooth-наушников в нём не
# было), в том числе открытое; пока в нём перетаскивают пункт - не трогаем,
# пересоберётся при закрытии.
[AqsDeviceWatch]::add_Changed({
    $known = $script:devIds; $wasDefault = $script:defaultId
    if (-not $script:menu.Dragging) { Refresh-Menu }
    $devs = @($script:menu.Items | Where-Object { $_.Tag -is [array] })
    # Подключились беспроводные наушники - звук на них. Windows сама переводит, только
    # если они и были устройством по умолчанию до отключения (а не, скажем, Voicemeeter).
    $to = $devs | Where-Object { $_.Tag[5] -and $known -notcontains $_.Tag[0] } | Select-Object -First 1
    # Отключилось устройство, на котором был звук: Windows подставляет что попало (часто
    # Voicemeeter Input без запущенного Voicemeeter - тишина). Возвращаем на последнее
    # выбранное из подключённых, Voicemeeter тоже (Set-OutputDevice его запустит);
    # истории нет - на первое не-Voicemeeter в меню.
    $vanished = $wasDefault -and $script:devIds -notcontains $wasDefault
    if (-not $to -and $vanished) {
        $to = @(foreach ($id in @($script:state.Recent)) { $devs | Where-Object { $_.Tag[0] -eq $id } }) +
              @($devs | Where-Object { $_.Tag[1] -notmatch "Voicemeeter" }) | Select-Object -First 1
    }
    # и сразу пересобираем: меню одним кадром покажет итог, без промежуточного выбора Windows
    if ($to -and -not $to.Tag[2]) { Set-OutputDevice $to.Tag[0] $to.Tag[1] $to.Tag[5]; Refresh-Menu }   # уведомление - там
    # Windows сама выбрала то же (переключила на наушники / с отключённого) - всё равно сообщаем
    elseif ($to -or $vanished) { Show-Toast "Устройство: $script:defaultOutput" }
    # Вывод ушёл с Voicemeeter - гасим его. Единственное место: переключение из меню
    # тоже приходит сюда уведомлением, а мимо утилиты Windows сама переключается,
    # например, на только что подключённые наушники.
    if ($voicemeeterProcessName -and $script:defaultOutput -notmatch "Voicemeeter") {
        Get-Process -Name $voicemeeterProcessName -ErrorAction SilentlyContinue | Stop-Process -Force
    }
})
[AqsDeviceWatch]::Start()

$notifyIcon.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        Toggle-Listen
    }
})

# Меню показываем сами, а не через NotifyIcon.ContextMenuStrip: тот ставит низ меню
# на точку клика (внутрь панели задач) и ограничивает его экраном, а не рабочей
# областью - меню заходило на панель на 28 px и пряталось под ней. Обычный Show
# ограничивает рабочей областью (WorkingAreaConstrained) ещё до показа, без
# мерцания, и сам учитывает высоту панели, в том числе компактной.
# SetForegroundWindow на скрытое окно значка - так же делает сам NotifyIcon,
# иначе меню не закрывается кликом мимо.
$trayWindow = $notifyIcon.GetType().GetField('window', [Reflection.BindingFlags]'NonPublic,Instance').GetValue($notifyIcon)
$trayIconId = $notifyIcon.GetType().GetField('id', [Reflection.BindingFlags]'NonPublic,Instance').GetValue($notifyIcon)
$notifyIcon.Add_MouseUp({
    param($s, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Right) { return }
    [DwmHelper]::SetForegroundWindow($trayWindow.Handle) | Out-Null
    Update-MenuBattery $script:menu   # до расчёта позиции: ширина зависит от заряда
    # как у других значков трея (Telegram и т.п.): левый край - по левому краю
    # значка, низ - на 1 px ниже рабочей области: поверх светлой линии по верхнему
    # краю панели задач. Иначе она шла вплотную к светлой рамке меню и выглядела
    # щелью в 1 px. Поэтому WorkingAreaConstrained выключен (иначе WinForms
    # вернёт меню выше), а правый край экрана проверяем сами.
    $c  = [System.Windows.Forms.Cursor]::Position
    $wa = [System.Windows.Forms.Screen]::FromPoint($c).WorkingArea
    $x  = [DwmHelper]::TrayIconLeft($trayWindow.Handle, $trayIconId)
    if ($x -lt 0) { $x = $c.X }   # не вышло узнать значок - по курсору
    $x  = [Math]::Max($wa.Left, [Math]::Min($x, $wa.Right - $script:menu.Width))
    $y  = if ($c.Y -ge $wa.Bottom) { $wa.Bottom + 1 } else { $c.Y }   # панель не снизу (автоскрытие) - по курсору
    $script:menu.Show((New-Object System.Drawing.Point($x, $y)), [System.Windows.Forms.ToolStripDropDownDirection]::AboveRight)
})

Update-Icon

# При входе в Windows утилита может стартовать раньше, чем панель задач готова принять
# значок: Shell_NotifyIcon не срабатывает, а WinForms всё равно считает значок
# добавленным и больше не пробует - процесс жив, значка нет. Первую минуту проверяем,
# что значок на месте, и если нет - добавляем заново (с записью в tray.log).
$trayCheck = New-Object System.Windows.Forms.Timer
$trayCheck.Interval = 2000
$script:trayChecks = 0
$trayCheck.Add_Tick({
    if ([DwmHelper]::TrayIconLeft($trayWindow.Handle, $trayIconId) -lt 0) {
        $notifyIcon.Visible = $false; $notifyIcon.Visible = $true
        Add-Content (Join-Path (Split-Path $stateFile) "tray.log") "$(Get-Date -Format s) значка нет - добавлен заново"
    }
    if (++$script:trayChecks -ge 30) { $trayCheck.Stop() }
})
$trayCheck.Start()

[System.Windows.Forms.Application]::Run()
