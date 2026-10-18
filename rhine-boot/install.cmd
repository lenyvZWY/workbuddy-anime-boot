@echo off
chcp 65001 >nul
setlocal
rem WorkBuddy 550C Boot - 安装器入口
rem 用法： 双击 install.cmd
rem         install.cmd -AppPath "D:\你的路径\WorkBuddy"
title WorkBuddy 550C Boot - Installer
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
echo.
pause
