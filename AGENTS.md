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
- Cluster restart flow: when resuming a staged Flux stack after `cluster-stop`, reconcile `platform-bootstrap` first, then force-reconcile HelmReleases, then wait on `platform-infrastructure`, `platform-applications`, and `platform`; waiting on higher stages before Helm has restored scaled-down Deployments produces misleading "stuck" reconcile output.
- Pause/resume flow: when `cluster-pause` scales Helm-managed Deployments or StatefulSets to zero, snapshot the replica targets first and restore them before the resume reconcile waits; Helm server-side apply does not reliably take back `spec.replicas` from a prior `kubectl scale`, and HPA-managed Deployments stay `ScalingDisabled` at zero until something raises replicas again.
- Pause-state recovery: `ConfigMap/flux-system/cluster-pause-state` can itself preserve stale `0` replica targets after an older or already-broken pause; recovery flows must detect zeroed snapshots and fall back to scaling paused-namespace workloads back up before relying on Helm/Flux reconcile.
- Flux bulk resume: for repo-wide HelmRelease fan-out, prefer `reconcile.fluxcd.io/requestedAt` / `forceAt` / `resetAt` annotations plus staged Kustomization waits over a long sequential `flux reconcile helmrelease ...` loop.
- Operator Make targets: for user-facing `kubectl` / `flux` Make targets, prefer explicit `--kubeconfig "$(KUBECONFIG)"` binding over relying only on the exported environment; it makes `make -n` and README snippets match what actually happens.
- Operator Make targets: when a preflight reads Services, Endpoints, or Flux objects, treat `kubectl` command failures separately from empty results; surface API-server-unreachable errors explicitly instead of reporting generic `Missing` or `no ready endpoints`.
- Operator Make targets: when a Make target shells out to repo scripts and users may override inputs on the command line (`make ... VLLM_IMAGE=...`, `ECHO_MCP_IMAGE=...`, `GIT_BRANCH=...`), pass those variables explicitly into the script invocation; values imported from `.env` inside scripts otherwise override the intended command-line render.
- Topology-aware Make/shell paths: when a target or script accepts `TOPOLOGY`, derive `TF_DIR` from that final topology and source `.env` before computing the fallback; explicit `make ... TOPOLOGY=github-workspace` must not silently keep using `local` paths from ambient variables.
- Makefile topology defaults: normalize an explicitly empty command-line `TOPOLOGY=` back to `local` with `override`; GNU Make treats empty CLI assignments as higher precedence than `?=`, which otherwise leaves `TF_DIR` pointing at `terraform/environments/`.
- Plaintext secret bootstrap: `make apply-plaintext-secrets` runs before Flux bootstrap, so `.generated/secrets/<env>/namespaces.yaml` must include every namespace referenced by those secrets, including early `context` and `observability` objects.
- Flux Git bootstrap preflight: when validating `GIT_REPO_URL` against local remotes, compare normalized repo identity (`github.com/org/repo`) rather than exact SSH-vs-HTTPS URL strings; developers often clone with SSH while Flux reads HTTPS.
- kgateway image pinning: the `kgateway` OCI chart can render a controller image tag with `+gitsha` suffixes such as `2.0.2+a98210b0b2c5`; pin `spec.values.controller.image.registry/repository/tag` in `flux/components/kgateway-core/release.yaml` to a stable published tag such as `cr.kgateway.dev/kgateway-dev/kgateway:v2.0.2`.
- Port-forward cleanup in Make recipes: do not use broad `pgrep -f` patterns that also appear in the current shell command line; match only real `kubectl` processes via `ps ... | awk '$$2=="kubectl"'` before killing stale managed forwards.
- Flux local chart packaging: when repo-local charts use `.Chart.Version` in labels or default image tags, sanitize `+` for labels and pin explicit image tags if the upstream registry does not publish `+gitsha` tags; do not solve this with a blanket `global.tag` override when vendored subcharts publish different image tags.
- Flux local chart packaging: for `charts/vendor/kagent`, pin `controller.image.tag`, `controller.agentImage.tag`, `controller.skillsInitImage.tag`, and `ui.image.tag` explicitly in the HelmRelease values. The top-level `tag` alone is not sufficient to prevent invalid `+gitsha` image references during Flux upgrades.
- Flux local chart packaging: the vendored `charts/vendor/kagent` chart renders its own `default-model-config`, so provider secret and base URL overrides must be set on the main `kagent` HelmRelease, not only on `kagent-crds` or separate `kagent-resources` manifests.
- AgentGateway: current Kubernetes `AgentgatewayBackend` CRDs use `spec.ai` with provider configuration, not legacy `spec.llm`; keep both active and duplicate repo manifests aligned with that schema.
- AgentGateway: current policy CRD is `AgentgatewayPolicy`, not `BackendTrafficPolicy`; backend request timeout belongs under `spec.backend.http.requestTimeout`.
- AgentGateway/Gateway API: when an `HTTPRoute` references `AgentgatewayBackend` from another namespace, set `backendRefs[].namespace` explicitly or the controller resolves it in the route namespace and returns `BackendNotFound` / `no valid backends`.
- AgentGateway/LiteLLM: if routes are resolved but AgentGateway still returns `upstream call failed: Connect: Connection refused`, inspect `ztunnel` and the target pod annotations; for local `ai-gateway` workloads under ambient, opt the backend pod out with `istio.io/dataplane-mode: none` before assuming the app bind address is wrong.
- Kagent restart behavior: the vendored controller chart's default startup probe is too short for post-stop/start recovery on this repo; keep the controller startup probe configurable and allow at least a few minutes before kubelet restarts it.
- Kagent controller probes: keep startup/readiness on the app server endpoint `:8083/health`; the controller also logs `ProbeAddr :8082`, but probing `:8082/health` returned `404` in this repo's live rollout.
- Kagent + ambient: if `HelmRelease/kagent` stays `InProgress` while the controller pod times out talking to the API server, inspect `ztunnel` and opt the controller pod out with `istio.io/dataplane-mode: none`; the live config may look fine even when ambient blocks startup.
- RemoteMCPServer integration: a plain REST endpoint under `/mcp` is not enough; use a real MCP server implementation or official MCP reference package, otherwise clients will hit `422` / `405` protocol mismatches.
- Stop/start flow: if `cluster-stop` scales Helm-managed workloads to zero, `cluster-start` must force-reconcile the affected HelmReleases; resume plus top-level Kustomization reconcile is not enough to restore objects like `Deployment/istiod` from `0/0`.
- Stop/start flow: do not scale `metallb-system` to zero; MetalLB's controller backs the validating webhook for `IPAddressPool`, and zero endpoints blocks `platform-applications` dry-run on the next reconcile.
- Command semantics: use `cluster-pause` / `cluster-resume` for reversible workload suspension, `cluster-remove` for k3s-only removal, and `environment-destroy` for cluster plus Terraform/OpenTofu cleanup; keep `cluster-stop` / `cluster-start` only as compatibility aliases.
- K3s image handling: local Docker builds are not visible to the cluster until imported into k3s/containerd; for sample images like `echo-mcp`, use tarball import targets and keep the manifest `image:` tag identical to the imported tag.
- K3s image handling: `/var/lib/rancher/k3s/agent/images/` may be absent on fresh nodes; import targets should `mkdir -p` it first instead of assuming it already exists.
- K3s image handling: copying a tarball into `/var/lib/rancher/k3s/agent/images/` is not enough for fast rollouts of a new tag; run `k3s ctr images import <tar>` in the target so kubelet can start the new image immediately instead of attempting a registry pull.
- Ansible privilege escalation: for local ad-hoc `ansible ... -b` commands in this repo, plain `make ...` is preferred; let the local sudo prompt appear if needed, and do not assume `ANSIBLE_BECOME_FLAGS=-K` is required.
- Sample workload image overrides: inject operator-specific images such as `ECHO_MCP_IMAGE` through generated Flux inputs in `flux/generated/<topology>` and stage-level Kustomize replacements, not by editing component manifests with user-specific tags.
- Sample workload images: the local `mcp/echo-server` image must run with a numeric non-root UID/GID (for example `USER 1000:1000`); `runAsNonRoot` will reject root or named-only users during local kmcp rollouts.
- Optional samples: do not include sample MCP workloads that depend on locally built or placeholder images in the default `platform-applications` path; gate them behind an explicit opt-in overlay or post-bootstrap workflow so a cold cluster can reach `Ready=True` without extra image import steps.
- Local operator access: verify Makefile port-forward targets against live `kubectl get svc -A` output; current local access uses `kagent-kagent-ui`, `kagent-kagent-controller`, and the gateway-facing `agentgateway-proxy` Service, not the older short service names.
- AgentGateway access: for north-south/operator access prefer the gateway-facing `Service/agentgateway-proxy` when it exists; the internal `agentgateway-system-agentgateway` service is not the canonical external entrypoint.
- K3s + Istio CNI: set HelmRelease values `cniConfDir=/var/lib/rancher/k3s/agent/etc/cni/net.d`, `cniBinDir=/var/lib/rancher/k3s/data/cni`, and `ambient.enabled=true` when using `ztunnel`; otherwise `istio-cni` may look healthy while `ztunnel` never gets `/var/run/ztunnel/ztunnel.sock`.
- TEI restart behavior: for local CPU embeddings, keep TEI on an ONNX-backed model, mount `/data` on an `emptyDir` cache, opt the pod out of ambient, and allow a longer Helm timeout; cold restarts otherwise flap on Hugging Face download retries and block `platform-infrastructure`.
- TEI CPU defaults: use an ONNX-backed embedding model for `EMBEDDING_MODEL` and generated `tei-values`; models without `model.onnx` keep `tei-embeddings` in rollout even after Flux and Helm are otherwise healthy.
- KServe chart behavior: upstream `ghcr.io/kserve/charts/kserve:v0.16.0` always renders the built-in `ClusterServingRuntime` objects and only toggles `spec.disabled`; in this repo, strip those objects with Helm post-renderer delete patches or stage them separately, otherwise first install can deadlock on the webhook before `kserve-controller-manager` has endpoints.
- Generated metadata like `flux/generated/*/topology-values.yaml` is for operators only and must not be listed under Kustomize `resources`.
- Terraform/OpenTofu local_file: when generating tracked repo manifests such as `flux/generated/**`, set explicit `directory_permission="0755"` and `file_permission="0644"`; provider defaults can flip YAML files to executable and create noisy diffs.

## Skills

### Available skills
- refactoring: Behavior-preserving refactoring for source code and configuration. Use when Codex needs to remove duplication, replace hard-coded values with inputs or defaults, simplify structure, or align code and operational configuration with current best practices across programming languages, Helm, Terraform, OpenTofu, Kubernetes, Flux, Ansible, and related configuration files. (file: /home/dmytro/.codex/skills/quality/refactoring/SKILL.md)
