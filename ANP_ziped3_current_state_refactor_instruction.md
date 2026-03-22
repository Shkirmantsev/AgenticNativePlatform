# AgenticNativePlatform Refactoring Instruction
## Current-state-aware plan for `AgenticNativePlatform-ziped3.zip`

## 1. Scope and goal

This instruction replaces earlier generic refactoring notes that were partly based on an older repository state.

It is written for the repository state contained in `AgenticNativePlatform-ziped3.zip`.

The goal is to refactor the project without breaking the currently working system, while improving:

- declarative architecture;
- GitOps discipline;
- multi-host and future multi-cloud readiness;
- startup performance and faster feedback loops;
- maintainability and lower shell-script dependence;
- documentation accuracy.

This plan is phased. After each phase, stop and test before moving to the next one.

---

## 2. Important correction to earlier instructions

The following items are already implemented correctly in the current repository and **must not be reworked as if they were missing**:

1. `kagent` MCP traffic in the active split path is already gatewayed through `agentgateway`.
   - File: `flux/components/kagent-resources/remote-mcp.yaml`
   - Current state: `RemoteMCPServer` points to `agentgateway-proxy.../mcp/kagent-tools`.

2. The `echo-mcp` sample is already represented as a real `MCPServer` with discovery disabled.
   - File: `flux/components/kmcp-resources/echo-mcpserver.yaml`

3. `agentgateway` already has separate LLM and MCP routing files.
   - Files:
     - `flux/components/agentgateway-resources/httproutes.yaml`
     - `flux/components/agentgateway-resources/mcp-backends.yaml`
     - `flux/components/agentgateway-resources/mcp-routes.yaml`

4. KServe is already installed in the platform and must remain installed.

5. The active staged bootstrap model already exists.
   - `platform-bootstrap`
   - `platform-infrastructure`
   - `platform-applications`

Because of that, any instruction that proposes to “introduce” these items from scratch is obsolete for this repository version.

---

## 3. What is still wrong or incomplete in the current repository

### 3.1 Documentation and diagram drift still exists

The main README and `docs/architecture.md` are mostly aligned with the current design, but some artifacts are still stale:

- `.assets/architecture-current.svg` still contains stale labels such as:
  - `kagent / kmcp agents`
  - `TEI embeddings` shown in the active request path in a misleading way
- `docs/adr/0006-canonical-llm-routing.md` still says `kagent / kmcp -> agentgateway -> LiteLLM -> ...`
  - `kmcp` is not an agent runtime.
- Some docs mention `echo-validation-agent`, but that resource is not actually present in active manifests.

### 3.2 The optional `echo-mcp` sample is only partially wired

Current state:

- `flux/components/kmcp-resources/echo-mcpserver.yaml` exists.
- `flux/components/kagent-resources/remote-mcp.yaml` does **not** expose `echo-mcp` to `kagent`; it only exposes `kagent-tool-server`.
- `flux/components/agentgateway-resources/mcp-backends.yaml` and `mcp-routes.yaml` currently include only `kagent-tools`.
- Documentation says `echo-validation-agent` exists, but there is no active manifest for it.

Therefore, the repository currently has a **partially implemented sample validation path**:

- the `echo-mcp` server side exists,
- but the end-to-end `kagent -> agentgateway -> echo-mcp` validation path is incomplete.

### 3.3 Legacy and active component trees coexist

The repository contains both:

- active split-path components:
  - `*-core`
  - `*-resources`
  - staged generated cluster roots
- older monolithic or legacy component trees:
  - `flux/components/kagent`
  - `flux/components/kmcp`
  - `flux/components/agentgateway`
  - `flux/components/kgateway`
  - `flux/components/platform-core`
  - `flux/components/platform`
  - old static cluster roots under `flux/clusters/*`

This is not immediately breaking, but it increases drift risk and makes automated refactoring dangerous.

### 3.4 Large YAML generation is still shell-driven

Current shell scripts still render tracked manifests:

- `scripts/render-cluster-kustomization.sh`
- `scripts/render-flux-values.sh`
- `scripts/render-terraform-tfvars.sh`
- `scripts/bootstrap-flux-git.sh`
- `scripts/cluster-up-github-workspace.sh`

This is exactly the area that should be reduced and redistributed using:

