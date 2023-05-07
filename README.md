# `drt`

`drt` is a program that runs bare Dart scripts without the need for a package,
`pubspec.yaml`, and other boilerplate.

## Installation

Clone from github:
```bash
$ git clone https://github.com/zanderso/drt.git
```

You can then either run `utils/install.dart` to build it and put it on your
`PATH`, or build it manually and do what you like with it.

### Install script

After clonging:
```bash
$ cd drt
$ dart pub get
$ dart utils/install.dart
```

This will compile `drt` to a standlone binary and prompt you to allow editing
`rc` files in your home directory as appropriate for your environment.

### Manually

Build directly using the Dart SDK:
```bash
$ cd drt
$ dart compile exe -o bin/drt bin/drt.dart
# Result in bin/drt
```

## Usage

`drt` can run Dart programs that have both `package:` and file system path
`import`s from the command line.

### Basic usage

Suppose you have a Dart file `arg_echo.dart`:
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

Then with `drt` you can run it like so:
```bash
$ drt arg_echo.dart a b c
arg/a
arg/b
arg/c
```

Without worrying about creating a new package, setting up a `pubspec.yaml`, etc.

### shebang

On Linux and macOS, if `drt` is on your path, then a file whose first line is:
```dart
#!/usr/bin/env drt
```
can be run directly, like:
```bash
$ ./arg_echo.dart
arg/a
arg/b
arg/c
```

As long as the file `arg_echo.dart` is marked executable.
```bash
$ chmod +x arg_echo.dart
```

### `--offline`

When the flag `--offline` is passed to `drt`, `pub` will not touch the network
when resolving package dependencies. If a dependency is not already in `pub`'s
cache, the script will fail to run.

### `DRT_PACKAGE_PATH`

If the environment variable `DRT_PACKAGE_PATH` is set to a list of `:`-separated
paths, those paths will be searched for packages. When found, the first
isntance of a package from the search paths will be used as a dependency
override instead of a version pulled form `pub`.

### `--analyze`

When the flag `--analyze` is passed to `drt`, the script will be analyzed
with default analyzer options instead of running it.

## Background

It's convenient to be able to whip up Python scripts quickly, and run them
immediately.
```bash
$ touch script.py
$ vim script.py  # edit edit edit
$ python3 script.py
```

In Dart there's a bit more setup involved.
```bash
$ dart create my_new_dart_thing
$ cd my_new_dart_thing
$ vim pubspec.yaml  # Bring in some dependencies
$ vim lib/my_new_dart_thing.dart  # edit edit edit
$ vim bin/my_new_dart_thing.dart  # edit edit edit
$ dart run bin/my_new_dart_thing.dart
```
I suspect there's even less typing if you use an IDE to help get set up.

## How does it work?

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
