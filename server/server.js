// Orbit.io - serveur de jeu pour VPS (Node.js)
//  - sert le jeu (public/index.html)
//  - relaie les rooms WebSocket (parties privées : un joueur héberge)
//  - Battle Royale classé : file d'attente, un "hôte serveur" (Chromium sans écran) par partie,
//    résultats signés par le serveur et enregistrés dans Supabase (PR).
//
// Variables d'environnement (fichier /opt/orbit/.env) :
//   SB_URL=https://xxxx.supabase.co        SB_SECRET=sb_secret_...  (clé secrète, JAMAIS dans le jeu)
//   MIN_PLAYERS=2   QUEUE_WAIT=20   PORT=3000
//   STATS_PASS=un-mot-de-passe   (active la page /stats ; sans lui, /stats n'existe pas)

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { WebSocketServer } = require('ws');

// ---------- config ----------
try { for (const l of fs.readFileSync(path.join(__dirname, '.env'), 'utf8').split('\n')) { const m = l.match(/^\s*([A-Z_]+)\s*=\s*(.*)\s*$/); if (m && !process.env[m[1]]) process.env[m[1]] = m[2].replace(/^["']|["']$/g, ''); } } catch (e) {}
const PORT = +process.env.PORT || 3000;
const HOST = process.env.HOST || '127.0.0.1';
const SB_URL = (process.env.SB_URL || '').replace(/\/+$/, '');
const SB_SECRET = process.env.SB_SECRET || '';
const MIN_PLAYERS = Math.max(1, +process.env.MIN_PLAYERS || 2);
const QUEUE_WAIT = (+process.env.QUEUE_WAIT || 20) * 1000;      // attente max si on n'est pas assez
const QUEUE_FILL = (+process.env.QUEUE_FILL || 2) * 1000;       // dès qu'il y a assez de joueurs : petite fenêtre pour en accueillir d'autres, puis lancement
const MAX_PLAYERS = 12;
const ARENA_MAX = Math.max(2, +process.env.ARENA_MAX || 12);
const HOST_KEY = crypto.randomBytes(24).toString('hex');   // seul l'hôte serveur la connaît
const PUBLIC = path.join(__dirname, 'public');
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png', '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.txt': 'text/plain; charset=utf-8', '.xml': 'application/xml; charset=utf-8', '.json': 'application/json', '.webmanifest': 'application/manifest+json' };
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

// ---------- fichiers statiques ----------
const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  if (url.pathname === '/health') { res.writeHead(200, { 'Content-Type': 'text/plain' }); res.end('ok'); return; }
  if (url.pathname === '/status') { res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(JSON.stringify({ arenas: [...arenas].map(([c, a]) => ({ c, joined: a.joined, closed: a.closed, present: arenaCount(c), now: rooms.get(c) ? rooms.get(c).sessions.size - 1 : 0 })), queues: Object.fromEntries(Object.entries(queues).map(([k, q]) => [k, q.length])), matches: matches.size, ranked: !!(SB_URL && SB_SECRET) })); return; }
  if (url.pathname === '/stats') { statsPage(req, res); return; }
  // adresses courtes : /cgv -> cgv.html
  let rel = url.pathname === '/' ? 'index.html' : url.pathname;
  if (!path.extname(rel)) rel = rel.replace(/\/+$/, '') + '.html';
  let file = path.normalize(path.join(PUBLIC, rel));
  if (!file.startsWith(PUBLIC)) { res.writeHead(403); res.end(); return; }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); res.end('Not found'); return; }
    const ext = path.extname(file), img = /^\.(png|jpe?g|webp|ico|svg)$/.test(ext);
    res.writeHead(200, { 'Content-Type': TYPES[ext] || 'application/octet-stream', 'Cache-Control': img ? 'public, max-age=604800' : 'no-cache' });
    res.end(data);
  });
});

// ---------- Supabase ----------
async function sbUser(token) {
  if (!SB_URL || !SB_SECRET) return null;
  try {
    const r = await fetch(SB_URL + '/auth/v1/user', { headers: { apikey: SB_SECRET, Authorization: 'Bearer ' + token } });
    if (!r.ok) return null;
    const u = await r.json();
    let p = await fetch(SB_URL + '/rest/v1/profiles?select=username,pr,banned_until,ban_reason&id=eq.' + u.id, { headers: { apikey: SB_SECRET } });
    if (!p.ok) p = await fetch(SB_URL + '/rest/v1/profiles?select=username,pr&id=eq.' + u.id, { headers: { apikey: SB_SECRET } });   // colonnes de ban pas encore créées
    const rows = p.ok ? await p.json() : [], r0 = rows[0] || {};
    return { id: u.id, username: r0.username || 'Joueur', pr: r0.pr || 0, ban: banOf(r0) };
  } catch (e) { log('sbUser', e.message); return null; }
}
// ban en cours ? -> { perm, until, reason } ou null
function banOf(row) {
  const t = row && row.banned_until; if (!t) return null;
  const perm = /^infinity$/i.test(String(t)), until = perm ? 0 : Date.parse(t);
  if (!perm && !(until > Date.now())) return null;
  return { perm, until, reason: row.ban_reason || '' };
}
function banMsg(b) {
  const end = b.perm ? 'définitivement' : 'jusqu\'au ' + new Date(b.until).toLocaleString('fr-FR', { timeZone: 'Europe/Paris', dateStyle: 'long', timeStyle: 'short' });
  return 'Ton compte est suspendu ' + end + '.' + (b.reason ? ' Raison : ' + b.reason + '.' : '');
}
async function sbRecord(userId, mode, placement, kills) {
  if (!SB_URL || !SB_SECRET) return null;
  try {
    const r = await fetch(SB_URL + '/rest/v1/rpc/record_ranked_result', {
      method: 'POST', headers: { apikey: SB_SECRET, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_user: userId, p_mode: mode, p_placement: placement, p_kills: kills })
    });
    const j = await r.json();
    if (!r.ok) { log('record error', JSON.stringify(j)); return null; }
    return Array.isArray(j) ? j[0] : j;
  } catch (e) { log('sbRecord', e.message); return null; }
}

