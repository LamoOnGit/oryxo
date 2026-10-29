// Vérifie que l'hôte et la prédiction du joueur donnent exactement la même position (au 1/100 px).
const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  await p.goto((process.env.BENCH_URL || 'http://127.0.0.1:3364') + '/'); await p.waitForTimeout(1200);
  console.log(await p.evaluate(() => window.__g.ev(`(() => {
    Xe("ffa"); ze.onclick();
    for (const t of N) if (t !== p) t.alive = false;
    const n = xt("R", false); n.remote = true; n.in = { x: 0, y: 0, a: 0, f: 0 }; n.x = 1500; n.y = 300; n.vx = n.vy = 0; n.effects = {}; N.push(n);
    const g = { x: n.x, y: n.y, vx: 0, vy: 0, moveT: 0 };
    n.stepQ = [];
    const out = [];
    for (let i = 1; i <= 40; i++) { n.stepQ.push([1, 0, 0.033, i, null]); Ta(g, 1, 0, 0.033, n, null); }
    let t = 0;
    for (let k = 0; k < 140; k++) { Es(1/60); if (n.ack) { /* rejoue depuis l'ack comme le joueur */ } }
    return JSON.stringify({ hote: [n.x.toFixed(2), n.y.toFixed(2)], joueur: [g.x.toFixed(2), g.y.toFixed(2)], lastSeq: n.lastSeq, reste: n.stepQ.length, ack: n.ack });
  })()`)));
  await b.close();
})();
