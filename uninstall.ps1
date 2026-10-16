<#
.SYNOPSIS
  WorkBuddy Anime Boot - 卸载器
.DESCRIPTION
  把 WorkBuddy 还原回官方原版界面：
    [1] 停掉并移除"更新看护"（如果装过）
    [2] 用备份还原 renderer/index.html
    [3] 删除安装目录里的素材文件（wb-boot.mp4 / wb-wallpaper.jpg）
.PARAMETER AppPath
  WorkBuddy 安装目录。省略则自动从看护配置或运行中进程探测。
#>
param(
    [string]$AppPath
)

$ErrorActionPreference = 'Continue'

$store = Join-Path $env:USERPROFILE '.workbuddy-anime'
$bkDir = Join-Path $store 'backup'
$cfg   = Join-Path $store 'watcher\config.txt'

function Step($n, $t) { Write-Host ''; Write-Host "[$n] $t" -ForegroundColor Cyan }
function Ok($t)       { Write-Host "    [OK] $t" -ForegroundColor Green }
function Warn($t)     { Write-Host "    [!]  $t" -ForegroundColor Yellow }
function Fail($t)     { Write-Host "    [X]  $t" -ForegroundColor Red }

Write-Host ''
Write-Host '==============================================' -ForegroundColor Magenta
Write-Host '  WorkBuddy Anime Boot - Uninstaller' -ForegroundColor Magenta
Write-Host '==============================================' -ForegroundColor Magenta

# ==========================================================================
# 1. 停掉 / 移除看护
# ==========================================================================
Step 1 '移除更新看护 ...'

$startup = [Environment]::GetFolderPath('Startup')
$cmdPath = Join-Path $startup 'WorkBuddyAnimeWatcher.cmd'
if (Test-Path -LiteralPath $cmdPath) {
    Remove-Item -LiteralPath $cmdPath -Force
    Ok '开机自启项已删除'
} else {
    Warn '开机自启项不存在，跳过'
}

# 结束正在运行的看护进程
try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*watch.ps1*' -or $_.CommandLine -like '*auto-apply.ps1*' } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            Ok "已结束看护进程 pid=$($_.ProcessId)"
        }
} catch { Warn "结束看护进程时出错: $_" }

# ==========================================================================
# 2. 定位安装目录
# ==========================================================================
Step 2 '定位 WorkBuddy 安装目录 ...'
$app = $AppPath
if (-not $app -and (Test-Path -LiteralPath $cfg)) {
    # 显式按 UTF-8 读（路径可能含中文；config.txt 由安装器写成 UTF-8 with BOM）
    $app = (Get-Content -LiteralPath $cfg -TotalCount 1 -Encoding UTF8).Trim()
    Ok "从看护配置读取: $app"
}
if (-not $app) {
    try {
        $p = Get-CimInstance Win32_Process -Filter "Name='WorkBuddy.exe'" -ErrorAction SilentlyContinue |
             Select-Object -First 1
        if ($p -and $p.ExecutablePath) { $app = Split-Path -Parent $p.ExecutablePath }
    } catch { }
}
if (-not $app) {
    Fail '无法定位安装目录，请用参数指定：uninstall.cmd -AppPath "D:\你的路径\WorkBuddy"'
    exit 1
}
Ok "安装目录: $app"

# ==========================================================================
# 3. 还原 index.html
# ==========================================================================
Step 3 '还原 index.html ...'
$target = Join-Path $app 'resources\app.asar.unpacked\renderer\index.html'
$bkFile = Join-Path $bkDir 'index.html.orig'

if ((Test-Path -LiteralPath $bkFile) -and (Test-Path -LiteralPath $target)) {
    Copy-Item -LiteralPath $bkFile -Destination $target -Force
    Ok "已用备份还原: $bkFile"
} elseif (Test-Path -LiteralPath $target) {
    Warn "没有找到备份（$bkFile），index.html 保持原样。"
    Warn '如果界面异常，请重新安装官方版本修复。'
} else {
    Fail "目标文件不存在: $target"
}

# ==========================================================================
# 4. 删除素材文件（只删我们自己部署的三个文件，逐一路径确认）
# ==========================================================================
Step 4 '清理素材文件 ...'
foreach ($f in @('resources\wb-boot.mp4', 'resources\wb-wallpaper.jpg')) {
    $full = Join-Path $app $f
    if (Test-Path -LiteralPath $full) {
        Remove-Item -LiteralPath $full -Force
        Ok "已删除 $f"
    } else {
        Warn "$f 不存在，跳过"
    }
}

Write-Host ''
Write-Host '==============================================' -ForegroundColor Magenta
Write-Host '  [DONE] 卸载完成，请重启 WorkBuddy' -ForegroundColor Magenta
Write-Host '==============================================' -ForegroundColor Magenta
Write-Host ''
Write-Host '  · 备份文件保留在: ' -NoNewline; Write-Host $bkDir -ForegroundColor DarkGray
Write-Host '  · 再次安装: 双击 install.cmd' -ForegroundColor DarkGray
Write-Host ''
