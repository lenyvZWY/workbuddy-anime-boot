@echo off
chcp 65001 >nul
title WorkBuddy Anime Boot - Uninstaller
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
echo.
pause
