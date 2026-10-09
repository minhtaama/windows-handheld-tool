@echo off
setlocal enabledelayedexpansion

title Windows Handheld Tool - Automated Release Packager

echo ========================================================
echo   Windows Handheld Tool - Automated Release Packager
echo ========================================================
echo.

cd /d "%~dp0"

:: 1. Check and close running process to avoid file lock error
echo [*] Check and close running process (windows_handheld_tool.exe)...
taskkill /F /IM "windows_handheld_tool.exe" 2>nul
echo.

:: 2. Compile DXGI Hook DLL
echo [*] Step 1/4: Compile C++ DXGI Hook DLL...
if exist "build_dxgi_hook.bat" (
    call build_dxgi_hook.bat
    if !ERRORLEVEL! NEQ 0 (
        echo [ERROR] Compile dxgi_hook.dll failed!
        pause
        exit /b !ERRORLEVEL!
    )
) else (
    echo [!] build_dxgi_hook.bat not found! Skip this step.
)
echo.

:: 3. Compile Flutter Windows Release
echo [*] Step 2/4: Compile Flutter Windows Release...
call flutter build windows --release
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Flutter build release failed!
    pause
    exit /b !ERRORLEVEL!
)
echo.

:: 4. Copy binary drivers and config.json to Release folder
echo [*] Step 3/4: Copy binary drivers (bin\) and config.json...
set "RELEASE_DIR=%~dp0build\windows\x64\runner\Release"

if not exist "%RELEASE_DIR%\bin" mkdir "%RELEASE_DIR%\bin"
xcopy /E /I /Y "bin\*" "%RELEASE_DIR%\bin\" >nul
copy /Y "config.json" "%RELEASE_DIR%\config.json" >nul

echo [OK] Copied all bin\ and config.json to Release.
echo.

:: 5. Package Portable ZIP to dist\portable\
echo [*] Step 4/4: Package Portable ZIP to dist\portable\...
set "DIST_DIR=%~dp0dist\portable"
if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"

set "ZIP_FILE=%DIST_DIR%\windows-handheld-tool-v1.0.0-portable.zip"
if exist "%ZIP_FILE%" del /F /Q "%ZIP_FILE%"

powershell -NoProfile -ExecutionPolicy Bypass -Command "Write-Host 'Packaging Portable ZIP...' -ForegroundColor Cyan; Compress-Archive -Path '%RELEASE_DIR%\*' -DestinationPath '%ZIP_FILE%' -Force"

if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Zip failed!
    pause
    exit /b !ERRORLEVEL!
)

echo.
echo ========================================================
echo   [SUCCESS] Created complete Portable release!
echo ========================================================
echo   Zip file: %ZIP_FILE%
echo ========================================================
echo.

:: Tuy chon mo thu muc hoac chay thu ung dung voi quyen Administrator
echo Options:
echo   [1] Open folder containing Portable file (dist\portable)
echo   [2] Run Release application (Run as Admin)
echo   [3] Exit
echo.
set /p "CHOICE=Choose your option (1/2/3, default is 1): "

if "%CHOICE%"=="2" (
    echo Running windows_handheld_tool.exe as Administrator...
    powershell -NoProfile -Command "Start-Process '%RELEASE_DIR%\windows_handheld_tool.exe' -Verb RunAs"
) else if "%CHOICE%"=="3" (
    exit /b 0
) else (
    explorer.exe "%DIST_DIR%"
)
