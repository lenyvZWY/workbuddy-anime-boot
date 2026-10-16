/* ==========================================================================
 * WorkBuddy Anime Boot — ④ 启动动漫逻辑（media/boot.mp4 存在时注入）
 * --------------------------------------------------------------------------
 * 注入位置：</body> 之前。安装器会把 __BOOT_MP4__ 替换成本机实际路径，
 *          例如  __BOOT_MP4__  →  E:/easy/WorkBuddy/resources/wb-boot.mp4
 *
 * 核心原理 —— "接管骨架屏拆除时机"：
 *   ① WorkBuddy 启动时先显示骨架屏（#skeleton-root）。
 *      等 React 主界面挂载完成后，它会调用 window.__removeSkeleton() 拆除骨架屏。
 *   ② 我们在骨架屏上盖一层全屏视频，并把 window.__removeSkeleton
 *      偷换成"只记录、不拆除"的版本 —— 于是界面虽然已就绪，
 *      骨架屏 + 视频仍然留在屏幕上继续播动漫。
 *   ③ 满足任一条件才真正放行（调用原来的函数拆掉骨架屏）：
 *        · 视频播完 / 用户点击 / 按 Esc / 总时长兜底 / 视频加载失败 / 启动出错弹遮罩
 *
 * 兼容性：
 *   · 只在主窗口生效（必须能找到 .sk-sidebar 和 .sk-content），
 *     设置窗口等其它窗口不受影响；
 *   · 整体 try/catch 包裹，任何异常都被吞掉 —— 最坏情况只是没有动画，
 *     绝不影响 WorkBuddy 自身启动。
 * ========================================================================== */
