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
#define AppVersion     "1.1.0"
#define AppPublisher   "shadovverse"
#define AppURL         "https://github.com/shadovverse/fast_audioswitcher"
#define Launcher       "start-hidden.vbs"
; до 1.0.0 включительно лаунчер назывался так - убираем при обновлении
#define OldLauncher    "Запустить_скрытно.vbs"

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
OutputBaseFilename=AudioQuickSwitch-Setup
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
Source: "..\{#Launcher}";              DestDir: "{app}"; Flags: ignoreversion
Source: "..\mic_icon_on.ico";          DestDir: "{app}"; Flags: ignoreversion
Source: "..\mic_icon_off.ico";         DestDir: "{app}"; Flags: ignoreversion
Source: "..\app_icon.ico";            DestDir: "{app}"; Flags: ignoreversion
; svcl от NirSoft - кладём целиком, как требует его лицензия (exe + справка + readme)
Source: "vendor\svcl-x64\*";          DestDir: "{app}"; Flags: ignoreversion
; вспомогательный скрипт - только на время установки, в {app} не попадает
Source: "stop-running.ps1";            Flags: dontcopy

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\{#Launcher}"""; IconFilename: "{app}\app_icon.ico"; WorkingDir: "{app}"

[Run]
; Обе строки превращаются в галочки на последней странице мастера.
; Автозапуск пишем значением в HKCU\...\Run, а не ярлыком в папке автозагрузки:
; из [Run] можно запустить программу, но не создать ярлык, а reg.exe есть везде.
Filename: "{sys}\reg.exe"; Parameters: "add ""HKCU\Software\Microsoft\Windows\CurrentVersion\Run"" /v {#AppName} /t REG_SZ /d ""\""{sys}\wscript.exe\"" \""{app}\{#Launcher}\"""" /f"; Description: "{cm:TaskStartup}"; Flags: postinstall skipifsilent runhidden
Filename: "{sys}\wscript.exe"; Parameters: """{app}\{#Launcher}"""; WorkingDir: "{app}"; Description: "{cm:RunAfter}"; Flags: nowait postinstall skipifsilent

[Registry]
; само значение создаёт галочка выше; здесь только уборка при удалении
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "{#AppName}"; Flags: uninsdeletevalue
; обновление: если автозапуск уже включён, переписываем его на новое имя лаунчера,
; иначе он указывал бы на удалённый {#OldLauncher}
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#AppName}"; ValueData: """{sys}\wscript.exe"" ""{app}\{#Launcher}"""; Check: AutostartEnabled

[InstallDelete]
Type: files; Name: "{app}\{#OldLauncher}"

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\{#AppName}"

[Code]

function AutostartEnabled: Boolean;
begin
  Result := RegValueExists(HKEY_CURRENT_USER, 'Software\Microsoft\Windows\CurrentVersion\Run', '{#AppName}');
end;

{ Гасим запущенный экземпляр: иначе при обновлении файлы заняты, а при удалении
  в трее остаётся живой значок от снесённой программы. }
procedure StopRunningApp;
var
  ResultCode: Integer;
begin
  ExtractTemporaryFile('stop-running.ps1');
  Exec('powershell.exe',
       '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + ExpandConstant('{tmp}\stop-running.ps1') + '"',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then StopRunningApp;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then
    Exec('powershell.exe',
         '-NoProfile -WindowStyle Hidden -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like ''*AudioQuickSwitch.ps1*'' -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"',
         '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;
