# Final attestation — revised answers for the current project

---

## 1) How could we handle “agent got stuck” scenarios?

In my implementation, “agent got stuck” is not treated as only an LLM problem. It can happen in four places:

- the agent loops between planning and tool-calls,
- the upstream LLM call becomes too slow,
- an MCP session remains open but stops making progress,
- the controller or gateway receives too many recursive A2A requests.

### What is implemented now

**Request-level timeout already exists** in AgentGateway for the `/v1` path to LiteLLM:
- `apps/ai-gateway/agentgateway/resources/policy.yaml`
- policy: `litellm-upstream-policy`
- value: `requestTimeout: 300s`

**Runaway traffic throttling** is now added for A2A traffic:
- `apps/ai-gateway/agentgateway/resources/policy.yaml`
- new policy: `agentgateway-kagent-a2a-rate-limit`

This is useful for demo and attestation because it gives a very concrete answer to the customer: if an agent starts recursively delegating or looping through tools, the platform now has a hard protective limit on the A2A route.

### What can be improved

The current protection is still mostly **request-centric**. A more mature production design would add **run-centric** controls:

- `maxSteps` per agent run,
- `maxToolCalls` per run,
- `maxWallClockDuration` per run,
- cancellation propagation from user request → controller → tool session,
- “stuck run reaper” job that marks abandoned runs as failed.

### Exact next place to extend

Best future place:
- **kagent controller / agent runtime settings** for step-count and run-duration guardrails.

Already available place in your repo:
- `apps/ai-gateway/agentgateway/resources/policy.yaml`
- tighten A2A and `/v1` limits per environment.

---

## 2) Any automatic timeout/circuit breaker patterns coming out of this framework?

Yes, but in the **current cluster-compatible version** the answer must be precise.

### What is implemented now

**AgentGateway** already gives me supported backend timeout and health/eviction controls for the LiteLLM upstream:
- `apps/ai-gateway/agentgateway/resources/policy.yaml`
- policy: `litellm-upstream-policy`
- implemented with:
  - `backend.tcp.connectTimeout: 2s`
  - `backend.http.requestTimeout: 300s`
  - `backend.health.unhealthyCondition: "response.code >= 500"`
  - eviction controls: `consecutiveFailures`, `healthThreshold`, `duration`, `restoreHealth`

So today the project already has:
- hard timeout behavior,
- passive unhealthy-backend detection,
- temporary eviction/recovery behavior for a bad LiteLLM upstream.

### Important truthful limitation

The **exact kgateway `BackendConfigPolicy` feature set** with:
- `circuitBreakers`,
- `outlierDetection`,

is **not active in the current repo version anymore**, because that requires a kgateway line that supports `BackendConfigPolicy` in-cluster. I removed that patch so the cluster stays consistent with the current runtime.

### What can be improved

Next production step:

- add retry budgets carefully,
- separate `/api`, `/v1`, and `/mcp` traffic classes more aggressively,
- tune thresholds using observed latency/error histograms rather than static demo numbers.

### Exact future path if I need the native kgateway feature set

If I later want the **exact** kgateway `circuitBreakers` + `outlierDetection` behavior, the correct place to upgrade is:
- `infrastructure/sources/ocirepositories.yaml`
- `infrastructure/network/kgateway/core/release.yaml`

Until then, the safe and truthful answer is: **timeouts and backend health/eviction are implemented now through AgentGatewayPolicy; full BackendConfigPolicy-style circuit breakers are a future upgrade path.**

---

## 3) How does kgateway handle model failover?

In my project, **kgateway does not perform model-level failover directly**.

That distinction is important in the interview.

### Current role split

**kgateway**:
- edge entry,
- routing into the platform,
- north-south traffic management.

**AgentGateway**:
- backend timeout control for LiteLLM,
- passive unhealthy-backend detection and eviction for the LiteLLM upstream.
- exact file: `apps/ai-gateway/agentgateway/resources/policy.yaml`

**LiteLLM**:
- model/provider routing,
- fallback chain,
- response normalization.
- exact file: `values/common/litellm/configmap.yaml`

