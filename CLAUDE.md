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
| `sql/` | Scripts Supabase dans l'ordre où ils ont été donnés (01 → 09 ; le 09 = passe premium donné à la main, donné à Malo le 05/11). `verification.sql` affiche ✅/❌ pour chacun (à lancer dans le SQL Editor). Tous installés et vérifiés ✅ par Malo le 26/10 (ordre sûr si on réinstalle : 05 puis 04 puis 06, le 04 utilise avatar_url et crown ajoutés par le 05) |
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

- Modes : Battle Royale classé (solo/duo/trio/squad, **complété par des bots jusqu'à 12 joueurs** depuis le 29/10/2026), Arène (carte Volcan, réapparition infinie), Multijoueur (room privée avec code), Entraînement (contre des bots).
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
- **2 colonnes sur grand écran** (≥ 900 × 560 px) pour ne plus défiler : `oxProfLayout()` (appelé après chaque `Dn()`) range identité / rang / frise / stats à gauche et parties / badges / compte / amis à droite. Le compte est redessiné à chaque `Dn()` : les blocs déplacés portent `.ox-moved` et sont supprimés avant d'être remplacés. Les stats locales et le titre « Classé » (masqués une fois connecté) sont retrouvés par `#profile .prof-stats:not(.acc-stats)` et `#profClasseH`. Testé : 590 px de haut de 1280×720 à 1920×1080 ; sur téléphone on garde 1 colonne (défilement).
- **Version compacte (26/10)** : bloc CSS « page profil compacte » (avatar 84 px, marges réduites) → 512 px de haut sur ordinateur (testé 1000×600 à 1440×900) ; sur téléphone ≤ 600 px : 3 dernières parties seulement, boutons du compte sur 1 ligne → tient sur un iPhone 13 (390×844), défile un peu sur iPhone SE. Frise : 12 paliers dans la largeur (`li{flex:1 1 0}`) et marge intérieure pour que le halo du rang actuel ne soit plus rogné par la zone de défilement.
- **Organisation (26/10, validée avec les vraies données de Malo)** : gauche = identité, rang, frise, stats, **badges** ; droite = dernières parties, **amis** (liste compacte, défile à l'intérieur au-delà de ~240 px) ; **bas sur toute la largeur** (`.ox-pfoot`) = boutons du compte. Pastille « 0 » à côté de « Amis » corrigée (`.acc-h .fr-badge[hidden]`), vide sous « Ajouter » supprimé (`.fr-msg:empty`).
- Tag de clan (`.ox-tag`) : il héritait de l'ombre portée du nom du clan, qui coupait le bas des lettres → `text-shadow:none`.

## Admins (ajouté le 26/10/2026)

- `sql/08-admins.sql` : colonne `profiles.is_admin` (un joueur ne peut pas la modifier : seuls username/avatar_url/updated_at sont modifiables depuis le jeu) + `set_admin(pseudo, true|false)` (SQL Editor seulement). Le script met **RaisedByLamo** admin.
- Jeu : `oxIsAdmin()` / `oxAdminAddSkins()` (appelé dans `oxRankAddOwned`, donc à chaque recalcul des skins possédés) → un admin possède **tous** les skins de `OX_SKINS` + `OX_RANK_SKINS`, donc automatiquement chaque nouveau skin ajouté au jeu. Le skin équipé n'est plus retiré tant que le profil n'est pas chargé (sinon un admin perdait son skin au rechargement).
- C'est côté jeu (cosmétique) : les skins des admins ne passent pas par `my_skins` ni Stripe.

## Balles qui traversaient les tanks (corrigé le 26/10/2026)

- Cause 1 : la collision n'était testée qu'à la position d'arrivée de chaque pas. Sniper = 1100 px/s ; si l'hôte serveur ralentit (pas de 50 ms → 55 px), la balle sautait par-dessus le tank (rayon de contact 26 px). Test : 37/40 touches à 50 ms avant, 40/40 après.
- Cause 2 (la plus fréquente en ligne) : pour compenser le ping, l'hôte avance d'un coup la balle d'un joueur distant (`oneWay`, jusqu'à 120 ms ≈ 130 px au sniper) **sans test de collision** → un ennemi proche était traversé. Test ennemi à 70-230 px : 20 à 34/40 avant selon le ping, 38-40/40 après.
- Correction : `oxSegDist` (distance d'un point au trajet de la balle pendant le pas) pour les tanks et les obstacles, côté hôte (`o.px/o.py`, et `o.fx/o.fy` = vrai point de départ testé au 1er pas après l'avance) et côté invité pour les tirs prédits.

## Tester en local

```
node tools/test/mocksb.js            # faux Supabase sur :5599
cd server && SB_URL=http://127.0.0.1:5599 SB_SECRET=x PORT=3311 node server.js
python3 tools/test/mktest.py server/public/index.html   # build de test avec window.__g (servi par le serveur local)
```
Avec `pkill`, ancrer le motif (`pkill -f "^node server.js"`), sinon on tue son propre shell.

## Arbres, eau, accueil, balles de skin (corrigés le 26/10/2026)

- **Arbres** : le tank s'arrête au bord du feuillage dessiné, plus au tronc (`oxTreeProf` recalcule le contour des boules de feuilles depuis `seed`, `oxTreeHit` = distance d'arrêt selon l'angle). Utilisé chez l'hôte (`Es`) et dans la prédiction de l'invité (identique). Les pièces/objets et téléportations évitent aussi le feuillage (`ws`, `Yo`). Le volcan (r ≥ 100) garde son cercle.
- **Eau** : `ot()` bloque maintenant le centre du tank à 12 px **avant** l'eau (avant : 13 px dedans, le tank débordait de ~35 px). Sur un pont, le tank reste sur le tablier (`oxOnBridge`, marge 17 px). `no()` n'a pas changé (sinon les arbres changeraient de place).
- **Accueil** : le gros tank avec un skin dessiné utilise la vignette `_thumb.webp` (256 px, `oxHeroSkin`) au lieu des calques 176 px agrandis ~6× ; canvas `#heroTank` à la résolution de l'écran (×DPR). Pour encore plus net : il faudrait les dessins originaux 512 px de Malo (faire des `_hd.webp`).
- **« ? » de « Prêt à dominer »** : `em` en `inline-block`, petit espace, italique comme le reste.
- **Balles de la couleur du skin** : `OX_SKIN_BULLET` (id 40-54 → couleur), `oxBulletColor` = couleur du skin dessiné s il y en a un (prioritaire, même si « Traceurs azur » est équipé : c était la cause des balles bleues de Malo le 27/10), sinon couleur de balles gagnée au classé, sinon couleur du tank. Traînée de la même couleur (`OX_SKIN_TRAIL` dans `oxBulletFx`), arc-en-ciel qui tourne pour Prisme. Le 27/10 Malo voyait encore des balles bleues avec Prisme : la version n était pas en ligne (le déploiement GitHub construit mais n envoie rien tant que les secrets `VPS_SSH_KEY`/`VPS_KNOWN_HOSTS` manquent). La couleur passe déjà par le snapshot, donc tout le monde la voit.

## Fluidité avec les skins (corrigé le 27/10/2026)

- Cause : chaque tank à skin dessiné copiait son morceau dans la **grande planche** (16 images × 3 calques, ex. 2816×528) à chaque image. Dessin d'une image avec 12 tanks à skin : ~21 ms → ~1 ms une fois corrigé (test logiciel). **`oxImgCell`** découpe chaque (skin, image d'animation, calque) une seule fois dans un petit canvas gardé en mémoire (`OXI_CELLS`).
- Pseudos au-dessus des tanks pré-dessinés (`oxNameTag`, cache `OX_TAGS`, vidé quand la police arrive). Avant : `strokeText` + `fillText` par tank et par image.
- Balles du classé (azur, fusion, étoile) : halo en simple cercle transparent au lieu de `shadowBlur` (très lent).
- **Résolution automatique** (`OXRES`, `oxQualityTick` dans `Os`) : en partie, si plus de la moitié des images dépassent 22 ms sur ~2 s, la résolution du canvas baisse (1,5 → 1,25 → 1). Ne remonte pas pendant la session.
- L'hôte serveur ne dessine rien (`SERVER_HOST`), donc ces changements ne touchent que les joueurs.