// ---------- rooms (relais) ----------
const rooms = new Map(); // code -> { sessions: Map(id -> {ws,name,user}), hostId, nextId, match }
function sys(ws, obj) { if (ws && ws.readyState === 1) ws.send('!|' + JSON.stringify(obj)); }
const TEST_LAG = +process.env.TEST_LAG || 0, TEST_JIT = +process.env.TEST_JIT || 0;   // test uniquement : simule du ping (0 en production)
function send(ws, data) { if (!ws || ws.readyState !== 1) return; if (!TEST_LAG) { ws.send(data); return; } const at = Math.max(ws._lagAt || 0, Date.now() + TEST_LAG + Math.random() * TEST_JIT); ws._lagAt = at; setTimeout(() => { if (ws.readyState === 1) ws.send(data); }, at - Date.now()); }

const wss = new WebSocketServer({ noServer: true, maxPayload: 64 * 1024, perMessageDeflate: false });
server.on('upgrade', (req, sock, head) => {
  const url = new URL(req.url, 'http://x');
  if (url.pathname !== '/ws' && url.pathname !== '/mm' && url.pathname !== '/social') { sock.destroy(); return; }
  wss.handleUpgrade(req, sock, head, ws => url.pathname === '/social' ? onSocial(ws, url) : url.pathname === '/mm' ? onQueue(ws, url) : url.searchParams.get('arena') ? onArena(ws, url) : onRoom(ws, url));
});

function onRoom(ws, url, viaArena) {
  const code = (url.searchParams.get('room') || 'PUBLIC').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 12) || 'PUBLIC';
  const name = (url.searchParams.get('name') || 'Joueur').slice(0, 16);
  const isServerHost = url.searchParams.get('key') === HOST_KEY;
  const ticket = url.searchParams.get('ticket') || '';
  let room = rooms.get(code);
  const match = matches.get(code);
  if (match && !isServerHost && !match.tickets.has(ticket)) { ws.close(4003, 'ticket'); return; }
  const arena = arenas.get(code);
  if (arena && !isServerHost && !viaArena) { ws.close(4003, 'arene'); return; }
  if (!room) { room = { sessions: new Map(), hostId: null, nextId: 1, match: !!match }; rooms.set(code, room); if (!match && !arena) STATS.rooms++; }
  if (room.sessions.size >= MAX_PLAYERS + 1) { ws.close(1013, 'Room pleine'); return; }

  const id = String(room.nextId++);
  const user = match && !isServerHost ? match.tickets.get(ticket) : null;
  room.sessions.set(id, { ws, name: user ? user.username : name, user });
  if (match || arena) { if (isServerHost) room.hostId = id; }
  else if (!room.hostId) room.hostId = id;
  const isHost = room.hostId === id;
  if (arena && isServerHost) { arena.hostReady = true; arena.onHostReady && arena.onHostReady(); }
  sys(ws, { t: 'welcome', id, host: isHost, ranked: !!match, arena: !!arena, room: code, mode: match ? match.mode : null, expected: match ? match.players.length : 0 });
  if (!isHost) { const h = room.sessions.get(room.hostId); if (h) sys(h.ws, { t: 'join', id, name, team: user && user.team != null ? user.team : undefined }); }
  if (isServerHost && match) { match.hostReady = true; match.onHostReady && match.onHostReady(); }

  ws.isAlive = true; ws.on('pong', () => { ws.isAlive = true; });
  ws.on('message', (raw, isBinary) => {
    if (isBinary) return;
    const data = raw.toString(); if (!data) return;
    if (id === room.hostId) {
      if (data.startsWith('#|') && match && isServerHost) { onMatchResult(code, room, JSON.parse(data.slice(2))); return; }
      // "~id|..." = snapshot jetable : si la connexion de ce joueur sature, on le saute (pas de retard qui s'empile)
      const droppable = data.charCodeAt(0) === 126; const raw = droppable ? data.slice(1) : data;
      const bar = raw.indexOf('|'); if (bar < 0) return;
      const to = raw.slice(0, bar), body = raw.slice(bar + 1);
      if (to === '*') { for (const [gid, s] of room.sessions) if (gid !== id) send(s.ws, body); }
      else { const s = room.sessions.get(to); if (!s) return;
        if (droppable && s.ws.bufferedAmount > 48 * 1024) { sys(ws, { t: 'drop', id: to }); return; }
        send(s.ws, body); }
    } else {
      if (data.charCodeAt(0) === 1) { sys(ws, { t: 'pong', c: data.slice(1, 20) }); return; }   // mesure du ping réel
      const h = room.sessions.get(room.hostId);
      if (h) send(h.ws, id + '|' + data);
    }
  });
  ws.on('close', () => {
    if (!room.sessions.has(id)) return;
    // classé : on garde le joueur qui part pour enregistrer son résultat (abandon = défaite)
    if (match && user && !match.done) { match.left = match.left || new Map(); match.left.set(id, user); }
    room.sessions.delete(id);
    if (id === room.hostId) {
      if (arenas.has(code)) { closeArena(code); return; }
      for (const [, s] of room.sessions) { sys(s.ws, { t: 'hostleft' }); try { s.ws.close(1000, 'host left'); } catch (e) {} }
      rooms.delete(code);
    } else {
      const h = room.sessions.get(room.hostId);
      if (h) sys(h.ws, { t: 'leave', id });
      if (room.sessions.size === 0 && !match) rooms.delete(code);
      if (arena) arenaCheckEmpty(code);
    }
  });
}

