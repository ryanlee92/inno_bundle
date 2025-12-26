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
    final outputDir = p.joinAll([Directory.current.path, ...installerBuildDir, config.type.dirName]);

    var installerIcon = config.installerIcon;
    if (installerIcon == defaultInstallerIconPlaceholder) {
      final installerIconDirPath = p.joinAll([Directory.systemTemp.absolute.path, "${camelCase(config.name)}Installer"]);
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

    final scriptDirPath = p.joinAll([Directory.systemTemp.absolute.path, "${camelCase(config.name)}Installer", config.type.dirName]);
    Directory(scriptDirPath).createSync(recursive: true);

    // --- 이 부분을 수정합니다 ---
    final vcRedistFiles = ['VC_redist.x64.exe', 'VC_redist.x86.exe', 'VC_redist.arm64.exe'];

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
// --- Windows API 직접 호출을 위한 정의 (버전 독립적) ---
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
    // Pointer 타입을 LongInt로 수정하여 구버전 호환성 확보
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

// Inno Setup 버전에 의존하지 않는 아키텍처 확인 함수
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
// --- Windows API 정의 끝 ---


// 특정 아키텍처의 VC++ 런타임이 설치되었는지 확인하는 함수
function IsVCRedistInstalled(const Arch: String): Boolean;
var
  Success: Boolean;
  Version: String;
  Key: String;
  Is64Bit: Boolean;
begin
  Key := '';
  Is64Bit := IsWin64;
  
  if Arch = 'x64' then
    Key := 'SOFTWARE/Microsoft/VisualStudio/14.0/VC/Runtimes/x64';
  
  if Arch = 'arm64' then
    Key := 'SOFTWARE/Microsoft/VisualStudio/14.0/VC/Runtimes/arm64';
  
  if Arch = 'x86' then
  begin
    if Is64Bit then
      Key := 'SOFTWARE/WOW6432Node/Microsoft/VisualStudio/14.0/VC/Runtimes/x86'
    else
      Key := 'SOFTWARE/Microsoft/VisualStudio/14.0/VC/Runtimes/x86';
  end;

  if Key = '' then 
  begin
     Result := True;
     exit;
  end;
  
  if Arch = 'x64' then
    Success := RegQueryStringValue(HKLM64, Key, 'Version', Version)
  else
    Success := RegQueryStringValue(HKLM, Key, 'Version', Version);

  Result := Success;
end;

// 각 아키텍처별 최종 체크 함수
function VCRedistNeedsInstall_x64: Boolean;
begin
  Result := (GetArch = 'x64') and (not IsVCRedistInstalled('x64'));
end;

function VCRedistNeedsInstall_x86: Boolean;
begin
  Result := ((GetArch = 'x86') or (GetArch = 'x64')) and (not IsVCRedistInstalled('x86'));
end;

function VCRedistNeedsInstall_arm64: Boolean;
begin
  Result := (GetArch = 'arm64') and (not IsVCRedistInstalled('arm64'));
end;

// --- 앱 이름 마이그레이션 관련 상수 및 함수 ---
const
  OLD_APP_NAME = 'Taskey';
  NEW_APP_NAME = '${config.name}';

// 이전 Program Files 경로 확인
function GetOldProgramFilesPath: String;
var
  ProgramFilesPath: String;
begin
  ProgramFilesPath := ExpandConstant('{autopf}');
  Result := ProgramFilesPath + '\\' + OLD_APP_NAME;
end;

// 이전 AppData 경로 확인
function GetOldAppDataPath: String;
var
  AppDataPath: String;
begin
  AppDataPath := ExpandConstant('{localappdata}');
  Result := AppDataPath + '\\' + OLD_APP_NAME;
end;

// 새 AppData 경로 확인
function GetNewAppDataPath: String;
var
  AppDataPath: String;
begin
  AppDataPath := ExpandConstant('{localappdata}');
  Result := AppDataPath + '\\' + NEW_APP_NAME;
end;

// AppData 마이그레이션 수행
procedure MigrateAppData;
var
  OldAppDataPath: String;
  NewAppDataPath: String;
  FindRec: TFindRec;
  ResultCode: Integer;
begin
  // 앱 이름이 변경된 경우에만 마이그레이션 수행
  if OLD_APP_NAME = NEW_APP_NAME then
    exit;

  OldAppDataPath := GetOldAppDataPath;
  NewAppDataPath := GetNewAppDataPath;

  // 이전 AppData 폴더가 존재하는지 확인
  if not DirExists(OldAppDataPath) then
  begin
    Log('📁 이전 AppData 폴더가 없습니다: ' + OldAppDataPath);
    exit;
  end;

  Log('🔄 AppData 마이그레이션 시작: ' + OldAppDataPath + ' -> ' + NewAppDataPath);

  // 새 AppData 폴더가 이미 존재하는 경우
  if DirExists(NewAppDataPath) then
  begin
    Log('⚠️ 새 AppData 폴더가 이미 존재합니다. 기존 데이터를 유지합니다.');
    exit;
  end;

  // 새 AppData 폴더 생성
  if not CreateDir(NewAppDataPath) then
  begin
    Log('❌ 새 AppData 폴더 생성 실패: ' + NewAppDataPath);
    exit;
  end;

  // xcopy를 사용하여 데이터 복사 (권한 문제 회피)
  if Exec('xcopy', '"' + OldAppDataPath + '\\*" "' + NewAppDataPath + '\\" /E /I /H /Y', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    if ResultCode = 0 then
      Log('✅ AppData 마이그레이션 완료')
    else
      Log('⚠️ AppData 마이그레이션 중 일부 파일 복사 실패 (코드: ' + IntToStr(ResultCode) + ')');
  end
  else
  begin
    Log('❌ AppData 마이그레이션 실패: xcopy 실행 실패');
  end;
end;

// 이전 Program Files 폴더 삭제 (설치 완료 후)
procedure DeleteOldProgramFilesFolder;
var
  OldProgramFilesPath: String;
  ResultCode: Integer;
begin
  // 앱 이름이 변경된 경우에만 삭제 수행
  if OLD_APP_NAME = NEW_APP_NAME then
    exit;

  OldProgramFilesPath := GetOldProgramFilesPath;

  // 이전 Program Files 폴더가 존재하는지 확인
  if not DirExists(OldProgramFilesPath) then
  begin
    Log('📁 이전 Program Files 폴더가 없습니다: ' + OldProgramFilesPath);
    exit;
  end;

  Log('🗑️ 이전 Program Files 폴더 삭제 시작: ' + OldProgramFilesPath);

  // rmdir를 사용하여 폴더 삭제
  if Exec('cmd.exe', '/c rmdir /s /q "' + OldProgramFilesPath + '"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    if ResultCode = 0 then
      Log('✅ 이전 Program Files 폴더 삭제 완료')
    else
      Log('⚠️ 이전 Program Files 폴더 삭제 실패 (코드: ' + IntToStr(ResultCode) + ')');
  end
  else
  begin
    Log('❌ 이전 Program Files 폴더 삭제 실패: rmdir 실행 실패');
  end;
end;

// 기존 CurStepChanged 프로시저
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

    // AppData 마이그레이션 수행 (설치 전)
    MigrateAppData;
  end;

  if CurStep = ssPostInstall then begin
    // 설치 완료 후 이전 Program Files 폴더 삭제
    DeleteOldProgramFilesFolder;
  end;
end;
''';
  }

  Future<File> build() async {
    CliLogger.info("Generating ISS script...");
    final script = scriptHeader + _setup() + _installDelete() + _tasks() + _files() + _icons() + _languages() + _run() + _code();

    final relScriptPath = p.joinAll([...installerBuildDir, config.type.dirName, "inno-script.iss"]);
    final absScriptPath = p.join(Directory.current.path, relScriptPath);
    final scriptFile = File(absScriptPath);
    scriptFile.createSync(recursive: true);
    scriptFile.writeAsStringSync(script);

    CliLogger.success("Script generated $relScriptPath");
    return scriptFile;
  }
}
