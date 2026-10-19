# The app image: the FastAPI server + worker with everything the pipeline needs (ffmpeg, Tesseract, LibreOffice,
# the Whisper model). The database is SQLite: a file (data/server.db) in the /data volume, so no database container.
# Follows doc/DOCKER_DEPLOYMENT_PLAN.md: one app process, FastAPI serves the web app files itself.
#
# Build context = the folder that holds lecturekit/ and lecturekit-server/ side by side (the compose file sets it):
#   docker build -f docker/app.Dockerfile .
#
# ---- stage 1: build the web app (Node stays out of the final image) ----
FROM node:22-slim AS web
WORKDIR /web
COPY lecturekit-web/package.json lecturekit-web/package-lock.json ./
RUN npm ci
COPY lecturekit-web/index.html lecturekit-web/vite.config.js ./
COPY lecturekit-web/public ./public
COPY lecturekit-web/src ./src
RUN npm run build                                  # output: /web/dist

# ---- the app ----
FROM python:3.12-slim

ENV LK_QUIZ_CODE_BLOCKS=1 LK_QUIZ_REVIEW=1 \
    PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 DEBIAN_FRONTEND=noninteractive \
    HF_HOME=/opt/hf HOME=/home/app DATA_DIR=/data WEB_DIST=/app/web/dist

# WITH_LIBREOFFICE=0 leaves LibreOffice out (about 500 MB smaller): the server then asks for slides as PDF
ARG WITH_LIBREOFFICE=1

# ffmpeg (decode audio), tesseract (OCR), LibreOffice Impress/Writer (PowerPoint and Word slides to PDF)
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg tesseract-ocr fonts-dejavu-core \
    && if [ "$WITH_LIBREOFFICE" = "1" ]; then apt-get install -y --no-install-recommends libreoffice-impress libreoffice-writer; fi \
    && rm -rf /var/lib/apt/lists/*

# an unprivileged user: LibreOffice runs on user files, so it gets no extra rights
RUN useradd --create-home --uid 1000 app && mkdir -p /data /app && chown app:app /data /app

WORKDIR /app
COPY lecturekit/requirements.txt /tmp/lecturekit-requirements.txt
COPY lecturekit-server/requirements.txt /tmp/server-requirements.txt
RUN pip install -r /tmp/lecturekit-requirements.txt -r /tmp/server-requirements.txt

# download the Whisper model now, so the first lecture does not wait for it
RUN python -c "from faster_whisper import WhisperModel; WhisperModel('small', device='cpu', compute_type='int8')" \
    && chmod -R a+rX /opt/hf

# the face detector (OpenCV YuNet, 230 KB) used to blur faces in pictures and replays; checked against its known SHA-256
RUN python -c "import hashlib, urllib.request; u='https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx'; d=urllib.request.urlopen(u, timeout=60).read(); assert hashlib.sha256(d).hexdigest()=='8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4', 'face model checksum differs'; import os; os.makedirs('/opt/models', exist_ok=True); open('/opt/models/face_detection_yunet_2023mar.onnx','wb').write(d)"
# the face recogniser (OpenCV SFace, 37 MB): finds the presenter, whose face stays clear in the replay
RUN python -c "import hashlib, urllib.request; u='https://github.com/opencv/opencv_zoo/raw/main/models/face_recognition_sface/face_recognition_sface_2021dec.onnx'; d=urllib.request.urlopen(u, timeout=120).read(); assert hashlib.sha256(d).hexdigest()=='0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79', 'face recogniser checksum differs'; open('/opt/models/face_recognition_sface_2021dec.onnx','wb').write(d)" \
    && chmod -R a+rX /opt/models

COPY lecturekit/lecturekit /app/lecturekit
COPY lecturekit-server/server /app/server
COPY --from=web /web/dist /app/web/dist

USER app
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=4)"

# ONE worker process: a second one would break the single job queue (SERVER_PLAN.md section 10.1)
CMD ["uvicorn", "server.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
