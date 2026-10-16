# ==========================================================================
# WorkBuddy Anime Boot - 看护循环
# --------------------------------------------------------------------------
# 登录后常驻运行，每 180 秒调用一次 auto-apply.ps1。
# auto-apply.ps1 平时是空转（几毫秒就退出），只有检测到
# "WorkBuddy 更新把皮肤冲掉了" 才会真正动作。
#
# 结束方式：运行 remove-autostart.cmd，或任务管理器结束该 powershell 进程。
# ==========================================================================
$ErrorActionPreference = 'SilentlyContinue'

$kit   = Split-Path -Parent $MyInvocation.MyCommand.Path
$apply = Join-Path $kit 'auto-apply.ps1'
$log   = Join-Path $kit 'watcher.log'

"$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))  看护已启动 (pid $PID)" |
    Out-File -Append -Encoding utf8 -LiteralPath $log

while ($true) {
    if (-not (Test-Path -LiteralPath $apply)) { break }   # 套件被删了就退出
    & powershell -NoProfile -ExecutionPolicy Bypass -File $apply
    Start-Sleep -Seconds 180
}
