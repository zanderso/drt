// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io' as io;
import 'dart:isolate';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:platform/platform.dart';
import 'package:process/process.dart';

import 'src/test_wrapper.dart';

void cleanupDirectory(Directory dir) {
  for (final File f in dir.listSync().whereType<File>()) {
    if (f.path.endsWith('.jit') || f.path.endsWith('.json')) {
      f.deleteSync();
    }
  }
}

Future<void> main() async {
  final FileSystem fs = LocalFileSystem();
  final Platform platform = LocalPlatform();
  final ProcessManager pm = LocalProcessManager();
  final String dart = platform.executable;
  final String packageConfigPath = (await Isolate.packageConfig)!.path;
  final Directory packageRoot = fs.file(packageConfigPath).parent.parent;
  final Directory libDirectory = packageRoot.childDirectory('lib');
  final Directory binDirectory = packageRoot.childDirectory('bin');

  final File binDrt = binDirectory.childFile('drt.dart');
  final File libScriptRunner = libDirectory.childFile('script_runner.dart');
  final File drtExe = binDirectory.childFile('drt.exe');

  final io.ProcessResult result = await pm.run(<String>[
    dart,
    'compile',
    'exe',
    binDrt.path,
  ]);
  if (result.exitCode != 0) {
    print('Failed to compile to exe:\n${result.stdout}\n${result.stderr}');
    io.exitCode = 1;
    return;
  }

  final Directory testDirectory = packageRoot.childDirectory('test');
  final Directory scriptsDirectory = testDirectory.childDirectory('scripts');

  // Cleanup.
  setUp(() {
    cleanupDirectory(scriptsDirectory);
  });
  tearDown(() {
    cleanupDirectory(scriptsDirectory);
  });

  test('Run a script', () async {
    final File echoScriptFile = scriptsDirectory.childFile(
      'echo_arguments.dart',
    );
    final io.ProcessResult echoResult = await pm.run(<String>[
      drtExe.path,
      echoScriptFile.path,
      'a',
      'b',
      'c',
      'd',
    ]);

    // The script emits the correct results.
    expect(echoResult.exitCode, equals(0));
    expect(echoResult.stdout, equals('arg/a\narg/b\narg/c\narg/d\n'));

    // The package config and app-jit snapshot are created.
    expect(
      scriptsDirectory.childFile('.echo_arguments.jit').existsSync(),
      isTrue,
    );
    expect(
      scriptsDirectory
          .childFile(
            '.echo_arguments.package_config.json',
          )
          .existsSync(),
      isTrue,
    );
  });

  test('Run a script twice', () async {
    final File echoScriptFile = scriptsDirectory.childFile(
      'echo_arguments.dart',
    );
    io.ProcessResult echoResult = await pm.run(<String>[
      drtExe.path,
      echoScriptFile.path,
      'a',
      'b',
      'c',
      'd',
    ]);

    expect(echoResult.exitCode, equals(0));
    expect(echoResult.stdout, equals('arg/a\narg/b\narg/c\narg/d\n'));

    // A second run produces the right results as well.
    echoResult = await pm.run(<String>[
      drtExe.path,
      echoScriptFile.path,
      'a',
      'b',
      'c',
      'd',
    ]);

    // The script emits the correct results.
    expect(echoResult.stdout, equals('arg/a\narg/b\narg/c\narg/d\n'));
  });

  test('Stdin/out are plumbed correctly', () async {
    final File echoScriptFile = scriptsDirectory.childFile('echo_stdin.dart');
    io.Process process = await pm.start(<String>[
      drtExe.path,
      echoScriptFile.path,
    ]);
    process.stdin.writeln('hello');
    process.stdin.writeln('world');
    process.stdin.writeln('quit');

    final StringBuffer stdoutBuffer = StringBuffer();
    late List<String> stdoutLines;
    process.stdout.listen((List<int> data) {
      stdoutBuffer.write(utf8.decode(data));
    }, onDone: () {
      stdoutLines = LineSplitter().convert(stdoutBuffer.toString());
    });

    final StringBuffer stderrBuffer = StringBuffer();
    late String stderrString;
    process.stderr.listen((List<int> data) {
      stderrBuffer.write(utf8.decode(data));
    }, onDone: () {
      stderrString = stderrBuffer.toString();
    });

    final int processResult = await process.exitCode;
    if (processResult != 0) {
      print('stderr: $stderrString');
    }

    expect(stdoutLines, equals(<String>['hello', 'world', 'quit']));
    expect(processResult, equals(0));
  });

  test('The script runner can run itself', () async {
    final File echoScriptFile = scriptsDirectory.childFile(
      'echo_arguments.dart',
    );
    final io.ProcessResult result = await pm.run(<String>[
      drtExe.path,
      libScriptRunner.path,
      echoScriptFile.path,
      'a',
      'b',
      'c',
    ]);
    cleanupDirectory(binDirectory);
    cleanupDirectory(libDirectory);

    if (result.exitCode != 0) {
      print(result.stderr);
      print(result.stdout);
    }

    expect(result.exitCode, equals(0));
    expect(result.stdout, equals('arg/a\narg/b\narg/c\n'));
  });
}
