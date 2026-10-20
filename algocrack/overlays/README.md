# Helm values organization

`algocrack/values.yaml` remains the chart default and is the only values file
Helm loads automatically. Everything under this directory must be supplied
explicitly with `-f`.

## `examples/`

Safe, reusable starter configurations. Copy an example to
`helm/my-values.local.yaml`, replace placeholders locally, and never commit the
result.

## `releases/`

Tracked release, upgrade, and rollback overlays. RC2 is retained for its
deployment and rollback procedures; RC3 is retained for the current CXE image
routing lineage. A newer release number does not make an older overlay
obsolete. Release-specific hotfix overlays belong here only after their owning
work is committed and approved.

## Classification rules

- Keep chart defaults and templates in the chart root.
- Keep reusable examples and operational release overlays tracked.
- Keep credentials and machine-local overrides in ignored local values files.
- Write generated manifests beneath `helm/rendered/` or use a temporary
  directory; do not commit them.
- Do not delete historical overlays required to reconstruct or roll back a
  deployed Helm revision.