## Fluidité en ligne (corrigé le 28/10/2026)

Mesuré avec un BR à 2 joueurs en local (`TEST_LAG=35 TEST_JIT=30`, et `15/3`) : tank qui roule tout droit vu par l'autre joueur, à-coups max par image **3,6-5,5 px avant → 0,3-0,6 px après** (connexion stable : 4,4 → 0,3 px). Ton propre tank : inchangé (déjà régulier).
- **Cause principale** : l'hôte jouait les « pas » de mouvement d'un joueur au moment où ils arrivaient, et en entier. Paquets en retard = rattrapage de 120 ms d'un coup ; appareil à 30 images/s = pas de 33 ms joués d'un bloc toutes les 2 frames de l'hôte → avance / arrêt / avance chez les autres.
- **Hôte (`Es`, branche `n.remote && n.stepQ`)** : réserve adaptative `n.inBuf` (45 ms au départ, 30-80 ms selon la régularité du joueur, ajustée chaque seconde via `n.inLow`), lecture à vitesse ×0,55 à ×1,5 selon le remplissage, max ~1,6× le temps réel par frame (sauf retard > 300 ms). Un pas peut être montré en plusieurs morceaux : il est **calculé en entier** sur une copie (`r[6]`, même résultat exact que la prédiction du joueur — découper la physique en petits pas allait ~11 % plus loin), puis le tank glisse vers ce résultat (`r[5]` = déjà joué, `r[7]/r[8]` = dernière position posée pour garder une poussée extérieure).
- **`n.ack`** = état exact (x, y, vx, vy, moveT) à la fin du dernier pas complet, envoyé au joueur en `g[id][10]` ; le joueur se recale dessus (au lieu de la position publique, qui peut être au milieu d'un pas). Remis à `null` à la mort.
- **Heure des snapshots** = `f.simT` (heure du dernier calcul `Es`) au lieu de l'heure d'envoi (écart variable de 0-16 ms → à-coups).
- **Horloge d'affichage lissée chez le joueur** (`f.rt` dans `_l`) : avance au rythme réel, se recale doucement (sautait à chaque changement de délai / d'horloge).
- Positions des tanks dans les snapshots au 1/10 de px (`Ve`) au lieu de l'entier.
- Le joueur envoie ses touches 60×/s (`ba = 60`, avant 30) : paquets plus petits et plus réguliers.
- Tests : `scratchpad/t7/sbr.js` + `runv.sh` (BR 2 joueurs, mesure écart à la ligne droite et à-coups), `det.js` (hôte = prédiction au 1/100 px).

## Compteur de performances (ajouté le 29/10/2026)

