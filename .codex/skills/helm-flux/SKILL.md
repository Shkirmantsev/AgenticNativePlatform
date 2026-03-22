---
name: "helm-flux"
description: "Design, modify, validate, and troubleshoot production-ready Helm charts and Flux GitOps resources in this repository. Use when work involves Helm chart authoring, HelmRelease or HelmChart changes, GitRepository or Kustomization staging, release remediation, CRD lifecycle, repo-local chart packaging, or Helm/Flux incident response."
---

# Helm Flux

Use this skill for Helm and Flux work that must be safe, reproducible, and production-ready. Start from current official Helm and Flux behavior, then apply this repository's operating rules.

## Operating Standard

Prefer solutions that are:

- declarative and Git-driven
- explicit about versions, timeouts, and failure behavior
- validated locally before cluster reconciliation
- least-privilege by default
- staged so CRDs, controllers, and dependent resources reconcile in a safe order

Avoid one-off cluster mutations unless the task explicitly requires emergency recovery and the final state is brought back into Git.

## Workflow

1. Classify the task:
   - chart authoring under `charts/`
   - Flux source or release behavior under `flux/`
   - staged reconciliation or restore flow
   - runtime incident rooted in Helm/Flux state
2. Check actual local versions before assuming CLI or API behavior:
   - `helm version --short`
   - `flux version --client`
3. Read [upstream-current.md](./references/upstream-current.md) for the official rules that are most relevant here.
4. Read [repo-workflow.md](./references/repo-workflow.md) and the nearest `AGENTS.md` for repository-specific constraints.
5. Validate from inner loop to outer loop:
   - `helm lint`
   - `helm template --debug`
   - `kubectl kustomize`
   - targeted Flux inspection and reconcile
   - broader staged reconcile only after the narrow layer is clean
6. Choose the smallest correct fix:
   - values or template issue: fix the chart
   - packaging issue: fix chart path, source, or `reconcileStrategy`
   - release safety issue: fix remediation, timeout, RBAC, CRD, or dependency settings
   - staged rollout issue: fix Flux ordering, not just the chart

## Production Defaults

Apply these unless the task gives a strong reason not to:

- Pin concrete container image tags. Do not rely on floating `latest`.
- Set resource requests and limits for long-running workloads.
- Keep ServiceAccounts and RBAC explicit. Grant only what the workload or Helm reconciliation needs.
- Use standard labels and predictable values structure.
- Avoid hard-coding `metadata.namespace` inside chart templates unless the chart is intentionally single-namespace and that tradeoff is explicit.
- Define failure behavior in `HelmRelease` when outages or partial rollouts matter:
  - explicit `timeout`
  - install and upgrade remediation or retry strategy
  - `dependsOn` when release ordering is real
- Be deliberate about CRDs:
  - separate CRD producers from CR consumers when needed
  - use Flux staging when dependent manifests would race chart-installed CRDs
- Prefer drift correction that is encoded in Git and Flux over hand-edited cluster fixes.

## Validation Order

### Helm chart changes

1. Run `helm lint <chart-dir>`.
2. Run `helm template --debug <release> <chart-dir>`.
3. If the chart uses `lookup`, run `helm install --dry-run=server --debug ...` against a suitable cluster.
4. If the chart is packaged by Flux from Git content, confirm the matching `HelmRelease` or `HelmChart` configuration will detect the change.

### Flux changes

1. Run `kubectl kustomize` on the smallest affected path.
2. Confirm staged dependencies still make sense when CRDs, controllers, or cross-namespace refs are involved.
3. Reconcile the narrowest affected object first.

### Incident response

1. Check `flux get sources -A`, `flux get helmreleases -A`, and `flux get kustomizations -A`.
2. Inspect the specific object with `kubectl describe`.
3. Use `flux debug helmrelease <name> -n <ns>` when available.
4. Move to workload logs, events, endpoints, or mesh diagnosis only after source, packaging, and release state are understood.

## Improve This Skill

When Helm or Flux problem solving produces a durable lesson:

1. Add the repo-specific rule to the nearest `AGENTS.md`.
2. Update this skill when the reusable workflow, validation order, or troubleshooting logic should change for future work.
3. Keep `SKILL.md` short. Put detailed facts in the reference files.
