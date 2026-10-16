@echo off
chcp 65001 >nul
rem ============================================================
rem  WorkBuddy Anime Boot - 移除"更新看护"
rem  删除开机自启项 + 结束正在运行的看护进程。
rem  注意：只停看护，皮肤本身不受影响（卸载皮肤请用 uninstall.cmd）。
rem ============================================================
echo === 移除更新看护 ===

set "SU=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\WorkBuddyAnimeWatcher.cmd"
if exist "%SU%" (
    del "%SU%"
    echo [OK] 开机自启已删除
) else (
    echo [SKIP] 开机自启项不存在
)

powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -like '*watch.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Host ('[OK] 已结束看护进程 pid=' + $_.ProcessId) }"

echo 完成（皮肤本身不受影响）。
pause
