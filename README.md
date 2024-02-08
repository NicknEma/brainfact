# Brainfact
A brainfuck interpreter and compiler (to C transpiler) written in odin.

## What is brainfuck?
[Brainfuck](https://en.wikipedia.org/wiki/Brainfuck) is an esoteric programming language created in 1993 by Urban Müller. It looks like this:

```
+[-->-[>>+>-----<<]<--<---]>-.>>>+.>>..+++[.>]<<<<.+++.------.<<-.>>>>+.
```

The above program prints `Hello, World!`.

## Why did I do this?
- To practice programming in odin.
- To build an interpreter/compiler without getting distracted by all the parsing theory and predefined structures that are easy to self-impose when thinking about a "regular" programming language.

## Build
#### Windows
- Setup your developement environment:
- Start a "developer command prompt", or
- Start a regular command prompt and run `vcvars64.bat`.
- Run `build.bat`.
- Done.

## Use
- Run `bf.exe -help` to see what you can do with it.

## Notes
Both the interpreter and the compiler use a "wrap-around" strategy when moving the data pointer out of bounds. The allocated space is of 30.000 bytes, and going off one end wraps you back to the other side.

The compiler is actually just a "C-front": it generates a C file and then calls out to Visual Studio.
