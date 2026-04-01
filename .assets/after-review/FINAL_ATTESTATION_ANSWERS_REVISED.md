# Final attestation — revised answers for the current project

Project context: **System Reliability Engineering for an AI cloud-native platform** built around **Flux + kgateway + AgentGateway + LiteLLM + kagent + KMCP/MCP + optional local runtimes such as vLLM**.

This version is aligned with the **current intended repository state after the edge split**:

- kgateway stays on the **2.1.x line**
- external edge traffic is split into **two kgateway Backends**
  - `agentgateway-llm-edge` for `/v1`
  - `agentgateway-mcp-edge` for `/mcp`
- **circuit breakers are applied only to the LLM edge backend**
- MCP keeps a separate resiliency profile without aggressive circuit breakers
- internal kagent traffic continues to go through **AgentGateway proxy inside the cluster**, not directly to LiteLLM or MCP servers
- Flux ordering is protected by `dependsOn` plus **`healthChecks`** on kgateway CRDs and Helm releases before runtime objects are applied

---

## Runtime map of my implementation

```text
external clients
  -> kgateway public-gateway
     -> /v1  -> kgateway Backend agentgateway-llm-edge -> agentgateway-proxy -> LiteLLM -> providers / local runtimes
     -> /mcp -> kgateway Backend agentgateway-mcp-edge -> agentgateway-proxy -> MCP backends

kagent agents inside cluster
  -> agentgateway-proxy /v1/...  -> LiteLLM -> remote providers and optional local runtimes
  -> agentgateway-proxy /mcp/... -> MCP backends via AgentGateway
```

Main repo locations referenced below:

- `infrastructure/network/kgateway/resources/*`
- `clusters/*/infrastructure.yaml`
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

**Edge-path protection split by protocol role**:
- file: `infrastructure/network/kgateway/resources/agentgateway-backend-policy.yaml`
- `/v1` is protected with `connectTimeout`, `idleTimeout`, `outlierDetection`, and `circuitBreakers`
- `/mcp` keeps `connectTimeout`, long `idleTimeout`, and `outlierDetection`, but no aggressive circuit breakers

This separation is important because MCP uses long-lived Streamable HTTP sessions and should not compete with LLM request bursts under the same breaker budget.

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

Already available places in the repo:
- `apps/ai-gateway/agentgateway/resources/policy.yaml`
- `infrastructure/network/kgateway/resources/agentgateway-backend-policy.yaml`

---

## 2) Any automatic timeout / circuit breaker patterns coming out of this framework?

Yes. In my project they are layered.

### What is implemented now

### Layer 1 — AgentGateway

**Request timeout** to LiteLLM:
- `apps/ai-gateway/agentgateway/resources/policy.yaml`

### Layer 2 — kgateway

**BackendConfigPolicy** is used on the kgateway 2.1.x line:
- `infrastructure/network/kgateway/resources/agentgateway-backend-policy.yaml`

It is attached to **separate kgateway Backends**, not to one shared Service policy anymore:

- `agentgateway-llm-edge` for `/v1`
- `agentgateway-mcp-edge` for `/mcp`

That means in my implementation:

- **AgentGateway** controls the AI-aware upstream timeout and internal traffic policy,
- **kgateway** protects the external north-south path,
- **LLM edge traffic** can use circuit breakers,
- **MCP edge traffic** keeps a different resiliency profile to avoid breaking stream sessions.

### Why this design is important

If `/v1` and `/mcp` share one breaker budget, MCP stream sessions and LLM bursts compete with each other. That is exactly the kind of coupling that can make the agent catalog, tool loading, or MCP session setup appear broken even when the cluster itself is healthy.

### What can be improved

- add carefully tuned retries only where they are safe,
- tune thresholds using real latency and overflow metrics,
- introduce dedicated edge paths for more traffic classes if needed.

---

## 3) How does kgateway handle model failover?

Important nuance:

> In my implementation, **kgateway does not perform model-level failover directly**.

### Role split in my project

**kgateway**:
- edge entry,
- service-level resiliency,
- path split between `/v1` and `/mcp`,
- protects the path to `agentgateway-proxy`.

That is implemented in:
- `infrastructure/network/kgateway/resources/agentgateway-backends.yaml`
- `infrastructure/network/kgateway/resources/routes.yaml`
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

- additional Agent CR versions in `apps/ai-gateway/kagent/resources/agents.yaml`
- future edge routing rules in `kgateway` or internal policy in `AgentGateway`

---

## 8) What’s the fastmcp-python framework mentioned?

In the attestation answer for my project, I should be precise:

> I did not add an extra Python FastMCP application to this repository. In this project I use the Go-based MCP path, because KMCP supports both FastMCP Python and MCP Go out of the box, and the same operational lifecycle still applies: `kmcp init`, `kmcp run`, `kmcp build`, and deployment through KMCP resources.

### What I use in this project

- custom Go MCP server:
  - `mcp/finnhub-mcp-server/*`
- KMCP/Kubernetes resources:
  - `apps/platform/kmcp/resources/*`

So the right answer is not “I used fastmcp-python here”, but rather:

> fastmcp-python is one supported path to MCP, but in my implementation I chose Go for this custom MCP server.

---

## 9) Is it the easiest path to MCP?

For Python projects, FastMCP is often the easiest path.

