@echo off
chcp 65001 >nul
setlocal
rem WorkBuddy 550C Boot - 卸载器入口
title WorkBuddy 550C Boot - Uninstaller
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
echo.
pause
