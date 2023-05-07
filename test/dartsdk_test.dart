// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' as io;

import 'package:drt/script_runner.dart';
import 'package:file/memory.dart';
import 'package:platform/platform.dart';

import 'src/fake_process_manager.dart';
import 'src/test_wrapper.dart';

void main() {
  group('DartSDK', () {
    late MemoryFileSystem fs;
    late FakeProcessManager fakeProcessManager;

    setUp(() {
      fs = MemoryFileSystem.test();
      fakeProcessManager = FakeProcessManager.empty();
    });

    test('FakeProcessManager canRun "dart"', () {
      final DartSDK dartSdk = DartSDK(
        fs: fs,
        processManager: fakeProcessManager,
        platform: FakePlatform(),
      );
      // FakeProcessManager returns true for `canRun` unless instructed
      // otherwise.
      expect(dartSdk.dartExe, isNotNull);
    });

    test('dartExe is non-null when it can be found from the platform', () {
      final String exePath = fs.path.join('path', 'to', 'dartaotruntime');
      final String dartPath = fs.path.join('path', 'to', 'dart');
      fs.file(exePath).createSync(recursive: true);
      fs.file(dartPath).createSync(recursive: true);

      fakeProcessManager.excludedExecutables = <String>{'dart'};

      final DartSDK dartSdk = DartSDK(
        fs: fs,
        processManager: fakeProcessManager,
        platform: FakePlatform(executable: exePath),
      );

      // FakeProcessManager returns true for `canRun` unless instructed
      // otherwise.
      expect(dartSdk.dartExe, equals(dartPath));
    });

    test(
        'dartExe is non-null when it can be found from the platform with an extension',
        () {
      final String exePath = fs.path.join('path', 'to', 'dartaotruntime.exe');
      final String dartPath = fs.path.join('path', 'to', 'dart.exe');
      fs.file(exePath).createSync(recursive: true);
      fs.file(dartPath).createSync(recursive: true);

      fakeProcessManager.excludedExecutables = <String>{'dart'};

      final DartSDK dartSdk = DartSDK(
        fs: fs,
        processManager: fakeProcessManager,
        platform: FakePlatform(executable: exePath),
      );

      // FakeProcessManager returns true for `canRun` unless instructed
      // otherwise.
      expect(dartSdk.dartExe, equals(dartPath));
    });

    test('verifyDartVersion succeeds when the version string is good', () {
      final DartSDK dartSdk = DartSDK(
        fs: fs,
        processManager: fakeProcessManager,
        platform: FakePlatform(version: '3.1.0-56.0.dev'),
      );
      expect(dartSdk.verifyDartVersion(), equals((true, null)));
    });

    test('verifyDartVersion fails when the version string is malformed', () {
      final DartSDK dartSdk = DartSDK(
        fs: fs,
        processManager: fakeProcessManager,
        platform: FakePlatform(version: 'a.1.0-56.0.dev'),
      );
      final (bool, String?) result = dartSdk.verifyDartVersion();
      expect(result.$1, isFalse);
      expect(result.$2, isNotNull);
    });

    test('verifyDartVersion fails when the version string is too low', () {
      final DartSDK dartSdk = DartSDK(
        fs: fs,
        processManager: fakeProcessManager,
        platform: FakePlatform(version: '2.1.0-56.0.dev'),
      );
      final (bool, String?) result = dartSdk.verifyDartVersion();
      expect(result.$1, isFalse);
      expect(result.$2, isNotNull);
    });

    test('runDart does something reasonable', () async {
      fakeProcessManager.addCommand(const FakeCommand(
        command: <String>['dart', 'run', 'some_script.dart'],
      ));
      final DartSDK dartSdk = DartSDK(
        fs: fs,
        processManager: fakeProcessManager,
        platform: FakePlatform(),
      );
      final int result = await dartSdk.runDart(<String>[
        'run',
        'some_script.dart',
      ]);
      expect(result, equals(0));
    });

    test('runPub does something reasonable', () async {
      fakeProcessManager.addCommand(const FakeCommand(
        command: <String>['dart', 'pub', 'get'],
      ));
      final DartSDK dartSdk = DartSDK(
        fs: fs,
        processManager: fakeProcessManager,
        platform: FakePlatform(),
      );
      final io.ProcessResult result = await dartSdk.runPub(<String>['get']);
      expect(result.exitCode, equals(0));
    });

    test('runPub plumbs the working directory', () async {
      const String workingDirectory = 'working_directory';
      fakeProcessManager.addCommand(const FakeCommand(
        command: <String>['dart', 'pub', 'get'],
        workingDirectory: workingDirectory,
      ));
      final DartSDK dartSdk = DartSDK(
        fs: fs,
        processManager: fakeProcessManager,
        platform: FakePlatform(),
      );
      final io.ProcessResult result = await dartSdk.runPub(
        <String>['get'],
        workingDirectory: workingDirectory,
      );
      expect(result.exitCode, equals(0));
    });
  });
}
