// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' show Process, ProcessResult, ProcessStartMode;

import 'package:file/file.dart';
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
