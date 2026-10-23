# Oryxo.eu

Jeu .io de tanks multijoueur — https://oryxo.eu

- Tout le contexte (organisation, déploiement, Supabase, règles du jeu) : [`CLAUDE.md`](CLAUDE.md)
- Ce qui reste à faire : [`TODO.md`](TODO.md)

## Mettre à jour le jeu

Chaque modification de `src/`, `server/` ou `build.py` poussée sur `main` est construite puis envoyée automatiquement sur le VPS
(voir l'onglet **Actions**). Bouton manuel : Actions → « Déployer sur oryxo.eu » → **Run workflow**.

## Construire à la main

```
npm ci
python3 build.py        # -> dist/index-oryxo.html
```