- OpenTofu `templatefile(...)` for topology/bootstrap outputs;
- Kustomize overlays for GitOps composition;
- Helm values only for per-chart configuration.

### 3.5 Terraform-generated YAML is syntactically valid but maintainability-poor

`terraform/modules/inventory-generator/main.tf` uses `yamlencode(...)` for files such as:

- `flux/generated/<topology>/metallb-values.yaml`
- `flux/generated/<topology>/topology-values.yaml`
- `flux/generated/<topology>/lmstudio-endpoint.yaml`

This produces heavily quoted YAML which is valid but hard to review and noisy in Git diffs.

### 3.6 Startup behavior still depends too much on coarse stage budgets

The repository already uses staged Flux roots and longer max timeouts, which is good.

However, the current approach still has these issues:

- heavy default infrastructure composition for local cold start;
- some optional/sample parts are still installed in the default path;
- waiting is still budget-based rather than health-driven in some bootstrap flows;
- shell scripts still use fixed waits in places such as background port-forward handling.

The design target must be:

- **health-driven progression**;
- **maximum limits only**;
- **no hardcoded mandatory sleeps as readiness logic**;
- **ability to finish earlier as soon as components are actually ready**.

### 3.7 Current repository is not yet properly shaped for future multi-host / multi-cloud growth

The repository already supports `hybrid` and `hybrid-remote`, which is a good base.

But for future scale-out, the architecture still needs:

- stronger topology abstraction;
- clearer distinction between single-node dev and HA/multi-host cluster modes;
- proper datastore strategy per topology;
- clearer profile separation between fast dev and full platform.

---

## 4. Non-goals during this refactor

Do **not** do the following in the first phases:

1. Do not remove KServe.
2. Do not replace already-correct MCP gatewaying in the active split path.
3. Do not delete working staged Flux roots.
4. Do not switch all existing cluster roots at once.
5. Do not break `make run-cluster-from-scratch` until the replacement flow is fully validated.
6. Do not remove legacy folders before all references are migrated and tested.
7. Do not make the `echo-mcp` sample mandatory for basic platform health.

---

## 5. Architectural target after refactor

Use this responsibility split.

### 5.1 OpenTofu / Terraform

Use for:

- topology variables and topology-specific outputs;
- cluster bootstrap inputs;
- `k3d` config generation for `github-workspace`;
- inventory generation;
- small generated bootstrap files;
- optional Flux bootstrap provider integration later.

Do **not** use it to render large application YAML trees.

### 5.2 Ansible

Use for:

- host preparation;
- package installation on real hosts;
- `k3s` installation and node join on host-based topologies;
- kubeconfig export;
- future host tuning and image pre-pull tasks.

### 5.3 Flux + Kustomize

Use as the main GitOps composition layer.

Use Kustomize for:

- staged roots;
- profile composition;
- environment overlays;
- optional component bundles;
- wiring of Flux-managed platform components.

### 5.4 Helm / HelmRelease values

Use only for chart-level configuration of concrete products, for example:

- `kagent`
- `kmcp`
- `agentgateway`
- `kgateway`
- `LiteLLM`
- `KServe`
- `TEI`
- `Postgres`
- `Redis`
- `Qdrant`
- `Weave GitOps UI`

---

## 6. Refactoring phases

---

## Phase 0 - Baseline freeze and safety net

### Goal

Freeze the current working state and make future changes auditable.

### Actions

1. note the actual state in the corresponding files of the project, like in AGENTS.MD and other;
2. Tag the current baseline commit.

### Definition of done

- A recoverable baseline exists.
- A rollback point exists.
- Current functional behavior is documented before edits begin.

---

## Phase 1 - Documentation and architecture drift cleanup only

### Goal

Fix documentation drift without changing runtime behavior.

### Files to change

1. `.assets/architecture-current.svg`
2. `README.md`
3. `docs/architecture.md`
4. `docs/adr/0006-canonical-llm-routing.md`
5. `docs/commands.md`
6. `docs/OPERATIONS.md`

### Required corrections

#### 1. Fix terminology

Replace all wording of this kind:

- `kagent / kmcp agents`

with wording of this kind:

- `kagent agents`
- `kmcp-managed MCP servers`

#### 2. Fix active request path visualization

