// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' as io;
import 'dart:isolate';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:platform/platform.dart';
import 'package:process/process.dart';

void cleanupDirectory(Directory dir) {
  for (final File f in dir.listSync().whereType<File>()) {
    if (f.path.endsWith('.jit') || f.path.endsWith('.json')) {
      f.deleteSync();
    }
  }
}

String userHomePath(Platform platform) {
  final String envKey = platform.isWindows ? 'APPDATA' : 'HOME';
  return platform.environment[envKey] ?? '.';
}

void maybeAppendStringToFile(
  File file,
  String string, {
  required String guard,
  required String prompt,
  required String instruction,
}) {
  if (!file.existsSync()) {
    return;
  }

  final String contents = file.readAsStringSync();
  if (contents.contains(guard)) {
    return;
  }

  io.stdout.write(prompt);
  final String? response = io.stdin.readLineSync();
  if (response == null || (response != 'Y' && response != 'y')) {
    return;
  }

  file.copySync('${file.path}.bak');
  file.writeAsStringSync(string, mode: io.FileMode.append);
  io.stdout.writeln('Backup written to "${file.path}.bak"');
  io.stdout.writeln(instruction);
}

void main() async {
  final FileSystem fs = LocalFileSystem();
  final Platform platform = LocalPlatform();
  final ProcessManager pm = LocalProcessManager();
  final String dart = platform.executable;
  final String packageConfigPath = (await Isolate.packageConfig)!.path;
  final Directory packageRoot = fs.file(packageConfigPath).parent.parent;
  final Directory binDirectory = packageRoot.childDirectory('bin');
  final Directory outDirectory = packageRoot.childDirectory('out');
  final File binDrt = binDirectory.childFile('drt.dart');
  final File drtExe = outDirectory.childFile('drt');

  outDirectory.createSync();
  final io.ProcessResult result = await pm.run(<String>[
    dart,
    'compile',
    'exe',
    '-o',
    drtExe.path,
    binDrt.path,
  ]);
  if (result.exitCode != 0) {
    io.stderr.writeln('Build failure:\n${result.stdout}\n${result.stderr}');
    io.exitCode = 1;
    return;
  }

  final Directory home = fs.directory(userHomePath(platform));
  final File dotBashRc = home.childFile('.bashrc');
  final File dotZshRc = home.childFile('.zshrc');

  final StringBuffer buffer = StringBuffer();
  buffer.writeln();
  buffer.writeln('# >>> drt PATH setup');
  buffer.writeln('export PATH="\$PATH:${outDirectory.path}"');
  buffer.writeln('# <<< drt PATH setup');

  maybeAppendStringToFile(
    dotBashRc,
    buffer.toString(),
    guard: 'drt PATH setup',
    prompt: 'Modify .bashrc to set PATH? (Y/N): ',
    instruction: 'Now, run: source ~/.bashrc',
  );
  maybeAppendStringToFile(
    dotZshRc,
    buffer.toString(),
    guard: 'drt PATH setup',
    prompt: 'Modify .zshrc to set PATH? (Y/N): ',
    instruction: 'Now, run: source ~/.zshrc',
  );
}
