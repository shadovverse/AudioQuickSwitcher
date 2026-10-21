// Свой exe вместо powershell.exe: в Диспетчере задач утилита видна как
// "AudioQuickSwitch" со своим значком, а не теряется среди "Windows PowerShell".
// Запускает AudioQuickSwitch.ps1 из своей папки внутри себя (хостинг PowerShell).
// Собирается установщиком (installer\AudioQuickSwitch.iss) штатным csc.exe из .NET.
using System;
using System.Diagnostics;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;

[assembly: AssemblyTitle("AudioQuickSwitch")]
[assembly: AssemblyProduct("AudioQuickSwitch")]
// версия программы - единственное место; установщик берёт её отсюда (из готового exe)
[assembly: AssemblyFileVersion("1.2.0")]

static class Program {
    [DllImport("kernel32.dll")]
    static extern bool AttachConsole(int pid);

    // Консоль без окна для консольных программ, которые запускает скрипт (svcl.exe).
    // Без неё PowerShell сам делает AllocConsole и прячет окно уже после создания -
    // при запуске утилиты консоль мелькала на панели задач (поймано хуком
    // EVENT_OBJECT_SHOW). У консоли процесса, запущенного с CREATE_NO_WINDOW, окна
    // нет вовсе: берём её у временного cmd.exe и подключаемся, cmd закрываем.
    static void AttachWindowlessConsole() {
        ProcessStartInfo psi = new ProcessStartInfo("cmd.exe", "/k");
        psi.CreateNoWindow = true;
        psi.UseShellExecute = false;
        using (Process p = Process.Start(psi)) {
            for (int i = 0; i < 50 && !AttachConsole(p.Id); i++) Thread.Sleep(10);
            p.Kill();
        }
    }

    [STAThread]   // WinForms в скрипте требует STA
    static void Main() {
        AttachWindowlessConsole();
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
