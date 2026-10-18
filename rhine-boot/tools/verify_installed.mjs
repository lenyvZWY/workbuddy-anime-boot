import puppeteer from 'file:///C:/Users/18334/.workbuddy/binaries/node/workspace/node_modules/puppeteer-core/lib/esm/puppeteer/puppeteer-core.js';

const EDGE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const target = 'file:///D:/wb/WorkBuddy/resources/app.asar.unpacked/renderer/index.html';
const b = await puppeteer.launch({
  executablePath: EDGE, headless: true,
  args: ['--no-sandbox', '--allow-file-access-from-files', '--autoplay-policy=no-user-gesture-required'],
  defaultViewport: { width: 1280, height: 720 },
});

const probe = p => p.evaluate(() => {
  const st = document.getElementById('wbboot-stage');
  const v = document.getElementById('wbboot-video');
  return {
    stage: st ? (st.className || 'on') : 'GONE',
    op: st ? (+getComputedStyle(st).opacity).toFixed(2) : '-',
    t: v ? +v.currentTime.toFixed(2) : '-',
    dur: v && v.duration ? +v.duration.toFixed(2) : '-',
    ended: v ? v.ended : '-',
    src: v && v.currentSrc ? v.currentSrc.slice(-24) : '-',
  };
});

// ---- 1. 窗口类型闸门 ----
for (const q of ['', '?windowAppId=main', '?windowAppId=settings', '?windowAppId=global-search', '?windowAppId=office']) {
  const p = await b.newPage();
  await p.goto(target + q, { waitUntil: 'load' });
  await new Promise(r => setTimeout(r, 350));
  const s = await p.evaluate(() => ({ stage: !!document.getElementById('wbboot-stage') }));
  console.log((q || '(no query)').padEnd(28), 'stage=' + s.stage);
  await p.close();
}

// ---- 2. 主窗口：起播 / 播完 / 淡出 ----
const p = await b.newPage();
const errs = [];
p.on('pageerror', e => errs.push(e.message));
await p.goto(target, { waitUntil: 'load' });
for (const [label, wait] of [['t=1s', 1000], ['t=3s', 2000], ['t=6.2s', 3200], ['t=6.6s', 400]]) {
  await new Promise(r => setTimeout(r, wait));
  console.log(label, JSON.stringify(await probe(p)));
}
await p.evaluate(() => window.__removeSkeleton && window.__removeSkeleton());
await new Promise(r => setTimeout(r, 900));
console.log('after-ready', JSON.stringify(await probe(p)));
console.log('errors', errs.length ? errs.slice(0, 3) : 'none');
await b.close();
