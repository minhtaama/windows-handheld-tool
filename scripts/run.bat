@echo off
title Windows Handheld Tool - Control Center
set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%~dp0.."
cd /d "%PROJECT_ROOT%"

if exist "%PROJECT_ROOT%\.venv\Scripts\python.exe" (
    set "PYTHON_CMD=%PROJECT_ROOT%\.venv\Scripts\python.exe"
) else (
    set "PYTHON_CMD=python"
)

if "%1"=="1" goto RUN_APP
if "%1"=="2" goto RUN_DEV_HOTRELOAD
if "%1"=="3" goto RUN_CHROME
if "%1"=="4" goto RUN_DEPLOY
if "%1"=="5" goto RUN_UNINSTALL
if "%1"=="0" exit /b 0

:MENU
cls
echo ========================================================
echo   Windows Handheld Tool - Control Center
echo ========================================================
echo.
echo   [1] Run Gaming Overlay (Python + Flutter Web)
echo   [2] Run Dev Hot Reload (Flutter Server + Overlay)
echo   [3] Open Flutter Web in Chrome (UI Inspector ^& Mock Data)
echo   [4] Build Release Package and Install to Program Files
echo   [5] Uninstall Application from System
echo   [0] Exit
echo.
echo ========================================================
set /p choice="Enter your choice [1-5]: "

if "%choice%"=="1" goto RUN_APP
if "%choice%"=="2" goto RUN_DEV_HOTRELOAD
if "%choice%"=="3" goto RUN_CHROME
if "%choice%"=="4" goto RUN_DEPLOY
if "%choice%"=="5" goto RUN_UNINSTALL
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
taskkill /F /IM WindowsHandheldTools.exe >nul 2>&1
exit /b 0

:RUN_APP
call :ENSURE_RTSS
call :CLEAN_PREVIOUS_INSTANCE
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
echo [*] Starting Flutter Web Server on port 5173 (Supports Hot Reload via r/R key)...
start "Flutter Web Dev Server (Port 5173)" /D "%PROJECT_ROOT%\frontend" cmd /k "flutter run -d web-server --web-port 5173 --web-hostname 127.0.0.1"

echo [*] Waiting for Flutter Web Server to become ready on port 5173...
set "WAIT_COUNT=0"
:WAIT_PORT_5173
%PYTHON_CMD% -c "import urllib.request, sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:5173/main.dart.js', timeout=2).status == 200 else 1)" >nul 2>&1
if %errorlevel% equ 0 goto DEV_SERVER_READY
timeout /t 1 >nul
set /a WAIT_COUNT+=1
if %WAIT_COUNT% geq 60 (
    echo [WARNING] Flutter Web Server took too long to start. Launching backend anyway...
    goto DEV_SERVER_READY
)
goto WAIT_PORT_5173

:DEV_SERVER_READY
echo [OK] Flutter Web Server is ready on http://127.0.0.1:5173!
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

:RUN_CHROME
echo [*] Starting Flutter Web directly in Google Chrome (UI Inspector ^& DevTools)...
pushd "%PROJECT_ROOT%\frontend"
flutter run -d chrome
popd
pause
exit /b

:RUN_DEPLOY
call :ENSURE_RTSS
call "%SCRIPT_DIR%deploy\deploy_test.bat"
exit /b

:RUN_UNINSTALL
call "%SCRIPT_DIR%deploy\uninstall_test.bat"
exit /b
