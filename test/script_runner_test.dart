// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:drt/script_runner.dart';
import 'package:file/memory.dart';
import 'package:platform/platform.dart';

import 'src/fake_process_manager.dart';
import 'src/test_wrapper.dart';

class BufferLogger implements Logger {
  List<String> logs = <String>[];
  List<String> errors = <String>[];

  @override
  void printLog(String message) => logs.add(message);

  @override
  void printError(String message) => errors.add(message);
}

void main() {
  group('ScriptRunner', () {
    late MemoryFileSystem fs;
    late FakeProcessManager fakeProcessManager;

    setUp(() {
      fs = MemoryFileSystem.test();
      fakeProcessManager = FakeProcessManager.empty();
    });

    test('runs normally without snapshot or package config', () async {
      final String script = '/script.dart';
      final String scriptContents = '''
        import 'package:process/process.dart';

        void main() {}
      ''';
      final String appJitSnapshotPath = '/.script.jit';
      final String packageConfigPath = '/.script.package_config.json';
      final String tempDirPath = '/drt_rand0';
      fakeProcessManager.addCommands(<FakeCommand>[
        FakeCommand(
          command: <String>['dart', 'pub', 'get'],
          workingDirectory: tempDirPath,
          onRun: () {
            final String packageConfigPath = fs.path.join(
              tempDirPath,
              '.dart_tool',
              'package_config.json',
            );
            fs.file(packageConfigPath).createSync(recursive: true);
          },
        ),
        FakeCommand(
          command: <String>[
            'dart',
            '--disable-dart-dev',
            '--snapshot-kind=app-jit',
            '--snapshot=$appJitSnapshotPath',
            '--packages=$packageConfigPath',
            script,
          ],
          onRun: () {
            fs.file(appJitSnapshotPath).createSync(recursive: true);
          },
        ),
      ]);

      fs.file(script)
        ..createSync(recursive: true)
        ..writeAsStringSync(scriptContents);

      final Platform platform = FakePlatform(
        version: '3.1.0-56.0.dev',
        environment: <String, String>{},
      );
      final DartSDK dartSdk = DartSDK(
        fs: fs,
        processManager: fakeProcessManager,
        platform: platform,
      );
      final ScriptRunner scriptRunner = ScriptRunner(
        fs: fs,
        dartSdk: dartSdk,
        logger: BufferLogger(),
        platform: platform,
      );

      await scriptRunner.run(<String>[script]);

      expect(scriptRunner.result, equals(0));
      expect(fs.file(appJitSnapshotPath).existsSync(), isTrue);
    });

    test('runs normally with a snapshot', () async {
      final String script = '/script.dart';
      final String appJitSnapshotPath = '/.script.jit';
      fakeProcessManager.addCommands(<FakeCommand>[
        FakeCommand(
          command: <String>[
            'dart',
            appJitSnapshotPath,
          ],
        ),
      ]);

      fs.file(script).createSync(recursive: true);
      fs.file(appJitSnapshotPath).createSync(recursive: true);

      final Platform platform = FakePlatform(version: '3.1.0-56.0.dev');
      final DartSDK dartSdk = DartSDK(
        fs: fs,
        processManager: fakeProcessManager,
        platform: platform,
      );
      final ScriptRunner scriptRunner = ScriptRunner(
        fs: fs,
        dartSdk: dartSdk,
        logger: BufferLogger(),
        platform: platform,
      );

      await scriptRunner.run(<String>[script]);

      expect(scriptRunner.result, equals(0));
    });
  });
}
