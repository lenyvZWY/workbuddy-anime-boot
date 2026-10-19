# ==========================================================================
# WorkBuddy Anime Boot - 看护循环
# --------------------------------------------------------------------------
# 登录后常驻运行，每 180 秒调用一次 auto-apply.ps1。
# auto-apply.ps1 平时是空转（几毫秒就退出），只有检测到
# "WorkBuddy 更新把皮肤冲掉了" 才会真正动作。
#
# 结束方式：运行 remove-autostart.cmd，或任务管理器结束该 powershell 进程。
#
# 【为什么看不到窗口】
#   · 本脚本由 VBS 启动器以 window style 0（完全隐藏）拉起，不产生控制台；
#   · 子进程用 Start-Process -WindowStyle Hidden 启动 —— 直接写
#     "powershell -WindowStyle Hidden" 会先把控制台窗口创建出来再隐藏，仍会闪一下。
# ==========================================================================
$ErrorActionPreference = 'SilentlyContinue'

$kit   = Split-Path -Parent $MyInvocation.MyCommand.Path
$apply = Join-Path $kit 'auto-apply.ps1'
$log   = Join-Path $kit 'watcher.log'

"$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))  看护已启动 (pid $PID)" |
    Out-File -Append -Encoding utf8 -LiteralPath $log

while ($true) {
    if (-not (Test-Path -LiteralPath $apply)) { break }   # 套件被删了就退出
    Start-Process -FilePath 'powershell.exe' `
                  -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $apply) `
                  -WindowStyle Hidden -Wait
    Start-Sleep -Seconds 180
}