// ---------- Arène publique : rooms de 12 vrais joueurs, hébergées par le serveur ----------
// Le 1er joueur ouvre une room, les 11 suivants la rejoignent. À 12 entrées la room se ferme
// (plus personne n'y entre, même si quelqu'un part) et le joueur suivant en ouvre une nouvelle.
const arenas = new Map(); // code -> { joined, pending, closed, hostReady, ready(Promise), page, emptySince }
// joueurs présents en ce moment (+ ceux en train d'entrer) : la room se ferme quand 12 joueurs y sont EN MÊME TEMPS
function arenaCount(code) { const a = arenas.get(code), r = rooms.get(code); return (r ? Math.max(0, r.sessions.size - 1) : 0) + (a && a.pending || 0); }
let arenaOpening = null;
async function openArena() {
  const code = 'A' + crypto.randomBytes(5).toString('hex').toUpperCase();
  const a = { joined: 0, closed: false, hostReady: false, page: null, emptyTimer: null };
  a.ready = new Promise(res => { a.onHostReady = res; setTimeout(res, 15000); });
  arenas.set(code, a); STATS.arenas++;
  log('arena open', code);
  try {
    const b = await getBrowser();
    a.page = await hostPage(code, '&mode=arena');
    a.page.on('pageerror', e => log('arena host error', code, e.message)); a.page.on('console', m => { const x = m.text(); if (/rror/.test(x)) log('HOST', x); });

    await a.ready;
    if (!a.hostReady) throw new Error('hôte non connecté');
  } catch (e) { log('arena failed', code, e.message); closeArena(code); return null; }
  return code;
}
function pickArena() {
  for (const [code, a] of arenas) if (!a.closed && a.hostReady && arenaCount(code) < ARENA_MAX) return Promise.resolve(code);
  if (!arenaOpening) arenaOpening = openArena().finally(() => { arenaOpening = null; });
  return arenaOpening;
}
async function onArena(ws, url) {
  let code = null;
  for (let tries = 0; tries < 3 && !code; tries++) {
    const c = await pickArena();
    const a = c && arenas.get(c);
    if (a && !a.closed && arenaCount(c) < ARENA_MAX) { a.joined++; a.pending = (a.pending || 0) + 1; if (arenaCount(c) >= ARENA_MAX) { a.closed = true; log('arena full', c); } code = c; }
  }
  if (!code) { sys(ws, { t: 'error', msg: 'Arène indisponible, réessaie.' }); ws.close(1013, 'arene'); return; }
  const a = arenas.get(code);
  if (ws.readyState !== 1) { if (a) a.pending = Math.max(0, (a.pending || 0) - 1); return; } if (a.emptyTimer) { clearTimeout(a.emptyTimer); a.emptyTimer = null; }
  const u = new URL(url.href); u.searchParams.set('room', code);
  a.pending = Math.max(0, (a.pending || 0) - 1);
  onRoom(ws, u, true);
}
function arenaCheckEmpty(code) {
  const a = arenas.get(code), room = rooms.get(code); if (!a) return;
  const players = room ? room.sessions.size - 1 : 0;
  if (players > 0 || a.emptyTimer) return;
  // room vide : fermée => on la supprime ; encore ouverte => on la garde un peu pour le prochain joueur
  a.emptyTimer = setTimeout(() => { const r = rooms.get(code); if (!r || r.sessions.size <= 1) closeArena(code); else a.emptyTimer = null; }, a.closed ? 1000 : 60000);
}
async function closeArena(code) {
  const a = arenas.get(code); if (!a) return;
  arenas.delete(code);
  const room = rooms.get(code);
  if (room) { for (const [, s] of room.sessions) { try { s.ws.close(1000, 'fin'); } catch (e) {} } rooms.delete(code); }
  if (a.page) { try { await a.page.close(); } catch (e) {} }
  log('arena close', code);
}

// ---------- Battle Royale classé : file d'attente ----------
const MODES = { solo: 1, duo: 2, trio: 3, squad: 4 };
const queues = { solo: [], duo: [], trio: [], squad: [] };
const matches = new Map(); // code -> { mode, players:[{user}], tickets: Map(ticket->user), hostReady, page }

