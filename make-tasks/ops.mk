.PHONY: diagnose-runtime-state recover-paused-workloads \
	cluster-pause cluster-resume cluster-stop cluster-start cluster-remove remove-cluster-only environment-destroy destroy-cluster-and-infra \
	k9s-local \
	port-forward-agentgateway port-forward-kagent port-forward-kagent-ui port-forward-litellm port-forward-grafana port-forward-prometheus port-forward-qdrant port-forward-flux-operator-ui \
	open-kagent-ui close-kagent-ui open-kagent-a2a close-kagent-a2a open-agentgateway close-agentgateway open-litellm close-litellm open-grafana close-grafana open-prometheus close-prometheus open-qdrant close-qdrant open-flux-operator-ui close-flux-operator-ui open-research-access close-research-access \
	check-kagent-ui check-agentgateway check-agentgateway-openai check-litellm check-flux-operator-ui check-flux-stages \
	test-a2a-agent test-finnhub-agent-card test-team-lead-agent-card test-agentgateway-gemini test-agentgateway-openai test-litellm

diagnose-runtime-state: require-kubeconfig ## Show staged Flux, paused-namespace workload state, and key service endpoints
	@echo "== Flux Kustomizations =="; \
	$(FLUX) get kustomizations -A || true
	@echo
	@echo "== Flux HelmReleases =="; \
	$(FLUX) get helmreleases -A || true
	@echo
	@echo "== Pause State ConfigMap =="; \
	if $(KUBECTL) -n flux-system get configmap "$(PAUSE_STATE_CONFIGMAP)" >/dev/null 2>&1; then \
	  $(KUBECTL) -n flux-system get configmap "$(PAUSE_STATE_CONFIGMAP)" -o jsonpath='{.metadata.name}{" savedAt="}{.data.savedAt}{" namespaces="}{.data.namespaces}{"\n"}'; \
	else \
	  echo "ConfigMap/flux-system/$(PAUSE_STATE_CONFIGMAP) is missing"; \
	fi
	@echo
	@echo "== ai-gateway / ai-models / context Deployments and StatefulSets =="; \
	$(KUBECTL) get deploy,statefulset -A -o custom-columns='KIND:.kind,NAMESPACE:.metadata.namespace,NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas' | awk 'NR==1 || $$2=="ai-gateway" || $$2=="ai-models" || $$2=="context"'
	@echo
	@echo "== Zero-replica workloads across the cluster =="; \
	zero_list="$$( $(KUBECTL) get deploy,statefulset -A -o custom-columns='KIND:.kind,NAMESPACE:.metadata.namespace,NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas' | awk 'NR==1 || $$4==0' )"; \
	echo "$$zero_list"
	@echo
	@echo "== Key Service endpoint counts =="; \
	for pair in "agentgateway-system agentgateway-proxy" "ai-gateway litellm" "context context-qdrant" "context context-postgres-postgresql"; do \
	  set -- $$pair; \
	  addresses="$$( $(KUBECTL) -n $$1 get endpoints $$2 -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{" "}{end}' 2>/dev/null || true )"; \
	  count="$$(printf '%s\n' "$$addresses" | wc -w | tr -d ' ')"; \
	  echo "$$1/$$2 endpoints=$$count"; \
	done

