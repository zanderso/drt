// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:path/path.dart' as path;

void main(List<String> arguments) {
  final ArgParser argParser = ArgParser();
  final ArgResults parsedArguments = argParser.parse(arguments);
  for (final String arg in parsedArguments.rest) {
    print(path.join('arg', arg));
  }
  io.exitCode = 0;
}
