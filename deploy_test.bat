@echo off
setlocal enabledelayedexpansion
title Windows Handheld Tool - Automated Build, Sign and Deploy Test (Python Runtime)

:: 1. Check Administrator Privileges (UAC Elevation)
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [*] Requesting Administrator privileges to sign and deploy to Program Files...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\" %*\"' -Verb RunAs"
    exit /b
)

echo ========================================================
echo   Windows Handheld Tool - Automated Deploy Test (Python)
echo ========================================================
echo.

cd /d "%~dp0"

:: 2. Check and ensure Code Signing Certificate exists
echo [*] Step 1/6: Checking Code Signing Certificate...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$cert = Get-ChildItem Cert:\LocalMachine\My -CodeSigningCert | Where-Object { $_.Subject -match 'HandheldToolsSigner' };" ^
    "if (-not $cert) { exit 1 } else { exit 0 }"
if %errorlevel% neq 0 (
    echo [!] Certificate HandheldToolsSigner not found. Running setup_certificate.bat...
    call setup_certificate.bat
) else (
    echo [OK] Certificate HandheldToolsSigner is ready.
)
echo.

:: 3. Terminate running process and stop driver service to avoid file lock
echo [*] Step 2/6: Stopping active processes and driver service...
taskkill /F /IM "windows_handheld_tool.exe" 2>nul
taskkill /F /IM "python.exe" /FI "WINDOWTITLE eq Windows Handheld Tool*" 2>nul
net stop "WinRing0_1_2_0" 2>nul
echo [OK] Environment unlocked.
echo.

:: 4. Build Standalone Executable via PyInstaller with UIAccess Manifest
echo [*] Step 3/6: Packaging Frontend and Python Application...
echo [*] Compiling React Frontend (Vite)...
cd frontend
call npm run build
if %errorlevel% neq 0 (
    echo [ERROR] Frontend build failed!
    cd ..
    pause
    exit /b %errorlevel%
)
cd ..

set "DIST_DIR=%~dp0dist\windows_handheld_tool"
if exist "dist\windows_handheld_tool" rmdir /S /Q "dist\windows_handheld_tool"

pyinstaller --noconfirm --onedir --windowed --name "windows_handheld_tool" ^
    --manifest "app.manifest" ^
    --add-data "config.json;." ^
    --add-data "bin;bin" ^
    --add-data "frontend/dist;frontend/dist" ^
    "main.py"


if %errorlevel% neq 0 (
    echo [ERROR] PyInstaller packaging failed!
    pause
    exit /b %errorlevel%
)
echo [OK] PyInstaller build completed.
echo.

:: 5. Copy clean runtime driver binaries and config.json to Release folder
echo [*] Step 4/6: Synchronizing driver binaries to dist folder...
for %%F in (
    "ryzenadj.dll"
    "libryzenadj.dll"
    "WinRing0x64.dll"
    "WinRing0x64.sys"
    "inpoutx64.dll"
) do (
    if exist "bin\%%~F" (
        copy /Y "bin\%%~F" "%DIST_DIR%\" >nul
    )
)
if exist "config.json" copy /Y "config.json" "%DIST_DIR%\config.json" >nul
echo [OK] Driver binaries synchronized.
echo.

:: 6. Locate signtool.exe and sign the release executable
echo [*] Step 5/6: Signing windows_handheld_tool.exe with Authenticode...
set "SIGNTOOL="
for /f "delims=" %%I in ('dir /b /s "C:\Program Files (x86)\Windows Kits\10\bin\*signtool.exe" 2^>nul ^| findstr /i "\\x64\\signtool.exe"') do (
    if exist "%%I" (
        set "SIGNTOOL=%%I"
        goto :FOUND_SIGNTOOL
    )
)

:FOUND_SIGNTOOL
if not defined SIGNTOOL (
    echo [ERROR] Could not find signtool.exe in Windows Kits! Please verify Windows 10/11 SDK installation.
    pause
    exit /b 1
)

echo [*] Using SignTool: "!SIGNTOOL!"
"!SIGNTOOL!" sign /sm /s My /n "HandheldToolsSigner" /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 "%DIST_DIR%\windows_handheld_tool.exe"
if %errorlevel% neq 0 (
    echo [!] Timestamp server unreachable. Signing without timestamp...
    "!SIGNTOOL!" sign /sm /s My /n "HandheldToolsSigner" /fd SHA256 "%DIST_DIR%\windows_handheld_tool.exe"
    if !errorlevel! neq 0 (
        echo [ERROR] Code signing failed!
        pause
        exit /b !errorlevel%
    )
)
echo [OK] Executable signed successfully with Authenticode UIAccess signature.
echo.

:: 7. Synchronize to Secure Location (C:\Program Files\WindowsHandheldTools)
echo [*] Step 6/6: Deploying to C:\Program Files\WindowsHandheldTools\...
set "TARGET_DIR=C:\Program Files\WindowsHandheldTools"
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"

robocopy "%DIST_DIR%" "%TARGET_DIR%" /E /PURGE /R:2 /W:1 >nul
:: Robocopy exit codes 0-7 indicate success
if %errorlevel% geq 8 (
    echo [ERROR] Robocopy deployment failed with code %errorlevel%!
    pause
    exit /b %errorlevel%
)

if exist "uninstall_test.bat" copy /Y "uninstall_test.bat" "%TARGET_DIR%\" >nul

echo.
echo ========================================================
echo   [SUCCESS] Deployment to Program Files completed!
echo ========================================================
echo   Target path: %TARGET_DIR%\windows_handheld_tool.exe
echo ========================================================
echo.

:: 8. Launch the deployed application
echo [*] Launching application from Secure Location...
start "" "%TARGET_DIR%\windows_handheld_tool.exe"

echo.
echo Application is now running in Windows System Z-Band with TokenUIAccess.
timeout /t 3 >nul
exit /b 0
