# Answers

## Q1 — Migrating ~40 Ingresses from ingress-nginx to the Gateway API, zero downtime

My approach would be to run both systems in parallel, migrate traffic gradually, and remove ingress-nginx only after everything is stable.

1. Inventory* Review all 40 Ingress resources and identify NGINX-specific annotations such as rewrites, authentication, timeouts, and body size limits.
2. Setup: Install a Gateway API implementation (Envoy Gateway, Cilium, or Istio) alongside ingress-nginx with a separate LoadBalancer IP.
3. Migration: Convert Ingress resources into Gateway and HTTPRoute configurations. Use `ingress2gateway` as a starting point and manually verify unsupported annotations.
4. Testing: Test all routes, TLS, and application responses using `curl --resolve` against the new LoadBalancer IP.
5. Traffic migration: Shift DNS traffic gradually in small batches while monitoring errors, latency, and logs.
6. Rollback: If issues occur, point DNS back to the old ingress-nginx IP. Keep the existing setup untouched during migration.
7. Cleanup: Decommission ingress-nginx only after confirming the new Gateway is stable.

Potential challenges: NGINX-specific annotations, rewrite rules, authentication, sticky sessions, timeouts, client IP preservation, TLS references, and existing NGINX monitoring dashboards.

## Q1 — Migrating ~40 Ingresses from ingress-nginx to Gateway API with zero downtime

Tool: Claude (Gemini) — used as a reviewer, sounding board

Parts 1 and 2 (such as Service, Dockerfile, Helm Chart): I built and committed these myself step by step before bringing AI into the workflow. The inline comments and notes in service/ are my own working notes from putting the service and chart together.

Parts 3, 5, 6, and CI Bonus: Once the core app and Helm chart were working, I shared the repository and assignment prompt with gemini to draft the initial versions of setup.sh, the README documentation, and the GitHub Actions workflow. I reviewed every generated file line by line, tested ./setup.sh locally on my machine

Part 4 (Debug Lab): I ran the investigation myself on a local kind cluster, so the session logs and FINDINGS.md come directly from my own troubleshooting run. I used AI only to at the last finding which is issues in reporter

Areas I'm Still Strengthening: While I understand the core Kubernetes and Helm mechanics used here, I relied more heavily on documentation and AI explanations for ingress-nginx admission webhook behavior and Gateway API edge cases in Q1. These are areas I am actively digging deeper into ahead of the live session.

