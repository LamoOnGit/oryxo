// Régularité des balles vues par un joueur (BR à 2 joueurs + bots, jetons tA / tB).
// Pour chaque balle suivie pendant au moins 12 images : écart d'une image par rapport au milieu de ses voisines (à-coup, en px).
const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch();
  const ev = (p, c) => p.evaluate((c) => window.__g.ev(c), c);
  const P = [];
  for (const tok of ['tA', 'tB']) { const q = await (await b.newContext()).newPage({ viewport: { width: 640, height: 400 } }); await q.goto((process.env.BENCH_URL || 'http://127.0.0.1:3364') + '/'); await q.waitForTimeout(1200);
    await q.evaluate(tok => { const ws = new WebSocket(location.origin.replace(/^http/, 'ws') + '/mm?mode=solo&token=' + tok); ws.onmessage = e => { const m = JSON.parse(e.data.slice(2)); if (m.t === 'match') window.__g.ev('Er(location.origin,' + JSON.stringify(m.room) + ',' + JSON.stringify(m.ticket) + ')'); }; }, tok); P.push(q); }
  const [A, B] = P;
  for (let i = 0; i < 40; i++) { await A.waitForTimeout(1000); if (await ev(A, 'f.state') === 'play' && await ev(B, 'f.state') === 'play') break; }
  await A.waitForTimeout(1500);
  // A tire sans arrêt vers la droite
  await ev(A, 'setInterval(() => { ee.x = he / 2 + 300; ee.y = de / 2; ee.down = true; }, 50); 1');
  const rec = (p) => p.evaluate(() => new Promise(r => { const tr = new Map(); let n = 0; const go = (t) => { const F = window.__g.f; if (F.bmap) for (const [id, o] of F.bmap) { if (!tr.has(id)) tr.set(id, []); tr.get(id).push([t, o.x, o.y]); } for (const o of (F.lb || [])) { o.__id = o.__id || Math.random(); const id = 'L' + o.__id; if (!tr.has(id)) tr.set(id, []); tr.get(id).push([t, o.x, o.y]); } ++n < 240 ? requestAnimationFrame(go) : r([...tr.entries()].filter(([, s]) => s.length >= 12)); }; requestAnimationFrame(go); }));
  console.log('etat', await ev(A, 'JSON.stringify([f.state, !!(p&&p.alive), Se.length, (f.lb||[]).length])'), await ev(B, 'JSON.stringify([f.state, Se.length, f.bmap ? f.bmap.size : -1])'));
  const [ra, rb] = await Promise.all([rec(A), rec(B)]);
  const stat = (list, filt) => { const j = []; for (const [id, s] of list) { if (!filt(String(id))) continue; let m = 0; for (let i = 1; i < s.length - 1; i++) { const u = (s[i][0] - s[i-1][0]) / Math.max(1e-6, s[i+1][0] - s[i-1][0]); m = Math.max(m, Math.hypot(s[i][1] - (s[i-1][1] + (s[i+1][1] - s[i-1][1]) * u), s[i][2] - (s[i-1][2] + (s[i+1][2] - s[i-1][2]) * u))); } j.push(m); } j.sort((a, b) => a - b); return j.length ? 'balles ' + j.length + ', à-coup médian ' + j[Math.floor(j.length / 2)].toFixed(2) + ' px, 90% < ' + j[Math.floor(j.length * 0.9)].toFixed(2) + ' px' : 'aucune'; };
  console.log((process.argv[2] || ''), '| tes balles (A) :', stat(ra, id => id[0] === 'L'), '| balles des autres vues par B :', stat(rb, id => id[0] !== 'L'));
  await b.close();
})();
