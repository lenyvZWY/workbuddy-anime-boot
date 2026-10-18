import puppeteer from 'file:///C:/Users/18334/.workbuddy/binaries/node/workspace/node_modules/puppeteer-core/lib/esm/puppeteer/puppeteer-core.js';

const EDGE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const here = 'C:/Users/18334/WorkBuddy/2026-10-18-17-53-40/wbboot';
const b = await puppeteer.launch({
  executablePath: EDGE, headless: true,
  args: ['--no-sandbox', '--hide-scrollbars', '--autoplay-policy=no-user-gesture-required'],
  defaultViewport: { width: 1280, height: 720 },
});
const at = (p, t) => p.evaluate(ms => new Promise(r => {
  const d = ms - performance.now(); d <= 0 ? r() : setTimeout(r, d);
}), t);
const probe = p => p.evaluate(() => {
  const st = document.getElementById('wbboot-stage');
  const v = document.getElementById('wbboot-video');
  const img = document.getElementById('wb550c-logo');
  return {
    stage: st ? (st.className || 'on') : 'GONE',
    op: st ? (+getComputedStyle(st).opacity).toFixed(2) : '-',
    t: v ? +v.currentTime.toFixed(2) : '-',
    ended: v ? v.ended : '-',
    logo: img ? img.naturalWidth : '-',
    app: getComputedStyle(document.getElementById('fake-app')).display,
  };
});

for (const [file, marks] of [['demo.html', [1200, 3200, 6300, 6900]], ['demo-550c.html', [1200, 2200, 3100, 3600]]]) {
  const p = await b.newPage();
  const errs = [];
  p.on('pageerror', e => errs.push(e.message));
  await p.goto('file:///' + here + '/docs/' + file, { waitUntil: 'load' });
  for (const t of marks) {
    await at(p, t);
    await p.screenshot({ path: `${here}/docs/shots/${file.replace('.html', '')}-${t}.png` });
    console.log(file.padEnd(16), t, JSON.stringify(await probe(p)));
  }
  console.log(file.padEnd(16), 'errors', errs.length ? errs.slice(0, 2) : 'none');
  await p.close();
}
await b.close();
