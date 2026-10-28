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

set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%~dp0..\.."
cd /d "%PROJECT_ROOT%"

:: Clean stale build artifacts (previous elevated runs own build/ and dist/)
call "%SCRIPT_DIR%clean.bat"
echo.

if exist "%PROJECT_ROOT%\.venv\Scripts\pyinstaller.exe" (
    set "PYINSTALLER_CMD="%PROJECT_ROOT%\.venv\Scripts\pyinstaller.exe""
) else (
    set "PYINSTALLER_CMD=pyinstaller"
)

:: 2. Check and ensure Code Signing Certificate exists
echo [*] Step 1/6: Checking Code Signing Certificate...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$cert = Get-ChildItem Cert:\LocalMachine\My -CodeSigningCert | Where-Object { $_.Subject -match 'HandheldToolsSigner' };" ^
    "if (-not $cert) { exit 1 } else { exit 0 }"
if %errorlevel% neq 0 (
    echo [!] Certificate HandheldToolsSigner not found. Running setup_certificate.bat...
    call "%SCRIPT_DIR%setup_certificate.bat"
) else (
    echo [OK] Certificate HandheldToolsSigner is ready.
)
echo.

:: 3. Terminate running process and stop driver service to avoid file lock
echo [*] Step 2/6: Stopping active processes and driver service...
taskkill /F /T /IM "windows_handheld_tool.exe" 2>nul
taskkill /F /T /IM "windows_handheld_ui.exe" 2>nul
taskkill /F /IM "python.exe" /FI "WINDOWTITLE eq Windows Handheld Tool*" 2>nul
net stop "WinRing0_1_2_0" 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-MpPreference -ExclusionPath '%PROJECT_ROOT%' -ErrorAction SilentlyContinue" 2>nul
timeout /t 1 >nul
echo [OK] Environment unlocked.
echo.

:: 4. Build Standalone Executable via PyInstaller with UIAccess Manifest
echo [*] Step 3/6: Packaging Frontend and Python Application...
echo [*] Compiling Flutter Windows Desktop Frontend...
pushd "%PROJECT_ROOT%\frontend"
call flutter build windows --release
set "FLUTTER_ERR=!errorlevel!"
popd
if !FLUTTER_ERR! neq 0 (
    echo [ERROR] Flutter Windows build failed!
    pause
    exit /b !FLUTTER_ERR!
)

set "DIST_DIR=%PROJECT_ROOT%\dist\windows_handheld_tool"

pushd "%PROJECT_ROOT%\backend"
if exist "windows_handheld_tool.spec" del /F /Q "windows_handheld_tool.spec"
%PYINSTALLER_CMD% --noconfirm --clean --onedir --windowed --name "windows_handheld_tool" ^
    --distpath "%PROJECT_ROOT%\dist" ^
    --workpath "%PROJECT_ROOT%\build" ^
    --uac-admin ^
    --manifest "app.manifest" ^
    --add-data "config.json;." ^
    --icon "assets\app_icon.ico" ^
    --add-data "assets;assets" ^
    --add-data "bin;bin" ^
    "main.py"
set "PYINST_ERR=!errorlevel!"
popd

if !PYINST_ERR! neq 0 (
    echo [ERROR] PyInstaller packaging failed!
    pause
    exit /b !PYINST_ERR!
)
echo [OK] PyInstaller build completed.
echo.

:: 5. Copy clean runtime driver binaries, UI assets and config.json to Release folder
echo [*] Step 4/6: Synchronizing driver binaries and UI assets to dist folder...
if not exist "%DIST_DIR%\bin" mkdir "%DIST_DIR%\bin"
if not exist "%DIST_DIR%\assets" mkdir "%DIST_DIR%\assets"
if exist "%PROJECT_ROOT%\backend\assets" (
    robocopy "%PROJECT_ROOT%\backend\assets" "%DIST_DIR%\assets" /E >nul
)
for %%F in (
    "ryzenadj.exe"
    "ryzenadj.dll"
    "libryzenadj.dll"
    "WinRing0x64.dll"
    "WinRing0x64.sys"
    "inpoutx64.dll"
    "dxgi_hook.dll"
) do (
    if exist "%PROJECT_ROOT%\backend\bin\%%~F" (
        copy /Y "%PROJECT_ROOT%\backend\bin\%%~F" "%DIST_DIR%\bin\" >nul
    )
)
:: Synchronize WinRing0 directly to the executable directory
if exist "%PROJECT_ROOT%\backend\bin\WinRing0x64.sys" copy /Y "%PROJECT_ROOT%\backend\bin\WinRing0x64.sys" "%DIST_DIR%\" >nul
if exist "%PROJECT_ROOT%\backend\bin\WinRing0x64.dll" copy /Y "%PROJECT_ROOT%\backend\bin\WinRing0x64.dll" "%DIST_DIR%\" >nul
if exist "%PROJECT_ROOT%\backend\config.json" copy /Y "%PROJECT_ROOT%\backend\config.json" "%DIST_DIR%\config.json" >nul

