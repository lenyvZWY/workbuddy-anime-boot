# 原理与踩坑

> 写给想改代码 / 排障的人。所有结论都是在本机 WorkBuddy 5.8.3 上实测出来的，
> 包括"看起来没问题、实际会白屏或会闪一下"的那些坑。

## 1. 三个来源是怎么拼起来的

| 来源 | 拿走了什么 |
| --- | --- |
| `lenyvZWY/workbuddy-anime-boot` | 工程骨架 + 接管思路：改 unpacked 的 `renderer/index.html`、偷换 `window.__removeSkeleton`、asar 字节数对齐、三重校验、备份/卸载；以及**启动动画本体** `media/boot.mp4` |
| `yannicksong0106/dsh-550c-boot` | 备选舞台：550C 片头（6 个字形逐个 `clip-path` 擦除 + 打字机 + glow）。它靠宿主插件插槽挂在 shadow root，WorkBuddy 没有这套体系，所以只搬动画，不搬注入方式 |
| `Voidpocket/html_550c` | 550C 字形 path 数据（在上游 `assets/550C-source.html` 里） |

## 2. WorkBuddy 这边的事实

```
D:\wb\WorkBuddy\resources\
├── app.asar                       96 MB，头部 JSON 记录每个文件的 size / offset
└── app.asar.unpacked\renderer\
    ├── index.html                 ★ 唯一可改的入口，27841 字节（= asar 头部记录的 size）
    └── assets\ ...
```

- `renderer/index.html` 是主窗口首屏，包含**骨架屏**（`#skeleton-root` + `.sk-sidebar` / `.sk-content`）
- 拆骨架屏的 `window.__removeSkeleton` 定义在 asar 内部
  `renderer/skeleton/skeleton-bootstrap.js`（不用改它，靠 index.html 末尾注入的脚本覆盖）
- 主窗口那支签名是 `__removeSkeleton(o)`：`o.animate === true` 时走 200ms CSS 淡出，
  否则 `display:none` + `remove()` —— **覆盖时必须把参数原样转发**（`orig.apply(null, argv)`）

### ★ 字节数陷阱

Electron 读 unpacked 文件时按 asar 头部记录的 `size` 截断读取。写多了 → 静默截断 → 白屏且无报错。
所以写回去的字节数必须分毫不差。本机复核：头部 `size = 27841`，文件也是 27841。✅

### CSP（从 app.asar 里挖出来的原文）

```
script-src 'self' 'unsafe-inline' 'unsafe-eval' blob: local-file: … wb-seed:
img-src    'self' data: blob: https: http://127.0.0.1:* local-file: wb-extension: wb-cover: …
media-src  'self' data: blob: local-file: https: …
frame-src  'self' blob: wb-extension: https://*.qq.com …
```

`local-file:` 在 `script/img/media` 里，**唯独不在 `frame-src`**。这条决定了两件事：

1. 视频 / SVG 必须走 `<video src>` / `<img src>` + `local-file:///D:/…`，不能用 iframe 装页面；
2. 用 `local-file://` 而不是 `file://` 才稳定（`file://` 只作兜底）。

## 3. 视频舞台（`-Stage video`）相对上游改了 5 处

上游 `boot.js` 是能跑的，但直接搬过来会有三个体验问题。改动都在 `src/stage-video.js`：

### ① 挂载点：`skeleton-root` 内部 → `body`

上游没有淡出，塞进骨架屏没问题。我们要 0.56s 淡出，挂在骨架屏里就会翻车：

```
淡出中 → 应用调用 __removeSkeleton() → skeleton-root 整个 remove()
       → 挂在里面的启动层一起消失 → 淡出变成瞬间闪断
```

实测复现：淡出开始 150ms 后 `opacity` 直接读到 `0.00`（元素已不在渲染树里）。
改成 `document.body.appendChild(st)`：骨架屏在下面被拆、真实界面在下面渲染，
启动层作为 body 上的最后一张"黑幕"独立淡出 → 界面从黑场里浮出来。

### ② 播完后：循环重播 → 停在末帧

素材末帧是设计好的品牌定格（光环 + `WorkBuddy` 字标）。上游在应用没就绪时
`currentTime = 0` 从头再播一遍；这里改成 `ended` 后原地停住（`video` 结束即定格最后一帧），
只有应用就绪才淡出。好处：应用慢的时候看起来是"正在启动"，而不是"动画卡了循环"。

### ③ 跳过语义：直接拆骨架屏 → 只撤黑幕

应用没就绪时提前拆骨架屏 = 一屏空白。现在跳过只 `fade()`；应用已就绪才 `pass()`。
`pass()` 里再调 `orig.apply(null, argv)`，把应用自己传的 `{animate:true}` 之类原样带回去。

### ④ 放行条件：视频播完 → 视频播完 **且** 应用就绪

