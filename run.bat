@echo off
title Handheld Quick Settings (Flutter Windows)
cd /d "%~dp0"

set "EXE_PATH=build\windows\x64\runner\Release\windows_handheld_tool.exe"

if exist "%EXE_PATH%" (
    echo [*] Dang khoi dong Handheld Quick Settings Release...
    start "" "%EXE_PATH%"
    exit
)

echo [*] Dang khoi dong Handheld Quick Settings qua Flutter...
flutter run -d windows
