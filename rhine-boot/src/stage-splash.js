/* ==========================================================================
 * WorkBuddy Boot —— ④ 莱茵开屏舞台逻辑（注入到 </body> 之前）
 * --------------------------------------------------------------------------
 * 素材：media/wb-rhine-splash.js —— 用户自己的「WorkBuddy · 莱茵生命开屏」载荷
 *       （派生自 dsh-rhine-splash，MIT © 2026 ArtemisFowl；build.py 生成的自包含脚本）
 *
 * 为什么是"外挂脚本"而不是内联：
 *   载荷 134KB（CSS 95KB + 标记 + base64 壁纸），而 renderer/index.html 的
 *   字节数是 asar 头部锁死的 27841，腾完注释和缩进也只有约 9.2KB 余量。
 *   主窗口 CSP 的 script-src 明确带 `local-file:`，所以用
 *     <script src="local-file:///…/wb-rhine-splash.js">
 *   把载荷当外挂脚本加载 —— index.html 里只留这段 2KB 多的接管逻辑。
 *
 * 载荷自己的生命周期（实测）：
 *   0.00s  门扇闭合的静帧（--rl-bg #edece8）
 *   0.25s  Act A 权限核验 PERMISSION AUTHORIZED
 *   1.60s  Act B 欢迎锁屏 / 徽记 / 模块瓦片
 *   3.70s  退场：main 淡出、门缝开启、门扇分开
 *   4.50s  自行 root.remove() —— 我们就是靠"元素消失"判定它播完的
 *
 * 放行规则（和视频舞台一致）：
 *   动画播完（#rhine-splash 消失） && 应用就绪（__removeSkeleton 被调用）
 *   两个都满足 → 撤底板 + 拆骨架屏，真实界面露出来。
 *   应用慢的话，动画播完就先把底板撤掉、把骨架屏交还给应用，不硬等。
 *
 * 兜底：
 *   · 载荷脚本加载失败（CSP / 协议 / 文件缺失）→ 立刻撤底板，绝不黑屏
 *   · 2.5s 还没见到 #rhine-splash → 认定没起来，撤底板
 *   · 12s 硬上限 → 强制移除载荷 + 撤底板
 *   · 整体 try/catch
 * ========================================================================== */
