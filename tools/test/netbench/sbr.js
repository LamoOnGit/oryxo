// BR classé à 2 joueurs (jetons tA / tB du faux Supabase) : le joueur A roule tout droit,
// on mesure la régularité de son tank chez lui (« toi ») et vu par B (« vu par l'autre »).
// Usage : node sbr.js <étiquette> [dbg]   (lancé par run.sh)
const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch();
  const ev = (p, c) => p.evaluate((c) => window.__g.ev(c), c);
  const P = [];
  for (const tok of ['tA', 'tB']) { const q = await (await b.newContext()).newPage({ viewport: { width: 640, height: 400 } }); await q.goto((process.env.BENCH_URL || 'http://127.0.0.1:3364') + '/'); await q.waitForTimeout(1200);
    await q.evaluate(tok => { const ws = new WebSocket(location.origin.replace(/^http/, 'ws') + '/mm?mode=solo&token=' + tok); ws.onmessage = e => { const m = JSON.parse(e.data.slice(2)); if (m.t === 'match') window.__g.ev('Er(location.origin,' + JSON.stringify(m.room) + ',' + JSON.stringify(m.ticket) + ')'); }; }, tok); P.push(q); }
  const [A, B] = P;
  for (let i = 0; i < 40; i++) { await A.waitForTimeout(1000); if (await ev(A, 'f.state') === 'play' && await ev(A, '!!(p && p.alive)')) break; }
  await A.waitForTimeout(1500);
  const nid = await ev(A, 'f.meNid'); 
  const stat = (s) => { s = s.slice(30).filter(r => isFinite(r[1]));
    const fit = (k) => { const n = s.length, mt = s.reduce((a, r) => a + r[0], 0) / n, mv = s.reduce((a, r) => a + r[k], 0) / n; let num = 0, den = 0; for (const r of s) num += (r[0] - mt) * (r[k] - mv), den += (r[0] - mt) ** 2; const sl = num / den; return s.map(r => r[k] - (mv + sl * (r[0] - mt))); };
    const ex = fit(1), ey = fit(2); const rms = Math.sqrt(ex.reduce((a, v, i) => a + v * v + ey[i] * ey[i], 0) / ex.length);
    let jerk = 0; for (let i = 1; i < s.length - 1; i++) { const u = (s[i][0] - s[i-1][0]) / Math.max(1e-6, s[i+1][0] - s[i-1][0]); jerk = Math.max(jerk, Math.hypot(s[i][1] - (s[i-1][1] + (s[i+1][1] - s[i-1][1]) * u), s[i][2] - (s[i-1][2] + (s[i+1][2] - s[i-1][2]) * u))); }
    return [Math.hypot(s[s.length-1][1] - s[0][1], s[s.length-1][2] - s[0][2]), rms, jerk]; };
  const out = [];
  for (const dir of ['right', 'left', 'right', 'left', 'down', 'up', 'down', 'up', 'right', 'left']) {
    await ev(A, 'ue = {}; ue[Q.' + dir + '.code] = true; 1'); await A.waitForTimeout(250);
    const rec = (p, sel) => p.evaluate((sel) => new Promise(r => { const out = []; let n = 0; const go = (t) => { const g = window.__g; const a = sel ? g.N.find(x => x.nid === sel) : g.p; if (!sel) { const o = Math.hypot(g.f.off.x, g.f.off.y); window.__offMax = Math.max(window.__offMax || 0, o); if (o > (window.__lo || 0) + 1) (window.__ev = window.__ev || []).push([Math.round(o*10)/10, g.ue ? 1 : 0, Math.round(Math.hypot(g.p.vx, g.p.vy))]); window.__lo = o; } const F = g.f, L = F.snaps[F.snaps.length-1]; out.push([t, a ? a.x : NaN, a ? a.y : NaN, L ? L.ts - (F.rt != null ? F.rt : (performance.now() - (F.clockOff||0) - (F.delay||100))) : 0, F.snaps.length]); ++n < 100 ? requestAnimationFrame(go) : r(out); }; requestAnimationFrame(go); }), sel);
    const [ra, rb] = await Promise.all([rec(A, 0), rec(B, nid)]);
    await ev(A, 'ue = {}; 1'); await A.waitForTimeout(500);
    const sa = stat(ra), sb = stat(rb); if (process.argv[3]) { const sv = await ev(B, 'JSON.stringify(f.snaps.slice(-25).map(S => { const e = S.tk.find(x => x[0] === ' + nid + '); return [S.ts, e ? e[1] : null, e ? e[2] : null]; }))'); const a = JSON.parse(sv); const v = []; for (let i = 1; i < a.length; i++) v.push(Math.round(Math.hypot(a[i][1]-a[i-1][1], a[i][2]-a[i-1][2]) / ((a[i][0]-a[i-1][0])/1000)) + '@' + Math.round(a[i][0]-a[i-1][0])); console.log('  vitesses entre snapshots (px/s@ms):', v.join(' ')); } if (process.argv[3]) { const s = rb.slice(30); for (let i = 1; i < s.length - 1; i++) { const u = (s[i][0] - s[i-1][0]) / (s[i+1][0] - s[i-1][0]); const e = Math.hypot(s[i][1] - (s[i-1][1] + (s[i+1][1] - s[i-1][1]) * u), s[i][2] - (s[i-1][2] + (s[i+1][2] - s[i-1][2]) * u)); if (e > 2) console.log('  saut', e.toFixed(1), 'px  avance du dernier snapshot', s[i][3].toFixed(0), 'ms (avant', s[i-1][3].toFixed(0), ')  dt image', (s[i][0]-s[i-1][0]).toFixed(0), (s[i+1][0]-s[i][0]).toFixed(0)); } }
    if (sa[0] > 150 && sb[0] > 150 && sa[1] < 4) out.push([sa, sb]);
  }
  const med = (a) => { a = a.slice().sort((x, y) => x - y); return a.length ? a[Math.floor(a.length / 2)] : NaN; };
  console.log((process.argv[2] || '') + ' segments valides', out.length,
    '| toi : écart', med(out.map(o => o[0][1])).toFixed(2), 'px, à-coup', med(out.map(o => o[0][2])).toFixed(2),
    '| vu par l\'autre : écart', med(out.map(o => o[1][1])).toFixed(2), 'px, à-coup', med(out.map(o => o[1][2])).toFixed(2), '| recalage max toi', await ev(A, '(window.__offMax||0).toFixed(1)'), '| délai', await ev(B, 'Math.round(f.delay)'), 'ping', await ev(A, 'Math.round(f.ping||f.rtt||0)'));
  await b.close();
})();
