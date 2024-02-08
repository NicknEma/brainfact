@echo off

if not exist debug mkdir debug
del debug/bf.pdb > NUL 2> NUL
odin build src -debug -o:none -out:debug/bf.exe -vet -warnings-as-errors
