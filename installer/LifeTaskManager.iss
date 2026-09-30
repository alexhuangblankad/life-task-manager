; 人生任务管理器 —— Windows 安装包脚本（Inno Setup 6）
;
; 用法：powershell -ExecutionPolicy Bypass -File tool\build_installer.ps1
; 产物：dist_installer\LifeTaskManager-1.0.0-setup.exe
;
; 设计取舍：
;   - PrivilegesRequired=lowest → 装到用户目录，不弹 UAC，一路下一步就行（傻瓜式）
;   - DisableDirPage=no → 保留「选择安装位置」那一页，用户能自己改路径
;   - 卸载**不删任何用户数据**（数据在「文档\LifeTaskManager」，跟程序目录分开）

#define AppName "人生任务管理器"
#define AppNameEn "LifeTaskManager"
#define AppVersion "1.1.10"
#define AppExe "life_task_manager.exe"
#define AppPublisher "LifeTaskManager"

[Setup]
AppId={{7C4A9E31-2B6D-4F58-9A03-1E5D7B8C0A42}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppNameEn}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
AllowNoIcons=yes
DisableDirPage=no
OutputDir=..\dist_installer
OutputBaseFilename={#AppNameEn}-{#AppVersion}-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
SetupIconFile=..\assets\tray.ico
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} 安装程序
VersionInfoVersion={#AppVersion}.0

[Languages]
Name: "chinese"; MessagesFile: "ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："
Name: "startupicon"; Description: "开机自动启动（常驻右下角托盘提醒）"; GroupDescription: "附加任务："; Flags: unchecked

[Files]
; dist 整个文件夹（exe + dll + data）
Source: "..\dist\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\卸载 {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon
Name: "{userstartup}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: startupicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "立即启动 {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; 故意留空：用户数据在「文档\LifeTaskManager」，卸载程序不碰它。
; 想彻底删干净的话，手动删那个文件夹就行。
