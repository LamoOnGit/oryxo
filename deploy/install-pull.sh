#!/bin/bash
# Oryxo : installe la mise à jour automatique depuis GitHub (à lancer UNE fois, en root, après le clone dans /opt/oryxo-src).
# Ensuite, chaque push sur main est en ligne en moins d'une minute (minuteur oryxo-pull.timer).
set -euo pipefail
SRC=/opt/oryxo-src
git -C "$SRC" config core.sshCommand "ssh -i /root/.ssh/oryxo_pull -o StrictHostKeyChecking=accept-new"
install -m 755 "$SRC/deploy/oryxo-pull.sh" /usr/local/sbin/oryxo-pull
cat > /etc/systemd/system/oryxo-pull.service <<'EOF'
[Unit]
Description=Oryxo : mise a jour depuis GitHub
After=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/oryxo-pull
EOF
cat > /etc/systemd/system/oryxo-pull.timer <<'EOF'
[Unit]
Description=Oryxo : regarde GitHub chaque minute
[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now oryxo-pull.timer
echo "Mise à jour automatique installée. Première mise en ligne en cours…"
/usr/local/sbin/oryxo-pull || true
echo "C'est fini. Tape : exit"
