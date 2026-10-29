# Mesures de fluidité en ligne

- `run.sh [étiquette]` : build de test + faux Supabase + serveur avec ping simulé (`LAG`, `JIT` en ms) + BR à 2 joueurs. Affiche, pour un tank qui roule tout droit : écart à la ligne droite et pire à-coup (chez le joueur et vu par l'autre), recalage max, délai d'affichage, ping.
- `det.js` (serveur lancé avec le build de test) : l'hôte et la prédiction du joueur doivent donner la même position (au 1/100 px).
- Références (28-29/10/2026, `LAG=35 JIT=30`) : toi à-coup ≈ 0,3-0,5 px · vu par l'autre à-coup ≈ 0,3-0,6 px · recalage max ≈ 5 px.
- Mesures bruitées : 2-3 lancers, comparer les médianes, ne jamais lancer deux mesures en même temps.