```js
if (!ready) return;   // 应用没就绪 → 守在末帧
if (!ended) return;   // 视频没播完 → 让它播完
if (el < MIN) return; // 太短会像闪一下
pass(); fade();
```

### ⑤ 窗口类型闸门（新增）

次级窗口（设置 / 会话 / 合并详情 / 开发者资料 / 全局搜索 / 图片查看 / office）
加载的是**同一个** `index.html`。不设闸的话，点一下"设置"就会闪一整段开机动画。
WorkBuddy 自己的判定写在 `skeleton-bootstrap.js`：

```js
let m = l.get("windowAppId") ?? l.get("windowKind");
if (m === "settings" || m === "conversation" || m === "im-merge-detail") { …变体骨架屏… }
// 另有 developer-profile / global-search / image-viewer / office 四支
```

本工具用同一套 key 做黑名单（主窗口放行，不用去猜主窗口的 appId 是什么）：

```js
if ('|settings|conversation|im-merge-detail|developer-profile|global-search|image-viewer|office|'
      .indexOf('|' + kind + '|') > -1) return;
```

### ★ 踩坑：素材 URL 被前缀两遍

脚本自己拼 scheme（`'local-file:///' + SRC` → 失败回退 `'file:///' + SRC`），
所以安装器替换占位符时只能给**裸路径**。第一版给成了 `local-file:///D:/…`，
结果变成 `local-file:///local-file:///D:/…`，两种源全废、启动直接黑屏半秒。
现在构建期有硬校验：`if ($js -like '*local-file:///local-file*') { Fail }`。

## 4. 550C 舞台（`-Stage 550c`）

同一套壳子换素材，但载体从视频换成**自播放 SVG**：

- 6 个字形 `clip-path` 擦除 + glow 呼吸全写在 SVG 自己的 `<style>` 里（`<img>` 加载时脚本不执行，
  但声明式 CSS 动画照常播放）→ 33KB、任意 DPI 清晰、零 JS 驱动
- 时间轴：`250 + i×300ms` 起擦，每个 600ms，`2450ms` 全部落定，`2400ms` 打字机，`2950ms` 允许淡出
- 坑：上游的 `.white{fill:#fff}` 写在**页面**的 `<style>` 里，不在 `<svg>` 里 ——
  直接抽 `<svg>` 会得到全黑字形，必须把填色搬进 SVG 内部

## 5. 字节预算（本机 27841）

| 步骤 | 字节 |
| --- | --- |
| 原文件 | 27841 |
| 去掉 HTML 注释 | −2186 |
| 压缩第一个 `<style>` 的缩进/注释 | −7016 |
| **可用余量** | **约 9200** |
| 莱茵舞台注入 CSS + JS | −203 −2609 |
| 视频舞台注入 CSS + JS | −1280 −3115 |
| 550C 舞台注入 CSS + JS | −2871 −2807 |
| 剩余 | 莱茵 ≈ 6.4KB，视频 ≈ 4.8KB，550C ≈ 3.5KB（补空格） |

校验（`install.ps1` 3.5 / 3.6 节）：字节数相等 → `TrimEnd().EndsWith('</html>')` →
含 `skeleton-root` → 含 `wbboot-stage` → 含当前舞台专属标记 → `node --check`。任一不过就不写盘。

## 6. 兜底链（任何一环断了都不该白屏）

```
① 找不到 skeleton-root / 缺 .sk-sidebar、.sk-content → 直接 return，界面原样
② 次级窗口（windowAppId 命中黑名单）→ 直接 return
③ 素材加载失败 → 换 file:// 再试一次 → 仍失败 → 立刻淡出黑幕，把骨架屏交还用户
④ 播到一半解码出错 → 立刻淡出
⑤ 启动失败遮罩 #sk-overlay 出现 → 立刻 pass() + fade()，把错误界面交给用户
⑥ 应用 45s 不就绪 → 只 fade()（露骨架屏），不 pass()，避免拆早了留空白
⑦ 整段 try/catch；JS 语法在安装前由 node --check 拦一遍
```

## 7. 单文件预览页：体积 / 长行坑

`docs/demo.html` 是给预览面板看的单文件版，第一版直接把 1080p 原片 base64 内联，结果：

- 文件 1.67MB，其中**一整行 1.66MB** 的 base64；
- 预览面板渲染不动（表现为"文件损坏"/白屏），但文件本身是完好的
  （base64 解出来 1247254 字节，与 `media/boot.mp4` 逐字节一致）。

现在的做法：

1. 预览版单独转码 `media/boot-preview.mp4`（960×540 / CRF27 / 无音轨 ≈ 160KB），
   安装用的仍是原片 1080p；
2. base64 拆成 76 字符一行放进 `<script type="text/plain" id="vidb64">`，
   运行时去空白 → `atob` → `Uint8Array` → `Blob` → `URL.createObjectURL`，
   于是 `<video src>` 拿到的是 `blob:` URL，文件里再没有超长行（最长 143 字符）；
