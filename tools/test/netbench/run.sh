#!/bin/bash
# Mesure de fluidité en ligne : construit un build de test, lance faux Supabase + serveur avec ping simulé,
# puis un Battle Royale à 2 joueurs (sbr.js).
#   tools/test/netbench/run.sh [étiquette]        LAG=35 JIT=30 par défaut (ms, aller simple)
#   LAG=15 JIT=3 tools/test/netbench/run.sh stable
# Pré-requis : cd server && npm i ws playwright && npx playwright install chromium
set -e
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
python3 tools/test/mktest.py server/public/index.html >/dev/null
pgrep -f "tools/test/mocksb.js" >/dev/null || nohup node tools/test/mocksb.js > /tmp/oryxo-mock.log 2>&1 < /dev/null &
for p in $(pgrep -f "^node server.js"); do kill -9 "$p"; done; sleep 0.5
MIN_PLAYERS=2 QUEUE_WAIT=2 STATS_PASS=test TEST_LAG=${LAG:-35} TEST_JIT=${JIT:-30} SB_URL=http://127.0.0.1:5599 SB_SECRET=x PORT=3364 \
  nohup bash -c 'cd server && exec node server.js' > /tmp/oryxo-srv.log 2>&1 < /dev/null &
sleep 3
NODE_PATH="$ROOT/server/node_modules${NODE_PATH:+:$NODE_PATH}" timeout 180 node tools/test/netbench/sbr.js "${1:-test}" $2
