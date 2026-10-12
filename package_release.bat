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
echo [*] Step 2/4: Compile Flutter Windows Release (preserving all Material Icons)...
call flutter build windows --release --no-tree-shake-icons
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Flutter build release failed!
    pause
    exit /b !ERRORLEVEL!
)
echo.

:: 4. Copy binary drivers and config.json to Release folder (only copy essential runtime binaries, remove all .ps1, .bat, .py scripts and debug files)
echo [*] Step 3/4: Copy clean binary drivers (bin\) and config.json...
set "RELEASE_DIR=%~dp0build\windows\x64\runner\Release"

:: Clean legacy Release\bin folder if exists to avoid duplicated files
if exist "%RELEASE_DIR%\bin" rmdir /S /Q "%RELEASE_DIR%\bin"
del /F /Q "%RELEASE_DIR%\*.old" 2>nul

:: Copy essential runtime binaries directly to Release root (WinRing0 requires WinRing0x64.sys alongside caller process)
for %%F in (
    "ryzenadj.dll"
    "libryzenadj.dll"
    "WinRing0x64.dll"
    "WinRing0x64.sys"
    "inpoutx64.dll"
    "dxgi_hook.dll"
) do (
    if exist "bin\%%~F" (
        copy /Y "bin\%%~F" "%RELEASE_DIR%\" >nul
    )
)
copy /Y "config.json" "%RELEASE_DIR%\config.json" >nul
if exist "uninstall.bat" copy /Y "uninstall.bat" "%RELEASE_DIR%\uninstall.bat" >nul

echo [OK] Copied clean runtime binaries, config.json, uninstall.bat to Release root.
echo.

:: 5. Package Portable ZIP to dist\portable\
echo [*] Step 4/4: Package Portable ZIP to dist\portable\...
set "DIST_DIR=%~dp0dist\portable"
if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"

set "ZIP_FILE=%DIST_DIR%\windows-handheld-tool-portable-release.zip"
if exist "%ZIP_FILE%" del /F /Q "%ZIP_FILE%"

powershell -NoProfile -ExecutionPolicy Bypass -Command "Write-Host 'Packaging Portable ZIP...' -ForegroundColor Cyan; Compress-Archive -Path '%RELEASE_DIR%\*' -DestinationPath '%ZIP_FILE%' -Force; if (Test-Path '%ZIP_FILE%') { Unblock-File -Path '%ZIP_FILE%' }"

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