The primary diagram and text must show:

- `kagent -> agentgateway -> LiteLLM -> providers / optional runtimes` for LLM;
- `kagent -> agentgateway -> kmcp-managed MCP servers` for MCP.

Do not show TEI as if it sits in the canonical hot path unless the manifests actually wire it there.

#### 3. Fix `echo-mcp` wording

The docs must stop claiming that `echo-validation-agent` already exists unless it is actually added in a later phase.

Until that phase is complete, documentation must say:

- `echo-mcp` server sample exists;
- full end-to-end validation agent is planned or optional;
- the default active MCP example is the bundled `kagent-tool-server` path.

#### 4. Fix port-forward wording

Where docs currently suggest opening root URLs as if they were UIs, rewrite them precisely:

- `agentgateway` local port-forward exposes API paths like `/v1/*` and `/mcp/*`.
- `LiteLLM` local port-forward exposes API endpoints, not a UI homepage.

### Definition of done

- No stale `kagent / kmcp agents` terminology remains in active docs.
- Diagram matches the actual manifests in `ziped3`.
- Docs no longer claim resources that do not exist.

### Tests

- `make verify`
- `make cluster-status`
- `make test-agentgateway-openai`
- `make test-litellm`

- `grep -RIn "kagent / kmcp agents" README.md docs .assets flux/components || true`
- `grep -RIn "echo-validation-agent" README.md docs flux/components || true`
- manual review of `README.md` architecture section against actual files:
  - `flux/components/kagent-resources/remote-mcp.yaml`
  - `flux/components/kmcp-resources/echo-mcpserver.yaml`
  - `flux/components/agentgateway-resources/*.yaml`

---

## Phase 2 - Add health checks and diagnostics before structural refactor

### Goal

Improve safety and observability before changing architecture internals.

### Files to change

1. `Makefile`
2. `docs/commands.md`
3. `docs/OPERATIONS.md`

### Required changes

#### 1. Add explicit health-check targets

Add targets such as:

- `check-agentgateway`
- `check-litellm`
- `check-kagent-ui`
- `check-flux-stages`

Behavior:

- `check-agentgateway` should validate `/v1/models` via `curl` with auth.
- `check-litellm` should validate `/health/readiness` and `/v1/models`.
- `check-flux-stages` should show readiness for:
  - `platform-bootstrap`
  - `platform-infrastructure`
  - `platform-applications`

#### 2. Replace “process alive” assumptions with HTTP readiness checks where possible

In local helpers, do not treat a running `kubectl port-forward` process as proof that the API is ready.

Use probe logic such as:

- success on HTTP 200/401/404 according to endpoint semantics;
- bounded retries with a max timeout;
- immediate success when endpoint becomes available.

#### 3. Add a simple endpoint truth table to docs

Document which local endpoints are expected to behave how:

- `http://localhost:15000/` -> no root route expected;
- `http://localhost:15000/v1/models` -> OpenAI-compatible API path;
- `http://localhost:4000/health/readiness` -> LiteLLM health;
- `http://localhost:4000/v1/models` -> LiteLLM API.

### Definition of done

- Diagnostics are better before deeper refactor starts.
- Local validation is health-driven, not just PID-driven.

### Tests

- `make open-agentgateway && make check-agentgateway`
- `make open-litellm && make check-litellm`
- `make verify`

---

## Phase 3 - Complete or isolate the `echo-mcp` sample path

### Goal

Remove the current half-wired state.

### Decision rule

Choose exactly one of these two options.

### Option A - Complete the sample path

Use this if you want `echo-mcp` as a real end-to-end validation scenario.

#### Files to add or change

1. `flux/components/agentgateway-resources/mcp-backends.yaml`
2. `flux/components/agentgateway-resources/mcp-routes.yaml`
3. `flux/components/kagent-resources/remote-mcp.yaml`
4. `flux/components/kagent-resources/agents.yaml` or a new dedicated file such as:
   - `flux/components/kagent-resources/echo-validation-agent.yaml`
5. `flux/components/kagent-resources/kustomization.yaml`

#### Required changes

1. Add an `AgentgatewayBackend` for `echo-mcp-http`.
2. Add an `HTTPRoute` for `/mcp/echo`.
3. Add a `RemoteMCPServer` pointing to:
   - `http://agentgateway-proxy.agentgateway-system.svc.cluster.local:8080/mcp/echo`
