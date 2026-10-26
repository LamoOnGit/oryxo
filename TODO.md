# Oryxo.eu — fonctionnalités à ajouter

À lire avec `CLAUDE.md` (contexte, organisation des fichiers, déploiement).
Rappels : le code est dans `src/main.js` + `src/shell.html`, on construit avec `python3 build.py`, et on explique tout à Malo en français, simplement, étape par étape.
Ordre conseillé : **1 → 2 → 3**, puis le reste selon ses envies.

---

## 1. Paiement Stripe des 15 nouveaux skins (bloquant pour vendre)
- L'edge function Supabase `create-checkout` connaît encore les anciens skins (ids 10-17). Il faut la mettre à jour avec les ids **40 à 54**.
- Prix : 40-42 = 1,49 € · 43-46 = 2,49 € · 47-51 = 3,99 € · 52-54 = 5,49 €. Le détail des noms est dans le tableau de `CLAUDE.md`.
- Retirer les ids 10-17.
- Vérifier que le webhook Stripe enregistre bien l'achat dans `my_skins`, et que le skin se débloque dans le jeu après le paiement.
- Le code de l'edge function n'est pas dans ce dossier : demander à Malo de le récupérer (Supabase → Edge Functions) ou de le coller.
- Sans cette mise à jour, cliquer sur un prix affiche « Le paiement n'est pas encore disponible ».

## 2. Pages légales (obligatoires pour vendre avec Stripe) — FAIT le 23/10, reste à remplir les champs [À COMPLÉTER]
- Mentions légales, CGV (vente de biens numériques, renonciation au droit de rétractation pour un contenu livré immédiatement), politique de confidentialité (Supabase, Stripe, cookies et stats éventuelles).
- Malo est micro-entrepreneur, sans TVA (mention « TVA non applicable, art. 293 B du CGI »).
- Liens en pied de page de l'accueil, à côté de « À propos · Modes de jeu · FAQ ».
- Pages statiques dans `server/public/`, à ajouter au `sitemap.xml`.

## 3. Statistiques de fréquentation — FAIT le 23/10 (/stats) ; Umami : identifiant ajouté le 23/10, actif après le prochain deploy
- Mesure d'audience légère et respectueuse de la vie privée (Umami auto-hébergé sur le VPS, ou Plausible), pour les visiteurs, les pages et les pays.
- Une page `/stats` protégée (mot de passe ou réservée à l'admin) servie par `server.js` :
  - joueurs connectés en ce moment ;
  - parties en cours (rooms, BR classé, file d'attente) ;
  - parties jouées par jour et nombre de comptes (via Supabase).

## 4. Bug : boomerang en Battle Royale — cause probable corrigée le 23/10 (arme ramassée perdue à la réouverture de la boutique), à confirmer par Malo
- Malo dit que le boomerang ne marche pas en BR. Il n'a pas été reproduit en test : en ligne dans le banc de test, il part et revient correctement.
- Demander à Malo ce qui se passe exactement (il ne part pas ? ne revient pas ? ne fait pas de dégâts ? seulement en duo/squad ? seulement pour un invité, pas l'hôte ?).
- Piste : en BR classé, l'hôte est le Chromium sans écran du serveur. Vérifier que l'arme boomerang achetée en partie est bien synchronisée entre l'invité et l'hôte serveur.

## 5. Accueil sur mobile : 2 défauts d'affichage — FAIT le 23/10
- Le bouton « SE CONNECTER » est coupé dans la grille des boutons du haut.
- Un losange décoratif (`.shape-star`) passe par-dessus le bouton « CLASSEMENT ».

## 6. Système de bannissement — FAIT le 23/10 (SQL 06 lancé ; actif après le prochain deploy du serveur)
- Colonnes `banned_until timestamptz` et `ban_reason text` dans `profiles` (modifiables seulement par le service_role).
- `server.js` vérifie le ban à la connexion (`/mm`, `/social`, tickets classés) et refuse avec la raison et la date de fin.
- Le jeu affiche un message clair au joueur banni.
- Permettre à Malo de bannir et débannir simplement : un petit script SQL ou une page admin protégée.

## 7. Pièces gérées par le serveur (anti-triche) — FAIT le 23/10 en BR classé (voir CLAUDE.md)
- Aujourd'hui, les pièces et l'argent de partie sont calculés côté navigateur, donc modifiables par un tricheur.
- En BR classé, l'hôte est déjà le serveur : y faire valider les achats en partie.
- Règle validée par Malo : les pièces ne servent que pendant la partie, **seuls les PR se gardent** d'une partie à l'autre.

## 8. Bots pour compléter les parties classées (à décider)
- Idée : si la file d'attente n'a pas assez de joueurs après X secondes, des bots remplissent la partie.
- Attention : Malo a choisi un BR classé **sans bots** pour l'instant. Ne pas le faire sans son accord, et si on le fait, des bots ne doivent jamais fausser les PR (par exemple, ne pas compter les éliminations de bots).

## 9. Déploiement automatique via GitHub — EN PLACE le 23/10 (dépôt LamoOnGit/oryxo) ; reste : lancer deploy/setup-vps.sh sur le VPS et ajouter les 2 secrets GitHub
- Mettre le projet dans un dépôt GitHub privé (sans `.env`).
- À chaque push sur `main` : GitHub Actions construit `dist/index-oryxo.html` puis l'envoie sur le VPS par SSH (clé de déploiement dédiée, stockée dans les secrets GitHub). Copie dans `/opt/orbit/public/index.html` (+ `server.js` s'il a changé), sauvegarde `.bak`, `systemctl restart orbit`.
- But : pouvoir mettre à jour le jeu sans le Mac.
- Garder ses commandes `deploy` et `rollback` du Mac utilisables.

## 10. Version CrazyGames
- Intégrer le SDK CrazyGames (pubs, début/fin de partie, comptes CrazyGames).
- Leurs règles interdisent de forcer la création de compte : le jeu doit être jouable sans compte (Arène et Entraînement).
- Idée de Malo pour oryxo.eu : 2 parties de BR classé d'essai sans compte, puis compte obligatoire. Sur CrazyGames, adapter (compte CrazyGames ou BR non classé).
- Prévoir une version à part (même code, drapeau `CRAZYGAMES`) : pas de Stripe, pas de liens externes.

## 11. Optionnel
- **Skins animés plus légers** : si ça rame sur les vieux téléphones, réduire la taille des planches en partie (aujourd'hui 176 px par calque, environ 6 Mo de mémoire par skin animé une fois chargé).
- **Sécurité** : faire changer la clé secrète Supabase à Malo (elle est apparue une fois sur une capture), puis mettre à jour `/opt/orbit/.env` sur le VPS et redémarrer `orbit`.

## Badges de quêtes (décidé le 26/10, à faire plus tard)
- Malo **dessinera lui-même** les badges (comme les skins) ; on les intégrera avec un outil de conversion.
- Pas de quêtes du jour / de la semaine pour l'instant.
- Pistes encore ouvertes : vitrine de badges sur la carte joueur, récompenses pour les badges Or, nouvelles quêtes.
