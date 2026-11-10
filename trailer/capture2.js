const { chromium } = require('playwright');
const fs = require('fs');
const W = 1280, H = 576, FPS = 24, DT = 1000 / FPS;
const ONLY = (process.env.ONLY || '').split(',').filter(Boolean);
(async () => {
  fs.mkdirSync('frames', { recursive: true });
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--enable-webgl', '--autoplay-policy=no-user-gesture-required'] });
  const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
  page.on('console', m => { const t = m.text(); if (/ERR|rror|CLIPLOG/.test(t)) console.log('PAGE:', t.slice(0, 260)); });
  page.on('pageerror', e => console.log('PAGEERR', e.message.slice(0, 240)));
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
  for (let i = 0; i < 120; i++) { await page.waitForTimeout(500); if (await page.evaluate(() => document.getElementById('load').style.display === 'none')) break; }
  await page.waitForTimeout(800);
  await page.click('#mnew');
  for (let i = 0; i < 30; i++) { await page.waitForTimeout(400); if (await page.evaluate(() => getComputedStyle(document.getElementById('menu')).display === 'none')) break; }
  for (let i = 0; i < 20; i++) await page.evaluate(ms => window.__adv(ms), 41);
  console.log('jogo iniciado');
  await page.evaluate(() => {
    document.getElementById('hud').style.display = 'none';
    window.__log = (...a) => console.log('CLIPLOG', a.map(x => typeof x == 'string' ? x : JSON.stringify(x)).join(' '));
    window.__goto = (v, tx, tz, amp, f) => {
      P.hp = 100; if (v) v.hp = Math.max(v.hp, 500);
      let err = Math.atan2(tx - v.x, tz - v.z) - v.yaw; err = Math.atan2(Math.sin(err), Math.cos(err));
      J.y = 1; J.x = Math.max(-1, Math.min(1, -err * 2.2)) + Math.sin(f / 16) * (amp || 0);
    };
    window.__REV = () => { P.dead = 0; P.hp = 100; P.rag = null; P.g.visible = true; J.x = 0; J.y = 0; K.Space = false; K.KeyF = false; FZ.mode = 'gnd'; FZ.chute = 0; P.y = P.y > 1 ? .9 : P.y };
    const r0 = rd.render.bind(rd); rd.render = (s, c) => { if (window.__cin) window.__cin(c); r0(s, c); };
  });
  let n = 0, dir = 'x';
  const clip = name => { dir = name; n = 0; fs.mkdirSync('frames/' + name, { recursive: true }); };
  const step = async (shot = true) => {
    await page.evaluate(ms => window.__adv(ms), DT);
    if (shot) await page.screenshot({ path: `frames/${dir}/f${String(n++).padStart(5, '0')}.jpg`, type: 'jpeg', quality: 90 });
  };
  const run = async (frames, every) => { for (let f = 0; f < frames; f++) { await page.evaluate(([f, fr]) => window.__sc && window.__sc(f, fr), [f, frames]); if (every) await every(f); await step(); } };
  const warm = async k => { for (let i = 0; i < k; i++) { await page.evaluate(([f]) => window.__sc && window.__sc(f, 0), [i]); await step(false); } };
  const setup = async code => { await page.evaluate(code); await warm(5); };
  const REV = 'window.__REV();window.__cin=null;';
  const scene = async (name, fn) => {
    if (ONLY.length && !ONLY.includes(name)) return;
    const t0 = Date.now();
    try { await fn(); console.log('OK', name, 'frames', n, (Date.now() - t0) / 1000); }
    catch (e) { console.log('FAIL', name, e.message.slice(0, 300)); }
    await page.evaluate(() => { window.__sc = null; window.__cin = null; J.x = J.y = 0; K.Space = false; K.KeyF = false; }).catch(() => {});
  };
  const clickText = async (t, ms = 300) => { await page.getByText(t, { exact: true }).first().click({ timeout: 4000 }); await page.waitForTimeout(ms); };
  const uiStep = async (k) => { for (let i = 0; i < k; i++) await step(); };

  // ===== CORRIDA: editor de rota + prova
  await scene('race', async () => {
    clip('race_a');
    await page.evaluate(() => { window.__REV(); P.veh = null; const m = MG.mk.find(x => x.id == 'rc'); place(m.x + 3, m.z + 1, 0); });
    await warm(8);
    await page.evaluate(() => { PAUSED = false; bMg.onpointerdown({ preventDefault() {} }); });
    await page.waitForTimeout(300); await clickText('JOGAR'); await warm(4);
    await clickText('CRIAR MINHA ROTA', 600);
    await uiStep(6);
    const pts = [[-230, -70], [-90, -140], [120, -110], [220, 40], [60, 120], [-160, 60]];
    for (const [dx, dy] of pts) { await page.mouse.click(W / 2 + dx, H / 2 + dy); await page.waitForTimeout(120); await uiStep(7); }
    await uiStep(10);
    clip('race_b');
    await page.evaluate(() => { document.getElementById('ed3').click(); });
    await page.waitForTimeout(400);
    await page.evaluate(() => { window.__sc = (f) => { const R = MG.RC, v = P.veh; if (!R || !R.cp || !v || !R.me) return; const t = R.cp[(R.me.k + 1) % R.cp.length]; window.__goto(v, t[0], t[1], 0, f); } });
    await warm(120);
    await run(150);
    await page.evaluate(() => __log('race', { veh: P.veh && P.veh.t, me: MG.RC && MG.RC.me && MG.RC.me.k }));
  });

  // ===== FUTEBOL
  await scene('soccer', async () => {
    clip('soccer');
    await page.evaluate(() => { window.__REV(); P.veh = null; const m = MG.mk.filter(x => x.id == 'fb')[1] || MG.mk.find(x => x.id == 'fb'); place(m.x + 2, m.z + 2, 0); });
    await warm(8);
    await page.evaluate(() => { PAUSED = false; bMg.onpointerdown({ preventDefault() {} }); });
    await page.waitForTimeout(300); await clickText('JOGAR'); await warm(4);
    try { await clickText('Entendi'); } catch (e) {}
    await warm(30);
    await page.evaluate(() => {
      window.__k = 0;
      window.__sc = (f) => {
        const FB = MG.FB; if (!FB || !FB.ball) return; P.hp = 100;
        const gk = FB.pl.find(e => e.team == 1 && e.role == 'gk'); if (gk) gk.x = FB.cx + 14;
        let tx, tz;
        if (FB.hold !== P) { tx = FB.ball.x; tz = FB.ball.z; } else { tx = FB.cx; tz = FB.cz + 31; }
        ca = Math.atan2(tx - P.x, tz - P.z); J.x = 0; J.y = 1;
        if (FB.hold === P) {
          if (!window.__k && P.z > FB.cz + 10) { fbK.onpointerdown({ preventDefault() {} }); window.__k = f + 1; }
          if (window.__k && f + 1 - window.__k > 9) { fbK.onpointerup({}); window.__k = 0; }
          if (f % 40 == 20) fbD.onpointerdown({ preventDefault() {} });
        }
      };
    });
    await run(260);
    await page.evaluate(() => __log('soccer', { sc: MG.FB.sc, hold: MG.FB.hold === P, pz: P.z - MG.FB.cz }));
  });

  // ===== MATA-MATA
  await scene('deathmatch', async () => {
    clip('dm');
    await page.evaluate(() => { window.__REV(); P.veh = null; const m = MG.mk.find(x => x.id == 'sv'); place(m.x + 2, m.z + 2, 0); });
    await warm(8);
    await page.evaluate(() => { PAUSED = false; bMg.onpointerdown({ preventDefault() {} }); });
    await page.waitForTimeout(300); await clickText('JOGAR'); await warm(6);
    await page.evaluate(() => { own.smg = { mag: 30, res: 9999 }; own.shot = { mag: 8, res: 999 }; own.rpg = { mag: 1, res: 99 }; cur = 'smg'; });
    await warm(30);
    await page.evaluate(() => {
      window.__sc = (f) => {
        const SV = MG.SV; P.hp = 100; K.KeyF = true; own.smg.mag = 30;
        let best = null, bd = 1e9; (SV.en || []).forEach(p => { if (p.rag || p.hp <= 0) return; const d = Math.hypot(p.x - P.x, p.z - P.z); if (d < bd) { bd = d; best = p } });
        if (best) { ca = Math.atan2(best.x - P.x, best.z - P.z); J.x = Math.sin(f / 12) * .8; J.y = bd > 12 ? .6 : (bd < 6 ? -.4 : 0); P.yaw = ca; if (f % 36 == 30) { try { boom(best.x, best.z) } catch (e) {} } }
      };
    });
    await run(230);
    await page.evaluate(() => __log('dm', { wave: MG.SV.wave, en: MG.SV.en.length, st: MG.SV.state }));
  });

  // ===== MUNDO ABERTO (várias cenas curtas)
  const car = (name, kind, lane, frames, amp = .05) => scene(name, async () => {
    clip(name);
    await setup(`${REV}place(L[${lane}]+3.5,-195,0);const c=spawnV('${kind}',P.x,P.z+4,0,0xe02020,0);c.ai=0;c.tr=0;P.veh=c;window.__sc=(f)=>{__goto(P.veh,L[${lane}]+3.5,P.veh.z+40,${amp},f)}`);
    await run(frames);
  });
  await car('ow_sup', 'sup', 2, 60);
  await car('ow_moto', 'smoto', 5, 48, .1);

  await scene('ow_ramp', async () => {
    clip('ow_ramp');
    await setup(`${REV}place(150,-200,PI/2);const c=spawnV('sup',P.x+3,P.z,PI/2,0x2255dd,0);c.ai=0;c.tr=0;P.veh=c;window.__sc=(f)=>{__goto(P.veh,P.veh.x+40,-200,0,f)}`);
    await run(110);
    await page.evaluate(() => __log('ramp', { y: P.veh && P.veh.y, x: P.veh && P.veh.x }));
  });

  await scene('ow_police', async () => {
    clip('ow_police');
    await setup(`${REV}place(L[6]+3.5,-195,0);const c=spawnV('sup',P.x,P.z+4,0,0x111111,0);c.ai=0;c.tr=0;P.veh=c;crime(6,P.x,P.z);window.__sc=(f)=>{__goto(P.veh,L[6]+3.5,P.veh.z+40,.04,f);const v=P.veh;if(v&&(f==30||f==70)){boom(v.x+Math.sin(v.yaw)*28,v.z+Math.cos(v.yaw)*28)}}`);
    await run(96);
    await page.evaluate(() => __log('police', { st: stars() }));
  });

  await scene('ow_shop_gun', async () => {
    clip('ow_shop_gun');
    await setup(`${REV}H.h=0;const m=XSHOP_API.MK.find(x=>x.id=='ar');place(m.x,m.z+1.5,0);window.__m=m`);
    await page.evaluate(() => { PAUSED = false; money = 99999; XSHOP_API.openShop(window.__m); });
    await uiStep(20);
    for (let i = 0; i < 3; i++) { await page.evaluate(() => { const e = document.getElementById('sr'); e && e.onpointerdown && e.onpointerdown({}) }); await uiStep(14); }
    await page.evaluate(() => { const e = document.getElementById('sbuy'); e && e.onpointerdown && e.onpointerdown({}) }); await uiStep(14);
  });

  await scene('ow_shop_clothes', async () => {
    clip('ow_shop_clothes');
    await setup(`${REV}H.h=0;const m=XSHOP_API.MK.find(x=>x.id=='cl');place(m.x,m.z,0);window.__m=m`);
    await page.evaluate(() => { PAUSED = false; money = 99999; XSHOP_API.openShop(window.__m); });
    await uiStep(30);
    await page.evaluate(() => __log('clothes ui', { html: document.body.innerText.slice(0, 120) }));
    for (let i = 0; i < 3; i++) { await page.evaluate(() => { const b = [...document.querySelectorAll('#hud *,body *')].filter(e => e.onpointerdown && /›|>|▶|→/.test(e.textContent)).slice(0, 1); b.forEach(e => e.onpointerdown({ preventDefault() {} })) }); await uiStep(12); }
  });

  await scene('ow_garage', async () => {
    clip('ow_garage');
    await setup(`${REV}H.h=0;const g=XSHOP_API.MK.find(x=>x.id=='gx');place(g.x-6,g.z,0);const c=spawnV('sup',P.x,P.z,PI/2,0xe02020,0);c.ai=0;c.tr=0;P.veh=c;window.__gm=g;`);
    await page.evaluate(() => { PAUSED = false; XGG.begin(P.veh); document.getElementById('hud').style.display = 'none'; });
    await uiStep(110);
    await page.evaluate(() => __log('garage', { st: XGG.st, ui: document.body.innerText.slice(0, 100) }));
  });

  await scene('ow_house', async () => {
    clip('ow_house');
    await setup(`${REV}H.h=0;const m=XSHOP_API.MK.find(x=>x.id=='pr_x3');place(m.x,m.z,0);window.__m=m;window.__cin=(c)=>{const t=window.__tc||0;c.position.set(__m.x+Math.sin(t)*20,9,__m.z+Math.cos(t)*20);c.lookAt(__m.x,4,__m.z)};window.__sc=(f)=>{window.__tc=f*.03-.6}`);
    await run(60);
  });

  const boat = (name, kind) => scene(name, async () => {
    clip(name);
    await setup(`${REV}place(-285,-10,0);const c=XVEH.spawnK('${kind}',-290,-10,0)||vehs[vehs.length-1];window.__b=c;P.veh=c;c.ai=0;c.tr=0;window.__sc=(f)=>{P.hp=100;J.y=1;J.x=Math.sin(f/14)*.5}`);
    await page.evaluate(() => __log('boat', { t: P.veh && P.veh.t, y: P.veh && P.veh.y }));
    await run(60);
  });
  await boat('ow_boat', 'lancha');
  await boat('ow_jet', 'jetski');

  await scene('ow_plane', async () => {
    clip('ow_plane');
    await setup(`${REV}place(-250,20,0);const c=spawnV('plane',-250,24,0,0xdd2222,0);c.y=45;c.sp=40;c.ai=0;c.tr=0;P.veh=c;window.__sc=(f)=>{P.hp=100;c.hp=500;J.y=1;K.Space=true;J.x=Math.sin(f/20)*.6}`);
    await run(80);
    await page.evaluate(() => __log('plane', { y: P.veh && P.veh.y }));
  });

  await scene('ow_chute', async () => {
    clip('ow_chute');
    await setup(`${REV}P.veh=null;place(0,0,0);own.para=1;P.y=160;FZ.mode='air';FZ.vy=0;window.__sc=(f)=>{P.hp=100;ca+=.012;if(f==36){document.getElementById('bPa').onpointerdown({preventDefault(){}})}}`);
    await run(120);
    await page.evaluate(() => __log('chute', { y: P.y, mode: FZ.mode, ch: FZ.chute }));
  });

  // ===== FINAL cinematográfico
  await scene('finale', async () => {
    clip('finale');
    await setup(`${REV}P.veh=null;H.h=0;place(0,0,0);window.__cin=(c)=>{const t=window.__tf||0,k=Math.min(1,t/7),e=k*k*(3-2*k),d=4+e*150,h=2.4+e*95,a=2.2+t*.25;c.position.set(P.x+Math.sin(a)*d,h,P.z+Math.cos(a)*d);c.lookAt(P.x,1.4+e*2,P.z)};window.__sc=(f)=>{window.__tf=f/24;P.hp=100}`);
    await run(192);
  });

  await browser.close();
})();
