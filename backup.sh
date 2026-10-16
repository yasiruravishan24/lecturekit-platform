#!/usr/bin/env bash
# Consistent backup of everything that matters (DOCKER_DEPLOYMENT_PLAN.md section 12). Run from this folder, with the stack running:
#   ./backup.sh
# 1. asks SQLite for a consistent copy of the database (a plain file copy of a live database can be inconsistent),
# 2. packs data/ (uploads, transcripts, notes, logs) with that copy into backups/lecturekit-<date>.tgz.
# To restore: unpack the .tgz into a fresh folder, then   mv data/backup.db data/server.db   and start the stack there.
set -euo pipefail
cd "$(dirname "$0")"

docker compose exec -T app python - <<'PY'
import sqlite3
src = sqlite3.connect("/data/server.db")
dst = sqlite3.connect("/data/backup.db")
src.backup(dst)
dst.close()
src.close()
print("database copied consistently to data/backup.db")
PY

mkdir -p backups
out="backups/lecturekit-$(date +%F-%H%M).tgz"
# the live database files are left out: backup.db is the consistent copy; the LLM reply cache is rebuilt when needed
tar czf "$out" --exclude='data/server.db' --exclude='data/server.db-shm' --exclude='data/server.db-wal' --exclude='data/cache' data
echo "wrote $out ($(du -h "$out" | cut -f1))"
