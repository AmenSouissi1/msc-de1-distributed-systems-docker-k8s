# MSc DE1 – Distributed Systems: Docker & Local Kubernetes Project

Containerization, hardening, publication and local orchestration of the
[UBC Flask Sample App](https://github.com/ubc/flask-sample-app).

| Item | Value |
|------|-------|
| Author | Amen Souissi – MSc Data Engineering, cohort DE1 |
| GitHub repository | https://github.com/AmenSouissi1/msc-de1-distributed-systems-docker-k8s |
| Docker Hub repository | **https://hub.docker.com/r/amsou/msc-de1-flask-app** |
| Image used for the final Kubernetes deployment | **`amsou/msc-de1-flask-app:1.1.0`** (also tagged `latest`) |
| Previous version (used for the rollback demo) | `amsou/msc-de1-flask-app:1.0.0` |

---

## 1. Objective and architecture

The goal is not to redesign the application but to deliver a clean, secure and
reproducible workflow: **run it locally → containerize it → secure it → publish it → orchestrate it**.

```
                 GitHub repo (code, Dockerfile, compose, k8s manifests, evidence)
                        |
                 docker build  ──>  Trivy scan + Syft SBOM
                        |
                 Docker Hub: amsou/msc-de1-flask-app:{1.0.0, 1.1.0, latest}
                        |
   kind cluster "msc-de1" (Kubernetes in Docker)
   ┌─────────────────────────────────────────────────────────────────┐
   │ control-plane        worker                 worker2             │
   │                      ┌─────────────┐        ┌─────────────┐     │
   │ namespace            │ flask-app   │        │ flask-app   │     │
   │ msc-de1-project      │ pod (1/2)   │        │ pod (2/2)   │     │
   │                      └──────▲──────┘        └──────▲──────┘     │
   │                             └──── Service ─────────┘            │
   │                          flask-app (ClusterIP :80 -> 5000)      │
   │   NetworkPolicy: only pods labelled role=client may connect     │
   └─────────────────────────────────────────────────────────────────┘
                        ▲
        kubectl port-forward svc/flask-app 18080:80  (local access)
```

The application is a small Flask REST API served by **gunicorn** inside a
non-root, read-only **python:3.12-alpine** container.

## 2. Starter application

- Original repository: https://github.com/ubc/flask-sample-app
- Routes: `GET /`, `GET /items`, `GET /items/{item_id}`, `POST /items`
- Added in release 1.1.0: `GET /version` (returns the image version, used to make the rolling update visible)

### Changes made to the original project

| Change | Reason |
|--------|--------|
| `gunicorn==26.2.0` added to `requirements.txt` | Production WSGI server instead of the Flask development server |
| `GET /version` route + `tests/test_version.py` | Visible change for the rolling update / rollback demo (1.1.0) |

All original routes and tests are unchanged.

## 3. Prerequisites

| Tool | Version used |
|------|--------------|
| Git | 2.47 |
| Python | 3.12.7 |
| Docker Desktop (Docker Engine + Compose v2) | Docker 29.3.1 |
| kind | 0.33.0 (node image `kindest/node:v1.37.0`) |
| kubectl | 1.34.1 |
| Trivy | 0.74.0 |
| Syft | 1.51.0 |

Commands below are written for Windows PowerShell; on Linux/macOS replace
`.\venv\Scripts\Activate.ps1` with `source venv/bin/activate` and `curl.exe` with `curl`.

## 4. Run the original application locally (without Docker)

```powershell
git clone https://github.com/AmenSouissi1/msc-de1-distributed-systems-docker-k8s.git
cd msc-de1-distributed-systems-docker-k8s
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
python -m unittest discover tests -v      # 5 tests, OK
python run.py                             # http://127.0.0.1:5000
```

Test from a second terminal:

```powershell
curl.exe -i http://127.0.0.1:5000/
curl.exe -i http://127.0.0.1:5000/items
curl.exe -i -X POST -H "Content-Type: application/json" --data "{\"name\":\"item1\"}" http://127.0.0.1:5000/items
curl.exe -i http://127.0.0.1:5000/items/0
curl.exe -i http://127.0.0.1:5000/items/5    # 404
```

Evidence: `evidence/01-baseline/`.

## 5. Build and run the Docker image

```powershell
docker build --build-arg APP_VERSION=1.1.0 -t amsou/msc-de1-flask-app:1.1.0 .
docker run -d --name flask-app -p 5000:5000 `
  --read-only --cap-drop ALL --security-opt no-new-privileges:true `
  amsou/msc-de1-flask-app:1.1.0
docker ps                                   # STATUS: Up ... (healthy)
curl.exe -i http://127.0.0.1:5000/version   # {"version":"1.1.0"}
docker logs flask-app
docker exec flask-app id                    # uid=10001(app) gid=10001(app)
docker stop flask-app; docker rm flask-app
```

Key Dockerfile choices: official `python:3.12-alpine` base, dependencies copied
before source (layer caching), `pip` removed after install, only `app/` copied,
non-root numeric user `10001:10001`, single exposed port `5000`, Python-based
`HEALTHCHECK` (no curl needed), exec-form `CMD` so gunicorn is PID 1 and receives
`SIGTERM`. Evidence: `evidence/02-docker/`.

> **Why 1 worker + 4 threads?** Items are stored in process memory. Several gunicorn
> worker processes would each hold a different list, so a POST and the following GET
> could hit different processes. Threads share the same memory.

## 6. Run with Docker Compose

```powershell
docker compose up -d --build
docker compose ps          # (healthy)
curl.exe -i http://127.0.0.1:5000/
docker compose down
```

`compose.yaml` includes: port mapping, `restart: unless-stopped`, non-secret
environment variables (overridable through a git-ignored `.env`), health check,
`user: 10001:10001`, `read_only: true` + `tmpfs /tmp`, `cap_drop: ALL`,
`no-new-privileges`, CPU / memory / PID limits. No `privileged`, no Docker socket,
no host networking. Evidence: `evidence/03-compose/`.

## 7. Docker Hub

- Repository: **https://hub.docker.com/r/amsou/msc-de1-flask-app** (public)
- Tags: `1.0.0` (initial release), `1.1.0` (adds `/version`), `latest` (= `1.1.0`)

```powershell
docker pull amsou/msc-de1-flask-app:1.1.0
```

Push → local image removal → pull → run verification: `evidence/04-dockerhub/`.

## 8. Create the kind cluster

```powershell
kind create cluster --config kind/kind-config.yaml   # 1 control-plane + 2 workers
kubectl get nodes -o wide
```

## 9. Deploy the Kubernetes manifests

```powershell
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/
kubectl rollout status deployment/flask-app -n msc-de1-project
kubectl get all -n msc-de1-project -o wide
```

| File | Object | Content |
|------|--------|---------|
| `k8s/namespace.yaml` | Namespace `msc-de1-project` | Pod Security Admission: enforce `baseline`, warn/audit `restricted` |
| `k8s/configmap.yaml` | ConfigMap `flask-app-config` | Non-sensitive config (`APP_ENV`, `TZ`, `GUNICORN_CMD_ARGS`) |
| `k8s/deployment.yaml` | Deployment `flask-app` | 2 replicas, image `1.1.0`, readiness + liveness probes, requests/limits, RollingUpdate `maxSurge 1 / maxUnavailable 0`, topology spread across nodes, full security context |
| `k8s/service.yaml` | Service `flask-app` | ClusterIP, port 80 → container port 5000 |
| `k8s/network-policy.yaml` | NetworkPolicy `flask-app-netpol` | Ingress only from pods labelled `role=client` on TCP 5000; egress only to cluster DNS |

No Secret is needed by the application, so none is created.

## 10. Access and test the application

```powershell
kubectl port-forward -n msc-de1-project svc/flask-app 18080:80
# in another terminal
curl.exe -i http://127.0.0.1:18080/
curl.exe -i http://127.0.0.1:18080/version
```

Port `18080` is used because `8080` was already taken on the test machine.

Service discovery and NetworkPolicy test from inside the cluster:

```powershell
# allowed (label role=client) -> "Hello, Flask!"
kubectl run client-allowed -n msc-de1-project --image=curlimages/curl:8.10.1 --labels="role=client" --restart=Never --rm -i --command -- sh -c "curl -s -m 5 http://flask-app/ || echo BLOCKED"
# denied (no label) -> "BLOCKED"
kubectl run client-denied -n msc-de1-project --image=curlimages/curl:8.10.1 --restart=Never --rm -i --command -- sh -c "curl -s -m 5 http://flask-app/ || echo BLOCKED"
```

Distributed-systems demonstrations:

```powershell
# Self-healing
kubectl delete pod <pod-name> -n msc-de1-project
kubectl get pods -n msc-de1-project -o wide
# Scaling
kubectl scale deployment/flask-app -n msc-de1-project --replicas=3
kubectl scale deployment/flask-app -n msc-de1-project --replicas=2
# Rolling update and rollback
kubectl set image deployment/flask-app -n msc-de1-project flask-app=amsou/msc-de1-flask-app:1.1.0
kubectl rollout status deployment/flask-app -n msc-de1-project
kubectl rollout history deployment/flask-app -n msc-de1-project
kubectl rollout undo deployment/flask-app -n msc-de1-project
```

Evidence: `evidence/05-kubernetes/` and `evidence/06-demos/`.

## 11. Clean up

```powershell
kubectl delete -f k8s/          # optional, removes the objects
kind delete cluster --name msc-de1
docker compose down
docker image rm amsou/msc-de1-flask-app:1.0.0 amsou/msc-de1-flask-app:1.1.0 amsou/msc-de1-flask-app:latest
```

## 12. Security decisions and known limitations

### Security decisions

| Layer | Decision |
|-------|----------|
| Image | Official `python:3.12-alpine`; `pip`/`ensurepip` removed; only `app/` copied; no secrets in any layer; `.dockerignore` excludes Git, venv, caches, IDE files, `.env`, tests, evidence and reports |
| User | Numeric non-root user `10001:10001` in the image, enforced again by Compose (`user`) and Kubernetes (`runAsNonRoot`, `runAsUser`, `runAsGroup`) |
| Filesystem | Read-only root filesystem everywhere (Docker, Compose, Kubernetes); only `/tmp` (tmpfs / memory `emptyDir`) and `/dev/shm` are writable |
| Privileges | All Linux capabilities dropped, `no-new-privileges` / `allowPrivilegeEscalation: false`, `seccompProfile: RuntimeDefault`, no host network/PID/IPC, no hostPath, service-account token not mounted |
| Resources | Compose: 0.5 CPU, 256 MiB, 100 PIDs. Kubernetes: requests 100m / 64Mi, limits 500m / 256Mi |
| Network | NetworkPolicy restricts ingress to `role=client` pods and egress to DNS; enforcement verified on kind |
| Supply chain | Trivy scan and Syft SPDX SBOM in `security/`. Moving from `python:3.12-slim` to `python:3.12-alpine` reduced findings from **44 HIGH / 0 CRITICAL** to **0 HIGH / 0 CRITICAL** (see `security/README.md`) |

### Known limitations

- **In-memory state**: each pod keeps its own item list. With 2 replicas behind the
  Service, an item created on one pod is not visible on the other, and all items are
  lost when a pod restarts. A production version would store items in an external
  database (e.g. PostgreSQL or Redis).
- `kubectl port-forward` and kubelet probes reach the pod through the node, so they
  are not filtered by the NetworkPolicy (expected Kubernetes behaviour).
- `tests/__init__.py` of the original project imports `flask_testing`, which is not in
  `requirements.txt`. It is not triggered by `python -m unittest discover tests`
  and was left unchanged to keep the original project intact.
- kind is a local test cluster only (single machine, no real high availability).

## Repository structure

```
app/                 Flask application (original + /version route)
tests/               Unit tests (original + test_version.py)
Dockerfile           Hardened production image
.dockerignore
compose.yaml         Local execution with Docker Compose
requirements.txt     flask==2.3.3, gunicorn==26.2.0
run.py               Original local launch script
kind/kind-config.yaml
k8s/                 namespace, configmap, deployment, service, network-policy
security/            Trivy scans (before/after), SBOM (SPDX JSON), summary
evidence/            Command outputs for every step (01-baseline ... 06-demos)
```
