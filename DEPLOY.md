# DEPLOY.md: running LectureKit with Docker (written for a beginner)

One command starts everything: `docker compose up -d --build`. Two containers run:

| Container | What it does |
|---|---|
| `app` | the FastAPI server and its worker, with ffmpeg, Tesseract, LibreOffice and the Whisper model inside. The **database is SQLite**: the file `data/server.db`, so there is no separate database container. |
| `caddy` | HTTPS (certificates are obtained and renewed automatically) and routing: `/api/*` and `/health` go to `app`; everything else goes to the web app, once it exists. |

Everything you must keep (database, uploads, notes, logs) is in the `data/` folder next to `docker-compose.yml`.

## A. Try it on your own computer first

1. Start Docker Desktop and wait until it says it is running.
2. In this folder:
   ```bash
   ./setup.sh                  # clones the two code repositories if they are not here yet, creates data/ and .env
   nano .env                   # fill in the four lines at the top (see below), and add these two for a local test:
   #   DOMAIN=localhost
   #   HTTP_PORT=8080
   #   HTTPS_PORT=8443
   docker compose up -d --build        # first time: 10 to 20 minutes (LibreOffice and the Whisper model are large)
   docker compose ps                   # both should be "running", app "healthy"
   curl -k https://localhost:8443/health
   ```
   (`-k` because the certificate for `localhost` comes from Caddy's own local authority.)
3. Check the whole flow with the 14-minute test lecture (needs the API key in `.env`):
   ```bash
   cd lecturekit-server
   .venv/bin/python scripts/smoke.py --url https://localhost:8443 --insecure --invite <INVITE_CODE> \
        --recording lecture14.mp4 --slides slides.pdf
   ```
4. Stop: `docker compose down` (the data stays in `data/`).

What goes in `.env`: `ANTHROPIC_API_KEY` (your Claude key), `JWT_SECRET` (32+ random characters:
`openssl rand -hex 32`), `INVITE_CODE` (any phrase; people need it to register), `DOMAIN`.

## B. Put it on the internet

| Thing | Suggestion |
|---|---|
| Server | Ubuntu 22.04 or 24.04, **4 vCPU, 8 GB RAM, 40 GB disk** (minimum 2 vCPU, 4 GB, 40 GB). Any provider. |
| Domain | a free DuckDNS name (https://www.duckdns.org) pointing at the server's IP address |

### 1. Create the server and point the domain at it
1. Create the Ubuntu server and note its **public IP**. Log in: `ssh <user>@<ip>`.
2. DuckDNS: sign in, create a name (for example `mylectures`), set its IP to the server's IP: `mylectures.duckdns.org`.
3. Open the firewall (keep SSH):
   ```bash
   sudo ufw allow 22 && sudo ufw allow 80 && sudo ufw allow 443 && sudo ufw --force enable
   ```
   (Also open ports 80 and 443 on your provider's own firewall page, if it has one.)

### 2. Install Docker (once)
```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER        # then log out and in again
docker --version && docker compose version
```

### 3. Get the code onto the server
Either, from your own computer (works with private repositories, nothing to log in to):
```bash
cd ~/Documents/Degree/Research/project
rsync -av --exclude '.venv' --exclude 'data' --exclude 'storage' --exclude 'logs' --exclude '.cache' \
      --exclude 'testing_result' --exclude 'dev_data' --exclude '.env' --exclude '__pycache__' --exclude 'node_modules' \
      ./ <user>@<ip>:~/app/
```
or, on the server, with git: `git clone <this repository's URL> ~/app && cd ~/app && ./setup.sh`
(private repositories need a GitHub login or token on the server).
Never copy a `.env` file: you create a new one on the server.

### 4. Configure
```bash
cd ~/app
mkdir -p data                        # the container runs as user id 1000; create it as your own user (id 1000 on Ubuntu)
cp .env.example .env && chmod 600 .env
nano .env                            # ANTHROPIC_API_KEY, JWT_SECRET, INVITE_CODE, DOMAIN (Ctrl+O, Enter, Ctrl+X)
```
If your user is not id 1000 (`id -u`), run `sudo chown -R 1000:1000 data`.

### 5. Build and start
```bash
docker compose up -d --build         # first time: 10 to 20 minutes
docker compose ps
curl https://<your-domain>/health    # {"ok":true,...}
```
Caddy gets the HTTPS certificate by itself (ports 80 and 443 must be open and the domain must point at the server).

### 6. First checks
1. Register the first account:
   ```bash
   curl -X POST https://<your-domain>/api/auth/register -H 'Content-Type: application/json' \
        -d '{"email":"you@example.com","password":"a long password","invite_code":"<INVITE_CODE>"}'
   ```
2. From your own computer, run the smoke test with the 14-minute lecture and its slides:
   ```bash
   cd lecturekit-server && .venv/bin/python scripts/smoke.py --url https://<your-domain> --invite <INVITE_CODE> \
        --recording lecture14.mp4 --slides slides.pdf
   ```
   It prints each stage and the time; **write the total in the table below**.
   For the live (chunk) path add `--live --end 600` (run it with `PYTHONPATH=../lecturekit`).
3. Look at the logs: `docker compose logs app | tail -50` and `grep -c sk-ant data/logs/*` (must print 0 for each file).

| Measurement (fill in on the real server) | Value |
|---|---|
| Server size | |
| 14-minute lecture with slides, whole file: seconds after upload until done | (laptop M3 Pro: about 190 s, ratio 0.22) |
| Same, live chunks (seconds after the last chunk) | |

## C. Everyday commands

```bash
docker compose logs -f app                       # watch the server
docker compose restart app                       # restart (unfinished jobs are marked failed: "server_restarted"; users retry)
docker compose exec app python -m server.admin list-users
docker compose exec app python -m server.admin set-password someone@example.com     # forgotten password
git pull (in lecturekit-server) && docker compose up -d --build      # update after new code
docker compose down                              # stop everything (data stays in ./data)
```

## D. Backups (do this before the viva)

Everything that matters is in `data/`:
```bash
# once, by hand, from your own computer
scp -r <user>@<ip>:~/app/data ./lecturekit-backup-$(date +%F)
# or a daily copy on the server (crontab -e):
0 3 * * * tar czf ~/backup-$(date +\%F).tgz -C ~/app data && find ~ -maxdepth 1 -name 'backup-*.tgz' -mtime +7 -delete
```
Large recordings are deleted `KEEP_MEDIA_DAYS` (default 7) days after a lecture is done; notes, quiz and transcript stay.

## E. Adding the web app later

1. Put the web app in `web/` here, with a `Dockerfile` that builds it and serves the built files with nginx on port 80.
2. In `docker-compose.yml` uncomment the `web:` service.
3. In `Caddyfile` replace the `respond ...` line with `reverse_proxy web:80`.
4. `docker compose up -d --build`. Nothing else changes: the API stays at `/api`, the database and data stay as they are.

## F. If something goes wrong

| Symptom | Likely cause and fix |
|---|---|
| `https://<domain>` does not load, Caddy log says "challenge failed" | the domain does not point at the server yet, or ports 80/443 are closed (also at the provider). Check with `curl http://<ip>`. |
| `app` keeps restarting | `docker compose logs app`: a missing `JWT_SECRET` (32+ characters) or `INVITE_CODE` is the usual cause |
| "database is locked" or odd file errors on a Mac | SQLite on Docker Desktop's shared folders can misbehave; on a Linux server it does not. Test the stack on the server, or tell me. |
| Upload fails with 413 | file above `MAX_RECORDING_MB` (1500); raise it in `.env` **and** `max_size` in `Caddyfile`, then `docker compose up -d` |
| A lecture shows "The AI service failed" | Claude API key wrong or no credit: check the console, then retry the lecture |
| "ffmpeg could not read this file" | the recording is damaged or has no audio track |
| Out of disk | `docker system prune -af` (unused images only), delete data you do not need, `df -h` |
| Permission denied on `data/` | `sudo chown -R 1000:1000 data` |

## G. Security checklist

- `.env` exists only on the server (`chmod 600`), is never committed, never copied by rsync.
- Port 8000 is not published: only Caddy (80/443) is reachable from outside.
- Share the invite code only with people you want as users; change `INVITE_CODE` and `docker compose up -d` to close registration to newcomers.
- Daily limit per user: `DAILY_LIMIT` (default 5 lectures), because every lecture costs Claude credit. Keep auto-reload off in the Anthropic console and watch the balance.

## H. Acceptance checklist (manual)

- [ ] `https://<domain>/health` ok, shows `ANTHROPIC_API_KEY: true` and `queue_length: 0`
- [ ] register with the invite code; a wrong code is refused; login works
- [ ] upload the 14-minute lecture with its slides; the stage progress moves (transcribe, align, filter, notes, quiz)
- [ ] read the notes; the quiz shows no answers; submit the quiz and see the score, correct answers and explanations
- [ ] export the notes as Markdown
- [ ] repeat with live chunks (`--live`)
- [ ] a second account cannot see the first account's lectures
- [ ] delete the session (its files disappear from `data/users/<id>/sessions`)
- [ ] `grep -c sk-ant data/logs/*` prints 0 for every file