- **F3** en partie (ou clic sur le badge du ping en haut, ou `?perf` dans l'adresse ; mémorisé dans `localStorage ox.perf`) : panneau `#oxPerf` (fonctions `oxPerf…`, données `OXPF`) avec 3 lignes, en vert / orange / rouge :
  - **Appareil** : images/s, pire image, temps de dessin (`tn`), résolution (`yn`).
  - **Réseau** (invité seulement) : ping, irrégularité (`f.jit` = 95e centile de l'écart d'arrivée des snapshots), positions reçues /s, plus grand trou entre 2 snapshots.
  - **Serveur** : calculs/s de l'hôte, durée d'un calcul (moy/max), plus grande pause entre 2 calculs, réserve de touches du joueur chez l'hôte (`n.inBuf`, envoyée en `g[id][11]`). L'hôte mesure avec `oxPerfTick` (dans la boucle `serverhost` et via `oxEsTimed` dans `Os`) et envoie `h.pf = [calculs/s, moy ms, max ms, pause max ms, joueurs]` une fois par seconde dans le snapshot.
  - **« Copier les chiffres »** : résumé des 30 dernières secondes (mode, navigateur, écran) dans le presse-papiers, à coller dans le chat.
- Seuils verts : ≥ 55 img/s, pire image ≤ 25 ms, ping ≤ 80 ms, irrégularité ≤ 15 ms, trou ≤ 70 ms, ≥ 57 calculs/s, calcul max ≤ 8 ms, pause ≤ 30 ms.
- **server.js** : les lignes `perf …` des hôtes (arène et BR) vont dans le journal (`journalctl -u orbit | grep PERF`) et sur **`/stats`**, section « Serveur (VPS) » : processeur (moyenne 1 et 15 min / nombre de cœurs), mémoire, et chiffres de chaque partie en cours.

## BR classé complété par des bots (ajouté le 29/10/2026, demande de Malo)

- Règle : **toujours 12 joueurs**. Seul → 11 bots ; 8 vrais joueurs → 4 bots, etc. On ne peut pas rejoindre une partie en cours (déjà le cas : tickets). Niveau des bots « moyen + ».
- **server.js** : `BR_BOTS` (actif par défaut, `BR_BOTS=0` dans `.env` pour couper). File d'attente (`tryStart`) : si moins de `MIN_PLAYERS` vrais joueurs, la partie part quand même au bout de `BOT_WAIT` secondes (défaut 8, réglable dans `.env`) à compter du plus ancien dans la file ; message `queue` avec `bots` = secondes restantes (le jeu affiche « départ dans X s, complété par des bots »). `welcome` envoie `bots: true` à l'hôte. Log : `match … + N bots`.
- **Hôte (`main.js`)** : `gr(mode, expected, bots)` → `f.br.bots`. Au compte à rebours (`Mr`), `oxBrAddBots()` complète chaque équipe des vrais joueurs puis crée des équipes de bots jusqu'à `12 / taille d'équipe` équipes (noms de `It`, différents des pseudos). Bots : pistolet + aucun power-up au départ comme les joueurs (ils ramassent et achètent ensuite, `Ki`), `aimErr` 0,07-0,13, `react` 0,8-1,05, `fireMul` 0,9 (bots normaux de l'Entraînement : 0,05-0,18 / 0,6-1).
- **Classement** : les bots comptent (`xr` = équipes vivantes, vrais joueurs ET bots ; `wr` traite aussi la mort d'un bot). La partie se termine quand il reste une seule équipe, ou quand plus aucune équipe ne contient de vrai joueur vivant (inutile de laisser les bots finir entre eux).
- **Équilibrage** (mesuré avec un joueur de test qui vise et tire sur le plus proche) : avant, les bots s'entretuaient (12 → 3 en 40 s, duels dès le départ car tous filaient au centre de la zone). Maintenant : **20 premières secondes calmes** (`f.br.playAt`, pas de bot contre bot, joueurs visés seulement à < 420 px), en BR classé avec bots un autre bot compte comme 1,4× plus loin pour le choix de cible, et tant que la zone ne rétrécit pas les bots ne se dirigent vers le centre qu'au-delà de 92 % du rayon (75 % sinon). Le joueur de test fait 1-3 éliminations et finit entre 2e et 9e.
- Tests : `scratchpad/t8/solo.js <mode> <jetons>` (ex. `solo.js duo tA,tB`), `timeline.js` (nombre de vivants toutes les 2 s). Serveur de test : `MIN_PLAYERS=2 QUEUE_WAIT=6`.

## Bannières au-delà de Céleste III (ajoutées le 29/10/2026)

- Au-delà de 1800 PR (Céleste III, rang max), **bannière selon la place mondiale** (`oxEliteTier(pos, pr)` / `oxEliteHtml`, CSS `.ox-elite-*` dans `src/shell.html`) : **N°1 MONDIAL** (couronne, doré + reflet animé), **TOP 10 MONDIAL** (doré), **TOP 100** (violet céleste), **TOP 500** (argent). Rien au-delà de la 500e place.
- Où : **page profil** (sous la barre de rang, `oxEliteMine` → `leaderboard_position`, gardé 60 s dans `OXEL`), **carte joueur** (remplace l'ancien encadré « TOP 500 », `top_pos` de `player_card`), **classement mondial** (étiquette « 👑 N°1 mondial » pour le 1er seulement : les autres sont tous dans le top 10, l'étiquette était redondante et coupait les pseudos).
- Place mondiale = 1 + nombre de joueurs avec plus de PR (`leaderboard_position` / `player_card.top_pos`), donc pas de nouveau SQL.
- **30/10 (demande de Malo)** : titre = **place exacte** (« N°2 MONDIAL », sous-titre « Top 10 mondial » / « Top 100 mondial » / « Top 500 mondial ») ; plus d'emoji : emblème SVG maison `oxEliteIcon(palier, taille)` dans le style des icônes de rang (ailes, médaillon avec globe, étoile ; couronne dessinée avec 3 pierres pour le N°1), couleurs `OX_ELITE_COL` (or / or / violet / argent).

## Dézoom bloqué en partie (30/10/2026)

- Avant, l'image de jeu prenait toute la fenêtre : dézoom du navigateur (Cmd −) ou très grand écran = on voyait une plus grande partie de la carte. Maintenant `_a()` limite la vue à **~1700 × 1000** de carte : `OXRES.zm = max(1, largeur/1700, hauteur/1000)`, `he/de` = taille de la fenêtre ÷ `zm` (taille en unités du jeu), transformation du canvas × `zm`. La souris (`ee`, `wt`, double-clic des clones) est divisée par `zm`.
- Écran normal (≤ 1700 × 1000) : rien ne change. 1920×1080 : léger agrandissement (×1,13). Dézoom 50 % sur un portable : même vue qu'à 100 %. Le HUD en HTML suit toujours le zoom du navigateur.

## Amis : statut « En partie » et invitations en jeu (corrigés le 30/10/2026)

- Avant : en Arène / room / Entraînement, les amis voyaient « En ligne » (le serveur ne connaissait que le BR classé = `game`). Maintenant le jeu envoie `{t:'st', play:0|1}` sur `/social` (`oxPlaySync`, toutes les 1,5 s si ça change, et à chaque `hello`) ; `server.js` garde `s.play` et `ustatus` renvoie **`play`** (« En partie », point bleu, **invitable**) ; `game` = « En partie classée » (non invitable, le serveur refuse « Ton ami est en pleine partie »). Ordre de tri : en ligne, en partie, en recherche, en partie classée, hors ligne.
- Invitation reçue en jeu : le toast (`#socToasts`, z-index 10050) passe au-dessus de la barre de spectateur (`#specBar`, 9999) qui cachait les boutons. « Rejoindre » pendant une partie hors classé = quitte la partie (`#backMenu`) puis rejoint le groupe (écran BR classé avec le groupe). En BR classé : « Termine ta partie classée avant de rejoindre » (abandon = dernière place).
- Textes « sans bots / aucun bot » remplacés (carte de mode « CLASSÉ EN LIGNE • 12 JOUEURS », FAQ, panneau classé, `server/public/llms.txt`).
- Test : `scratchpad/t8/social.js` (jeu connecté avec un faux client Supabase jeton `tA` + Bravo en WebSocket brut).

## Réglages, balles, badges (31/10/2026)

- **Onglet « Réglages »** (à côté de Jouer / Personnage / Touches, `#t-reglages`, rendu par `oxSetRender`) : qualité graphique Auto / Haute / Moyenne / Basse (`OXSET.q` → `OXRES.cap` 1,5 / 1,5 / 1,25 / 1, particules `nl` 420 / 420 / 250 / 120, « Basse » coupe les traînées de balles ; seul « Auto » baisse la résolution tout seul), volume des effets et de la musique séparés (tous les sons passent par `Ne.__sfx` : `F()` remplace `Ne.destination` par ce gain ; la musique `kt` va à `Ne.__real`), secousses de l'écran oui/non (`J` ignoré), taille des commandes tactiles 70-140 % (`--oxts`, téléphone seulement), compteur de performances. Sauvegardé dans `localStorage ox.set` et dans le compte (`settings.prefs`, via `save_settings`).
- **Balles** : mesurées déjà fluides (`tools/test/netbench/bullets.js` : à-coup médian 0 px pour ses balles, 0,2-0,5 px pour celles des autres, même avec ±150 ms d'irrégularité). Améliorations : les balles des autres suivent l'horloge d'affichage des tanks (`f.rt`) pour rester alignées avec leur cible ; tes roquettes / couteaux (non prédits, avant : petits sauts à chaque snapshot) sont lissés comme les autres ; lissage indépendant des images/s (`1 - 0.08^dt`).
- **Badges : 5 paliers** (Bronze, Argent, Or, **Platine**, **Diamant**, `OX_TIERS` avec `l/c/d`), objectifs étendus dans `OX_Q` (ex. Fléau 50 / 250 / 1 000 / 2 500 / 5 000 ; Ascension jusqu'à Céleste III 1800 PR) → 76 badges. Nouveau dessin `oxBadgeSVG` : dégradé + reflet + halo, lauriers dès l'Or, étoile au-dessus en Platine, gemme + éclats en Diamant, pastilles colorées par palier ; badge unique (clan) = style Or.

## Bots du classé moins forts et moins acharnés (31/10/2026, retour de Malo)

- Malo : « un peu trop forts, et quand ils croisent un vrai joueur ils le focus et arrêtent de tirer entre eux ». Bots du BR classé (`ai.brBot`) : `aimErr` 0,10-0,17, `react` 0,65-0,9, `fireMul` 0,8 (proches des bots normaux).
- Ciblage (`hl`) : plus de préférence pour les vrais joueurs ; un bot **garde sa cible quand c'est un autre bot** (jusqu'à 700 px) au lieu de la lâcher pour un joueur ; **2 bots max** sur le même vrai joueur ; 6 premières secondes : personne n'est visé, jusqu'à 20 s : pas de bot contre bot et joueurs seulement à < 420 px.
- Test (`timeline.js`, joueur de test très simple) : finit 2e / 3e / 2e sur 12 (avant ces réglages : mort en 4-18 s).

## Passe de combat, collection, cartes BR (04/11/2026, demande de Malo)

- **Passe « Cœur du Volcan » (saison 1)** : bouton orange « Passe » sur l'accueil (`#openPass`, pastille = récompenses à récupérer), fenêtre `oxOpenPass` / `oxPassRender`. **20 niveaux**, **1 000 XP par niveau** (demande de Malo le 05/11 ; avant 150 + 10 × (niveau − 1)). Récompenses dans `OX_PASS` (`lv`, `tr` f = gratuit tous les 2 niveaux / p = premium à chaque niveau, `type`, `id`). Fin de saison `OXPS.end` (4/1/2027).
- **XP** (`oxPassAddXp`) : +10 par élimination en ligne, +5 par minute de jeu en ligne, fin de BR classé +30 et bonus selon la place (1er +80, 2e +50, 3e +40, top 5 +25, top 8 +12) avec la pastille « +X XP » sur l'écran de fin. L'Entraînement ne compte pas. Toast « Niveau X ! ».
- **Sauvegarde** : dans la progression des quêtes (`OXQ.prog`, synchronisée par `quest_sync` qui garde le max, **pas de nouveau SQL**) : `pass_xp`, `pass_cf` / `pass_cp` = dernier niveau récupéré (gratuit / premium). Côté jeu, donc trichable (cosmétique seulement).
- **Premium** (05/11) : achat Stripe comme un skin, **produit 90** (`OX_PASS_PREMIUM_ID`, 4,99 € = `OX_PASS_PRICE` 499 centimes) → ligne dans `my_skins` ; `oxPassPremium()` = `OXS.owned.has(90)`. Bouton « Acheter » + case de renonciation dans la fenêtre du passe ; retour `?achat=ok&skin=90` → message puis ouverture du passe. **L'edge function `create-checkout` doit accepter l'id 90 (4,99 €)**, sinon « Le paiement n'est pas encore disponible ».
- **Plus de passe-droit admin pour le passe** (05/11, Malo pouvait tout équiper) : un admin garde seulement tous les skins de la boutique et de rang ; titres, cartes, balles, sons, skins du passe et premium se débloquent normalement.
- **Nouveaux objets** : 17 titres (`OX_TITLES`, « Recrue » offert), cartes Cendres / Coulée / Obsidienne / Éruption (CSS `.pcd-*`), balles Givre / Toxique / Foudre (dans `oxBulletFx` surchargé), sons Pop / Arc électrique / Éruption (`oxShotSfx` surchargé), skins dessinés en code 33 Braise, 34 Obsidienne, 35 Éruption (`OX_PASS_SKINS`, cases de `oxSkinPaint`). Raretés partout : com / rare / epic / legendary / mythic (`OX_RARITY`, classes `.ox-r-*`).
- **Possession** : `oxHas` = rang OU passe (`oxPassHas`). Titre équipé `I.rttl` (sauvegardé dans `settings.look.title`). Un skin du passe n'est pas retiré avant le chargement de la progression du compte (`OXQ.pulled`).
- **Écran « Nouveau … ! »** (`oxReveal`) : rayons, halo de la couleur de la rareté, objet qui flotte, son plus riche selon la rareté, Équiper / Suivant.
- **Collection** (`oxOpenColl` / `oxCollRender`, bouton dans le passe et dans Personnaliser) : onglets Skins / Titres / Cartes / Balles / Sons, compteur X / Y, aperçu de ta carte BR à gauche, objets verrouillés avec leur source (boutique, rang, niveau du passe).
- **Cartes de l'intro BR (3-2-1)** : cadre selon la rareté (design de carte, sinon skin ; arc-en-ciel animé pour mythique), rayons, emblème de rang, « N°X » mondial, titre sous le pseudo. Grande carte du joueur : gemme, rayons qui tournent, tank qui flotte, bandeau « N°X MONDIAL », titre, rang + PR. Les infos passent par `oxMyLook()` → `lk` dans `hi` et à l'index 25 des snapshots (`oxLookOk` vérifie). La moitié des bots reçoit un titre simple.
- **« 10 joueurs » corrigé** : l'hôte attend 220 ms après avoir ajouté les bots avant d'envoyer `intro` (sinon l'invité n'avait pas encore les bots).
- Tests : `scratchpad/t9/pass.js [largeur hauteur]`, `intro.js`, `fin.js`.

## Sniper, chargeurs, bonus, classes (05/11/2026, demande de Malo)

- **Sniper** : vue **×1,25** quand on l'a en main (`OXRES.sz`, transition douce dans `oxViewTick` appelé par `Os` ; `oxApplyView` = `he/de` et transformation du canvas ; la souris utilise le zoom effectif `OXRES.vz`). Dégâts : **200 à l'arrêt** (vitesse < `SNIPER_STILL_SPEED` 40, `oxSniperStill`, décidé par l'hôte) sinon 60. Viseur : ligne rouge à l'arrêt, pointillés blancs en mouvement (`oxSniperSight`).
- **Chargeurs** (`OX_MAG` : [balles, s de rechargement]) : pistolet 12 / 1,3 · SMG 30 / 1,8 · shotgun 5 / 2 · sniper 4 / 2,3 · roquettes 3 / 2,6 · boomerang 4 / 1,6. Couteau et laser : pas de chargeur. Rechargement automatique à 0, touche **R** (`Q.reload`, modifiable dans Touches) ou toucher le compteur sur téléphone. Changer d'arme ou mourir = chargeur plein. Calculé chez l'hôte (`Tn` → `oxAmmoCan/oxAmmoUse`, `oxAmmoTick` dans `Es`, bots compris) et prédit chez le joueur ; l'hôte envoie `[balles, reste]` en `g[id][12]` (`oxAmmoFromHost`) ; `{t:'rl'}` = recharger. Affichage `#oxAmmo` à droite de la barre de vie. Chargeur indiqué dans la boutique.
- **Bonus** : retirés de la boutique (onglet masqué), apparaissent 2× plus souvent au sol (`PICKUP_INTERVAL` 5 → 2,5 s, `PICKUP_MAX` 10 → 16).
- **Classes** : textes ultime / note raccourcis (bloc « descriptions des classes raccourcies »).
- Test : `scratchpad/t9/ammo.js` (local + BR en ligne), `ammom.js` (affichage ordinateur / téléphone).

## Sons et traînées du passe (05/11/2026)

- Testés : une fois récupérés, ils s'équipent et marchent (balles Givre #bff4ff + effets, son Pop). Les objets premium restent verrouillés sans achat (normal).
- **Priorité des balles changée** : `oxBulletColor` = skin d'arme équipé d'abord, sinon couleur du skin dessiné (`OX_SKIN_BULLET`), sinon couleur du tank. Avant, un skin dessiné écrasait toujours le skin d'arme → les traînées du passe ne se voyaient jamais avec un skin dessiné. Pour retrouver les balles de la couleur du skin : enlever le skin d'arme (toucher l'équipé dans la collection).
- Aperçu des sons : `oxSoundPreview` passe par `OXSND.force` (surcharge de `oxEquipped("sound")`), donc on entend aussi les sons pas encore débloqués. Dans la collection, toucher un son possédé l'équipe et le joue. Notes d'aide dans les onglets Balles et Sons (`.ox-cl-note`).
- Rappel : le son de tir n'est entendu que par le joueur lui-même ; les balles / traînées sont vues par tout le monde.

## Objets verrouillés + passe premium donné à la main (05/11/2026)

- **Message d'erreur** au lieu d'équiper un objet pas débloqué : `oxEquipItem` refuse et affiche `oxLockMsg` (toast `fn`) : « réservé au passe premium (niveau X) », « atteins le niveau X du passe (tu es niveau Y) », « récupère-le d'abord dans le passe », « atteins le rang X en classé », « à acheter dans la boutique ». Écran de récompense en aperçu : titre « À DÉBLOQUER », bouton gris « 🔒 Verrouillé » + message. Collection : toucher un objet verrouillé = message (+ ouverture du passe / de la boutique).
- **Possession = niveau vraiment atteint** : `oxPassClaimed` / `oxPassHas` ne comptent que les niveaux ≤ niveau actuel (Malo avait récupéré des niveaux avec l'ancien coût d'XP ou en admin ; `quest_sync` garde le max, on ne peut pas baisser `pass_cf/pass_cp`).
- **`sql/09-passe.sql`** : colonne `profiles.pass_premium` (non modifiable par le joueur) + `give_pass(pseudo, true|false)` (SQL Editor seulement). `oxPassPremium()` = produit 90 acheté **ou** `q.profile.pass_premium`.

## Intro BR : skin et fond de carte des autres joueurs (05/11/2026)

- Les infos arrivaient bien (`lk`, skin), mais : (1) les designs de carte du classé (acier, azur, nébuleuse, prisme) n'avaient de CSS que pour `.pc-card` / `.ox-rr-card` → ajout de `.bx-bgd.pcd-*` et `.ox-cl-bgd.pcd-*` ; (2) l'image d'un skin dessiné jamais vu sur cet appareil n'était pas encore chargée au moment de dessiner la carte → l'intro redessine les canvas toutes les 200 ms pendant ~3 s (`drawAll` dans `xo`).
- Test : `scratchpad/t9/intro2.js` (2 vrais joueurs avec skin + carte + titre différents).

## Boutique en packs (05/11/2026, demande de Malo)

- **Les 15 skins dessinés ne sont plus en vente** (`OX_PACKS_LIVE = true` → `oxShopList()` = `OX_PACK_SKINS`). Ceux qui les ont achetés les gardent (Personnaliser + collection les montrent s'ils sont possédés).
- **Packs** (`OX_PACK_SKINS`, dessinés dans le moteur du jeu, `oxPackPaint` appelé par `oxSkinPaint` surchargé ; aura sous le tank `oxSkinAura`, appelée dans `fo`) : **60 Dragon de Jade, 61 Hologramme, 63 Pharaon Éternel, 64 Oni Cyber**, tous mythiques à 5,49 €. Supernova (62) retirée. Chaque pack = skin + balles (`OX_BULLETS` jade / holo / sable / oni, effets dans `oxBulletFx` surchargé) + traînée. Sans skin d'arme équipé, un tank à skin de pack tire les balles du pack (`OX_SKIN_PACK`, `oxBulletColor` surchargé) ; acheter le pack donne aussi le skin d'arme (`oxHas` surchargé).
- **Fenêtre « pack »** (`oxOpenPack`, ouverte par `oxOpenSkinModal` pour un skin de pack) : grande scène animée (`oxPackScene` mode hero) + skin / balles / traînée séparés + achat Stripe (même `create-checkout`, ids 60 61 63 64 à 5,49 €, **à ajouter dans l'edge function**).
- **Boutique de l'accueil** (`oxPackShopRender`) : pack **en vedette** (change chaque jour à minuit, heure de Paris approx.), bandeau **passe de combat** (niveau, XP, premium, ouvre le passe), grille **Tous les packs** avec tanks animés. `#shop.skins-only` élargi à 1000 px.
- Statut des amis (05/11) : retesté, marche (en ligne / en partie / retour / hors ligne 8 s après). Si ça ne marche pas en ligne, vérifier que le VPS a bien le `server.js` qui gère `{t:'st'}`.
- Tests : `scratchpad/packs/shop2.js` (boutique ordinateur + téléphone, packs 63/64, en partie), `scratchpad/t8/social2.js`.

## Packs refaits dans la DA du jeu (05/11/2026, retour de Malo)

- Malo n'aimait pas les packs (masques, visages, auras) : « rester dans la DA du jeu, comme Obsidienne ou Éruption ». `oxPackPaint` refait : une **matière** (dégradé + motif simple + reflet / lueur qui bouge doucement, mêmes helpers `sweep` et `veins` que Braise), identique châssis / tourelle, **sans aura** (`oxSkinAura` ne dessine que si `sk.aura`, aucun pack ne l'a).
- Packs : 60 **Jade Impérial** (jade veiné d'or), 61 **Hologramme** (verre de lumière cyan + balayage), 63 **Pharaon** (or strié de lapis, pierres turquoise), 64 **Oni** (laque noire, veines néon rouges). Balles / traînées inchangées.
- Comparaison : `scratchpad/packs/cmp.js` (Braise, Obsidienne, Éruption à côté des 4 packs).
- 05/11 : boutique de l'accueil sans la barre d'onglets (un seul onglet « Skins », inutile : `#shop.skins-only .shop-tabs` masqué), marges ajustées, textes en Trebuchet (pas la police des titres), tank en vedette plus grand (scène `feat` dans `oxPackScene`).

## Oryx, la monnaie du jeu (05/11/2026, idée de Malo)

- **Principe** : on achète des **Oryx** (gemme dessinée par Malo, `server/public/oryx.webp` + `oryx_64.webp`, intégrées aussi dans le jeu en data URI `OX_ORYX_IMG`) avec de l'argent, puis on achète packs et passe premium en Oryx.
- **Prix** : offres (`OX_ORYX_OFFERS`, Stripe, ids **101-105**) : 100 = 0,99 € · 550 (dont 50 offerts) = 4,99 € · 1 200 (dont 200) = 9,99 € « le plus populaire » · 2 600 (dont 600) = 19,99 € · 7 000 (dont 2 000) = 49,99 € « meilleure offre ». Objets (`OX_ORYX_PRICE`, mêmes valeurs dans `oryx_price()` en SQL) : pack mythique **500**, passe premium **450**. L'équivalent en euros (au tarif de l'offre 550 / 4,99 €) est affiché à côté (« ≈ 4,54 € ») par transparence.
- **`sql/10-oryx.sql`** (après le 09) : `profiles.oryx` (non modifiable par le joueur), tables `oryx_items` (achats en Oryx) et `oryx_credits` (Oryx reçus, `ref` unique), fonctions `buy_with_oryx(item)` (vérifie solde / déjà possédé, retire, donne ; item 90 met aussi `pass_premium`), `my_oryx()` (solde + objets), `credit_oryx(user, n, ref)` (service_role, pour le webhook Stripe, jamais deux fois le même `ref`), `give_oryx(pseudo, n)` (SQL Editor). Testé sur PostgreSQL 16.
- **Jeu** : `OXW` (solde), `oxOryxFetch` (appelé après `oxSkinsFetch`, ajoute les objets à `OXS.owned`), compteur `#oryxChip` dans la barre de l'accueil (ouvre les offres), `oxOryxBuyBtn` (1er clic « Confirmer », 2e clic achat ; « Il te manque X Oryx » + lien), `oxOpenOryxShop` (offres + case de renonciation + `oxCheckout(101..105)`), section « Oryx » en bas de la boutique. Fenêtre pack et passe premium payés en Oryx (plus de Stripe direct pour les objets).
- **À faire côté Stripe** : `create-checkout` doit vendre les ids 101-105 aux prix ci-dessus, et le webhook doit appeler `credit_oryx(user_id, nombre, id_de_session)` après paiement. Tant que ce n'est pas fait, on peut donner des Oryx avec `give_oryx`.
- Test : `scratchpad/packs/oryx.js` (faux Supabase : achat, confirmation, pas assez, fenêtre des offres).

## Packs : titre + fond de carte ; intro BR sans bugs (05/11/2026)

- Chaque pack donne aussi un **titre** et un **fond de carte** (`OX_PACK_EXTRA`, bloc placé juste avant « Mobile : doubles joysticks » car `OX_TITLES` doit déjà exister) : 60 « Empereur de Jade » + carte Jade, 61 « Fantôme numérique » + carte Hologramme, 63 « Pharaon éternel » + carte Pharaon, 64 « Démon rouge » + carte Oni (CSS `.pcd-jade/holo/pharaon/oni`, reflet animé `pcSheen`). Possédés si le pack est possédé (`oxHas` surchargé, champ `pack`). Fenêtre pack : 5 objets (skin, balles, traînée, titre, fond de carte) ; après achat, écran « Nouveau … ! » pour chacun. Collection : source « Pack X » ; message « inclus dans le pack X ».
- **Intro BR** : avant, on voyait ~1 s la carte du jeu + le HUD (liste 2 → 12 joueurs) avant l'intro → **écran d'attente** `oxBrCover` (fond bleu + « Préparation de la partie… ») affiché dès `Er` (rejoindre une partie classée), retiré 250 ms après le début de l'intro (sécurités : partie quittée, phase `play`, 25 s max). Le rond d'étincelles (`.bx-sparks`) qui apparaissait seul au centre avant la carte : `animation-fill-mode: forwards` + délai 0,75 s.
- Rappel : les packs ne sont pas donnés aux admins (comme le passe) ; pour tester : `give_oryx` puis acheter.
- Tests : `scratchpad/t9/introv3.js` (vidéo de l'intro à 2 vrais joueurs), `scratchpad/packs/pk5.js`.

## Barre du haut réorganisée (05/11/2026, demande de Malo : « structuré, facile d'accès, léger »)

- HTML (`src/shell.html`, `.quick`) : `<nav class="qnav">` = **Personnaliser, Quêtes, Social, Classement** en boutons plats avec icône (`.qtab`, `.qi` SVG), dans une pastille discrète ; `<div class="qright">` = **Passe, Oryx, Boutique, compte, plein écran** (les seuls boutons en relief). Bloc CSS « barre du haut réorganisée » juste avant `</head>` (il passe après tous les anciens styles).
- Ordinateur : libellés jusqu'à 1260 px, icônes seules (avec infobulle) de 901 à 1260 px ; rang sous le pseudo et plein écran masqués sous 1420 px.
- Téléphone / tablette (≤ 900 px ou hauteur ≤ 560 px) : grille de 6 colonnes, ligne 1 = logo + Oryx + compte (« Se connecter » prend la place des Oryx), ligne 2 = 6 onglets icône + libellé court (`data-short` : Perso, Passe, Quêtes, Amis, Top, Boutique ; Passe et Boutique en couleur).
- `oxPassChip` met « Passe » dans `<span class="ql">`. Test : `scratchpad/nav/nav.js` (8 tailles, connecté / déconnecté).
- 05/11 (retour de Malo : « Classement » rentrait dans « Passe ») : la barre se **compacte toute seule** si elle déborde (vraie largeur des textes, zoom, long pseudo) : petit script avant « Mobile : doubles joysticks » (ResizeObserver + toutes les 2 s) qui ajoute `.qc1` (rang sous le pseudo, plein écran, marges), puis `.qc2` (icônes seules dans la navigation), puis `.qc3` (pseudo masqué) tant que la navigation est rognée ou à moins de 8 px des boutons de droite. Test : `scratchpad/nav/nav2.js` (1024 → 1920 px, zoom 110 / 125 %).

## HUD du bas regroupé + touches en double (05/11/2026, retour de Malo)

- Avant : nom de l'arme flottant loin au-dessus, cases bonus au milieu, chargeur collé à droite (repères sur 2 lignes). Maintenant **`#oxDock`** (créé au démarrage, petit script avant « Mobile : doubles joysticks » qui y déplace les éléments existants) : ligne 1 = **[arme + chargeur]** (`#weaponHud` + `#oxAmmo` collés en une carte) puis **[bonus 1-3 + ultime]** (`#hudGroup`), ligne 2 = **barre de vie** sur toute la largeur. CSS « HUD du bas regroupé » avant `</head>` (anciennes positions absolues neutralisées). Téléphone (`body.touch-play`) : même bloc à 78 %.
- **Touches en double** : Malo avait le bonus 2 sur R = rechargement. Au chargement, si la touche de rechargement est déjà prise, elle passe sur la première libre parmi R, F, X, G, V, T. Dans l'onglet Touches, choisir une touche déjà utilisée **échange** les deux actions (plus jamais deux actions sur la même touche).
- Test : `scratchpad/nav/hud.js` (1280×720, 1920×1080, téléphone 844×390 ; bonus sur C / R / CapsLock).

## Oryx et compte au lancement sans saut (05/11/2026, retour de Malo)

- Avant : les Oryx étaient chargés **après** les skins (`my_skins` puis `my_oryx`) ; le compteur apparaissait tard, à 0 puis au vrai solde, et la barre du haut bougeait (le bouton du compte aussi : « Se connecter » puis le pseudo).
- Maintenant : `my_oryx` part **en même temps** que `my_skins` (`oxSkinsFetch` surchargé avec `Promise.all`) ; dernier solde + objets gardés sur l'appareil (`localStorage ox.oryx`, `oxOryxSave`) et affichés dès le lancement ; dernier pseudo / rang / avatar gardés (`ox.acct`, `oxAcctCached`) ; compteur à largeur fixe (132 px, chiffres à chasse fixe) avec animation d'attente au tout premier lancement (`.oxo-wait`).
- Oubli : `oxForgetAccount()` à la déconnexion (les 2 `signOut`) et si aucune session n'est revenue 8,5 s après le lancement. Un autre compte sur le même appareil remet le solde à 0 avant chargement.
- Tests : `scratchpad/nav/oload.js` (Supabase lent de 2 s : 1er / 2e lancement, position de la Boutique), `ologout.js`.

## Version de Malo (autre PC) reprise + pièces + favicon (05/11/2026)

- Malo a fait une version sur un autre PC (`index-2.html`, minifiée) : **reportée dans les sources** (build identique à la sienne, mêmes 1 156 942 octets) : bouton **Collection** à la place de Personnaliser dans la barre (`#openColl`, `data-short="Collec"`), **roue crantée** `#oxGear` (ouvre Réglages / Touches, classe `#start.ox-cfg` qui cache l'onglet Jouer), onglet Personnage caché (`#t-perso` hidden, onglets = Jouer / Réglages / Touches), « Personnaliser le cercle » du profil → « Ma collection », collection avec en-tête fixe (seule la grille défile), **les 15 skins dessinés retirés du jeu** (`OX_IMG_SKINS` vide ; un skin 40-54 équipé repasse à 0, choix de Malo).
- **Pièces** : dessin de Malo (`server/public/coin.webp` + data URI `OX_COIN_IMG`) pour les caisses de pièces au sol (`Gn.coins`) et le compteur `.coin-ic` (style injecté au démarrage).
- **Favicon** : illustration du tank de Malo recadrée : `favicon.ico` (16-64), `apple-touch-icon.png` (180), `icon-192.png`, `icon-512.png` (image entière) dans `server/public/`, + favicons 32/64 intégrés dans `src/shell.html` (le lien apple 180 intégré a été retiré : il pointe sur le fichier).
- Images envoyées à Malo dans `oryxo-images.zip` (à décompresser dans `/opt/orbit/public`).

## Bots du BR classé : seulement quand on cherche seul (05/11/2026, demande de Malo)

- `server.js` : `BR_BOTS` actif par défaut (`BR_BOTS=0` dans `.env` = jamais de bots). Des bots complètent la partie jusqu'à 12 **seulement s'il n'y a qu'une seule entrée dans la file** (un joueur seul, ou un seul groupe d'amis) depuis `BOT_WAIT` s (`botsNow` dans `tryStart`). Dès qu'il y a 2 entrées (2 vrais joueurs ou plus), partie normale **sans aucun bot** (`startMatch(mode, group, withBots)` → `match.bots`, envoyé à l'hôte dans `welcome`). Log : `+ N bots` ou `(sans bots)`.
- Textes : FAQ, panneau classé, `llms.txt` (« si tu cherches seul, des bots complètent ; à partir de 2 vrais joueurs, plus aucun bot »).
- Test : `scratchpad/t8/bots2.js` (seul → 12 tanks dont 11 bots ; à 2 → 2 tanks, 0 bot), serveur `MIN_PLAYERS=2 QUEUE_WAIT=4 BOT_WAIT=4`. Le serveur local a besoin de `ws` (`server/node_modules`).

## Amis : diagnostic du statut / des invitations (05/11/2026)

- Malo : « en ligne / hors ligne et jouer avec un ami ne marchent pas ». Retesté en local avec 2 vrais navigateurs (`scratchpad/t8/social3.js`) : statut, invitation, Rejoindre, groupe = tout marche → le problème vient du VPS (ancien `server.js` ou connexion du serveur à Supabase, `SB_SECRET`).
- Ajouté : `SDIAG` dans `server.js` (derniers échecs de `sbUser` / `sbFriends`, sans secret) visible sur **`https://oryxo.eu/status`** → `social: { version: 3, online, userFail, friendsFail, badToken, last, ago }`. Pas de champ `social` = ancien serveur. `/social` envoie la raison (`why`) avant de fermer en 4001, `hello` porte `ferr` si la liste d'amis n'a pas pu être lue.
- Jeu : message orange dans la liste d'amis (`D.serr`, dans `hr` surchargé) : compte non vérifié par le serveur, liste d'amis illisible, ou connexion impossible.
- Test du cas cassé : `scratchpad/t8/social4.js` (serveur avec un faux `SB_URL`).

## Pièces partagées en équipe (05/11/2026, demande de Malo)

- BR en duo / trio / squad (`ce === "br" && be > 1`) : une caisse de pièces (`fl`, `kind: "coins"`, 100 pièces) donne ses pièces à **chaque coéquipier vivant** (portefeuille de l'hôte `wal.crates`, bots `money`, joueur local `O.coins`). Les coéquipiers voient « +100 pièces · Pseudo » (`{t:'coins', n, by}`). Solo et Arène inchangés. Les gains au score / aux éliminations restent personnels.
- Côté hôte (le serveur charge le jeu `public/index.html`), donc il suffit de déployer le jeu. Test : `scratchpad/t8/coins.js`.

## Mise en ligne automatique depuis GitHub, tirée par le VPS (05/11/2026)

- Les téléchargements depuis le chat ne marchaient plus pour Malo (fichiers non cliquables, copier-coller raté qui a remplacé `server.js` par 37 octets). Les secrets GitHub `VPS_SSH_KEY` / `VPS_KNOWN_HOSTS` n'ont jamais été mis (le workflow construit mais n'envoie rien), et Claude ne peut pas les créer (API Actions bloquée par le proxy).
- Solution : **le VPS va chercher la version tout seul**. `deploy/install-pull.sh` (une fois, en root) installe `/usr/local/sbin/oryxo-pull` (= `deploy/oryxo-pull.sh`) et le minuteur `oryxo-pull.timer` (chaque minute). Si `origin/main` a changé : copie `dist/index-oryxo.html` → `public/index.html`, `server/server.js`, `server/public/` ; sauvegarde `.bak`, `node --check`, redémarre `orbit`, vérifie `/health`, retour arrière sinon. Commit déployé dans `/opt/orbit/.deployed-commit`. Journal : `journalctl -u oryxo-pull -n 30`.
- Clone dans `/opt/oryxo-src` avec une **clé de déploiement en lecture seule** `/root/.ssh/oryxo_pull` (ajoutée par Malo dans GitHub → Settings → Deploy keys).
- Donc : **pousser sur `main` = en ligne en ~1 min** (et `dist/index-oryxo.html` doit être reconstruit avant chaque commit). Les fonctions `deploy` / `rollback` du Mac restent utilisables (mais le prochain push les écrase).
- **Cause trouvée (05/11)** : `/status` affichait `friendships 403` code 42501 → le rôle `service_role` n'avait pas le droit `SELECT` sur `public.friendships`. Correctif : `sql/11-amis-serveur.sql` (grant select sur friendships + profiles à service_role).
- Traînées : seules les balles à skin (rang, passe, packs) ont une traînée ; les 15 skins dessinés (40-54) avaient une traînée de leur couleur, retirée avec eux dans la version de Malo. Testé : les 10 skins de balles dessinent bien leur traînée.
- Traînée par défaut (05/11) : toute balle sans skin a une petite traînée de la couleur du tank (48 px, `oxBulletFx` de base), sauf en qualité Basse.
- Carte joueur avec fond de carte (`.pc-card.pcd-*`) : voile sombre (ombre intérieure rgba(6,10,34,.58)) pour lire les infos (05/11, retour de Malo).
- Traînées et effets de balles affichés **même en qualité Basse** (05/11 : Malo ne voyait aucune animation des balles spéciales, réglage Basse gardé dans son compte). Basse = seulement moins de particules + image moins fine.

## Assassin rééquilibré (05/11/2026, retour de Malo : « trop fort et peu cher en BR »)

- Couteau : dégâts au contact 80 → **55** (`KNIFE_DAMAGE`), cadence 0,4 → **0,55 s** (`KNIFE_RATE`, 1,8 coup/s), prix 150 → **275** pièces (classe Assassin = couteau + Momentum + Berserk : 525 → 650). Lancer inchangé (45-90).
- Ultime « Coup de l'ombre » : 160 → **85** dégâts (plus de mort en un coup sur un tank plein, 100 PV), portée de téléportation 480 → **360** px. Textes mis à jour (classe + description courte).

## Version de Malo (index-oryxo_7) reportée + garde coupée + nouveau Mercenaire (05/11/2026)

- Malo a mis en ligne sa propre version (`index-oryxo_7.html`, minifiée, partie de `228335464cba`). **Reportée dans `src/main.js`** (86 changements sur 87) : mines (arme `mines`, classe **Piégeur** élite, ultime 8 mines), **mur de fumée** (bonus `smoke`, bloque la vue dans les 2 sens, `oxSmoke*`), bonus avec **prix et fréquence** propres (`we[x].cost` / `w`, tirage pondéré dans `dl`), régénération après 4 s sans dégât (`REGEN_*`), Adrénaline soigne 15 au kill, Vampire plafonné (`VAMPIRE_MAX_HEAL`), Last Stand 2,5 s avec recharge 20 s, roquette 70 + coup direct (`ks(o, cible)`), boomerang 32, laser 1,8 s de refroidissement, sniper 3 balles + tir à l'arrêt après 0,4 s immobile (`stillT`), couteau 80 / 0,65 s / 225, ultimes Assassin 95, temps de recharge élite 26 / légendaire 28 / immortelle 34, Phénix sans 2e vie, **le Gel n'immobilise plus** (empêche seulement de tirer, choix de Malo). Événements réseau `sm`, `mn`, `mb`, `mr`.
- Vérifié : toutes les tables (armes, power-ups, bonus, classes, constantes) identiques à sa version, et mêmes résultats aux duels de bots (±4 %).
- **Garde coupée** (demande de Malo) : `hi = 0` (sa version avait 45 : -35 % de dégâts pour qui ne tire pas).
- **Mercenaire, nouvel ultime « Contrat »** (l'ancien = 110 auto sur 3 cibles, sans viser) : rechargement instantané, puis les **2 prochains tirs de sniper (8 s) font 100** et marquent la cible 5 s (`MERC_SHOTS/DAMAGE/TIME/MARK`, `e.mercShots/mercT`, balle dorée `markHit`, viseur doré). Raté = perdu.
- **Banc d'équilibrage** (scratchpad `bal/`) : `harness2.js` (duels de bots dans un build `mktest`, distance idéale par arme, ultime lancé dès que prêt), `suitem.js` (armes, TTK, power-ups), `suite4m.js` (classes, moitié ultime prêt), `suite2m.js` (classe vs arme seule, ultime, bonus). Limites : bots trop précis au sniper, nuls avec couteau / mines / fumée.
- **05/11 (demande de Malo) : Mines, Mur de fumée et Piégeur retirés** (arme, bonus, classe, textes). Le moteur `oxMine*` / `oxSmoke*` reste dans le code mais plus rien ne crée de mine ni de fumée. Le nouvel ultime du Mercenaire est gardé.

## Panneau Admin de la boutique (05/11/2026, demande de Malo)

- **`sql/12-boutique-admin.sql`** (après 08 et 10) : table `shop_config` (1 ligne, `cfg` jsonb, aucun accès direct), `get_shop_config()` (anon + authenticated), `set_shop_config(p_cfg)` (refuse si `profiles.is_admin` est faux, code `admin`), et **`oryx_price` remplacée** : prix de base → prix admin → promo active ; objet caché = `null` (donc `buy_with_oryx` refuse « item »). Testé sur PostgreSQL 16.
- `cfg` = `{ featured: { pack, until }, items: { "60": { hidden, price, promo, promoUntil } }, map: { arena: "volcano"|"classic" }, banner: { on, text, color, until } }` (couleurs : or, bleu, rouge, vert, violet).
- Jeu : `OXCFG`, `oxCfgLoad()` (au lancement, `fetch` REST avec la clé publishable, gardé dans `localStorage ox.cfg`), `oxCfgApply` (met à jour `OX_ORYX_PRICE` depuis `OX_BASE_PRICE`), `oxCfgHidden` (filtre `oxShopList` et la grille), `oxCfgFeatured` (vedette choisie, sinon rotation quotidienne), `oxCfgPriceHtml` (ancien prix barré + « -X % »), `oxBannerRender` (`#oxBanner` sous la barre du haut), `oxArenaCardRender` (« CARTE PRAIRIE / VOLCAN » sur la carte de mode), `oxCfgArenaMap()` utilisée par `Xe` / `Hl` pour la carte de l'Arène. L'hôte serveur attend les réglages (3 s max) avant de rejoindre sa partie.
- Bouton **Admin** (bouclier jaune, `#oxAdminBtn`, ajouté dans `.qnav` seulement si `oxIsAdmin()`) → `oxOpenAdmin()` : annonce, pack en vedette + date de fin, tableau des objets (en vente, prix, promo, fin de promo), carte de l'Arène, bouton Enregistrer (`set_shop_config`).
- Test : `scratchpad/adm/t.js` (faux Supabase par `page.route` + `setG`), `t2.js` (promo dans la grille).
- Pas encore : collections (Noël, Halloween…) à mettre en vedette, à ajouter quand elles existeront ; l'image de la carte « Arène » reste le volcan même en Prairie.
