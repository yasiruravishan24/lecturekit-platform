#!/usr/bin/env bash
# Run once after cloning this repository (on your computer or on the server): fetches the three code repositories
# next to docker-compose.yml, creates the data folder and a .env to fill in.
set -euo pipefail
cd "$(dirname "$0")"

fetch() {   # fetch <url> <folder>
  if [ -d "$2/.git" ]; then echo "$2: already here"; else git clone "$1" "$2"; fi
}
fetch https://github.com/yasiruravishan24/lecturekit.git lecturekit
fetch https://github.com/yasiruravishan24/lecturekit-server.git lecturekit-server
fetch https://github.com/yasiruravishan24/lecturekit-web.git lecturekit-web

mkdir -p data certs               # created by you, so the container (user id 1000) can write to it
if [ ! -f .env ]; then
  cp .env.example .env
  chmod 600 .env
  echo "Created .env: open it and fill in ANTHROPIC_API_KEY, JWT_SECRET and DOMAIN."
fi
echo "Next:  docker compose up -d --build"
