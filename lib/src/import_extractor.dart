// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:file/file.dart';

class ImportVisitor extends RecursiveAstVisitor<void> {
  ImportVisitor({required this.fs, required this.scriptPath});

  final FileSystem fs;
  final String scriptPath;
  final Set<String> packageImports = <String>{};
  final Set<String> fsImports = <String>{};

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
      final (Set<String>, Set<String>) imports = _getPackages(script);
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
