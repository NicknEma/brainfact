@echo off

rc /nologo res/resources.rc

odin build src -o:speed -out:bf.exe -vet -warnings-as-errors -extra-linker-flags:res/resources.res
del res/resources.res > NUL 2> NUL
