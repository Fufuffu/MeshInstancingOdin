tasklist /fi "ImageName eq Main.exe" /fo csv 2>NUL | find /I "main.exe">NUL
IF %ERRORLEVEL% EQU 0 compile_game && call focusOn.bat %cd% && call focusOn.bat "TransparentWindow" && EXIT

compile_game && compile_main && START main.exe game