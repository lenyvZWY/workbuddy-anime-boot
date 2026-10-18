<#
.SYNOPSIS
  WorkBuddy Boot - 一键安装器 (Windows PowerShell 5.1+)
.DESCRIPTION
  把 WorkBuddy 桌面端的启动画面换成自定义动画。两套舞台可选：

    -Stage splash （默认）你自己的「WorkBuddy · 莱茵生命开屏」
                          media\wb-rhine-splash.js（134KB 自包含载荷，4.5s 五幕）
    -Stage video           workbuddy-anime-boot 的星云动画
                          media\boot.mp4（1920x1080 / 6.0s）
    -Stage 550c            550C 量子计算机开机（自播放 SVG，2.45s 矢量时间轴）

  安装器流程：
    [1] 定位 WorkBuddy 安装目录（自动探测，或用 -AppPath 指定）
    [2] 从 app.asar 头部读取"当前版本要求的 index.html 字节数"
    [3] 实时构建定制 index.html（压缩原版 CSS 腾空间 → 注入样式与脚本 → 补齐字节）
    [4] 三重校验（字节数 / 结构 / 标记）+ node --check 语法校验
    [5] 备份原文件 → 写入定制文件 → 部署素材

  安全设计：
    * Electron 按 asar 头部记录的字节数读取 unpacked 文件，写多了会被静默截断
      导致白屏 —— 所以构建完必须字节数分毫不差，否则拒绝写入。
    * 原文件首次安装自动备份到 %USERPROFILE%\.workbuddy-boot\backup\。
    * 只写安装目录里的 2 个"文件"，不新建任何文件夹
      （多余的文件夹会挡住 WorkBuddy 官方更新）。

.PARAMETER AppPath
  WorkBuddy 安装目录，例如 D:\wb\WorkBuddy。省略则自动探测。
.PARAMETER Stage
  舞台：video（默认）或 550c。
.PARAMETER DryRun
  只构建 + 校验，把成品写到本工具目录的 build\index.html，不碰安装目录。
.PARAMETER Force
  已装过时，用备份的原版重新构建并覆盖（换舞台 / 改素材后都加它）。
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install.ps1
  powershell -ExecutionPolicy Bypass -File install.ps1 -Stage splash -Force
  powershell -ExecutionPolicy Bypass -File install.ps1 -AppPath "D:\wb\WorkBuddy" -DryRun
#>
param(
    [string]$AppPath,
    [ValidateSet('splash', 'video', '550c')]
    [string]$Stage = 'splash',
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# ==========================================================================
# 0. 基础路径与输出工具
# ==========================================================================
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $root) { $root = (Get-Location).Path }

$store  = Join-Path $env:USERPROFILE '.workbuddy-boot'
$bkDir  = Join-Path $store 'backup'
$legacy = Join-Path $env:USERPROFILE '.workbuddy-550c\backup'
$buildDir = Join-Path $root 'build'

function Say($t)      { Write-Host $t }
function Step($n, $t) { Write-Host ''; Write-Host "[$n] $t" -ForegroundColor Cyan }
function Ok($t)       { Write-Host "    [OK] $t" -ForegroundColor Green }
function Warn($t)     { Write-Host "    [!]  $t" -ForegroundColor Yellow }
function Fail($t)     { Write-Host "    [X]  $t" -ForegroundColor Red }

Write-Host ''
Write-Host '==============================================' -ForegroundColor Magenta
Write-Host "  WorkBuddy Boot - Installer  [$Stage]" -ForegroundColor Magenta
Write-Host '==============================================' -ForegroundColor Magenta

# ==========================================================================
# 工具函数
# ==========================================================================

