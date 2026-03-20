# Repo Workflow

Apply these repository rules after checking the official docs.

## Read First

- nearest `AGENTS.md`
- `docs/OPERATIONS.md`
- `docs/flux-bootstrap.md`
- `docs/helm-charts.md`

## Repository Rules

- Prefer directory references with a local `kustomization.yaml` over sibling file references. Validate with `kubectl kustomize <path>`.
- When charts install CRDs that repo manifests consume, split the rollout into staged Flux `Kustomization` resources so Helm reconciles before dependent custom resources.
- When `HelmRelease.spec.chart.spec.chart` points at a repo-local path under `./charts/...`, use `chart.spec.reconcileStrategy: Revision` or Flux will ignore source-only chart changes until `Chart.yaml` version changes.
- When repo-local charts use `.Chart.Version` in labels or default image tags, sanitize `+` for labels and pin explicit image tags when registries do not publish `+gitsha` tags.
- For `charts/vendor/kagent`, pin `controller.image.tag`, `controller.agentImage.tag`, `controller.skillsInitImage.tag`, and `ui.image.tag` explicitly in `HelmRelease` values.
- During resume after `cluster-stop` or `cluster-pause`, reconcile `platform-bootstrap` first, then force-reconcile HelmReleases, then wait on `platform-infrastructure`, `platform-applications`, and `platform`.
- During `cluster-pause`, save Deployment and StatefulSet replica targets before scaling them to zero. During `cluster-resume`, restore those replicas before waiting on staged Flux health. This repo uses Helm server-side apply; a direct `kubectl scale` can leave `spec.replicas` owned by another field manager and block later Helm-driven restore.
- For bulk repo resume, annotate HelmReleases for immediate reconcile instead of waiting serially on `flux reconcile helmrelease` per release; let the staged Kustomization waits be the convergence boundary.
- Prefer repo `make` targets for cluster-facing `kubectl` and `flux` operations because they already bind the generated kubeconfig explicitly.
- Do not list `flux/generated/*/topology-values.yaml` under Kustomize `resources`; it is operator metadata only.

## Practical Validation Commands

```bash
helm lint charts/<chart>
helm template --debug test charts/<chart>
kubectl kustomize flux/generated/local
kubectl kustomize flux/generated/clusters/local-dev-none-external
flux get kustomizations -A
flux get helmreleases -A
```

Prefer existing `Makefile` automation for staged reconcile and restore instead of inventing a new order ad hoc.
