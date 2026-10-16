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
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hwnd);
}

// Подсветку пункта рисуем сами. Штатная: без EnableVisualStyles (PowerShell его не
// зовёт) берёт системный светло-голубой вместо цветов таблицы - белый текст на нём
// не читается; прямоугольник до самых краёв давал острые углы у скруглённого меню;
// неактивные заголовки обводила рамкой. Здесь - как в Windows 11: скруглённая
// плашка с отступом от краёв, у неактивных пунктов ничего.
public class Win11Renderer : ToolStripProfessionalRenderer {
    public Win11Renderer(ProfessionalColorTable t) : base(t) { }
    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e) {
        if (!e.Item.Enabled || !e.Item.Selected) return;
        Rectangle r = new Rectangle(4, 1, e.Item.Width - 8, e.Item.Height - 2);
        const int d = 8;   // диаметр скругления
        using (System.Drawing.Drawing2D.GraphicsPath p = new System.Drawing.Drawing2D.GraphicsPath())
        using (Brush b = new SolidBrush(ColorTable.MenuItemSelected)) {
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            e.Graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            e.Graphics.FillPath(b, p);
        }
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
}

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
public class AqsMMDeviceEnumerator { }

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
    const int NumW = 30;   // место справа под число процентов

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

    int X0 { get { return R + 2; } }
    int X1 { get { return Width - R - 2 - NumW; } }
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
        int cy = Height / 2, x = XOf(val);
        using (Pen p = RoundPen(Dark ? Color.FromArgb(153, 153, 153) : Color.FromArgb(138, 138, 138))) g.DrawLine(p, X0, cy, X1, cy);
        using (Pen p = RoundPen(Accent)) g.DrawLine(p, X0, cy, x, cy);
        using (Brush b = new SolidBrush(Dark ? Color.FromArgb(69, 69, 69) : Color.White)) g.FillEllipse(b, x - R, cy - R, 2 * R, 2 * R);
        using (Pen p = new Pen(Dark ? Color.FromArgb(84, 84, 84) : Color.FromArgb(229, 229, 229))) g.DrawEllipse(p, x - R, cy - R, 2 * R, 2 * R);
        int r = (hover || dragging) ? 7 : 6;
        using (Brush b = new SolidBrush(Accent)) g.FillEllipse(b, x - r, cy - r, 2 * r, 2 * r);
        // число рисуем сами: подпись-пункт меню при каждом изменении заставляла
        // всё меню пересчитывать раскладку
        TextRenderer.DrawText(g, val.ToString(), Font, new Rectangle(Width - NumW, 0, NumW, Height),
                              ForeColor, TextFormatFlags.Right | TextFormatFlags.VerticalCenter);
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
    Icon logo; string title, text; bool dark;
    Timer timer = new Timer();
    const int Pad = 16, LogoSize = 32;

    AqsToast(Icon logo, string title, string text, bool dark) {
        this.logo = logo; this.title = title; this.text = text; this.dark = dark;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        Font = SystemFonts.MessageBoxFont;
        BackColor = dark ? Color.FromArgb(32, 32, 32) : Color.FromArgb(249, 249, 249);
        int textW = Math.Max(TextRenderer.MeasureText(title, new Font(Font, FontStyle.Bold)).Width,
                             TextRenderer.MeasureText(text, Font).Width);
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
    }
    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        int cy = ClientSize.Height / 2;
        // DrawIcon, а не Icon.ToBitmap(): ToBitmap отдаёт на месте этой иконки шум
        if (logo != null) g.DrawIcon(logo, new Rectangle(Pad, cy - LogoSize / 2, LogoSize, LogoSize));
        int x = Pad + LogoSize + 12;
        using (Font bold = new Font(Font, FontStyle.Bold))
            TextRenderer.DrawText(g, title, bold, new Point(x, cy - 19), dark ? Color.White : Color.Black);
        TextRenderer.DrawText(g, text, Font, new Point(x, cy + 1), dark ? Color.FromArgb(200, 200, 200) : Color.FromArgb(90, 90, 90));
        using (Pen p = new Pen(dark ? Color.FromArgb(50, 50, 50) : Color.FromArgb(220, 220, 220)))
            g.DrawRectangle(p, 0, 0, ClientSize.Width - 1, ClientSize.Height - 1);
    }
    protected override void OnFormClosed(FormClosedEventArgs e) { timer.Dispose(); base.OnFormClosed(e); }

    public static void Pop(Icon logo, string title, string text, bool dark) {
        if (current != null && !current.IsDisposed) current.Close();
        current = new AqsToast(logo, title, text, dark);
        Rectangle wa = Screen.PrimaryScreen.WorkingArea;
        current.Location = new Point(wa.Right - current.Width - 12, wa.Bottom - current.Height - 12);
        current.Show();
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
    })
}

