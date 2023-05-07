// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:drt/script_runner.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:platform/platform.dart';

import 'src/fake_process_manager.dart';
import 'src/test_wrapper.dart';

void main() {
  group('PackageConfigGenerator', () {
    late MemoryFileSystem fs;
    late FakeProcessManager fakeProcessManager;
    late Platform platform;

    setUp(() {
      fs = MemoryFileSystem.test();
      fakeProcessManager = FakeProcessManager.empty();
      platform = FakePlatform(environment: <String, String>{});
    });

    test('can build pubspec.yaml string', () {
      final DartSDK dartSdk = DartSDK(
        fs: fs,
        processManager: fakeProcessManager,
        platform: platform,
      );
      final PackageConfigGenerator generator = PackageConfigGenerator(
        dartSdk: dartSdk,
        fs: fs,
        platform: platform,
      );
      final String pubspec = generator.buildPubspecString(<String>{'analyzer'});
      expect(pubspec, contains('dependencies:\n  analyzer: any'));
    });

    test('can generate package config from pubspec', () async {
      final String tempDirPath = '/drt_rand0';
      final String packageConfigContents = 'package config contents';
      fakeProcessManager.addCommand(FakeCommand(
        command: <String>['dart', 'pub', 'get'],
        workingDirectory: tempDirPath,
        onRun: () {
          final String packageConfigPath = fs.path.join(
            tempDirPath,
            '.dart_tool',
            'package_config.json',
          );
          fs.file(packageConfigPath)
            ..createSync(recursive: true)
            ..writeAsStringSync(packageConfigContents);
        },
      ));

      final DartSDK dartSdk = DartSDK(
        fs: fs,
        processManager: fakeProcessManager,
        platform: platform,
      );
      final PackageConfigGenerator generator = PackageConfigGenerator(
        dartSdk: dartSdk,
        fs: fs,
        platform: platform,
      );
      final String pubspec = generator.buildPubspecString(<String>{'analyzer'});
      final File packageConfigFile = fs.file('package_config_file');
      await generator.generatePackageConfig(pubspec, packageConfigFile);
      expect(
        packageConfigFile.readAsStringSync(),
        equals(packageConfigContents),
      );
    });

    test('uses existing package config file when possible', () async {
      final String packageConfigContents = '''{
  "configVersion": 2,
  "packages": [
    {
      "name": "args",
      "rootUri": "file:///Users/zra/.pub-cache/hosted/pub.dev/args-2.4.1",
      "packageUri": "lib/",
      "languageVersion": "2.18"
    },
    {
      "name": "path",
      "rootUri": "file:///Users/zra/.pub-cache/hosted/pub.dev/path-1.8.3",
      "packageUri": "lib/",
      "languageVersion": "2.12"
    },
    {
      "name": "script",
      "rootUri": "../",
      "packageUri": "lib/",
      "languageVersion": "3.0"
    }
  ],
  "generated": "2023-05-04T01:38:42.045701Z",
  "generator": "pub",
  "generatorVersion": "3.1.0-56.0.dev"
}''';
      final String packageConfigPath = fs.path.join(
        '/path',
        'to',
        'package_config.json',
      );
      fs.file(packageConfigPath)
        ..create(recursive: true)
        ..writeAsStringSync(packageConfigContents);

      final DartSDK dartSdk = DartSDK(
        fs: fs,
        processManager: fakeProcessManager,
        platform: platform,
      );
      final PackageConfigGenerator generator = PackageConfigGenerator(
        dartSdk: dartSdk,
        fs: fs,
        platform: platform,
      );
      // This will try to call 'pub' and fail if the fast path check fails
      // because 'dart pub get' won't be in the fakePackageManager.
      await generator.ensurePackageConfig(
        <String>{'args', 'path', 'script'},
        packageConfigPath,
      );
    });

    test(
        'falls back on pub when an existing package config is missing something',
        () async {
      final String packageConfigContents = '''{
  "configVersion": 2,
  "packages": [
    {
      "name": "args",
      "rootUri": "file:///Users/zra/.pub-cache/hosted/pub.dev/args-2.4.1",
      "packageUri": "lib/",
      "languageVersion": "2.18"
    },
    {
      "name": "path",
      "rootUri": "file:///Users/zra/.pub-cache/hosted/pub.dev/path-1.8.3",
      "packageUri": "lib/",
      "languageVersion": "2.12"
    },
    {
      "name": "script",
      "rootUri": "../",
      "packageUri": "lib/",
      "languageVersion": "3.0"
    }
  ],
  "generated": "2023-05-04T01:38:42.045701Z",
  "generator": "pub",
  "generatorVersion": "3.1.0-56.0.dev"
}''';
      final String packageConfigPath = fs.path.join(
        '/path',
        'to',
        'package_config.json',
      );
      final File packageConfigFile = fs.file(packageConfigPath)
        ..create(recursive: true)
        ..writeAsStringSync(packageConfigContents);

      final String tempDirPath = '/drt_rand0';
      final String newPackageConfigContents = 'package config contents';
      fakeProcessManager.addCommand(FakeCommand(
        command: <String>['dart', 'pub', 'get'],
        workingDirectory: tempDirPath,
        onRun: () {
          final String packageConfigPath = fs.path.join(
            tempDirPath,
            '.dart_tool',
            'package_config.json',
          );
          fs.file(packageConfigPath)
            ..createSync(recursive: true)
            ..writeAsStringSync(newPackageConfigContents);
        },
      ));

      final DartSDK dartSdk = DartSDK(
        fs: fs,
        processManager: fakeProcessManager,
        platform: platform,
      );
      final PackageConfigGenerator generator = PackageConfigGenerator(
        dartSdk: dartSdk,
        fs: fs,
        platform: platform,
      );
      // This will try to call 'pub' and fail if the fast path check fails
      // because 'dart pub get' won't be in the fakePackageManager.
      await generator.ensurePackageConfig(
        <String>{'analyzer', 'args', 'path', 'script'},
        packageConfigPath,
      );
      expect(
        packageConfigFile.readAsStringSync(),
        equals(newPackageConfigContents),
      );
    });
  });

  group('PackageConfigGenerator with path overrides', () {
    late MemoryFileSystem fs;
    late FakeProcessManager fakeProcessManager;
    late Platform platform;
    late String packagesPath;

    setUp(() {
      fs = MemoryFileSystem.test();
      packagesPath = fs.path.join('/path', 'to', 'packages');
      fs.directory(packagesPath).createSync(recursive: true);
      fs.directory(packagesPath).childDirectory('args').createSync();
      fs.directory(packagesPath).childDirectory('file').createSync();
      fs.directory(packagesPath).childDirectory('path').createSync();

      fakeProcessManager = FakeProcessManager.empty();
      platform = FakePlatform(environment: <String, String>{
        PackageConfigGenerator.drtPackagesPathVar: packagesPath,
      });
    });

    test('finds packages using the packages path', () {
      final DartSDK dartSdk = DartSDK(
        fs: fs,
        processManager: fakeProcessManager,
        platform: platform,
      );
      final PackageConfigGenerator generator = PackageConfigGenerator(
        dartSdk: dartSdk,
        fs: fs,
        platform: platform,
      );

      Map<String, String> packagesMap = generator.makePackagesMap();

      expect(
          packagesMap,
          equals(<String, String>{
            'args': fs.path.join(packagesPath, 'args'),
            'file': fs.path.join(packagesPath, 'file'),
            'path': fs.path.join(packagesPath, 'path'),
          }));
    });

    test('', () {
      final DartSDK dartSdk = DartSDK(
        fs: fs,
        processManager: fakeProcessManager,
        platform: platform,
      );
      final PackageConfigGenerator generator = PackageConfigGenerator(
        dartSdk: dartSdk,
        fs: fs,
        platform: platform,
      );

      final String pubspec = generator.buildPubspecString(<String>{
        'args',
        'file',
      });

      expect(pubspec, contains('dependency_overrides:'));
      expect(
        pubspec,
        contains('  args:\n    path: ${fs.path.join(packagesPath, "args")}'),
      );
      expect(
        pubspec,
        contains('  file:\n    path: ${fs.path.join(packagesPath, "file")}'),
      );
    });
  });
}