(function () {
  try {
    /* 载荷素材的绝对路径（安装器替换成裸路径，例如 D:/wb/WorkBuddy/resources/wb-rhine-splash.js） */
    var PATH = '__ASSET_PATH__';
    var NAME = 'wb-rhine-splash.js';

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

    var FADE = 380;      /* 与 CSS transition 对齐 */
    var APPEAR = 2500;   /* 超出这个时间还没见到载荷 → 认定没起来 */
    var CAP = 12000;     /* 硬上限 */

    var t0 = Date.now();
    var orig = window.__removeSkeleton;
    var argv = null;
    var ready = false, passed = false, out = false, seen = false, done = false;
    var tm = null;

    /* ---------- 底板：盖住骨架屏，颜色与载荷首帧一致 ---------- */
    var bd = document.createElement('div');
    bd.id = 'wbboot-stage';
    (document.body || document.documentElement).appendChild(bd);

    function stop() { if (tm) { clearInterval(tm); tm = null; } }

    function pass() {
      if (passed) return;
      passed = true;
      try { if (typeof orig === 'function') orig.apply(null, argv || []); else root.remove(); }
      catch (e) { try { root.remove(); } catch (e2) {} }
    }

    function fade() {
      if (out) return;
      out = true;
      bd.classList.add('wbboot-out');
      document.removeEventListener('keydown', onKey, true);
      setTimeout(function () { try { bd.remove(); } catch (e) {} }, FADE + 80);
    }

    /* 载荷还在但该收场了（跳过 / 超时）→ 连它的样式一起清掉 */
    function wipe() {
      var el = document.getElementById('rhine-splash');
      if (el) { try { el.remove(); } catch (e) {} }
      var st = document.getElementById('rhine-splash-css');
      if (st) { try { st.remove(); } catch (e) {} }
    }

    /* 跳过：只处理 Esc —— 点击交给载荷自己（它自带"点击任意处跳过"），
       两套都拦会互相打架 */
    function onKey(e) {
      if (e.key !== 'Escape' && e.keyCode !== 27) return;
      if (done) return;
      done = true; stop(); wipe();
      if (ready) pass();
      fade();
    }

    /* 载荷消失 = 动画播完 */
    function onSplashGone() {
      seen = true;
      try { document.documentElement.setAttribute('data-wbboot', 'ok'); } catch (e) {}
      if (ready) { pass(); fade(); }
      else { fade(); }        /* 应用还在启动：把骨架屏交还给它 */
    }

    /* 载荷压根没起来（脚本加载失败 / CSP / 文件缺失）
       把状态写到标题和 <html data-wbboot>：一眼能看出是"没加载"还是"正常播完" */
    function bail() {
      if (done) return;
      done = true; stop();
      wipe();
      try {
        document.documentElement.setAttribute('data-wbboot', 'fallback-' + ci);
        if (document.title.indexOf('WorkBuddy') === 0) document.title = 'WorkBuddy';
      } catch (e) {}
      if (ready) pass();
      fade();
    }

    /* 注入时刻：用来估算"挂载开销"，预判载荷会不会降级（见 loadNext 之后） */
    var tInject = Date.now();

    /* ---------- 加载外挂载荷（三级回退）----------
       ① 相对路径：index.html 在 resources/app.asar.unpacked/renderer/，
          资产在 resources/，所以是 ../../wb-rhine-splash.js。同源（'self'）即可，不依赖 CSP 里的协议白名单；
       ② local-file:/// ：主窗口 CSP 的 script-src 明确带 local-file:
       ③ file:///      ：兜底，页面本身是 file:// 时 'self' 命中
       谁先成功就用谁；三级都失败就撤底板，绝不黑屏。 */
    var cands = ['../../' + NAME, 'local-file:///' + PATH, 'file:///' + PATH];
    var ci = 0;

    function loadNext() {
      if (ci >= cands.length) { bail(); return; }
      var src = cands[ci++];
      var sc = document.createElement('script');
      sc.src = src;
      sc.onerror = loadNext;
      (document.head || document.documentElement).appendChild(sc);
    }

    loadNext();

    /* ---------- 预判降级：把 is-lite 提前到首帧，避免动画中途翻转 ----------
       载荷自己会在 start() 后 400ms 采样帧间隔，p95 > 34ms 就加 is-lite。
       但那个采样窗口正好和"挂载那 200ms 停顿"重叠 → 几乎必然超标，
       于是它会在动画已经播了 ~700ms 时才翻转一次 —— 实测这一下会带来
       一次全局样式重算 + 74vw 位图重栅格化，单帧 75ms（真机就是"卡一下"）。
       终态本来就是 lite，所以：只要"挂载耗时"已经超过它自己的阈值(34ms)，
       就在 #rhine-splash 插入的同一拍把 is-lite 打上 —— 首帧即降级，
       不再有中途翻转，观感与载荷自己判定的结果一致。 */
    var liteDone = false;
    var liteTimer = null;

    function preLite(el) {
      if (liteDone || !el) return;
      if (Date.now() - tInject <= 34) return;   /* 挂载够快 → 交给载荷自己判 */
      liteDone = true;
      try { el.classList.add('is-lite'); } catch (e) {}
    }

    try {
      var mo = new MutationObserver(function () {
        var el = document.getElementById('rhine-splash');
        if (el) { preLite(el); mo.disconnect(); }
      });
      mo.observe(document.body || document.documentElement, { childList: true, subtree: true });
      liteTimer = setTimeout(function () { try { mo.disconnect(); } catch (e) {} }, 4000);
    } catch (e) {}

    window.addEventListener('keydown', onKey, true);

    /* ---------- 接管拆骨架屏 ---------- */
    window.__removeSkeleton = function () {
      argv = arguments;
      ready = true;
      if (done) pass();       /* 已经收过场（跳过 / 失败 / 播完）→ 立刻放行 */
    };

    /* ---------- 主循环（100ms）---------- */
    tm = setInterval(function () {
      var el = document.getElementById('rhine-splash');
      var el2 = document.getElementById('sk-overlay');

      /* 启动失败遮罩出现 → 立刻交界面 */
      if (el2 && el2.style.display && el2.style.display !== 'none') {
        stop(); done = true; wipe(); pass(); fade(); return;
      }

      if (el) seen = true;

      if (seen && !el && !done) {          /* 载荷自己 remove 了 = 播完 */
        done = true; stop(); onSplashGone(); return;
      }

      var el3 = Date.now() - t0;
      if (!seen && el3 > APPEAR) { stop(); bail(); return; }
      if (el3 > CAP) { stop(); bail(); return; }
    }, 100);
  } catch (e) {}
})();
