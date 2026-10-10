@echo off
setlocal enabledelayedexpansion
title Windows Handheld Tool - Clean Uninstaller

:: 1. Check Administrator Privileges (UAC Elevation)
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [*] Requesting Administrator privileges to uninstall application and system services...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\" %*\"' -Verb RunAs"
    exit /b
)

:: If parameter %1 is provided, this script is running independently from %TEMP%
if not "%~1"=="" goto :RUN_FROM_TEMP

:: 2. Running directly from the application folder
echo ========================================================
echo   Windows Handheld Tool - Clean Uninstaller
echo ========================================================
echo.
echo Application folder: %~dp0
echo.
echo WARNING: This action will:
echo   1. Terminate all active application processes.
echo   2. Stop and delete WinRing0 kernel driver service.
echo   3. Unhook global graphics hooks and delete Autostart task.
echo   4. PERMANENTLY DELETE this entire application directory.
echo.
set /p "CONFIRM=Are you sure you want to proceed? (Y/N, default is N): "
if /i not "!CONFIRM!"=="Y" (
    echo [*] Uninstallation cancelled by user.
    timeout /t 2 >nul
    exit /b 0
)

:: Copy script to %TEMP% to unlock the working directory
set "TEMP_SCRIPT=%TEMP%\handheld_tool_cleanup_%RANDOM%.bat"
set "APP_DIR=%~dp0"
if "%APP_DIR:~-1%"=="\" set "APP_DIR=%APP_DIR:~0,-1%"

copy /y "%~f0" "%TEMP_SCRIPT%" >nul

echo.
echo [*] Transferring control to standalone background process...
start "" cmd.exe /c ""%TEMP_SCRIPT%" "%APP_DIR%""
exit /b 0

:: =========================================================================
:RUN_FROM_TEMP
:: Standalone cleanup process running in %TEMP%
cd /d "%TEMP%"
set "TARGET_DIR=%~1"

echo ========================================================
echo   Uninstalling and Cleaning Up Application Files...
echo ========================================================
echo.

:: 1. Force terminate main application and child processes
echo [*] Terminating windows_handheld_tool.exe...
taskkill /F /IM "windows_handheld_tool.exe" /T >nul 2>&1

:: 2. Unhook Global DXGI Hook before unlocking DLL
echo [*] Unhooking global DXGI hooks...
if exist "%TARGET_DIR%\dxgi_hook.dll" (
    rundll32.exe "%TARGET_DIR%\dxgi_hook.dll",UninstallGlobalDxgiHook >nul 2>&1
)

:: 3. Stop and delete WinRing0 Kernel Driver Service
echo [*] Stopping and deleting WinRing0 kernel driver service...
net stop "WinRing0_1_2_0" >nul 2>&1
sc.exe stop "WinRing0_1_2_0" >nul 2>&1
sc.exe delete "WinRing0_1_2_0" >nul 2>&1

:: 4. Remove Task Scheduler autostart task and registry entries
echo [*] Removing Windows autostart Task Scheduler entry...
schtasks /delete /tn "WindowsHandheldTool_AutoStart" /f >nul 2>&1
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "HandheldQuickSettings" /f >nul 2>&1

:: 5. Wait for Windows NT Kernel to release file and memory handles
echo [*] Waiting for kernel to release memory and driver handles...
timeout /t 2 /nobreak >nul

:: 6. Attempt recursive directory deletion
echo [*] Deleting application folder: "%TARGET_DIR%"...
set /a ATTEMPTS=0

:RETRY_DELETE
rmdir /S /Q "%TARGET_DIR%" >nul 2>&1
if exist "%TARGET_DIR%" (
    set /a ATTEMPTS+=1
    if !ATTEMPTS! equ 2 (
        :: If dxgi_hook.dll is still locked by Windows Explorer, restart explorer.exe once to release handle
        if exist "%TARGET_DIR%\dxgi_hook.dll" (
            echo [*] Refreshing Windows shell to release active hook handles...
            taskkill /F /IM explorer.exe >nul 2>&1
            start explorer.exe
            timeout /t 2 /nobreak >nul
        )
    )
    if !ATTEMPTS! leq 5 (
        timeout /t 1 /nobreak >nul
        goto :RETRY_DELETE
    )
)

:: 7. Fallback: Register locked files for deletion on next reboot via MoveFileEx
if exist "%TARGET_DIR%" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $path = '%TARGET_DIR%'; Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class WinFile { [DllImport(\"kernel32.dll\", SetLastError=true, CharSet=CharSet.Unicode)] public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, int dwFlags); }'; Get-ChildItem -Path $path -Recurse -Force | ForEach-Object { [WinFile]::MoveFileEx($_.FullName, $null, 4) }; [WinFile]::MoveFileEx($path, $null, 4); } catch {}" >nul 2>&1
)

echo.
if not exist "%TARGET_DIR%" (
    echo ========================================================
    echo   [SUCCESS] Application folder completely removed!
    echo ========================================================
) else (
    echo ========================================================
    echo   [SCHEDULED] Remaining system-locked files scheduled 
    echo   for automatic deletion upon next Windows restart.
    echo ========================================================
)

echo.
timeout /t 3 >nul

:: 8. Self-destruct temporary script in %TEMP%
(goto) 2>nul & del "%~f0" & exit
