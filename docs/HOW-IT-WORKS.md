# 工作原理与踩坑记录

> 本文写给想改代码 / 二创 / 排障的人。所有结论都是实战验证过的，尤其是那些"看起来没问题、实际会白屏"的坑。

## 1. WorkBuddy 的技术结构

WorkBuddy 桌面端是 **Electron** 应用（实测 v5.8.x，Electron 37 / Chrome 138）：

```text
<安装目录>\
├── WorkBuddy.exe
├── resources\
│   ├── app.asar                     ← 主程序代码（打包，98MB 左右）
│   └── app.asar.unpacked\           ← 部分文件被"解包"放在外面
│       └── renderer\
│           └── index.html           ← ★ 我们要改的"进入界面"
└── ...
```

关键事实：**`renderer/` 整个目录是 unpacked 的**，直接改里面的文件即可，不需要重新打包 asar。

### 什么是"进入界面"（骨架屏）

启动 WorkBuddy 时，在 React 主界面就绪之前，先显示的是一个**骨架屏**（skeleton）：

```text
#skeleton-root
 ├── .sk-titlebar      顶栏占位块
 ├── .sk-sidebar       侧栏占位块（带 sk-shimmer 流光动画）
 ├── .sk-content       内容区占位块
 ├── .sk-statusbar     状态栏占位块
 └── #sk-overlay       启动失败时的错误遮罩
```

React 主界面挂载完成后，会调用 `window.__removeSkeleton()` 把骨架屏拆掉 —— **这就是我们插入启动动画的窗口期**。

## 2. ★★★ 最重要的坑：asar 的字节数陷阱

**现象**：改完 `index.html` 后重启，界面**整片白屏**，且没有任何报错、没有任何日志。

**原因**：Electron 在读取 `app.asar.unpacked` 里的文件时，是**按 `app.asar` 头部记录的原始 size 来截断读取的**：

```text
app.asar 头部（JSON）记录：
  files.renderer.files['index.html'] = { size: 27841, unpacked: true, ... }
                               ↑ 这里写着 27841
读取时：从 index.html 里读 27841 字节，多的部分直接丢弃
```

所以如果你把文件改成 35922 字节，**它会静默地只读前 27841 字节**。
截断点如果落在你注入的 `<style>` 或 `<script>` 中间：

- HTML 结构不完整 → 整页白屏
- 无任何报错（连 DevTools 都看不出所以然）

**解决方案（本项目采用的）**：

1. 构建前先读 asar 头部，拿到"当前版本要求的字节数"；
2. 构建时**删掉原版的 HTML 注释 / CSS 注释和缩进**腾出空间；
3. 注入定制内容后，**用空格补齐到精确等于头部记录的字节数**；
4. 写入前做三重校验（字节数 / 结构 / 标记）。

### 怎么读 asar 头部的 size

```powershell
$fs = [System.IO.File]::OpenRead($asarPath)
$br = New-Object System.IO.BinaryReader($fs)
$null = $br.ReadUInt32()          # 固定 4
$null = $br.ReadUInt32()          # pickle 载荷长度
$null = $br.ReadUInt32()          # 头部长度(+4)
$jsonLen = [int]$br.ReadUInt32()  # JSON 实际长度
$br.BaseStream.Position = 16      # JSON 从 offset 16 开始
$bytes = $br.ReadBytes($jsonLen)
$hdr = ([System.Text.Encoding]::UTF8.GetString($bytes)) | ConvertFrom-Json
$size = [int]$hdr.files.renderer.files.'index.html'.size
```

（该格式是 Chromium pickles 的经典布局：4 字节对齐标记 + 载荷长度 + 头部长度 + JSON 长度，随后 JSON。）

## 3. 注入机制

注入分四块（源码都在 `src/`，安装器会压缩后注入）：

### ① 深色玻璃主题（skin-dark.css）

覆盖 WorkBuddy 的 CSS 变量 + 强制 `color-scheme: dark`，把面板背景换成半透明深色：

```css
html:root, html:root body {
  --cb-bg-primary: #090b1173 !important;   /* 45% 黑 */
  --wb-sidebar-bg: #090b1166 !important;   /* 侧栏 */
  ...
}
```

- 为什么挂在 `html:root` 上？为了**压过** WorkBuddy 自身皮肤系统的变量定义（配合 `!important`）。
- 变量名是从 WorkBuddy 自带的 `skin.v2.css` 里 grep 出来的（`--cb-*` / `--wb-*` / `--vscode-*` 三族）。

### ② 壁纸铺底（skin-wallpaper.css）

用 `body::before` 固定定位铺满全屏（`z-index:0`），上面叠一层深色渐变膜把壁纸压暗，保证浅色文字可读：

```css
body::before {
  background-image:
    linear-gradient(rgba(6,8,14,.42), rgba(6,8,14,.52)),  /* 压暗膜 */
    url("local-file:///E:/.../resources/wb-wallpaper.jpg");
}
```