3. 加了"▶ 点击播放"兜底：面板里万一自动播放被拦，会给出按钮而不是黑屏。

顺带一个坑：那段"base64 → Blob"的 `<script>` 必须排在 `<script id="vidb64">`
**之后**，否则 `getElementById` 拿到 null，`src` 变成 `undefined`，
浏览器会去请求 `/undefined`（在 HTTP 日志里能直接看到这条 404）。


## 8. 莱茵开屏舞台（默认）：为什么是"外挂脚本"

`splash.html` 有 226KB（CSS 95KB + 标记 + base64 壁纸），而 `renderer/index.html`
的字节数被 asar 头部锁死在 27841，腾完注释和缩进也只有约 9.2KB 余量。三条路里只有一条通：

| 方案 | 结论 |
| --- | --- |
| 内联进 index.html | ✗ 塞不下（226KB vs 9.2KB） |
| iframe 装整个页面 | ✗ 主窗口 CSP 的 `frame-src` 没有 `local-file:` |
| **`<script src="local-file:///…">` 外挂** | ✓ `script-src` 明确带 `local-file:` |

于是拆成两半：

```
renderer/index.html（27841 字节，锁死）
└── <script>  ← 2.6KB 接管逻辑（src/stage-splash.js）
      │  1. 铺一层 #edece8 底板盖住骨架屏（= 载荷的 --rl-bg，接缝看不见）
      │  2. 注入 <script src="local-file:///…/wb-rhine-splash.js">
      │  3. 接管 __removeSkeleton，按"载荷消失 + 应用就绪"放行
      └─────────────────────────────────────────────┐
resources/wb-rhine-splash.js（134KB，原样不动）      │
└── 载荷自己注入 <style id="rhine-splash-css">、建 #rhine-splash、播 4.5s、自行 root.remove()
```

### 载荷的生命周期（实测，用来定放行条件）

```
0.00s  #rhine-splash 挂上，class = rl-root is-playing
0.40s  量一遍帧间隔，p95 > 34ms → 加 is-lite（只砍装饰层，主构图不变）
4.20s  class += is-leaving（main 淡出 / 门缝开 / 门扇分）
4.80s  载荷调用 root.remove()  ←── 我们就是盯这个当"播完"信号
```

关键发现：载荷的 `appReady()` 会等 **`#root` 有子元素**（WorkBuddy 的 React 根）
才退场，最长等 `maxWait = 8000ms`。也就是说它**自带与冷启动对齐的能力**，
我们的 `ready` 判定只是第二道保险。

### 我们只用 Esc，不接管点击

载荷自己带"点击任意处跳过"（`skippable: true`）。两套都拦会互相打架（我们一拦就把
`#rhine-splash` 删了，载荷的退场动画再也播不到）。所以：

- 点击 → 交给载荷
- Esc → 我们 `wipe()`（连它的 `<style>` 一起删）+ 撤底板 + 应用就绪就放行

### 兜底链

```
脚本 onerror（CSP / 协议 / 文件缺失）→ 立刻撤底板，绝不黑屏
2.5s 还没见到 #rhine-splash        → 认定没起来，撤底板
12s 硬上限                          → 强制 wipe + 撤底板
```

### 一个真实踩坑：`?hold=1` 撞上了载荷的 `__WB_SPLASH_HOLD__`

调试时我用 `?hold=1` 表示"应用别就绪"，结果载荷那边也有 `HOLD` 概念
（`globalThis.__WB_SPLASH_HOLD__`，CDP 注入器用来当网络闸门）。两者无关，
但读数会让人误判 —— 现在测试用的 `hold` 只在桩里生效，载荷侧没设这个全局变量。

## 9. 验证手段（无 GUI）
```powershell
# 构建 + 三重校验 + 语法检查，不碰安装目录
install.ps1 -AppPath "D:\wb\WorkBuddy" -DryRun -Force

# 直接验装好的 index.html：闸门 / 起播 / 播完 / 放行 / 有无报错
node tools\verify_installed.mjs

# 按页面时钟截关键帧（真实渲染进程；--virtual-time-budget 不推进 CSS 动画，别用）
node tools\shot_video.mjs

# 校验两个单文件演示页
node tools\check_demo.mjs
```

要点：截图必须用 `page.evaluate(ms => new Promise(...))` 对齐**页面自己的时钟**，
否则截图耗时会把 700ms 的帧拍成 900ms 的帧，时序判断全错。

实测输出（装好后的真实文件）：

```
(no query)                 stage=true      ← 主窗口，播
?windowAppId=settings      stage=false     ← 设置窗口，不播
?windowAppId=global-search stage=false
?windowAppId=office        stage=false

t=1s   stage=on  t=1.02 / dur=6
t=3s   stage=on  t=3.03
t=6.2s stage=on  t=6.00 ended=true        ← 停在末帧
ready 之后 900ms → stage=GONE             ← 淡出完成、骨架屏已拆
```
