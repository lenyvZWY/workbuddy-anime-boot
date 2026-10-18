/* ==========================================================================
 * WorkBuddy Boot —— ② 视频舞台逻辑（默认舞台，注入到 </body> 之前）
 * --------------------------------------------------------------------------
 * 注入时安装器会把 __BOOT_MP4__ 替换成本机实际路径，例如
 *   __BOOT_MP4__ -> D:/wb/WorkBuddy/resources/wb-boot.mp4
 *
 * 与上游 workbuddy-anime-boot 的 boot.js 相比，改的是"路径"不是"画面"：
 *   ① 挂载点：skeleton-root 内部 → body
 *      上游没有淡出。我们要 0.56s 淡出，挂在骨架屏里会随骨架屏一起被删，
 *      淡出直接变成闪断 —— 实测复现过（150ms 后 opacity 读 0）。
 *   ② 播完后：循环重播 → 停在末帧
 *      素材末帧是品牌定格（光环 + WorkBuddy 字标），应用没就绪就一直停在
 *      这一帧上，比从头再播一遍像"正在启动"得多。
 *   ③ 跳过：直接拆骨架屏 → 只撤黑幕
 *      应用没就绪时提前拆骨架屏 = 一屏空白。跳过只淡出，骨架屏留给应用自己拆。
 *   ④ 放行条件：视频播完 → 视频播完 && 应用就绪
 *   ⑤ 次级窗口（设置/会话/全局搜索…）共用同一个 index.html，按 windowAppId 排除
 *
 * 安全边界：整体 try/catch；源失败降级；错误遮罩出现立刻交界面；45s 兜底。
 * ========================================================================== */
(function () {
  try {
    /* 视频路径（安装器替换占位符） */
    var SRC = '__BOOT_MP4__';

    /* 只处理主窗口：骨架屏必须同时有侧栏与内容区 */
    var root = document.getElementById('skeleton-root');
    if (!root || !root.querySelector('.sk-sidebar') || !root.querySelector('.sk-content') || window.__wbboot) return;
    window.__wbboot = 1;

    /* 设置 / 会话 / 合并详情 / 开发者资料 / 全局搜索 / 图片查看 / office 是次级窗口 */
    var kind = '';
    try {
      var sp = new URLSearchParams(location.search);
      kind = sp.get('windowAppId') || sp.get('windowKind') || '';
    } catch (e) {}
    if ('|settings|conversation|im-merge-detail|developer-profile|global-search|image-viewer|office|'.indexOf('|' + kind + '|') > -1) return;

    var FADE = 560;      /* 与 CSS transition 对齐 */
    var MIN = 1500;      /* 至少亮 1.5s，别让慢机器"闪一下" */
    var CAP = 45000;     /* 应用一直不就绪时的兜底 */

    var t0 = Date.now();
    var orig = window.__removeSkeleton;
    var argv = null;     /* 原函数的参数（{animate:true} 之类）要原样转发 */
    var ready = false, passed = false, out = false, bail = false;
    var started = false, ended = false;

    /* ---------- 舞台 ---------- */
    var st = document.createElement('div');
    st.id = 'wbboot-stage';
    st.innerHTML =
      '<video id="wbboot-video" muted playsinline preload="auto"></video>' +
      '<div class="wbboot-bar"><i id="wbboot-progress"></i></div>' +
      '<div id="wbboot-skip">点击 / Esc 跳过</div>';
    /* 挂 body：骨架屏被拆时启动层要能继续存在并淡出 */
    (document.body || document.documentElement).appendChild(st);

    var v = st.querySelector('#wbboot-video');
    var bar = st.querySelector('#wbboot-progress');

    /* 两个候选源：优先自定义协议（CSP 的 media-src 允许），失败回退 file:// */
    var srcs = ['local-file:///' + SRC, 'file:///' + SRC];
    var si = 0;

    function play() {
      try { var p = v.play(); if (p && p.catch) p.catch(function () {}); } catch (e) {}
    }

    function next() {
      if (si >= srcs.length) { bail = true; fade(); return; }
      v.src = srcs[si++];
      try { v.load(); } catch (e) {}
      play();
    }

    /* ---------- 三个动作：放行 / 淡出 / 跳过 ---------- */
    function pass() {
      if (passed) return;
      passed = true;
      try { if (typeof orig === 'function') orig.apply(null, argv || []); else root.remove(); }
      catch (e) { try { root.remove(); } catch (e2) {} }
    }

    function fade() {
      if (out) return;
      out = true;
      st.classList.add('wbboot-out');
      document.removeEventListener('mousedown', skip, true);
      window.removeEventListener('keydown', onKey, true);
      setTimeout(function () { try { st.remove(); } catch (e) {} }, FADE + 80);
    }

    function skip() {
      if (out) return;
      bail = true;
      fade();                 /* 先撤黑幕，露出骨架屏 */
      if (ready) pass();      /* 应用已就绪就别让它继续等 */
    }

    function onKey(e) { if (e.key === 'Escape' || e.keyCode === 27) skip(); }
    document.addEventListener('mousedown', skip, true);
    window.addEventListener('keydown', onKey, true);

    /* ---------- 视频事件 ---------- */
    v.addEventListener('playing', function () {
      if (started) return;
      started = true;
      t0 = Date.now();        /* 计时零点对齐到真正出画的时刻 */
    });

    v.addEventListener('timeupdate', function () {
      if (v.duration && isFinite(v.duration)) {
        bar.style.transform = 'scaleX(' + Math.min(1, v.currentTime / v.duration) + ')';
      }
    });

    v.addEventListener('ended', function () {
      ended = true;
      bar.style.transform = 'scaleX(1)';
      /* 不循环：停在末帧（品牌定格）等应用就绪 */
    });

    v.addEventListener('error', function () {
      if (started) { bail = true; fade(); }   /* 播到一半坏了 → 直接交界面 */
      else next();                            /* 还没起来 → 换下一个源 */
    });

    next();

    /* ---------- 接管拆骨架屏：只记录，不真正拆 ---------- */
    window.__removeSkeleton = function () {
      argv = arguments;
      ready = true;
      if (bail) pass();
    };

    /* ---------- 主循环（120ms）：视频播完 && 应用就绪 才放行 ---------- */
    var tm = setInterval(function () {
      /* 启动出错、错误遮罩弹出 → 立刻把界面交给用户 */
      var ov = document.getElementById('sk-overlay');
      if (ov && ov.style.display && ov.style.display !== 'none') {
        clearInterval(tm); pass(); fade(); return;
      }

      if (bail) { clearInterval(tm); if (ready) pass(); return; }

      var el = Date.now() - t0;
      if (el > CAP) {           /* 兜底：实在等不到就先把黑幕撤掉 */
        clearInterval(tm); fade(); return;
      }
      if (!ready) return;       /* 应用还没好，继续守在末帧上 */
      if (!ended) return;       /* 视频还没播完，让它播完 */
      if (el < MIN) return;     /* 太短会像闪一下 */
      clearInterval(tm);
      pass();                   /* 先拆骨架屏（真实界面在下面渲染） */
      fade();                   /* 再淡出黑幕 → 无缝进入 */
    }, 120);
  } catch (e) {}
})();
