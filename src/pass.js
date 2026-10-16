/* ==========================================================================
 * WorkBuddy Anime Boot — ⑤ 大面板持续透明化（总是注入，"保险丝"）
 * --------------------------------------------------------------------------
 * 背景：WorkBuddy 界面由 React 动态渲染，面板背景色来自各种 CSS 变量。
 *       我们已经用 ① skin-dark.css 覆盖了已知变量，但仍可能有漏网之鱼：
 *         · 不同版本存在没覆盖到的变量；
 *         · 切换任务等操作会渲染出全新面板，样式可能不经过我们覆盖的变量。
 *       所以再加这道动态保险：把所有"面积大、不透明、无背景图"的面板
 *       自动改成半透明深色，保证壁纸始终透得出来。
 *
 * 为什么不会卡、不会死循环：
 *   · 已处理的元素（内联背景色已是目标值）直接跳过 → 天然收敛；
 *   · DOM 变化用 MutationObserver 捕获 + 300ms 节流（React 再频繁也不怕）；
 *   · 另有 4.5 秒兜底轮询做双保险（已处理元素会被瞬间跳过，开销极小）。
 *
 * 目标值：rgba(9,11,17,0.18) —— 18% 不透明的深色，与皮肤整体观感一致。
 * ========================================================================== */
(function () {
  try {
    var TARGET = 'rgba(9,11,17,0.18)';

    /* 扫描全页，把符合条件的"大面板"透明化 */
    function fx() {
      var els = document.querySelectorAll('div,main,section,aside,nav,header,footer,ul');
      var min = innerWidth * innerHeight * 0.07;      /* 面积阈值：视口的 7% */

      for (var i = 0; i < els.length; i++) {
        var e = els[i];

        /* 跳过根节点和我们自己的元素 */
        if (e.id === 'root' || e.id.indexOf('wb-') === 0) continue;

        /* 已处理过（内联背景色已是目标值）→ 跳过，保证收敛
           注：内联样式读回来带空格，所以去掉空格再比较 */
        if (e.style.backgroundColor.replace(/ /g, '') === TARGET) continue;

        var r = e.getBoundingClientRect();
        if (r.width * r.height < min) continue;        /* 小元素不动（代码块、按钮等） */

        var cs = getComputedStyle(e);
        if (cs.backgroundImage !== 'none') continue;   /* 带背景图的不动（可能是设计元素） */

        var bc = cs.backgroundColor;
        if (!bc || bc === 'transparent' || bc === 'rgba(0, 0, 0, 0)') continue;  /* 本来就透明 */

        e.style.setProperty('background-color', TARGET, 'important');
      }
    }

    /* DOM 变化 → 300ms 节流后重扫 */
    var Q = false, T = null;
    function sc() {
      if (Q) return;
      Q = true;
      if (T) clearTimeout(T);
      T = setTimeout(function () { Q = false; fx(); }, 300);
    }

    function bt() {
      fx();   /* 立即执行一次 */

      /* 持续监听 DOM 变化（含 style/class 改动 —— 切换任务时 React 会改这些） */
      try {
        new MutationObserver(sc).observe(document.body, {
          childList: true, subtree: true,
          attributes: true, attributeFilter: ['style', 'class']
        });
      } catch (e) {}

      /* 启动阶段多跑几次（首屏渲染是分批完成的） */
      [600, 1600, 3200, 6000, 10000].forEach(function (d) { setTimeout(fx, d); });

      /* 长期兜底轮询 */
      setInterval(fx, 4500);
    }

    if (document.body) bt();
    else document.addEventListener('DOMContentLoaded', bt);
  } catch (e) {}
})();
