// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:drt/script_runner.dart';
import 'package:file/memory.dart';

import 'src/test_wrapper.dart';

void main() {
  group('PackageImportExtractor', () {
    late MemoryFileSystem fs;

    setUp(() {
      fs = MemoryFileSystem.test();
    });

    test('Extracts package imports from a script', () {
      final String scriptContents ='''
        import 'dart:io'
          show exitCode, Process, ProcessResult, ProcessStartMode;

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

        void main() {}
      ''';
      final String scriptPath = fs.path.join('path', 'to', 'script.dart');
      fs.file(scriptPath)..createSync(recursive: true)
                         ..writeAsStringSync(scriptContents);

      final PackageImportExtractor extractor = PackageImportExtractor(
        fs: fs,
      );
      final Set<String> packages = extractor.getPackages(scriptPath);
      final List<String> sortedPackages = List.of(packages)..sort();
      expect(sortedPackages, equals(<String>[
        'analyzer',
        'args',
        'file',
        'package_config',
        'path',
        'platform',
        'process',
      ]));
    });
  });
}
