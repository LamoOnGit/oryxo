#!/bin/bash
# Oryxo : mise à jour automatique du VPS depuis GitHub (lancé chaque minute par le minuteur systemd oryxo-pull.timer).
# Installé dans /usr/local/sbin/oryxo-pull par deploy/install-pull.sh.
# Si la branche main a changé : copie dist/index-oryxo.html (le jeu), server/server.js et server/public/ (fichiers statiques,
# rien n'est supprimé) dans /opt/orbit, sauvegarde en .bak, redémarre orbit, vérifie /health et remet l'ancienne
# version tout seul si le serveur ne répond pas. Journal : journalctl -u oryxo-pull
set -euo pipefail
SRC=/opt/oryxo-src
APP=/opt/orbit
SERVICE=orbit
MARK=$APP/.deployed-commit
exec 9>/run/oryxo-deploy.lock
flock -n 9 || exit 0
cd "$SRC"
git fetch -q origin main
NEW=$(git rev-parse origin/main)
OLD=$(cat "$MARK" 2>/dev/null || echo aucun)
[ "$NEW" = "$OLD" ] && exit 0
git reset -q --hard "$NEW"
echo "Nouvelle version sur GitHub : ${NEW:0:12} (avant : ${OLD:0:12})"

# le script se met à jour lui-même pour la prochaine fois
install -m 755 "$SRC/deploy/oryxo-pull.sh" /usr/local/sbin/oryxo-pull.new && mv -f /usr/local/sbin/oryxo-pull.new /usr/local/sbin/oryxo-pull

GAME=$SRC/dist/index-oryxo.html
SERVER=$SRC/server/server.js
if ! { [ -s "$GAME" ] && [ -s "$SERVER" ] && grep -qi '<html' "$GAME"; }; then
  echo "Fichiers manquants dans GitHub, rien n'est changé."; echo "$NEW" > "$MARK"; exit 1
fi
NODE=$(command -v node || echo /usr/bin/node)
if ! "$NODE" --check "$SERVER"; then
  echo "server.js a une erreur, rien n'est changé."; echo "$NEW" > "$MARK"; exit 1
fi

cp -a "$APP/public/index.html" "$APP/public/index.html.bak"
cp -a "$APP/server.js" "$APP/server.js.bak"
cp -r --no-preserve=mode,ownership "$SRC/server/public/." "$APP/public/"
cp --no-preserve=all "$GAME" "$APP/public/index.html"
cp --no-preserve=all "$SERVER" "$APP/server.js"
chown -R orbit:orbit "$APP/public"
chown orbit:orbit "$APP/server.js" 2>/dev/null || true
echo "$NEW" > "$MARK"

systemctl restart "$SERVICE" 9>&-
PORT=$(sed -n 's/^[[:space:]]*PORT[[:space:]]*=[[:space:]]*["'\'']\{0,1\}\([0-9]*\).*/\1/p' "$APP/.env" 2>/dev/null | head -1)
PORT=${PORT:-3000}
for i in $(seq 1 20); do
  sleep 1
  if curl -fsS -m 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    sleep 3
    if systemctl is-active --quiet "$SERVICE" 9>&- && curl -fsS -m 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
      echo "En ligne : jeu $(sha256sum "$APP/public/index.html" | cut -c1-12), serveur $(sha256sum "$APP/server.js" | cut -c1-12)"
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
