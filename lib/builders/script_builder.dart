/// This file contains the [ScriptBuilder] class, which is responsible for generating
/// the Inno Setup Script (ISS) file for creating the installer of an application.
///
/// The [ScriptBuilder] class takes a [Config] object and an [appDir] directory as inputs
/// and generates the ISS script based on the provided configuration. This script defines
/// various sections like setup, files, icons, tasks, and languages, among others.
///
/// Key methods:
/// - [_setup]: Generates the `[Setup]` section of the ISS script.
/// - [_installDelete]: Generates the `[InstallDelete]` section.
/// - [_languages]: Generates the `[Languages]` section.
/// - [_tasks]: Generates the `[Tasks]` section.
/// - [_files]: Generates the `[Files]` section.
/// - [_icons]: Generates the `[Icons]` section.
/// - [_run]: Generates the `[Run]` section.
///
/// The [build] method is the main method of this class, which combines all the sections and writes
/// the complete ISS script to a file. It returns the generated script file.
library;

import 'dart:io';

import 'package:inno_bundle/models/config.dart';
import 'package:inno_bundle/models/admin_mode.dart';
import 'package:inno_bundle/utils/cli_logger.dart';
import 'package:inno_bundle/utils/constants.dart';
import 'package:inno_bundle/utils/functions.dart';
import 'package:path/path.dart' as p;

/// A class responsible for generating the Inno Setup Script (ISS) file for the installer.
class ScriptBuilder {
  /// The configuration guiding the script generation process.
  final Config config;

  /// The directory containing the application files to be included in the installer.
  final Directory appDir;

  /// Creates a [ScriptBuilder] instance with the given [config] and [appDir].
  ScriptBuilder(this.config, this.appDir);

  /// Generates the `[Setup]` section of the ISS script, containing metadata and
  /// configuration for the installer.
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
UseSetupLdr=no
${config.signTool != null ? config.signTool?.toInnoCode() : ""}
\n''';
}

String _run() {
  return '''
[Run]
Filename: "{app}\\restart_helper.cmd"; Flags: nowait postinstall skipifsilent;
\n''';
}

String _code() {
  return '''
[Code]
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
    // Sleep 1000 ms to allow Windows to release file handles
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

  // 추가: restart_helper.cmd 생성
  final restartHelperPath = p.join(appDir.path, "restart_helper.cmd");
  final restartHelper = File(restartHelperPath);
  restartHelper.writeAsStringSync('''
@echo off
timeout /t 2 > nul
start "" "%~dp0${config.exeName}"
exit
''');

  CliLogger.success("Script generated $relScriptPath");
  return scriptFile;
}
}
