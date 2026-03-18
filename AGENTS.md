# AGENTS.md

## Working style

- Deliver the requested solution first.
- When a task required course-correction, a false start, a reverted approach, repeated failing tests, or a later clearly better approach, run `$solution-retrospective` before ending the task.
- Keep the retrospective short and action-oriented.

## Persistence rules

- Put **repo-specific durable guidance** in this repository's nearest `AGENTS.md`.
- Put **cross-repo reusable workflows** in a **personal skill**, not in this repo skill directory.
- Prefer **updating an existing rule or skill** over creating a new one.
- Create a new skill only when the pattern is reusable, concrete, and likely to save future work.
- Do not create noise: no new skill for one-off mistakes, temporary outages, or facts already enforced by tests/linters.

## Retrospective trigger examples

Run `$solution-retrospective` when one or more are true:

- The first design choice was wrong and had to be replaced.
- The first patch passed partially but violated project conventions.
- Several files were read or changed unnecessarily before the correct path became clear.
- A better verification method was discovered late.
- The same kind of mistake appeared more than once in the task.

## Update rules

When updating this file:

- Add only durable rules.
- Keep additions specific and short.
- Place rules near the scope where they apply.
- Prefer command examples and path hints over vague prose.

## Repo notes

- Agent handoff: keep a local chronological troubleshooting log in `tmp/agent-handoff.md`; append findings, fixes, results, and next blockers before ending substantial debug sessions so later agents do not repeat the same steps.
- Flux/Kustomize: prefer directory references with a local `kustomization.yaml` over sibling file references such as `../foo/bar.yaml`; verify with `kubectl kustomize <path>`.
- Flux/Kustomize: when charts install CRDs that repo manifests consume, render staged Flux `Kustomization` resources so HelmReleases reconcile before dependent custom resources; do not place both in the same Flux apply path.
- Flux HelmRelease: when `chart.spec.chart` points to a repo-local path under `./charts/...`, use `chart.spec.reconcileStrategy: Revision` or Flux will not rebuild the packaged chart on file changes unless `Chart.yaml` version also changes.
- Flux local chart packaging: when repo-local charts use `.Chart.Version` in labels or default image tags, sanitize `+` for labels and pin explicit image tags if the upstream registry does not publish `+gitsha` tags; do not solve this with a blanket `global.tag` override when vendored subcharts publish different image tags.
- Flux local chart packaging: for `charts/vendor/kagent`, pin `controller.image.tag`, `controller.agentImage.tag`, `controller.skillsInitImage.tag`, and `ui.image.tag` explicitly in the HelmRelease values. The top-level `tag` alone is not sufficient to prevent invalid `+gitsha` image references during Flux upgrades.
- Flux local chart packaging: the vendored `charts/vendor/kagent` chart renders its own `default-model-config`, so provider secret and base URL overrides must be set on the main `kagent` HelmRelease, not only on `kagent-crds` or separate `kagent-resources` manifests.
- AgentGateway: current Kubernetes `AgentgatewayBackend` CRDs use `spec.ai` with provider configuration, not legacy `spec.llm`; keep both active and duplicate repo manifests aligned with that schema.
- Stop/start flow: if `cluster-stop` scales Helm-managed workloads to zero, `cluster-start` must force-reconcile the affected HelmReleases; resume plus top-level Kustomization reconcile is not enough to restore objects like `Deployment/istiod` from `0/0`.
- K3s image handling: local Docker builds are not visible to the cluster until imported into k3s/containerd; for sample images like `echo-mcp`, use tarball import targets and keep the manifest `image:` tag identical to the imported tag.
- K3s image handling: `/var/lib/rancher/k3s/agent/images/` may be absent on fresh nodes; import targets should `mkdir -p` it first instead of assuming it already exists.
- Sample workload image overrides: inject operator-specific images such as `ECHO_MCP_IMAGE` through generated Flux inputs in `flux/generated/<topology>` and stage-level Kustomize replacements, not by editing component manifests with user-specific tags.
- K3s + Istio CNI: set HelmRelease values `cniConfDir=/var/lib/rancher/k3s/agent/etc/cni/net.d`, `cniBinDir=/var/lib/rancher/k3s/data/cni`, and `ambient.enabled=true` when using `ztunnel`; otherwise `istio-cni` may look healthy while `ztunnel` never gets `/var/run/ztunnel/ztunnel.sock`.
- TEI CPU defaults: use an ONNX-backed embedding model for `EMBEDDING_MODEL` and generated `tei-values`; models without `model.onnx` keep `tei-embeddings` in rollout even after Flux and Helm are otherwise healthy.
- Generated metadata like `flux/generated/*/topology-values.yaml` is for operators only and must not be listed under Kustomize `resources`.

## Skills

### Available skills
- refactoring: Behavior-preserving refactoring for source code and configuration. Use when Codex needs to remove duplication, replace hard-coded values with inputs or defaults, simplify structure, or align code and operational configuration with current best practices across programming languages, Helm, Terraform, OpenTofu, Kubernetes, Flux, Ansible, and related configuration files. (file: /home/dmytro/.codex/skills/quality/refactoring/SKILL.md)
