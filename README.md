<p align="center">
	<img src="assets/Brainfact.png" alt="Brainfact logo." style="width:25%">
</p>

# Brainfact
A brainfuck interpreter and brainfuck–to–C transpiler written in Odin.

## What is brainfuck?
[Brainfuck](https://en.wikipedia.org/wiki/Brainfuck) is an esoteric programming language created in 1993 by Urban Müller.
A program written in it looks like this:

```
+[-->-[>>+>-----<<]<--<---]>-.>>>+.>>..+++[.>]<<<<.+++.------.<<-.>>>>+.
```

This program prints `Hello, World!`.

## Why did I do this?
- To practice programming in odin.
- To build an interpreter/compiler without getting distracted by all the parsing theory and predefined structures that are easy to self–impose when thinking about a “regular” programming language.

## Build
### Windows
- Make sure you have [Visual Studio](https://learn.microsoft.com/en-us/visualstudio/install/install-visual-studio?view=vs-2022) installed on your device.
- Install the [Odin compiler](https://github.com/odin-lang/Odin) and [add its location to the `path`](https://www.computerhope.com/issues/ch000549.htm) environment variable.
- Either start a [64–bit developer command prompt](https://learn.microsoft.com/en-us/visualstudio/ide/reference/command-prompt-powershell?view=vs-2022) or start a regular command prompt and run `vcvars64.bat`.
- Run `build.bat` or `build_release.bat`.
### Linux
- Install the [Odin compiler](https://github.com/odin-lang/Odin).
- Run `build.sh` or `build_release.sh`.

## Use
- Run it on a brainfuck source file to interpret it. It will only run the first argument and ignore every other file. The _examples_ folder contains a bunch of brainfuck source files you can try to run.
- Run it with `-build` to compile the argument instead of running it (see below how the compilation is implemented). You can optionally pass in another file name which will be used as the output name.
- Run it with `-help` to see what you can do with it.

## Notes
The `-build` compiles the Brainfuck source by generating a C implementation and then invoking a C compiler on it.
The C compiler is not shipped with this program.
Instead, the program hopes to find a C compiler on the current machine.
It is currently hardcoded to look for `cl` on Windows and `clang` on Linux.

Both the interpreter and the compiler use a “wrap–around” strategy when moving the data pointer out of bounds.
The allocated space is of 30.000 bytes, and going off one end wraps you back to the other side.
