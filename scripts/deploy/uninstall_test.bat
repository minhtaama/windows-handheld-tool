@echo off
setlocal enabledelayedexpansion
title Windows Handheld Tool - Clean Uninstall Test

:: 1. Check Administrator Privileges (UAC Elevation)
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [*] Requesting Administrator privileges to uninstall and clean up application...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\" %*\"' -Verb RunAs"
    exit /b
)

echo ========================================================
echo   Windows Handheld Tool - Clean Test Uninstaller
echo ========================================================
echo.

set "TARGET_DIR=C:\Program Files\WindowsHandheldTools"

:: 1. Force terminate all running instances
echo [*] Terminating windows_handheld_tool.exe...
taskkill /F /IM "windows_handheld_tool.exe" /T >nul 2>&1

:: 2. Release legacy global hooks if dxgi_hook.dll exists
if exist "%TARGET_DIR%\dxgi_hook.dll" (
    echo [*] Releasing global DXGI hooks...
    rundll32.exe "%TARGET_DIR%\dxgi_hook.dll",UninstallGlobalDxgiHook >nul 2>&1
)

:: 3. Stop and delete WinRing0 Kernel Driver Service
echo [*] Stopping and deleting WinRing0 kernel driver service...
net stop "WinRing0_1_2_0" >nul 2>&1
sc.exe stop "WinRing0_1_2_0" >nul 2>&1
sc.exe delete "WinRing0_1_2_0" >nul 2>&1

:: 4. Remove Task Scheduler autostart task and registry entries
echo [*] Removing Windows autostart entries...
schtasks /delete /tn "WindowsHandheldTool_AutoStart" /f >nul 2>&1
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "HandheldQuickSettings" /f >nul 2>&1

:: 5. Wait for Windows NT Kernel to release file and memory handles
echo [*] Waiting for kernel to release memory and driver handles...
timeout /t 2 /nobreak >nul

:: 6. Clean target directory
if exist "%TARGET_DIR%" (
    echo [*] Deleting directory: "%TARGET_DIR%"...
    rmdir /S /Q "%TARGET_DIR%" >nul 2>&1
    if exist "%TARGET_DIR%" (
        echo [!] Files still locked. Refreshing shell handle...
        taskkill /F /IM explorer.exe >nul 2>&1
        start explorer.exe
        timeout /t 2 /nobreak >nul
        rmdir /S /Q "%TARGET_DIR%" >nul 2>&1
    )
)

if not exist "%TARGET_DIR%" (
    echo.
    echo ========================================================
    echo   [SUCCESS] Clean uninstallation completed successfully!
    echo   Ready for a fresh deployment.
    echo ========================================================
) else (
    echo.
    echo [WARNING] Could not remove all files in "%TARGET_DIR%".
)

echo.
timeout /t 3 >nul
exit /b 0