recover-paused-workloads: require-kubeconfig ## Restore paused workloads, force a fresh reconcile, and print runtime status
	@if $(KUBECTL) -n flux-system get configmap "$(PAUSE_STATE_CONFIGMAP)" >/dev/null 2>&1; then \
	  echo "Restoring saved replica targets from ConfigMap/flux-system/$(PAUSE_STATE_CONFIGMAP)"; \
	  PAUSE_STATE_CONFIGMAP="$(PAUSE_STATE_CONFIGMAP)" STATE_NAMESPACE=flux-system ./scripts/restore-paused-workloads.sh; \
	fi
	@fallback_needed=0; \
	for ns in $(PAUSE_NAMESPACES); do \
	  $(KUBECTL) get ns $$ns >/dev/null 2>&1 || continue; \
	  for kind in deployment statefulset; do \
	    zero_names="$$( $(KUBECTL) -n $$ns get $$kind -o jsonpath='{range .items[?(@.spec.replicas==0)]}{.metadata.name}{"\n"}{end}' 2>/dev/null )"; \
	    if [ -n "$$zero_names" ]; then \
	      fallback_needed=1; \
	    fi; \
	  done; \
	done; \
	if [ "$$fallback_needed" -eq 1 ]; then \
	  echo "Saved pause state left workloads at 0 replicas; scaling zero-replica workloads in $(PAUSE_NAMESPACES) back to 1 as a fallback."; \
	  for ns in $(PAUSE_NAMESPACES); do \
	    $(KUBECTL) get ns $$ns >/dev/null 2>&1 || continue; \
	    for kind in deployment statefulset; do \
	      zero_names="$$( $(KUBECTL) -n $$ns get $$kind -o jsonpath='{range .items[?(@.spec.replicas==0)]}{.metadata.name}{"\n"}{end}' 2>/dev/null )"; \
	      [ -n "$$zero_names" ] || continue; \
	      for name in $$zero_names; do \
	        echo "Scaling $$kind/$$ns/$$name -> 1"; \
	        $(KUBECTL) -n $$ns scale $$kind/$$name --replicas=1; \
	      done; \
	    done; \
	  done; \
	fi
	@$(MAKE) reconcile TOPOLOGY=$(TOPOLOGY) ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED)
	@$(MAKE) diagnose-runtime-state TOPOLOGY=$(TOPOLOGY) ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED)

