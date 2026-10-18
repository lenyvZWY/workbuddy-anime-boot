# -*- coding: utf-8 -*-
"""生成单文件演示页（给预览面板用，必须小且稳）：

    docs/demo.html       —— 视频舞台，用 media/boot-preview.mp4（960x540/CRF27 ≈ 160KB）
    docs/demo-550c.html  —— 550C 舞台（logo 33KB）

第一版直接把 1080p 原片 base64 塞进 HTML，得到 1.67MB、单行 1.66MB 的文件 ——
预览面板渲染不动（看起来像"文件损坏"）。现在：
  ① 用 960x540 的轻量预览版，体积降到 ~1/10；
  ② base64 拆成 76 字符一行，放进 <script type="text/plain">，运行时拼回 Blob URL，
     彻底避免"单行超长"；
  ③ 加"点击播放"兜底：面板里如果自动播放被拦，会显示提示而不是黑屏。
"""
import base64
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

TPL = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<title>WorkBuddy Boot — __TITLE__</title>
<style>
  html,body{margin:0;height:100%;background:#fff;font:14px/1.6 system-ui,"Microsoft YaHei",sans-serif;overflow:hidden}
  #skeleton-root{position:fixed;inset:0;background:#f7f7f8}
  .sk-titlebar{height:48px;background:#e9e9ec}
  .sk-body{display:flex}
  .sk-sidebar{width:220px;height:calc(100vh - 72px);background:#eef0f4}
  .sk-content{flex:1;height:calc(100vh - 72px);background:#fff}
  .sk-statusbar{height:24px;background:#e9e9ec}
  .app{position:fixed;inset:0;display:none;flex-direction:column;align-items:center;justify-content:center;gap:14px;background:#fff;color:#333}
  .app b{font-size:16px;font-weight:600}
  .app span{color:#888;font-size:13px}
  .app button{margin-top:6px;padding:9px 22px;border-radius:999px;border:1px solid #ddd;background:#fafafa;cursor:pointer;font:13px system-ui}
  .app button:hover{border-color:#8ea2ff;color:#4a5cc4}
  __EXTRA_CSS__
</style>
<style>
__CSS__
</style>
</head>
<body>
<div id="skeleton-root">
  <div class="sk-titlebar"></div>
  <div class="sk-body"><div class="sk-sidebar"></div><div class="sk-content"></div></div>
  <div class="sk-statusbar"></div>
  <div id="sk-overlay" style="display:none"></div>
</div>

<div class="app" id="fake-app">
  <b>WorkBuddy 主界面</b>
  <span>演示占位 —— 真实环境里这里是应用本体，黑幕淡出后无缝出现</span>
  <button onclick="location.reload()">再看一次</button>
</div>

__PAYLOAD__

<script>
  window.__removeSkeleton = function () {
    document.getElementById('skeleton-root').style.display = 'none';
    document.getElementById('fake-app').style.display = 'flex';
  };
  if (!location.search.includes('hold')) {
    setTimeout(function () { window.__removeSkeleton(); }, 1200);
  }
</script>
<script>
__JS__
</script>
__TAIL__
</body>
</html>
"""

PLAY_FALLBACK = """
<script>
  /* 预览面板里如果自动播放被拦，给一个"点一下播放"的兜底，别让人对着黑屏 */
  (function () {
    var tries = 0;
    var t = setInterval(function () {
      var v = document.getElementById('wbboot-video');
      tries++;
      if (v && v.currentTime > 0.05) { clearInterval(t); return; }
      if (tries > 8 && v && v.paused) {
        clearInterval(t);
        var b = document.createElement('div');
        b.id = 'demo-play';
        b.textContent = '▶  点击播放';
        b.onclick = function () {
          b.remove();
          try { v.play(); } catch (e) {}
        };
        document.body.appendChild(b);
      }
    }, 250);
  })();
</script>
"""

EXTRA_CSS = """
#demo-play{position:fixed;left:50%;top:50%;transform:translate(-50%,-50%);z-index:2147483647;
  padding:14px 34px;border-radius:999px;cursor:pointer;
  background:rgba(255,255,255,.92);color:#2b2f3a;font:15px/1 system-ui;
  box-shadow:0 10px 30px rgba(0,0,0,.35);border:1px solid rgba(0,0,0,.06)}
#demo-play:hover{background:#fff;box-shadow:0 12px 36px rgba(0,0,0,.45)}
"""


def wrap76(b64):
    return "\n".join(b64[i:i + 76] for i in range(0, len(b64), 76))


def write(name, title, css, js, payload="", tail="", extra_css=""):
    html = (TPL.replace("__TITLE__", title)
               .replace("__CSS__", css)
               .replace("__JS__", js)
               .replace("__PAYLOAD__", payload)
               .replace("__TAIL__", tail)
               .replace("__EXTRA_CSS__", extra_css))
    path = os.path.join(ROOT, "docs", name)
    open(path, "w", encoding="utf-8", newline="\n").write(html)
    print("OK  %-22s %7.1f KB" % (name, len(html.encode()) / 1024))
    return path


def main():
    # ---------- 视频舞台 ----------
    css = open(os.path.join(ROOT, "src", "stage-video.css"), encoding="utf-8").read()
    js = open(os.path.join(ROOT, "src", "stage-video.js"), encoding="utf-8").read()
    prev = os.path.join(ROOT, "media", "boot-preview.mp4")
    mp4 = open(prev, "rb").read()

    payload = ('<script id="vidb64" type="text/plain">\n'
               + wrap76(base64.b64encode(mp4).decode("ascii"))
               + '\n</script>')

    # base64 -> Blob URL，再把舞台脚本的视频源换成它
    js = js.replace("'__BOOT_MP4__'", "'__BLOB__'")
    js = js.replace("var srcs = ['local-file:///' + SRC, 'file:///' + SRC];",
                    "var srcs = [window.__DEMO_SRC];")

    head = """
<script>
  (function () {
    var s = document.getElementById('vidb64').textContent.replace(/\\s+/g, '');
    var bin = atob(s), n = bin.length, u8 = new Uint8Array(n);
    for (var i = 0; i < n; i++) u8[i] = bin.charCodeAt(i);
    window.__DEMO_SRC = URL.createObjectURL(new Blob([u8], { type: 'video/mp4' }));
  })();
</script>
"""
    write("demo.html", "视频舞台（media/boot.mp4 预览版 960x540）", css, js,
          payload=payload + head, tail=PLAY_FALLBACK, extra_css=EXTRA_CSS)

    # ---------- 550C 舞台 ----------
    css = open(os.path.join(ROOT, "src", "stage-550c.css"), encoding="utf-8").read()
    js = open(os.path.join(ROOT, "src", "stage-550c.js"), encoding="utf-8").read()
    svg = open(os.path.join(ROOT, "media", "wb-550c-logo.svg"), "rb").read()
    uri = "data:image/svg+xml;base64," + base64.b64encode(svg).decode("ascii")
    js = js.replace("'__LOGO_SVG__'", "'" + uri + "'")
    write("demo-550c.html", "550C 舞台", css, js)


if __name__ == "__main__":
    main()
