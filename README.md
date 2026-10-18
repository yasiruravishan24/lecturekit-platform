# LectureKit (platform folder)

Starts the whole system with Docker. The three code repositories sit side by side:

```
docker-compose.yml   starts the containers: caddy (HTTPS, forwards everything) and app (server + worker + pipeline; serves the web app)
docker/              the app image (Dockerfile; builds the web app in its first stage)
lecturekit-web/      the web app (Vue 3 + Quasar; own repository: github.com/yasiruravishan24/lecturekit-web)
Caddyfile            HTTPS, upload size limit, forwards everything to app
.env.example         the settings you fill in (the real .env is never committed)
make-local-cert.sh   makes a trusted HTTPS certificate for localhost with mkcert (no "Not Secure" warning), run once
setup.sh             clones the three code repositories below, creates data/ and .env
DEPLOY.md            step-by-step guide: test on your computer, then the internet (follows doc/DOCKER_DEPLOYMENT_PLAN.md)
backup.sh            consistent backup of the database and data/ into backups/
data/                runtime data: the SQLite database, uploads, notes, logs (not committed: back it up)
lecturekit/          the pipeline (own repository: github.com/yasiruravishan24/lecturekit)
lecturekit-server/   the FastAPI server (own repository: github.com/yasiruravishan24/lecturekit-server)
```

Quick start: `./setup.sh`, fill in `.env`, `docker compose up -d --build`. Details in `DEPLOY.md`.
