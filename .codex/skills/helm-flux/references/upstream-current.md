# Upstream Current References

Use official Helm and Flux docs as the primary source of truth. Re-check them when behavior is version-sensitive.

## Verified On 2026-03-20

- Local tool versions in this repo session:
  - `helm version --short` -> `v3.20.1+ga2369ca`
  - `flux version --client` -> `v2.8.2`
- Helm docs currently expose multiple versioned trees. Do not assume the newest docs page matches the installed CLI until `helm version --short` confirms it.

## Helm

Official docs:

- https://helm.sh/docs/v3/chart_best_practices/
- https://helm.sh/docs/v3/chart_best_practices/conventions/
- https://helm.sh/docs/chart_best_practices/values/
- https://helm.sh/docs/chart_best_practices/rbac/
- https://helm.sh/docs/v3/chart_best_practices/custom_resource_definitions/
- https://helm.sh/docs/chart_template_guide/debugging/

Production-relevant rules from the docs:

- Chart names should use lowercase letters, numbers, and dashes.
- Helm uses SemVer 2 for chart versions; when SemVer is stored in labels, `+` must be replaced because label values cannot contain `+`.
- Prefer lowercase camelCase keys in `values.yaml`; avoid hyphens in values keys.
- Prefer flat values over deeply nested values in most cases.
- Use labels for queryable operational metadata and annotations for non-query metadata; Helm hooks are annotations.
- Keep `serviceAccount` and `rbac` configuration under separate keys.
- CRDs must be installed before resources that use them; Helm can install CRDs from `crds/`, but Helm does not upgrade or delete CRDs natively.
- When CRDs and CRs should evolve independently, split them into separate charts or otherwise stage them explicitly.
- Use `helm lint` first, then `helm template --debug`, then `helm install --dry-run --debug` or `--dry-run=server` when live lookup behavior matters.

## Flux HelmRelease

Official docs:

- https://fluxcd.io/flux/components/helm/helmreleases/

Production-relevant rules from the docs:

- `HelmRelease` supports ordered release execution with `.spec.dependsOn`.
- Failure handling is configurable; install and upgrade support remediation and retry behavior.
- `RetryOnFailure` and `RemediateOnFailure` are distinct strategies. Choose deliberately when rollout recovery matters.
- `.spec.install.remediation` and `.spec.upgrade.remediation` control retries and whether the last failure is remediated.
- Drift detection can be enabled with `.spec.driftDetection.mode: enabled`.
- Drift detection can be scoped with ignore rules or disabled per resource by annotation when some fields must remain mutable.
- `HelmRelease` can reconcile under a specific ServiceAccount via `.spec.serviceAccountName`; use this when cluster-admin scope is unnecessary.
- CRD lifecycle policy matters:
  - install default: `Create`
  - upgrade default: `Skip`
  - use `CreateReplace` only when CRD replacement by Flux is intentional and acceptable

## Flux HelmChart

Official docs:

- https://fluxcd.io/flux/components/source/helmcharts/

Production-relevant rules from the docs:

- `reconcileStrategy` decides when a new chart artifact is built.
- `ChartVersion` rebuilds when chart version changes.
- `Revision` rebuilds when the underlying Git or Bucket source revision changes.
- For Git-backed local charts, `ChartVersion` misses source-only changes unless `Chart.yaml` version also changes.
- For repo-local chart packaging from Git content, `Revision` is usually the correct setting.
