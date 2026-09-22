# Проверка связки с Core Audio (класс AqsVolume в AudioQuickSwitch.ps1).
# Если в C#-интерфейсах нарушить порядок методов (vtable), ошибки компиляции
# не будет - громкость просто начнёт читаться/писаться мимо. Этот скрипт ловит это.
# Запуск: powershell -ExecutionPolicy Bypass -File tests\check-volume.ps1
# Громкость трогается на 1% и сразу возвращается.

$src  = Join-Path $PSScriptRoot "..\AudioQuickSwitch.ps1"
$text = [IO.File]::ReadAllText($src)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Invoke-Expression $text.Substring(0, $text.IndexOf('# ---------- НАСТРОЙКИ'))

$orig   = [AqsVolume]::Get()
$target = if ($orig -gt 0) { $orig - 1 } else { 1 }
try {
    [AqsVolume]::Set($target)
    $got = [AqsVolume]::Get()
    if ($got -ne $target) { throw "поставили $target%, прочитали $got%" }
    "OK: Get/Set сходятся ($orig% -> $target% -> $got%)"
} finally {
    [AqsVolume]::Set($orig)
}
