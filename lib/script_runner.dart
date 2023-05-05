// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' show exitCode, Process, ProcessResult, ProcessStartMode;

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:args/args.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as path;
import 'package:platform/platform.dart';
import 'package:process/process.dart';

class DartSDK {
  DartSDK({
    required this.fs,
    required this.processManager,
    required this.platform,
  });

  final FileSystem fs;
  final ProcessManager processManager;
  final Platform platform;

  bool get valid => dartExe != null;

  Future<int> runDart(List<String> arguments) async {
    final Process process = await processManager.start(
      <String>[dartExe!, ...arguments],
      mode: ProcessStartMode.inheritStdio,
    );
    return process.exitCode;
  }

  Future<ProcessResult> runPub(
    List<String> arguments, {
    String? workingDirectory,
  }) {
    return processManager.run(
      <String>[dartExe!, 'pub', ...arguments],
      workingDirectory: workingDirectory,
    );
  }

  (bool, String?) verifyDartVersion() {
    final String version = platform.version;
    final List<String> versionNumberParts = version.split('.');
    final int? majorVersion = int.tryParse(versionNumberParts[0]);
    if (majorVersion == null) {
      return (false, 'Parsing Dart version string "$version" failed');
    }
    if (majorVersion < 3) {
      return (false, 'The Dart version must be greater than 3.0.0: "$version"');
    }
    return (true, null);
  }

  late final String? dartExe = () {
    // First see if the processManager knows how to find 'dart'.
    if (processManager.canRun('dart')) {
      return 'dart';
    }

    // Otherwise, compute from `Platform.executable`, though this will be wrong
    // if this program is compiled into a self-contained binary from
    // `dart compile exe`.
    final String exe = platform.executable;
    final String dartGuess = path.join(
      path.dirname(exe),
      'dart${path.extension(exe)}',
    );
    return fs.file(dartGuess).existsSync() ? dartGuess : null;
  }();
}

class ImportVisitor extends RecursiveAstVisitor<void> {
  ImportVisitor({required this.fs, required this.scriptPath});

  final FileSystem fs;
  final String scriptPath;
  final Set<String> packageImports = {};
  final Set<String> fsImports = {};

  @override
  void visitImportDirective(ImportDirective node) {
    final String? import = node.uri.stringValue;
    if (import == null) {
      // TODO(zra): Do something more useful here.
      print('ImportDirective with null uri.stringValue: "$node"');
      return;
    }
    final Uri? uri = Uri.tryParse(import);
    if (uri == null) {
      // TODO(zra): Do something more useful here.
      print('ImportDirective was not a URI: "$import"');
      return;
    }
    //print('uri: $uri, scheme: ${uri.scheme}');
    if (uri.scheme == 'package') {
      final int indexOfColon = import.indexOf(':');
      final int indexOfSlash = import.indexOf('/');
      packageImports.add(import.substring(indexOfColon + 1, indexOfSlash));
    } else if (uri.scheme == '') {
      // The uri is absolute or relative to the current file's path.
      if (fs.path.isAbsolute(import)) {
        fsImports.add(import);
      } else {
        fsImports.add(fs.path.canonicalize(fs.path.join(
          fs.path.dirname(scriptPath),
          import,
        )));
      }
    }
  }
}

class PackageImportExtractor {
  PackageImportExtractor({required this.fs});

  final FileSystem fs;

  Set<String> getPackages(String scriptPath) {
    final Set<String> visitedFsImports = <String>{};
    final Set<String> unvisitedFsImports = <String>{scriptPath};
    final Set<String> packageImports = <String>{};
    do {
      final String script = unvisitedFsImports.first;
      //print('Import extractor visiting: "$script"');
      final (Set<String>, Set<String>) imports = _getPackages(script);
      // for (final i in imports.$1) {
      //   print('\tFound package $i');
      // }
      // for (final i in imports.$2) {
      //   print('\tFound path $i');
      // }
      packageImports.addAll(imports.$1);
      visitedFsImports.add(script);
      unvisitedFsImports.remove(script);
      unvisitedFsImports.addAll(imports.$2);
      unvisitedFsImports.removeWhere(
        (String i) => visitedFsImports.contains(i),
      );
    } while (unvisitedFsImports.isNotEmpty);

    return packageImports;
  }

