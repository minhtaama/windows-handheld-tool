@echo off
setlocal

cd /d "%~dp0"

echo [BUILD] Dang khoi tao moi truong Visual Studio 64-bit...
call "D:\dev-tools\VS BuildTools\VC\Auxiliary\Build\vcvars64.bat"
if errorlevel 1 (
    echo [ERROR] Khong the khoi tao vcvars64.bat
    exit /b 1
)

set OUTDIR=..\..\bin
if not exist "%OUTDIR%" mkdir "%OUTDIR%"

if not exist "build_obj" mkdir "build_obj"

echo [BUILD] Dang bien dich dxgi_hook.dll...
cl /nologo /O2 /MD /LD /EHsc /std:c++17 /W3 ^
   /I "minhook\include" /I "minhook\src" /I "src" ^
   "src\dllmain.cpp" "src\dxgi_hook.cpp" ^
   "minhook\src\buffer.c" "minhook\src\hook.c" "minhook\src\trampoline.c" ^
   "minhook\src\hde\hde64.c" ^
   /Fo"build_obj\\" ^
   /link /OUT:"%OUTDIR%\dxgi_hook.dll" /IMPLIB:"build_obj\dxgi_hook.lib" ^
   dxgi.lib d3d11.lib user32.lib gdi32.lib

if errorlevel 1 (
    echo [ERROR] Bien dich dxgi_hook.dll that bai!
    exit /b 1
)

if exist dllmain.exp del dllmain.exp
if exist dllmain.lib del dllmain.lib

echo [SUCCESS] Da bien dich thanh cong: %OUTDIR%\dxgi_hook.dll
endlocal

