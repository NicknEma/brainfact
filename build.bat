@echo off

rc /nologo res/resources.rc

if not exist debug mkdir debug
del debug/bf.pdb > NUL 2> NUL
odin build src -debug -o:none -out:debug/bf.exe -vet -warnings-as-errors -extra-linker-flags:"res/resources.res /map:debug/bf.map"
del res/resources.res > NUL 2> NUL