  (Set<String>, Set<String>) _getPackages(String scriptPath) {
    final File scriptFile = fs.file(scriptPath);

    final ParseStringResult parseResult = parseString(
      content: scriptFile.readAsStringSync(),
      featureSet: FeatureSet.latestLanguageVersion(),
    );
    final ImportVisitor visitor = ImportVisitor(
      fs: fs,
      scriptPath: scriptPath,
    );
    visitor.visitCompilationUnit(parseResult.unit);
    return (visitor.packageImports, visitor.fsImports);
  }
}

class PackageConfigGenerator {
  PackageConfigGenerator({required this.dartSdk, required this.fs});

  final DartSDK dartSdk;
  final FileSystem fs;

  Future<void> ensurePackageConfig(
    Set<String> packages,
    String packageConfigPath,
  ) async {
    final File packageConfigFile = fs.file(packageConfigPath);
    // If it exists, see if the dot packages file already has everything.
    if (packageConfigFile.existsSync()) {
      final String packageConfigContents = packageConfigFile.readAsStringSync();
      final PackageConfig packageConfig = PackageConfig.parseString(
        packageConfigContents,
        packageConfigFile.parent.uri,
      );
      if (packages.every((String package) => packageConfig[package] != null)) {
        return;
      }
    }

    // The file does not exist, or it doesn't have all packages. Run pub to
    // write it into packageConfigFile.
    final String pubspecString = buildPubspecString(packages);
    await generatePackageConfig(pubspecString, packageConfigFile);
  }

  String buildPubspecString(Set<String> packages) {
    final StringBuffer pubspecBuilder = StringBuffer()
      ..writeln('name: script')
      ..writeln('publish_to: none')
      ..writeln('environment:')
      ..writeln("  sdk: '>=3.0.0-0 <4.0.0'")
      ..writeln('dependencies:');
    for (final import in packages) {
      pubspecBuilder.writeln('  $import: any');
    }
    return pubspecBuilder.toString();
  }

  Future<void> generatePackageConfig(
    String pubspecString,
    File packageConfigFile,
  ) async {
    final Directory tempDir = fs.currentDirectory.createTempSync(
      'drt_',
    );
    try {
      final File pubspecFile = fs.file(path.join(tempDir.path, 'pubspec.yaml'));
      pubspecFile.writeAsStringSync(pubspecString);

      final ProcessResult pubGetResult = await dartSdk.runPub(
        <String>['get'],
        workingDirectory: tempDir.path,
      );
      if (pubGetResult.exitCode != 0) {
        print('pub get failed');
        return;
      }

      final File packageConfigJson = fs.file(path.join(
        tempDir.path,
        '.dart_tool',
        'package_config.json',
      ));

      packageConfigJson.copySync(packageConfigFile.path);
    } finally {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {
        // Ignore.
      }
    }
  }
}

abstract class Logger {
  void printLog(String message);

  void printError(String message);
}

class LocalLogger implements Logger {
  @override
  void printLog(String message) => print(message);

  @override
  void printError(String message) => print('ERROR: $message');
}

class ScriptRunner {
  ScriptRunner({
    required this.fs,
    required this.dartSdk,
    required this.logger,
  });

  final FileSystem fs;
  final DartSDK dartSdk;
  final Logger logger;

  int _result = 0;
  int get result => _result;

  Future<void> run(List<String> arguments) async {
    if (!checkArguments(arguments)) {
      _result = 1;
      return;
    }

    if (!checkDart()) {
      _result = 1;
      return;
    }

    final int? appJitResult = await tryAppJit(arguments);
    if (appJitResult != null) {
      _result = appJitResult;
      return;
    }

    final String script = arguments[0];
    final String appJitSnapshotPath = fs.path.join(
      fs.path.dirname(script),
      '.${fs.path.basenameWithoutExtension(script)}.jit',
    );
    final String packageConfigPath = await getPackageConfig(script);
    _result = await dartSdk.runDart(<String>[
      '--disable-dart-dev',
      '--snapshot-kind=app-jit',
      '--snapshot=$appJitSnapshotPath',
      '--packages=$packageConfigPath',
      script,
      if (arguments.length > 1) ...arguments.sublist(1),
    ]);
  }

