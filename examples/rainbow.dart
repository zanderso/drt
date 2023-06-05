// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:chalkdart/chalk.dart';

void main() {
  // Get the width and height of the terminal.
  var width = stdout.terminalColumns;
  var height = stdout.terminalLines;

  // Draw the rainbow.
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      // Calculate the color of the pixel.
      double hue = (x / width) * 360;

      // Print the pixel.
      stdout.write(chalk.onHsl(hue, 100, 50)(' '));
    }
    stdout.writeln();
  }
}
