<#
.SYNOPSIS
  WorkBuddy Boot - 卸载器
.DESCRIPTION
  把 WorkBuddy 还原回官方原版启动画面：
    [1] 定位安装目录
    [2] 用备份还原 renderer/index.html（并校验字节数）
    [3] 删除安装目录里的素材文件（wb-boot.mp4 / wb-550c-logo.svg）
.PARAMETER AppPath
  WorkBuddy 安装目录。省略则自动探测。
#>
param(
    [string]$AppPath
)

$ErrorActionPreference = 'Continue'

$store  = Join-Path $env:USERPROFILE '.workbuddy-boot'
$bkDir  = Join-Path $store 'backup'
$legacy = Join-Path $env:USERPROFILE '.workbuddy-550c\backup'

function Step($n, $t) { Write-Host ''; Write-Host "[$n] $t" -ForegroundColor Cyan }
function Ok($t)       { Write-Host "    [OK] $t" -ForegroundColor Green }
function Warn($t)     { Write-Host "    [!]  $t" -ForegroundColor Yellow }
function Fail($t)     { Write-Host "    [X]  $t" -ForegroundColor Red }

Write-Host ''
Write-Host '==============================================' -ForegroundColor Magenta
Write-Host '  WorkBuddy Boot - Uninstaller' -ForegroundColor Magenta
Write-Host '==============================================' -ForegroundColor Magenta

Step 1 '定位 WorkBuddy 安装目录 ...'
$app = $AppPath
if (-not $app) {
    try {
        $p = Get-CimInstance Win32_Process -Filter "Name='WorkBuddy.exe'" -ErrorAction SilentlyContinue |
             Select-Object -First 1
        if ($p -and $p.ExecutablePath) { $app = Split-Path -Parent $p.ExecutablePath }
    } catch { }
}
if (-not $app) {
    foreach ($d in @('D:\wb\WorkBuddy', 'E:\easy\WorkBuddy', 'C:\Program Files\WorkBuddy')) {
        if (Test-Path -LiteralPath (Join-Path $d 'resources\app.asar')) { $app = $d; break }
    }
}
if (-not $app) {
    Fail '无法定位安装目录，请用参数指定：uninstall.cmd -AppPath "D:\你的路径\WorkBuddy"'
    exit 1
}
Ok "安装目录: $app"

Step 2 '还原 index.html ...'
$target = Join-Path $app 'resources\app.asar.unpacked\renderer\index.html'
$bkFile = Join-Path $bkDir 'index.html.orig'
$legacyFile = Join-Path $legacy 'index.html.orig'
if (-not (Test-Path -LiteralPath $bkFile) -and (Test-Path -LiteralPath $legacyFile)) { $bkFile = $legacyFile }

$expected = $null
try {
    $fs = [System.IO.File]::OpenRead((Join-Path $app 'resources\app.asar'))
    $br = New-Object System.IO.BinaryReader($fs)
    $null = $br.ReadUInt32(); $null = $br.ReadUInt32(); $null = $br.ReadUInt32()
    $jsonLen = [int]$br.ReadUInt32()
    $br.BaseStream.Position = 16
    $bytes = $br.ReadBytes($jsonLen)
    $expected = [int](([System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json).files.renderer.files.'index.html'.size)
    $fs.Close()
} catch { }

if ((Test-Path -LiteralPath $bkFile) -and (Test-Path -LiteralPath $target)) {
    Copy-Item -LiteralPath $bkFile -Destination $target -Force
    $actual = (Get-Item -LiteralPath $target).Length
    if ($expected -and $actual -ne $expected) {
        Warn "还原后字节数 $actual 与 asar 要求 $expected 不一致（版本已更新过？）"
        Warn '如果界面白屏，请重装官方版本。'
    } else {
        Ok "已用备份还原（$actual 字节）"
    }
} else {
    Warn "没有找到备份（$bkFile），index.html 保持原样。"
}

Step 3 '清理素材文件 ...'
foreach ($f in @('resources\wb-boot.mp4', 'resources\wb-550c-logo.svg')) {
    $full = Join-Path $app $f
    if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Force; Ok "已删除 $f" }
    else { Warn "$f 不存在，跳过" }
}

Write-Host ''
Write-Host '==============================================' -ForegroundColor Magenta
Write-Host '  [DONE] 卸载完成，请重启 WorkBuddy' -ForegroundColor Magenta
Write-Host '==============================================' -ForegroundColor Magenta
Write-Host ''
