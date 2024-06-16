@echo off
odin build main -define:RAYLIB_SHARED=true -out:main.exe -strict-style -vet-using-stmt -vet-using-param -vet-style -vet-semicolon -debug
copy G:\OdinProjects\Odin\vendor\raylib\windows\raylib.dll .