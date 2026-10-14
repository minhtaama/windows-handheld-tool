@echo off
title Windows Handheld Tool (Dev Runner)
cd /d "%~dp0"
echo [*] Starting Windows Handheld Tool via Python...
python main.py
if %errorlevel% neq 0 (
    echo [ERROR] Application exited with code %errorlevel%
    pause
)