function notifyEntry(e, obj) { sys(e.ws, obj); for (const u of e.users) if (u.id !== e.user.id) ssend(u.id, { t: 'mm', m: obj }); }
function qCount(q) { return q.reduce((n, e) => n + e.users.length, 0); }
async function onQueue(ws, url) {
  const mode = MODES[url.searchParams.get('mode')] ? url.searchParams.get('mode') : 'solo';
  const token = url.searchParams.get('token') || '';
  let user = await sbUser(token);
  if (!user) {
    if (SB_URL && SB_SECRET) { sys(ws, { t: 'error', msg: 'Connecte-toi à ton compte pour jouer en classé.' }); ws.close(4001, 'auth'); return; }
    // mode développement (pas de Supabase configuré) : joueur anonyme, pas de PR
    user = { id: 'dev-' + crypto.randomBytes(4).toString('hex'), username: (url.searchParams.get('name') || 'Joueur').slice(0, 16), pr: 0, dev: true };
  }
  if (user.ban) { log('ban refusé (classé)', user.username); sys(ws, { t: 'error', msg: banMsg(user.ban) }); ws.close(4005, 'ban'); return; }
  ws.isAlive = true; ws.on('pong', () => { ws.isAlive = true; });
  // groupe d'amis : seul le chef lance la recherche, tout le groupe entre dans la même équipe
  let users = [user], party = null;
  const sp = social.get(user.id);
  if (sp && sp.party) {
    party = parties.get(sp.party);
    if (party && party.members.length > 1) {
      if (party.leader !== user.id) { sys(ws, { t: 'error', msg: 'C\'est le chef du groupe qui lance la recherche.' }); ws.close(4005, 'party'); return; }
      if (party.members.length > MODES[mode]) { sys(ws, { t: 'error', msg: 'Ton groupe est trop grand pour ce mode.' }); ws.close(4005, 'party'); return; }
      if (party.members.some(id => !social.has(id) || inGame.has(id))) { sys(ws, { t: 'error', msg: 'Un membre du groupe n\'est pas disponible.' }); ws.close(4005, 'party'); return; }
      users = party.members.map(id => id === user.id ? user : social.get(id).user);
    } else party = null;
  }
  const ids = new Set(users.map(u => u.id));
  for (const qq of Object.values(queues)) for (let i = qq.length - 1; i >= 0; i--) { const e = qq[i]; if (e.users.some(u => ids.has(u.id))) { qq.splice(i, 1); try { e.ws.close(4002, 'doublon'); } catch (er) {} } }
  const q = queues[mode];
  const entry = { ws, user, users, party, since: Date.now() };
  if (party) party.entry = entry;
  q.push(entry);
  log('queue', mode, users.map(u => u.username).join('+'), qCount(q));
  for (const u of users) pushPresence(u.id);
  ws.on('close', () => { const i = q.indexOf(entry); if (i >= 0) { q.splice(i, 1); for (const u of users) if (u.id !== user.id) ssend(u.id, { t: 'mm', m: { t: 'cancel' } }); for (const u of users) pushPresence(u.id); } if (party && party.entry === entry) party.entry = null; queueStatus(mode); });
  queueStatus(mode);
  tryStart(mode);
}
function queueStatus(mode) {
  const q = queues[mode], n = qCount(q);
  for (const e of q) notifyEntry(e, { t: 'queue', n, max: MAX_PLAYERS, min: MIN_PLAYERS, wait: q.minAt ? Math.max(0, Math.ceil((QUEUE_FILL - (Date.now() - q.minAt)) / 1000)) : -1 });
}
setInterval(() => { for (const m of Object.keys(queues)) { queueStatus(m); tryStart(m); } }, 1000);

function tryStart(mode) {
  const q = queues[mode], n = qCount(q);
  if (!q.length) { q.minAt = 0; return; }
  if (n >= MIN_PLAYERS) { if (!q.minAt) q.minAt = Date.now(); } else q.minAt = 0;
  if (n >= MAX_PLAYERS || (q.minAt && Date.now() - q.minAt >= QUEUE_FILL)) {
    q.minAt = 0;
    const group = []; let total = 0;
    for (let i = 0; i < q.length;) { const e = q[i]; if (total + e.users.length <= MAX_PLAYERS) { group.push(e); total += e.users.length; q.splice(i, 1); } else i++; }
    if (group.length) startMatch(mode, group);
  }
}

let browser = null;
// pages hôtes préchauffées : le jeu est déjà chargé, la partie démarre sans attendre le chargement (~instantané)
const warm = []; let warming = false;
async function fillWarm() {
  if (warming) return; warming = true;
  try { while (warm.length < 2) { const b = await getBrowser(); const p = await b.newPage(); p.on('pageerror', e => log('host error', e.message));
      await p.goto(`http://127.0.0.1:${PORT}/?serverhost=WARM&warm=1&key=${HOST_KEY}`); await p.waitForFunction(() => !!window.__oxGo, null, { timeout: 15000 }); warm.push(p); } }
  catch (e) { log('warm', e.message); } finally { warming = false; }
}
async function hostPage(code, query) {
  let p = warm.shift();
  if (p && !p.isClosed()) { setTimeout(fillWarm, 50); await p.evaluate(c => window.__oxGo(c), code); return p; }
  const b = await getBrowser(); p = await b.newPage(); await p.goto(`http://127.0.0.1:${PORT}/?serverhost=${code}&key=${HOST_KEY}${query}`); setTimeout(fillWarm, 50); return p;
}
async function getBrowser() {
  if (browser && browser.isConnected()) return browser;
  const { chromium } = require('playwright');
  const opts = { handleSIGTERM: false, handleSIGINT: false, handleSIGHUP: false, args: ['--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage', '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--disable-backgrounding-occluded-windows', '--autoplay-policy=no-user-gesture-required'] };
  if (process.env.CHROMIUM_PATH) opts.executablePath = process.env.CHROMIUM_PATH;
  browser = await chromium.launch(opts);
  return browser;
}

