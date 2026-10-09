@echo off
setlocal enabledelayedexpansion

title Windows Handheld Tool - Automated Release Packager

echo ========================================================
echo   Windows Handheld Tool - Automated Release Packager
echo ========================================================
echo.

cd /d "%~dp0"

:: 1. Tắt tiến trình cũ đang chạy để tránh lỗi khóa tệp (File Lock)
echo [*] Kiem tra va dong tien trinh dang chay (windows_handheld_tool.exe)...
taskkill /F /IM "windows_handheld_tool.exe" 2>nul
echo.

:: 2. Bien dich thu vien C++ DXGI Hook DLL
echo [*] Buoc 1/4: Bien dich thu vien C++ DXGI Hook DLL...
if exist "build_dxgi_hook.bat" (
    call build_dxgi_hook.bat
    if !ERRORLEVEL! NEQ 0 (
        echo [ERROR] Bien dich dxgi_hook.dll that bai!
        pause
        exit /b !ERRORLEVEL!
    )
) else (
    echo [!] Khong tim thay build_dxgi_hook.bat, bo qua buoc nay.
)
echo.

:: 3. Bien dich Flutter Windows sang che do Release
echo [*] Buoc 2/4: Bien dich Flutter Windows Release...
call flutter build windows --release
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Flutter build release that bai!
    pause
    exit /b !ERRORLEVEL!
)
echo.

:: 4. Sao chep cac tep driver phan cung va tep cau hinh vao thu muc Release
echo [*] Buoc 3/4: Sao chep driver nhi phan (bin\) va config.json...
set "RELEASE_DIR=%~dp0build\windows\x64\runner\Release"

if not exist "%RELEASE_DIR%\bin" mkdir "%RELEASE_DIR%\bin"
xcopy /E /I /Y "bin\*" "%RELEASE_DIR%\bin\" >nul
copy /Y "config.json" "%RELEASE_DIR%\config.json" >nul

echo [OK] Da sao chep day du thu muc bin\ va config.json vao Release.
echo.

:: 5. Dong goi ban Portable ZIP vao dist\portable\
echo [*] Buoc 4/4: Nen ban Portable ZIP bang PowerShell...
set "DIST_DIR=%~dp0dist\portable"
if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"

set "ZIP_FILE=%DIST_DIR%\windows-handheld-tool-v1.0.0-portable.zip"
if exist "%ZIP_FILE%" del /F /Q "%ZIP_FILE%"

powershell -NoProfile -ExecutionPolicy Bypass -Command "Write-Host 'Dang nen du lieu...' -ForegroundColor Cyan; Compress-Archive -Path '%RELEASE_DIR%\*' -DestinationPath '%ZIP_FILE%' -Force"

if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Nen file zip that bai!
    pause
    exit /b !ERRORLEVEL!
)

echo.
echo ========================================================
echo   [THANH CONG] Da tao ban phat hanh Portable hoan chinh!
echo ========================================================
echo   Tep nen: %ZIP_FILE%
echo ========================================================
echo.

:: Tuy chon mo thu muc hoac chay thu ung dung voi quyen Administrator
echo Tuy chon:
echo   [1] Mo thu muc chua file Portable (dist\portable)
echo   [2] Khoi chay ngay ung dung Release voi quyen Administrator (Run as Admin)
echo   [3] Thoat
echo.
set /p "CHOICE=Nhap lua chon cua ban (1/2/3, mac dinh la 1): "

if "%CHOICE%"=="2" (
    echo Dang khoi chay windows_handheld_tool.exe voi quyen Administrator...
    powershell -NoProfile -Command "Start-Process '%RELEASE_DIR%\windows_handheld_tool.exe' -Verb RunAs"
) else if "%CHOICE%"=="3" (
    exit /b 0
) else (
    explorer.exe "%DIST_DIR%"
)
