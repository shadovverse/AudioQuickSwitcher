; Установщик AudioQuickSwitch.
; Сборка:  "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" installer\AudioQuickSwitch.iss
;
; svcl.exe намеренно НЕ лежит в репозитории и не вшит в установщик -
; он качается с nirsoft.net во время установки (страница "Загрузка компонентов").

#define AppName        "AudioQuickSwitch"
#define AppVersion     "1.0.0"
#define AppPublisher   "shadovverse"
#define AppURL         "https://github.com/shadovverse/fast_audioswitcher"
#define Launcher       "Запустить_скрытно.vbs"
#define SvclUrl32      "https://www.nirsoft.net/utils/svcl.zip"
#define SvclUrl64      "https://www.nirsoft.net/utils/svcl-x64.zip"

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
SetupIconFile=..\mic_icon_on.ico
UninstallDisplayIcon={app}\mic_icon_on.ico
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
ru.TaskStartup=Запускать при входе в Windows
ru.RunAfter=Запустить {#AppName}
ru.DownloadFail=Не удалось скачать svcl.exe с nirsoft.net.%n%nПроверь интернет и попробуй снова. Без этого файла утилита не заработает.%n%nОшибка: %1
en.TaskStartup=Start with Windows
en.RunAfter=Launch {#AppName}
en.DownloadFail=Failed to download svcl.exe from nirsoft.net.%n%nCheck your connection and try again.%n%nError: %1
ru.ExtractFail=Не удалось распаковать svcl.exe.%n%nУтилита без него не работает: скачай svcl-x64.zip с nirsoft.net вручную и положи svcl.exe рядом с AudioQuickSwitch.ps1.
en.ExtractFail=Failed to unpack svcl.exe.%n%nThe app needs it: download svcl-x64.zip from nirsoft.net manually and put svcl.exe next to AudioQuickSwitch.ps1.

[Tasks]
Name: "startupicon"; Description: "{cm:TaskStartup}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\AudioQuickSwitch.ps1";     DestDir: "{app}"; Flags: ignoreversion
Source: "..\{#Launcher}";              DestDir: "{app}"; Flags: ignoreversion
Source: "..\mic_icon_on.ico";          DestDir: "{app}"; Flags: ignoreversion
Source: "..\mic_icon_off.ico";         DestDir: "{app}"; Flags: ignoreversion
; вспомогательный скрипт - только на время установки, в {app} не попадает
Source: "stop-running.ps1";            Flags: dontcopy

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\{#Launcher}"""; IconFilename: "{app}\mic_icon_on.ico"; WorkingDir: "{app}"
Name: "{autostartup}\{#AppName}"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\{#Launcher}"""; IconFilename: "{app}\mic_icon_on.ico"; WorkingDir: "{app}"; Tasks: startupicon

[Run]
Filename: "{sys}\wscript.exe"; Parameters: """{app}\{#Launcher}"""; WorkingDir: "{app}"; Description: "{cm:RunAfter}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; докачанное установщиком - Inno про эти файлы не знает, убираем вручную
Type: files;          Name: "{app}\svcl.exe"
Type: files;          Name: "{app}\svcl.chm"
Type: files;          Name: "{app}\readme.txt"
Type: filesandordirs; Name: "{userappdata}\{#AppName}"

[Code]

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

{ Качаем svcl.exe здесь, а не отдельной страницей мастера: PrepareToInstall
  вызывается и при обычной, и при тихой установке (/VERYSILENT), а страницы
  мастера в тихом режиме не показываются и их код не выполняется вовсе.
  Непустая строка в Result прерывает установку и показывается пользователю. }
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Url: String;
begin
  Result := '';
  if IsWin64 then
    Url := '{#SvclUrl64}'
  else
    Url := '{#SvclUrl32}';
  try
    DownloadTemporaryFile(Url, 'svcl.zip', '', nil);
  except
    Result := FmtMessage(ExpandConstant('{cm:DownloadFail}'), [GetExceptionMessage]);
  end;
end;

{ Распаковываем через Expand-Archive, а не встроенным ExtractArchive:
  архивы NirSoft его декодер не принимает ("not an archive"). }
procedure ExtractSvcl;
var
  ResultCode: Integer;
  Cmd: String;
begin
  Cmd := '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "' +
         'Expand-Archive -LiteralPath ''' + ExpandConstant('{tmp}\svcl.zip') + ''' ' +
         '-DestinationPath ''' + ExpandConstant('{app}') + ''' -Force"';
  Exec('powershell.exe', Cmd, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

  if not FileExists(ExpandConstant('{app}\svcl.exe')) then
    SuppressibleMsgBox(ExpandConstant('{cm:ExtractFail}'), mbCriticalError, MB_OK, IDOK);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
    StopRunningApp
  else if CurStep = ssPostInstall then
    ExtractSvcl;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then
    Exec('powershell.exe',
         '-NoProfile -WindowStyle Hidden -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like ''*AudioQuickSwitch*'' -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"',
         '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;
