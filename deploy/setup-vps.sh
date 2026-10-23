#!/bin/bash
# Oryxo : installation du déploiement automatique (GitHub Actions -> VPS). À lancer UNE SEULE FOIS sur le VPS :
#   connecté en ubuntu@57.129.178.141, colle tout ce fichier dans le terminal, puis Entrée.
# Ce que ça fait :
#   1. installe /usr/local/sbin/oryxo-deploy (le script qui reçoit et installe une nouvelle version) ;
#   2. autorise l'utilisateur ubuntu à lancer CE script (et lui seul) en administrateur ;
#   3. crée une clé réservée à GitHub : elle ne peut QUE déployer (pas de terminal, pas d'autre commande) ;
#   4. affiche les 2 valeurs à copier dans GitHub (Settings -> Secrets and variables -> Actions).
set -e
sudo tee /usr/local/sbin/oryxo-deploy >/dev/null <<'ORYXO_DEPLOY_EOF'
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
ORYXO_DEPLOY_EOF
sudo chown root:root /usr/local/sbin/oryxo-deploy && sudo chmod 755 /usr/local/sbin/oryxo-deploy
echo 'ubuntu ALL=(root) NOPASSWD: /usr/local/sbin/oryxo-deploy' | sudo tee /etc/sudoers.d/oryxo-deploy >/dev/null
sudo chmod 440 /etc/sudoers.d/oryxo-deploy && sudo visudo -cf /etc/sudoers.d/oryxo-deploy >/dev/null
mkdir -p ~/.ssh && chmod 700 ~/.ssh
[ -f ~/.ssh/oryxo_github ] || ssh-keygen -q -t ed25519 -N '' -C 'github-actions-oryxo' -f ~/.ssh/oryxo_github
touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
grep -q 'github-actions-oryxo' ~/.ssh/authorized_keys || echo "command=\"sudo -n /usr/local/sbin/oryxo-deploy\",restrict $(cat ~/.ssh/oryxo_github.pub)" >> ~/.ssh/authorized_keys
IP=$(curl -fsS -m 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
echo
echo "===== Secret 1 : VPS_SSH_KEY  (copie tout, de -----BEGIN à -----END… compris) ====="
cat ~/.ssh/oryxo_github
echo
echo "===== Secret 2 : VPS_KNOWN_HOSTS  (une seule ligne) ====="
echo "$IP $(cut -d' ' -f1,2 /etc/ssh/ssh_host_ed25519_key.pub)"
echo
echo "Installation terminée. Après avoir copié ces 2 valeurs dans GitHub, tape : clear"
