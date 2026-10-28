@echo off
setlocal enabledelayedexpansion
title Windows Handheld Tool - Clean Build Artifacts

:: Self-elevate: artifacts created by an elevated PyInstaller run are owned by
:: Administrators, so a standard user shell cannot delete them.
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [*] Requesting Administrator privileges to clean build artifacts...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\" %*\"' -Verb RunAs"
    exit /b
)

set "PROJECT_ROOT=%~dp0..\.."

echo [*] Cleaning build artifacts...
for %%D in ("%PROJECT_ROOT%\build" "%PROJECT_ROOT%\dist") do (
    if exist %%D (
        echo     - %%~fD
        rmdir /S /Q %%D
        if exist %%D (
            echo [!] Could not remove %%~fD ^(in use by another process^)
        )
    )
)
echo [OK] Build artifacts cleaned.
endlocal
exit /b 0
