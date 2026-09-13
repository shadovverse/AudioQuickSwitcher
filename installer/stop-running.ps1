# Гасит работающий AudioQuickSwitch перед установкой/обновлением.
# Ищем по командной строке, а не по имени процесса: это обычный powershell.exe,
# убивать все подряд нельзя.
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*AudioQuickSwitch*" -and $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
