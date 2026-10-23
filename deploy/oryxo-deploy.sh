#!/bin/bash
# Oryxo : déploiement envoyé par GitHub Actions.
# Installé sur le VPS dans /usr/local/sbin/oryxo-deploy (par deploy/setup-vps.sh).
# Reçoit sur l'entrée standard une archive .tar.gz contenant :
#   index.html   -> /opt/orbit/public/index.html
#   server.js    -> /opt/orbit/server.js
#   public/...   -> /opt/orbit/public/ (fichiers statiques : skins, pages légales… rien n'est supprimé)
# Sauvegarde en .bak (comme la commande deploy du Mac), redémarre orbit, vérifie /health,
# et remet l'ancienne version tout seul si le serveur ne répond pas.
set -euo pipefail
APP=/opt/orbit
SERVICE=orbit
exec 9>/run/oryxo-deploy.lock
flock -n 9 || { echo "Un déploiement est déjà en cours."; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

head -c 300000000 | tar -xz -C "$TMP" --no-same-owner --no-same-permissions
[ -s "$TMP/index.html" ] && [ -s "$TMP/server.js" ] || { echo "Archive incomplète, rien n'est changé."; exit 1; }
grep -qi '<html' "$TMP/index.html" || { echo "index.html invalide, rien n'est changé."; exit 1; }
NODE=$(command -v node || echo /usr/bin/node)
"$NODE" --check "$TMP/server.js" || { echo "server.js a une erreur de syntaxe, rien n'est changé."; exit 1; }

# sauvegardes
cp -a "$APP/public/index.html" "$APP/public/index.html.bak"
cp -a "$APP/server.js" "$APP/server.js.bak"

# fichiers statiques puis jeu + serveur (cp sur un fichier existant garde son propriétaire)
if [ -d "$TMP/public" ]; then
  cp -r --no-preserve=mode,ownership "$TMP/public/." "$APP/public/"
  chown -R orbit:orbit "$APP/public"
fi
cp --no-preserve=all "$TMP/index.html" "$APP/public/index.html"
cp --no-preserve=all "$TMP/server.js" "$APP/server.js"
chown orbit:orbit "$APP/public/index.html"

systemctl restart "$SERVICE" 9>&-
PORT=$(sed -n 's/^[[:space:]]*PORT[[:space:]]*=[[:space:]]*["'\'']\{0,1\}\([0-9]*\).*/\1/p' "$APP/.env" 2>/dev/null | head -1)
PORT=${PORT:-3000}
for i in $(seq 1 20); do
  sleep 1
  if curl -fsS -m 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    # il répond : on revérifie un peu plus tard (un serveur qui plante juste après le démarrage ne doit pas passer)
    sleep 3
    if systemctl is-active --quiet "$SERVICE" 9>&- && curl -fsS -m 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
      echo "Déploiement réussi : le jeu répond sur le port $PORT."
      exit 0
    fi
    break
  fi
done

echo "Le serveur ne répond pas après la mise à jour : retour à la version précédente."
cp -a "$APP/public/index.html.bak" "$APP/public/index.html"
cp -a "$APP/server.js.bak" "$APP/server.js"
systemctl restart "$SERVICE" 9>&-
exit 1
