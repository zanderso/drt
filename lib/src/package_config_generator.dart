// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' show ProcessResult;

import 'package:file/file.dart';
import 'package:package_config/package_config.dart';
import 'package:platform/platform.dart';

import 'dartsdk.dart';

class PackageConfigGenerator {
  PackageConfigGenerator({
    required this.dartSdk,
    required this.fs,
    required this.platform,
    this.offline = false,
  });

  static const String drtPackagesPathVar = 'DRT_PACKAGES_PATH';

  final DartSDK dartSdk;
  final FileSystem fs;
  final Platform platform;
  final bool offline;

  String buildPubspecString(Set<String> packages) {
    final StringBuffer pubspecBuilder = StringBuffer()
      ..writeln('name: script')
      ..writeln('publish_to: none')
      ..writeln('environment:')
      ..writeln("  sdk: '>=3.0.0-0 <4.0.0'")
      ..writeln('dependencies:');
    for (final String import in packages) {
      pubspecBuilder.writeln('  $import: any');
    }

    final Map<String, String> packagesMap = makePackagesMap();
    if (packages.any(packagesMap.containsKey)) {
      pubspecBuilder.writeln();
      pubspecBuilder.writeln('dependency_overrides:');
      for (final String import in packages) {
        if (!packagesMap.containsKey(import)) {
          continue;
        }
        pubspecBuilder.writeln('  $import:');
        pubspecBuilder.writeln('    path: ${packagesMap[import]}');
      }
    }
    return pubspecBuilder.toString();
  }

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

  Future<void> generatePackageConfig(
    String pubspecString,
    File packageConfigFile,
  ) async {
    final Directory tempDir = fs.currentDirectory.createTempSync(
      'drt_',
    );
    try {
      final File pubspecFile =
          fs.file(fs.path.join(tempDir.path, 'pubspec.yaml'));
      pubspecFile.writeAsStringSync(pubspecString);

      final ProcessResult pubGetResult = await dartSdk.runPub(
        <String>['get', if (offline) '--offline'],
        workingDirectory: tempDir.path,
      );
      if (pubGetResult.exitCode != 0) {
        print('pub get failed');
        return;
      }

      final File packageConfigJson = fs.file(fs.path.join(
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

  Map<String, String> makePackagesMap() {
    final String? drtPackagesPath = platform.environment[drtPackagesPathVar];
    if (drtPackagesPath == null) {
      return <String, String>{};
    }

    final List<String> searchPaths = drtPackagesPath.split(':');
    final Map<String, String> packageMap = <String, String>{};
    for (final String p in searchPaths) {
      final Directory dir = fs.directory(p);
      if (!dir.existsSync()) {
        continue;
      }
      for (final Directory subdir in dir.listSync().whereType<Directory>()) {
        final String packageName = fs.path.basename(subdir.path);
        if (!packageMap.containsKey(packageName)) {
          packageMap[packageName] = subdir.absolute.path;
        }
      }
    }

    return packageMap;
  }
}
