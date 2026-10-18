# rhine-boot · WorkBuddy 莱茵开屏

> 给 WorkBuddy 桌面端换启动画面：**不重打包 asar、不改主程序**，
> 只往 unpacked 的 `renderer/index.html` 注入 ~2.8KB 接管逻辑，
> 把 134KB 的「莱茵生命开屏」载荷当**外挂脚本**加载，播完再放行 React。
>
> 已在本机 WorkBuddy **5.8.3（Electron 37 / Chrome 138）** 真机跑通。

![效果](docs/splash-boot.mp4)

---

## 一、实现路径（先看这个）

### 1. 为什么必须"外挂"，不能内联

三个硬约束把路堵到只剩一条：

| 约束 | 实测值 | 后果 |
| --- | --- | --- |
| `renderer/index.html` 字节数被 `app.asar` 头部锁死 | **27841**（多一个字节就静默截断 → 白屏） | 腾完注释/缩进只剩 ≈9.2KB 余量，塞不进 226KB 的开屏 |
| 主窗口 CSP 的 `frame-src` | `'self' blob: wb-extension: https://*.qq.com …`，**没有 `local-file:`** | iframe 装整个页面会被拦 |
| 主窗口 CSP 的 `script-src` | `'self' 'unsafe-inline' 'unsafe-eval' blob: local-file: …` | **`local-file:` 在**，可以外挂脚本 |

于是拆成两半：

```
<安装目录>\resources\
├── app.asar.unpacked\renderer\index.html   27841 字节（锁死）
│   └── <script>  ← 2.8KB 接管逻辑（src/stage-splash.js）
│         ├─ ① 铺 #edece8 底板盖住骨架屏（= 载荷的 --rl-bg，接缝看不见）
│         ├─ ② 三级回退加载载荷
│         └─ ③ 接管 window.__removeSkeleton，按"载荷消失 + 应用就绪"放行
└── wb-rhine-splash.js                      133,990 字节（开屏载荷，原样不动）
```

### 2. 三级回退加载（这是本方案能稳的关键）

同一个文件三种取法，谁先成功用谁，全失败就撤底板（**绝不黑屏**）：

```js
var cands = [
  '../../wb-rhine-splash.js',        // ① 相对 index.html → 同源 'self'，不依赖协议白名单
  'local-file:///' + PATH,           // ② 主窗口 CSP 的 script-src 明确带 local-file:
  'file:///' + PATH                  // ③ 兜底，页面本身是 file:// 时 'self' 命中
];
```

为什么不是只写 `local-file:`：`protocol.registerSchemesAsPrivileged` 给的是
`{standard:true, secure:true, supportFetchAPI:true, stream:true}`，`.js/.mjs` 的 MIME 是
`text/javascript` —— 理论上没问题，但**路径解析**（`local-file:///D:/…` 的 host 为空、
`toFileUrl` 会再拼成 `file:///…`）在行为上依赖实现细节。三条一起试，成本是几百字节，
收益是不用赌。

### 3. 时序与放行条件

载荷自己的时间轴（4.5s）：

```
0.00s  #rhine-splash 挂上，class = rl-root is-playing
0.25s  Act A  权限核验 · PERMISSION AUTHORIZED
1.60s  Act B  欢迎锁屏 / 徽记 / 模块瓦片 / 探针显微图
3.70s  Act C/D 会话列、终端行、装载条 100%
4.20s  is-leaving：main 淡出 → 门缝开 → 门扇分开（iris）
4.80s  载荷自行 root.remove()
```

我们的放行规则只有一条：**盯 `#rhine-splash` 消失**（不是猜时长）+ 应用就绪：

```js
if (seen && !el) {                 // 载荷自己 remove 了 = 播完
  if (ready) { pass(); fade(); }   // 应用也好了 → 拆骨架屏 + 撤底板
  else fade();                     // 应用还在起 → 撤底板，把骨架屏交还它
}
```

**关键发现**：载荷的 `appReady()` 会等 `#root` 有子元素（WorkBuddy 的 React 根）才退场，
最长等 `maxWait = 8000ms`。所以它**自带与冷启动对齐的能力**，慢机也不会"闪一下就没"。

### 4. 三个容易踩的细节

**① 底板必须在 body 上，不能塞进骨架屏**

```
淡出中 → 应用调用 __removeSkeleton() → #skeleton-root 整个 remove()
       → 挂在里面的启动层一起消失 → 淡出变成瞬间闪断（实测 opacity 立刻读到 0）
```

**② 只接管 Esc，不接管点击**

载荷自己带"点击任意处跳过"（`skippable: true`）。两套都拦会互相打架
（我们一拦就把 `#rhine-splash` 删了，载荷的退场动画再也播不到）。

**③ 次级窗口要排除**

设置 / 会话 / 合并详情 / 开发者资料 / 全局搜索 / 图片查看 / office 这些窗口
加载的是**同一个** `index.html`，不设闸的话点一下"设置"就会闪一整段开屏：

```js
if ('|settings|conversation|im-merge-detail|developer-profile|global-search|image-viewer|office|'
      .indexOf('|' + kind + '|') > -1) return;   // kind = windowAppId || windowKind
```

### 5. 字节预算（27841 的账）

