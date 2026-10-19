<#
.SYNOPSIS
  WorkBuddy Anime Boot - 一键安装器 (Windows PowerShell 5.1+)
.DESCRIPTION
  给 WorkBuddy 桌面端加上「动漫启动动画 + 全屏壁纸背景 + 深色玻璃面板」。

  安装器流程：
    [1] 定位 WorkBuddy 安装目录（自动探测，或用 -AppPath 指定）
    [2] 从 app.asar 头部读取"当前版本要求的 index.html 字节数"
    [3] 在本地实时构建定制 index.html（读取 src/ 下的模板，注入）
    [4] 三重校验后备份原文件、写入定制文件、部署素材
    [5] 可选：安装"WorkBuddy 更新后自动修复皮肤"的后台看护

  安全设计（这是本项目踩坑最多的地方）：
    * Electron 对 app.asar.unpacked 的文件按 asar 头部记录的字节数读取，
      写入的文件字节数必须分毫不差，否则界面白屏 —— 所以 [3] 构建完成
      后必须通过字节数 + 结构完整性校验，否则拒绝写入。
    * 原文件首次安装时自动备份到 %USERPROFILE%\.workbuddy-anime\backup\。
    * 所有改动只涉及安装目录内 3 个"文件"，不新建任何文件夹
      （多余的文件夹会挡住 WorkBuddy 官方更新，教训见 docs/HOW-IT-WORKS.md）。

.PARAMETER AppPath
  WorkBuddy 安装目录，例如 E:\easy\WorkBuddy。省略则自动探测。
.PARAMETER InstallWatcher
  同时安装"更新后自动修复"看护（推荐）。
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install.ps1
  powershell -ExecutionPolicy Bypass -File install.ps1 -AppPath "D:\Apps\WorkBuddy" -InstallWatcher
#>
param(
    [string]$AppPath,
    [switch]$InstallWatcher
)

$ErrorActionPreference = 'Stop'

# ==========================================================================
# 0. 基础路径与输出工具
# ==========================================================================
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $root) { $root = (Get-Location).Path }

$store  = Join-Path $env:USERPROFILE '.workbuddy-anime'         # 数据目录（备份/看护都放这，不碰安装目录）
$bkDir  = Join-Path $store 'backup'

function Say($t)      { Write-Host $t }
function Step($n, $t) { Write-Host ''; Write-Host "[$n] $t" -ForegroundColor Cyan }
function Ok($t)       { Write-Host "    [OK] $t" -ForegroundColor Green }
function Warn($t)     { Write-Host "    [!]  $t" -ForegroundColor Yellow }
function Fail($t)     { Write-Host "    [X]  $t" -ForegroundColor Red }

Write-Host ''
Write-Host '==============================================' -ForegroundColor Magenta
Write-Host '  WorkBuddy Anime Boot - Installer' -ForegroundColor Magenta
Write-Host '==============================================' -ForegroundColor Magenta

# ==========================================================================
# 工具函数
# ==========================================================================

function Find-WorkBuddy {
    <# 定位 WorkBuddy 安装目录：显式参数 → 运行中进程 → 常见路径 #>
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
            foreach ($sub in @('WorkBuddy', 'easy\WorkBuddy', 'Apps\WorkBuddy', 'Program Files\WorkBuddy', 'Program Files (x86)\WorkBuddy', 'Programs\WorkBuddy')) {
                [void]$candidates.Add((Join-Path $drive $sub))
            }
        }
    } catch { }

    # 校验：必须同时存在 app.asar 与 unpacked 的 index.html
    foreach ($c in ($candidates | Select-Object -Unique)) {
        if (-not $c) { continue }
        $asar = Join-Path $c 'resources\app.asar'
        $html = Join-Path $c 'resources\app.asar.unpacked\renderer\index.html'
        if ((Test-Path -LiteralPath $asar) -and (Test-Path -LiteralPath $html)) { return $c }
    }
    return $null
}

function Get-AsarIndexSize {
    <# 读取 app.asar 头部，返回 renderer/index.html 应有的字节数 #>
    param([string]$AsarPath)
    $fs = [System.IO.File]::OpenRead($AsarPath)
    try {
        $br = New-Object System.IO.BinaryReader($fs)
        $null = $br.ReadUInt32()                        # 4
        $null = $br.ReadUInt32()                        # pickle 长度
        $null = $br.ReadUInt32()                        # 头部长度
        $jsonLen = [int]$br.ReadUInt32()                # JSON 实际长度
        $br.BaseStream.Position = 16
        $bytes = $br.ReadBytes($jsonLen)
        $hdr = ([System.Text.Encoding]::UTF8.GetString($bytes)) | ConvertFrom-Json
        return [int]$hdr.files.renderer.files.'index.html'.size
    } finally { $fs.Close() }
}