async function startMatch(mode, group) {
  const code = 'R' + crypto.randomBytes(5).toString('hex').toUpperCase();
  // équipes : les groupes d'amis restent ensemble, les joueurs seuls complètent
  const ts = MODES[mode], teams = [];
  const order = group.slice().sort((a, b) => b.users.length - a.users.length);
  for (const e of order) { let t = teams.findIndex(x => ts - x.length >= e.users.length); if (t < 0) { teams.push([]); t = teams.length - 1; } for (const u of e.users) teams[t].push(u); e.team = t; }
  const players = []; for (const e of group) for (const u of e.users) players.push(Object.assign({}, u, { team: e.team }));
  const match = { mode, players, tickets: new Map(), hostReady: false, page: null, done: false, started: Date.now() };
  matches.set(code, match); STATS.br[mode] = (STATS.br[mode] || 0) + 1;
  for (const u of players) inGame.set(u.id, code);
  for (const e of group) if (e.party) e.party.entry = null;
  log('match', code, mode, group.map(e => e.users.map(u => u.username).join('+')).join(', '));
  for (const e of group) notifyEntry(e, { t: 'found', n: players.length });
  for (const u of players) pushPresence(u.id);
  try {
    const ready = new Promise(res => { match.onHostReady = res; setTimeout(res, 15000); });   // créé AVANT : la page préchauffée se connecte tout de suite
    const page = await hostPage(code, `&mode=${mode}&n=${players.length}`);
    match.page = page;
    page.on('pageerror', e => log('host error', code, e.message));
    if (match.hostReady) match.onHostReady();

    await ready;
    if (!match.hostReady) throw new Error('hôte non connecté');
  } catch (e) {
    log('start failed', code, e.message);
    for (const ent of group) { notifyEntry(ent, { t: 'error', msg: 'Impossible de lancer la partie, réessaie.' }); try { ent.ws.close(); } catch (er) {} }
    endMatch(code); return;
  }
  for (const e of group) {
    for (const u of e.users) {
      const pl = players.find(x => x.id === u.id);
      const ticket = crypto.randomBytes(16).toString('hex');
      match.tickets.set(ticket, pl);
      const msg = { t: 'match', room: code, ticket, mode };
      if (u.id === e.user.id) sys(e.ws, msg); else ssend(u.id, { t: 'mm', m: msg });
    }
    setTimeout(() => { try { e.ws.close(1000, 'match'); } catch (er) {} }, 2000);
  }
  // sécurité : une partie ne dure jamais plus de 15 min
  setTimeout(() => endMatch(code), 15 * 60 * 1000);
}