For **this repository**, the correct project-specific answer is:

> I used the Go route instead, because my custom MCP implementation here is a Go service and KMCP already supports that path cleanly. Operationally, the lifecycle is still simple: local run, image build, and Kubernetes deployment through KMCP.

So for my project, the easiest path was not “Python first”, but:
- KMCP + MCP Go for the custom backend,
- AgentGateway + RemoteMCPServer for exposure and controlled access.

---

## 10) About FinOps: how much control can I have?

A lot, and the control exists at several layers.

### What is implemented now

### AgentGateway

Hard request/token throttling:
- `apps/ai-gateway/agentgateway/resources/policy.yaml`

### LiteLLM

Per-model / per-provider budget controls and routing metadata:
- `values/common/litellm/configmap.yaml`

### Redis-backed consistency for LiteLLM accounting

Redis already exists in the project and is connected to LiteLLM so that shared counters and spend/budget state can be kept consistent across LiteLLM instances.

Relevant locations:
- `apps/context/redis/release.yaml`
- `scripts/render-plaintext-secrets.sh`
- `values/common/litellm/configmap.yaml`
- `charts/litellm-proxy/templates/deployment.yaml`

So my FinOps control is not only conceptual. It has:
- gateway hard limits,
- LiteLLM spend metadata,
- model/provider budget knobs,
- Redis-backed shared state.

---

## 11) Token level / per agent level

### What is implemented now

**Token-level control**:
- AgentGateway local rate limits

**Per-agent attribution**:
- `apps/ai-gateway/kagent/resources/modelconfigs.yaml`

Each important agent has its own headers and metadata, for example:
- `team-lead-agent-assist`
- `finnhub-agent`
- `k8s-a2a-agent`

I use:
- `x-litellm-tags`
- `x-litellm-spend-logs-metadata`

This means I can identify which agent generated the spend, rather than treating all traffic as one anonymous platform bucket.

---

## 12) Can I implement custom cost controls?

Yes.

### In my current implementation

I already have the building blocks:

- AgentGateway hard throttling,
- LiteLLM model budgets,
- per-agent spend metadata,
- Redis-backed shared spend/routing state.

### Next stronger step

The next production step would be to make budget enforcement more explicit by agent/team/tag and connect that to reporting dashboards.

Best insertion points:
- `values/common/litellm/configmap.yaml`
- observability / dashboards layer

---

## 13) Per-agent budgets or depth of token limits

### What is implemented now

**Per-agent attribution** is already implemented.

**Budget-ready model configuration** is already present in LiteLLM.

So my honest answer is:

> Today I already have per-agent attribution and model/provider budget controls. The next step is to promote those controls into stricter per-agent budget enforcement and richer dashboards.

That is a strong answer because it shows both current implementation and realistic next evolution.

---

## 14) vLLM is suitable for agents with many back-and-forth tool calls, or is it better for single-shot inference?

In my project, vLLM is not just theoretical. It already exists as an optional local serving path.

Relevant repo locations:
- `apps/ai-models/vllm/release.yaml`
- `charts/vllm-cpu/*`
- `values/common/vllm/configmap.yaml`

### Correct project-specific answer

vLLM can serve both:
- single-shot inference,
- multi-step agent workflows.

In agentic systems its bigger advantage appears when there are:
- repeated system-prompt prefixes,
- many similar requests,
- enough concurrency to benefit from batching and cache reuse.

In this project I explicitly enable prefix-caching-related runtime arguments on the vLLM side, because that is the scenario where repeated agent/tool workflows benefit most.

So my answer is:

> In my platform, vLLM is suitable for agents too, especially when there are repeated prompt prefixes and enough concurrency to benefit from batching and cache reuse. It is not limited to single-shot inference.

---

## 15) llm-d’s scheduler — helps when agents make 15 LLM calls?

Yes, but with an important scope clarification.

### What “15 LLM calls” really means

It means a **multi-call agent workload**:
- planning,
- tool-selection,
- follow-up inference,
- retries,
- summarization,
- delegation.

### What is true in my project today

Today those repeated calls are handled by:
- kagent
- AgentGateway
- LiteLLM
- optional local vLLM

**llm-d is not yet deployed in this repository today.**

### Why it still matters architecturally

Because llm-d becomes relevant when:
- local inference grows beyond one backend,
- multiple replicas or distributed serving are introduced,
- cache-aware and latency-aware request placement becomes important.

So my project-specific answer is:

> Today llm-d does not schedule requests in this repo yet. But because I already have gatewayed local model serving and an agentic multi-call architecture, llm-d is a natural future step if I want cache-aware and latency-aware scheduling across multiple inference backends or replicas.

---

## GitOps / ordering nuance that matters in this project

One operational lesson from this repository is very important for the defense:

When using `BackendConfigPolicy`, Flux must apply runtime custom resources **only after**:
- kgateway CRDs are installed,
- kgateway is ready,
- the CRD `backendconfigpolicies.gateway.kgateway.dev` is visible to the API server.

So in my project I rely on:
- `dependsOn` between the staged `Kustomization` objects,
- and `healthChecks` in `platform-infrastructure` for kgateway readiness before runtime resources are considered safe to apply.

This is a strong SRE point because it shows that platform reliability here depends not only on the resource content, but also on correct GitOps ordering and readiness semantics.
