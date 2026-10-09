; Inno Setup Script for Windows Handheld Tool
; Tự động đóng gói bộ cài đặt cài vào Program Files với đầy đủ Ring-0 Drivers, DLLs và Shortcuts.

#define MyAppName "Windows Handheld Tool"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "minhtaama"
#define MyAppURL "https://github.com/minhtaama/windows-handheld-tool"
#define MyAppExeName "windows_handheld_tool.exe"
#define SourceDistDir "dist\windows-handheld-tool"

[Setup]
AppId={{5E21F648-9F89-4D01-B101-7F8C430DA3D8}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=dist
OutputBaseFilename=WindowsHandheldTool-Setup-v{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "autostart"; Description: "Khởi động cùng Windows (Tự động chạy khi mở máy)"; GroupDescription: "Tùy chọn khởi động:"

[Files]
; Sao chép toàn bộ tệp từ thư mục phân phối
Source: "{#SourceDistDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Khởi chạy ứng dụng ngay sau khi cài đặt hoàn tất
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
