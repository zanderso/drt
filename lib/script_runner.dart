// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' as io show exitCode, stdout;

import 'package:args/args.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:platform/platform.dart';
import 'package:process/process.dart';

import 'src/dartsdk.dart';
import 'src/import_extractor.dart';
import 'src/package_config_generator.dart';

export 'src/dartsdk.dart';
export 'src/import_extractor.dart';
export 'src/package_config_generator.dart';

abstract class Logger {
  void printLog(String message);

  void printError(String message);
}

class LocalLogger implements Logger {
  const LocalLogger();

  @override
  void printLog(String message) => io.stdout.writeln(message);

  @override
  void printError(String message) => io.stdout.writeln('ERROR: $message');
}

class ScriptRunner {
  ScriptRunner({
    required this.fs,
    required this.dartSdk,
    required this.logger,
    required this.platform,
    this.offline = false,
    this.analyze = false,
  });

  final FileSystem fs;
  final DartSDK dartSdk;
  final Logger logger;
  final Platform platform;
  final bool offline;
  final bool analyze;

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
    final String packageConfigPath = await getPackageConfig(script);

    if (analyze) {
      await dartSdk.runDart(<String>[
        'analyze',
        '--packages=$packageConfigPath',
        script,
      ]);
    } else {
      final String appJitSnapshotPath = fs.path.join(
        fs.path.dirname(script),
        '.${fs.path.basenameWithoutExtension(script)}.jit',
      );
      _result = await dartSdk.runDart(<String>[
        '--disable-dart-dev',
        '--snapshot-kind=app-jit',
        '--snapshot=$appJitSnapshotPath',
        '--packages=$packageConfigPath',
        script,
        if (arguments.length > 1) ...arguments.sublist(1),
      ]);
    }
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
      await PackageConfigGenerator(
        fs: fs,
        dartSdk: dartSdk,
        platform: platform,
        offline: offline,
      ).ensurePackageConfig(packages, packageConfigPath);
    }

    return packageConfigPath;
  }
}

Future<void> main(List<String> arguments) async {
  final ArgParser argParser = ArgParser(allowTrailingOptions: false);
  argParser.addFlag(
    'analyze',
    abbr: 'a',
    negatable: false,
    help: 'Run the analyzer on the script instead of running it.',
  );
  argParser.addFlag(
    'help',
    abbr: 'h',
    negatable: false,
    help: 'Print help for this command.',
  );
  argParser.addFlag(
    'offline',
    negatable: false,
    help: 'Pass --offline to pub',
  );
  final ArgResults parsedArguments = argParser.parse(arguments);
  if (parsedArguments['help'] as bool? ?? false) {
    io.stdout.writeln('This program runs standalone Dart scripts.');
    io.stdout.writeln(
        'usage: drt [drt options] path/to/script.dart [script arguments]');
    io.stdout.writeln(argParser.usage);
    io.exitCode = 1;
    return;
  }

  const FileSystem fs = LocalFileSystem();
  final DartSDK dartSdk = DartSDK(
    fs: fs,
    processManager: const LocalProcessManager(),
    platform: const LocalPlatform(),
  );
  final ScriptRunner scriptRunner = ScriptRunner(
    fs: fs,
    dartSdk: dartSdk,
    logger: const LocalLogger(),
    platform: const LocalPlatform(),
    offline: parsedArguments['offline'] as bool? ?? false,
    analyze: parsedArguments['analyze'] as bool? ?? false,
  );
  await scriptRunner.run(parsedArguments.rest);
  io.exitCode = scriptRunner.result;
}
