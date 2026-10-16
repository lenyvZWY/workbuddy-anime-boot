@echo off
rem ============================================================
rem  WorkBuddy Anime Boot - 立即启动"更新看护"（后台静默运行）
rem  下次登录 Windows 后会自动启动，这里只是不想等的话手动启动一次。
rem ============================================================
start "" /b powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%USERPROFILE%\.workbuddy-anime\watcher\watch.ps1"
