@echo off
title Handheld Quick Settings
cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
    echo [!] Chua tim thay moi truong ao .venv.
    echo Dang khoi tao .venv...
    py -3.11 -m venv .venv
    .\.venv\Scripts\pip.exe install -r requirements.txt
)

echo [*] Dang khoi dong Handheld Quick Settings Overlay...
start "" ".\.venv\Scripts\pythonw.exe" main.py
exit
