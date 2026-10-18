# RC2 local Minikube deployment runbook

This runbook deploys only the verified images listed in
[`release-manifests/v1.0.0-rc.2/images.tsv`](../release-manifests/v1.0.0-rc.2/images.tsv).
It does not rebuild, retag, or publish images.

## Preconditions

- Current context is `minikube` and namespace is `algocrack`.
- The host resolves `algocrack.local` to the Minikube ingress address.
- Google Cloud OAuth has this exact authorized redirect URI:

  `http://algocrack.local/api/v1/auth/login/oauth2/code/google`

- `algocrack-app-secrets` contains the existing database/OAuth keys **and** a
  non-empty `INTERNAL_SERVICE_TOKEN` key. This key was absent in the observed
  cluster inventory, so an operator must add it out of band before deploying.
  Do not place its value in this repository.
- `jwt-signing-keys` retains `private.pem` and `public.pem`.

## Read-only preflight

```bash
kubectl config current-context
kubectl get deploy,svc,ingress,pvc -n algocrack
kubectl get secret algocrack-app-secrets -n algocrack \
  -o go-template='{{range $k, $v := .data}}{{$k}}{{"\n"}}{{end}}'
helm lint ./helm/algocrack -f helm/algocrack/values.local-prod-sim-rc2.yaml
helm template algocrack ./helm/algocrack --namespace algocrack \
  -f helm/algocrack/values.local-prod-sim-rc2.yaml > /tmp/algocrack-rc2.yaml
kubectl apply --server-side --dry-run=server -f /tmp/algocrack-rc2.yaml
```

Never print Secret data values. Save the existing non-secret resource state
before adoption:

```bash
mkdir -p /tmp/algocrack-rc2-backup
kubectl get deploy,svc,ingress,cm,sa,role,rolebinding,pvc -n algocrack -o yaml \
  > /tmp/algocrack-rc2-backup/resources.yaml
kubectl get pvc mysql-data redis-data -n algocrack -o yaml \
  > /tmp/algocrack-rc2-backup/pvc.yaml
```

## Adoption approval gate

The existing objects have no Helm ownership metadata. The following command
will add Helm ownership metadata and reconcile workloads, services, ConfigMaps,
Ingress, RBAC, and the two existing PVC definitions. It must be run only after
reviewing the rendered manifest and backing up the non-secret object state:

```bash
helm upgrade --install algocrack ./helm/algocrack \
  --namespace algocrack \
  --create-namespace \
  --take-ownership \
  -f helm/algocrack/values.local-prod-sim-rc2.yaml
```

This can roll every application Deployment and change the Ingress `/api` target
from `api-gateway:9090` to `waf:8080`. It must not delete the namespace, PVCs,
PVs, Secrets, MySQL data, or Redis data.

The RC2 overlay enables the chart's one-time legacy selector compatibility mode.
The existing Deployment selectors are immutable (`app: <component>`); without
that mode, Helm cannot adopt them and Kubernetes rejects the update. Do not
remove this setting until a separately approved zero-downtime selector
migration has been designed.

## Post-adoption validation

```bash
kubectl rollout status deployment/api-gateway -n algocrack
kubectl rollout status deployment/auth-service -n algocrack
kubectl rollout status deployment/problem-service -n algocrack
kubectl rollout status deployment/submission-service -n algocrack
kubectl rollout status deployment/code-execution-engine -n algocrack
kubectl rollout status deployment/frontend -n algocrack
kubectl rollout status deployment/waf -n algocrack
kubectl get deploy,svc,ingress,pvc -n algocrack
curl -i http://algocrack.local/
curl -i http://algocrack.local/api/v1/questions
curl -i 'http://algocrack.local/api/v1/questions?id=1%27%20OR%20%271%27%3D%271'
kubectl logs deployment/waf -n algocrack --tail=100
```

The malicious query should be rejected by the WAF. Validate normal browser
requests, OAuth with authorized test access, submissions, and CXE separately;
do not run destructive or load tests.

The RC2 overlay trusts Minikube's observed Pod network (`10.244.0.0/16`) for
the WAF `X-Real-IP` source. Re-check the ingress controller networking before
using this overlay on any other cluster; do not broaden this CIDR blindly.

## Rollback and data protection

For an application regression, retain Helm ownership and roll workload images
back to their prior ReplicaSets individually, for example:

```bash
kubectl rollout undo deployment/frontend -n algocrack
kubectl rollout undo deployment/api-gateway -n algocrack
```

For a chart configuration regression, correct the reviewed RC2 values and run
`helm upgrade` again. Do **not** use `helm uninstall`, delete the namespace,
delete PVCs/PVs, or recreate MySQL/Redis. Restore only non-secret manifests
from `/tmp/algocrack-rc2-backup/resources.yaml` if a reviewed rollback requires
it; PVCs and Secrets remain untouched.
