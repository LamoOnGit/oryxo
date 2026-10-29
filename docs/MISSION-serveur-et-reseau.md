# Mission : serveur sans Chromium (2) + messages réseau compacts (3)

> Fichier destiné au **Claude Code** de la personne qui reprend cette partie.
> Lis aussi `CLAUDE.md` à la racine (contexte complet du jeu, noms courts de `src/main.js`, déploiement).
> Le propriétaire du jeu est **Malo** (débutant) : tout ce qui lui est destiné s'écrit en **français simple**.

## 0. Règles à respecter

- **Ne jamais toucher au VPS ni à Supabase.** Pas de SSH, pas de `.env`, pas de clé secrète (`SB_SECRET` n'est pas dans ce dépôt et ne doit jamais y entrer). On rend des fichiers ; c'est Malo qui déploie (fonction `deploy` sur son Mac, voir `CLAUDE.md`).
- **Ne pas pousser sur `main`.** Un push sur `main` qui touche `src/` ou `server/` lance le workflow de déploiement. Travailler sur une branche (`git checkout -b serveur-node`) et ouvrir une pull request.
- **Le gameplay ne doit pas changer** : mêmes règles, mêmes dégâts, mêmes vitesses, même carte. Le seul but est la fluidité et la charge du serveur.
- **La prédiction du joueur doit rester identique à l'hôte**, au 1/100 de pixel près (`tools/test/netbench/det.js`). Toute modification de la physique (`Ta`, `Es`) casse le recalage (le joueur « tremble »).
- `src/main.js` est une version **dé-minifiée** : noms courts (`p`, `N`, `Se`, `f`, `Es`, `Ta`…). La table est dans `CLAUDE.md`. Le code récent est lisible et préfixé `ox…`. Garder ce style : commentaires courts, en français.
- Après chaque étape : `python3 build.py` doit passer, puis les tests de la section 5.

## 1. Comment ça marche aujourd'hui

```
Navigateur du joueur  ──WebSocket /ws──►  server/server.js (Node, relais)  ──►  « hôte » de la partie
```

- **Un seul fichier de jeu** (`src/shell.html` + `src/main.js` → `dist/index-oryxo.html`). Le même fichier sert de **client** (joueur) et d'**hôte** (calcule la partie).
- **Rooms privées** : l'hôte est le navigateur du joueur qui crée la room.
- **Arène et Battle Royale classé** : l'hôte est le **serveur**. `server.js` lance **Chromium sans écran (Playwright)** et ouvre `http://127.0.0.1:PORT/?serverhost=<code>&key=<HOST_KEY>&mode=...`. Quelques pages sont **préchauffées** (`?serverhost=WARM&warm=1`, puis `window.__oxGo(code)`). Voir `hostPage`, `fillWarm` et `getBrowser` dans `server.js`.
- Dans la page hôte, `main.js` détecte `serverhost` (cherche `e.get("serverhost")`), met `window.SERVER_HOST = true`, coupe le son et le dessin, puis :
  - `setInterval(… Es(dt) …, 1000/60)` : calcul de la partie (`Es` = mise à jour du monde) ;
  - `f.sendTimer = setInterval(Mo, 1000/Ln)` avec `Ln = 30` : envoi des snapshots (`Mo`) ;
  - une ligne `perf images/s=… calcul moy=… max=… pause max=… joueurs=… balles=…` toutes les 10 s dans la console (récupérée par `server.js` → `perfLine`, journal et page `/stats`).
- **Format des messages** (texte, JSON), relayés par `server.js` (`onRoom`) :
  - serveur → client : `!|{json}` (messages système : `welcome`, `join`, `leave`, `pong`, `drop`, `hostleft`…) ;
  - hôte → un joueur : `<id>|{json}` ; hôte → tous : `*|{json}` ; snapshot « jetable » : `~<id>|{json}` (sauté si la connexion du joueur sature) ;
  - hôte → serveur : `#|{"t":"res",…}` (résultat du BR classé, enregistré par le serveur dans Supabase : `onMatchResult`) ;
  - joueur → hôte : `{json}` (le serveur préfixe `<id>|`) ; `\x01<horodatage>` = mesure du ping.
- **Snapshot** (`Mo`, `t:"s"`) : `ts` (heure du calcul `f.simT`), `tk` (tanks : `[nid, x, y, angle, hp, vivant, …]` + infos d'apparence quand elles changent), `b` (balles), `g` (données privées du joueur destinataire : vitesse, inventaire, `lastSeq`, portefeuille BR, `ack`, réserve), `c` (clones), zone BR `z`, `pf` (perf de l'hôte, 1×/s).
- **Côté joueur** (`_l`, `Ma`) : prédiction de son propre tank (`Ta` rejoué depuis `ack`/`lastSeq`), interpolation des autres (`f.snaps`, délai `f.delay`, horloge lissée `f.rt`).
- **Côté hôte**, entrées des joueurs (`t:"i"`) : file `n.stepQ` jouée à vitesse régulière avec une réserve adaptative (`n.inBuf`). Voir la section « Fluidité en ligne (28/10/2026) » de `CLAUDE.md` : c'est délicat, à ne pas casser.

## 2. Étape A — Serveur sans Chromium (priorité 1)

**But** : faire tourner l'hôte des parties Arène / BR **directement dans Node** (ou dans un `worker_thread` par partie) au lieu d'une page Chromium. Chromium est lourd (processeur, mémoire) et ses minuteries sont irrégulières.

**Approche conseillée (la moins risquée)** : exécuter le **même `main.js`** dans Node avec un faux environnement de navigateur, plutôt que de réécrire la simulation.
1. Construire un bundle « hôte » : `main.js` tel quel, ou avec un petit garde-fou (`if (globalThis.OX_NODE_HOST) …`) autour du code qui touche au DOM au démarrage.
2. Fournir un **faux `window` / `document`** minimal : `getElementById` / `querySelector` qui renvoient des éléments factices (style, `classList`, `addEventListener`, `innerHTML`…), un faux canvas 2D dont toutes les méthodes ne font rien, `localStorage` en mémoire, `performance.now`, `requestAnimationFrame` (inutilisé par l'hôte), `location.search` = `?serverhost=…&key=…&mode=…`, `WebSocket` = le client `ws` de Node, `Image` factice, `AudioContext` absent (le son est coupé côté hôte). Commencer par une `Proxy` qui renvoie des fonctions vides, puis remplacer au cas par cas. `jsdom` est possible mais lourd ; un faux minimal suffit sûrement.
3. Lancer chaque partie dans un **`worker_thread`** (un plantage n'emporte pas tout le serveur, et l'état global du jeu reste séparé entre les parties). Le worker se connecte au serveur comme aujourd'hui (WebSocket local avec `HOST_KEY`), donc **le relais de `server.js` ne change pas** au début.
4. Garder Chromium derrière une variable d'environnement (`HOST_ENGINE=chromium|node`, `node` par défaut une fois validé), pour pouvoir revenir en arrière sans redéployer de code.
5. **Boucle fixe** : 60 calculs/s réguliers (accumulateur de temps, pas de pas qui dérive) ; snapshot juste après un calcul, toutes les 2 frames (30/s).
6. Garder `perfLine` : le worker envoie la même ligne `perf …` (et les erreurs) au thread principal.
7. Ensuite seulement (optionnel) : supprimer le saut WebSocket local en échangeant les messages avec le worker par `postMessage`.

**À vérifier particulièrement** : le BR classé complet (lobby → zone → résultats `#|res` → PR enregistrés → message `ranked` au joueur), les abandons, l'arène (12 joueurs max, réapparition, fermeture quand vide), les pièces côté serveur (`oxWal…`), les achats en partie, les bots de l'arène, l'arrêt propre (SIGTERM, cf. `server.js`), et la mémoire après plusieurs dizaines de parties (pas de fuite).

**Critères de réussite** : sur `/stats` et dans la ligne `perf`, **60 calculs/s stables, calcul max < 8 ms, pause max < 30 ms** avec 12 joueurs en arène ; utilisation du processeur divisée d'au moins 3 par rapport à Chromium (le mesurer, avec le même nombre de parties et de joueurs) ; `det.js` OK ; mesures `run.sh` au moins aussi bonnes qu'avant.

## 3. Étape B — Messages compacts (priorité 2)

**But** : réduire la taille et le temps de lecture des snapshots (30/s par joueur) et des entrées (60/s par joueur). C'est le plus utile sur téléphone et en 4G.

- Mesurer d'abord : taille moyenne d'un snapshot en arène avec 12 joueurs et beaucoup de balles (octets/s par joueur).
- Passer les messages **les plus fréquents** en **binaire** (`ArrayBuffer` + `DataView`, envoi en binaire par WebSocket) : snapshot `t:"s"` et entrées `t:"i"`. Les messages rares (achats, chat, résultats, système `!|`) peuvent rester en JSON.
- Positions en `Int16` / `Uint16` (carte 3000 × 3000 ; 1/10 de px = `Int32`, ou 1/8 de px sur `Uint16` + base), angles sur 1 octet ou `Int16`, PV sur 1 octet, drapeaux en bits. **Garder la précision actuelle** (positions des tanks au 1/10 de px, sinon des micro-saccades reviennent).
- Données d'apparence (nom, couleur, skin…) : envoyées seulement quand elles changent (c'est déjà le cas, `A._nst`), à garder.
- Option : delta par rapport au dernier snapshot confirmé, seulement si les mesures le justifient.
- **`server.js`** : aujourd'hui `ws.on('message', (raw, isBinary) => { if (isBinary) return; …`. Il faut faire passer le binaire. Garder un préfixe de routage (destinataire) lisible par le relais, par exemple 1 octet de type + 2 octets d'id.
- **Compatibilité** : pendant la transition, une version de jeu en cache chez un joueur peut parler l'ancien format. Ajouter un numéro de version de protocole dans `welcome` / `hi` et refuser proprement (message « recharge la page ») plutôt que de planter.

**Critères de réussite** : octets/s par joueur divisés par 2 à 4 ; aucune différence visible en jeu ; `run.sh` aussi bon qu'avant ; rien de cassé en room privée (hôte = navigateur d'un joueur).

