; Установщик AudioQuickSwitch.
; Сборка:  "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" installer\AudioQuickSwitch.iss
;
; svcl.exe от NirSoft лежит внутри установщика (installer/vendor/svcl-x64).
; Раньше он качался с nirsoft.net во время установки - от этого отказались:
; у части машин установка обрывалась сразу после выбора папки (нет доступа
; к сайту, антивирус блокирует NirSoft или запуск PowerShell из установщика).
; Лицензия NirSoft разрешает свободно распространять утилиту без изменений.
;
; Перед сборкой: скачать svcl-x64.zip с nirsoft.net и распаковать в
; installer/vendor/svcl-x64 (в репозиторий не коммитится).

#define AppName        "AudioQuickSwitch"
#define AppPublisher   "shadovverse"
#define AppURL         "https://github.com/shadovverse/AudioQuickSwitcher"
; Собираем свой AudioQuickSwitch.exe (launcher\AudioQuickSwitch.cs) штатным csc.exe
; из .NET Framework - он есть в любой Windows 10/11. Версия программы задаётся
; там же (AssemblyFileVersion) и отсюда читается из готового exe.
#define CscExe  "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
#define SmaDll  "C:\Windows\Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation\v4.0_3.0.0.0__31bf3856ad364e35\System.Management.Automation.dll"
#if Exec(CscExe, '/nologo /target:winexe /out:"AudioQuickSwitch.exe" /win32icon:"..\app_icon.ico" /r:"' + SmaDll + '" "..\launcher\AudioQuickSwitch.cs"', SourcePath, 1, 0) != 0
  #error Не собрался launcher\AudioQuickSwitch.cs (csc.exe)
#endif
#define AppVersion GetStringFileInfo(AddBackslash(SourcePath) + "AudioQuickSwitch.exe", "ProductVersion")

[Setup]
AppId={{D9ED2889-A9F8-44B8-9D0E-4D2689043DA9}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
VersionInfoVersion={#AppVersion}

; Ставим в профиль пользователя: UAC не нужен, окно "разрешить изменения" не всплывёт.
PrivilegesRequired=lowest
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
AllowNoIcons=yes

OutputDir=..\dist
OutputBaseFilename=AQS Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; язык берём по системе, лишний диалог в начале не нужен
ShowLanguageDialog=no
SetupIconFile=..\app_icon.ico
UninstallDisplayIcon={app}\app_icon.ico
; в комплекте только 64-битный svcl.exe - на 32-битной Windows ставить нечего
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; запись в "Установленные приложения" (HKCU, раз ставим в профиль пользователя)
UninstallDisplayName={#AppName} {#AppVersion}
AppVerName={#AppName} {#AppVersion}
CreateUninstallRegKey=yes

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
ru.TaskStartup=Запускать при входе в Windows
ru.RunAfter=Запустить {#AppName}
en.TaskStartup=Start with Windows
en.RunAfter=Launch {#AppName}

[Files]
Source: "..\AudioQuickSwitch.ps1";     DestDir: "{app}"; Flags: ignoreversion
Source: "AudioQuickSwitch.exe";        DestDir: "{app}"; Flags: ignoreversion
Source: "..\mic_icon_on.ico";          DestDir: "{app}"; Flags: ignoreversion
Source: "..\mic_icon_off.ico";         DestDir: "{app}"; Flags: ignoreversion
Source: "..\app_icon.ico";            DestDir: "{app}"; Flags: ignoreversion
; svcl от NirSoft - кладём целиком, как требует его лицензия (exe + справка + readme)
Source: "vendor\svcl-x64\*";          DestDir: "{app}"; Flags: ignoreversion
; вспомогательный скрипт - только на время установки, в {app} не попадает
Source: "stop-running.ps1";            Flags: dontcopy

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\AudioQuickSwitch.exe"; WorkingDir: "{app}"

[Run]
; Обе строки превращаются в галочки на последней странице мастера.
; Автозапуск пишем значением в HKCU\...\Run, а не ярлыком в папке автозагрузки:
; из [Run] можно запустить программу, но не создать ярлык, а reg.exe есть везде.
Filename: "{sys}\reg.exe"; Parameters: "add ""HKCU\Software\Microsoft\Windows\CurrentVersion\Run"" /v {#AppName} /t REG_SZ /d ""\""{app}\AudioQuickSwitch.exe\"""" /f"; Description: "{cm:TaskStartup}"; Flags: postinstall skipifsilent runhidden
Filename: "{app}\AudioQuickSwitch.exe"; WorkingDir: "{app}"; Description: "{cm:RunAfter}"; Flags: nowait postinstall skipifsilent

[Registry]
; само значение создаёт галочка выше; здесь только уборка при удалении
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "{#AppName}"; Flags: uninsdeletevalue
; обновление: если автозапуск уже включён, переписываем его на AudioQuickSwitch.exe,
; иначе он указывал бы на удалённый старый лаунчер
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#AppName}"; ValueData: """{app}\AudioQuickSwitch.exe"""; Check: AutostartEnabled

[InstallDelete]
; прежние лаунчеры (через wscript.exe): до 1.0.0 и в 1.1.0
Type: files; Name: "{app}\Запустить_скрытно.vbs"
Type: files; Name: "{app}\start-hidden.vbs"

[UninstallRun]
; гасим утилиту, иначе в трее остаётся живой значок от снесённой программы;
; деинсталлятор - unins000.exe, под фильтр не попадает
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM AudioQuickSwitch.exe"; Flags: runhidden; RunOnceId: "StopApp"

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\{#AppName}"

[Code]

function AutostartEnabled: Boolean;
begin
  Result := RegValueExists(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Run', '{#AppName}');
end;

{ Гасим запущенный экземпляр: иначе при обновлении файлы заняты, а при удалении
  в трее остаётся живой значок от снесённой программы (это - [UninstallRun]). }
procedure StopRunningApp;
var
  ResultCode: Integer;
begin
  ExtractTemporaryFile('stop-running.ps1');
  Exec('powershell.exe',
       '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + ExpandConstant('{tmp}\stop-running.ps1') + '" -App "' + ExpandConstant('{app}') + '"',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then StopRunningApp;
end;

