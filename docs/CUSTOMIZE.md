# 进阶自定义

改完 `src/` 里的文件后，重新运行安装器生效：先 `uninstall.cmd` 还原，再 `install.cmd`。

---

## 1. 调面板深浅（最重要）

打开 `src/skin-dark.css`，"深色玻璃变量"一节里每个变量的值是 8 位十六进制：

```css
--cb-bg-primary: #090b1173 !important;
                        ↑↑
                        最后两位是透明度：00（全透）~ ff（全不透）
```

常用档位参考：

| 值 | 效果 |
| --- | --- |
| `#090b1133` | 20%，非常透（壁纸清晰可见） |
| `#090b1147` | 28%，微透 |
| `#090b1166` | 40%，标准玻璃感 |
| `#090b1180` | 50%，偏实（壁纸隐约可见） |
| `#0b0d14f2` | 95%，几乎不透明（下拉菜单用这个，保证文字可读） |

> 口诀：**数字越大越黑**。想整体更透 → 所有值末尾两位调小；想更实 → 调大。

---

## 2. 调壁纸暗度

`src/skin-wallpaper.css` 里的深色膜：

```css
background-image:
    linear-gradient(rgba(6, 8, 14, .42), rgba(6, 8, 14, .52)),
    url("local-file:///__APP_DIR__/resources/wb-wallpaper.jpg");
                        ↑ .42 / .52 就是暗度（0~1）
```

- 壁纸太亮看不清字 → 调大（如 `.55` / `.62`）
- 想看得更清楚壁纸细节 → 调小（如 `.30` / `.40`）

---

## 3. 调动态保险的力度

`src/pass.js` 顶部：

```javascript
var TARGET = 'rgba(9,11,17,0.18)';   /* 把大面板刷成的颜色（18% 黑） */
```

- 和 `skin-dark.css` 的风格保持一致即可；想让动态保险跟手一点就改这里。
- 阈值在 `fx()` 里：`var min = innerWidth * innerHeight * 0.07;` —— 视口面积的 7%。
  调小（如 `0.04`）会处理更多中等面板；调大会更保守。**不建议小于 0.05**，否则可能误伤代码块、输入框。

---

## 4. 调启动动画行为

`src/boot.js` 顶部：

```javascript
var G  = 3000;    /* 等视频起播的上限：3 秒（超时直接进界面） */
var M  = 24000;   /* 总兜底：24 秒（读到视频真实时长后自动调整为 时长+4s，上限 3 分钟） */
var ST = 2500;    /* 播放卡死判定：2.5 秒无进度就放行 */
```

- 想让动画必须播完、不许兜底跳过 → 把 `M` 改大（如 `600000`）
- 想更激进地进界面 → 把 `G` / `ST` 改小

底部"正在进入"胶囊的文字（`src/boot.js`）：

```javascript
bd.innerHTML = '<span class="wb-dot"></span><span>WorkBuddy \u00b7 正在进入</span>';
```

跳过按钮的文字：

```javascript
sk.textContent = '点击 / Esc 跳过';
```

> 注意：**`src/boot.js` 里只能写"块注释"（`/* */`），不能写"行注释"（`//`）**。
> 因为安装器压缩时会把行注释和下一行粘在一起，导致语法错误。

---

## 5. 调颜色主题

想把蓝紫色换成别的色系？改两处：

**启动动画的颜色**（在 `extra/gen_media.py` 里，重新生成视频）：

```python
# 旋转光带 1（紫粉色 → 换成你喜欢的 RGB）
img += (band * 0.80 * a1)[..., None] * np.array([148, 106, 248], np.float32)
#                                       ↑ R   G   B
```

**界面玻璃的底色**（`src/skin-dark.css`）：

```css
--cb-bg-primary: #090b1173 !important;
                  ↑↑↑↑↑↑ 前六位是 RGB（09/0b/11 = 近黑的深蓝）
```

例如想换成"暖棕玻璃"：`#14100b73`。

---

## 6. 增加自定义 CSS

`src/` 里新建一个 `.css` 文件（比如 `my-tweak.css`），然后在 `install.ps1` 的"3.3 注入 CSS"一节照葫芦画瓢加一行：

```powershell
$cssParts += Compress-Css ([System.IO.File]::ReadAllText((Join-Path $root 'src\my-tweak.css'), [System.Text.Encoding]::UTF8))
```

或者更省事：直接把你想要的规则追加到 `src/skin-dark.css` 末尾。

---

## 7. 完全从头做一套素材

`extra/gen_media.py` 是默认素材的生成器，全参数化：

```python
W, H = 1920, 1080        # 分辨率
FPS = 30                 # 帧率
DUR = 6.0                # 时长（秒）
SEED = 20261016          # 随机种子（换一个数字 → 粒子分布不同）
```

颗粒度较高的调整点都带中文注释：光晕半径、旋转光带的瓣数 / 速度 / 颜色、粒子数量、文字内容与出现时机。

改完运行：

```bash
python extra/gen_media.py
```

两个素材会重新生成到 `media/`。

---

## 8. 常见"改了没生效"排查

| 症状 | 原因 |
| --- | --- |
| 改了 src 但界面没变 | 忘了重跑安装器（且要先 uninstall） |
| 重跑安装器报"已安装过" | 必须先运行 `uninstall.cmd` 还原 |
| 改了素材但视频还是老的 | 只替换了 `media/` 但没重跑安装器 |
| 安装器报"字节数超出" | 素材/样式太多；精简 CSS 或换更短的动画 |
| 安装器报"版本不兼容" | WorkBuddy 大版本更新了，需要为新版适配（提 Issue） |
