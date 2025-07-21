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
Filename: "{tmp}\\VC_redist.x64.exe"; Parameters: "/install /passive /norestart"; StatusMsg: "Installing Microsoft VC++ Runtime (x64)..."; Check: not IsVCRedistInstalled('x64'); Architectures: x64
Filename: "{tmp}\\VC_redist.x86.exe"; Parameters: "/install /passive /norestart"; StatusMsg: "Installing Microsoft VC++ Runtime (x86)..."; Check: not IsVCRedistInstalled('x86'); Architectures: x64 x86
Filename: "{tmp}\\VC_redist.arm64.exe"; Parameters: "/install /passive /norestart"; StatusMsg: "Installing Microsoft VC++ Runtime (arm64)..."; Check: not IsVCRedistInstalled('arm64'); Architectures: arm64
Filename: "{app}\\${config.exeName}"; Description: "{cm:LaunchProgram,{#StringChange('${config.name}', '&', '&&')}}"; Flags: nowait postinstall skipifsilent shellexec runascurrentuser
\n''';
  }

  String _code() {
  return '''
[Code]
// 공통 헬퍼 함수: 특정 아키텍처의 VC++ 런타임이 설치되었는지 확인
function IsVCRedistInstalled(const Arch: String): Boolean;
var
  Version: String;
  Key: String;
  Wow64: Boolean;
begin
  // 32비트 OS인지 64비트 OS인지 확인
  Wow64 := IsWin64;

  if Arch = 'x64' then
    Key := 'SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\x64'
  // 64비트 윈도우의 32비트 프로그램 레지스트리 경로
  else if Arch = 'x86' and Wow64 then
    Key := 'SOFTWARE\\WOW6432Node\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\x86'
  // 32비트 윈도우의 32비트 프로그램 레지스트리 경로
  else if Arch = 'x86' and not Wow64 then
    Key := 'SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\x86'
  else if Arch = 'arm64' then
    Key := 'SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\arm64'
  else begin
    Result := True;
    exit;
  end;

  // 64비트 키는 HKLM64에서 찾아야 함
  if Arch = 'x64' then
    Result := RegQueryStringValue(HKLM64, Key, 'Version', Version)
  else
    Result := RegQueryStringValue(HKLM, Key, 'Version', Version);
end;

// --- VCRedistNeedsInstall_... 함수들은 모두 삭제 ---

procedure CurStepChanged(CurStep: TSetupStep);
// ... (기존 CurStepChanged 코드는 그대로 둡니다) ...
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
