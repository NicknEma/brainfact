@echo off

rc /nologo res/resources.rc

if not exist debug mkdir debug
odin build src -debug -o:none -out:debug/bf_debug.exe -vet -warnings-as-errors -extra-linker-flags:"res/resources.res /map:debug/bf_debug.map"
del res/resources.res > NUL 2> NUL
