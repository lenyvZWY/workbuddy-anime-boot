/* ==========================================================================
 * WorkBuddy Boot —— ⓪ App 入口闸门（独立脚本，不参与主流程的 try/catch）
 * --------------------------------------------------------------------------
 * 构建期会把 index.html 里的 deferred module 入口改成不可执行的类型
 * （type="text/wb-deferred" + data-wb-entry），让开屏期间它既不下载也不执行。
 * 那段标记必须由谁来"放行"—— 就是这里。
 *
 * 为什么单独一个文件、单独一段 <script>：
 *   主接管脚本（stage-splash.js）整体包在 try/catch 里，任何异常都会静默返回。
 *   如果放行逻辑也在里面，一旦它出错，App 就永远不会启动（白屏 + 骨架屏）。
 *   所以闸门独立存在，并且带一个 6s 的看门狗 —— 无论动画那侧发生什么，
 *   6 秒后一定把 App 放出来。
 * ========================================================================== */
(function () {
  var done = false;

  function boot(reason) {
    if (done) return;
    var el = document.querySelector('script[data-wb-entry]');
    if (!el) return;                  /* 没扣住过（老版本 / 已被放行）→ 什么都不做 */
    var src = el.getAttribute('src');
    if (!src) return;
    done = true;

    var s = document.createElement('script');
    s.type = 'module';
    s.setAttribute('data-wb-released', reason || '1');
    var co = el.getAttribute('crossorigin');
    if (co !== null) s.setAttribute('crossorigin', co || '');
    s.src = src;
    s.onerror = function () {
      /* 相对路径失败 → 绝对 URL 再试一次（file:// 下 module 受 CORS 限制时有用） */
      try {
        if (s.dataset.retried) return;
        s.dataset.retried = '1';
        s.src = new URL(src, location.href).href;
        (document.head || document.documentElement).appendChild(s);
      } catch (e) {}
    };
    (document.head || document.documentElement).appendChild(s);
  }

  /* 对外只暴露这一个函数，主脚本到点就调它 */
  window.__wbBootApp = boot;

  /* 看门狗：主脚本没来叫，也放行 */
  setTimeout(function () { boot('watchdog'); }, 6000);
})();