So the truthful explanation is:
> In my implementation, kgateway is the entry/routing layer, AgentGateway protects the immediate AI upstream connection, and model failover itself is intentionally implemented in LiteLLM, because that layer understands providers, aliases, and fallback policy.

### Important architectural note

If later I want **kgateway-native backend circuit breakers and outlier detection**, that is a separate future upgrade path. But in the current cluster-compatible version, I do **not** claim that kgateway itself is already doing model failover or native BackendConfigPolicy-based backend protection.

---

## 4) Can we automatically switch from OpenAI to Claude to the local model?

Yes. In my implementation this is handled in **LiteLLM**, not in kagent and not in kgateway.

### What is implemented now

In:
- `values/common/litellm/configmap.yaml`

I added router-level fallback:

- `default-gemini` → `openai-default` → `anthropic-default` → `local-vllm`

That means the platform can start with a preferred provider and then automatically continue through commercial providers and finally to the local vLLM backend.

### Why this is the right place

Because LiteLLM already acts as the provider abstraction layer for:

- provider-specific auth,
- model aliases,
- OpenAI-compatible normalization,
- retries and fallbacks.

So the switching logic belongs there.

### What can be improved

- split fallback chains by error type,
- separate “budget fallback” from “availability fallback”,
- add a dedicated cheap-local-first chain for non-critical workloads.

---

## 5) Could we seamlessly handle the response formats from these providers?

Yes.

In my implementation, the key design choice is to use an **OpenAI-compatible contract** internally.

### What is implemented now

**kagent ModelConfig** points to AgentGateway `/v1` as an OpenAI provider style endpoint:
- `apps/ai-gateway/kagent/core/releases.yaml`
- `apps/ai-gateway/kagent/resources/modelconfigs.yaml`

**AgentGateway** routes `/v1` to LiteLLM:
- `apps/ai-gateway/agentgateway/resources/backends.yaml`

**LiteLLM** normalizes multiple providers back into the OpenAI-style response contract:
- `values/common/litellm/configmap.yaml`

That is why the agents do not need separate parsing logic for OpenAI, Anthropic, Gemini, or local OpenAI-compatible vLLM.

---

## 6) Can we version the agents built from kagent?

Yes.

### In the current project

1. **Git versioning of agent definitions**
   - `apps/ai-gateway/kagent/resources/agents.yaml`
   - every change is versioned by Git commits.

2. **Controller/runtime version pinning**
   - `apps/ai-gateway/kagent/core/releases.yaml`
   - kagent image/tag is pinned there.

### What can be improved

Add explicit labels/annotations such as:
- `app.kubernetes.io/version`
- `platform.example.com/prompt-version`
- `platform.example.com/agent-schema-version`

This makes attestation easier because you can show both Git history and in-cluster runtime metadata.

---

## 7) Any blue/green or canary deployment patterns for agents?

Yes, but in this setup an agent is mostly a **declarative CR/config artifact**, not a heavyweight standalone service.

### Practical patterns in this project

**Blue/green by agent name / config version**
- deploy `team-lead-agent-assist-v1`
- deploy `team-lead-agent-assist-v2`
- switch callers or route selection policy

**Blue/green by ModelConfig**
- current improvement already moves you toward that by separating model configs:
  - `k8s-a2a-model-config`
  - `finnhub-model-config`
  - `team-lead-model-config`

That is useful because you can change provider, headers, or budgets per agent without editing the agent logic itself.

### Further step

For true percentage canary you would need traffic split in front of the execution path, typically at:
- kgateway,
- AgentGateway,
- or at the caller selection logic.

---

## 8) What’s the fastmcp-python framework mentioned?

For the attestation, I would now answer this question in a project-aligned way:

> In my project I did **not** add a new Python FastMCP application. I already use a Go-based MCP server approach, and KMCP supports both Python FastMCP and Go-based MCP projects out of the box. I chose Go because it fits my existing implementation direction and is attractive for speed and lower operational overhead.

### Important project-aligned explanation

KMCP officially supports developing MCP servers with both:
- **FastMCP Python**, and
- **MCP Go**. 

