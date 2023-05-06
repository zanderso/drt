# `drt`

A program that runs bare Dart scripts.

# Installation

Clone from github:
```
$ git clone https://github.com/zanderso/drt.git
```

You can then use a helper script to build it and put it on your `PATH`, or
build it manually and do what you like with it.

## Install script

```
$ dart bin/drt.dart utils/install.dart
```

Which will compile `drt` and prompt you to allow editing `.rc` files as
appropriate for your environment.

## Manually

Build directly using the Dart SDK:
```
$ cd drt
$ dart compile exe -o bin/drt bin/drt.dart
# Result in bin/drt
```

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

# How does it work?

First `drt` uses `package:analyzer` to extract `package:` `import` directives
from the input script. In doing so, it traverses `import` directives that
reference other `.dart` files by their absolute or relative paths, like
`import 'src/utils.dart';`.

`drt` then composes a `pubspec.yaml` file in a temporary directory. The
version constraint for every package is specified as `any`. Then, `drt` invokes
`pub`, which resolves and downloads dependencies into the pub package cache and
produces a `package_config.json` file. `drt` caches the `package_config.json`
file next to the input script file to avoid invoking `pub` on subsequent runs
of the script.

Now that dependencies have been resolved, `drt` invokes `dart` to run the
script. In addition, it passes flags to `dart` to cause it to create an
"app-jit" snapshot, which contains some of the native code that `dart` JITs for
the script. The app-jit snapshot is cached next to the script so that
subsequent runs use the precompiled native code.

Notes:
* If the file modification time of the script is newer than either the cached
`package_config.json` or the app-jit snapshot, then they are regenerated.
* `drt` invokes the `dart` subprocess with `ProcessStartMode.inheritStdio`, which
means that the script will use the same `stdout`, `stderr`, and `stdio` file
handles of the `drt` process.