function Find-WorkBuddy {
    param([string]$Hint)
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($Hint) { [void]$candidates.Add($Hint) }

    # ① 正在运行的 WorkBuddy 进程（最可靠）
    try {
        Get-CimInstance Win32_Process -Filter "Name='WorkBuddy.exe'" -ErrorAction SilentlyContinue |
            ForEach-Object { if ($_.ExecutablePath) { [void]$candidates.Add((Split-Path -Parent $_.ExecutablePath)) } }
    } catch { }

    # ② 常见安装位置
    try {
        foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue).Root) {
            foreach ($sub in @('WorkBuddy', 'wb\WorkBuddy', 'easy\WorkBuddy', 'Apps\WorkBuddy',
                               'Program Files\WorkBuddy', 'Program Files (x86)\WorkBuddy')) {
                [void]$candidates.Add((Join-Path $drive $sub))
            }
        }
    } catch { }

    foreach ($c in ($candidates | Select-Object -Unique)) {
        if (-not $c) { continue }
        $asar = Join-Path $c 'resources\app.asar'
        $html = Join-Path $c 'resources\app.asar.unpacked\renderer\index.html'
        if ((Test-Path -LiteralPath $asar) -and (Test-Path -LiteralPath $html)) { return $c }
    }
    return $null
}

function Get-AsarIndexSize {
    param([string]$AsarPath)
    $fs = [System.IO.File]::OpenRead($AsarPath)
    try {
        $br = New-Object System.IO.BinaryReader($fs)
        $null = $br.ReadUInt32()
        $null = $br.ReadUInt32()
        $null = $br.ReadUInt32()
        $jsonLen = [int]$br.ReadUInt32()
        $br.BaseStream.Position = 16
        $bytes = $br.ReadBytes($jsonLen)
        $hdr = ([System.Text.Encoding]::UTF8.GetString($bytes)) | ConvertFrom-Json
        return [int]$hdr.files.renderer.files.'index.html'.size
    } finally { $fs.Close() }
}

function Compress-Css {
    param([string]$Css)
    $css = [regex]::Replace($Css, '/\*.*?\*/', '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $out = ''
    foreach ($ln in ($css -split "`r?`n")) {
        $t = $ln.Trim()
        if ($t -ne '') { $out += $t }
    }
    return $out
}

function Compress-Js {
    <#
      去块注释 + 去空行 + 每行 trim；只有当行尾是 ; { } , 时才直接拼接下一行，
      否则保留换行，防止两条语句被粘连。所有源文件注释必须用块注释 /* */。
    #>
    param([string]$Js)
    $js = [regex]::Replace($Js, '/\*.*?\*/', '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ln in ($js -split "`r?`n")) {
        $t = $ln.Trim()
        if ($t -eq '') { continue }
        [void]$sb.Append($t)
        if (-not ($t.EndsWith(';') -or $t.EndsWith('{') -or $t.EndsWith('}') -or $t.EndsWith(','))) {
            [void]$sb.Append("`n")
        }
    }
    return $sb.ToString()
}

function Verify-Balanced {
    param([string]$Code)
    foreach ($pair in @(@('(', ')'), @('{', '}'), @('[', ']'))) {
        $open = ([regex]::Matches($Code, [regex]::Escape($pair[0]))).Count
        $close = ([regex]::Matches($Code, [regex]::Escape($pair[1]))).Count
        if ($open -ne $close) { return "括号不平衡: $($pair[0])=$open  $($pair[1])=$close" }
    }
    return $null
}

# ==========================================================================
# 1. 定位安装目录
# ==========================================================================
Step 1 '定位 WorkBuddy 安装目录 ...'
$app = Find-WorkBuddy -Hint $AppPath
if (-not $app) {
    Fail '未找到 WorkBuddy 安装目录。'
    Say  '    请用参数指定：  install.cmd -AppPath "D:\你的路径\WorkBuddy"'
    exit 1
}
$target = Join-Path $app 'resources\app.asar.unpacked\renderer\index.html'
$asar   = Join-Path $app 'resources\app.asar'
Ok "安装目录: $app"

# ==========================================================================
# 2. 读取版本信息
# ==========================================================================
Step 2 '读取当前版本要求（asar 头部）...'
try {
    $expected = Get-AsarIndexSize -AsarPath $asar
    Ok "index.html 字节数要求: $expected"
} catch {
    Fail "无法解析 app.asar 头部: $_"
    exit 1
}

# 备份目录：首次安装前先把旧版（.workbuddy-550c）的原版备份迁移过来
if (-not (Test-Path -LiteralPath $bkDir)) { $null = New-Item -ItemType Directory -Path $bkDir -Force }
$bkFile = Join-Path $bkDir 'index.html.orig'
$legacyFile = Join-Path $legacy 'index.html.orig'
if (-not (Test-Path -LiteralPath $bkFile) -and (Test-Path -LiteralPath $legacyFile)) {
    Copy-Item -LiteralPath $legacyFile -Destination $bkFile -Force
    Ok "已沿用旧版备份的原文件: $legacyFile"
}

$origText = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)

