// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' as io;

void main(List<String> arguments) {
  if (io.stdin.hasTerminal) {
    io.stdin.lineMode = false;
    io.stdin.echoMode = false;
  }
  while (true) {
    final String? input = io.stdin.readLineSync();
    if (input == null) {
      break;
    }
    io.stdout.writeln(input);
    if (input == 'quit') {
      break;
    }
  }
  io.exitCode = 0;
}
