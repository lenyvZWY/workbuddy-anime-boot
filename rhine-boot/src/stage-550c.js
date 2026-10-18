/* ==========================================================================
 * WorkBuddy 550C Boot —— ③ 启动层逻辑（注入到 </body> 之前）
 * --------------------------------------------------------------------------
 * 注入时安装器会把 __LOGO_SVG__ 替换成本机实际路径，例如
 *   __LOGO_SVG__ -> D:/wb/WorkBuddy/resources/wb-550c-logo.svg
 *
 * 与「视频版」的区别（这是本次改造的核心）：
 *   视频版：靠 video.ended 判断播完 —— 时长由视频决定，等 React 就绪后
 *           「播完即放行」，因此启动块慢的时候动画会一直循环重播。
 *   550C 版：动画时间轴写在 SVG 里（固定 2450ms 走完 6 个字形），
 *           脚本只负责三件事 ——
 *             ① 接管 window.__removeSkeleton（只记录，不拆）
 *             ② 等「动画播完 && React 就绪」两个条件同时满足
 *             ③ 淡出启动层的同时调用原函数拆骨架屏 → 真实界面从黑场里浮出
 *           应用慢的时候，启动画面就停在"glow 呼吸 + 光标闪烁"状态，
 *           正好是 550C 终端该有的样子，不需要循环重播。
 *
 * 安全边界（与视频版一致）：
 *   · 只在主窗口生效（骨架屏必须同时有 .sk-sidebar / .sk-content）；
 *   · 整体 try/catch，异常只会导致"没有动画"，不会影响启动；
 *   · 启动失败遮罩 #sk-overlay 一旦出现 → 立刻交出界面；
 *   · 图片加载失败 → 退化成纯文字启动屏（1.3s）；再失败 → 直接放行。
 * ========================================================================== */
(function () {
  try {
    /* 动画素材路径（安装器替换占位符） */
    var SRC = '__LOGO_SVG__';

    /* 只处理主窗口：骨架屏必须包含侧栏与内容区 */
    var root = document.getElementById('skeleton-root');
    if (!root || !root.querySelector('.sk-sidebar') || !root.querySelector('.sk-content') || window.__wbboot) return;
    window.__wbboot = 1;

    /* 设置 / 会话 / 合并详情 / 开发者资料 / 全局搜索 / 图片查看 / office 等次级窗口
       加载的是同一个 index.html，只是换了骨架屏变体 —— 它们不该播开机动画 */
    var kind = '';
    try {
      var sp = new URLSearchParams(location.search);
      kind = sp.get('windowAppId') || sp.get('windowKind') || '';
    } catch (e) {}
    if ('|settings|conversation|im-merge-detail|developer-profile|global-search|image-viewer|office|'.indexOf('|' + kind + '|') > -1) return;

    /* 时间轴：250 + 6*300 + 400 = 2450ms 字形擦完，2.4s 起打字机 .52s 到 2.92s，
       再留 30ms 余量 → 2950ms 之后才允许淡出（与 SVG / CSS 里的时间严格对齐） */
    var HOLD = 2950;
    var FADE = 560;    /* 与 CSS transition 对齐 */
    var CAP = 45000;   /* 应用一直不就绪时的兜底 */

    var t0 = Date.now();
    var orig = window.__removeSkeleton;
    var argv = null;   /* 应用调用 __removeSkeleton 时带的参数（{animate:true} 之类），要原样转发 */
    var ready = false, passed = false, out = false, skipped = false;

    /* ---------- 舞台 ---------- */
    var st = document.createElement('div');
    st.id = 'wbboot-stage';
    st.innerHTML =
      '<div class="wb550c-scan"></div>' +
      '<div class="wb550c-sweep"></div>' +
      '<div class="wb550c-core">' +
        '<img id="wb550c-logo" src="' + SRC + '" alt="">' +
        '<div id="wb550c-txt"><span class="wb550c-line">550C SYSTEM BOOT</span><i class="wb550c-cur"></i></div>' +
      '</div>' +
      '<div class="wb550c-hud wb550c-tl">UEG &#47;&#47; 550C</div>' +
      '<div class="wb550c-hud wb550c-bl">QUANTUM COMPUTER &middot; BOOT SEQUENCE</div>' +
      '<div id="wbboot-skip">点击 / Esc 跳过</div>';
    /* 挂到 body 而不是骨架屏里 —— 骨架屏一被拆除，挂在它里面的节点会一起消失，
       那样"淡出"就变成了瞬间消失。挂在 body 上才能让真实界面从黑场下面浮出来。 */
    (document.body || document.documentElement).appendChild(st);

    /* ---------- logo 加载：成功后把计时零点对齐到真正解码完的时刻 ---------- */
    var img = st.querySelector('#wb550c-logo');
    var alt = SRC.indexOf('local-file') === 0 ? 'file:///' + SRC.slice(13) : '';

    img.addEventListener('load', function () { t0 = Date.now(); });

    img.addEventListener('error', function () {
      if (alt) { img.src = alt; alt = ''; return; }   /* 换协议再试一次 */
      HOLD = 1300;                                    /* 退化成纯文字启动屏 */
      st.classList.add('wb550c-noimg');
    });

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
      skipped = true;
      fade();                 /* 先让黑场淡掉，露出骨架屏 */
      if (ready) pass();      /* 应用已就绪就别让它继续等 */
    }

    function onKey(e) { if (e.key === 'Escape' || e.keyCode === 27) skip(); }
    document.addEventListener('mousedown', skip, true);
    window.addEventListener('keydown', onKey, true);

    /* ---------- 接管拆骨架屏：只记录，不真正拆 ---------- */
    window.__removeSkeleton = function () {
      argv = arguments;
      ready = true;
      if (skipped) pass();
    };

    /* ---------- 主循环（120ms）：两个条件都满足才放行 ---------- */
    var tm = setInterval(function () {
      /* 启动出错、错误遮罩弹出 → 立刻把界面交给用户 */
      var ov = document.getElementById('sk-overlay');
      if (ov && ov.style.display && ov.style.display !== 'none') {
        clearInterval(tm); pass(); fade(); return;
      }

      if (!out && Date.now() - t0 > CAP) { clearInterval(tm); fade(); return; }

      if (!ready) return;                      /* 应用还没好，继续守在启动画面 */
      if (Date.now() - t0 < HOLD) return;      /* 字形还没擦完，让它播完 */
      clearInterval(tm);
      pass();                                  /* 先拆骨架屏（真实界面在下面渲染） */
      fade();                                  /* 再淡出黑场 → 无缝进入 */
    }, 120);
  } catch (e) {}
})();