  bool checkArguments(List<String> arguments) {
    if (arguments.isEmpty) {
      logger.printError('Missing script');
      return false;
    }
    if (!fs.file(arguments[0]).existsSync()) {
      logger.printError('Script file "${arguments[0]}" not found');
      return false;
    }
    return true;
  }

  bool checkDart() {
    if (!dartSdk.valid) {
      logger.printError(
        'A "dart" executable could not be found. Make sure that a Dart SDK '
        'newer than 3.0 is on your PATH.',
      );
      return false;
    }

    final (bool, String?) dartVersion = dartSdk.verifyDartVersion();
    if (!dartVersion.$1) {
      logger.printError(dartVersion.$2!);
      return false;
    }

    return true;
  }

  Future<int?> tryAppJit(List<String> arguments) async {
    final String script = arguments[0];
    final File scriptFile = fs.file(script);
    final String appJitSnapshotPath = fs.path.join(
      fs.path.dirname(script),
      '.${fs.path.basenameWithoutExtension(script)}.jit',
    );

    // If the snapshot file exists, and the script hasn't been modified since
    // the snapshot was created, then run from the snapshot.
    final File appJitSnapshotFile = fs.file(appJitSnapshotPath);
    if (appJitSnapshotFile.existsSync()) {
      final DateTime snapshotModified = appJitSnapshotFile.lastModifiedSync();
      final DateTime scriptModified = scriptFile.lastModifiedSync();
      if (snapshotModified.isAfter(scriptModified)) {
        return dartSdk.runDart(<String>[
          appJitSnapshotFile.path,
          if (arguments.length > 1) ...arguments.sublist(1),
        ]);
      }
    }

    // If the snapshot is stale, then delete it.
    if (appJitSnapshotFile.existsSync()) {
      try {
        appJitSnapshotFile.deleteSync();
      } catch (_) {
        // Ignore.
      }
    }
    return null;
  }

  Future<String> getPackageConfig(String script) async {
    final File scriptFile = fs.file(script);
    final String packageConfigPath = fs.path.join(
      fs.path.dirname(script),
      '.${fs.path.basenameWithoutExtension(script)}.package_config.json',
    );

    final File packageConfigFile = fs.file(packageConfigPath);
    final DateTime scriptModified = scriptFile.lastModifiedSync();
    if (!packageConfigFile.existsSync() ||
        packageConfigFile.lastModifiedSync().isBefore(scriptModified)) {
      if (packageConfigFile.existsSync()) {
        packageConfigFile.deleteSync();
      }
      final Set<String> packages =
          PackageImportExtractor(fs: fs).getPackages(script);
      await PackageConfigGenerator(fs: fs, dartSdk: dartSdk)
          .ensurePackageConfig(packages, packageConfigPath);
    }

    return packageConfigPath;
  }
}

Future<void> main(List<String> arguments) async {
  final ArgParser argParser = ArgParser(allowTrailingOptions: false);
  argParser.addFlag(
    'help',
    abbr: 'h',
    negatable: false,
    help: 'Print help for this command.',
  );
  final ArgResults parsedArguments = argParser.parse(arguments);
  if (parsedArguments['help'] as bool? ?? false) {
    print('This program runs standalone Dart scripts.');
    print('usage: rundart path/to/script.dart [script arguments]');
    print(argParser.usage);
    exitCode = 1;
    return;
  }

  final FileSystem fs = LocalFileSystem();
  final DartSDK dartSdk = DartSDK(
    fs: fs,
    processManager: LocalProcessManager(),
    platform: LocalPlatform(),
  );
  final ScriptRunner scriptRunner = ScriptRunner(
    fs: fs,
    dartSdk: dartSdk,
    logger: LocalLogger(),
  );
  await scriptRunner.run(parsedArguments.rest);
  exitCode = scriptRunner.result;
}
