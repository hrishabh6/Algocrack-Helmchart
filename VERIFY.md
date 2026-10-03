# Helm Live Verification Runbook

This runbook is the operational checklist for validating a real AlgoCrack Helm deployment on a live Kubernetes cluster.

Use this after the chart has been fully templated and preflight-validated.

## Goal

Confirm that a real `helm upgrade --install`:

- creates the expected resources
- starts the core workloads successfully
- exposes the expected ingress routes
- behaves correctly for basic cluster health checks

This runbook is written primarily for local Minikube-style validation, but the same flow works for other clusters with small adjustments.

## 1. Cluster Preflight

Confirm that a Kubernetes context is available:

```bash
kubectl config current-context
```

Confirm the cluster is reachable:

```bash
kubectl get nodes
```

If you intend to validate ingress locally, confirm an ingress controller exists:

```bash
kubectl get pods -A | grep -i ingress
```

If you intend to validate HPAs, confirm `metrics-server` exists:

```bash
kubectl get deployment -A | grep metrics-server
```

## 2. Prepare Values

Start from:

- [algocrack/values.minikube.example.yaml](/home/hrishabh/codebases/java/leetcode/helm/algocrack/values.minikube.example.yaml)

Create a local verification file:

```bash
cp helm/algocrack/values.minikube.example.yaml helm/my-values.local.yaml
```

Replace all placeholders with real values:

- `auth.google.clientId`
- `auth.google.clientSecret`
- `auth.jwt.privateKeyPem`
- `auth.jwt.publicKeyPem`
- `mysql.auth.rootPassword`
- `mysql.auth.password`

If you are using local ingress:

- keep `ingress.host=algocrack.local`
- set `auth.google.redirectUri=http://algocrack.local/api/v1/auth/login/oauth2/code/google`
- keep `services.frontend.publicApiBaseUrl=""` for same-origin browser calls

## 3. Preflight Render Checks

Render the chart:

```bash
helm template algocrack ./helm/algocrack -f helm/my-values.local.yaml
```

Lint the chart:

```bash
helm lint ./helm/algocrack -f helm/my-values.local.yaml
```

Expected result:

- `helm template` succeeds
- `helm lint` succeeds

## 4. Install or Upgrade

Install into the target namespace:

```bash
helm upgrade --install algocrack ./helm/algocrack \
  -f helm/my-values.local.yaml \
  --namespace algocrack \
  --create-namespace
```

Check release state:

```bash
helm status algocrack -n algocrack
```

Expected result:

- release status should become `deployed`

## 5. Workload Verification

Watch pods until they settle:

```bash
kubectl get pods -n algocrack -w
```

Once stable, inspect:

```bash
kubectl get deploy,svc,ingress,pvc -n algocrack
```

Expected workloads:

- `mysql`
- `redis`
- `auth-service`
- `problem-service`
- `submission-service`
- `code-execution-engine`
- `api-gateway`
- `frontend`

Expected services:

- `mysql`
- `redis`
- `auth-service`
- `problem-service`
- `submission-service`
- `code-execution-engine`
- `api-gateway`
- `frontend`

Expected PVCs:

- `mysql-data`
- `redis-data`

## 6. Health and Startup Checks

If any pod is not ready:

```bash
kubectl describe pod <pod-name> -n algocrack
kubectl logs <pod-name> -n algocrack
```

Most important things to verify:

- JWT secret mounts resolve properly for `auth-service` and `api-gateway`
- MySQL and Redis become ready
- service startup probes pass
- `code-execution-engine` starts in the expected worker mode

## 7. Ingress Verification

Check ingress:

```bash
kubectl get ingress -n algocrack
kubectl describe ingress algocrack -n algocrack
```

Expected routing:

- `/` -> `frontend:3000`
- `/api` -> `api-gateway:9090`

If using Minikube locally, map the ingress host:

```text
127.0.0.1 algocrack.local
```

Then verify:

```bash
curl -I http://algocrack.local/
curl -I http://algocrack.local/api
```

## 8. Port-Forward Fallback

If ingress is not available yet:

```bash
kubectl port-forward svc/frontend 3000:3000 -n algocrack
kubectl port-forward svc/api-gateway 9090:9090 -n algocrack
```

Then check:

- frontend on `http://localhost:3000`
- gateway on `http://localhost:9090`

## 9. Optional HPA Verification

If you want to validate autoscaling object creation:

```bash
helm upgrade --install algocrack ./helm/algocrack \
  -f helm/my-values.local.yaml \
  --namespace algocrack \
  --create-namespace \
  --set services.apiGateway.autoscaling.enabled=true \
  --set services.codeExecutionEngine.autoscaling.enabled=true \
  --set services.frontend.autoscaling.enabled=true
```

Then check:

```bash
kubectl get hpa -n algocrack
```

Expected HPAs:

- `api-gateway`
- `code-execution-engine`
- `frontend`

Note:

- HPA runtime behavior depends on a working `metrics-server`

## 10. Uninstall and Cleanup

Remove the release:

```bash
helm uninstall algocrack -n algocrack
```

Optional namespace cleanup:

```bash
kubectl delete namespace algocrack
```

## 11. Verification Exit Criteria

Consider live verification successful when:

1. `helm upgrade --install` completes with `deployed`
2. all expected Deployments become ready
3. MySQL and Redis PVCs bind successfully
4. ingress or port-forward access works
5. no core service is stuck in crash loop or failed probe state

## 12. Known High-Value Failure Checks

If verification fails, check these first:

1. invalid or placeholder Google/JWT/MySQL values
2. ingress controller not installed
3. metrics-server missing when validating HPAs
4. image pull failures
5. JWT secret mount path issues in `auth-service` or `api-gateway`
6. MySQL/Redis readiness problems delaying dependent services