function Set-MenuTheme($menu) {
    $isDark = Get-IsDarkTheme
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
    $colorTable = New-Object Win11ColorTable($bg, $hover, $border)
    $menu.Renderer = New-Object Win11Renderer($colorTable)
    $menu.BackColor = $bg
    $menu.ForeColor = $fg
    foreach ($it in $menu.Items) {
        if ($it -is [System.Windows.Forms.ToolStripMenuItem]) { $it.ForeColor = $fg }
        if ($it.Control -is [AqsSlider]) {
            $s = $it.Control
            $s.BackColor = $bg; $s.ForeColor = $fg; $s.Dark = $isDark
            $s.Accent = Get-AccentColor $isDark
        }
    }
    Set-RoundedCorners $menu
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
    try { [AqsToast]::Pop($toastLogo, "AudioQuickSwitch", $text, (Get-IsDarkTheme)) } catch {}   # уведомление - не повод ронять переключение
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
    $status = if ($script:state.ListenOn) { "ВКЛ" } else { "ВЫКЛ" }
    Show-Toast "Мониторинг микрофона: $status"
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
    Start-Process -FilePath $voicemeeterExe -WindowStyle Minimized
    return $true
}

function Set-OutputDevice($deviceName) {
    # Громкость общая на все устройства: новое получает уровень текущего. Windows
    # держит у каждого устройства свою, и ползунок "прыгал" при переключении.
    # Читаем до всего остального: если ниже гасится Voicemeeter, Windows сама
    # перекидывает вывод на железо, и прочиталась бы громкость чужого устройства.
    $vol = $null
    try { $vol = [AqsVolume]::Get() } catch {}

    if ($deviceName -match "Voicemeeter") {
        Disable-Listening-Silently; Update-Icon   # с Voicemeeter мониторинг запрещён
        # даём Voicemeeter время создать свои аудио-эндпоинты перед переключением
        if (Start-Voicemeeter) { Start-Sleep -Milliseconds 1500 }
    } elseif ($voicemeeterProcessName) {
        # $voicemeeterProcessName пуст, если Voicemeeter на этой машине не установлен
        Get-Process -Name $voicemeeterProcessName -ErrorAction SilentlyContinue | Stop-Process -Force
    }

    # Ждать подтверждения не нужно: замерено, что первый же /sjson после
    # /SetDefault уже отдаёт новое устройство. Прежний поллинг только добавлял
    # лишнюю секунду на каждое переключение.
    & $svcl /SetDefault $deviceName all
    if ($null -ne $vol) { try { [AqsVolume]::Set($vol) } catch {} }
    Show-Toast "Устройство: $deviceName"
    # меню пересоберётся само после клика (отложенный Closed в Refresh-Menu)
}

