@echo off
setlocal enabledelayedexpansion

echo ========================================================
echo   Building DXGI Borderless Hook DLL (x64 Release)
echo ========================================================

set "VS_BUILDTOOLS_PATH=D:\dev-tools\VS BuildTools\VC\Auxiliary\Build\vcvars64.bat"
if not exist "%VS_BUILDTOOLS_PATH%" (
    set "VS_BUILDTOOLS_PATH=C:\Users\h\dev-tools\VisualStudio BuildTools\VC\Auxiliary\Build\vcvars64.bat"
)
if exist "%VS_BUILDTOOLS_PATH%" (
    call "%VS_BUILDTOOLS_PATH%"
) else (
    echo [!] Searching via vswhere...
    for /f "usebackq tokens=*" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
        if exist "%%i\VC\Auxiliary\Build\vcvars64.bat" (
            call "%%i\VC\Auxiliary\Build\vcvars64.bat"
        )
    )
)

set "SRC_DIR=%~dp0windows\dxgi_hook"
set "MINHOOK_DIR=%SRC_DIR%\minhook"
set "OUT_DIR=%~dp0bin"
set "BUILD_RELEASE_DIR=%~dp0build\windows\x64\runner\Release"

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

echo [*] Compiling C++ and C source files...
cl.exe /O2 /MD /EHsc /std:c++17 /W3 /D"DXGI_HOOK_EXPORTS" /D"UNICODE" /D"_UNICODE" /D"NOMINMAX" /I"%SRC_DIR%" /I"%MINHOOK_DIR%" /c ^
    "%SRC_DIR%\dxgi_hook.cpp" ^
    "%MINHOOK_DIR%\buffer.c" ^
    "%MINHOOK_DIR%\hde64.c" ^
    "%MINHOOK_DIR%\hook.c" ^
    "%MINHOOK_DIR%\trampoline.c"

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Compilation failed!
    exit /b %ERRORLEVEL%
)

if exist "%OUT_DIR%\dxgi_hook.dll" (
    del /F /Q "%OUT_DIR%\dxgi_hook.dll.old" 2>nul
    move /Y "%OUT_DIR%\dxgi_hook.dll" "%OUT_DIR%\dxgi_hook.dll.old" 2>nul
)

echo [*] Linking dxgi_hook.dll...
link.exe /DLL /DEF:"%SRC_DIR%\dxgi.def" /OUT:"%OUT_DIR%\dxgi_hook.dll" ^
    dxgi_hook.obj buffer.obj hde64.obj hook.obj trampoline.obj ^
    dxgi.lib d3d11.lib shlwapi.lib user32.lib kernel32.lib

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Linking failed!
    exit /b %ERRORLEVEL%
)

if exist "%BUILD_RELEASE_DIR%" (
    if exist "%BUILD_RELEASE_DIR%\dxgi_hook.dll" (
        del /F /Q "%BUILD_RELEASE_DIR%\dxgi_hook.dll.old" 2>nul
        move /Y "%BUILD_RELEASE_DIR%\dxgi_hook.dll" "%BUILD_RELEASE_DIR%\dxgi_hook.dll.old" 2>nul
    )
    echo [*] Copying to %BUILD_RELEASE_DIR%...
    copy /Y "%OUT_DIR%\dxgi_hook.dll" "%BUILD_RELEASE_DIR%\dxgi_hook.dll"
)

echo [*] Cleaning temporary obj/exp/lib files...
del /Q dxgi_hook.obj buffer.obj hde64.obj hook.obj trampoline.obj dxgi_hook.exp dxgi_hook.lib 2>nul

echo ========================================================
echo   [SUCCESS] dxgi_hook.dll built successfully in bin\
echo ========================================================
