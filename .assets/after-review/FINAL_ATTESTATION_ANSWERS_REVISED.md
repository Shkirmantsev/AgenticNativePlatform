# Final attestation — revised answers for the current project

Project context: **System Reliability Engineering for an AI cloud-native platform** built around **kgateway + AgentGateway + LiteLLM + kagent + KMCP + MCP + optional local runtimes such as vLLM**.

This version is aligned with the **current repository state**.

---

## Runtime map of my implementation

```text
external clients
  -> kgateway
  -> agentgateway

kagent agents
  -> agentgateway /v1/...  -> LiteLLM -> remote providers and optional local runtimes
  -> agentgateway /mcp/... -> MCP backends
```

Main repo locations referenced below:

- `infrastructure/network/kgateway/resources/*`
- `apps/ai-gateway/agentgateway/resources/*`
- `values/common/litellm/configmap.yaml`
- `apps/ai-gateway/kagent/resources/modelconfigs.yaml`
- `apps/ai-gateway/kagent/resources/agents.yaml`
- `apps/ai-models/vllm/release.yaml`
- `charts/vllm-cpu/*`
- `values/common/vllm/configmap.yaml`

---

## 1) How could we handle “agent got stuck” scenarios?

In my implementation, “agent got stuck” is handled as a **platform reliability problem**, not only as an LLM problem.

It can happen in several places:

- the agent loops between planning and tools,
- the upstream model call becomes too slow,
- the MCP session stays open but does not make progress,
- the platform receives too many recursive A2A calls.

### What is implemented now

**AgentGateway upstream timeout to LiteLLM**:
- file: `apps/ai-gateway/agentgateway/resources/policy.yaml`
- policy: `litellm-upstream-policy`
- value: `requestTimeout: 300s`

**A2A traffic throttling**:
- file: `apps/ai-gateway/agentgateway/resources/policy.yaml`
- policy: `agentgateway-kagent-a2a-rate-limit`

This gives a concrete protective boundary for recursive delegation or excessive back-and-forth traffic.

### What can be improved

The current protection is still mostly **request-centric**. A more mature production design would add:

- `maxSteps` per agent run,
- `maxToolCalls` per run,
- `maxWallClockDuration` per run,
- cancellation propagation from user request to controller to tools,
- a “stuck run reaper” that marks abandoned runs as failed.

### Exact next place to extend

Best future place:
- kagent controller / runtime settings

Already available place in the repo:
- `apps/ai-gateway/agentgateway/resources/policy.yaml`

---

## 2) Any automatic timeout / circuit breaker patterns coming out of this framework?

Yes. In my project they are layered.

### What is implemented now

### Layer 1 — AgentGateway

**Request timeout** to LiteLLM:
- `apps/ai-gateway/agentgateway/resources/policy.yaml`

### Layer 2 — kgateway

**BackendConfigPolicy** is now used on the kgateway 2.1.x line:
- `infrastructure/network/kgateway/resources/agentgateway-backend-policy.yaml`

It currently applies to `Service/agentgateway-proxy` and includes:

- `connectTimeout: 2s`
- `commonHttpProtocolOptions.idleTimeout: 60s`
- `outlierDetection`
- `circuitBreakers`

So in my implementation:

- **AgentGateway** controls the AI-aware upstream timeout,
- **kgateway** protects the north-south service path with service-level resiliency.

### What can be improved

- add carefully tuned retries,
- separate policies more aggressively for `/v1`, `/mcp`, and `/api/a2a`,
- tune thresholds using real latency and error histograms from observability.

---

## 3) How does kgateway handle model failover?

Important nuance:

> In my implementation, **kgateway does not perform model-level failover directly**.

### Role split in my project

**kgateway**:
- edge entry,
- service-level resiliency,
- protects the path to `agentgateway-proxy`.

That is implemented in:
- `infrastructure/network/kgateway/resources/agentgateway-backend-policy.yaml`

**LiteLLM**:
- provider/model routing,
- retries,
- fallback chain,
- OpenAI-compatible normalization.

