# LectureKit (platform folder)

Starts the whole system with Docker. Three folders sit side by side:

```
docker-compose.yml   starts the containers (caddy for HTTPS and routing, app for the server; the web app is added later)
docker/              the app image (Dockerfile)
Caddyfile            routing: /api and /health -> app, everything else -> the web app (later)
.env.example         the settings you fill in (the real .env is never committed)
setup.sh             clones the two code repositories below, creates data/ and .env
DEPLOY.md            step-by-step guide: test on your computer, then the internet
data/                runtime data: the SQLite database, uploads, notes, logs (not committed: back it up)
lecturekit/          the pipeline (own repository: github.com/yasiruravishan24/lecturekit)
lecturekit-server/   the FastAPI server (own repository: github.com/yasiruravishan24/lecturekit-server)
```

Quick start: `./setup.sh`, fill in `.env`, `docker compose up -d --build`. Details in `DEPLOY.md`.
