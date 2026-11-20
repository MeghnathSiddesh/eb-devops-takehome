# EB DevOps take-home

Local-only: Docker, kind, kubectl, helm. No cloud account needed.

## Layout

| Path | What |
|---|---|
| `setup.sh` | Part 3 - one-command, idempotent setup |
| `service/` | Part 1 - Python stdlib HTTP service + multi-stage non-root Dockerfile |
| `chart/` | Part 2 - Helm chart (release `demo`, namespace `demo`) |
| `lab/` | Part 4 - debug lab, fixed chart in `lab/broken-chart/`, notes in `lab/FINDINGS.md` |
| `ANSWERS.md` | Part 5 |
| `.github/workflows/ci.yml` | Bonus - helm lint, image build, Trivy (fails on HIGH/CRITICAL) |

## Run it

```bash
./setup.sh        # safe to run repeatedly
```

It creates kind cluster `demo` (ports 80/443 mapped to the host), installs ingress-nginx,
builds `demo-app:1.0.0`, loads it into kind, and installs the chart.

## Verify it works

```bash
kubectl -n demo get pods                                   # 2/2 pods Running and Ready
curl -H 'Host: demo.local' http://localhost/               # {"app": "demo-app", "version": "1.0.0", "pod": "demo-..."}
curl -H 'Host: demo.local' http://localhost/healthz        # ok
# change config at runtime (env vars are read at container start, so roll the pods):
kubectl -n demo patch configmap demo --type merge -p '{"data":{"APP_NAME":"changed","VERSION":"2.0.0"}}'
kubectl -n demo rollout restart deploy/demo && kubectl -n demo rollout status deploy/demo
curl -H 'Host: demo.local' http://localhost/               # now shows "changed" / "2.0.0"
# chart overrides:
helm template demo chart --set replicaCount=3 --set config.appName=x | grep -E 'replicas:|APP_NAME'
```

## Resource requests and limits

| | CPU | Memory |
|---|---|---|
| requests | 50m | 64Mi |
| limits | 200m | 128Mi |

Why: the service is a stdlib Python process that does almost no work per request, so it idles
at a few tens of MB and a sliver of CPU. 64Mi/50m reserves enough for the scheduler to place
it without wasting cluster capacity; 128Mi gives ~2x headroom before an OOM-kill; 200m allows
short bursts (startup, a spike of requests) without letting one pod hog a node. They also match
the LimitRange defaults of the lab namespace, so both parts follow the same convention.
**These are reasoned estimates, not load-tested numbers** - with real traffic I would measure
usage (metrics-server / Prometheus) and tune.

## What I deliberately skipped (and the risk)

- **No TLS on the Ingress.** Traffic is plain HTTP. Risk: fine for local, unacceptable in production (cert-manager would fix it).
- **No PodDisruptionBudget, HPA or anti-affinity.** Risk: a node drain could take both replicas down at once; no autoscaling under load.
- **No NetworkPolicy.** Risk: any pod in the cluster can reach the service.
- **No registry / image signing.** The image is built locally and loaded into kind. Risk: no provenance, no reproducible distribution.
- **ConfigMap changes need a pod restart** (env vars are only read at start). The chart's `checksum/config` annotation makes `helm upgrade` do this automatically, but a raw `kubectl patch` does not. Risk: config drift between ConfigMap and running pods until a restart.
- **ingress-nginx is end-of-life** but the assignment requires it. Risk: no security patches; see `ANSWERS.md` for the migration plan.
- **Image tag is fixed (`1.0.0`).** Re-running `setup.sh` after code changes rebuilds and reloads the image, but already-running pods keep the old one until restarted.

## Production-readiness changes

TLS via cert-manager; real registry with immutable tags/digests and image signing; PDB, HPA
and topology spread constraints; NetworkPolicies; resource tuning from real metrics;
Prometheus metrics and structured logs; secrets from an external secret store; migrate off
ingress-nginx to Gateway API; CI that also runs `helm template | kubeconform` and deploys to
a kind cluster in the pipeline.

## How I used AI


- Tool: gemini. Used for: < reviewing my Dockerfile/chart, drafting setup.sh, ANSWERS.md and the CI workflow, listing the lab's likely defect areas>.
- What I corrected / verified myself: <fill in - e.g. ran setup.sh twice on my machine, fixed X>.
- Part 4: investigation, recording and FINDINGS.md are my own work from my cluster. <adjust if not true>
