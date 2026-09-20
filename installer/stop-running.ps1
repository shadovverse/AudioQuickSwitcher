# Гасит работающий AudioQuickSwitch перед установкой/обновлением.
#
# Фильтр ОБЯЗАН ловить только процесс, который крутит сам скрипт.
# Раньше здесь было совпадение по "*AudioQuickSwitch*" - под него попадали
# и установщик (AudioQuickSwitch-Setup.exe), и деинсталлятор (лежит в папке
# ...\AudioQuickSwitch), то есть они убивали сами себя: установка обрывалась
# сразу после выбора папки, а удаление не удаляло ничего.
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*AudioQuickSwitch.ps1*" -and $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