4. Add `echo-validation-agent` that explicitly uses that `RemoteMCPServer`.
5. Update docs only after the manifest exists and is reconciled successfully.

#### Recommended manifest names

- backend: `echo-mcp-backend`
- route: `echo-mcp-route`
- remote MCP resource: `echo-mcp`
- agent: `echo-validation-agent`

### Option B - Move the sample out of the default path

Use this if you want the default platform bootstrap to remain leaner and deterministic.

#### Files to add or change

1. Create a new optional component bundle, for example:
   - `flux/components/samples-echo-mcp/`
2. Move or reference:
   - `flux/components/kmcp-resources/echo-mcpserver.yaml`
   - any future echo-specific route/backend/agent manifests
3. Remove the sample from the default applications stage.
4. Update docs to say the sample is opt-in.

#### Recommended choice

For this repository, **Option B is the safer default**.

Reason:

- the base platform already works without `echo-mcp`;
- the sample is not required for the main path;
- optional samples should not slow down or destabilize first bootstrap.

### Definition of done

Either:

- the sample is fully usable end-to-end,

or:

- the sample is clearly optional and no docs imply otherwise.

### Tests

If Option A:

- `kubectl -n agentgateway-system get agentgatewaybackend echo-mcp-backend`
- `kubectl -n agentgateway-system get httproute echo-mcp-route`
- `kubectl -n kagent get remotemcpserver echo-mcp`
- test through `echo-validation-agent`

If Option B:

- default bootstrap succeeds without any `echo-mcp` resource in the default path;
- docs explicitly mark the sample as optional.

---

## Phase 4 - Introduce declarative topology rendering and reduce shell generation

### Goal

Move rendering responsibilities to the correct layers without breaking GitOps.

### Target split

#### Use OpenTofu `templatefile(...)` for:

- generated topology files under `flux/generated/<topology>/`;
- generated `ansible/generated/<topology>.ini`;
- generated `k3d` config for `github-workspace`;
- generated tfvars or equivalent topology outputs.

#### Use Kustomize for:

- cluster roots;
- staged platform composition;
- environment overlays;
- optional profiles and bundles.

#### Use Helm values for:

- chart-specific settings only.

### Files to change

1. `terraform/modules/inventory-generator/main.tf`
2. `terraform/modules/inventory-generator/variables.tf`
3. add template files under:
   - `terraform/modules/inventory-generator/templates/`
4. `scripts/render-flux-values.sh`
5. `scripts/render-cluster-kustomization.sh`
6. `scripts/render-terraform-tfvars.sh`
7. `scripts/cluster-up-github-workspace.sh`

### Required changes

#### 1. Replace `yamlencode(...)` outputs for tracked YAML files

Create text templates for:

- `metallb-values.yaml`
- `lmstudio-endpoint.yaml`
- `topology-values.yaml`
- `lmstudio-values-configmap.yaml`

Render them with `templatefile(...)`.

Result:

- readable YAML in Git;
- lower diff noise;
- easier code review.

#### 2. Keep shell only as thin wrappers during transition

During this phase, shell scripts may remain, but they must only call declarative generators.

Examples:

- `render-flux-values.sh` becomes a wrapper around `tofu apply` or a small generation target;
- `cluster-up-github-workspace.sh` becomes a wrapper around a generated `k3d` config file, not a place with embedded cluster topology logic.

#### 3. Generate a `k3d` config file declaratively

Create a generated file such as:

- `.generated/k3d/github-workspace.yaml`

Then use:

- `k3d cluster create --config <file>`

instead of a long imperative shell command.

### Definition of done

- tracked YAML is no longer rendered by large shell scripts;
- generated YAML is readable;
- shell is now wrapper-level only, not architecture-level.

### Tests

- regenerate current topology files and compare semantic equivalence;
- `git diff` for generated YAML should become simpler and less noisy;
- `make run-cluster-from-scratch` must still work.

---

## Phase 5 - Introduce explicit platform bundles and profiles

### Goal

Prepare the repository for faster starts, optional stacks, and future scale.

### Current issue

`platform-infrastructure` currently installs too much at once.

### Required refactor