KMCP can scaffold Go projects, and the same operational pattern still applies:
- `kmcp init go ...`
- `kmcp run --project-dir ...`
- `kmcp build --project-dir ...`
- `kmcp deploy ...`

So the answer is:
> FastMCP Python is one of the supported ways to build MCP servers, but in my implementation I use the Go path because KMCP supports MCP Go as well, and the same KMCP run/build/deploy workflow remains available.

---

## 9) Is it the easiest path to MCP?

My answer for this project would be:

> The easiest path depends on language choice. For Python, FastMCP is usually the fastest way to start. In my project, however, I deliberately stay with Go-based MCP implementation, because KMCP supports MCP Go natively too, and that lets me keep one consistent operational workflow while using Go for speed and deployment simplicity.

### Interview-safe distinction

- **Fastest path for Python teams**: FastMCP Python.
- **Best path for my current project**: MCP Go with KMCP commands and Kubernetes deployment workflow.

---

## 10) About FinOps: how much control can I have?

In this project, control can be applied on several layers.

### Current practical control points

1. **AgentGateway rate limits**
   - hard request/token throttling
   - file: `apps/ai-gateway/agentgateway/resources/policy.yaml`

2. **LiteLLM routing and fallback policy**
   - choose cheaper or local backends first
   - file: `values/common/litellm/configmap.yaml`

3. **Per-agent tagging foundation**
   - file: `apps/ai-gateway/kagent/resources/modelconfigs.yaml`
   - tags can later be used for reporting or budgets downstream.

### Meaning for the customer

This means I can control cost not only globally, but also by:
- route,
- model,
- agent,
- provider order,
- local-vs-remote preference.

---

## 11) Token level / per agent level

### What is implemented now

**Token-level protection** exists now at AgentGateway policy level.

**Per-agent separation** is now improved through dedicated `ModelConfig` resources:
- `apps/ai-gateway/kagent/resources/modelconfigs.yaml`

This is important because it creates an architectural place where each agent can later have:
- different provider,
- different headers/tags,
- different budget class,
- different fallback chain.

---

## 12) Can I implement custom cost controls?

Yes.

### Immediate controls in this repo

- hard token/request gates in AgentGateway,
- custom provider priority in LiteLLM,
- local-model fallback to reduce remote-provider spend,
- per-agent tags via ModelConfig.

### Stronger next step

Introduce budget enforcement logic at the LiteLLM layer and/or a separate policy service that evaluates:
- estimated token usage,
- per-agent monthly budget,
- provider-specific cost ceilings,
- emergency downgrade rules.

---

## 13) Per-agent budgets or depth of token limits

Today in this project, the strongest ready-to-show control is:
- gateway token/request ceilings,
- per-agent model separation.

### Next proper production design

Per-agent budget enforcement should use:
- per-agent tags,
- budget tables/config,
- routing policies that downgrade or deny when the budget is exceeded.

That work would most naturally connect to:
- `apps/ai-gateway/kagent/resources/modelconfigs.yaml`
- `values/common/litellm/configmap.yaml`
- optionally an external DB/reporting component.

---

## 14) vLLM is suitable for agents with many back-and-forth tool calls, or is it better for single-shot inference?

For **my existing project**, the correct nuanced answer is:

> vLLM is already a good fit in this platform, but it is most beneficial when there is enough request volume or enough repeated prompt structure to benefit from efficient serving and KV/prefix-cache reuse. It is not limited to single-shot inference.

### Why this matters in my project

I already have vLLM in the repo as a local OpenAI-compatible backend:

- HelmRelease: `apps/ai-models/vllm/release.yaml`
- values: `values/common/vllm/configmap.yaml`
- chart: `charts/vllm-cpu/*`
- LiteLLM route alias: `values/common/litellm/configmap.yaml` → `local-vllm`

So in my architecture, vLLM is not theoretical — it is already part of the designed runtime path.

### How to explain its role correctly

vLLM is strong for:
- **OpenAI-compatible serving**,
- **high-throughput batching**,
- **prefix/KV cache reuse**,
- **shared local inference service for many calls**.