That is implemented in:
- `values/common/litellm/configmap.yaml`

So the correct interview answer is:

> In my project, kgateway protects the service path and unhealthy upstream endpoints, while LiteLLM performs provider and model failover because that layer understands model aliases, providers, and fallback order.

---

## 4) Can we automatically switch from OpenAI to Claude to the local model?

Yes.

In my implementation this is handled in **LiteLLM**.

### What is implemented now

In:
- `values/common/litellm/configmap.yaml`

I use a fallback chain:

- `default-gemini` → `openai-default` → `anthropic-default` → `local-vllm`

So the platform can start from the preferred provider and continue to remote commercial alternatives and finally to the local vLLM backend.

### Why this is the right place

Because LiteLLM already centralizes:

- provider-specific auth,
- model aliases,
- retries and fallbacks,
- response normalization.

---

## 5) Could we seamlessly handle the response formats from these providers?

Yes.

### What is implemented now

The key design choice is to keep an **OpenAI-compatible contract** inside the platform.

**kagent** uses an OpenAI provider style configuration:
- `apps/ai-gateway/kagent/core/releases.yaml`
- `apps/ai-gateway/kagent/resources/modelconfigs.yaml`

**AgentGateway** routes `/v1` traffic to LiteLLM:
- `apps/ai-gateway/agentgateway/resources/backends.yaml`
- `apps/ai-gateway/agentgateway/resources/httproutes.yaml`

**LiteLLM** normalizes different providers back into the same API contract:
- `values/common/litellm/configmap.yaml`

So the agents do not need provider-specific response parsing logic.

---

## 6) Can we version the agents built from kagent?

Yes.

### What is implemented now

### 1. Git versioning

Agent definitions are stored in Git:
- `apps/ai-gateway/kagent/resources/agents.yaml`

### 2. Runtime/controller pinning

kagent runtime is pinned in:
- `apps/ai-gateway/kagent/core/releases.yaml`

### 3. In-cluster metadata versioning

I also added explicit metadata to agent CRs:
- `app.kubernetes.io/version`
- `platform.agenticnative.io/agent-version`
- `platform.agenticnative.io/prompt-version`
- `platform.agenticnative.io/release-channel`

This gives me three practical versioning layers:
- Git history,
- controller/runtime version,
- declarative version metadata on the agent resources themselves.

---

## 7) Any blue/green or canary deployment patterns for agents?

Yes, but in this architecture an agent is primarily a **declarative CR/config artifact**.

### Practical pattern in my project

The most natural patterns are:

### Blue/green by agent name

Examples:
- `team-lead-agent-assist-v1`
- `team-lead-agent-assist-v2`

### Blue/green by ModelConfig

This project is already moving in that direction because different agents now have dedicated `ModelConfig` resources:
- `k8s-a2a-model-config`
- `finnhub-model-config`
- `team-lead-model-config`

That means I can change:
- provider,
- fallback policy,
- tagging,
- FinOps policy,

without rewriting agent logic.

### What is not yet implemented as live canary routing

I do **not** yet have percentage traffic split for agent versions. That would be the next step if I want true canary behavior.

### Best next insertion points

- kgateway routing layer,
- AgentGateway routing layer,
- or caller-side agent selection logic.

---

## 8) What’s the fastmcp-python framework mentioned?

For this project, the correct answer is:

> I did not add a separate Python FastMCP application into this repository. I use the Go-based MCP path, because KMCP supports both FastMCP Python and MCP Go out of the box. I chose Go because it matches my current implementation direction and is attractive for speed and operational simplicity.

### Important project-aligned explanation

KMCP supports both:
- FastMCP Python,
- MCP Go.

The same operational workflow still applies:
- `kmcp init ...`
- `kmcp run --project-dir ...`
- `kmcp build --project-dir ...`
- `kmcp deploy ...`

So the point is not “Python only”, but:

> KMCP gives a standard MCP lifecycle, and in my project I use that lifecycle with the Go-based MCP implementation.

---

## 9) Is it the easiest path to MCP?

My project-specific answer is:

> It depends on the language. For Python teams, FastMCP is usually the fastest path. In my current project, I deliberately stay with the Go-based MCP route because KMCP supports MCP Go natively as well, and that keeps my operational workflow consistent.

### Interview-safe distinction

- fastest path for Python teams: **FastMCP Python**
- best path for this project: **MCP Go + KMCP workflow**

---

## 10) About FinOps: how much control can I have?

In this project, cost control can be applied at several layers.

### What is implemented now

### 1. Gateway-level hard throttling

- file: `apps/ai-gateway/agentgateway/resources/policy.yaml`
- request / token rate limits for `/v1`
- request / token rate limits for A2A traffic

### 2. LiteLLM routing and fallback control

- file: `values/common/litellm/configmap.yaml`
- provider order and fallback chain influence cost directly
- local vLLM is part of the fallback path

### 3. Concrete model-level budget controls

In `values/common/litellm/configmap.yaml` I now set **model-level budgets** for remote models via:

- `max_budget`
- `budget_duration`

This creates a real “rubber-meets-the-road” FinOps control point in the repository, not only a theoretical answer.

### 3b. Redis-backed budget consistency

- files:
  - `apps/context/redis/release.yaml`
  - `scripts/render-plaintext-secrets.sh`
  - `.generated/secrets/dev/platform-redis-auth.yaml`
  - `values/common/litellm/configmap.yaml`

LiteLLM provider budgets and shared rpm/tpm state are now connected to the Redis instance that already exists in the project. This is important because LiteLLM documents Redis as the mechanism used to keep budget and routing state consistent across replicas / instances.

### 4. Per-agent cost attribution foundation

- file: `apps/ai-gateway/kagent/resources/modelconfigs.yaml`
- each important agent has its own dedicated LiteLLM attribution headers, especially:
  - `team-lead-agent-assist`
  - `finnhub-agent`
  - `k8s-a2a-agent`
- each agent now injects:
  - `x-litellm-tags`
  - `x-litellm-spend-logs-metadata`

So the attribution is not generic at gateway level only. It is already attached per agent, and in the attestation I should emphasize the custom project agents such as `team-lead-agent-assist` and `finnhub-agent`.

---

## 11) Token level / per agent level

### Token-level control

Implemented at AgentGateway policy level:
- `apps/ai-gateway/agentgateway/resources/policy.yaml`

### Per-agent control

Implemented structurally via separate `ModelConfig` resources:
- `apps/ai-gateway/kagent/resources/modelconfigs.yaml`

This is important because each agent can already differ by:
- headers,
- tags,
- metadata,
- future budgets,
- future routing strategy.

In this repo the most relevant examples are `team-lead-agent-assist` and `finnhub-agent`, not only the sample `k8s-a2a-agent`.

So the correct answer is:

> Yes, token-level protection exists now, and per-agent control is structurally prepared through dedicated ModelConfig resources.

---

## 12) Can I implement custom cost controls?

Yes.

### What is already real in this repo

- gateway request/token throttling,
- LiteLLM fallback/routing order,
- model-level budgets on remote models,
- per-agent spend tags and metadata,
- local-vLLM fallback for cost reduction.

### Stronger next step

For a more advanced production design, I would extend this with:

- provider budgets,
- per-agent budgets,
- team budgets,
- alerting and reporting backed by a DB,
- emergency downgrade rules.

That next step would most naturally extend:
- `values/common/litellm/configmap.yaml`
- and an external reporting / DB layer.

---

## 13) Per-agent budgets or depth of token limits

### Today

What I can already demonstrate concretely is:

- hard request/token gates at AgentGateway,
- separate per-agent ModelConfigs,
- model-level LiteLLM budgets for remote models,
- spend attribution tags and metadata per agent.

### Next proper production design

Per-agent hard budgets would be best implemented by combining:

- per-agent `ModelConfig`,
- LiteLLM spend tracking + DB,
- tag/team/customer budget rules,
- optionally provider or policy-side downgrade rules.

So the honest answer is:

> The repository already contains the right control points. Some are enforced today, and the next step is to connect them to full spend tracking and budget enforcement.

---

## 14) vLLM is suitable for agents with many back-and-forth tool calls, or is it better for single-shot inference?

For my current project, the correct answer is:

> vLLM is already a real component of this platform. It is useful for both single-shot inference and multi-step agent workflows, but it becomes especially valuable when requests share common prompt prefixes or when multiple users/agents hit the same local serving backend.

### Why this is grounded in my repo

vLLM already exists here as a local OpenAI-compatible runtime:

- HelmRelease: `apps/ai-models/vllm/release.yaml`
- chart: `charts/vllm-cpu/*`
- values: `values/common/vllm/configmap.yaml`
- LiteLLM alias: `values/common/litellm/configmap.yaml` → `local-vllm`

### What I improved now

I explicitly enabled **prefix caching** in the vLLM runtime values:
- `values/common/vllm/configmap.yaml`
- `charts/vllm-cpu/templates/all.yaml`

That matters because repeated conversation history and repeated system/context prefixes are exactly the kind of workload where vLLM can reuse KV/prefix cache instead of recomputing the whole shared prefix again.

### Honest nuance

- if requests are highly repetitive or multi-round, vLLM helps a lot more,
- if the workload is strictly sequential, low-concurrency, and every prompt is very different, the benefit is smaller,
- so vLLM is **not only** for single-shot inference, but it shines most as a **shared inference backend**.

---

## 15) llm-d’s scheduler — helps when agents make 15 LLM calls?

The correct project-specific answer is:

> Not directly today, because llm-d is not yet deployed in this repository. But it is highly relevant as a future extension because my platform already has a gatewayed local serving layer with vLLM.

### What “15 calls” means

It means a **multi-call agent workload**, for example:

- planning,
- tool selection,
- retries,
- reflection,
- summarization,
- delegation.

So the real question is:

> can the serving/scheduling layer stay efficient when one user request fans out into many inference calls?

### How llm-d relates to my current project

My current stack already contains:

- gateway-based entry,
- AgentGateway,
- LiteLLM routing,
- local vLLM serving.

That means llm-d is most naturally associated with the **future scheduling layer around vLLM**, not with kagent logic itself.

### Why it could help later

If this platform evolves from:
- one local vLLM instance

to:
- multiple replicas,
- multiple nodes,
- multiple local inference backends,

then llm-d can become valuable because it helps decide **which inference endpoint should receive each request**, especially for cache-aware and latency-aware routing.

### Honest answer for the interview

> In my current implementation, multi-call agent workflows are handled by kagent + AgentGateway + LiteLLM + optional local vLLM. llm-d is not yet deployed, so it does not currently schedule those 15 calls. But because the project already has a gatewayed vLLM serving layer, llm-d is a very natural future step if I need cache-aware and latency-aware routing across multiple inference endpoints.

---

## Short summary for the presentation

1. **kgateway protects service-level traffic and upstream health; LiteLLM handles model/provider failover.**
2. **AgentGateway already enforces concrete timeout and throttling controls.**
3. **LiteLLM already implements multi-provider fallback and now also contains concrete remote-model budget controls.**
4. **Per-agent control exists structurally via separate ModelConfigs with tags and spend metadata.**
5. **vLLM is already in the project today, and prefix caching is now explicitly enabled to better support repeated multi-turn workloads.**
6. **llm-d is not yet deployed, but it is the natural future scheduling layer around vLLM if local inference becomes multi-endpoint or distributed.**


### FinOps clarification for agent attribution

When I show `x-litellm-spend-logs-metadata`, I should not present it as only a `k8s-a2a-agent` example. The repo already contains dedicated per-agent ModelConfigs for `team-lead-agent-assist`, `finnhub-agent`, and `k8s-a2a-agent`. For the attestation, the strongest examples are the custom project agents: `team-lead-agent-assist` as the coordinator and `finnhub-agent` as the domain specialist.

LiteLLM is also now connected to the project Redis instance, so shared provider budgets / routing counters are not left only in one proxy process memory.