Create bundle-style Kustomizations such as:

- `flux/components/bundles/platform-base`
- `flux/components/bundles/platform-network`
- `flux/components/bundles/platform-agent-runtime`
- `flux/components/bundles/platform-serving`
- `flux/components/bundles/platform-context`
- `flux/components/bundles/platform-observability`
- `flux/components/bundles/platform-apps`
- `flux/components/bundles/platform-samples`

Then create profiles such as:

- `platform-profile-fast`
- `platform-profile-fast-serving`
- `platform-profile-fast-context`
- `platform-profile-full`
- `platform-profile-workspace`

### Initial recommended profile mapping

#### `local` first-run default

- base
- network
- agent-runtime
- apps
- serving optional
- context optional
- observability optional

#### `github-workspace`

- base
- network
- agent-runtime
- apps
- serving optional
- no MetalLB

#### `minipc`, `hybrid`, `hybrid-remote`

- full profile
- with clearer HA-oriented topology values

### Important rule

Do not remove the current staged model.

Instead, make the staged model point to a profile-specific composition.

### Definition of done

- fast profile exists;
- full profile exists;
- workspace profile exists;
- startup time improves because optional stacks are no longer always in the first path.

### Tests

- bootstrap `local` fast profile successfully;
- bootstrap `github-workspace` fast profile successfully;
- bootstrap one full profile successfully;
- compare cold-start time before vs after.

---

## Phase 6 - Add Weave GitOps UI as a Flux-managed optional component

### Goal

Install Flux UI without violating GitOps.

### Principle

The UI must be installed:

- via Git;
- via Flux;
- through a `HelmRelease`;
- as an optional bundle.

### Files to add

Suggested structure:

- `flux/components/weave-gitops/`
  - `helmrepository.yaml`
  - `namespace.yaml`
  - `release.yaml`
  - `kustomization.yaml`

Then optionally include it in:

- `flux/components/bundles/platform-ops-ui/`
- or `platform-profile-full`
- or `platform-profile-local-ops`

### Requirements

1. The UI must not be manually installed with ad-hoc commands.
2. Access must be documented as port-forward or gateway exposure.
3. Authentication and ingress policy must be explicit.
4. It must be possible to disable the UI by removing its bundle from the profile.

### Definition of done

- Weave GitOps UI is installed by Flux from Git.
- Removing the bundle removes the UI cleanly.
- Git remains the source of truth.

### Tests

- `flux get helmreleases -A`
- UI pod is Ready
- UI reachable via documented access method

---

## Phase 7 - Optional later phase: Flux Operator

### Goal

Introduce Flux Operator only after the repository is already stable.

### Why optional

Flux Operator manages Flux lifecycle more declaratively, but it is not required to achieve correct GitOps architecture.

For this repository, it should come later, after:

- topology generation is cleaned up;
- bundles/profiles are stable;
- docs are aligned;
- the bootstrap path is reliable.

### Suggested structure

- `flux/components/flux-operator/`
  - CRDs / release manifests depending on chosen installation method
- `flux/components/bundles/platform-flux-operator/`

### Rules

1. Do not combine introduction of Flux Operator with unrelated platform refactors.
2. Introduce it in its own isolated phase.
3. Keep a tested fallback bootstrap path available during migration.

### Definition of done

- Flux lifecycle is managed declaratively with no loss of current behavior.
- Existing GitOps roots still reconcile correctly.

### Tests

- fresh bootstrap still works;
- Flux self-management still works;
- upgrade path is documented.

---

## Phase 8 - Multi-host and future multi-cloud preparation

### Goal

Prepare the architecture for hybrid scale-out without overcomplicating single-node development.

### Required design decisions

#### 1. Distinguish datastore policy by topology

- single-node local/workspace dev may use simpler datastore choices;
- multi-server K3s must not use SQLite as the control-plane datastore.

#### 2. Define HA cluster modes explicitly

Create topology classes such as:

- `single-node-dev`
- `single-node-remote`
- `ha-embedded-etcd`
- `ha-external-datastore`

#### 3. Make registration endpoints first-class topology inputs

For future multi-host or multi-cloud, define declaratively:

- control plane registration address;
- node roles;
- network assumptions;
- load-balancer strategy;
- DNS and certificate strategy.

