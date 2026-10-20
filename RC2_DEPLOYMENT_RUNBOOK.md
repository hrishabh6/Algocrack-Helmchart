# RC2 local Minikube deployment runbook

This runbook deploys only the verified images listed in
[`release-manifests/v1.0.0-rc.2/images.tsv`](../release-manifests/v1.0.0-rc.2/images.tsv).
It does not rebuild, retag, or publish images. RC2 is not deployed until the
adoption command below is run on purpose.

## Preconditions

- Current context is `minikube`. Namespace `algocrack` already exists.
- `algocrack-app-secrets` already contains a non-empty `INTERNAL_SERVICE_TOKEN`
  (observed 2026-10-18, 64 bytes). Do not rotate it. Do not put the value in
  this repository, a shell command, or a log.
- `jwt-signing-keys` retains `private.pem` and `public.pem`.
- Google Cloud Console has this exact authorized redirect URI on the existing
  OAuth client. This is a manual console change, not a repository change, and
  it does not require a new OAuth client:

  `http://localhost:3000/api/v1/auth/login/oauth2/code/google`

- The browser entry point is `http://localhost:3000` through the port-forward
  in the next section. `http://algocrack.local` is not a valid Google HTTP
  redirect URI, and the published auth image only accepts post-login targets
  that start with `http://localhost:3000`.

## Local access

