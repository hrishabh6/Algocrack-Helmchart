# Helm Deployment Guide

This directory contains the reusable Helm chart for deploying AlgoCrack.

The chart lives under:

- `helm/algocrack/`

This guide is the repo-owned path for installing, upgrading, validating, and removing the chart on a real cluster.

## What the chart covers

The chart currently templates:

- namespace
- shared configmaps
- generated or existing secret wiring
- bundled MySQL
- bundled Redis
- `auth-service`
- `problem-service`
- `submission-service`
- `code-execution-engine`
- `api-gateway`
- `frontend`
- ingress
- optional HPAs for:
  - `api-gateway`
  - `code-execution-engine`
  - `frontend`

## Defaults

- release name: `algocrack`
- namespace: `algocrack`
- ingress host: `algocrack.local`
- ingress class: `nginx`
- bundled MySQL: enabled
- bundled Redis: enabled
- HPA creation: disabled by default

## Prerequisites

Before installing, make sure you have:

1. `helm` available locally
2. a working Kubernetes cluster context
3. an ingress controller if you want public routing
4. `metrics-server` if you want HPA resources to function at runtime

## Recommended values workflow

Start from the safe committed example files:

- [algocrack/values.example.yaml](/home/hrishabh/codebases/java/leetcode/helm/algocrack/values.example.yaml)
- [algocrack/values.minikube.example.yaml](/home/hrishabh/codebases/java/leetcode/helm/algocrack/values.minikube.example.yaml)

Create your own local file, for example:

```bash
cp helm/algocrack/values.minikube.example.yaml helm/my-values.yaml
```

Then replace the placeholders with your own:

- Google OAuth client ID and client secret
- JWT private/public PEM values
- MySQL password values if you keep bundled MySQL
- ingress host if you are not using `algocrack.local`

## Preflight validation

Render the chart before installing:

```bash
helm template algocrack ./helm/algocrack -f helm/my-values.yaml
```

Lint the chart:

```bash
helm lint ./helm/algocrack
```

## Install or upgrade

Recommended install flow:

```bash
helm upgrade --install algocrack ./helm/algocrack \
  -f helm/my-values.yaml \
  --namespace algocrack \
  --create-namespace
```

If you want to keep namespace creation inside the chart instead, omit `--create-namespace`.

## Useful override examples

Set a different ingress host:

```bash
helm upgrade --install algocrack ./helm/algocrack \
  -f helm/my-values.yaml \
  --set ingress.host=mydomain.local
```

Enable existing secret reuse:

```bash
helm upgrade --install algocrack ./helm/algocrack \
  -f helm/my-values.yaml \
  --set secrets.useExisting=true \
  --set secrets.appSecretName=my-app-secret \
  --set secrets.jwtSecretName=my-jwt-secret
```

Enable autoscaling for supported services:

```bash
helm upgrade --install algocrack ./helm/algocrack \
  -f helm/my-values.yaml \
  --set services.apiGateway.autoscaling.enabled=true \
  --set services.codeExecutionEngine.autoscaling.enabled=true \
  --set services.frontend.autoscaling.enabled=true
```

Inject PEM files from disk instead of inline YAML:

```bash
helm upgrade --install algocrack ./helm/algocrack \
  --set auth.google.clientId=your-client-id \
  --set auth.google.clientSecret=your-client-secret \
  --set-file auth.jwt.privateKeyPem=./private.pem \
  --set-file auth.jwt.publicKeyPem=./public.pem
```

## Post-install verification

Check the release:

```bash
helm status algocrack -n algocrack
```

Check pods:

```bash
kubectl get pods -n algocrack
```

Check services:

```bash
kubectl get svc -n algocrack
```

Check ingress:

```bash
kubectl get ingress -n algocrack
```

## Local access

If ingress is not available yet, you can still test locally:

```bash
kubectl port-forward svc/frontend 3000:3000 -n algocrack
kubectl port-forward svc/api-gateway 9090:9090 -n algocrack
```

If you do use ingress locally, map your host to the ingress controller address, for example:

```text
127.0.0.1 algocrack.local
```

## Uninstall

```bash
helm uninstall algocrack -n algocrack
```

If you want to remove the namespace too:

```bash
kubectl delete namespace algocrack
```

## Notes

- HPA resources render only when explicitly enabled.
- HPA runtime behavior depends on a working cluster metrics pipeline.
- Bundled MySQL and Redis are convenient defaults for self-hosting, not HA production infrastructure.
