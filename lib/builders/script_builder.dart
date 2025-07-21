import 'dart:io';
import 'package:inno_bundle/models/config.dart';
import 'package:inno_bundle/models/admin_mode.dart';
import 'package:inno_bundle/utils/cli_logger.dart';
import 'package:inno_bundle/utils/constants.dart';
import 'package:inno_bundle/utils/functions.dart';
import 'package:path/path.dart' as p;

class ScriptBuilder {
  final Config config;
  final Directory appDir;

  ScriptBuilder(this.config, this.appDir);

  String _setup() {
    final outputDir = p.joinAll([
      Directory.current.path,
      ...installerBuildDir,
      config.type.dirName,
    ]);

    var installerIcon = config.installerIcon;
    if (installerIcon == defaultInstallerIconPlaceholder) {
      final installerIconDirPath = p.joinAll([
        Directory.systemTemp.absolute.path,
        "${camelCase(config.name)}Installer",
      ]);
      installerIcon = persistDefaultInstallerIcon(installerIconDirPath);
    }

    return '''
[Setup]
AppId=${config.id}
AppName=${config.name}
UninstallDisplayName=${config.name}
UninstallDisplayIcon={app}\\${config.exeName}
AppVersion=${config.version}
AppPublisher=${config.publisher}
AppPublisherURL=${config.url}
AppSupportURL=${config.supportUrl}
AppUpdatesURL=${config.updatesUrl}
LicenseFile=${config.licenseFile}
DefaultDirName={autopf}\\${config.name}
PrivilegesRequired=${config.admin == AdminMode.nonAdmin ? 'lowest' : 'admin'}
PrivilegesRequiredOverridesAllowed=${config.admin == AdminMode.auto ? "dialog commandline" : ""}
OutputDir=$outputDir
OutputBaseFilename=${camelCase(config.name)}-${config.arch.cpu}-${config.version}-Installer
SetupIconFile=$installerIcon
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
DisableWelcomePage=no
ArchitecturesAllowed=${config.arch.value}
ArchitecturesInstallIn64BitMode=${config.arch.value}
DisableDirPage=auto
DisableProgramGroupPage=auto
ShowLanguageDialog=no
CloseApplications=no
${config.signTool != null ? config.signTool?.toInnoCode() : ""}
\n''';
  }

  String _installDelete() {
    return '''
[InstallDelete]
Type: filesandordirs; Name: "{app}\\*"
\n''';
  }

  String _languages() {
    return '''
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
\n''';
  }

  String _tasks() {
    return '''
[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}";
Name: "startup"; Description: "Run ${config.name} when Windows starts"; GroupDescription: "Additional Options:"


[Registry]
Root: "HKCU"; Subkey: "Software\\Microsoft\\Windows\\CurrentVersion\\Run"; ValueType: string; ValueName: "${config.name}"; ValueData: """{app}\\${config.exeName}"""; Flags: uninsdeletevalue; Tasks: startup
  
\n''';
  }

  String _files() {
    var section = "[Files]\n";

    final files = appDir.listSync();
    for (final file in files) {
      final filePath = file.absolute.path;
      if (FileSystemEntity.isDirectorySync(filePath)) {
        final fileName = p.basename(file.path);
        section += "Source: \"$filePath\\*\"; DestDir: \"{app}\\$fileName\"; Flags: ignoreversion recursesubdirs createallsubdirs\n";
      } else {
        if (p.basename(filePath) == config.exePubspecName && config.exeName != config.exePubspecName) {
          print("Renamed ${config.exePubspecName} ${config.exeName}");
          section += "Source: \"$filePath\"; DestDir: \"{app}\"; DestName: \"${config.exeName}\"; Flags: ignoreversion\n";
        } else {
          section += "Source: \"$filePath\"; DestDir: \"{app}\"; Flags: ignoreversion\n";
        }
      }
    }

    final scriptDirPath = p.joinAll([
      Directory.systemTemp.absolute.path,
      "${camelCase(config.name)}Installer",
      config.type.dirName,
    ]);
    Directory(scriptDirPath).createSync(recursive: true);

    // --- 이 부분을 수정합니다 ---
    final vcRedistFiles = [
      'VC_redist.x64.exe',
      'VC_redist.x86.exe',
      'VC_redist.arm64.exe',
    ];
    
    for (final fileName in vcRedistFiles) {
      final filePath = p.join(Directory.current.path, 'dependencies', fileName);
      if (File(filePath).existsSync()) {
        section += 'Source: "$filePath"; DestDir: "{tmp}"; Flags: deleteafterinstall\n';
      } else {
        CliLogger.warning('$fileName not found in "dependencies" folder. Skipping.');
      }
    }
    // --- 여기까지 수정 ---
    
    for (final fileName in vcDllFiles) {
      final file = File(p.joinAll([...system32, fileName]));
      if (!file.existsSync()) continue;
      final fileNewPath = p.join(scriptDirPath, p.basename(file.path));
      file.copySync(fileNewPath);
      section += "Source: \"$fileNewPath\"; DestDir: \"{app}\";\n";
    }

    return '$section\n';
  }

  String _icons() {
    return '''
[Icons]
Name: "{autoprograms}\\${config.name}"; Filename: "{app}\\${config.exeName}"; AppUserModelID: "WaveCorporation.Taskey"; AppUserModelToastActivatorCLSID: "6D809377-6AF0-444B-8957-A3773F02200E";
Name: "{autodesktop}\\${config.name}"; Filename: "{app}\\${config.exeName}"; Tasks: desktopicon; AppUserModelID: "WaveCorporation.Taskey"; AppUserModelToastActivatorCLSID: "6D809377-6AF0-444B-8957-A3773F02200E"; Flags: preventpinning;
\n''';
  }