## 4. Installer et lancer en local

```bash
npm ci                                   # esbuild (build du jeu)
cd server && npm i --no-save ws@8 playwright@1.56 && npx playwright install chromium && cd ..
python3 build.py                         # → dist/index-oryxo.html
python3 tools/test/mktest.py server/public/index.html   # build de test (non minifié, accroche window.__g)
node tools/test/mocksb.js &              # faux Supabase sur :5599 (jetons de test tA, tB, tC, tD)
cd server && SB_URL=http://127.0.0.1:5599 SB_SECRET=x PORT=3364 MIN_PLAYERS=2 QUEUE_WAIT=2 STATS_PASS=test node server.js
```
- Jeu : http://127.0.0.1:3364 ; page de stats : http://127.0.0.1:3364/stats (n'importe quel nom, mot de passe `test`).
- **Ping simulé** : variables `TEST_LAG` (ms, aller simple) et `TEST_JIT` (irrégularité) de `server.js`, 0 en production.
- `window.__g.ev("code")` (build de test seulement) évalue du code dans le jeu : pratique avec Playwright.
- Pour arrêter le serveur : `pkill -f "^node server.js"` (motif ancré, sinon on tue son propre terminal).
- En jeu, **F3** affiche le compteur de performances (appareil, réseau, serveur) ; « Copier les chiffres » donne un résumé de 30 s.

