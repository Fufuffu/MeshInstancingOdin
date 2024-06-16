@echo off

odin build game -show-timings -define:RAYLIB_SHARED=true -define:DEV_BUILD=true -build-mode:dll -out:game.dll -vet-using-stmt -vet-using-param -vet-style -vet-semicolon -strict-style -debug