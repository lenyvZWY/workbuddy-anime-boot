# ==========================================================================
# WorkBuddy Anime Boot - 自动修复（看护核心）
# --------------------------------------------------------------------------
# 由 watch.ps1 每 3 分钟调用一次；平时是"静默空转"，只在一种情况下干活：
#    WorkBuddy 自动更新后，会把 resources\ 整个替换成官方原版
#    → 我们的 index.html 和素材被冲掉 → 本脚本自动把皮肤装回去。
#
# 安全三道闸（防止版本变化时装错导致白屏）：
#   ① 读 app.asar 头部，得到"当前版本要求的 index.html 字节数"，
#      与我们 kit 里的成品比对，不一致 → 拒绝操作（等人工为新版重新构建）。
#   ② 实时文件里已有 wb-anime-bg 标记 → 说明皮肤健在，直接退出。
#   ③ 覆盖前先把实时文件备份到 kit\backup-live\（安装目录之外）。
#
# 安装目录归属：从同目录 config.txt 第一行读取（安装器写入）。
# ==========================================================================
$ErrorActionPreference = 'SilentlyContinue'

$kit     = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfg     = Join-Path $kit 'config.txt'
$app     = ''
# 显式按 UTF-8 读（路径可能含中文；config.txt 由安装器写成 UTF-8 with BOM）
if (Test-Path -LiteralPath $cfg) { $app = (Get-Content -LiteralPath $cfg -TotalCount 1 -Encoding UTF8).Trim() }
$log     = Join-Path $kit 'auto-apply.log'

function L($m) { "$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))  $m" | Out-File -Append -Encoding utf8 -LiteralPath $log }

if (-not $app) { L 'skip: config.txt missing or empty'; exit 0 }

$target  = Join-Path $app 'resources\app.asar.unpacked\renderer\index.html'
$asar    = Join-Path $app 'resources\app.asar'
$kitHtml = Join-Path $kit 'index.html'

if (-not (Test-Path -LiteralPath $target))  { L "skip: target not found"; exit 0 }
if (-not (Test-Path -LiteralPath $asar))    { L "skip: app.asar not found"; exit 0 }
if (-not (Test-Path -LiteralPath $kitHtml)) { L "skip: kit index.html missing"; exit 0 }

# ---- 闸①：读取当前版本要求的字节数 ----
try {
    $fs = [System.IO.File]::OpenRead($asar)
    $br = New-Object System.IO.BinaryReader($fs)
    $null = $br.ReadUInt32()
    $null = $br.ReadUInt32()
    $null = $br.ReadUInt32()
    $jsonLen = [int]$br.ReadUInt32()
    $br.BaseStream.Position = 16
    $bytes = $br.ReadBytes($jsonLen)
    $fs.Close()
    $hdr = ([System.Text.Encoding]::UTF8.GetString($bytes)) | ConvertFrom-Json
    $expected = [int]$hdr.files.renderer.files.'index.html'.size
} catch {
    L "skip: cannot parse asar header - $_"
    exit 0
}

$kitSize = (Get-Item -LiteralPath $kitHtml).Length
if ($expected -ne $kitSize) {
    L "WARN 版本变化: asar 要求 $expected 字节，但 kit 里是 $kitSize 字节 —— 不执行（需要为新版重新构建）"
    exit 0
}

# ---- 闸②：已经装好了？ ----
$live = Get-Content -LiteralPath $target -Raw -Encoding UTF8
if ($live -like '*wb-anime-bg*') { exit 0 }   # 静默空转

# ---- 闸③：备份现有文件到 kit 目录（安装目录之外），然后装回 ----
$bdir = Join-Path $kit 'backup-live'
if (-not (Test-Path -LiteralPath $bdir)) { $null = New-Item -ItemType Directory -Path $bdir -Force }
Copy-Item -LiteralPath $target -Destination (Join-Path $bdir 'index.html.live.bak') -Force

Copy-Item -LiteralPath $kitHtml -Destination $target -Force
if (Test-Path -LiteralPath (Join-Path $kit 'wb-boot.mp4')) {
    Copy-Item -LiteralPath (Join-Path $kit 'wb-boot.mp4') -Destination (Join-Path $app 'resources\wb-boot.mp4') -Force
}
if (Test-Path -LiteralPath (Join-Path $kit 'wb-wallpaper.jpg')) {
    Copy-Item -LiteralPath (Join-Path $kit 'wb-wallpaper.jpg') -Destination (Join-Path $app 'resources\wb-wallpaper.jpg') -Force
}
L "已自动装回皮肤（expected=$expected）—— 重启 WorkBuddy 即可看到"
exit 0
