@echo off
chcp 65001 >nul
rem ============================================================
rem  WorkBuddy Anime Boot - 移除"更新看护"
rem  删除开机自启项 + 结束正在运行的看护进程。
rem  注意：只停看护，皮肤本身不受影响（卸载皮肤请用 uninstall.cmd）。
rem  自启项有两代：.vbs（v1.0.1+，无窗口）/ .cmd（旧版），两个都清。
rem ============================================================
echo === 移除更新看护 ===

set "SU1=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\WorkBuddyAnimeWatcher.vbs"
set "SU2=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\WorkBuddyAnimeWatcher.cmd"

if exist "%SU1%" (
    del /f /q "%SU1%"
    echo [OK] 已删除自启项 WorkBuddyAnimeWatcher.vbs
) else (
    echo [SKIP] 未找到 WorkBuddyAnimeWatcher.vbs
)

if exist "%SU2%" (
    del /f /q "%SU2%"
    echo [OK] 已删除旧版自启项 WorkBuddyAnimeWatcher.cmd
) else (
    echo [SKIP] 未找到 WorkBuddyAnimeWatcher.cmd
)

powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.ProcessId -ne $PID -and ($_.CommandLine -like '*watch.ps1*' -or $_.CommandLine -like '*auto-apply.ps1*') } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Host ('[OK] 已结束看护进程 pid=' + $_.ProcessId) }"

echo 完成（皮肤本身不受影响）。
pause
