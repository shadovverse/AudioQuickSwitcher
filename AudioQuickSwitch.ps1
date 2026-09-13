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
"@

# ---------- НАСТРОЙКИ: укажи свой путь к svcl.exe ----------
$svcl = "B:\Утилиты\sound_script\svcl.exe"
$voicemeeterExe = "C:\Program Files (x86)\VB\Voicemeeter\voicemeeter.exe"
$voicemeeterProcessName = "voicemeeter"
# -------------------------------------------------------------

# Иконки лежат рядом со скриптом (mic_on_icon.ico / mic_off_icon.ico)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$iconOnPath  = Join-Path $scriptDir "mic_icon_on.ico"
$iconOffPath = Join-Path $scriptDir "mic_icon_off.ico"

if (-not (Test-Path $svcl)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Не найден $svcl`n`nСкачай SoundVolumeCommandLine (svcl.exe) с nirsoft.net и укажи правильный путь в начале скрипта.",
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
    $menu.Renderer = New-Object System.Windows.Forms.ToolStripProfessionalRenderer($colorTable)
    $menu.BackColor = $bg
    $menu.ForeColor = $fg
    foreach ($it in $menu.Items) {
        if ($it -is [System.Windows.Forms.ToolStripMenuItem]) { $it.ForeColor = $fg }
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

function Update-Icon {
    $notifyIcon.Icon = if ($script:state.ListenOn) { $iconOn } else { $iconOff }
    $status = if ($script:state.ListenOn) { "ВКЛ" } else { "ВЫКЛ" }
    $notifyIcon.Text = "Прослушивание: $status"
}

function Toggle-Listen {
    $script:state.ListenOn = -not $script:state.ListenOn
    $val = if ($script:state.ListenOn) { 1 } else { 0 }
    & $svcl /SetListenToThisDevice DefaultCaptureDevice $val
    Save-State $script:state
    Update-Icon
    $status = if ($script:state.ListenOn) { "включено" } else { "выключено" }
    $notifyIcon.ShowBalloonTip(1200, "Аудио", "Прослушивание микрофона $status", [System.Windows.Forms.ToolTipIcon]::Info)
    # левый клик меню не открывает, значит событие Closed не сработает -
    # пересобираем сами, иначе пункт "Мониторинг: ..." останется со старым статусом
    Refresh-Menu
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

function Set-OutputDevice($deviceName) {
    $isVoicemeeter = $deviceName -match "Voicemeeter"
    $vmProcess = Get-Process -Name $voicemeeterProcessName -ErrorAction SilentlyContinue

    if ($isVoicemeeter) {
        if (-not $vmProcess) {
            if (Test-Path $voicemeeterExe) {
                Start-Process -FilePath $voicemeeterExe
                # даём Voicemeeter время создать свои аудио-эндпоинты перед переключением
                Start-Sleep -Milliseconds 1500
            } else {
                $notifyIcon.ShowBalloonTip(1500, "Аудио", "Не найден Voicemeeter по пути $voicemeeterExe", [System.Windows.Forms.ToolTipIcon]::Warning)
            }
        }
    } else {
        if ($vmProcess) {
            Stop-Process -InputObject $vmProcess -Force
        }
    }

    # Ждать подтверждения не нужно: замерено, что первый же /sjson после
    # /SetDefault уже отдаёт новое устройство. Прежний поллинг только добавлял
    # лишнюю секунду на каждое переключение.
    & $svcl /SetDefault $deviceName all
    $notifyIcon.ShowBalloonTip(1200, "Аудио", "Устройство вывода: $deviceName", [System.Windows.Forms.ToolTipIcon]::Info)
    # WinForms не гарантирует, что Closed сработает после Click, а не до него:
    # пересобираем явно, чтобы галочка гарантированно встала на новое устройство
    Refresh-Menu
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

    $listenStatus = if ($script:state.ListenOn) { "ВКЛ" } else { "ВЫКЛ" }
    $toggleItem = New-Object System.Windows.Forms.ToolStripMenuItem("Мониторинг: $listenStatus")
    $toggleItem.Add_Click({ Toggle-Listen })
    $menu.Items.Add($toggleItem) | Out-Null

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
    $menu.Add_Closed({ Refresh-Menu })
    $notifyIcon.ContextMenuStrip = $menu
}

Refresh-Menu

$notifyIcon.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        Toggle-Listen
    }
    # правый клик ничего не делает: Windows сама покажет готовый ContextMenuStrip
})

Update-Icon
[System.Windows.Forms.Application]::Run()
