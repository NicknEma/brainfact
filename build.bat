@echo off

REM odin build src -o:speed -out:release/bf.exe -vet -warnings-as-errors
odin build src -debug -o:none -out:debug/bf.exe -vet -warnings-as-errors
