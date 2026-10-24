@echo off
title Windows Handheld Tool - Control Center
set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%~dp0.."
cd /d "%PROJECT_ROOT%"

if exist "%PROJECT_ROOT%\.venv\Scripts\python.exe" (
    set "PYTHON_CMD="%PROJECT_ROOT%\.venv\Scripts\python.exe""
) else (
    set "PYTHON_CMD=python"
)

if "%1"=="1" goto RUN_APP
if "%1"=="2" goto RUN_DEV_HOTRELOAD
if "%1"=="3" goto RUN_CHROME
if "%1"=="4" goto RUN_DEPLOY
if "%1"=="5" goto RUN_UNINSTALL

:MENU
cls
echo ========================================================
echo   Windows Handheld Tool - Control Center
echo ========================================================
echo.
echo   [1] Chay Gaming Overlay (Python + Flutter Web)
echo   [2] Chay che do Dev Hot Reload (Flutter Server + Overlay)
echo   [3] Mo Flutter Web tren Chrome (UI Inspector ^& Mock Data)
echo   [4] Dong goi Release va Cai dat vao Program Files
echo   [5] Go cai dat ung dung khoi he thong
echo   [0] Thoat
echo.
echo ========================================================
set /p choice="Nhap lua chon cua ban [1-5]: "

if "%choice%"=="1" goto RUN_APP
if "%choice%"=="2" goto RUN_DEV_HOTRELOAD
if "%choice%"=="3" goto RUN_CHROME
if "%choice%"=="4" goto RUN_DEPLOY
if "%choice%"=="5" goto RUN_UNINSTALL
if "%choice%"=="0" exit /b 0
echo Lua chon khong hop le!
timeout /t 2 >nul
goto MENU

:ENSURE_RTSS
set "RTSS_INSTALLED="
if exist "%ProgramFiles(x86)%\RivaTuner Statistics Server\RTSS.exe" set "RTSS_INSTALLED=1"
if exist "%ProgramFiles%\RivaTuner Statistics Server\RTSS.exe" set "RTSS_INSTALLED=1"

if not defined RTSS_INSTALLED (
    echo.
    echo ========================================================
    echo   [!] KHONG TIM THAY RIVATUNER STATISTICS SERVER (RTSS)
    echo   Dang tu dong cai dat RTSS de ho tro OSD ^& Fps Limiter...
    echo ========================================================
    echo.
    where winget >nul 2>&1
    if %errorlevel% equ 0 (
        echo [*] Dang cai dat RTSS qua winget...
        winget install --id Guru3D.RTSS -e --silent --accept-package-agreements --accept-source-agreements
    )
    if not exist "%ProgramFiles(x86)%\RivaTuner Statistics Server\RTSS.exe" (
        if not exist "%ProgramFiles%\RivaTuner Statistics Server\RTSS.exe" (
            echo [*] Thu cai dat RTSS qua backend installer...
            pushd "%PROJECT_ROOT%\backend"
            %PYTHON_CMD% -c "from src.hardware.rtss_service import rtss_service; rtss_service.install_rtss_silent()"
            popd
        )
    )
    if exist "%ProgramFiles(x86)%\RivaTuner Statistics Server\RTSS.exe" (
        echo [OK] RTSS da duoc cai dat thanh cong!
    ) else if exist "%ProgramFiles%\RivaTuner Statistics Server\RTSS.exe" (
        echo [OK] RTSS da duoc cai dat thanh cong!
    ) else (
        echo [CANH BAO] Khong the tu dong cai dat RTSS. Ban co the cai dat sau trong tab Performance.
    )
    echo.
)
exit /b 0

:RUN_APP
call :ENSURE_RTSS
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
echo [*] Khoi dong Flutter Web Server tai port 5173 (Ho tro Hot Reload qua phim r/R)...
start "Flutter Web Dev Server (Port 5173)" cmd /c "cd /d "%PROJECT_ROOT%\frontend" && flutter run -d web-server --web-port 5173"
timeout /t 2 >nul
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
echo [*] Khoi dong Flutter Web truc tiep tren Google Chrome (UI Inspector ^& DevTools)...
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