That means it can help both:
- **single-shot inference**, and
- **multi-step agent workflows**.

But the benefit is different.

### For single-shot inference

vLLM is helpful because it provides a stable local serving endpoint and can batch requests efficiently.

### For many back-and-forth tool calls

vLLM becomes useful when:
- the agent repeatedly calls the model,
- prompts share common prefixes/system instructions,
- multiple agents/users hit the same serving backend.

In that case, prefix/KV-cache reuse can reduce repeated prompt computation and improve effective throughput.

### Important limitation to say honestly

If the workflow is **strictly sequential** and every turn is very different, with little shared prefix and low concurrency, then vLLM gives less advantage than in high-throughput serving scenarios. In other words:

- vLLM is **not only** for single-shot inference,
- but it shines more as a **shared inference engine** than as a magic accelerator for one isolated agent loop.

### Concrete places in my repo to evolve vLLM

1. `charts/vllm-cpu/templates/all.yaml`
   - today it runs:
     - one replica,
     - `--max-model-len 2048`
   - future tuning could add more serving flags and model-specific options.

2. `charts/vllm-cpu/values.yaml`
   - resources,
   - PVC size,
   - CPU cache-related env values.

3. `values/common/vllm/configmap.yaml`
   - environment-specific image/model/cache sizing.

4. `values/common/litellm/configmap.yaml`
   - routing policy deciding when `local-vllm` is primary, fallback, or budget-saving option.

---

## 15) llm-d’s scheduler — helps when agents make 15 LLM calls?

The short answer for my project is:

> Not directly today, because llm-d is not yet deployed in this repository. But it is highly relevant as a future 
> extension specifically because my platform already includes vLLM and gateway-based routing.

### What “15 calls” really means

Understanding  **multi-call agent workload**:

- one user request,
- then many LLM turns for planning, tool selection, reflection, retries, summarization, and delegation.

So “15 calls” means:
> does the serving/control plane still behave well when one agent run fans out into many inference requests?

### How llm-d relates to your project

My project already has the foundations that make llm-d relevant later:

- gateway-based entry,
- agent execution layer,
- LiteLLM routing layer,
- vLLM local serving backend.

llm-d is most naturally associated with the **serving/scheduling layer around vLLM**, not with kagent logic itself.

### Why llm-d could help in the future

llm-d’s scheduler is designed to route inference requests using scheduler plugins and cache-aware / latency-aware logic.
That matters when many LLM requests are sent across one or more backends, especially if you want better utilization and lower latency variance.

So if in the future my platform evolves from:
- one local vLLM instance

to:
- multiple replicas,
- multiple nodes,
- or multiple serving backends,

then llm-d can become valuable because it helps decide **which serving endpoint should receive each inference request**.

### Honest project-specific answer

For my current repo:
- **No, llm-d is not yet an active capability in the current deployment**.
- **Yes, it is a realistic future enhancement because I already have vLLM in the stack**.


> In my current implementation, multi-call agent workflows are handled by kagent + AgentGateway + LiteLLM + optional local vLLM. llm-d is not yet deployed, so it does not currently schedule those 15 calls. But because my platform already has a gatewayed local serving layer with vLLM, llm-d is a very natural next step if I need cache-aware, latency-aware routing across multiple inference backends or replicas.

### Exact future insertion points

If I decide to explore llm-d later, the best architectural place is between the AI routing layer and the local 
distributed inference backends.

In practice, that means reviewing and evolving:
- `apps/ai-models/vllm/*`
- `charts/vllm-cpu/*`
- `values/common/litellm/configmap.yaml`
- and the northbound routing contract used by AgentGateway.

---

## Summary for my presentation

1. **kgateway is the entry/routing layer; model semantics stay elsewhere.**
2. **AgentGateway currently provides the implemented backend timeout and health/eviction controls for LiteLLM.**
3. **LiteLLM is where provider failover and response normalization live.**
4. **vLLM already exists in the project today; llm-d is the logical future scaling/scheduling layer around it, not a replacement for kagent.**