| 步骤 | 字节 |
| --- | --- |
| 原文件 | 27841 |
| 去掉 HTML 注释 | −2186 |
| 压缩第一个 `<style>` 的缩进/注释 | −7016 |
| **可用余量** | **≈ 9200** |
| 注入 CSS（底板） | −203 |
| 注入 JS（接管） | −3061 |
| 剩余（补空格） | ≈ 5.9KB |

写入前五道校验：字节数相等 → `TrimEnd().EndsWith('</html>')` → 含 `skeleton-root` →
含舞台标记 → `node --check`。任一不过就不写盘。

---

## 二、⚠️ 已知问题：冷启动卡顿（未彻底解决）

**现象**：冷启动那 4.5 秒里，机械硬盘 / 低核机器上 Act B（1.6–3.7s）会有轻微掉帧，
鼠标拖窗口偶有顿感；强机上基本无感。

**根因**：开屏动画和 React 首帧在**同一个渲染进程、同一条主线程**上抢时间。
这不是脚本写得糙，是注入式开屏的固有代价 —— 除非把动画搬到主进程的独立窗口
（那要改 asar，本方案不做）。

**载荷自带的缓解**：它在 400ms 时量一遍帧间隔，p95 > 34ms 就加 `is-lite`
（只砍最费绘制的装饰层：点阵场位移/蒙版、大字水印描边、扫描线），
主构图（徽记 / 标题板 / 阶段条 / 方块）一个不少。

**你可以再压一档**（在 `media/wb-rhine-splash.js` 挂载前注入配置）：

```js
globalThis.__RHINE_SPLASH__ = {
  duration: 3000,        // 4.5s → 3s，卡顿窗口同比缩短
  exit: 'doors',         // 退场更短的开门，而不是 iris
  reducedMotion: true    // 直接走 reduced 路径（无长动画，只剩一两帧）
};
```

**实测建议**：如果只在意外观不在意时长，`duration: 3200` + 默认 `iris` 是手感最好的组合。

---

## 三、参考来源与作者

- **开屏视觉与 4.5s 时间轴**：`dsh-rhine-splash` —— **DeepSeek Harness（dsh）插件生态**里的开源插件，
  MIT © 2026 **ArtemisFowl**。本项目使用的载荷（`media/wb-rhine-splash.js`）由其构建产物派生，
  视觉、文案、动效时间轴均归原作者。
- **接管思路 / asar 字节数陷阱 / 三重校验**：本仓库 v1.0.0（`lenyvZWY/workbuddy-anime-boot`）自己的实践。
- **备选 550C 舞台**：`yannicksong0106/dsh-550c-boot`（MIT，同样来自 DeepSeek Harness 生态），
  字形原作者 `Voidpocket/html_550c`。

> 与 WorkBuddy 官方无关；素材仅限个人本地美化，请勿二次分发影视 / 游戏相关 IP。

---

## 四、安装

```powershell
# 双击（自动定位安装目录），默认莱茵开屏
install.cmd

# 指定目录 / 只看构建不动安装目录 / 换舞台
install.cmd -AppPath "D:\wb\WorkBuddy"
install.cmd -DryRun                          # 只构建到 build\index.html
install.cmd -Stage video -Force              # 星云视频
install.cmd -Stage 550c  -Force              # 550C 量子计算机
```

安装器会：定位目录 → 读 asar 头部拿"本版本要求的字节数" → 实时构建 → 五道校验 →
备份原文件 → 写入 → 部署素材 → 清理其它舞台的素材。

| 写入位置 | 内容 |
| --- | --- |
| `resources\app.asar.unpacked\renderer\index.html` | 注入底板样式 + 接管脚本（字节数与 asar 头部严格相等） |
| `resources\wb-rhine-splash.js` | 开屏载荷（换舞台时换成 `wb-boot.mp4` / `wb-550c-logo.svg`） |

备份：`%USERPROFILE%\.workbuddy-boot\backup\index.html.orig`
**只写文件、不建目录** —— 安装目录里多出的文件夹会挡住 WorkBuddy 官方更新。

## 五、卸载

```powershell
uninstall.cmd
```

还原 `index.html`（并校验字节数）+ 删除素材文件。

## 六、目录

```
install.ps1 / install.cmd        安装器（-Stage splash|video|550c，-DryRun，-Force）
uninstall.ps1 / uninstall.cmd    卸载器
src/stage-splash.css|.js         莱茵舞台（默认）：底板 + 三级回退加载 + 接管
src/stage-video.css|.js          星云视频舞台
src/stage-550c.css|.js           550C 舞台（自播放 SVG）
media/wb-rhine-splash.js         开屏载荷（134KB，自包含）
media/boot.mp4                   星云视频（1080p/6s）
media/wb-550c-logo.svg           550C logo（自带时间轴）
docs/HOW-IT-WORKS.md             全部原理、CSP 原文、踩坑记录
docs/splash-boot.mp4             真机开屏录屏（用真实构建产物 + 真实载荷）
tools/make_harness.py            用构建产物造可本地打开的测试页
tools/test_splash.mjs            端到端测试（正常 / 慢启动 / Esc）
tools/record_boot.mjs            CDP 录制开屏全过程
tools/build_svg.py               从上游 550C 源码抽 logo 并注入时间轴
tools/build_demo.py              生成两个单文件演示页
```

## License

MIT。开屏载荷的著作权归 `dsh-rhine-splash` 作者（ArtemisFowl）；550C 素材归其原作者。
