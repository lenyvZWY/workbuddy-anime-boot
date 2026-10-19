@echo off
chcp 65001 >nul
rem ============================================================
rem  WorkBuddy Anime Boot - 立即启动"更新看护"（静默，无窗口）
rem  实际启动工作交给同目录的 start-watcher.vbs（window style 0 = 完全隐藏）。
rem  下次登录 Windows 后会自动启动，这里只是不想等的话手动启动一次。
rem ============================================================
echo === 启动更新看护（后台静默运行）===
start "" wscript.exe "%~dp0start-watcher.vbs"
echo [OK] 已在后台启动，不会出现任何窗口。
echo      看护每 3 分钟检查一次，只有 WorkBuddy 更新冲掉皮肤时才会动作。
timeout /t 3 >nul
