# Drt

A program that runs bare Dart scripts.

# Background

It's convenient to be able to whip up Python scripts quickly, and run them
immediately.
```
$ touch script.py
$ vim script.py  # edit edit edit
$ python3 script.py
```

In Dart there's a bit more setup involved. Dart's tooling reduces the manual
setup overhead quite a bit.
```
$ dart create my_new_dart_thing
$ cd my_new_dart_thing
$ vim pubspec.yaml  # Bring in some dependencies
$ vim lib/my_new_dart_thing.dart  # edit edit edit
$ vim bin/my_new_dart_thing.dart  # edit edit edit
$ dart run bin/my_new_dart_thing.dart
```
I suspect there's even less typing if you use an IDE to help get set up.

# Overview

This package aims to give a more Python-y, script-y experience for Dart. It does
this with some straightforward wrappers around the Dart SDK tooling. With this
package you can do:
```
arg_echo.dart
```
```dart
import 'package:args/args.dart';
import 'package:path/path.dart' as path;

void main(List<String> arguments) {
  final ArgParser argParser = ArgParser();
  final ArgResults parsedArguments = argParser.parse(arguments);
  for (final String arg in parsedArguments.rest) {
    print(path.join('arg', arg));
  }
}
```
```
$ drt arg_echo.dart a b c
arg/a
arg/b
arg/c
```

And not worry about setting up a directory structure, editing the `pubspec.yaml`
etc.. That is you type in some Dart code, and then you're running.

## Why not just use DartPad?

As an alternative to Python scripts that inspect the local file system, DartPad
isn't a real replacement for that.

## Why not just use an IDE that makes Dart more convenient?

Sorry, I'm a dinosaur. IDEs drive me crazy.