$installed = ($origText -like '*wbboot-stage*') -or ($origText -like '*wb550c-stage*')
if ($installed) {
    if ($Force -and (Test-Path -LiteralPath $bkFile)) {
        Warn '检测到已装过启动动画，-Force：改用备份的原版重新构建'
        $origText = [System.IO.File]::ReadAllText($bkFile, [System.Text.Encoding]::UTF8)
    } else {
        Warn '检测到启动动画已装过（文件里已有注入标记）。'
        Say  '    换舞台 / 改素材后重装请加 -Force；或先运行 uninstall.cmd 还原。'
        exit 1
    }
}

# ==========================================================================
# 3. 构建定制 index.html
# ==========================================================================
Step 3 "构建定制 index.html（舞台: $Stage）..."

# ---- 3.0 舞台清单 ----
if ($Stage -eq 'splash') {
    $cssFile  = Join-Path $root 'src\stage-splash.css'
    $jsFile   = Join-Path $root 'src\stage-splash.js'
    $mediaSrc = Join-Path $root 'media\wb-rhine-splash.js'
    $mediaDst = 'wb-rhine-splash.js'
    $token    = '__ASSET_PATH__'
} elseif ($Stage -eq 'video') {
    $cssFile  = Join-Path $root 'src\stage-video.css'
    $jsFile   = Join-Path $root 'src\stage-video.js'
    $mediaSrc = Join-Path $root 'media\boot.mp4'
    $mediaDst = 'wb-boot.mp4'
    $token    = '__BOOT_MP4__'
} else {
    $cssFile  = Join-Path $root 'src\stage-550c.css'
    $jsFile   = Join-Path $root 'src\stage-550c.js'
    $mediaSrc = Join-Path $root 'media\wb-550c-logo.svg'
    $mediaDst = 'wb-550c-logo.svg'
    $token    = '__LOGO_SVG__'
}
$others = @('wb-rhine-splash.js', 'wb-boot.mp4', 'wb-550c-logo.svg') | Where-Object { $_ -ne $mediaDst }
foreach ($f in @($cssFile, $jsFile, $mediaSrc)) {
    if (-not (Test-Path -LiteralPath $f)) { Fail "缺少文件: $f"; exit 1 }
}
Ok ("素材: " + (Split-Path -Leaf $mediaSrc) + " ($((Get-Item -LiteralPath $mediaSrc).Length) 字节)")

# ---- 3.1 去掉全部 HTML 注释，腾出字节空间 ----
$built = [regex]::Replace($origText, '<!--.*?-->', '', [System.Text.RegularExpressions.RegexOptions]::Singleline)

# ---- 3.2 压缩第一个 <style> 块的 CSS ----
$m = [regex]::Match($built, '(?s)<style>(.*?)</style>')
if ($m.Success) {
    $slim = Compress-Css $m.Groups[1].Value
    $built = $built.Substring(0, $m.Index) + '<style>' + $slim + '</style>' + $built.Substring($m.Index + $m.Length)
    Ok '已压缩原版 CSS 缩进'
} else {
    Warn '原版里没有找到 <style> 块（继续，但空间可能紧张）'
}

