# DEPLOY.md: running LectureKit with Docker (written for a beginner)

Follows `doc/DOCKER_DEPLOYMENT_PLAN.md`. One rented Linux server runs Docker Compose with two containers:

| Container | What it does |
|---|---|
| `caddy` | the only part open to the internet (ports 80 and 443): HTTPS certificate (obtained and renewed by itself), upload size limit, forwards everything to `app` |
| `app` | one Python process: the FastAPI server, the job worker (one job at a time), the pipeline (Whisper, ffmpeg, Tesseract, LibreOffice) and, later, the web app files. The **database is SQLite**: the file `data/server.db`, so there is no database container. |

Everything that must survive a restart (database, recordings, slides, transcripts, notes, cache, logs) is in the `data/` folder next to
`docker-compose.yml`. Secrets are only in the `.env` file next to it. The only outside service the app calls is the Claude API, with text only.

---

## A. Try it on your own computer first (about 30 minutes, mostly waiting)

1. Start Docker Desktop and wait until it says it is running.
2. In this folder:
   ```bash
   ./setup.sh                  # clones the three code repositories if they are missing, creates data/ and .env
   nano .env                   # ANTHROPIC_API_KEY, JWT_SECRET (openssl rand -hex 32), and for a local test:
   #   DOMAIN=localhost
   #   HTTP_PORT=8080
   #   HTTPS_PORT=8443
   docker compose up -d --build        # first time: 10 to 20 minutes
   docker compose ps                   # app "healthy", caddy "running"
   curl -k https://localhost:8443/health
   ```
   (`-k` because the certificate for `localhost` comes from Caddy's own local authority.)
3. Check every feature (the API check creates throw-away users and deletes them):
   ```bash
   cd lecturekit-server
   .venv/bin/python scripts/api_check.py --url https://localhost:8443 --insecure \
       --recording ../lecturekit/data/L02/media.mp4 --slides ../lecturekit/data/L02/slides.pdf
   ```
   Without `--recording` only the checks that need no AI run. Interactive API docs: `https://localhost:8443/api/docs`.
   To open the web app at `https://localhost:8443/` without the browser's "Not Secure" warning: `brew install mkcert`, then `./make-local-cert.sh` once
   (it makes the certificate files in `certs/`, trusts them on your computer, asks for your password, and restarts Caddy), then restart the browser.
   On a real server this is not needed: `certs/` stays empty and Caddy gets a Let's Encrypt certificate for your domain by itself (what certbot does).
4. Stop: `docker compose down` (the data stays in `data/`).

---

## B. First deployment on a rented server (the steps you run)

I cannot log in to your server from the workspace, so these steps are yours. Everything was tested locally first (section A).

**Server:** Ubuntu LTS (22.04 or 24.04), minimum 2 vCPU, 4 GB RAM, 40 GB disk; recommended **4 vCPU, 8 GB RAM, 80 GB disk**. Any provider
that gives a plain Ubuntu server with a public IP (a few to about fifteen US dollars a month). Whisper `small` runs on the CPU and needs
about 1 to 2 GB of RAM while it runs; LibreOffice and big uploads need headroom; recordings take disk space.
**Speed:** the laptop ran the whole pipeline at 0.19 x the lecture length; a shared-CPU server will be slower (expect 0.5 to 1 x).
Measure it on day one and write it into the table at the end of this section.

### 1. Server and domain
1. Create the server and note its **public IP address**.
2. DuckDNS (https://www.duckdns.org): sign in, create a name (for example `mylectures`) and set its IP to the server's IP.
   Your domain is `mylectures.duckdns.org`. (Your own domain works too: an `A` record pointing at the IP.)

### 2. Log in, a non-root user, firewall (do this before anything else)
```bash
ssh root@<ip>                                          # or the user your provider gave you
adduser deploy && usermod -aG sudo deploy              # a normal user for daily work
# from YOUR computer, in a second terminal, copy your SSH key to it, and check that this login works:
#   ssh-copy-id deploy@<ip>   then   ssh deploy@<ip>
# only after that works, on the server, turn off password logins (SSH by key only):
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && sudo systemctl restart ssh
sudo ufw allow OpenSSH && sudo ufw allow 80 && sudo ufw allow 443 && sudo ufw --force enable     # only SSH, 80 and 443
sudo apt-get update && sudo apt-get install -y unattended-upgrades                               # security updates by themselves
```
(Also open ports 80 and 443 on your provider's own firewall page, if it has one.)

### 3. Install Docker and the Compose plugin
```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER            # then log out and in again
docker --version && docker compose version
```

### 4. Put the project in `/opt/lecturekit`
```bash
sudo mkdir -p /opt/lecturekit && sudo chown $USER:$USER /opt/lecturekit
```
Then, from your own computer (works with private repositories; nothing to log in to):
```bash
cd ~/Documents/Degree/Research/project
rsync -av --exclude '.venv' --exclude 'data' --exclude 'backups' --exclude 'storage' --exclude 'logs' --exclude '.cache' \
      --exclude 'testing_result' --exclude 'dev_data' --exclude '.env' --exclude '__pycache__' --exclude 'node_modules' \
      ./ deploy@<ip>:/opt/lecturekit/
```
or on the server with git: `git clone <the platform repository URL> /opt/lecturekit && cd /opt/lecturekit && ./setup.sh`
(private repositories need a GitHub login or token on the server). **Never copy a `.env` file**: you create a new one on the server.

### 5. Configure
```bash
cd /opt/lecturekit
mkdir -p data                              # created by you (user id 1000 on Ubuntu), so the container can write to it
cp .env.example .env && chmod 600 .env
nano .env                                  # DOMAIN, ANTHROPIC_API_KEY, JWT_SECRET (Ctrl+O, Enter, Ctrl+X)
openssl rand -hex 32                       # use this output as JWT_SECRET
```
In `.env` also set the email settings:

- **Confirmation email (Gmail).** Turn on 2-Step Verification for the Gmail account, then Google Account > Security > App passwords: create one (16 characters).
  Set `SMTP_HOST=smtp.gmail.com`, `SMTP_PORT=587`, `SMTP_USER=<the gmail address>`, `SMTP_PASSWORD=<the app password>`. Gmail allows about 500 emails a day.
  New accounts get a 6-digit code in this email (valid 10 minutes) and must enter it before they can log in. With `SMTP_HOST` empty the emails are only written to the log (`docker compose logs app`).
- **Google login (optional).** In Google Cloud Console create a project, then APIs & Services > OAuth consent screen (External), then Credentials > Create credentials >
  OAuth client ID > Web application. Add your web app's address under Authorised JavaScript origins (the extension needs its own client of type Chrome extension later).
  Copy the client ID into `GOOGLE_CLIENT_ID`. It is not a secret; with it empty Google login is off.

Also set `APP_MEM_LIMIT` below the server's RAM (for example `3g` on a 4 GB server). If your user is not id 1000 (`id -u`):
`sudo chown -R 1000:1000 data`.

### 6. Build and start
```bash
docker compose build                       # first time: several minutes (it downloads the Whisper model too)
docker compose up -d
docker compose ps                          # app "healthy", caddy "running"
```

### 7. Check the health
```bash
curl https://<your-domain>/health          # {"ok":true,...}: tools present, key set, no secrets shown
```
Caddy gets the certificate by itself the first time (ports 80 and 443 open, the domain pointing at the server).

### 8. First real use
1. Register the first account, then confirm it with the 6-digit code from the email you receive (check spam too):
   ```bash
   curl -X POST https://<your-domain>/api/auth/register -H 'Content-Type: application/json' \
        -d '{"full_name":"Your Name","email":"you@example.com","password":"a long password","accept_terms":true}'
   curl -X POST https://<your-domain>/api/auth/verify-email -H 'Content-Type: application/json' \
        -d '{"email":"you@example.com","code":"123456"}'
   ```
   If no email arrives: `docker compose logs app` shows why (usually a wrong app password), and
   `docker compose exec app python -m server.admin verify-email you@example.com` confirms the address by hand.
2. The checks create their own test accounts and confirm them with `--verify-cmd` (the email code is never in an API reply), which runs the admin
   command on the server over SSH. From your own computer run the checks against the server with the 14-minute test lecture and its slides (this also checks the stage progress,
   notes, quiz, live chunks and deleting):
   ```bash
   cd lecturekit-server
   .venv/bin/python scripts/api_check.py --url https://<your-domain> \
        --recording lecture14.mp4 --slides slides.pdf --clip-seconds 840 \
        --verify-cmd "ssh deploy@<ip> 'cd /opt/lecturekit && docker compose exec -T app python -m server.admin verify-email {email}'"
   .venv/bin/python scripts/smoke.py --url https://<your-domain> --recording lecture14.mp4 --slides slides.pdf
   ```
   The smoke test prints each stage and the time. For the live path add `--live --end 600` (run it with `PYTHONPATH=../lecturekit`).

### 9. Write the measured speed here

| Measurement | Value |
|---|---|
| Server (provider, vCPU, RAM) | |
| 14-minute lecture with slides, whole file: seconds from upload to done | (laptop M3 Pro: about 190 s, ratio 0.22) |
| The same with live chunks: seconds from the last chunk to done | |

---

## C. Updating

```bash
cd /opt/lecturekit
git pull                      # or copy the new files with rsync again
docker compose build app
docker compose up -d          # restarts only what changed; ./data is untouched
```
A job running during the restart is marked `failed: server_restarted`; the user presses retry. Update when nobody is processing a lecture.

## D. Backups and housekeeping

- **Backup:** `./backup.sh` makes a consistent copy of the SQLite database (SQLite's own backup, safe while the server runs) and packs `data/`
  into `backups/lecturekit-<date>.tgz`. Copy that file to another machine: `scp deploy@<ip>:/opt/lecturekit/backups/*.tgz .`
  Daily on the server (`crontab -e`): `0 3 * * * cd /opt/lecturekit && ./backup.sh && find backups -name '*.tgz' -mtime +7 -delete`
- **Restore:** unpack the `.tgz` in a fresh folder next to `docker-compose.yml`, run `mv data/backup.db data/server.db`, then `docker compose up -d`.
- **Disk:** after the notes are ready the server makes a replay copy (faces blurred, at most 720 p) and deletes the original upload; the replay and the screenshots stay until the owner deletes the lecture, up to `MAX_STORAGE_GB` (default 10) per user. Plan the disk for that: about 0.3 to 0.7 GB per hour of video, much less for audio. The picture and replay work runs in a second lane at low CPU priority (`VISUALS_ENABLED=0` switches it off).
  Check `df -h` weekly during the viva period.
- **Logs:** `data/logs` (lecturekit logs and one line per request, no bodies and no secrets); `docker compose logs -f app` for live output.
- **Restart:** both services use `restart: unless-stopped`, so they come back after a server reboot.
- **Certificates:** renewed by Caddy; the `caddy_data` volume must not be deleted.

## E. Security checklist

- [ ] only ports 22, 80 and 443 are open; port 8000 is not published (the compose file only `expose`s it to Caddy)
- [ ] `.env` is `chmod 600`, not in git, not in the image, not printed in logs or `/health`
- [ ] `JWT_SECRET` is random and at least 32 characters (the server refuses to start otherwise)
- [ ] the app container runs as a normal user, not root
- [ ] SSH by key only (password logins off) and `unattended-upgrades` installed (section B2)
- [ ] CORS allows only the web origin and the extension origin (`WEB_ORIGIN`, `EXTENSION_ORIGIN`; same-origin needs neither)
- [ ] upload limits are enforced by Caddy (total size) and by the server (type and size per kind)
- [ ] the API key never goes to a client; the Claude API receives transcript and slide text only, never audio or video
- [ ] registration is open but needs a working email address (confirmed by an emailed code); each account gets 10 lectures per day (`DAILY_LIMIT`), but only when `CHECK_DAILY_LIMIT=true`: it is `false` by default, so **set it to `true` on a real server** or nobody is limited
- [ ] the per-user daily limit (`DAILY_LIMIT`, default 10) protects your Claude credit; keep auto-reload off in the Anthropic console

Owner commands: `docker compose exec app python -m server.admin list-users` and
`docker compose exec app python -m server.admin set-password someone@example.com` (forgotten password).

## F. Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| `https://<domain>` shows a certificate error | the name does not point at the server yet, or port 80 or 443 is blocked (also at the provider). Fix DNS or the firewall, then `docker compose restart caddy` |
| `/health` shows a missing tool | the image build was incomplete: `docker compose build --no-cache app` |
| `app` keeps restarting | `docker compose logs app`: a missing `JWT_SECRET` (32+ characters) is the usual cause |
| Upload fails with 413 | file larger than the Caddy or server limit: raise `MAX_RECORDING_MB` in `.env` **and** `max_size` in `Caddyfile` together, then `docker compose up -d` |
| A job stays "queued" | the worker is busy with a long job (one at a time), or the app restarted: `docker compose logs app` |
| A lecture shows "The AI service failed" | missing key, no credit, rate limit or no outgoing network: check `.env` and the Anthropic console, then retry the lecture |
| "ffmpeg could not read this file" | the recording is damaged or has no audio track |
| Out of memory during Whisper | server too small or `APP_MEM_LIMIT` too low: use 8 GB, or `LK_WHISPER_SIZE=base` |
| Disk full | users' replays: ask them to delete old lectures (Settings shows each user's storage), lower `MAX_STORAGE_GB`, `docker system prune` (unused images), enlarge the disk |
| Permission denied on `data/` | `sudo chown -R 1000:1000 data` |
| PowerPoint or Word slides are refused | the image was built with `WITH_LIBREOFFICE=0`; upload the slides as PDF or rebuild with it set to 1 |
| "database is locked" on a Mac | SQLite on Docker Desktop's shared folders can misbehave; a Linux server does not (it worked in the local tests) |

## G. Acceptance checklist (before the viva)

- [ ] `docker compose up -d` works from a clean server in under 15 minutes following this guide
- [ ] `https://<domain>/health` ok; certificate valid
- [ ] register a new account: the email with the 6-digit code arrives, the code confirms it, login works only after that
- [ ] the verification email and the welcome email arrive and look right
- [ ] the 14-minute lecture with slides: stage progress shown, notes and quiz appear, speed recorded (section B9)
- [ ] quiz answers not visible before submitting; an attempt shows score and explanations
- [ ] a second account cannot see the first account's data
- [ ] restart the server while idle: the data is still there; restart during a job: the job shows failed (`server_restarted`) and retry works
- [ ] the extension (if built) records a short test in chunks and finishes
- [ ] a backup of `data/` restored on another machine opens correctly
- [ ] no secrets in `docker compose logs`, in the image (`docker history`) or in git

`scripts/api_check.py` covers most of these automatically (see section A and B8).

## H. The web app

The web app is in `lecturekit-web/` and is built inside the image (the first stage of `docker/app.Dockerfile`), so `docker compose up -d --build` is all that is needed.
The server serves it at `/` and keeps the API at `/api`: one address, one certificate, no CORS. To work on it, see `lecturekit-web/README.md`.