// ---------- Amis : présence, invitations et groupes (duo / trio / squad) ----------
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const social = new Map();   // userId -> { ws:Set, user, friends:Set, party:null|partyId }
const parties = new Map();  // partyId -> { id, leader, members:[userId], mode, invites:Map(userId->time), entry }
const inGame = new Map();   // userId -> code de la partie classée en cours
async function sbFriends(uid) {
  if (!SB_URL || !SB_SECRET || !UUID_RE.test(uid)) return new Set();
  try {
    const r = await fetch(SB_URL + '/rest/v1/friendships?select=requester,addressee&status=eq.accepted&or=(requester.eq.' + uid + ',addressee.eq.' + uid + ')', { headers: { apikey: SB_SECRET } });
    if (!r.ok) { log('friends error', r.status); return new Set(); }
    const rows = await r.json();
    return new Set(rows.map(x => x.requester === uid ? x.addressee : x.requester));
  } catch (e) { log('sbFriends', e.message); return new Set(); }
}
function ssend(uid, obj) { const s = social.get(uid); if (s) for (const w of s.ws) sys(w, obj); }
function inQueue(uid) { for (const q of Object.values(queues)) for (const e of q) if (e.users.some(u => u.id === uid)) return true; return false; }
function ustatus(uid) { if (inGame.has(uid)) return 'game'; if (inQueue(uid)) return 'queue'; return social.has(uid) ? 'online' : 'offline'; }
function pushPresence(uid) { const st = ustatus(uid); for (const [, s] of social) if (s.friends.has(uid)) for (const w of s.ws) sys(w, { t: 'presence', id: uid, st }); }
function partyState(p) {
  const msg = p ? { t: 'party', id: p.id, leader: p.leader, mode: p.mode, members: p.members.map(id => { const s = social.get(id); return { id, username: s ? s.user.username : 'Joueur', pr: s ? s.user.pr : 0 }; }) } : { t: 'party', id: null };
  return msg;
}
function partyBroadcast(p) { const m = partyState(p); for (const id of p.members) ssend(id, m); }
function cancelPartyQueue(p, why) {
  const e = p && p.entry; if (!e) return; p.entry = null;
  sys(e.ws, { t: 'error', msg: why }); try { e.ws.close(4004, 'party'); } catch (er) {}
}
function leaveParty(uid, quiet) {
  const s = social.get(uid); const p = s && s.party ? parties.get(s.party) : null; if (s) s.party = null;
  if (!p) return;
  p.members = p.members.filter(id => id !== uid);
  if (p.entry) cancelPartyQueue(p, 'Un membre a quitté le groupe : recherche annulée.');
  if (!quiet) ssend(uid, { t: 'party', id: null });
  if (p.members.length <= 1) { for (const id of p.members) { const ms = social.get(id); if (ms) ms.party = null; ssend(id, { t: 'party', id: null, msg: 'Le groupe a été dissous.' }); } parties.delete(p.id); return; }
  if (p.leader === uid) p.leader = p.members[0];
  partyBroadcast(p);
}
async function onSocial(ws, url) {
  const user = await sbUser(url.searchParams.get('token') || '');
  if (!user) { sys(ws, { t: 'error', msg: 'auth' }); ws.close(4001, 'auth'); return; }
  if (user.ban) { sys(ws, { t: 'banned', msg: banMsg(user.ban), perm: user.ban.perm, until: user.ban.until, reason: user.ban.reason }); ws.close(4005, 'ban'); return; }
  ws.isAlive = true; ws.on('pong', () => { ws.isAlive = true; });
  let s = social.get(user.id);
  if (!s) { s = { ws: new Set(), user, friends: new Set(), party: null }; social.set(user.id, s); }
  s.user = user; s.ws.add(ws);
  s.friends = await sbFriends(user.id);
  const pres = {}; for (const f of s.friends) pres[f] = ustatus(f);
  sys(ws, { t: 'hello', me: user.id, presences: pres });
  if (s.party) sys(ws, partyState(parties.get(s.party)));
  pushPresence(user.id);
  ws.on('message', async raw => {
    let m; try { m = JSON.parse(raw.toString()); } catch (e) { return; }
    if (!m || typeof m.t !== 'string') return;
    if (m.t === 'refresh') {
      s.friends = await sbFriends(user.id); const p2 = {}; for (const f of s.friends) p2[f] = ustatus(f);
      sys(ws, { t: 'presences', presences: p2 });
      // prévient aussi les amis (nouvelle amitié acceptée)
      for (const f of s.friends) { const fs2 = social.get(f); if (fs2 && !fs2.friends.has(user.id)) { fs2.friends = await sbFriends(f); ssend(f, { t: 'friends-changed' }); } }
      pushPresence(user.id); return;
    }
    if (m.t === 'invite') {
      const to = String(m.to || ''); const mode = MODES[m.mode] && m.mode !== 'solo' ? m.mode : 'duo';
      if (!s.friends.has(to)) { s.friends = await sbFriends(user.id); if (!s.friends.has(to)) { sys(ws, { t: 'toast', msg: 'Ce joueur n\'est pas dans tes amis.' }); return; } }
      if (!social.has(to)) { sys(ws, { t: 'toast', msg: 'Ton ami n\'est pas connecté.' }); return; }
      if (inGame.has(to)) { sys(ws, { t: 'toast', msg: 'Ton ami est en pleine partie.' }); return; }
      let p = s.party ? parties.get(s.party) : null;
      if (p && p.leader !== user.id) { sys(ws, { t: 'toast', msg: 'Seul le chef du groupe peut inviter.' }); return; }
      if (p && p.members.includes(to)) { sys(ws, { t: 'toast', msg: 'Il est déjà dans ton groupe.' }); return; }
      if (!p) { p = { id: crypto.randomBytes(6).toString('hex'), leader: user.id, members: [user.id], mode, invites: new Map(), entry: null }; parties.set(p.id, p); s.party = p.id; }
      if (p.members.length >= 4) { sys(ws, { t: 'toast', msg: 'Ton groupe est complet.' }); return; }
      if (MODES[mode] > MODES[p.mode]) p.mode = mode;
      if (p.members.length + 1 > MODES[p.mode]) p.mode = Object.keys(MODES).find(k => MODES[k] >= p.members.length + 1);
      p.invites.set(to, Date.now());
      ssend(to, { t: 'invited', party: p.id, from: { id: user.id, username: user.username }, mode: p.mode });
      sys(ws, { t: 'toast', msg: 'Invitation envoyée !' });
      partyBroadcast(p); return;
    }
    if (m.t === 'join') {
      const p = parties.get(String(m.party || ''));
      if (!p || !p.invites.has(user.id) || Date.now() - p.invites.get(user.id) > 5 * 60 * 1000) { sys(ws, { t: 'toast', msg: 'Cette invitation n\'est plus valable.' }); return; }
      if (p.members.length >= 4) { sys(ws, { t: 'toast', msg: 'Le groupe est déjà complet.' }); return; }
      if (p.entry) { sys(ws, { t: 'toast', msg: 'Le groupe est déjà en recherche, réessaie dans un instant.' }); return; }
      if (s.party && s.party !== p.id) leaveParty(user.id, true);
      p.invites.delete(user.id); p.members.push(user.id); s.party = p.id;
      if (p.members.length > MODES[p.mode]) p.mode = Object.keys(MODES).find(k => MODES[k] >= p.members.length);
      partyBroadcast(p); return;
    }
    if (m.t === 'decline') {
      const p = parties.get(String(m.party || '')); if (!p) return;
      p.invites.delete(user.id); ssend(p.leader, { t: 'toast', msg: user.username + ' a refusé ton invitation.' }); return;
    }
    if (m.t === 'leave') { leaveParty(user.id); return; }
    if (m.t === 'mode') {
      const p = s.party ? parties.get(s.party) : null; if (!p || p.leader !== user.id || !MODES[m.mode] || m.mode === 'solo') return;
      if (MODES[m.mode] < p.members.length) { sys(ws, { t: 'toast', msg: 'Ce mode est trop petit pour ton groupe.' }); partyBroadcast(p); return; }
      if (p.entry) return; p.mode = m.mode; partyBroadcast(p); return;
    }
  });
  ws.on('close', () => {
    const cur = social.get(user.id); if (!cur) return;
    cur.ws.delete(ws);
    if (cur.ws.size === 0) setTimeout(() => { const c2 = social.get(user.id); if (c2 && c2.ws.size === 0) { leaveParty(user.id, true); social.delete(user.id); pushPresence(user.id); } }, 8000);
  });
}

