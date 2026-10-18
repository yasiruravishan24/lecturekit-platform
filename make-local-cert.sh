#!/usr/bin/env bash
# Local HTTPS without the browser's "Not Secure" warning. Run once, from this folder.
#
# Makes a certificate for https://localhost:8443 with mkcert (https://github.com/FiloSottile/mkcert), a small tool that
# creates its own certificate authority on your computer and makes your system and browsers trust it. The files go to
# certs/ (not committed) and Caddy uses them automatically (Caddyfile: import /certs/*.caddy).
# Let's Encrypt (certbot) cannot issue a certificate for "localhost". On a real server with a real domain Caddy gets a
# Let's Encrypt certificate by itself, certs/ stays empty and none of this is needed.
#
# Undo:  rm certs/*  &&  docker compose up -d --force-recreate caddy      (and  mkcert -uninstall  to remove the authority)
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v mkcert >/dev/null 2>&1; then
  echo "mkcert is not installed."
  echo "  macOS:  brew install mkcert"
  echo "  Linux / Windows: see https://github.com/FiloSottile/mkcert#installation"
  exit 1
fi

mkcert -install                                   # asks for your computer's password once: trusts the local authority
mkdir -p certs
mkcert -cert-file certs/localhost.pem -key-file certs/localhost-key.pem localhost 127.0.0.1 ::1
echo 'tls /certs/localhost.pem /certs/localhost-key.pem' > certs/tls.caddy

docker compose up -d --force-recreate caddy
echo "Done. Quit and reopen the browser, then open https://localhost:8443/ (no warning)."