  String _run() {
    return '''
[Run]
Filename: "{tmp}\\VC_redist.x64.exe"; Parameters: "/install /passive /norestart"; StatusMsg: "Installing Microsoft VC++ Runtime (x64)..."; Check: VCRedistNeedsInstall_x64
Filename: "{tmp}\\VC_redist.x86.exe"; Parameters: "/install /passive /norestart"; StatusMsg: "Installing Microsoft VC++ Runtime (x86)..."; Check: VCRedistNeedsInstall_x86
Filename: "{tmp}\\VC_redist.arm64.exe"; Parameters: "/install /passive /norestart"; StatusMsg: "Installing Microsoft VC++ Runtime (arm64)..."; Check: VCRedistNeedsInstall_arm64
Filename: "{app}\\${config.exeName}"; Description: "{cm:LaunchProgram,{#StringChange('${config.name}', '&', '&&')}}"; Flags: nowait postinstall skipifsilent shellexec runascurrentuser
\n''';
  }

  String _code() {
  return '''
[Code]
// Windows API 함수 및 상수 정의
const
  PROCESSOR_ARCHITECTURE_AMD64 = 9;
  PROCESSOR_ARCHITECTURE_ARM = 5;
  PROCESSOR_ARCHITECTURE_ARM64 = 12;
  PROCESSOR_ARCHITECTURE_INTEL = 0;

type
  SYSTEM_INFO = record
    wProcessorArchitecture: Word;
    wReserved: Word;
    dwPageSize: DWord;
    lpMinimumApplicationAddress: LongInt;
    lpMaximumApplicationAddress: LongInt;
    dwActiveProcessorMask: DWord;
    dwNumberOfProcessors: DWord;
    dwProcessorType: DWord;
    dwAllocationGranularity: DWord;
    wProcessorLevel: Word;
    wProcessorRevision: Word;
  end;

procedure GetNativeSystemInfo(var lpSystemInfo: SYSTEM_INFO);
  external 'GetNativeSystemInfo@kernel32.dll stdcall';

// 현재 PC의 아키텍처를 문자열로 반환하는 헬퍼 함수
function GetArch: String;
var
  SystemInfo: SYSTEM_INFO;
begin
  GetNativeSystemInfo(SystemInfo);
  case SystemInfo.wProcessorArchitecture of
    PROCESSOR_ARCHITECTURE_AMD64: Result := 'x64';
    PROCESSOR_ARCHITECTURE_ARM64: Result := 'arm64';
    PROCESSOR_ARCHITECTURE_INTEL: Result := 'x86';
    else Result := 'unknown';
  end;
end;

// 특정 아키텍처의 VC++ 런타임이 설치되었는지 확인하는 헬퍼 함수
function IsVCRedistInstalled(const Arch: String): Boolean;
var
  Version: String;
  Key: String;
  Is64Bit: Boolean;
begin
  Is64Bit := IsWin64;
  
  if Arch = 'x64' then
    Key := 'SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\x64'
  else if Arch = 'x86' and Is64Bit then
    Key := 'SOFTWARE\\WOW6432Node\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\x86'
  else if Arch = 'x86' and not Is64Bit then
    Key := 'SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\x86'
  else if Arch = 'arm64' then
    Key := 'SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\arm64'
  else begin
    Result := True;
    exit;
  end;
  
  if Arch = 'x64' then
    Result := RegQueryStringValue(HKLM64, Key, 'Version', Version)
  else
    Result := RegQueryStringValue(HKLM, Key, 'Version', Version);
end;

// x64용 최종 체크 함수
function VCRedistNeedsInstall_x64: Boolean;
begin
  Result := (GetArch = 'x64') and (not IsVCRedistInstalled('x64'));
end;

// x86용 최종 체크 함수
function VCRedistNeedsInstall_x86: Boolean;
begin
  // x64 윈도우에서도 x86 런타임이 필요할 수 있음
  Result := ((GetArch = 'x86') or (GetArch = 'x64')) and (not IsVCRedistInstalled('x86'));
end;

// arm64용 최종 체크 함수
function VCRedistNeedsInstall_arm64: Boolean;
begin
  Result := (GetArch = 'arm64') and (not IsVCRedistInstalled('arm64'));
end;

// 기존 CurStepChanged 프로시저 (그대로 둡니다)
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  ExecResult: Boolean;
begin
  if CurStep = ssInstall then begin
    Log('🔧 Killing running ${config.exeName} during installation...');
    ExecResult := Exec('taskkill.exe', '/F /IM ${config.exeName}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    if not ExecResult then
      Log('❌ Failed to kill process')
    else
      Log('✅ Process killed, sleeping for 1 second...');
    Sleep(1000);
  end;
end;
''';
}

  Future<File> build() async {
    CliLogger.info("Generating ISS script...");
    final script = scriptHeader +
        _setup() +
        _installDelete() +
        _tasks() +
        _files() +
        _icons() +
        _languages() +
        _run() +
        _code();

    final relScriptPath = p.joinAll([
      ...installerBuildDir,
      config.type.dirName,
      "inno-script.iss",
    ]);
    final absScriptPath = p.join(Directory.current.path, relScriptPath);
    final scriptFile = File(absScriptPath);
    scriptFile.createSync(recursive: true);
    scriptFile.writeAsStringSync(script);

    CliLogger.success("Script generated $relScriptPath");
    return scriptFile;
  }
}
