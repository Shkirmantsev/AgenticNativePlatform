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

- Flux/Kustomize: prefer directory references with a local `kustomization.yaml` over sibling file references such as `../foo/bar.yaml`; verify with `kubectl kustomize <path>`.
- Flux/Kustomize: when charts install CRDs that repo manifests consume, render staged Flux `Kustomization` resources so HelmReleases reconcile before dependent custom resources; do not place both in the same Flux apply path.
- Flux HelmRelease: when `chart.spec.chart` points to a repo-local path under `./charts/...`, use `chart.spec.reconcileStrategy: Revision` or Flux will not rebuild the packaged chart on file changes unless `Chart.yaml` version also changes.
- K3s + Istio CNI: set HelmRelease values `cniConfDir=/var/lib/rancher/k3s/agent/etc/cni/net.d` and `cniBinDir=/var/lib/rancher/k3s/data/cni` or `istio-cni` will either wait on the empty generic `/etc/cni/net.d` or install the plugin into a path K3s never uses.
- Generated metadata like `flux/generated/*/topology-values.yaml` is for operators only and must not be listed under Kustomize `resources`.

## Skills

### Available skills
- refactoring: Behavior-preserving refactoring for source code and configuration. Use when Codex needs to remove duplication, replace hard-coded values with inputs or defaults, simplify structure, or align code and operational configuration with current best practices across programming languages, Helm, Terraform, OpenTofu, Kubernetes, Flux, Ansible, and related configuration files. (file: /home/dmytro/.codex/skills/quality/refactoring/SKILL.md)
