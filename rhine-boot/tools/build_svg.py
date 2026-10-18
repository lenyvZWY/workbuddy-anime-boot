# -*- coding: utf-8 -*-
"""
把 dsh-550c-boot 里的 550C 开机 logo（assets/550C-source.html 中的 <svg>）
转成一个「自播放」的独立 SVG 文件，供 WorkBuddy 启动层用 <img> 直接加载。

为什么不再用 <video>：
  550C 片头本质是 6 个字形（5/5/0/C）从左到右逐个 clip-path 擦除，
  矢量 + 400ms 级联延时。做成视频要 1080p 编码、体积大、缩放糊；
  做成「自带 CSS 时间轴的 SVG」则零 JS、任意分辨率清晰、<img> 即可播放。

时间轴完全对齐原版 playBoot()：
  第 i 个字形 delay = 250 + i*300 ms，擦除 600ms → 最后一个 1750+600 = 2350ms
  原版 playBoot 返回 250 + n*300 + 400 = 2450ms（n=6），之后加 glow 呼吸。

用法：python tools/build_svg.py
输入：<repo>/assets/550C-source.html（上游 550C 源码，需先 clone）
输出：media/wb-550c-logo.svg
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(os.path.dirname(ROOT), "boot-550c", "assets", "550C-source.html")
OUT = os.path.join(ROOT, "media", "wb-550c-logo.svg")

STEP = 300      # 每个字形间隔
BASE = 250      # 首个字形开始时间
WIPE = 600      # 单字形擦除时长
FINISH = 2450   # 全部擦完、开始 glow（= BASE + n*STEP + 400）


def main():
    if not os.path.exists(SRC):
        sys.exit("找不到 550C 源码：%s" % SRC)
    html = open(SRC, encoding="utf-8").read()
    m = re.search(r'<svg viewBox="0 0 800 230".*?</svg>', html, re.S)
    if not m:
        sys.exit("550C 源码里没有找到 logo <svg>")
    svg = m.group(0)

    # 1) 定位所有 path，按文档顺序（= 从左到右）编号
    paths = list(re.finditer(r'<path\b', svg))
    if not paths:
        sys.exit("logo <svg> 里没有 path")

    # 2) 给每个 path 补 animation-delay（第一段是擦除延迟，第二段是 glow 起始）
    out, last = [], 0
    for i, pm in enumerate(paths):
        d = (BASE + i * STEP) / 1000.0
        seg = svg[last:pm.start()]
        # 找到该 path 的结束尖括号，把 style 加在 <path .../> 里
        end = svg.index(">", pm.start())
        head = svg[pm.start():end]
        if head.endswith("/"):
            head = head[:-1].rstrip()
            self_close = True
        else:
            self_close = False
        if "style=" in head:
            head = re.sub(r'style="([^"]*)"', r'style="\1;animation-delay:%ss,%ss"' % (d, FINISH / 1000.0), head)
        else:
            head += ' style="animation-delay:%ss,%ss"' % (d, FINISH / 1000.0)
        if self_close:
            head += "/"
        out.append(seg)
        out.append(head)
        last = end
    out.append(svg[last:])
    svg = "".join(out)

    # 3) 注入动画样式（只动 CSS，不动 path 数据，确保字形 100% 还原上游）
    style = (
        "<style>"
        ".white{fill:#fff;stroke:none}"
        ".red{fill:#ff2d2d;stroke:none}"
        "path{opacity:.08;"
        "animation:wipe .6s cubic-bezier(.4,0,.2,1) both,"
        "glowW 2.6s ease-in-out @FIN@s infinite}"
        "path.red{animation-name:wipe,glowR}"
        "@keyframes wipe{"
        "from{opacity:.08;clip-path:inset(0 100% 0 0);-webkit-clip-path:inset(0 100% 0 0)}"
        "to{opacity:1;clip-path:inset(0 0 0 0);-webkit-clip-path:inset(0 0 0 0)}}"
        "@keyframes glowW{0%,100%{filter:drop-shadow(0 0 5px rgba(255,255,255,.35))}"
        "50%{filter:drop-shadow(0 0 13px rgba(255,255,255,.85))}}"
        "@keyframes glowR{0%,100%{filter:drop-shadow(0 0 6px rgba(255,45,45,.45))}"
        "50%{filter:drop-shadow(0 0 16px rgba(255,45,45,.95))}}"
        "</style>"
    ).replace("@FIN@", "%.2f" % (FINISH / 1000.0))

    svg = svg.replace(">", ">" + style, 1)          # 紧跟 <svg ...> 之后
    if not svg.lstrip().startswith("<?xml"):
        svg = '<?xml version="1.0" encoding="UTF-8"?>\n' + svg

    # 4) 轻度压缩：标签之间的空白压掉（path 数据一律不动）
    svg = re.sub(r">\s+<", "><", svg)
    svg = re.sub(r"\s{2,}", " ", svg)

    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(svg)
    print("OK  %s  (%d bytes, %d glyphs, total %dms)" % (OUT, len(svg.encode("utf-8")), len(paths), FINISH))


if __name__ == "__main__":
    main()