function Build-Menu {
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $menu.ShowImageMargin = $false
    $menu.AutoSize = $true
    $menu.Padding = New-Object System.Windows.Forms.Padding(1)

    $tmp = Join-Path $env:TEMP "aqs_devices.json"
    Remove-Item $tmp -ErrorAction SilentlyContinue

    $header = New-Object System.Windows.Forms.ToolStripMenuItem("Устройства вывода:")
    $header.Enabled = $false
    $menu.Items.Add($header) | Out-Null
    $menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

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

        foreach ($d in $playback) {
            $isDefault = ($d.Default -eq "Render")
            if ($isDefault) { $script:defaultOutput = $d.Name }
            $mark = if ($isDefault) { "`t  ✔" } else { "" }
            $item = New-Object System.Windows.Forms.ToolStripMenuItem("$($d.Name)$mark")
            $item.Padding = New-Object System.Windows.Forms.Padding(4, 0, 2, 0)
            $item.Tag = $d.Name
            $item.Add_Click({ param($s,$e) Set-OutputDevice $s.Tag })
            $menu.Items.Add($item) | Out-Null
        }
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
        $volLabel = New-Object System.Windows.Forms.ToolStripMenuItem("Громкость")
        $volLabel.Enabled = $false
        $menu.Items.Add($volLabel) | Out-Null

        $track = New-Object AqsSlider
        $track.Size = New-Object System.Drawing.Size(200, 28)
        $track.Value = $vol
        $menu.Items.Add((New-Object System.Windows.Forms.ToolStripControlHost($track))) | Out-Null

        # меню собрано заранее - в момент открытия подтягиваем фактическую громкость
        # (её могли поменять клавишами или в другом приложении)
        $menu.Tag = $track
        $menu.Add_Opening({ param($s, $e) try { $s.Tag.Value = [AqsVolume]::Get() } catch {} })

        $menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
    } catch {}   # нет устройства вывода - просто без ползунка

    $script:toggleItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $script:toggleItem.Enabled = $script:state.ListenOn -or $script:defaultOutput -notmatch "Voicemeeter"
    $script:toggleItem.Add_Click({ Toggle-Listen })
    $menu.Items.Add($script:toggleItem) | Out-Null
    Update-Icon   # надпись "Мониторинг: ..." ставит она же (заодно переставляет тот же значок)

    # Штатный список устройств Windows (mmsys.cpl, вкладка "Воспроизведение") -
    # в Windows 11 он спрятан глубоко в параметрах, отсюда до него один клик.
    $panelItem = New-Object System.Windows.Forms.ToolStripMenuItem("Настройки звука Windows")
    $panelItem.Add_Click({ Start-Process "control.exe" -ArgumentList "mmsys.cpl,,0" })
    $menu.Items.Add($panelItem) | Out-Null

    $exitItem = New-Object System.Windows.Forms.ToolStripMenuItem("Выход")
    $exitItem.Add_Click({
        Disable-Listening-Silently
        $notifyIcon.Visible = $false
        [System.Windows.Forms.Application]::Exit()
    })
    $menu.Items.Add($exitItem) | Out-Null

    Set-MenuTheme $menu

    return $menu
}

# Меню собирается ЗАРАНЕЕ, а не по правому клику. Сборка стоит ~180мс (запуск
# svcl /sjson), и раньше эти 180мс висели ровно между нажатием кнопки и
# появлением меню - именно это и ощущалось как задержка. Теперь клик показывает
# уже готовое меню, а пересборка идёт после его закрытия, когда её не видно.
function Refresh-Menu {
    # Старое меню намеренно не освобождаем: Refresh-Menu вызывается в том числе
    # из события Closed, когда прежнее меню ещё закрывается, и Dispose() на нём
    # роняет приложение. Так же вело себя и прежнее пересоздание по клику.
    $menu = Build-Menu
    # При клике по пункту WinForms сначала закрывает меню (Closed), и только потом
    # вызывает Click. Синхронная пересборка тут (~200 мс) задерживала сам клик:
    # мониторинг выключался через ~420 мс. BeginInvoke откладывает её до конца клика -
    # заодно галочка устройства гарантированно ставится уже после переключения.
    $menu.Add_Closed({ param($s) $s.BeginInvoke([Action]{ Refresh-Menu }) | Out-Null })
    $script:menu = $menu
}

Refresh-Menu

# Если ПК выключили, оставив устройством вывода Voicemeeter, после загрузки звук
# уходит в его виртуальный вход, а сам Voicemeeter никто не запустил - тишина.
# Build-Menu уже узнал текущее устройство, поднимаем Voicemeeter сразу.
if ($script:defaultOutput -match "Voicemeeter") { Start-Voicemeeter | Out-Null }

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
$notifyIcon.Add_MouseUp({
    param($s, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Right) { return }
    [DwmHelper]::SetForegroundWindow($trayWindow.Handle) | Out-Null
    $script:menu.Show([System.Windows.Forms.Cursor]::Position, [System.Windows.Forms.ToolStripDropDownDirection]::AboveLeft)
})

Update-Icon
[System.Windows.Forms.Application]::Run()