cluster-pause: require-cluster-api ## Pause platform workloads without uninstalling the cluster
	@PAUSE_NAMESPACES="$(PAUSE_NAMESPACES)" PAUSE_STATE_CONFIGMAP="$(PAUSE_STATE_CONFIGMAP)" STATE_NAMESPACE=flux-system ./scripts/save-paused-workloads.sh
	@for k in $(PLATFORM_KUSTOMIZATIONS); do \
	  $(KUBECTL) -n flux-system get kustomization $$k >/dev/null 2>&1 || continue; \
	  $(FLUX) suspend kustomization $$k -n flux-system || true; \
	done
	@$(FLUX) suspend source git $(FLUX_SYNC_SOURCE_NAME) -n flux-system || true
	@for hr in $$($(KUBECTL) -n flux-system get helmrelease -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do \
	  $(FLUX) suspend helmrelease $$hr -n flux-system || true; \
	done
	@for ns in $(PAUSE_NAMESPACES); do \
	  $(KUBECTL) get ns $$ns >/dev/null 2>&1 || continue; \
	  $(KUBECTL) -n $$ns get deploy -o name 2>/dev/null | xargs -r -n1 $(KUBECTL) -n $$ns scale --replicas=0; \
	  $(KUBECTL) -n $$ns get statefulset -o name 2>/dev/null | xargs -r -n1 $(KUBECTL) -n $$ns scale --replicas=0; \
	done
	@echo "cluster-pause completed: Flux roots and HelmReleases are suspended, selected app/data replica targets were snapshotted, and pausable workloads were scaled to 0."
	@echo "Infrastructure namespaces remain running by design so ambient, gateways, controllers, and cached images stay warm for fast resume."

cluster-resume: require-cluster-api ## Resume platform workloads from Git desired state
	@$(FLUX) resume source git $(FLUX_SYNC_SOURCE_NAME) -n flux-system || true
	@for hr in $$($(KUBECTL) -n flux-system get helmrelease -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do \
	  $(FLUX) resume helmrelease $$hr -n flux-system || true; \
	done
	@for k in $(PLATFORM_KUSTOMIZATIONS); do \
	  $(KUBECTL) -n flux-system get kustomization $$k >/dev/null 2>&1 || continue; \
	  $(FLUX) resume kustomization $$k -n flux-system || true; \
	done
	@$(FLUX) reconcile source git $(FLUX_SYNC_SOURCE_NAME) -n flux-system || true
	@$(FLUX) reconcile kustomization platform-infrastructure -n flux-system --with-source || true
	@PAUSE_STATE_CONFIGMAP="$(PAUSE_STATE_CONFIGMAP)" STATE_NAMESPACE=flux-system ./scripts/restore-paused-workloads.sh
	@token="$$(date -u +"%Y-%m-%dT%H:%M:%SZ")"; \
	for hr in $$($(KUBECTL) -n flux-system get helmrelease -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do \
	  $(KUBECTL) -n flux-system annotate --overwrite helmrelease $$hr \
	    reconcile.fluxcd.io/requestedAt="$$token" \
	    reconcile.fluxcd.io/forceAt="$$token" \
	    reconcile.fluxcd.io/resetAt="$$token" || true; \
	done
	@for k in platform-secrets platform-applications; do \
	  $(KUBECTL) -n flux-system get kustomization $$k >/dev/null 2>&1 || continue; \
	  $(FLUX) reconcile kustomization $$k -n flux-system --with-source || true; \
	done

cluster-stop: ## Deprecated alias for cluster-pause
	@$(MAKE) cluster-pause TOPOLOGY=$(TOPOLOGY) ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED) IAC_TOOL=$(IAC_TOOL) TF_BIN=$(TF_BIN) ANSIBLE_INVENTORY="$(ANSIBLE_INVENTORY)" ANSIBLE_BECOME_FLAGS="$(ANSIBLE_BECOME_FLAGS)"

cluster-start: ## Deprecated alias for cluster-resume
	@$(MAKE) cluster-resume TOPOLOGY=$(TOPOLOGY) ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED) IAC_TOOL=$(IAC_TOOL) TF_BIN=$(TF_BIN) ANSIBLE_INVENTORY="$(ANSIBLE_INVENTORY)" ANSIBLE_BECOME_FLAGS="$(ANSIBLE_BECOME_FLAGS)"

remove-cluster-only: ## Remove the cluster only; keep Terraform/OpenTofu infrastructure, generated assets, and downloaded images/resources
	@if [ "$(TOPOLOGY)" = "github-codespace" ]; then \
	  WORKSPACE_CLUSTER_NAME="$(WORKSPACE_CLUSTER_NAME)" ./scripts/cluster-remove-github-codespace.sh; \
	else \
	  $(MAKE) uninstall-k3s TOPOLOGY=$(TOPOLOGY) ANSIBLE_INVENTORY="$(ANSIBLE_INVENTORY)" ANSIBLE_BECOME_FLAGS="$(ANSIBLE_BECOME_FLAGS)"; \
	fi

cluster-remove: ## Compatibility alias for remove-cluster-only
	@$(MAKE) remove-cluster-only TOPOLOGY=$(TOPOLOGY) ANSIBLE_INVENTORY="$(ANSIBLE_INVENTORY)" ANSIBLE_BECOME_FLAGS="$(ANSIBLE_BECOME_FLAGS)"

destroy-cluster-and-infra: ## Remove the cluster and also destroy Terraform/OpenTofu-managed infrastructure for the topology
	@$(MAKE) remove-cluster-only TOPOLOGY=$(TOPOLOGY) ANSIBLE_INVENTORY="$(ANSIBLE_INVENTORY)" ANSIBLE_BECOME_FLAGS="$(ANSIBLE_BECOME_FLAGS)"
	@if [ "$(TOPOLOGY)" != "github-codespace" ]; then \
	  $(MAKE) terraform-destroy TOPOLOGY=$(TOPOLOGY) TF_BIN=$(TF_BIN); \
	fi

environment-destroy: ## Compatibility alias for destroy-cluster-and-infra
	@$(MAKE) destroy-cluster-and-infra TOPOLOGY=$(TOPOLOGY) TF_BIN=$(TF_BIN) ANSIBLE_INVENTORY="$(ANSIBLE_INVENTORY)" ANSIBLE_BECOME_FLAGS="$(ANSIBLE_BECOME_FLAGS)"

k9s-local: require-kubeconfig ## Open k9s against the repo kubeconfig across all namespaces
	k9s --kubeconfig "$(KUBECONFIG)" --all-namespaces

port-forward-agentgateway: require-kubeconfig ## Port-forward AgentGateway to localhost:15000
	$(KUBECTL) -n agentgateway-system port-forward svc/agentgateway-proxy $(AGENTGATEWAY_LOCAL_PORT):8080

port-forward-kagent: require-kubeconfig ## Port-forward the kagent controller API to localhost:8083
	$(KUBECTL) -n kagent port-forward svc/kagent-kagent-controller $(KAGENT_A2A_LOCAL_PORT):8083

port-forward-kagent-ui: require-kubeconfig ## Port-forward the kagent UI to localhost:8080
	$(KUBECTL) -n kagent port-forward svc/kagent-kagent-ui $(KAGENT_UI_LOCAL_PORT):8080

port-forward-litellm: require-kubeconfig ## Port-forward LiteLLM to localhost:4000
	$(KUBECTL) -n ai-gateway port-forward svc/litellm $(LITELLM_LOCAL_PORT):4000

port-forward-grafana: require-kubeconfig ## Port-forward Grafana to localhost:3000
	$(KUBECTL) -n observability port-forward svc/observability-kube-prometheus-stack-grafana $(GRAFANA_LOCAL_PORT):80

port-forward-prometheus: require-kubeconfig ## Port-forward Prometheus to localhost:9090
	$(KUBECTL) -n observability port-forward svc/observability-kube-prometh-prometheus $(PROMETHEUS_LOCAL_PORT):9090

port-forward-qdrant: require-kubeconfig ## Port-forward Qdrant to localhost:6333
	$(KUBECTL) -n context port-forward svc/context-qdrant $(QDRANT_LOCAL_PORT):6333

port-forward-flux-operator-ui: require-kubeconfig ## Port-forward the Flux Operator web UI to localhost:9080
	$(KUBECTL) -n flux-system port-forward svc/flux-operator $(FLUX_OPERATOR_UI_LOCAL_PORT):9080

open-kagent-ui: require-kubeconfig ## Open the kagent UI at http://localhost:8080
	$(call start_port_forward,kagent-ui,http://localhost:$(KAGENT_UI_LOCAL_PORT),kagent,kagent-kagent-ui,$(KAGENT_UI_LOCAL_PORT),8080,http://localhost:$(KAGENT_UI_LOCAL_PORT)/,200 301 302 303 307 308,)

close-kagent-ui: ## Close the kagent UI port-forward
	$(call stop_port_forward,kagent-ui)

open-kagent-a2a: require-kubeconfig ## Open the kagent controller API at http://localhost:8083
	$(call start_port_forward,kagent-a2a,http://localhost:$(KAGENT_A2A_LOCAL_PORT),kagent,kagent-kagent-controller,$(KAGENT_A2A_LOCAL_PORT),8083,http://localhost:$(KAGENT_A2A_LOCAL_PORT)/api/a2a/kagent/k8s-a2a-agent/.well-known/agent.json,200,)

close-kagent-a2a: ## Close the kagent controller API port-forward
	$(call stop_port_forward,kagent-a2a)

open-agentgateway: require-kubeconfig ## Open AgentGateway at http://localhost:15000
	$(call start_port_forward,agentgateway,http://localhost:$(AGENTGATEWAY_LOCAL_PORT),agentgateway-system,agentgateway-proxy,$(AGENTGATEWAY_LOCAL_PORT),8080,http://localhost:$(AGENTGATEWAY_LOCAL_PORT)/,200 301 302 303 307 308 401 403 404 405,)

close-agentgateway: ## Close the AgentGateway port-forward
	$(call stop_port_forward,agentgateway)

open-litellm: require-kubeconfig ## Open LiteLLM at http://localhost:4000
	$(call start_port_forward,litellm,http://localhost:$(LITELLM_LOCAL_PORT),ai-gateway,litellm,$(LITELLM_LOCAL_PORT),4000,http://localhost:$(LITELLM_LOCAL_PORT)/health/readiness,200,)

close-litellm: ## Close the LiteLLM port-forward
	$(call stop_port_forward,litellm)

open-grafana: require-kubeconfig ## Open Grafana at http://localhost:3000
	$(call start_port_forward,grafana,http://localhost:$(GRAFANA_LOCAL_PORT),observability,observability-kube-prometheus-stack-grafana,$(GRAFANA_LOCAL_PORT),80,http://localhost:$(GRAFANA_LOCAL_PORT)/login,200 302,)

close-grafana: ## Close the Grafana port-forward
	$(call stop_port_forward,grafana)

open-prometheus: require-kubeconfig ## Open Prometheus at http://localhost:9090
	$(call start_port_forward,prometheus,http://localhost:$(PROMETHEUS_LOCAL_PORT),observability,observability-kube-prometh-prometheus,$(PROMETHEUS_LOCAL_PORT),9090,http://localhost:$(PROMETHEUS_LOCAL_PORT)/-/ready,200,)

close-prometheus: ## Close the Prometheus port-forward
	$(call stop_port_forward,prometheus)

open-qdrant: require-kubeconfig ## Open Qdrant at http://localhost:6333
	$(call start_port_forward,qdrant,http://localhost:$(QDRANT_LOCAL_PORT),context,context-qdrant,$(QDRANT_LOCAL_PORT),6333,http://localhost:$(QDRANT_LOCAL_PORT)/dashboard,200 301 302 303 307 308,)

open-flux-operator-ui: require-kubeconfig ## Open the Flux Operator web UI at http://localhost:9080
	$(call start_port_forward,flux-operator-ui,http://localhost:$(FLUX_OPERATOR_UI_LOCAL_PORT),flux-system,flux-operator,$(FLUX_OPERATOR_UI_LOCAL_PORT),9080,http://localhost:$(FLUX_OPERATOR_UI_LOCAL_PORT)/,200,)

check-kagent-ui: ## Verify the local kagent UI endpoint
	$(call wait_for_http_status,http://localhost:$(KAGENT_UI_LOCAL_PORT)/,200 301 302 303 307 308,)

check-agentgateway: ## Verify the local AgentGateway port-forward and HTTP liveness
	$(call wait_for_http_status,http://localhost:$(AGENTGATEWAY_LOCAL_PORT)/,200 301 302 303 307 308 401 403 404 405,)

check-agentgateway-openai: ## Verify the local AgentGateway OpenAI-compatible API path
	$(call wait_for_http_status,http://localhost:$(AGENTGATEWAY_LOCAL_PORT)/v1/models,200 401,Authorization: Bearer $(LITELLM_MASTER_KEY))

check-litellm: ## Verify the local LiteLLM readiness and API endpoints
	$(call wait_for_http_status,http://localhost:$(LITELLM_LOCAL_PORT)/health/readiness,200,)
	$(call wait_for_http_status,http://localhost:$(LITELLM_LOCAL_PORT)/v1/models,200 401,Authorization: Bearer $(LITELLM_MASTER_KEY))

check-flux-operator-ui: ## Verify the local Flux Operator web UI endpoint
	$(call wait_for_http_status,http://localhost:$(FLUX_OPERATOR_UI_LOCAL_PORT)/,200,)

check-flux-stages: require-kubeconfig ## Show and validate readiness for the staged Flux Kustomizations
	@failed=0; \
	for stage in platform-infrastructure platform-secrets platform-applications; do \
	  json="$$( $(KUBECTL) -n flux-system get kustomization $$stage -o json 2>&1 )"; \
	  status=$$?; \
	  if [ "$$status" -ne 0 ]; then \
	    if printf '%s' "$$json" | grep -qi 'not found'; then \
	      echo "$$stage	False	Missing	Kustomization not found"; \
	    else \
	      printf '%s\tFalse\tClusterUnreachable\t%s\n' "$$stage" "$$(printf '%s' "$$json" | head -n1)"; \
	    fi; \
	    failed=1; \
	    continue; \
	  fi; \
	  ready="$$(printf '%s' "$$json" | jq -r '.status.conditions[]? | select(.type=="Ready") | .status' | tail -n1)"; \
	  reason="$$(printf '%s' "$$json" | jq -r '.status.conditions[]? | select(.type=="Ready") | .reason' | tail -n1)"; \
	  message="$$(printf '%s' "$$json" | jq -r '.status.conditions[]? | select(.type=="Ready") | .message' | tail -n1)"; \
	  [ -n "$$ready" ] || ready="Unknown"; \
	  [ -n "$$reason" ] || reason="-"; \
	  [ -n "$$message" ] || message="-"; \
	  printf '%s\t%s\t%s\t%s\n' "$$stage" "$$ready" "$$reason" "$$message"; \
	  if [ "$$ready" != "True" ]; then \
	    failed=1; \
	  fi; \
	done; \
	exit $$failed

close-qdrant: ## Close the Qdrant port-forward
	$(call stop_port_forward,qdrant)

close-flux-operator-ui: ## Close the Flux Operator web UI port-forward
	$(call stop_port_forward,flux-operator-ui)

open-research-access: require-kubeconfig ## Open the main local research endpoints on localhost
	@set +e; \
	failures=0; \
	attempted=0; \
	printf '%-18s %s\n' "Endpoint" "Result"; \
	for spec in \
	  "open-kagent-ui|kagent|kagent-kagent-ui" \
	  "open-kagent-a2a|kagent|kagent-kagent-controller" \
	  "open-agentgateway|agentgateway-system|agentgateway-proxy" \
	  "open-litellm|ai-gateway|litellm" \
	  "open-grafana|observability|observability-kube-prometheus-stack-grafana" \
	  "open-prometheus|observability|observability-kube-prometh-prometheus" \
	  "open-qdrant|context|context-qdrant" \
	  "open-flux-operator-ui|flux-system|flux-operator"; do \
	  IFS='|' read -r target namespace service <<<"$$spec"; \
	  label="$${target#open-}"; \
	  if ! $(KUBECTL) -n "$$namespace" get svc "$$service" >/dev/null 2>&1; then \
	    printf '%-18s %s\n' "$$label" "skipped"; \
	    continue; \
	  fi; \
	  attempted=$$((attempted + 1)); \
	  if $(MAKE) $$target; then \
	    printf '%-18s %s\n' "$$label" "opened"; \
	  else \
	    failures=$$((failures + 1)); \
	    printf '%-18s %s\n' "$$label" "failed"; \
	  fi; \
	done; \
	echo; \
	echo "A2A agent cards via kagent controller:"; \
	echo "  http://localhost:$(KAGENT_A2A_LOCAL_PORT)/api/a2a/kagent/k8s-a2a-agent/.well-known/agent.json"; \
	echo "  http://localhost:$(KAGENT_A2A_LOCAL_PORT)/api/a2a/kagent/finnhub-agent/.well-known/agent.json"; \
	echo "  http://localhost:$(KAGENT_A2A_LOCAL_PORT)/api/a2a/kagent/team-lead-agent-assist/.well-known/agent.json"; \
	echo "A2A agent cards via AgentGateway:"; \
	echo "  http://localhost:$(AGENTGATEWAY_LOCAL_PORT)/api/a2a/kagent/finnhub-agent/.well-known/agent.json"; \
	echo "  http://localhost:$(AGENTGATEWAY_LOCAL_PORT)/api/a2a/kagent/team-lead-agent-assist/.well-known/agent.json"; \
	test $$attempted -gt 0; \
	test $$failures -eq 0

close-research-access: ## Close all background localhost research endpoints
	$(MAKE) close-kagent-ui
	$(MAKE) close-kagent-a2a
	$(MAKE) close-agentgateway
	$(MAKE) close-litellm
	$(MAKE) close-grafana
	$(MAKE) close-prometheus
	$(MAKE) close-qdrant
	$(MAKE) close-flux-operator-ui

test-a2a-agent: ## Fetch the sample agent card from kagent
	curl -fsSL http://localhost:8083/api/a2a/kagent/k8s-a2a-agent/.well-known/agent.json | jq .

test-finnhub-agent-card: ## Fetch the finnhub-agent card from kagent
	curl -fsSL http://localhost:8083/api/a2a/kagent/finnhub-agent/.well-known/agent.json | jq .

test-team-lead-agent-card: ## Fetch the team-lead-agent-assist card from kagent
	curl -fsSL http://localhost:8083/api/a2a/kagent/team-lead-agent-assist/.well-known/agent.json | jq .

test-agentgateway-gemini: require-kubeconfig open-agentgateway check-agentgateway-openai ## Test the canonical OpenAI-compatible route through agentgateway -> LiteLLM -> Gemini
	curl -fsSL -H "Authorization: Bearer $(LITELLM_MASTER_KEY)" http://localhost:$(AGENTGATEWAY_LOCAL_PORT)/v1/models | jq .

test-agentgateway-openai: require-kubeconfig open-agentgateway check-agentgateway-openai ## Test the agentgateway OpenAI-compatible route without requiring provider-specific CLI tools
	curl -fsSL -H "Authorization: Bearer $(LITELLM_MASTER_KEY)" http://localhost:$(AGENTGATEWAY_LOCAL_PORT)/v1/models | jq .

test-litellm: require-kubeconfig open-litellm check-litellm ## List available models directly from the LiteLLM service
	curl -fsSL -H "Authorization: Bearer $(LITELLM_MASTER_KEY)" http://localhost:$(LITELLM_LOCAL_PORT)/v1/models | jq .
