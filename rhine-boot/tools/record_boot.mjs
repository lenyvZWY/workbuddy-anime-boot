import puppeteer from 'file:///C:/Users/18334/.workbuddy/binaries/node/workspace/node_modules/puppeteer-core/lib/esm/puppeteer/puppeteer-core.js';
import fs from 'node:fs';

const EDGE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const here = 'C:/Users/18334/WorkBuddy/2026-10-18-17-53-40/wbboot';
const dir = here + '/docs/frames';
fs.rmSync(dir, { recursive: true, force: true });
fs.mkdirSync(dir, { recursive: true });

const b = await puppeteer.launch({
  executablePath: EDGE, headless: 'new',
  args: ['--no-sandbox', '--hide-scrollbars', '--force-device-scale-factor=1'],
  defaultViewport: { width: 1280, height: 800 },
});
const p = await b.newPage();
const cdp = await p.createCDPSession();

let n = 0;
const stamps = [];
cdp.on('Page.screencastFrame', async ({ data, sessionId, metadata }) => {
  fs.writeFileSync(`${dir}/f${String(n++).padStart(4, '0')}.jpg`, Buffer.from(data, 'base64'));
  stamps.push(metadata.timestamp || Date.now() / 1000);
  try { await cdp.send('Page.screencastFrameAck', { sessionId }); } catch (e) {}
});

await p.goto('file:///' + here + '/preview/built-splash.html', { waitUntil: 'load' });
await cdp.send('Page.startScreencast', { format: 'jpeg', quality: 88, maxWidth: 1280, maxHeight: 800, everyNthFrame: 1 });
await new Promise(r => setTimeout(r, 9000));
await cdp.send('Page.stopScreencast');
// 把每帧的真实间隔写成 ffmpeg concat 清单，避免"按固定帧率编码"把快慢段拉歪
const lines = [];
for (let i = 0; i < n; i++) {
  const dt = i < n - 1 ? Math.max(0.004, stamps[i + 1] - stamps[i]) : 0.04;
  lines.push(`file 'f${String(i).padStart(4, '0')}.jpg'`);
  lines.push(`duration ${dt.toFixed(4)}`);
}
lines.push(`file 'f${String(n - 1).padStart(4, '0')}.jpg'`);
fs.writeFileSync(`${dir}/list.txt`, lines.join('\n'));
const wall = stamps.length ? stamps[stamps.length - 1] - stamps[0] : 0;
console.log('frames', n, 'wall', wall.toFixed(2) + 's', 'avg fps', (n / wall).toFixed(1));
await b.close();