## 5. Tests à refaire après chaque étape

1. `python3 build.py` sans erreur.
2. `node tools/test/netbench/det.js` (serveur lancé avec le build de test) : `hote` et `joueur` doivent être identiques à 0,01 près.
3. `tools/test/netbench/run.sh avant` sur `main`, puis `tools/test/netbench/run.sh apres` sur la branche, avec le même ping simulé (par défaut `LAG=35 JIT=30` ; aussi `LAG=15 JIT=3`). Comparer :
   - « toi : à-coup » ≈ 0,3-0,5 px (ton propre tank) ;
   - « vu par l'autre : à-coup » ≈ 0,3-0,6 px (référence du 28/10) ;
   - « recalage max toi » ≈ 5 px ou moins.
   Mesures bruitées : lancer 2-3 fois et comparer les médianes. Ne pas lancer plusieurs mesures en parallèle (la machine sature et tout devient faux).
4. À la main (Playwright ou navigateur) : Entraînement, Arène (2 onglets), BR classé à 2 (jetons `tA`/`tB`, cf. `run.sh`/`sbr.js`) jusqu'aux résultats, room privée avec code.
5. Tirs : `oxSegDist` (les balles rapides touchent même avec du ping) ; boutique en partie ; skins (couleur des balles).

## 6. Ce qu'il faut rendre

- Une **pull request** sur `LamoOnGit/oryxo` (ou une archive si pas d'accès GitHub) avec :
  - le code ;
  - la mise à jour de `CLAUDE.md` (nouvelle section datée : ce qui change, où, comment revenir en arrière) ;
  - les chiffres avant / après (`run.sh`, ligne `perf`, octets/s, processeur).
- Pour Malo, un **petit texte en français simple** : quels fichiers déployer (`dist/index-oryxo.html` et/ou `server/server.js`, plus tout nouveau fichier serveur, qu'il faudra ajouter à `deploy/oryxo-deploy.sh` et à sa fonction `deploy`), comment vérifier (`/stats`, F3), et comment revenir en arrière (`rollback` sur son Mac, ou `HOST_ENGINE=chromium` dans `/opt/orbit/.env` puis `sudo systemctl restart orbit` **sur le VPS**).
- Attention : **un déploiement redémarre le serveur et coupe les parties en cours.**