async function onMatchResult(code, room, res) {
  const match = matches.get(code);
  if (!match || match.done) return;
  match.done = true;
  log('result', code, JSON.stringify(res.players));
  for (const p of res.players || []) {
    const left = match.left && match.left.get(String(p.gid));
    const s = room.sessions.get(String(p.gid)) || (left ? { user: left, ws: null } : null);
    if (!s || !s.user) continue;
    // abandon en cours de partie : compté comme une dernière place, sans bonus d'éliminations
    const quit = !!p.quit;
    let rec = null;
    if (!s.user.dev) rec = await sbRecord(s.user.id, match.mode, quit ? MAX_PLAYERS : Math.max(1, p.placement | 0), quit ? 0 : Math.max(0, p.kills | 0));
    if (quit || !s.ws) { log('abandon', s.user.username, quit ? 'pendant la partie' : 'après élimination', rec ? rec.pr_delta : ''); continue; }
    sys(s.ws, { t: 'ranked', placement: p.placement, kills: p.kills, total: res.total, dev: !!s.user.dev, pr_before: rec && rec.pr_before, pr_delta: rec && rec.pr_delta, pr_after: rec && rec.pr_after, rank: rec && rec.rank });
  }
  setTimeout(() => endMatch(code), 20000);
}
async function endMatch(code) {
  const match = matches.get(code); if (!match) return;
  matches.delete(code);
  for (const u of match.players) if (inGame.get(u.id) === code) { inGame.delete(u.id); pushPresence(u.id); }
  const room = rooms.get(code);
  if (room) { for (const [, s] of room.sessions) { try { s.ws.close(1000, 'fin'); } catch (e) {} } rooms.delete(code); }
  if (match.page) { try { await match.page.close(); } catch (e) {} }
  log('end', code);
}

setInterval(() => {
  for (const ws of wss.clients) { if (!ws.isAlive) { ws.terminate(); continue; } ws.isAlive = false; try { ws.ping(); } catch (e) {} }
}, 15000);

