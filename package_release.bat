@echo off
setlocal enabledelayedexpansion

echo ========================================================
echo   Windows Handheld Tool - Packaging Release Distribution
echo ========================================================

set "PROJECT_ROOT=%~dp0"
set "DIST_DIR=%PROJECT_ROOT%dist\windows-handheld-tool"
set "OUTPUT_ZIP=%PROJECT_ROOT%dist\WindowsHandheldTool-v1.0.0-Portable.zip"

echo [*] 1. Compiling C++ DXGI Hook DLL...
call "%PROJECT_ROOT%build_dxgi_hook.bat"
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] DXGI Hook build failed!
    exit /b %ERRORLEVEL%
)

echo [*] 2. Building Flutter Windows Release...
call flutter build windows --release
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Flutter release build failed!
    exit /b %ERRORLEVEL%
)

echo [*] 3. Assembling Distribution Directory in dist\windows-handheld-tool...
if exist "%DIST_DIR%" rd /S /Q "%DIST_DIR%"
mkdir "%DIST_DIR%"
mkdir "%DIST_DIR%\bin"

xcopy /E /I /Y "%PROJECT_ROOT%build\windows\x64\runner\Release\*" "%DIST_DIR%\" >nul
xcopy /E /I /Y "%PROJECT_ROOT%bin\*" "%DIST_DIR%\bin\" >nul
copy /Y "%PROJECT_ROOT%config.json" "%DIST_DIR%\config.json" >nul
if exist "%PROJECT_ROOT%README.md" copy /Y "%PROJECT_ROOT%README.md" "%DIST_DIR%\README.md" >nul

echo [*] 4. Creating Portable ZIP Archive...
powershell -NoProfile -Command "Compress-Archive -Path '%DIST_DIR%\*' -DestinationPath '%OUTPUT_ZIP%' -Force"

if exist "%OUTPUT_ZIP%" (
    echo [SUCCESS] Portable release created: %OUTPUT_ZIP%
) else (
    echo [WARN] Could not create zip archive.
)

echo [*] 5. Checking for Inno Setup compiler...
where iscc >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo [*] Compiling Inno Setup Installer...
    iscc "%PROJECT_ROOT%installer.iss"
) else (
    if exist "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" (
        echo [*] Compiling Inno Setup Installer via default path...
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" "%PROJECT_ROOT%installer.iss"
    ) else (
        echo [INFO] Inno Setup compiler not found. You can install it from https://jrsoftware.org/isdl.php to build Setup.exe.
    )
)

echo ========================================================
echo   [DONE] Distribution package assembled in dist\
echo ========================================================
pause