Google's web-server redirect rules require HTTPS except for localhost
([OAuth 2.0 for Web Server Applications](https://developers.google.com/identity/protocols/oauth2/web-server)).
`.local` is not a public-suffix host, so `http://algocrack.local/...` cannot be
registered. The published auth image also hardcodes its post-login allowlist to
`http://localhost:3000`.

Port-forward the ingress controller onto local port 3000. Ingress matches the
hostname without the port, so `Host: localhost:3000` matches `host: localhost`.
Do not use `minikube tunnel` on port 80: that origin is `http://localhost`,
which fails the auth image's allowlist. Do not port-forward the ingress
controller while the Ingress host is still `algocrack.local`; the Host header
would not match.

```bash
kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 3000:80
```

Leave that process running, then open `http://localhost:3000`.

| Path | Route |
| --- | --- |
| `/` | `frontend:3000` |
| `/api` | `waf:8080` → `api-gateway:9090` |

No authorized JavaScript origin is required. Sign-in is a server-side
authorization-code redirect, not Google Identity Services in the browser.

After Google returns, the auth service stores the session and `redirect_uri`
cookies on `localhost` (path `/`, not `Secure`). The `leetoken` cookie in the
published image is `Secure`, so browsers drop it on HTTP. The frontend does not
use that cookie: it reads the `token` query parameter and stores it in
`localStorage`.

OAuth callback blocking by the WAF has not been runtime-tested. The published
WAF image forwards `Set-Cookie`, does not rewrite `Location`, and applies a
2 request/second auth limit with burst 5.

## INTERNAL_SERVICE_TOKEN

Problem Service, Submission Service, and CXE all read `INTERNAL_SERVICE_TOKEN`
from `algocrack-app-secrets`. Problem Service and Submission Service send or
require the header `X-Internal-Service-Token`. No other service validates the
token. The live key is already present, so do not generate a replacement.

Confirm presence without printing the value:

```bash
kubectl get secret algocrack-app-secrets -n algocrack \
  -o go-template='{{with index .data "INTERNAL_SERVICE_TOKEN"}}{{if .}}present{{else}}missing{{end}}{{else}}missing{{end}}{{"\n"}}'
```

Expected output is `present`. If it is `missing`, stop and ask before patching
the Secret. The patch below preserves every other key, writes the new value
only through mode-0600 files, and does nothing when the key already exists.

```bash
umask 077
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if kubectl get secret algocrack-app-secrets -n algocrack \
  -o go-template='{{with index .data "INTERNAL_SERVICE_TOKEN"}}{{if .}}present{{end}}{{end}}{{"\n"}}' \
  | grep -qx present; then
  echo "INTERNAL_SERVICE_TOKEN already present; not rotating"
  exit 0
fi
python3 - "$work" << 'PY'
import base64, json, pathlib, secrets, sys
work = pathlib.Path(sys.argv[1])
token = secrets.token_urlsafe(48).encode()
(work / "token").write_bytes(token)
patch = {"data": {"INTERNAL_SERVICE_TOKEN": base64.b64encode(token).decode()}}
(work / "patch.json").write_text(json.dumps(patch))
PY
chmod 600 "$work/token" "$work/patch.json"
kubectl patch secret algocrack-app-secrets -n algocrack --type merge --patch-file "$work/patch.json"
```

Do not print `$work/token` or `$work/patch.json`. The temporary directory is
removed when the script exits.

## MySQL backup

Saving YAML is not a database backup. The live databases are small (about 1 MB
of table data on 2026-10-18: `auth_db`, `problem_db`, `submission_db`). The
host has more than 100 GB free. Take this logical backup before adoption. It
uses `--single-transaction` and the password already injected into the MySQL
pod. Do not pass the password with `-p`.

```bash
umask 077
backup_dir="${HOME}/algocrack-backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup_dir"
chmod 700 "$backup_dir"
kubectl exec -n algocrack deploy/mysql -- sh -c \
  'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysqldump --protocol=TCP -h 127.0.0.1 -u root --single-transaction --routines --events --triggers --all-databases' \
  > "$backup_dir/mysql-all.sql"
chmod 600 "$backup_dir/mysql-all.sql"
grep -E '^CREATE DATABASE' "$backup_dir/mysql-all.sql"
```

The dump is valid when that grep lists `auth_db`, `problem_db`, and
`submission_db`, and the `kubectl exec` exit code is 0.

Do not restore this dump onto the running instance. To rehearse a restore,
load it into a separate temporary MySQL process or another namespace, then
check those three databases. A live restore would require an explicit decision
to replace current data.

Redis has AOF enabled on `redis-data` (about 232 KB). It holds execution queue
and status, not user accounts or submissions. A separate Redis backup is not
required for user data. The PVC retain annotation below is the protection.

Also save non-secret manifests:

```bash
mkdir -p "$backup_dir"
kubectl get deploy,svc,ingress,cm,sa,role,rolebinding,pvc -n algocrack -o yaml \
  > "$backup_dir/resources.yaml"
chmod 600 "$backup_dir/resources.yaml"
```

## Chart safeguards

- Both PVC templates set `helm.sh/resource-policy: keep`.
- The RC2 overlay sets `namespace.create: false`, so Helm does not own the
  namespace. `helm uninstall` therefore cannot delete the namespace.
- The overlay pins both claims to StorageClass `standard`, matching the live
  10 GiB and 2 GiB claims. The Minikube class reclaim policy is `Delete`:
  deleting a claim deletes its volume. Do not delete `mysql-data`,
  `redis-data`, or their Bound PVs. Several older PVs are `Released`; leave
  those in place as well.
- The chart renders no Secret and no Helm hook.
- MySQL init SQL is `CREATE DATABASE IF NOT EXISTS` and runs only on an empty
  data directory. The current data directory is already populated.

`helm uninstall` still deletes Helm-owned Deployments, Services, Ingress,
ConfigMaps, and RBAC. The application would go down, and the PVCs, namespace,
and Secrets would remain. Re-running the adoption command mounts the same
claims again. Do not use uninstall as rollback.

There is no Helm revision yet. After the first install, `helm rollback` returns
to a previous Helm revision. It cannot restore the pre-Helm objects. For a bad
application image after adoption, undo that Deployment:

```bash
kubectl rollout undo deployment/frontend -n algocrack
kubectl rollout undo deployment/api-gateway -n algocrack
```

Repeat per Deployment that regressed. For a bad chart value, fix the overlay
and run `helm upgrade` again with the same flags. Do not delete PVCs, PVs, or
the namespace.

## Read-only preflight

```bash
kubectl config current-context
kubectl get deploy,svc,ingress,pvc -n algocrack
helm lint ./helm/algocrack -f helm/algocrack/overlays/releases/values.local-prod-sim-rc2.yaml
helm template algocrack ./helm/algocrack --namespace algocrack \
  -f helm/algocrack/overlays/releases/values.local-prod-sim-rc2.yaml > /tmp/algocrack-rc2.yaml
kubectl apply --server-side --dry-run=server -f /tmp/algocrack-rc2.yaml
```

Kubernetes prints non-fatal warnings about migrating
`kubectl.kubernetes.io/last-applied-configuration`. A successful dry run still
lists every resource as server-side applied and does not persist changes.
Remove `/tmp/algocrack-rc2.yaml` afterward. Do not treat lint or dry-run as a
runtime test of OAuth, submissions, or WAF blocking.

## Adoption approval gate

Existing objects have no Helm ownership. This command adds that ownership and
rolls the application images from `latest` to `v1.0.0-rc.2`. It also moves
Ingress `/api` from `api-gateway:9090` to `waf:8080` and creates the WAF and
monitoring workloads. It updates PVC metadata in place. It must not delete the
namespace, PVCs, PVs, Secrets, or database files.

```bash
helm upgrade --install algocrack ./helm/algocrack \
  --namespace algocrack \
  --create-namespace \
  --take-ownership \
  -f helm/algocrack/overlays/releases/values.local-prod-sim-rc2.yaml
```

`--create-namespace` is a no-op while `algocrack` exists. The chart itself does
not render a Namespace.

The overlay keeps `adoption.legacySelectors: true`. The live selectors are the
immutable `app: <component>` labels. Do not remove that setting until a
separately approved selector migration exists.

Rendered application images must all be `v1.0.0-rc.2` with `IfNotPresent`.
MySQL stays `mysql:8.0` and Redis stays `redis:7-alpine`. No application image
uses `latest`.

Chart requests are about 1.4 CPU and 3.2 GiB. The Minikube node has 16 CPU and
about 15.7 GiB allocatable. Monitoring pods do not set requests. This fits the
node. CXE Jobs created during submissions are extra and short-lived.

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
curl -i http://localhost:3000/
curl -i http://localhost:3000/api/v1/questions
curl -i 'http://localhost:3000/api/v1/questions?id=1%27%20OR%20%271%27%3D%271'
kubectl logs deployment/waf -n algocrack --tail=100
```

Run those curls only while the port-forward is active. The malicious query
should be rejected by the WAF. Validate browser sign-in, submissions, and CXE
separately. Do not run destructive or load tests.

The overlay trusts Minikube's Pod network (`10.244.0.0/16`) for the WAF
`X-Real-IP` source. Re-check that CIDR before using this overlay on another
cluster.
