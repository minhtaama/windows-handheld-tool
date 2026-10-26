@echo off
title Windows Handheld Tool - Control Center
set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%~dp0.."
cd /d "%PROJECT_ROOT%"

:: Host and UIAccess UI must run at the same integrity level; otherwise Windows
:: UIPI filters WM_CLOSE/SetWindowBand between them and leaves orphan overlays.
whoami /groups | findstr /C:"S-1-16-12288" >nul 2>&1
if %errorlevel% neq 0 (
    echo [*] Requesting Administrator privileges...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\" %*\"' -Verb RunAs"
    exit /b
)

if exist "%PROJECT_ROOT%\.venv\Scripts\python.exe" (
    set "PYTHON_CMD=%PROJECT_ROOT%\.venv\Scripts\python.exe"
) else (
    set "PYTHON_CMD=python"
)

if "%1"=="1" goto RUN_APP
if "%1"=="2" goto RUN_DEV_HOTRELOAD
if "%1"=="3" goto RUN_DEPLOY
if "%1"=="4" goto RUN_UNINSTALL
if "%1"=="0" exit /b 0

:MENU
cls
echo ========================================================
echo   Windows Handheld Tool - Control Center
echo ========================================================
echo.
echo   [1] Run Gaming Overlay (Python + Flutter Desktop)
echo   [2] Run Dev Hot Reload (Flutter Windows + Overlay)
echo   [3] Build Release Package and Install to Program Files
echo   [4] Uninstall Application from System
echo   [0] Exit
echo.
echo ========================================================
set /p choice="Enter your choice [1-4]: "

if "%choice%"=="1" goto RUN_APP
if "%choice%"=="2" goto RUN_DEV_HOTRELOAD
if "%choice%"=="3" goto RUN_DEPLOY
if "%choice%"=="4" goto RUN_UNINSTALL
if "%choice%"=="0" exit /b 0
echo Invalid choice!
timeout /t 2 >nul
goto MENU

:ENSURE_RTSS
if exist "%ProgramFiles(x86)%\RivaTuner Statistics Server\RTSS.exe" exit /b 0
if exist "%ProgramFiles%\RivaTuner Statistics Server\RTSS.exe" exit /b 0

echo.
echo ========================================================
echo   [!] RIVATUNER STATISTICS SERVER [RTSS] NOT FOUND
echo   Automatically installing RTSS for OSD ^& FPS Limiter...
echo ========================================================
echo.

where winget >nul 2>&1
if %errorlevel% equ 0 (
    echo [*] Installing RTSS via winget...
    winget install --id Guru3D.RTSS -e --silent --accept-package-agreements --accept-source-agreements
)

if exist "%ProgramFiles(x86)%\RivaTuner Statistics Server\RTSS.exe" goto RTSS_INSTALLED_OK
if exist "%ProgramFiles%\RivaTuner Statistics Server\RTSS.exe" goto RTSS_INSTALLED_OK

echo [*] Attempting RTSS installation via backend installer...
pushd "%PROJECT_ROOT%\backend"
%PYTHON_CMD% -c "from src.hardware.rtss_service import rtss_service; rtss_service.install_rtss_silent()"
popd

if exist "%ProgramFiles(x86)%\RivaTuner Statistics Server\RTSS.exe" goto RTSS_INSTALLED_OK
if exist "%ProgramFiles%\RivaTuner Statistics Server\RTSS.exe" goto RTSS_INSTALLED_OK

echo [WARNING] Could not automatically install RTSS. You can install it later from the Performance tab.
echo.
exit /b 0

:RTSS_INSTALLED_OK
echo [OK] RTSS installed successfully!
echo.
exit /b 0

:CLEAN_PREVIOUS_INSTANCE
taskkill /F /IM windows_handheld_tool.exe >nul 2>&1
taskkill /F /IM windows_handheld_ui.exe >nul 2>&1
taskkill /F /IM WindowsHandheldTools.exe >nul 2>&1
exit /b 0

:RUN_APP
call :ENSURE_RTSS
call :CLEAN_PREVIOUS_INSTANCE
if not exist "%PROJECT_ROOT%\frontend\build\windows\x64\runner\Release\windows_handheld_ui.exe" (
    echo [*] Flutter Windows release binary not found. Compiling now...
    pushd "%PROJECT_ROOT%\frontend"
    call flutter build windows --release
    popd
)
echo [*] Starting Windows Handheld Tool via Python...
pushd "%PROJECT_ROOT%\backend"
%PYTHON_CMD% main.py
if %errorlevel% neq 0 (
    echo [ERROR] Application exited with code %errorlevel%
    popd
    pause
) else (
    popd
)
exit /b

:RUN_DEV_HOTRELOAD
call :ENSURE_RTSS
call :CLEAN_PREVIOUS_INSTANCE
echo [*] Starting Flutter Windows in Dev Mode (Supports Hot Reload via r/R key)...
start "Flutter Windows Dev Runner" /D "%PROJECT_ROOT%\frontend" cmd /k "flutter run -d windows"

echo [*] Waiting for Flutter Windows UI window to appear...
set "WAIT_COUNT=0"
:WAIT_FLUTTER_WINDOW
%PYTHON_CMD% -c "import ctypes, sys; sys.exit(0 if ctypes.windll.user32.FindWindowW('FLUTTER_RUNNER_WIN32_WINDOW', 'WindowsHandheldOverlay') else 1)" >nul 2>&1
if %errorlevel% equ 0 goto DEV_WINDOW_READY
timeout /t 1 >nul
set /a WAIT_COUNT+=1
if %WAIT_COUNT% geq 60 (
    echo [WARNING] Flutter UI window took too long to appear. Launching backend anyway...
    goto DEV_WINDOW_READY
)
goto WAIT_FLUTTER_WINDOW

:DEV_WINDOW_READY
echo [OK] Flutter Windows UI is active!
echo [*] Starting Windows Handheld Tool via Python...
pushd "%PROJECT_ROOT%\backend"
%PYTHON_CMD% main.py
if %errorlevel% neq 0 (
    echo [ERROR] Application exited with code %errorlevel%
    popd
    pause
) else (
    popd
)
exit /b

:RUN_DEPLOY
call :ENSURE_RTSS
call "%SCRIPT_DIR%deploy\deploy_test.bat"
exit /b

:RUN_UNINSTALL
call "%SCRIPT_DIR%deploy\uninstall_test.bat"
exit /b
