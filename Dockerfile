# Image officielle Python, variante Alpine : choisie apres le scan Trivy
# (la variante slim/Debian contenait 44 HIGH dans des paquets OS inutiles a l'app)
FROM python:3.12-alpine

# Version applicative, exposee par la route /version
ARG APP_VERSION=1.1.0

LABEL org.opencontainers.image.title="msc-de1-flask-app" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.source="https://github.com/AmenSouissi1/msc-de1-distributed-systems-docker-k8s"

# Pas de .pyc (compatible filesystem read-only), logs non bufferises, pas de cache pip
ENV APP_VERSION=${APP_VERSION} \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Utilisateur systeme non-root, sans home ni shell de connexion
RUN addgroup -S -g 10001 app \
 && adduser -S -u 10001 -G app -H -s /sbin/nologin app

# Dependances d'abord (cache des layers), puis suppression de pip (inutile au runtime)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
 && pip uninstall -y pip \
 && rm -rf /root/.cache /usr/local/lib/python3.12/ensurepip

# Seul le code applicatif est copie, possede par root donc non modifiable par l'app
COPY app/ ./app/

# UID numerique : permet a Kubernetes de verifier runAsNonRoot
USER 10001:10001

EXPOSE 5000

# Healthcheck en Python pur (pas besoin d'installer curl)
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:5000/', timeout=2).status == 200 else 1)"]

STOPSIGNAL SIGTERM

# Forme exec : gunicorn est PID 1 et recoit SIGTERM directement.
# 1 worker + threads car les items sont stockes en memoire du processus.
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "1", "--threads", "4", "--worker-tmp-dir", "/dev/shm", "--access-logfile", "-", "--error-logfile", "-", "app:app"]
