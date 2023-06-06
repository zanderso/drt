#!/usr/bin/env drt
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' as io;
import 'dart:math';

import 'package:args/args.dart' as args;
import 'package:chalkdart/chalk.dart' as chalk;
import 'package:image/image.dart' as image;

void main(List<String> arguments) {
  final args.ArgParser argParser = args.ArgParser()
    ..addOption('input', abbr: 'i', help: 'Input image');
  final args.ArgResults argResults = argParser.parse(arguments);
  final Options? options = Options.fromArgResults(argResults);
  if (options == null) {
    io.stderr.writeln(argParser.usage);
    io.exitCode = 1;
    return;
  }

  drawImageInTerminal(options.img!);
}

image.Pixel getPixel(image.Image image, double u, double v) =>
    image.getPixel((u * image.width).toInt(), (v * image.height).toInt());

void drawPixelPair(image.Image img, double u, double v1, double v2) {
  const String upperHalfBlock = '\u2580';
  final image.Pixel c1 = getPixel(img, u, v1);
  final image.Pixel c2 = getPixel(img, u, v2);
  final chalk.Chalk chlk =
      chalk.chalk.rgb(c1.r, c1.g, c1.b).onRgb(c2.r, c2.g, c2.b);
  io.stdout.write(chlk(upperHalfBlock));
}

void drawImageInTerminal(image.Image img) {
  final int termWidth = io.stdout.terminalColumns;
  final int termHeight = 2 * (io.stdout.terminalLines - 2);

  final double scale = min(termWidth / img.width, termHeight / img.height);
  final int termImgWidth = (img.width * scale).toInt();
  final int termImgHeight = (img.height * scale).toInt();

  const String upperHalfBlock = '\u2580';
  for (int i = 0; i < termImgHeight - 1; i += 2) {
    final double v1 = i / termImgHeight;
    final double v2 = (i + 1) / termImgHeight;
    for (int j = 0; j < termImgWidth; j++) {
      final double u = j / termImgWidth;
      drawPixelPair(img, u, v1, v2);
    }
    io.stdout.writeln();
  }
}

class Options {
  Options._(this.img);

  final image.Image? img;

  static Options? fromArgResults(args.ArgResults results) {
    if (!results.wasParsed('input')) {
      io.stderr.writeln('Please supply an image with the --input flag.');
      return null;
    }
    final String imgPath = results['input']!;
    final io.File inputFile = io.File(imgPath);
    if (!inputFile.existsSync()) {
      io.stderr.writeln('--input image "$imgPath" does not exist.');
      return null;
    }
    return Options._(image.decodeImage(inputFile.readAsBytesSync()));
  }
}