(function () {
  try {
    /* 启动动画文件路径（安装器替换占位符） */
    var E = '__BOOT_MP4__';

    /* 只处理主窗口：骨架屏必须包含侧栏与内容区 */
    var r = document.getElementById('skeleton-root');
    if (!r || !r.querySelector('.sk-sidebar') || !r.querySelector('.sk-content') || window.__wbAnime) return;
    window.__wbAnime = 1;                       /* 防重复注入 */

    /* 视频源候选：优先自定义协议（workbuddy 的 CSP 允许），失败回退 file:// */
    var S = ['local-file:///' + E, 'file:///' + E];

    var G = 3000;      /* 等待首次播放的上限：3 秒 */
    var M = 24000;      /* 总兜底上限：24 秒（读到视频真实时长后自动调整） */
    var ST = 2500;      /* 播放中途卡死判定：2.5 秒无进度 */

    /* ---------- 创建覆盖元素 ---------- */
    var v = document.createElement('video');
    v.id = 'wb-anime-bg';
    v.autoplay = true; v.muted = true; v.defaultMuted = true; v.playsInline = true;
    v.preload = 'auto';
    v.setAttribute('muted', ''); v.setAttribute('playsinline', '');
    v.style.display = 'none';

    var vl = document.createElement('div'); vl.id = 'wb-anime-veil'; vl.style.display = 'none';

    var bd = document.createElement('div'); bd.id = 'wb-anime-badge'; bd.style.display = 'none';
    /* \u00b7 是间隔号"·"的 unicode 转义，保证任何文件编码下都不乱码 */
    bd.innerHTML = '<span class="wb-dot"></span><span>WorkBuddy \u00b7 正在进入</span>';

    var sk = document.createElement('div'); sk.id = 'wb-anime-skip'; sk.style.display = 'none';
    sk.textContent = '点击 / Esc 跳过';

    r.insertBefore(vl, r.firstChild);
    r.insertBefore(v, r.firstChild);
    r.appendChild(bd);
    r.appendChild(sk);

    /* ---------- 状态 ---------- */
    var o = window.__removeSkeleton;   /* 原始"拆骨架屏"函数，最后要调用它 */
    var pl = false;    /* playing：视频真正开始播放了 */
    var fl = false;    /* failed：所有视频源都失败了 */
    var i = 0;         /* 当前尝试到第几个源 */
    var dn = false;    /* done：已放行（幂等标记） */
    var rq = false;    /* requested：React 已请求拆除骨架屏 */
    var at = 0;        /* requestedAt：上面那个请求的时间戳 */
    var tm = null;     /* 主循环定时器 */
    var lt = 0;        /* lastTimeupdate：最近一次播放进度更新的时间 */

    /* 尝试播放（忽略 play() 的 Promise 报错，如自动播放限制） */
    function P() {
      try { var p = v.play(); if (p && p.catch) p.catch(function () {}); } catch (e) {}
    }

    /* 结束：清理动漫层并放行真实界面（幂等，重复调用安全） */
    function F() {
      if (dn) return;
      dn = true;
      if (tm) clearInterval(tm);
      window.removeEventListener('keydown', K, true);
      document.removeEventListener('mousedown', X, true);
      try { v.pause(); } catch (e) {}
      try { bd.remove(); sk.remove(); } catch (e) {}
      try {
        if (typeof o === 'function') o();   /* 调用原始函数 -> 骨架屏被拆除 */
        else r.remove();                    /* 没有原始函数就手动移除 */
      } catch (e) { try { r.remove(); } catch (e2) {} }
    }

    /* 点击跳过（只有视频真的在播时才允许） */
    function X() { if (pl) F(); }
    /* Esc 跳过 */
    function K(e) { if (pl && (e.key === 'Escape' || e.keyCode === 27)) F(); }

    document.addEventListener('mousedown', X, true);
    window.addEventListener('keydown', K, true);

    /* 尝试下一个视频源（两个都失败则标记 fl） */
    function N() {
      if (i >= S.length) { fl = true; return; }
      v.src = S[i++];
      try { v.load(); } catch (e) {}
      P();
    }

    /* ---------- 视频事件 ---------- */
    v.addEventListener('playing', function () {
      if (pl) return;
      pl = true; lt = Date.now();
      r.classList.add('wb-anime-on');       /* 骨架屏切换到磨砂玻璃皮肤 */
      v.style.display = ''; vl.style.display = ''; bd.style.display = ''; sk.style.display = '';
      P();
    });

    /* 记录播放进度，用于检测"卡死" */
    v.addEventListener('timeupdate', function () { lt = Date.now(); });

    /* 读到真实时长后调整总兜底：至少 24s，最长 3 分钟 */
    v.addEventListener('loadedmetadata', function () {
      if (v.duration && isFinite(v.duration)) {
        M = Math.max(24000, Math.min(v.duration * 1000 + 4000, 180000));
      }
    });

    v.addEventListener('ended', function () {
      if (rq) F();                          /* React 已就绪 → 放行 */
      else { try { v.currentTime = 0; P(); } catch (e) {} }   /* 未就绪 → 从头循环再播 */
    });

    v.addEventListener('error', function () {
      if (pl) F();                          /* 播放中出错 → 直接放行 */
      else N();                             /* 还没播起来 → 换下一个源 */
    });

    N();

    /* ---------- 接管拆骨架屏：只记录，不真正拆 ---------- */
    window.__removeSkeleton = function () { rq = true; at = Date.now(); };

    /* ---------- 主循环（150ms 一次）：判断何时放行 ---------- */
    tm = setInterval(function () {
      if (dn) { clearInterval(tm); return; }

      /* 启动失败遮罩（#sk-overlay）被显示 → 立刻放行，把错误界面交给用户 */
      var ov = document.getElementById('sk-overlay');
      if (ov && ov.style.display && ov.style.display !== 'none') { F(); return; }

      if (!rq) return;                      /* React 还没就绪，继续等 */

      var w = Date.now() - at;              /* React 就绪后经过的毫秒数 */

      if (!pl) {                            /* 视频还没播起来 */
        if (fl || w > G) F();               /* 所有源失败 / 等待超 3s → 放行 */
        return;
      }
      if (v.ended || v.paused) { F(); return; }     /* 播完 / 被暂停 → 放行 */
      if (Date.now() - lt > ST) { F(); return; }    /* 播放卡住 2.5s → 放行 */
      if (w > M) F();                       /* 总时长兜底 */
    }, 150);
  } catch (e) {}
})();
