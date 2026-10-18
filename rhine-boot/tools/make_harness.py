# -*- coding: utf-8 -*-
"""用真实构建产物造一个可本地打开的测试页：
   build/index.html（真骨架屏 + 真注入）→ 把 local-file:// 素材地址换成相对路径，
   再补一个 __removeSkeleton 桩（真机里由 skeleton-bootstrap.js 提供）。
"""
import io, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
s = io.open(os.path.join(ROOT, 'build', 'index.html'), encoding='utf-8').read()

import re as _re
s = _re.sub(r"var cands = \[[^\]]*\];",
            "var cands = ['../media/wb-rhine-splash.js'];", s, count=1)

stub = ("""<script>
  window.__removeSkeleton = function () {
    var r = document.getElementById('skeleton-root');
    if (r) r.remove();
    document.body.insertAdjacentHTML('afterbegin',
      '<div id="app" style="position:fixed;inset:0;display:flex;align-items:center;' +
      'justify-content:center;background:#fff;font:15px system-ui;color:#444">WorkBuddy 主界面（桩）</div>');
  };
  /* 模拟 React 挂载：往 #root 里塞内容 + 调 __removeSkeleton
     （载荷的 appReady() 就是看 #root.childElementCount > 0） */
  if (!location.search.includes('hold')) setTimeout(function () {
    var root = document.getElementById('root');
    if (root) root.innerHTML =
      '<div id="app-real" style="position:fixed;inset:0;z-index:9;background:#fff;display:flex;' +
      'align-items:center;justify-content:center;font:16px/1.6 system-ui;color:#333">' +
      '<div style="text-align:center"><b style="font-size:20px">WorkBuddy 主界面</b>' +
      '<div style="color:#999;margin-top:6px;font-size:13px">开屏退场后由这里接管（桩）</div></div></div>';
    window.__removeSkeleton();
  }, 1200);
</script>
""")
i = s.lower().find('<body')
j = s.find('>', i) + 1
s = s[:j] + stub + s[j:]

out = os.path.join(ROOT, 'preview', 'built-splash.html')
io.open(out, 'w', encoding='utf-8', newline='\n').write(s)
print('OK', out, len(s.encode()), 'bytes')
print('asset ref ok:', '../media/wb-rhine-splash.js' in s)