if exist "%PROJECT_ROOT%\frontend\build\windows\x64\runner\Release" (
    if not exist "%DIST_DIR%\ui" mkdir "%DIST_DIR%\ui"
    robocopy "%PROJECT_ROOT%\frontend\build\windows\x64\runner\Release" "%DIST_DIR%\ui" /E >nul
)
echo [OK] Driver binaries and UI assets synchronized.
echo.

:: 6. Locate mt.exe and signtool.exe to embed UIAccess manifest and sign
echo [*] Step 5/6: Embedding UIAccess manifest and signing executables...
set "MT_EXE="
for /f "delims=" %%I in ('dir /b /s "C:\Program Files (x86)\Windows Kits\10\bin\*mt.exe" 2^>nul ^| findstr /i "\\x64\\mt.exe"') do (
    if exist "%%I" (
        set "MT_EXE=%%I"
        goto :FOUND_MT
    )
)

:FOUND_MT
if defined MT_EXE (
    if exist "%DIST_DIR%\ui\windows_handheld_ui.exe" (
        echo [*] Embedding UIAccess manifest into ui\windows_handheld_ui.exe...
        "!MT_EXE!" -manifest "%SCRIPT_DIR%ui_privileged.manifest" -outputresource:"%DIST_DIR%\ui\windows_handheld_ui.exe;#1"
    )
)

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
        echo [ERROR] Code signing failed for windows_handheld_tool.exe!
        pause
        exit /b !errorlevel!
    )
)

if exist "%DIST_DIR%\ui\windows_handheld_ui.exe" (
    echo [*] Signing windows_handheld_ui.exe with Authenticode...
    "!SIGNTOOL!" sign /sm /s My /n "HandheldToolsSigner" /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 "%DIST_DIR%\ui\windows_handheld_ui.exe"
    if !errorlevel! neq 0 (
        "!SIGNTOOL!" sign /sm /s My /n "HandheldToolsSigner" /fd SHA256 "%DIST_DIR%\ui\windows_handheld_ui.exe"
        if !errorlevel! neq 0 (
            echo [ERROR] Code signing failed for windows_handheld_ui.exe!
            pause
            exit /b !errorlevel!
        )
    )
)
echo [OK] Executables signed successfully with Authenticode UIAccess signature.
echo.

:: 7. Synchronize to Secure Location (C:\Program Files\WindowsHandheldTools)
echo [*] Step 6/6: Deploying to C:\Program Files\WindowsHandheldTools\...
set "TARGET_DIR=C:\Program Files\WindowsHandheldTools"
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"

if exist "%TARGET_DIR%\_internal\VCRUNTIME140.dll" (
    robocopy "%DIST_DIR%" "%TARGET_DIR%" /E /PURGE /XF "VCRUNTIME140.dll" "VCRUNTIME140_1.dll" /R:2 /W:1 /NP /NDL
) else (
    robocopy "%DIST_DIR%" "%TARGET_DIR%" /E /PURGE /R:2 /W:1 /NP /NDL
)
:: Robocopy exit codes 0-7 indicate success
if %errorlevel% geq 8 (
    echo [ERROR] Robocopy deployment failed with code %errorlevel%!
    pause
    exit /b %errorlevel%
)

if exist "%SCRIPT_DIR%uninstall_test.bat" copy /Y "%SCRIPT_DIR%uninstall_test.bat" "%TARGET_DIR%\" >nul

echo.
echo ========================================================
echo   [SUCCESS] Deployment to Program Files completed!
echo ========================================================
echo   Target path: %TARGET_DIR%\windows_handheld_tool.exe
echo ========================================================
echo.

:: 8. Launch the deployed application via ShellExecuteEx (Start-Process) so AppInfo service grants TokenUIAccess
echo [*] Launching application from Secure Location via ShellExecute...
powershell -NoProfile -ExecutionPolicy Bypass -Command "ie4uinit.exe -show 2>$null; Start-Process -FilePath '%TARGET_DIR%\windows_handheld_tool.exe' -WorkingDirectory '%TARGET_DIR%'"

echo.
echo Application is now running in Windows System Z-Band with TokenUIAccess.
timeout /t 3 >nul
exit /b 0