# ---- 3.3 注入 CSS ----
$appUrl = $app.Replace('\', '/')
$css = Compress-Css ([System.IO.File]::ReadAllText($cssFile, [System.Text.Encoding]::UTF8))
$si = $built.IndexOf('</style>')
if ($si -lt 0) { Fail '找不到 </style> 注入点，版本可能不兼容'; exit 1 }
$built = $built.Substring(0, $si) + $css + $built.Substring($si)
Ok "已注入舞台样式（$([System.Text.Encoding]::UTF8.GetByteCount($css)) 字节）"

# ---- 3.4 注入 JS ----
$js = [System.IO.File]::ReadAllText($jsFile, [System.Text.Encoding]::UTF8)
if ($Stage -eq '550c') {
    # 550C 舞台直接 <img src>，要整条 local-file URL
    $js = $js.Replace($token, "local-file:///$appUrl/resources/$mediaDst")
} else {
    # splash / video 的脚本自己拼候选地址（相对路径 / local-file:/// / file://），
    # 所以这里只给裸路径，绝不能把 scheme 带进去，否则会拼出 local-file:///local-file:///…
    $js = $js.Replace($token, "$appUrl/resources/$mediaDst")
}
$js = Compress-Js $js
$err = Verify-Balanced $js
if ($err) { Fail "舞台脚本压缩校验失败（$err）"; exit 1 }
if ($js -like '*local-file:///local-file*') { Fail '素材 URL 被重复加了协议前缀，构建中止'; exit 1 }
$jsParts = '<script>' + $js + '</script>'

$bi = $built.LastIndexOf('</body>')
if ($bi -lt 0) { Fail '找不到 </body> 注入点，版本可能不兼容'; exit 1 }
$built = $built.Substring(0, $bi) + "`n" + $jsParts + $built.Substring($bi)
Ok "已注入舞台脚本（$([System.Text.Encoding]::UTF8.GetByteCount($js)) 字节）"

# ---- 3.5 字节数对齐 ----
$bytesNow = [System.Text.Encoding]::UTF8.GetByteCount($built)
if ($bytesNow -gt $expected) {
    Fail "构建结果超出 $($bytesNow - $expected) 字节 —— 此版本不兼容。"
    Say  "    （构建 $bytesNow / 允许 $expected）"
    exit 1
}
$room = $expected - $bytesNow
$built += ' ' * $room
Ok "字节数对齐: $expected / $expected（$room 字节余量用空格补齐）"

# ---- 3.6 最终完整性校验 ----
$finalBytes = [System.Text.Encoding]::UTF8.GetByteCount($built)
if ($finalBytes -ne $expected) { Fail "字节数校验失败: $finalBytes != $expected"; exit 1 }
if (-not $built.TrimEnd().EndsWith('</html>')) { Fail '结构校验失败：缺少 </html> 结尾'; exit 1 }
if ($built -notlike '*skeleton-root*') { Fail '结构校验失败：缺少骨架屏节点'; exit 1 }
if ($built -notlike '*wbboot-stage*') { Fail '结构校验失败：缺少注入标记'; exit 1 }
if ($Stage -eq 'video'  -and $built -notlike '*wbboot-video*')       { Fail '结构校验失败：缺少视频标记'; exit 1 }
if ($Stage -eq '550c'   -and $built -notlike '*wb-550c-logo.svg*')   { Fail '结构校验失败：缺少 550C 素材路径'; exit 1 }
if ($Stage -eq 'splash' -and $built -notlike '*wb-rhine-splash.js*') { Fail '结构校验失败：缺少莱茵载荷路径'; exit 1 }
Ok '完整性校验通过（字节数 / 结构 / 标记）'

# ---- 3.7 node --check 语法验证 ----
$nodeCandidates = @((Join-Path $env:USERPROFILE '.workbuddy\binaries\node\versions\22.22.2-6\node.exe'))
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if ($nodeCmd) { $nodeCandidates += $nodeCmd.Source }
$nodeExe = $null
foreach ($n in $nodeCandidates) { if ($n -and (Test-Path -LiteralPath $n)) { $nodeExe = $n; break } }
if ($nodeExe) {
    $tmp = Join-Path $env:TEMP ('wbboot-check-' + [guid]::NewGuid().ToString('N') + '.js')
    try {
        [System.IO.File]::WriteAllText($tmp, $js, (New-Object System.Text.UTF8Encoding($false)))
        $null = & $nodeExe --check $tmp 2>&1
        if ($LASTEXITCODE -ne 0) { Fail 'node --check 未通过，已中止（未写入任何文件）'; exit 1 }
        Ok 'node --check 语法验证通过'
    } catch {
        Warn "跳过 node 语法验证: $_"
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
} else {
    Warn '未检测到 Node.js，跳过 JS 语法验证'
}

# ==========================================================================
# 4. 写入（DryRun 只落盘到 build\）
# ==========================================================================
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if ($DryRun) {
    Step 4 'DryRun：只输出到 build\index.html（未改动安装目录）'
    if (-not (Test-Path -LiteralPath $buildDir)) { $null = New-Item -ItemType Directory -Path $buildDir -Force }
    [System.IO.File]::WriteAllText((Join-Path $buildDir 'index.html'), $built, $utf8NoBom)
    Ok "已输出 build\index.html（$expected 字节）"
    exit 0
}

Step 4 '写入文件 ...'
if (-not (Test-Path -LiteralPath $bkFile)) {
    Copy-Item -LiteralPath $target -Destination $bkFile -Force
    Ok "已备份原文件 -> $bkFile"
} else {
    Ok "原版备份已存在（保留首次备份，不覆盖）: $bkFile"
}

[System.IO.File]::WriteAllText($target, $built, $utf8NoBom)
Ok "已写入 index.html（$expected 字节）"

$resDir = Join-Path $app 'resources'
Copy-Item -LiteralPath $mediaSrc -Destination (Join-Path $resDir $mediaDst) -Force
Ok "已部署素材 -> resources\$mediaDst"

# 换舞台时清掉上一个舞台的素材（都是本工具写的文件）
foreach ($o in $others) {
    $old = Join-Path $resDir $o
    if (Test-Path -LiteralPath $old) {
        Remove-Item -LiteralPath $old -Force
        Ok "已清理其它舞台的素材 -> resources\$o"
    }
}

Write-Host ''
Write-Host '==============================================' -ForegroundColor Magenta
Write-Host '  [DONE] 安装完成！重启 WorkBuddy 查看效果' -ForegroundColor Magenta
Write-Host '==============================================' -ForegroundColor Magenta
Say ''
if ($Stage -eq 'splash') {
    Say '  启动时播放你的莱茵生命开屏（media\wb-rhine-splash.js，4.5s 五幕）：'
    Say '  权限核验 → 欢迎锁屏 → 模块瓦片 → 会话 → 门扇开启。'
    Say '  载荷播完会自行移除，应用就绪即撤底板；载荷没起来立刻撤底板，不会黑屏。'
} elseif ($Stage -eq 'video') {
    Say '  启动时播放你仓库的动画（media\boot.mp4，1080p/6s）：'
    Say '  星云汇聚 → 光环亮起 → WorkBuddy 字标定格。'
    Say '  应用就绪且视频播完 → 黑幕 0.56s 淡出，界面无缝浮出；应用慢就停在末帧。'
} else {
    Say '  启动时播放 550C 开机动画：6 个字形逐个擦除 → glow 呼吸 → 光标闪烁（2.45s）。'
    Say '  应用就绪后黑幕 0.56s 淡出，界面无缝浮出。'
}
Say '  点击 / Esc 随时跳过。'
Say ''
Say "  卸载：运行 uninstall.cmd（备份在 $bkDir）"
Say '  换舞台：install.cmd -Stage video -Force  /  -Stage 550c -Force  /  -Stage splash -Force'
Say ''
