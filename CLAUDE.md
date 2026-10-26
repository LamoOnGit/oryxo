# Oryxo.eu — jeu .io de tanks multijoueur

Jeu web de Malo (ex « Orbit.io »), en ligne sur **https://oryxo.eu**.
Malo débute en dev : explique-lui les choses **en français, simplement, une étape à la fois**, et dis toujours **où** taper une commande (Terminal du Mac ou VPS).

## Organisation du dossier

| Chemin | Rôle |
|---|---|
| `src/shell.html` | Le HTML + tout le CSS du jeu. Contient `/*__MAIN__*/` où le JS minifié est injecté |
| `src/main.js` | Tout le JS du jeu (une grosse IIFE). **C'est une version « dé-minifiée » : beaucoup de noms sont courts et obscurs** (voir la table plus bas) |
| `build.py` | `python3 build.py` → `dist/index-oryxo.html` (minifie avec esbuild). Il faut Node + esbuild (`npm i -D esbuild` ou npx) |
| `dist/index-oryxo.html` | Dernière version construite (celle qu'on déploie) |
| `server/server.js` | (= `/opt/orbit/server.js`) Serveur Node (http + WebSocket `ws`) : sert `public/`, rooms, file d'attente classée, social |
| `server/public/` | = `/opt/orbit/public` sur le VPS. Fichiers statiques à côté du jeu : `skins/*.webp`, favicon, og-image, robots.txt, sitemap.xml, llms.txt, manifest, pages légales (`mentions-legales.html`, `cgv.html`, `confidentialite.html` + `legal.css`) |
| `sql/` | Scripts Supabase dans l'ordre où ils ont été donnés (01 → 07). `verification.sql` affiche ✅/❌ pour chacun (à lancer dans le SQL Editor). Tous installés et vérifiés ✅ par Malo le 26/10 (ordre sûr si on réinstalle : 05 puis 04 puis 06, le 04 utilise avatar_url et crown ajoutés par le 05) |
| `deploy/` | `setup-vps.sh` (installation unique sur le VPS) et `oryxo-deploy.sh` (script qui reçoit et installe une version, copié dans `/usr/local/sbin/oryxo-deploy`) |
| `.github/workflows/deploy.yml` | Déploiement automatique : chaque push sur `main` qui touche `src/`, `server/`, `build.py` ou `package*.json` construit le jeu et l'envoie sur le VPS |
| `package.json` | esbuild 0.28.2 fixé (`npm ci` puis `python3 build.py`) |
| `tools/test/` | `mocksb.js` (faux Supabase sur :5599, jetons tA/tB/tC/tD) et `mktest.py` (build non minifié avec accroche `window.__g`) |
| `tools/skins-pipeline/make.py` | Transforme les skins dessinés par Malo (PNG/spritesheets 512 px) en planches 3 calques pour le jeu |

## Hébergement et déploiement

- VPS OVH `57.129.178.141`, utilisateur `ubuntu`. Jeu dans `/opt/orbit` (fichiers servis : `/opt/orbit/public/`, le jeu = `public/index.html`), service systemd **`orbit`** (drop-in : `TimeoutStopSec=5`, `KillMode=mixed`). nginx + Let's Encrypt devant (HTTPS).
- Secrets dans `/opt/orbit/.env` : `SB_URL`, `SB_SECRET` (clé secrète Supabase, **jamais dans le jeu, jamais dans un chat ni une capture**), `MIN_PLAYERS`, `QUEUE_WAIT`, `PORT`, `STATS_PASS` (mot de passe de la page `/stats` ; sans lui, `/stats` renvoie 404).
- **Dépôt GitHub privé `LamoOnGit/oryxo`** (branche `main`). Claude y a accès en écriture depuis les sessions Claude Code.
- **Déploiement automatique (GitHub Actions)** : un push sur `main` qui touche le jeu ou le serveur → GitHub lance `npm ci` + `python3 build.py`, vérifie, puis envoie une archive par SSH à `ubuntu@57.129.178.141`. Sur le VPS, la clé de GitHub est **limitée à une seule commande** (`command="sudo -n /usr/local/sbin/oryxo-deploy",restrict` dans `~/.ssh/authorized_keys`) : sauvegarde `.bak`, copie (`public/index.html`, `server.js`, fichiers statiques de `server/public/` sans rien supprimer), `systemctl restart orbit`, vérification de `/health` (2 fois à 3 s d'écart), et **retour automatique à l'ancienne version** si le serveur ne répond pas. Bouton manuel : onglet Actions → « Déployer sur oryxo.eu » → Run workflow. Secrets GitHub : `VPS_SSH_KEY`, `VPS_KNOWN_HOSTS` (affichés par `deploy/setup-vps.sh`). Sans eux, le jeu est construit (téléchargeable dans l'onglet Actions) mais pas envoyé. Un déploiement redémarre `orbit` : les parties en cours sont coupées.
- Depuis le Mac, Malo a aussi deux fonctions zsh (toujours utilisables) :
  - `deploy` : prend le plus récent `~/Downloads/index-oryxo*.html` et `server*.js` (plus récents que `~/.oryxo_deployed`), les envoie par scp, sauvegarde en `.bak`, copie dans `/opt/orbit`, redémarre `orbit`.
  - `rollback` : remet les `.bak`.
- Fichiers statiques en plus (ex. skins) : zip → `scp X.zip ubuntu@57.129.178.141:/tmp/` puis
  `ssh ubuntu@57.129.178.141 "cd /opt/orbit/public && sudo python3 -m zipfile -e /tmp/X.zip . && sudo chown -R orbit:orbit ."`
- Piège fréquent : Malo tape parfois les commandes du Mac **dans** le VPS. Rappeler `exit` et de regarder l'invite (`ubuntu@...` = VPS).

## Supabase

Projet `rexptnaqcumxrdbxhmoi`. Le jeu utilise la clé **publishable** (normal qu'elle soit dans le HTML).
- Tables : `profiles` (id uuid = auth user, username, pr, peak_pr, settings jsonb, games, wins, kills, best_place, crown bool, loss_streak, avatar_url), `matches`, `friendships`, plus `my_skins` (achats).
- RPC : `record_ranked_result` (service_role uniquement, appelé par le serveur), `leaderboard(n)`, `leaderboard_position(p_user)`, `friend_request/respond/remove`, `friends_list`, `player_card(p_id)`, `save_settings(p_settings)`.
- Edge function `create-checkout` (Stripe) pour acheter les skins — **à mettre à jour avec les ids 40-54** (voir Skins).

## Architecture du jeu

- Un seul fichier HTML. Rendu canvas 2D.
- WebSocket du serveur : `/ws` (rooms : un joueur héberge), `/mm` (file d'attente classée), `/social` (présence, invitations, groupes).
- Battle Royale classé : le serveur lance un « hôte serveur » (Chromium sans écran) par partie ; les résultats sont signés par le serveur puis enregistrés via `record_ranked_result`. Quitter une partie en cours = classé dernier (pénalité de PR).
- Réglages (touches + apparence) liés au compte : `save_settings`, rechargés à la connexion.

### Table des noms courts dans `src/main.js`

`p` joueur · `Se` balles · `N` tanks · `f` réseau (NET) · `q` compte (ACC) · `G` client Supabase · `I` apparence perso (custom) · `Q` touches · `O` portefeuille · `K` partie en cours · `le` overlay · `ln` divisions · `it` rankOf · `Nt` icône de rang · `fe` sauvegarde des prefs · `Oa` ouvrir carte joueur · `fi` résultat classé · `Er` rejoindre partie classée · `Tn` tirer · `Fe` créer une balle · `Jn` son de tir · `pe` tone · `F` audio · `Ae` muet · `z` PAD · `fo` dessiner un tank · `He` dessiner un aperçu de tank · `ko` afficher les touches · `Kt` kill · `Vl` retirer un invité · `Tt` envoyer réseau · `Ke` est invité · `tt` particules · `at` feed · `ie` échapper HTML · `$e` boutique en partie · `he/de` largeur/hauteur écran · `Z` caméra · `ee` souris · `ue` touches pressées · `J` tremblement · `xt` créer un tank · `st` rendu boutique · `an` onglet boutique · `Pt` contexte boutique.
Le code ajouté récemment est lisible et préfixé `ox…` (`oxApplySettings`, `oxImgHull`, `OX_SKINS`, `OX_RANK_REWARDS`…).

## Règles de jeu validées par Malo

- Modes : Battle Royale classé (solo/duo/trio/squad, **sans bots**), Arène (carte Volcan, réapparition infinie), Multijoueur (room privée avec code), Entraînement (contre des bots).
- BR : les pièces ne servent que pendant la partie, **seuls les PR se gardent**. Nuages : −10 PV au-delà de 3 s dedans. Tirer en invisible révèle. Minimap de la zone en bas à gauche (sans les joueurs). À la mort : caméra du tueur, on peut passer d'un joueur vivant à l'autre. Arbres toujours aux mêmes endroits, jamais sur les ponts ; pièces jamais dans les arbres ni l'eau. Clones : double-clic pour leur donner une direction.
- Couronne : seulement pour le vainqueur de la partie précédente (pas un accessoire).
- Classé : Rookie → … → Céleste, chacun en I/II/III ; gains de PR décroissants et pertes croissantes en montant ; top 3 ne perd jamais ; paliers plancher. Au-delà de Céleste III : **Top 500** affiché sur la carte joueur. Récompense à chaque palier (skins de rang 30-32, designs de carte, couleurs de balles, sons de tir). Frise de progression sur la carte joueur.
- Amis + groupes pour jouer en duo/trio/squad ; cartes joueur cliquables.
- Classement global : bouton « Classement » en haut → modale.

## Page d'accueil (design validé le 23/10/2026)

Ancien design : fond bleu nuit avec grille en perspective et losanges, gros tank à gauche (« Un cercle. Un canon. Ton arène. », étiquettes READY!/LEVEL UP), cartes de mode numérotées 01-04 avec sur-titres, compteur « 04 MODES ». **Pas de bouton JOUER.** Nav : Personnaliser, Quêtes, Social, Classement, Boutique, Se connecter, plein écran. La carte « Prochain badge » est masquée sur l'accueil. Le bouton Boutique de l'accueil ouvre **uniquement l'onglet Skins** (classe `#shop.skins-only`), sans pièces.

## Skins (boutique)

Seuls les **15 skins dessinés par Malo** sont en vente (les 8 anciens skins procéduraux, ids 10-17, ont été retirés). Images en 3 calques (châssis, canon, tourelle) dans `server/public/skins/<clé>.webp` (+ `_thumb.webp`). Les animés ont 16 images, 80 ms par image.

| id | clé | Nom | Rareté | Prix | Animé |
|---|---|---|---|---|---|
| 40 | carbone | Carbone | Rare | 1,49 € | non |
| 41 | camo_jungle | Camo Jungle | Rare | 1,49 € | non |
| 42 | arctique | Arctique | Rare | 1,49 € | non |
| 43 | desert_dore | Désert Doré | Épique | 2,49 € | non |
| 44 | bonbon | Bonbon | Épique | 2,49 € | non |
| 45 | royal | Royal | Épique | 2,49 € | non |
| 46 | citrouille | Citrouille | Épique | 2,49 € | oui |
| 47 | neon_cyber | Néon Cyber | Légendaire | 3,99 € | oui |
| 48 | magma | Magma | Légendaire | 3,99 € | oui |
| 49 | toxique | Toxique | Légendaire | 3,99 € | oui |
| 50 | dragon_dor | Dragon d'Or | Légendaire | 3,99 € | oui |
| 51 | fantome | Fantôme | Légendaire | 3,99 € | oui |
| 52 | galaxie | Galaxie | Mythique | 5,49 € | oui |
| 53 | tempete | Tempête | Mythique | 5,49 € | oui |
| 54 | prisme | Prisme | Mythique | 5,49 € | oui |

Prix stockés en centimes dans `OX_IMG_SKINS`. Si la page n'est pas servie depuis oryxo.eu (aperçu, fichier local), les images sont chargées depuis `https://oryxo.eu/skins/` (`OX_ASSET`).

## À faire / en attente

1. **Stripe** : mettre à jour l'edge function `create-checkout` (ids 40-54 et prix ci-dessus, retirer 10-17). Sans ça, l'achat affiche « Le paiement n'est pas encore disponible ».
2. **Classement** : l'appel `leaderboard` renvoyait une erreur → faire lancer `sql/05-classement-fix.sql` dans le SQL Editor de Supabase.
3. **Boomerang** ne marcherait pas en Battle Royale (non reproduit en test, attendre les détails de Malo).
4. Pages légales (mentions légales, CGV, confidentialité) nécessaires pour vendre via Stripe.
5. Idées proposées, pas encore validées : système de ban (banned_until / ban_reason vérifiés par le serveur), déploiement automatique via GitHub, bots pour remplir les parties classées, pièces côté serveur, statistiques de fréquentation (Umami), version CrazyGames (SDK, pas de connexion forcée ; idée de Malo : 2 parties de BR d'essai sans compte, puis compte obligatoire).
6. Bonne pratique sécurité : faire tourner la clé secrète Supabase (elle a été exposée une fois dans une capture).

## Tank et performances en ligne (intégré le 21/10/2026)

- Tank à chenilles (`fo`) : le châssis pivote vers la direction du déplacement (`_body`), les chenilles défilent (`_tread`), la tourelle suit la souris. Les dégradés sont mis en cache par couleur.
- Mode glace (Hiver) prêt mais coupé : `v.FEATURES.ice` (accélération 650 au lieu de 1800, friction `0.3^dt`). Appliqué pareil chez l'hôte et chez l'invité.
- Anti-saccades : bruit des sons pré-calculé ; sons des autres joueurs limités à 25/s et ignorés quand ils sont inaudibles (vol ≤ 0,03) ; 420 particules max (`nl`) ; 45 chiffres de dégâts max ; vignette « vie basse » pré-rendue ; table des tanks du snapshot calculée une seule fois (`_m`).
- Réseau : en tirant, la visée seule est renvoyée à 60/s max (les changements de touches restent à 120/s).
- L'hôte serveur calcule `perf images/s=… calcul max=…` toutes les 10 s, mais `server.js` ne recopie dans ses logs que les lignes contenant « rror » (et seulement pour l'arène). Pour diagnostiquer des saccades en ligne, il faudrait d'abord faire suivre ces lignes `perf` dans les logs (`journalctl -u orbit`). Sous 60 images/s, c'est le processeur du VPS qui sature.

## Pages légales et statistiques (ajoutées le 23/10/2026)

- Pages `/mentions-legales`, `/cgv`, `/confidentialite` (le serveur ajoute `.html` aux adresses sans extension). Liens en pied de page de l'accueil (`.legal-links` dans `src/shell.html`) et dans le texte sous le bouton d'achat d'un skin. Ajoutées au `sitemap.xml`.
- Les infos personnelles de Malo sont des champs **`[À COMPLÉTER]`** en orange (nom, adresse, SIRET, e-mail, médiateur de la consommation) : il faut les remplir avant de vendre. Ce sont des modèles, à faire relire si possible.
- La case « je renonce à mon droit de rétractation » existait déjà avant le paiement (`data-ox-consent`), les CGV s'appuient dessus.
- `/stats` (dans `server.js`, `statsPage`) : mot de passe `STATS_PASS` (nom d'utilisateur au choix). Joueurs en ce moment (arène, BR, rooms, file), compteurs depuis le dernier redémarrage (en mémoire), et via Supabase : nombre de comptes et participations classées par jour (une ligne de `matches` = un joueur dans une partie). Page rafraîchie toutes les 15 s, cache Supabase 60 s.
- Umami (visites, pays, pages, sans cookie) : `UMAMI_ID` = `83df179b-0828-4a0c-8e07-3a2e2275e1c1` (compte cloud.umami.is de Malo), dans le petit script juste avant `</head>` de `src/shell.html`. Vide = désactivé. Ne se charge que sur oryxo.eu et jamais dans les pages hôtes du serveur.

## Bannissement (ajouté le 23/10/2026)

- `sql/06-bannissement.sql` : colonnes `banned_until` (timestamptz, `infinity` = définitif) et `ban_reason` dans `profiles`, + fonctions `ban(pseudo, durée, raison)` et `unban(pseudo)` utilisables seulement depuis le SQL Editor (service_role).
- Le même script **limite ce qu'un joueur peut modifier dans `profiles` depuis le jeu à `username`, `avatar_url`, `updated_at`** (avant, selon les règles RLS, il pouvait peut-être changer ses PR ou sa couronne). Toutes les autres écritures passent par des fonctions `security definer`, donc rien ne casse.
- `server.js` : `sbUser` lit le ban (`banOf`, `banMsg`) ; `/mm` refuse avec le message (code 4005), `/social` envoie `{t:'banned'}` puis ferme. Les tickets classés passent par `/mm`, donc sont couverts. L'Arène, les rooms privées et l'Entraînement restent jouables (pas de compte obligatoire).
- Jeu : `oxBanCheck` (au chargement du profil) et `oxShowBan` affichent la fenêtre « Compte suspendu » ; le social ne se reconnecte plus en boucle (`D.banned`).

## Accueil mobile (corrigé le 23/10/2026)

Bloc CSS « accueil mobile » juste avant le script Umami dans `src/shell.html` : taille du texte des boutons du haut adaptée à la largeur (`clamp`), sous-texte « pour le classé » masqué sur petit écran, logo + boutons sur 2 lignes entre 591 et 900 px, losanges `.star-a`/`.star-b` déplacés (ou masqués en paysage) pour ne plus toucher les boutons. Testé de 320 px à 915 px de large, portrait et paysage.

## Boomerang en BR (testé le 23/10/2026)

En BR classé solo (2 joueurs, hôte serveur), acheté en partie : il part (~400 px) puis revient, et l'achat est bien transmis à l'hôte (`Nl` → `{t:'lo'}`). Il disparaît s'il touche un arbre (comme les balles) et, chez l'invité, il n'est pas prédit en local (il apparaît avec le ping). En attente de la description précise de Malo.

## Pièces gérées par le serveur en BR classé (ajouté le 23/10/2026)

- En BR classé (`f.br`, hôte = serveur), l'hôte tient un portefeuille par joueur (`t.wal`, fonctions `oxWal…` dans `src/main.js`) : gains = même formule que le jeu (`score × COIN_PER_SCORE × 2 + kills × COIN_PER_KILL × 2`, plafond `COIN_CAP_PER_GAME`, comptés seulement en phase `play`) + caisses de pièces.
- Chaque achat (`{t:'lo'}` arme/power-ups, `{t:'ab'}` bonus à `BONUS_COST`) est vérifié : pas assez de pièces → refusé, et l'hôte renvoie `{t:'wal'}` (solde, armes et power-ups possédés, équipement réel) que le jeu applique (`oxWalApply`, message « Pas assez de pièces »).
- Le solde de l'hôte est envoyé à chaque snapshot (données privées `g`, index 9) et fait foi chez le joueur (`oxWalFromHost`, `f.walHost`) ; les gains locaux sont ignorés.
- À l'entrée en BR, l'hôte force pistolet + aucun power-up (avant, le joueur pouvait arriver avec l'arme de sa partie précédente).
- Les armes / power-ups **ramassés au sol** sont ajoutés au portefeuille et renvoyés au joueur. Avant, le jeu du joueur ne le savait pas et renvoyait son ancienne arme à la prochaine ouverture de la boutique : **cause probable du « boomerang qui ne marche pas en BR »** (boomerang ramassé puis perdu).
- Arène et rooms privées : inchangées (pièces encore calculées par le joueur).

## Boutiques (règle validée par Malo le 23/10/2026)

- Boutique de l'accueil = **uniquement les skins** (achat réel, Stripe). Les skins ne s'achètent **jamais en partie** : l'onglet Skins est masqué dans toute autre boutique (`#shop:not(.skins-only) .shtab[data-sh="skins"]`), et la boutique en partie s'ouvre sur Armes.
- Boutique en partie : se ferme avec B, avec le bouton « Fermer », ou **en cliquant / touchant en dehors du panneau** (`oxShopOutside`, ne déclenche pas de tir).

## Confort de jeu (ajouté le 23/10/2026)

- **Écran « Tourne ton téléphone »** : tant qu'il est affiché, la protection d'apparition du joueur ne s'use pas (30 s max par vie, `holdT`). L'invité l'envoie dans ses entrées (`{t:'i', h:1}`), l'hôte la maintient (`holdAt`). Avant, on se faisait tuer derrière cet écran.
- **Apparition** : `En()` refuse les points dans un nuage ou à moins de 160 px (`oxNearCloud`, protégé par `try` car les nuages n'existent pas encore au tout premier chargement). Avant, ~1 apparition sur 10 tombait dans un nuage. `SPAWN_PROTECT` passé de 0,6 à 2,5 s.
- **Boutique sur mobile** : le bouton 🛒 (barre en haut à droite) ouvre bien la boutique en paysage quand on est vivant (rien à changer).
- **Personnaliser** : grille des skins en grandes vignettes avec nom + prix (`.ox-skins-row`) ; toucher un skin non acheté ouvre la fenêtre d'achat.
- **Classement en partie** : ta ligne est surlignée avec « (toi) » ; si tu n'es pas dans le top 8, elle est ajoutée en bas avec ton vrai rang.
- Sur le VPS, seul `magma.webp` était présent dans `public/skins/` (aperçus manquants) : zip complet des 30 images donné le 23/10.

## Arrêt du serveur (corrigé le 26/10/2026)

- Avant : `systemctl restart orbit` restait bloqué en « deactivating (stop-sigterm) » (le serveur ignorait SIGTERM à cause de Chromium/Playwright) ; il fallait `sudo kill -9 <Main PID>`. Le drop-in `TimeoutStopSec=5` ne semblait pas actif (à vérifier : `systemctl show orbit -p TimeoutStopUSec`).
- Maintenant : `server.js` gère SIGTERM/SIGINT/SIGHUP (ferme Chromium puis quitte, 2 s max) et lance Chromium avec `handleSIGTERM/SIGINT/SIGHUP: false`. Testé : arrêt en 1-2 s.

## En ligne (26/10/2026)

Déployé par Malo : jeu `8445d3a08b64…` (commit 12b01cc) + serveur `90ddd578c4a8…` (arrêt propre), 30 images de skins, `STATS_PASS` ajouté au `.env`, scripts Supabase 01-06 ✅. Vérifier une version en ligne : `sha256sum /opt/orbit/public/index.html /opt/orbit/server.js` sur le VPS. Clé secrète Supabase de nouveau exposée sur une capture le 26/10 → à remplacer (nouvelle clé dans `.env`, puis supprimer l'ancienne dans Supabase).

## Clans (backend ajouté le 26/10/2026)

- L'interface existait déjà dans le jeu (onglet Clan du Social, fonctions `oxClan…`), mais aucune fonction Supabase : d'où « Clans indisponibles ». `sql/07-clans.sql` crée tout.
- Tables `clans`, `clan_members` (1 clan max par joueur, clé = user_id), `clan_requests`, `clan_invites` : RLS activé, **aucun accès direct**, tout passe par des fonctions `security definer`.
- Fonctions : `clan_get(p_clan)`, `clan_search(p_q)` (vide = classement par PR total), `clan_my_invites`, `clan_tags(p_ids)`, `clan_create`, `clan_update` (chef), `clan_disband` (chef), `clan_join` (ouvert = direct, sur demande = demande, sur invitation = refus), `clan_invite` / `clan_respond` (chef + officiers), `clan_invite_respond`, `clan_kick` (chef : tous sauf chef ; officier : membres), `clan_set_role` (chef ; nommer chef = l'ancien devient officier), `clan_leave` (le chef qui part passe la main à l'officier le plus ancien ; dernier membre = clan supprimé). Codes renvoyés = clés de `OX_CLAN_ERR`. 30 membres max, nom 3-24, tag 2-5 `[A-Z0-9]`, description 200 max.
- Le même script ajoute `profiles.quests` + `quest_get` / `quest_sync` (quêtes sauvegardées avec le compte, on garde toujours le max) et `player_extras(p_id)` (clan + badges sur la carte joueur).
- Testé sur PostgreSQL 16 avec 4 joueurs (scénario complet) + affichage de l'onglet Clan avec ces données.

## Page profil + tag de clan (corrigés le 26/10/2026)

- Page profil (`#profile`) : elle débordait en haut quand elle était plus haute que l'écran (le `#overlay` centre verticalement) → `box-sizing:border-box` + hauteur max + défilement interne. Frise « Progression classée » ajoutée sous le rang (`oxTimelineHtml`, comme sur la carte joueur). « Voir les quêtes » à droite du titre Badges (`.ox-bh`), boutons du compte en grille alignée (3 colonnes, 2 + 1 sur téléphone).
- Tag de clan (`.ox-tag`) : il héritait de l'ombre portée du nom du clan, qui coupait le bas des lettres → `text-shadow:none`.

## Tester en local

```
node tools/test/mocksb.js            # faux Supabase sur :5599
cd server && SB_URL=http://127.0.0.1:5599 SB_SECRET=x PORT=3311 node server.js
python3 tools/test/mktest.py server/public/index.html   # build de test avec window.__g (servi par le serveur local)
```
Avec `pkill`, ancrer le motif (`pkill -f "^node server.js"`), sinon on tue son propre shell.