用 `local-file://` 而不是 `file://`：WorkBuddy 的 CSP 与自定义协议体系下前者才稳定可用。

### ③ 启动动漫（boot.js + boot-anime.css）

核心思路 —— **偷换 `__removeSkeleton`**：

```javascript
// 1. 在骨架屏上盖一层全屏 <video> 播放动画
// 2. 把 window.__removeSkeleton 换成"只记录、不拆除"
window.__removeSkeleton = function () { rq = true; at = Date.now(); };

// 3. 主循环 150ms 一次，满足任一条件才调用原函数真正放行：
//    · 视频播完         · 用户点击 / Esc
//    · 总时长兜底        · 加载失败 / 启动出错
```

这样"界面已经准备好了但动画还在放"成为可能，动画结束的瞬间界面无缝衔接。

### ④ 动态透明化保险（pass.js）

CSS 变量覆盖总有漏网之鱼（不同版本变量不同、React 运行时渲染的新面板）。

所以再加一道**运行时保险**：持续扫描所有"面积 > 视口 7% 且不透明且无背景图"的面板，把背景改成半透明深色。

关键设计：

- 用 `MutationObserver`（childList + style/class 变化）+ 300ms 节流捕获变化 —— 切换任务时 React 渲染出的新面板会被立刻处理；
- 已处理元素（内联背景色已是目标值）直接跳过 → **天然收敛，不会死循环**；
- 4.5 秒兜底轮询 + 启动阶段多次补扫。

> 早期版本的 bug：只在启动时扫 5 次就停 → 切换任务后新面板没人处理，变成纯黑。这个文件就是修复。

## 4. 为什么"更新后皮肤会消失"

WorkBuddy 自动更新时会把 `resources\` 目录**整个替换成官方版本**，于是：

- `renderer/index.html` → 变回官方原版
- `resources/wb-boot.mp4`、`wb-wallpaper.jpg` → 被删除

看护（`tools/auto-apply.ps1`）就是为此而生：每 3 分钟检查一次，发现皮肤被冲掉就用 kit 里的成品装回去。

### 看护的三道安全闸

1. **版本闸**：读 asar 头部拿到"当前版本要求字节数"，与 kit 成品不一致 → 拒绝操作（防止新版结构变化时装错白屏）；
2. **状态闸**：实时文件里已有 `wb-anime-bg` 标记 → 皮肤健在，直接退出；
3. **备份闸**：覆盖前先把现有文件备份到 kit 目录（安装目录之外）。

## 5. ★ 另一条血泪教训：不要往安装目录里放文件夹

**现象**：WorkBuddy 弹窗拒绝更新 ——

> "检测到应用安装目录下存在用户项目目录，更新会导致项目记录丢失，请先将项目迁移到其他目录后再重试更新。"

**原因**：把自制脚本包 / 备份目录（文件夹）放进了 `<安装目录>\`，被更新程序判定为"用户项目目录"。

**结论**：

- ❌ 不要在安装目录里新建**任何文件夹**
- ✅ 只写"文件"是安全的：本项目只写 3 个文件（`renderer/index.html`、`resources/wb-boot.mp4`、`resources/wb-wallpaper.jpg`），实测不影响更新
- ✅ 看护、备份、日志全部放在 `%USERPROFILE%\.workbuddy-anime\`

## 6. 调试与验证方法（无 GUI）

改这个文件最怕"改完看不出问题，重启才发现白屏"。以下是无头验证手段：

```powershell
# 1. HTML 结构 + 字节数校验（安装器内置，见 install.ps1 的 3.5 / 3.6 节）
# 2. JS 语法校验（本机有 Node.js 时自动执行）
node --check extracted.js

# 3. 括号平衡粗检
# 4. 无头 Edge 加载页面检查 DOM 是否正常挂载（需要 Edge）
msedge.exe --headless=new --dump-dom --user-data-dir=<临时目录> <index.html 路径>
```

另外两个实用技巧：

- **保留原版备份**：安装器首次安装时把原文件备份到 `%USERPROFILE%\.workbuddy-anime\backup\index.html.orig`，任何可疑情况先还原再说；
- **看日志**：看护的日志在 `%USERPROFILE%\.workbuddy-anime\watcher\auto-apply.log`。

## 7. 文件速查表

| 文件 | 作用 | 什么时候改它 |
| --- | --- | --- |
| `src/skin-dark.css` | 深色玻璃变量覆盖 | 想调面板深浅 / 适配新变量 |
| `src/skin-wallpaper.css` | 壁纸铺底 + 压暗膜 | 想调壁纸暗度 |
| `src/boot-anime.css` | 启动动画的样式 | 想改胶囊文案样式 / 跳过按钮 |
| `src/boot.js` | 启动动画逻辑 | 想改跳过行为 / 时间参数 |
| `src/pass.js` | 动态透明化保险 | 想调面积阈值 / 目标透明度 |
| `tools/auto-apply.ps1` | 看护核心 | 想改自愈策略 |
| `install.ps1` | 安装器（构建 + 三重校验） | 想改构建流程 |
