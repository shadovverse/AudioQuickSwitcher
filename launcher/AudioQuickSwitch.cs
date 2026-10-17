// Свой exe вместо powershell.exe: в Диспетчере задач утилита видна как
// "AudioQuickSwitch" со своим значком, а не теряется среди "Windows PowerShell".
// Запускает AudioQuickSwitch.ps1 из своей папки внутри себя (хостинг PowerShell).
// Собирается установщиком (installer\AudioQuickSwitch.iss) штатным csc.exe из .NET.
using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;

[assembly: AssemblyTitle("AudioQuickSwitch")]
[assembly: AssemblyProduct("AudioQuickSwitch")]
// версия программы - единственное место; установщик берёт её отсюда (из готового exe)
[assembly: AssemblyFileVersion("1.2.0")]

static class Program {
    [STAThread]   // WinForms в скрипте требует STA
    static void Main() {
        InitialSessionState iss = InitialSessionState.CreateDefault();
        iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
        using (Runspace rs = RunspaceFactory.CreateRunspace(iss)) {
            rs.ThreadOptions = PSThreadOptions.UseCurrentThread;
            rs.Open();
            using (PowerShell ps = PowerShell.Create()) {
                ps.Runspace = rs;
                ps.AddCommand(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "AudioQuickSwitch.ps1"));
                ps.Invoke();
            }
        }
    }
}