function Compress-Css {
    <# CSS 压缩：去块注释 + 去空行 + 每行 trim + 直接拼接（CSS 语法对换行不敏感） #>
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
      JS 压缩：去块注释 + 去空行 + 每行 trim；
      【关键安全规则】只有当行尾是 ; { } , 时才把下一行直接拼接，
      否则保留换行 —— 防止两条语句被粘连导致语法错误。
      模板中的注释必须全部使用块注释（/* */），不能用行注释（//）。
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

function Verify-Injection {
    <# 括号平衡粗检（忽略字符串内容不完美，但能挡住绝大多数结构性错误） #>
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
    Say  '    （如果你知道安装位置，也可以直接把该文件夹拖到 install.cmd 上）'
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

$origText = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)

# 已安装检测：避免在同一文件上重复注入（会导致字节数溢出）
if ($origText -like '*wb-anime-bg*') {
    Warn '检测到皮肤已安装过（文件里已有 wb-anime-bg 标记）。'
    Say  '    如需重新安装：先运行 uninstall.cmd 还原，再运行本安装器。'
    exit 1
}

# ==========================================================================
# 3. 构建定制 index.html
# ==========================================================================
Step 3 '构建定制 index.html ...'

$mediaBoot = Join-Path $root 'media\boot.mp4'
$mediaWall = Join-Path $root 'media\wallpaper.jpg'
$hasVideo = Test-Path -LiteralPath $mediaBoot
$hasWall  = Test-Path -LiteralPath $mediaWall
if ($hasVideo) { Ok '启动动画: media\boot.mp4' } else { Warn '未找到 media\boot.mp4，跳过启动动画' }
if ($hasWall) { Ok '壁纸素材: media\wallpaper.jpg' } else { Warn '未找到 media\wallpaper.jpg，跳过壁纸背景' }
if (-not $hasVideo -and -not $hasWall) {
    Fail 'media 目录里没有任何素材（boot.mp4 / wallpaper.jpg），没有东西可装。'
    exit 1
}

# ---- 3.1 去掉全部 HTML 注释，腾出字节空间 ----
$built = [regex]::Replace($origText, '<!--.*?-->', '', [System.Text.RegularExpressions.RegexOptions]::Singleline)

# ---- 3.2 压缩第一个 <style> 块的 CSS（去注释、去缩进）----
$m = [regex]::Match($built, '(?s)<style>(.*?)</style>')
if ($m.Success) {
    $slim = Compress-Css $m.Groups[1].Value
    $built = $built.Substring(0, $m.Index) + '<style>' + $slim + '</style>' + $built.Substring($m.Index + $m.Length)
    Ok '已压缩原版 CSS 缩进'
} else {
    Warn '原版里没有找到 <style> 块（继续，但空间可能紧张）'
}

# ---- 3.3 注入 CSS ----
$appUrl = $app.Replace('\', '/')           # E:\easy\WorkBuddy -> E:/easy/WorkBuddy

$cssParts = ''
$cssParts += Compress-Css ([System.IO.File]::ReadAllText((Join-Path $root 'src\skin-dark.css'), [System.Text.Encoding]::UTF8))
if ($hasWall) {
    $w = [System.IO.File]::ReadAllText((Join-Path $root 'src\skin-wallpaper.css'), [System.Text.Encoding]::UTF8)
    $w = $w.Replace('__APP_DIR__', $appUrl)
    $cssParts += Compress-Css $w
}
if ($hasVideo) {
    $cssParts += Compress-Css ([System.IO.File]::ReadAllText((Join-Path $root 'src\boot-anime.css'), [System.Text.Encoding]::UTF8))
}

$si = $built.IndexOf('</style>')
if ($si -lt 0) { Fail '找不到 </style> 注入点，版本可能不兼容'; exit 1 }
$built = $built.Substring(0, $si) + $cssParts + $built.Substring($si)
Ok '已注入 CSS（深色玻璃 + 壁纸 + 启动动漫）'

# ---- 3.4 注入 JS ----
$jsParts = ''
if ($hasVideo) {
    $b = [System.IO.File]::ReadAllText((Join-Path $root 'src\boot.js'), [System.Text.Encoding]::UTF8)
    $b = $b.Replace('__BOOT_MP4__', "$appUrl/resources/wb-boot.mp4")
    $b = Compress-Js $b
    $err = Verify-Injection $b
    if ($err) { Fail "boot.js 压缩校验失败（$err）"; exit 1 }
    $jsParts += '<script>' + $b + '</script>'
    Ok '已注入启动动漫脚本'
}
$p = Compress-Js ([System.IO.File]::ReadAllText((Join-Path $root 'src\pass.js'), [System.Text.Encoding]::UTF8))
$err = Verify-Injection $p
if ($err) { Fail "pass.js 压缩校验失败（$err）"; exit 1 }
$jsParts += '<script>' + $p + '</script>'
Ok '已注入面板透明化保险'

$bi = $built.LastIndexOf('</body>')
if ($bi -lt 0) { Fail '找不到 </body> 注入点，版本可能不兼容'; exit 1 }
$built = $built.Substring(0, $bi) + "`n" + $jsParts + $built.Substring($bi)

# ---- 3.5 字节数对齐（精确补齐空格）----
$bytesNow = [System.Text.Encoding]::UTF8.GetByteCount($built)
if ($bytesNow -gt $expected) {
    Fail "构建结果超出 $($bytesNow - $expected) 字节 —— 此版本不兼容，请到项目主页提 Issue。"
    Say  "    （构建 $bytesNow / 允许 $expected）"
    exit 1
}
$built += ' ' * ($expected - $bytesNow)
Ok "字节数对齐: $expected / $expected (余量 $($expected - $bytesNow) 已用空格补齐)"

# ---- 3.6 最终完整性校验（写入前最后一道闸）----
$finalBytes = [System.Text.Encoding]::UTF8.GetByteCount($built)
if ($finalBytes -ne $expected) { Fail "字节数校验失败: $finalBytes != $expected"; exit 1 }
$trimEnd = $built.TrimEnd()
if (-not $trimEnd.EndsWith('</html>')) { Fail '结构校验失败：缺少 </html> 结尾'; exit 1 }
if ($built -notlike '*skeleton-root*') { Fail '结构校验失败：缺少骨架屏节点'; exit 1 }
if ($built -notlike '*wb-anime-bg*')   { Fail '结构校验失败：缺少注入标记'; exit 1 }
Ok '完整性校验通过（字节数 / 结构 / 标记）'

# ---- 3.7 【可选】本机装有 Node.js 时，用 node --check 验证注入 JS 语法 ----
$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) {
    $tmp = Join-Path $env:TEMP ('wb-anime-check-' + [guid]::NewGuid().ToString('N') + '.js')
    try {
        [System.IO.File]::WriteAllText($tmp, ($jsParts -replace '</?script>', ''), (New-Object System.Text.UTF8Encoding($false)))
        $null = & node --check $tmp 2>&1
        if ($LASTEXITCODE -ne 0) { Fail 'node --check 未通过，已中止（不写入任何文件）'; exit 1 }
        Ok 'node --check 语法验证通过'
    } catch {
        Warn "跳过 node 语法验证: $_"
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
} else {
    Warn '未检测到 Node.js，跳过 JS 语法验证（不影响安装）'
}

# ==========================================================================
# 4. 备份 + 写入 + 部署素材
# ==========================================================================
Step 4 '写入文件 ...'

if (-not (Test-Path -LiteralPath $bkDir)) { $null = New-Item -ItemType Directory -Path $bkDir -Force }
$bkFile = Join-Path $bkDir 'index.html.orig'
if (-not (Test-Path -LiteralPath $bkFile)) {
    Copy-Item -LiteralPath $target -Destination $bkFile -Force
    Ok "已备份原文件 -> $bkFile"
} else {
    Ok "原版备份已存在（保留首次备份不覆盖）: $bkFile"
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($target, $built, $utf8NoBom)
Ok "已写入 index.html（$expected 字节）"

$resDir = Join-Path $app 'resources'
if ($hasVideo) {
    Copy-Item -LiteralPath $mediaBoot -Destination (Join-Path $resDir 'wb-boot.mp4') -Force
    Ok '已部署启动动画 -> resources\wb-boot.mp4'
}
if ($hasWall) {
    Copy-Item -LiteralPath $mediaWall -Destination (Join-Path $resDir 'wb-wallpaper.jpg') -Force
    Ok '已部署壁纸 -> resources\wb-wallpaper.jpg'
}

# ==========================================================================
# 5. 【可选】安装更新看护
# ==========================================================================
if ($InstallWatcher) {
    Step 5 '安装"更新后自动修复"看护 ...'

    $wdir = Join-Path $store 'watcher'
    if (-not (Test-Path -LiteralPath $wdir)) { $null = New-Item -ItemType Directory -Path $wdir -Force }

    Copy-Item -LiteralPath (Join-Path $root 'tools\auto-apply.ps1') -Destination $wdir -Force
    Copy-Item -LiteralPath (Join-Path $root 'tools\watch.ps1')      -Destination $wdir -Force
    # 看护自愈时需要的"成品三件套"（文件名必须与 auto-apply.ps1 期望一致）
    [System.IO.File]::WriteAllText((Join-Path $wdir 'index.html'), $built, $utf8NoBom)
    if ($hasVideo) { Copy-Item -LiteralPath $mediaBoot -Destination (Join-Path $wdir 'wb-boot.mp4') -Force }
    if ($hasWall)  { Copy-Item -LiteralPath $mediaWall -Destination (Join-Path $wdir 'wb-wallpaper.jpg') -Force }
    # 记录安装路径（auto-apply.ps1 会读取）
    # 注意：必须写成 UTF-8 with BOM —— PS 5.1 的 Get-Content 默认按系统 ANSI 编码
    # 读取无 BOM 文件，路径含中文时会读错；带 BOM 才能被正确识别为 UTF-8。
    [System.IO.File]::WriteAllText((Join-Path $wdir 'config.txt'), $app, (New-Object System.Text.UTF8Encoding($true)))
    Ok "看护套件 -> $wdir"

    # 开机自启项：用 VBS 启动器（window style 0 = 完全隐藏，全程无黑窗）
    # 旧方案是 .cmd 批处理 —— 每次开机必然弹出一闪而过的控制台窗口，已在 v1.0.1 废弃。
    $startup   = [Environment]::GetFolderPath('Startup')
    $watchFile = Join-Path $wdir 'watch.ps1'
    $vbsText = "' WorkBuddy Anime Boot - silent watcher launcher`r`n" +
               "' window style 0 = hidden, no console window at all`r`n" +
               'Set sh = CreateObject("WScript.Shell")' + "`r`n" +
               'sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""' + $watchFile + '""", 0, False' + "`r`n"
    # 用系统 ANSI 编码写：wscript 可直接读取，且能正确处理中文用户名路径
    $vbsEnc = [System.Text.Encoding]::Default
    $vbsPath = Join-Path $startup 'WorkBuddyAnimeWatcher.vbs'
    [System.IO.File]::WriteAllText($vbsPath, $vbsText, $vbsEnc)
    [System.IO.File]::WriteAllText((Join-Path $wdir 'start-watcher.vbs'), $vbsText, $vbsEnc)
    # 清理旧版遗留的 .cmd 自启项，避免同时启动两个看护
    $oldCmd = Join-Path $startup 'WorkBuddyAnimeWatcher.cmd'
    if (Test-Path -LiteralPath $oldCmd) {
        Remove-Item -LiteralPath $oldCmd -Force
        Say '    已清理旧版 .cmd 自启项'
    }
    Ok "开机自启已安装（无窗口）-> $vbsPath"
    Say '    （下次登录 Windows 后自动生效；现在想立刻启用，双击 start-watcher.vbs）'
} else {
    Step 5 '跳过看护安装（未指定 -InstallWatcher）'
    Say '    建议加上该参数安装看护，WorkBuddy 更新后皮肤会自动恢复。'
}

# ==========================================================================
# 完成
# ==========================================================================
Write-Host ''
Write-Host '==============================================' -ForegroundColor Magenta
Write-Host '  [DONE] 安装完成！请重启 WorkBuddy 查看效果' -ForegroundColor Magenta
Write-Host '==============================================' -ForegroundColor Magenta
Say ''
Say '  想要什么效果：'
Say '    · 启动时播放动漫   （media\boot.mp4）'
Say '    · 界面透出壁纸     （media\wallpaper.jpg）'
Say '    · 深色玻璃面板     （自动应用）'
Say ''
Say '  换素材：替换 media\ 下的文件后重新运行本安装器即可（先运行 uninstall.cmd）。'
Say '  卸载： 运行 uninstall.cmd（或 uninstall.ps1）。'
Say ''