#### 4. Separate bootstrap assumptions from runtime profiles

A large full stack on a production-style hybrid cluster must not dictate the bootstrap experience of a laptop workspace topology.

### Suggested repository additions

- `terraform/modules/topology/`
- `terraform/modules/k3d-cluster/`
- `terraform/modules/flux-bootstrap/`
- `ansible/roles/common/`
- `ansible/roles/k3s-server/`
- `ansible/roles/k3s-agent/`
- `ansible/roles/image-prepull/`

### Definition of done

- topology model is explicit and future-proof;
- single-node dev remains simple;
- multi-host growth path is prepared.

### Tests

- validate `local` and `github-workspace` still bootstrap successfully;
- validate at least one `hybrid` topology after migration;
- document HA assumptions and datastore choice.

---

## 7. Specific file-level instructions for Codex agent

### 7.1 Files that must be treated as already correct in the active path

Do not rewrite these “from scratch”:

- `flux/components/kagent-resources/remote-mcp.yaml`
- `flux/components/kmcp-resources/echo-mcpserver.yaml`
- `flux/components/agentgateway-resources/httproutes.yaml`
- `flux/components/agentgateway-resources/mcp-backends.yaml`
- `flux/components/agentgateway-resources/mcp-routes.yaml`
- `flux/components/kagent-core/releases.yaml`
- `flux/components/platform-infrastructure/kustomization.yaml`
- `flux/components/platform-applications/kustomization.yaml`
- `flux/components/platform-infrastructure-workspace/kustomization.yaml`

These may be **extended** carefully, but not replaced using stale assumptions.

### 7.2 Files that should be corrected first

Priority order:

1. `.assets/architecture-current.svg`
2. `docs/adr/0006-canonical-llm-routing.md`
3. `README.md`
4. `docs/architecture.md`
5. `docs/commands.md`
6. `docs/OPERATIONS.md`
7. `Makefile`
8. `terraform/modules/inventory-generator/main.tf`
9. `scripts/render-flux-values.sh`
10. `scripts/render-cluster-kustomization.sh`
11. `scripts/render-terraform-tfvars.sh`
12. `scripts/cluster-up-github-workspace.sh`

### 7.3 Files or directories to mark as legacy before later removal

Mark clearly in comments/docs as legacy, but do not delete in the first pass:

- `flux/components/kagent/`
- `flux/components/kmcp/`
- `flux/components/agentgateway/`
- `flux/components/kgateway/`
- `flux/components/platform/`
- `flux/components/platform-core/`
- `flux/clusters/*`

Deletion is allowed only after all references are migrated and validated.

---

## 8. Startup-performance guidance during refactor

### Mandatory rules

1. Never use fixed mandatory sleeps as readiness logic.
2. Keep only maximum timeout budgets.
3. Advance immediately when health is actually ready.
4. Optional samples and UI must not block the core platform profile.
5. Use staged `dependsOn` and health-driven progression.

### Concrete improvements to implement later

1. separate fast vs full profiles;
2. move samples out of default path;
3. move optional UI out of core path;
4. add pre-pull/image-cache role for host-based topologies;
5. keep cold-start timeouts as max limits only.

---

## 9. Acceptance criteria for the full refactor

The refactor is successful only when all of the following are true:

1. The current working system still works.
2. Active MCP path remains gatewayed through `agentgateway`.
3. KServe remains installed and testable.
4. Documentation matches the actual manifests.
5. Shell no longer renders large tracked YAML trees.
6. OpenTofu handles topology/bootstrap outputs.
7. Kustomize is the main GitOps composition layer.
8. Helm values are used only for chart-level configuration.
9. Weave GitOps UI is installed through Flux as an optional component.
10. Flux Operator remains optional and isolated to a later phase.
11. The repository is cleaner for future multi-host and multi-cloud growth.

---

## 10. Final recommendation

Start with Phases 1 and 2 only.

Do **not** jump directly to Phase 4 or Phase 5.

The safest execution order is:

1. Phase 1
2. Phase 2
3. Phase 3
4. Phase 4
4. Phase 5
6. Phase 6
7. Phase 7 optional
8. Phase 8

This preserves the working system while progressively moving the repository toward a cleaner, more scalable, and more declarative architecture.