// ---------- page /stats (protégée par STATS_PASS) ----------
const STATS = { since: Date.now(), rooms: 0, arenas: 0, br: {}, peak: 0, peakAt: 0 };
function liveCounts() {
  let arena = 0, ranked = 0, priv = 0, privRooms = 0;
  for (const [code, r] of rooms) {
    if (arenas.has(code)) arena += Math.max(0, r.sessions.size - 1);
    else if (matches.has(code)) ranked += Math.max(0, r.sessions.size - 1);
    else if (r.sessions.size) { priv += r.sessions.size; privRooms++; }
  }
  let queued = 0; const q = {};
  for (const [m, list] of Object.entries(queues)) { const n = list.reduce((a, e) => a + (e.users ? e.users.length : 1), 0); q[m] = n; queued += n; }
  const playing = arena + ranked + priv;
  return { arena, ranked, priv, privRooms, queued, q, playing, online: social.size, arenas: arenas.size, matches: matches.size };
}
setInterval(() => { const n = liveCounts(); const tot = n.playing + n.queued; if (tot > STATS.peak) { STATS.peak = tot; STATS.peakAt = Date.now(); } }, 10000);
let sbStats = null, sbStatsAt = 0;
async function sbCount(table, filter) {
  const r = await fetch(SB_URL + '/rest/v1/' + table + '?select=*' + (filter || ''), { method: 'HEAD', headers: { apikey: SB_SECRET, Prefer: 'count=exact', Range: '0-0' } });
  const m = (r.headers.get('content-range') || '').match(/\/(\d+)/);
  return m ? +m[1] : null;
}
async function supabaseStats() {
  if (!SB_URL || !SB_SECRET) return null;
  if (sbStats && Date.now() - sbStatsAt < 60000) return sbStats;
  try {
    const days = [];
    const d0 = new Date(); d0.setUTCHours(0, 0, 0, 0);
    for (let i = 0; i < 7; i++) {
      const a = new Date(d0.getTime() - i * 864e5), b = new Date(a.getTime() + 864e5);
      days.push({ day: a.toISOString().slice(0, 10), n: await sbCount('matches', '&created_at=gte.' + a.toISOString() + '&created_at=lt.' + b.toISOString()) });
    }
    sbStats = { accounts: await sbCount('profiles'), ranked: await sbCount('matches'), days }; sbStatsAt = Date.now();
  } catch (e) { log('stats', e.message); }
  return sbStats;
}
function statsAuthOk(req) {
  const pass = process.env.STATS_PASS || '';
  const m = (req.headers.authorization || '').match(/^Basic (.+)$/);
  if (!pass || !m) return false;
  const given = Buffer.from(m[1], 'base64').toString().split(':').slice(1).join(':');
  const a = crypto.createHash('sha256').update(given).digest(), b = crypto.createHash('sha256').update(pass).digest();
  return crypto.timingSafeEqual(a, b);
}
async function statsPage(req, res) {
  if (!process.env.STATS_PASS) { res.writeHead(404); res.end('Not found'); return; }
  if (!statsAuthOk(req)) { res.writeHead(401, { 'WWW-Authenticate': 'Basic realm="Oryxo stats", charset="UTF-8"', 'Content-Type': 'text/plain; charset=utf-8' }); res.end('Mot de passe requis'); return; }
  const n = liveCounts(), sb = await supabaseStats();
  const t = ms => new Date(ms).toLocaleString('fr-FR', { timeZone: 'Europe/Paris' });
  const card = (v, l) => `<div class="c"><b>${v}</b><span>${l}</span></div>`;
  const br = Object.keys(MODES).map(m => `${m} : ${STATS.br[m] || 0}`).join(' · ');
  const days = sb && sb.days ? sb.days.map(d => `<tr><td>${d.day}</td><td>${d.n == null ? '?' : d.n}</td></tr>`).join('') : '';
  const html = `<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><meta http-equiv="refresh" content="15"><title>Stats – Oryxo.eu</title>
<style>body{margin:0;background:#0b1534;color:#d9e4ff;font:15px/1.5 "Trebuchet MS",system-ui,sans-serif;padding:16px}main{max-width:900px;margin:0 auto}h1{color:#fff;margin:8px 0}h2{color:#ffcf4e;font-size:17px;margin:22px 0 8px}.g{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:10px}.c{background:#101c47;border:2px solid rgba(128,175,255,.22);border-radius:14px;padding:12px}.c b{display:block;font-size:28px;color:#fff;font-variant-numeric:tabular-nums}.c span{color:#9fb0d8;font-size:13px}table{border-collapse:collapse;min-width:260px}td,th{border:1px solid rgba(128,175,255,.22);padding:6px 12px;text-align:left}td:last-child{text-align:right;font-variant-numeric:tabular-nums}.m{color:#9fb0d8;font-size:13px}</style></head><body><main>
<h1>Oryxo.eu · stats</h1><p class="m">Mis à jour toutes les 15 s · ${t(Date.now())}</p>
<h2>En ce moment</h2><div class="g">${card(n.playing + n.queued, 'joueurs en ligne')}${card(n.online, 'connectés à leur compte')}${card(n.arena, 'en arène (' + n.arenas + ' arène' + (n.arenas > 1 ? 's' : '') + ')')}${card(n.ranked, 'en BR classé (' + n.matches + ' partie' + (n.matches > 1 ? 's' : '') + ')')}${card(n.priv, 'en room privée (' + n.privRooms + ')')}${card(n.queued, 'en file d\'attente')}</div>
<p class="m">File d'attente : ${Object.entries(n.q).map(([m, v]) => m + ' ' + v).join(' · ')}</p>
<h2>Depuis le dernier redémarrage (${t(STATS.since)})</h2><div class="g">${card(Object.values(STATS.br).reduce((a, b) => a + b, 0), 'parties BR classé')}${card(STATS.arenas, 'arènes ouvertes')}${card(STATS.rooms, 'rooms privées créées')}${card(STATS.peak, 'pic de joueurs' + (STATS.peakAt ? ' (' + t(STATS.peakAt) + ')' : ''))}</div>
<p class="m">BR par mode : ${br}</p>
<h2>Comptes et parties (Supabase)</h2>${sb ? `<div class="g">${card(sb.accounts == null ? '?' : sb.accounts, 'comptes')}${card(sb.ranked == null ? '?' : sb.ranked, 'participations au classé (total)')}</div><p class="m">Une participation = un joueur dans une partie classée.</p><table><tr><th>Jour (UTC)</th><th>Participations</th></tr>${days}</table>` : '<p class="m">Supabase non configuré.</p>'}
</main></body></html>`;
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', 'X-Robots-Tag': 'noindex' });
  res.end(html);
}

// arrêt propre (systemctl restart / deploy) : on ferme Chromium puis on quitte, 2 s maximum.
// Avant, le serveur restait bloqué en « deactivating » jusqu'à ce que systemd le tue.
let stopping = false;
for (const sig of ['SIGTERM', 'SIGINT', 'SIGHUP']) process.on(sig, () => {
  if (stopping) return; stopping = true;
  log('arrêt demandé (' + sig + ')');
  setTimeout(() => process.exit(0), 2000).unref();
  try { server.close(); } catch (e) {}
  const b = browser; browser = null;
  Promise.resolve(b && b.close()).catch(() => {}).finally(() => process.exit(0));
});

server.listen(PORT, HOST, () => { setTimeout(fillWarm, 500); }); server.on('listening', () => log(`Orbit.io sur http://${HOST}:${PORT} — classé ${SB_URL && SB_SECRET ? 'ACTIVÉ' : 'en mode dev (pas de Supabase)'}`));
