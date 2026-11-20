#!/usr/bin/env bash
# One-command setup: kind cluster "demo" + ingress-nginx + image + Helm release "demo".
# Idempotent: safe to run any number of times.
set -euo pipefail

CLUSTER=demo
NAMESPACE=demo
RELEASE=demo
IMAGE_REPO=demo-app
IMAGE_TAG=1.0.0
# Pinned so the setup is reproducible. ingress-nginx is end-of-life, but this
# release's manifests are still published; see README for the migration note.
INGRESS_NGINX_VERSION=controller-v1.12.1
CTX="kind-${CLUSTER}"

cd "$(dirname "$0")"

log()  { printf '\n==> %s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---- 0. prerequisites -------------------------------------------------------
for bin in docker kind kubectl helm curl; do
  command -v "$bin" >/dev/null 2>&1 || die "'$bin' is not installed or not on PATH"
done
docker info >/dev/null 2>&1 || die "the Docker daemon is not running"

# ---- 1. kind cluster (create or reuse) --------------------------------------
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  log "kind cluster '$CLUSTER' already exists - reusing it"
else
  log "creating kind cluster '$CLUSTER'"
  # Config is inline so the repo keeps its required layout. The node label and
  # host port mappings are what the ingress-nginx "kind" manifest expects, and
  # they let `curl http://localhost/` reach the controller.
  kind create cluster --name "$CLUSTER" --wait 120s --config=- <<'KINDCFG'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
KINDCFG
fi
kubectl --context "$CTX" cluster-info >/dev/null

# ---- 2. ingress-nginx -------------------------------------------------------
log "installing ingress-nginx ($INGRESS_NGINX_VERSION)"
kubectl --context "$CTX" apply -f \
  "https://raw.githubusercontent.com/kubernetes/ingress-nginx/${INGRESS_NGINX_VERSION}/deploy/static/provider/kind/deploy.yaml"

log "waiting for the ingress-nginx controller to be ready"
kubectl --context "$CTX" -n ingress-nginx wait --for=condition=Ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=240s

# ---- 3. build + load image --------------------------------------------------
log "building image ${IMAGE_REPO}:${IMAGE_TAG}"
docker build -t "${IMAGE_REPO}:${IMAGE_TAG}" ./service

log "loading image into kind cluster '$CLUSTER'"
kind load docker-image "${IMAGE_REPO}:${IMAGE_TAG}" --name "$CLUSTER"

# ---- 4. install chart -------------------------------------------------------
# The ingress admission webhook can briefly refuse requests right after the
# controller turns Ready, so retry the install a few times.
log "installing Helm release '$RELEASE' into namespace '$NAMESPACE'"
for attempt in 1 2 3 4 5; do
  if helm --kube-context "$CTX" upgrade --install "$RELEASE" ./chart \
       --namespace "$NAMESPACE" --create-namespace \
       --set image.repository="$IMAGE_REPO" --set image.tag="$IMAGE_TAG" \
       --wait --timeout 3m; then
    break
  fi
  [ "$attempt" -eq 5 ] && die "helm install failed after $attempt attempts"
  echo "helm install failed (attempt $attempt/5), retrying in 10s..."
  sleep 10
done

# ---- 5. smoke test ----------------------------------------------------------
log "smoke test through the Ingress (Host: demo.local)"
for i in $(seq 1 30); do
  if out=$(curl -fsS -m 3 -H 'Host: demo.local' http://localhost/ 2>/dev/null); then
    echo "$out"
    log "done - service is reachable"
    exit 0
  fi
  sleep 2
done
echo "WARNING: release installed but http://localhost/ did not answer within 60s." >&2
echo "         Check: kubectl -n ingress-nginx get pods; kubectl -n $NAMESPACE get ingress" >&2
exit 1
