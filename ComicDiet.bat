@echo off
title ComicDiet

where pwsh.exe >nul 2>&1
if errorlevel 1 (
    echo PowerShell 7 is not installed.
    echo Please run Install.bat first to set up ComicDiet.
    pause
    exit /b 1
)

pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\ComicDiet.ps1"
