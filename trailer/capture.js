const { chromium } = require('playwright');
const fs = require('fs');
const W = 1280, H = 576, FPS = 24, DT = 1000 / FPS;
(async () => {
  fs.mkdirSync('frames', { recursive: true });
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--enable-webgl', '--autoplay-policy=no-user-gesture-required'] });
  const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
  page.on('console', m => { const t = m.text(); if (/ERR|rror/.test(t)) console.log('PAGE:', t.slice(0, 200)); });
  page.on('pageerror', e => console.log('PAGEERR', e.message.slice(0, 200)));
  await page.addInitScript(() => {
    window.__q = []; window.__t = 1000;
    window.requestAnimationFrame = cb => { window.__q.push(cb); return window.__q.length; };
    window.cancelAnimationFrame = () => {};
    performance.now = () => window.__t;
    window.__adv = ms => { window.__t += ms; const q = window.__q; window.__q = []; q.forEach(cb => cb(window.__t)); };
  });
  const three = fs.readFileSync('three.min.js');
  await page.route('**/three.min.js', r => r.fulfill({ body: three, contentType: 'application/javascript' }));
  await page.goto('file://' + process.cwd() + '/game.html');
  await page.waitForTimeout(500);
  await page.click('#bj');
  for (let i = 0; i < 120; i++) {
    await page.waitForTimeout(500);
    const done = await page.evaluate(() => document.getElementById('load').style.display === 'none');
    if (done) break;
  }
  console.log('carregado');
  await page.evaluate(() => { document.getElementById('hud').style.display = 'none'; });
  let n = 0;
  const step = async (shot = true) => {
    await page.evaluate(ms => window.__adv(ms), DT);
    if (shot) { await page.screenshot({ path: `frames/f${String(n++).padStart(5, '0')}.jpg`, type: 'jpeg', quality: 90 }); }
  };
  const run = async (frames, fn) => { for (let f = 0; f < frames; f++) { if (fn) await page.evaluate(([f, fr]) => window.__sc && window.__sc(f, fr), [f, frames]); await step(); } };
  const setup = async code => { await page.evaluate(code); for (let i = 0; i < 6; i++) await step(false); };
  const t0 = Date.now();
  // ---- S1: a pé, câmera orbitando
  await setup(`PAUSED=false;P.veh=null;J.x=0;J.y=0;place(L[3]+3.5,-120,0);P.g.visible=true;window.__sc=(f)=>{ca+=.035}`);
  await run(72);
  // ---- S2: carro
  await setup(`J.x=0;J.y=0;place(L[2]+3.5,-195,0);const c=spawnV('car',P.x,P.z+4,0,0xe02020,0);c.ai=0;c.tr=0;P.veh=c;window.__sc=(f)=>{J.y=1;J.x=Math.sin(f/18)*.12}`);
  await run(120);
  // ---- S3: caos
  await setup(`J.x=0;J.y=0;place(L[6]+3.5,-195,0);const c2=spawnV('car',P.x,P.z+4,0,0xf0c020,0);c2.ai=0;c2.tr=0;P.veh=c2;crime(3,P.x,P.z);window.__sc=(f)=>{J.y=1;J.x=Math.sin(f/14)*.1;const v=P.veh;if(v&&(f==24||f==62||f==98||f==125)){boom(v.x+Math.sin(v.yaw)*(26+f/6),v.z+Math.cos(v.yaw)*(26+f/6)+(f%2?4:-4))}}`);
  await run(144);
  // ---- S4: moto
  await setup(`J.x=0;J.y=0;place(L[1]+3.5,-195,0);const m=spawnV('moto',P.x,P.z+3,0,0x2255dd,0);m.ai=0;m.tr=0;P.veh=m;window.__sc=(f)=>{J.y=1;J.x=Math.sin(f/10)*.15}`);
  await run(96);
  // ---- S5: final, a pé em perseguição
  await setup(`J.x=0;J.y=0;P.veh=null;place(L[4]+3.5,40,PI);H.h=4.6;crime(2,P.x,P.z);window.__sc=(f)=>{ca-=.03}`);
  await run(60);
  console.log('frames', n, 'seg', (Date.now() - t0) / 1000);
  await browser.close();
})();
