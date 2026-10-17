# Гасит работающий AudioQuickSwitch перед установкой/обновлением.
#
# Фильтр ОБЯЗАН ловить только саму утилиту: процесс, который крутит скрипт
# (до 1.2.0 - powershell.exe с AudioQuickSwitch.ps1 в командной строке), или
# AudioQuickSwitch.exe именно из папки установки. Раньше здесь было совпадение
# по "*AudioQuickSwitch*" - под него попадали и установщик, и деинсталлятор
# (лежит в папке ...\AudioQuickSwitch), то есть они убивали сами себя:
# установка обрывалась сразу после выбора папки, а удаление не удаляло ничего.
param([string]$App)
$exe = Join-Path $App "AudioQuickSwitch.exe"
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { ($_.CommandLine -like "*AudioQuickSwitch.ps1*" -or $_.ExecutablePath -eq $exe) -and $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
