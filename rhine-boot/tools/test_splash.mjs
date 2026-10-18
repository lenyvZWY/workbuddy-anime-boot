import puppeteer from 'file:///C:/Users/18334/.workbuddy/binaries/node/workspace/node_modules/puppeteer-core/lib/esm/puppeteer/puppeteer-core.js';

const EDGE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const here = 'C:/Users/18334/WorkBuddy/2026-10-18-17-53-40/wbboot';
const b = await puppeteer.launch({ executablePath: EDGE, headless: true, args: ['--no-sandbox', '--hide-scrollbars'], defaultViewport: { width: 1280, height: 800 } });

const probe = p => p.evaluate(() => {
  const sp = document.getElementById('rhine-splash');
  const bd = document.getElementById('wbboot-stage');
  const sk = document.getElementById('skeleton-root');
  const app = document.getElementById('app');
  return {
    splash: !!sp,
    backdrop: bd ? (bd.className || 'on') + '/' + (+getComputedStyle(bd).opacity).toFixed(2) : 'GONE',
    skeleton: !!sk,
    app: !!app,
    cls: sp ? sp.className : '-',
  };
});

const run = async (name, query, marks, shotAt) => {
  const p = await b.newPage();
  const errs = [];
  p.on('pageerror', e => errs.push(e.message.slice(0, 100)));
  await p.goto('file:///' + here + '/preview/built-splash.html' + query, { waitUntil: 'load' });
  for (const t of marks) {
    await p.evaluate(ms => new Promise(r => { const d = ms - performance.now(); d <= 0 ? r() : setTimeout(r, d); }), t);
    console.log(name, String(t).padStart(5), JSON.stringify(await probe(p)));
    if (shotAt.includes(t)) await p.screenshot({ path: `${here}/docs/shots/boot-${name}-${t}.png` });
  }
  console.log(name, 'errors', errs.length ? errs.slice(0, 2) : 'none');
  await p.close();
};

// A. 正常：应用 1.2s 就绪
await run('A', '', [600, 1400, 2600, 4200, 4900, 5400], [1400, 2600, 4900]);
// B. 应用慢：一直不就绪 → 动画播完先撤底板露骨架屏
await run('B', '?hold=1', [2600, 4600, 5600], [5600]);
// C. Esc 跳过
const p = await b.newPage();
await p.goto('file:///' + here + '/preview/built-splash.html', { waitUntil: 'load' });
await p.evaluate(ms => new Promise(r => { const d = ms - performance.now(); d <= 0 ? r() : setTimeout(r, d); }), 1200);
await p.keyboard.press('Escape');
await p.evaluate(ms => new Promise(r => { const d = ms - performance.now(); d <= 0 ? r() : setTimeout(r, d); }), 2200);
console.log('C  esc  ', JSON.stringify(await probe(p)));

await b.close();
