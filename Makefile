SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

ifneq (,$(wildcard .env))
include .env
export
endif

TOPOLOGY ?= local
override TOPOLOGY := $(if $(strip $(TOPOLOGY)),$(strip $(TOPOLOGY)),local)
ENV ?= dev
RUNTIME ?= none
SECRETS_MODE ?= external
PLATFORM_PROFILE ?=
PLATFORM_ENABLE_SAMPLES_ECHO_MCP ?= false
LMSTUDIO_ENABLED ?= false
INSTALL_K9S ?= true
IAC_TOOL ?= tofu
TF_BIN ?= $(if $(filter tofu,$(IAC_TOOL)),tofu,terraform)
TF_DIR = terraform/environments/$(TOPOLOGY)
FLUX_OPERATOR_VERSION ?= 0.45.1
FLUX_VERSION ?= 2.8.3
FLUX_INSTANCE_SYNC_PATH ?= ./flux/generated/clusters/$(TOPOLOGY)-$(ENV)-$(RUNTIME)-$(SECRETS_MODE)
ANSIBLE_INVENTORY ?= $(or $(wildcard ansible/generated/$(TOPOLOGY).ini),ansible/inventory.ini.example)
ANSIBLE_BECOME_FLAGS ?=
KUBECONFIG_DIR ?= .kube/generated
KUBECONFIG ?= $(abspath $(KUBECONFIG_DIR)/current.yaml)
WORKSPACE_CLUSTER_NAME ?= agentic-native-platform
ECHO_MCP_IMAGE ?= echo-mcp:local
ECHO_MCP_IMAGE_TARBALL ?= /tmp/echo-mcp-image.tar
PORT_FORWARD_STATE_DIR ?= /tmp/agentic-native-platform-port-forwards
KAGENT_UI_LOCAL_PORT ?= 8080
KAGENT_A2A_LOCAL_PORT ?= 8083
AGENTGATEWAY_LOCAL_PORT ?= 15000
LITELLM_LOCAL_PORT ?= 4000
GRAFANA_LOCAL_PORT ?= 3000
PROMETHEUS_LOCAL_PORT ?= 9090
QDRANT_LOCAL_PORT ?= 6333
FLUX_OPERATOR_UI_LOCAL_PORT ?= 9080
LITELLM_MASTER_KEY ?=
PAUSE_STATE_CONFIGMAP ?= cluster-pause-state
PLATFORM_ROOT_TIMEOUT ?= 30m
PLATFORM_BOOTSTRAP_TIMEOUT ?= 10m
PLATFORM_INFRA_TIMEOUT ?= 15m
PLATFORM_APPS_TIMEOUT ?= 20m
HTTP_PROBE_TIMEOUT ?= 30
HTTP_PROBE_INTERVAL ?= 1
CURL ?= curl
export KUBECONFIG
KUBECTL ?= kubectl --kubeconfig "$(KUBECONFIG)"
FLUX ?= flux --kubeconfig "$(KUBECONFIG)"

PAUSE_NAMESPACES ?= ai-gateway ai-models context
PLATFORM_KUSTOMIZATIONS ?= platform-bootstrap platform-infrastructure platform-applications platform

.PHONY: help \
	tools-install-local render-terraform-tfvars terraform-init terraform-apply terraform-destroy \
	bootstrap-hosts install-k3s-server join-workers label-llm-nodes kubeconfig uninstall-k3s \
	cluster-up-local cluster-up-minipc cluster-up-hybrid cluster-up-hybrid-remote cluster-up-github-workspace run-cluster-from-scratch \
	profile-fast profile-fast-serving profile-full \
	flux-values render-cluster-root ensure-generated-flux-clean install-flux-operator install-flux-local install-flux bootstrap-flux-instance bootstrap-flux-git reconcile verify cluster-status \
	render-plaintext-secrets apply-plaintext-secrets delete-plaintext-secrets \
	sops-age-key render-sops-secrets encrypt-secrets decrypt-secrets sops-bootstrap-cluster \
	cluster-pause cluster-resume cluster-stop cluster-start cluster-remove environment-destroy diagnose-runtime-state recover-paused-workloads preimport-vllm-image-tarball preimport-vllm-image-online require-kubeconfig require-cluster-api \
	build-echo-mcp-image save-echo-mcp-image preimport-echo-mcp-image-tarball prepare-echo-mcp-image-local \
	k9s-local port-forward-agentgateway port-forward-kagent port-forward-kagent-ui port-forward-litellm port-forward-grafana port-forward-prometheus port-forward-qdrant port-forward-flux-operator-ui \
	open-kagent-ui close-kagent-ui open-kagent-a2a close-kagent-a2a open-agentgateway close-agentgateway open-litellm close-litellm open-grafana close-grafana open-prometheus close-prometheus open-qdrant close-qdrant open-flux-operator-ui close-flux-operator-ui open-research-access close-research-access \
	check-kagent-ui check-agentgateway check-agentgateway-openai check-litellm check-flux-operator-ui check-flux-stages \
	test-a2a-agent test-agentgateway-gemini test-agentgateway-openai test-litellm test-lmstudio test-ollama test-vllm

define wait_for_http_status
	@url="$(1)"; accepted_codes="$(2)"; header="$(3)"; deadline=$$(( $$(date +%s) + $(HTTP_PROBE_TIMEOUT) )); last_code="000"; \
	while [ $$(date +%s) -le $$deadline ]; do \
	  if [ -n "$$header" ]; then \
	    last_code="$$( $(CURL) -s -o /dev/null -w '%{http_code}' -H "$$header" "$$url" 2>/dev/null || true )"; \
	  else \
	    last_code="$$( $(CURL) -s -o /dev/null -w '%{http_code}' "$$url" 2>/dev/null || true )"; \
	  fi; \
	  case " $$accepted_codes " in \
	    *" $$last_code "*) echo "$$url -> $$last_code"; exit 0 ;; \
	  esac; \
	  sleep $(HTTP_PROBE_INTERVAL); \
	done; \
	echo "Probe failed for $$url; expected one of [$$accepted_codes], last status $$last_code" >&2; \
	exit 1
endef

define start_port_forward
	@mkdir -p $(PORT_FORWARD_STATE_DIR)
	@pid_file="$(PORT_FORWARD_STATE_DIR)/$(1).pid"; \
	port_file="$(PORT_FORWARD_STATE_DIR)/$(1).port"; \
	probe_url="$(7)"; \
	accepted_codes="$(8)"; \
	header="$(9)"; \
	endpoint_query="$$( $(KUBECTL) -n $(3) get endpoints $(4) -o jsonpath='{.subsets[*].addresses[*].ip}' 2>&1 )"; \
	endpoint_status=$$?; \
	if [ "$$endpoint_status" -ne 0 ]; then \
	  echo "$(1) cannot query service $(3)/$(4): $$endpoint_query"; \
	  exit 1; \
	fi; \
	if [ -z "$$endpoint_query" ]; then \
	  echo "$(1) cannot open because service $(3)/$(4) has no ready endpoints"; \
	  exit 1; \
	fi; \
	if [ -f "$$pid_file" ] && kill -0 "$$(cat "$$pid_file")" 2>/dev/null; then \
	  kill "$$(cat "$$pid_file")" 2>/dev/null || true; \
	  rm -f "$$pid_file" "$$port_file"; \
	fi; \
	if [ -f "$$pid_file" ] && ! kill -0 "$$(cat "$$pid_file")" 2>/dev/null; then \
	  rm -f "$$pid_file" "$$port_file"; \
	fi; \
	existing_pids="$$(ps -eo pid=,comm=,args= | awk -v service="svc/$(4)" -v mapping="$(5):$(6)" '$$2=="kubectl" && $$0 ~ /port-forward/ && index($$0, service) && index($$0, mapping) { print $$1 }')"; \
	if [ -n "$$existing_pids" ]; then \
	  echo "$$existing_pids" | xargs -r kill 2>/dev/null || true; \
	  rm -f "$$pid_file" "$$port_file"; \
	  sleep 1; \
	fi; \
	if command -v ss >/dev/null 2>&1 && ss -ltn "( sport = :$(5) )" | tail -n +2 | grep -q .; then \
	  if [ -n "$$probe_url" ]; then \
	    if [ -n "$$header" ]; then \
	      last_code="$$( $(CURL) -s -o /dev/null -w '%{http_code}' -H "$$header" "$$probe_url" 2>/dev/null || true )"; \
	    else \
	      last_code="$$( $(CURL) -s -o /dev/null -w '%{http_code}' "$$probe_url" 2>/dev/null || true )"; \
	    fi; \
	    case " $$accepted_codes " in \
	      *" $$last_code "*) echo "$(1) already available at $(2)"; exit 0 ;; \
	    esac; \
	  fi; \
	  echo "$(1) cannot open because localhost:$(5) is already in use"; \
	  exit 1; \
	else \
	  nohup $(KUBECTL) -n $(3) port-forward svc/$(4) $(5):$(6) >"$(PORT_FORWARD_STATE_DIR)/$(1).log" 2>&1 </dev/null & \
	  echo $$! >"$$pid_file"; \
	  echo "$(5)" >"$$port_file"; \
	  if ! kill -0 "$$(cat "$$pid_file")" 2>/dev/null; then \
	    echo "$(1) failed to open"; \
	    sed -n '1,40p' "$(PORT_FORWARD_STATE_DIR)/$(1).log"; \
	    rm -f "$$pid_file" "$$port_file"; \
	    exit 1; \
	  fi; \
	  if [ -n "$$probe_url" ]; then \
	    deadline=$$(( $$(date +%s) + $(HTTP_PROBE_TIMEOUT) )); \
	    ready=0; \
	    last_code="000"; \
	    while [ $$(date +%s) -le $$deadline ]; do \
	      if [ -n "$$header" ]; then \
	        last_code="$$( $(CURL) -s -o /dev/null -w '%{http_code}' -H "$$header" "$$probe_url" 2>/dev/null || true )"; \
	      else \
	        last_code="$$( $(CURL) -s -o /dev/null -w '%{http_code}' "$$probe_url" 2>/dev/null || true )"; \
	      fi; \
	      case " $$accepted_codes " in \
	        *" $$last_code "*) ready=1; break ;; \
	      esac; \
	      if ! kill -0 "$$(cat "$$pid_file")" 2>/dev/null; then \
	        echo "$(1) failed while waiting for $$probe_url"; \
	        sed -n '1,40p' "$(PORT_FORWARD_STATE_DIR)/$(1).log"; \
	        rm -f "$$pid_file" "$$port_file"; \
	        exit 1; \
	      fi; \
	      sleep $(HTTP_PROBE_INTERVAL); \
	    done; \
	    if [ "$$ready" -ne 1 ]; then \
	      echo "$(1) failed readiness check for $$probe_url (last status $$last_code)"; \
	      sed -n '1,40p' "$(PORT_FORWARD_STATE_DIR)/$(1).log"; \
	      kill "$$(cat "$$pid_file")" 2>/dev/null || true; \
	      rm -f "$$pid_file" "$$port_file"; \
	      exit 1; \
	    fi; \
	  fi; \
	  echo "$(1) available at $(2)"; \
	fi
endef

define stop_port_forward
	@if [ -f "$(PORT_FORWARD_STATE_DIR)/$(1).pid" ]; then \
	  pid="$$(cat "$(PORT_FORWARD_STATE_DIR)/$(1).pid")"; \
	  if kill -0 "$$pid" 2>/dev/null; then kill "$$pid" 2>/dev/null || true; fi; \
	  rm -f "$(PORT_FORWARD_STATE_DIR)/$(1).pid" "$(PORT_FORWARD_STATE_DIR)/$(1).port"; \
	  echo "$(1) closed"; \
	else \
	  echo "$(1) is not running"; \
	fi
endef

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9_.-]+:.*##/ {printf "%-32s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

tools-install-local: ## Install local operator tools (age, sops, kubectl, helm, flux, optional k9s, Terraform/OpenTofu)
	@sudo -v
	ansible-playbook $(ANSIBLE_BECOME_FLAGS) -i localhost, -c local ansible/playbooks/install-local-tools.yml --extra-vars "iac_tool=$(IAC_TOOL) install_k9s=$(INSTALL_K9S)"

render-terraform-tfvars: ## Render local terraform.auto.tfvars from .env for the selected topology
	./scripts/render-terraform-tfvars.sh $(TOPOLOGY)

terraform-init: render-terraform-tfvars ## Initialize Terraform/OpenTofu in the selected topology directory
	$(TF_BIN) -chdir=$(TF_DIR) init

terraform-apply: render-terraform-tfvars ## Apply Terraform/OpenTofu in the selected topology directory
	$(TF_BIN) -chdir=$(TF_DIR) apply -auto-approve

terraform-destroy: render-terraform-tfvars ## Destroy Terraform/OpenTofu artifacts in the selected topology directory
	$(TF_BIN) -chdir=$(TF_DIR) destroy -auto-approve

bootstrap-hosts: ## Prepare the selected hosts for k3s
	ansible-playbook $(ANSIBLE_BECOME_FLAGS) -i $(ANSIBLE_INVENTORY) ansible/playbooks/bootstrap-hosts.yml

install-k3s-server: ## Install the k3s server on the control-plane host
	ansible-playbook $(ANSIBLE_BECOME_FLAGS) -i $(ANSIBLE_INVENTORY) ansible/playbooks/install-k3s-server.yml

join-workers: ## Join worker nodes to the k3s cluster
	ansible-playbook $(ANSIBLE_BECOME_FLAGS) -i $(ANSIBLE_INVENTORY) ansible/playbooks/join-k3s-workers.yml

label-llm-nodes: ## Label worker nodes as runtime-capable for self-hosted LLM workloads
	ansible-playbook $(ANSIBLE_BECOME_FLAGS) -i $(ANSIBLE_INVENTORY) ansible/playbooks/label-llm-nodes.yml

kubeconfig: ## Export kubeconfig from the control-plane host to .kube/generated
	mkdir -p $(KUBECONFIG_DIR)
	ansible-playbook $(ANSIBLE_BECOME_FLAGS) -i $(ANSIBLE_INVENTORY) ansible/playbooks/export-kubeconfig.yml

require-kubeconfig:
	@test -f "$(KUBECONFIG)" || (echo "Missing kubeconfig: $(KUBECONFIG). Run 'make kubeconfig TOPOLOGY=$(TOPOLOGY)' first." >&2; exit 1)

require-cluster-api: require-kubeconfig
	@./scripts/require-kube-apiserver.sh "$@"

uninstall-k3s: ## Uninstall k3s from all hosts in the selected topology inventory
	ansible-playbook $(ANSIBLE_BECOME_FLAGS) -i $(ANSIBLE_INVENTORY) ansible/playbooks/uninstall-k3s.yml

cluster-up-local: ## Bootstrap a single-node local topology
	$(MAKE) terraform-init TOPOLOGY=local TF_BIN=$(TF_BIN)
	$(MAKE) terraform-apply TOPOLOGY=local TF_BIN=$(TF_BIN)
	$(MAKE) ensure-generated-flux-clean TOPOLOGY=local ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) PLATFORM_PROFILE=$(PLATFORM_PROFILE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED) PLATFORM_ENABLE_SAMPLES_ECHO_MCP=$(PLATFORM_ENABLE_SAMPLES_ECHO_MCP) VLLM_IMAGE="$(VLLM_IMAGE)" ECHO_MCP_IMAGE="$(ECHO_MCP_IMAGE)"
	$(MAKE) bootstrap-hosts TOPOLOGY=local
	$(MAKE) install-k3s-server TOPOLOGY=local
	$(MAKE) kubeconfig TOPOLOGY=local

cluster-up-minipc: ## Bootstrap a single-node miniPC topology
	$(MAKE) terraform-init TOPOLOGY=minipc TF_BIN=$(TF_BIN)
	$(MAKE) terraform-apply TOPOLOGY=minipc TF_BIN=$(TF_BIN)
	$(MAKE) ensure-generated-flux-clean TOPOLOGY=minipc ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) PLATFORM_PROFILE=$(PLATFORM_PROFILE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED) PLATFORM_ENABLE_SAMPLES_ECHO_MCP=$(PLATFORM_ENABLE_SAMPLES_ECHO_MCP) VLLM_IMAGE="$(VLLM_IMAGE)" ECHO_MCP_IMAGE="$(ECHO_MCP_IMAGE)"
	$(MAKE) bootstrap-hosts TOPOLOGY=minipc
	$(MAKE) install-k3s-server TOPOLOGY=minipc
	$(MAKE) kubeconfig TOPOLOGY=minipc

cluster-up-hybrid: ## Bootstrap a miniPC control-plane plus workstation worker topology
	$(MAKE) terraform-init TOPOLOGY=hybrid TF_BIN=$(TF_BIN)
	$(MAKE) terraform-apply TOPOLOGY=hybrid TF_BIN=$(TF_BIN)
	$(MAKE) ensure-generated-flux-clean TOPOLOGY=hybrid ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) PLATFORM_PROFILE=$(PLATFORM_PROFILE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED) PLATFORM_ENABLE_SAMPLES_ECHO_MCP=$(PLATFORM_ENABLE_SAMPLES_ECHO_MCP) VLLM_IMAGE="$(VLLM_IMAGE)" ECHO_MCP_IMAGE="$(ECHO_MCP_IMAGE)"
	$(MAKE) bootstrap-hosts TOPOLOGY=hybrid
	$(MAKE) install-k3s-server TOPOLOGY=hybrid
	$(MAKE) join-workers TOPOLOGY=hybrid
	$(MAKE) label-llm-nodes TOPOLOGY=hybrid
	$(MAKE) kubeconfig TOPOLOGY=hybrid

cluster-up-hybrid-remote: ## Bootstrap a miniPC control-plane with workstation and remote worker nodes
	$(MAKE) terraform-init TOPOLOGY=hybrid-remote TF_BIN=$(TF_BIN)
	$(MAKE) terraform-apply TOPOLOGY=hybrid-remote TF_BIN=$(TF_BIN)
	$(MAKE) ensure-generated-flux-clean TOPOLOGY=hybrid-remote ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) PLATFORM_PROFILE=$(PLATFORM_PROFILE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED) PLATFORM_ENABLE_SAMPLES_ECHO_MCP=$(PLATFORM_ENABLE_SAMPLES_ECHO_MCP) VLLM_IMAGE="$(VLLM_IMAGE)" ECHO_MCP_IMAGE="$(ECHO_MCP_IMAGE)"
	$(MAKE) bootstrap-hosts TOPOLOGY=hybrid-remote
	$(MAKE) install-k3s-server TOPOLOGY=hybrid-remote
	$(MAKE) join-workers TOPOLOGY=hybrid-remote
	$(MAKE) label-llm-nodes TOPOLOGY=hybrid-remote
	$(MAKE) kubeconfig TOPOLOGY=hybrid-remote

cluster-up-github-workspace: ## Bootstrap a GitHub workspace / Codespaces topology with k3d
	$(MAKE) terraform-init TOPOLOGY=github-workspace TF_BIN=$(TF_BIN)
	$(MAKE) terraform-apply TOPOLOGY=github-workspace TF_BIN=$(TF_BIN)
	$(MAKE) ensure-generated-flux-clean TOPOLOGY=github-workspace ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) PLATFORM_PROFILE=$(PLATFORM_PROFILE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED) PLATFORM_ENABLE_SAMPLES_ECHO_MCP=$(PLATFORM_ENABLE_SAMPLES_ECHO_MCP) VLLM_IMAGE="$(VLLM_IMAGE)" ECHO_MCP_IMAGE="$(ECHO_MCP_IMAGE)"
	WORKSPACE_CLUSTER_NAME="$(WORKSPACE_CLUSTER_NAME)" TF_BIN="$(TF_BIN)" ./scripts/cluster-up-github-workspace.sh

profile-fast: ## Render and reconcile the fast profile for the selected topology
	$(MAKE) render-cluster-root TOPOLOGY=$(TOPOLOGY) ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) PLATFORM_PROFILE=platform-profile-fast LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED) PLATFORM_ENABLE_SAMPLES_ECHO_MCP=$(PLATFORM_ENABLE_SAMPLES_ECHO_MCP)
	$(MAKE) reconcile TOPOLOGY=$(TOPOLOGY) ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) PLATFORM_PROFILE=platform-profile-fast LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED)

profile-fast-serving: ## Render and reconcile the fast-serving profile for the selected topology
	$(MAKE) render-cluster-root TOPOLOGY=$(TOPOLOGY) ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) PLATFORM_PROFILE=platform-profile-fast-serving LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED) PLATFORM_ENABLE_SAMPLES_ECHO_MCP=$(PLATFORM_ENABLE_SAMPLES_ECHO_MCP)
	$(MAKE) reconcile TOPOLOGY=$(TOPOLOGY) ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) PLATFORM_PROFILE=platform-profile-fast-serving LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED)

profile-full: ## Render and reconcile the full profile for the selected topology
	$(MAKE) render-cluster-root TOPOLOGY=$(TOPOLOGY) ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) PLATFORM_PROFILE=platform-profile-full LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED) PLATFORM_ENABLE_SAMPLES_ECHO_MCP=$(PLATFORM_ENABLE_SAMPLES_ECHO_MCP)
	$(MAKE) reconcile TOPOLOGY=$(TOPOLOGY) ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) PLATFORM_PROFILE=platform-profile-full LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED)

run-cluster-from-scratch: ## Bootstrap the selected topology, install Flux, apply secrets, bootstrap GitOps, and reconcile from the current repo state
	@$(MAKE) tools-install-local IAC_TOOL=$(IAC_TOOL) INSTALL_K9S=$(INSTALL_K9S)
	@$(MAKE) cluster-up-$(TOPOLOGY) TOPOLOGY=$(TOPOLOGY) TF_BIN=$(TF_BIN) ANSIBLE_INVENTORY="$(ANSIBLE_INVENTORY)" ANSIBLE_BECOME_FLAGS="$(ANSIBLE_BECOME_FLAGS)"
	@if [ "$(TOPOLOGY)" = "local" ] || [ "$(TOPOLOGY)" = "github-workspace" ]; then \
	  $(MAKE) install-flux-local TOPOLOGY=$(TOPOLOGY); \
	else \
	  $(MAKE) install-flux TOPOLOGY=$(TOPOLOGY) KUBE_CONTEXT="$(KUBE_CONTEXT)"; \
	fi
	@if [ "$(SECRETS_MODE)" = "sops" ]; then \
	  $(MAKE) sops-bootstrap-cluster TOPOLOGY=$(TOPOLOGY) ENV=$(ENV); \
	else \
	  $(MAKE) apply-plaintext-secrets TOPOLOGY=$(TOPOLOGY) ENV=$(ENV); \
	fi
	@$(MAKE) bootstrap-flux-instance TOPOLOGY=$(TOPOLOGY) ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) PLATFORM_PROFILE=$(PLATFORM_PROFILE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED) PLATFORM_ENABLE_SAMPLES_ECHO_MCP=$(PLATFORM_ENABLE_SAMPLES_ECHO_MCP)
	@$(MAKE) reconcile TOPOLOGY=$(TOPOLOGY) ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) PLATFORM_PROFILE=$(PLATFORM_PROFILE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED)
	@$(MAKE) cluster-status TOPOLOGY=$(TOPOLOGY)

flux-values: ## Render non-secret Flux ConfigMaps for the selected topology
	VLLM_IMAGE="$(VLLM_IMAGE)" ECHO_MCP_IMAGE="$(ECHO_MCP_IMAGE)" ./scripts/render-flux-values.sh $(TOPOLOGY)

render-cluster-root: ## Render the Flux root kustomization for the selected topology/env/runtime/secrets mode
	TOPOLOGY=$(TOPOLOGY) ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) PLATFORM_PROFILE=$(PLATFORM_PROFILE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED) PLATFORM_ROOT_TIMEOUT=$(PLATFORM_ROOT_TIMEOUT) PLATFORM_BOOTSTRAP_TIMEOUT=$(PLATFORM_BOOTSTRAP_TIMEOUT) PLATFORM_INFRA_TIMEOUT=$(PLATFORM_INFRA_TIMEOUT) PLATFORM_APPS_TIMEOUT=$(PLATFORM_APPS_TIMEOUT) GIT_REPO_URL="$(GIT_REPO_URL)" GIT_BRANCH="$(GIT_BRANCH)" PLATFORM_ENABLE_SAMPLES_ECHO_MCP=$(PLATFORM_ENABLE_SAMPLES_ECHO_MCP) VLLM_IMAGE="$(VLLM_IMAGE)" ECHO_MCP_IMAGE="$(ECHO_MCP_IMAGE)" ./scripts/render-cluster-kustomization.sh

ensure-generated-flux-clean: flux-values render-cluster-root ## Render tracked Flux inputs and fail before cluster install continues if GitOps inputs need commit/push
	@changed="$$(git status --porcelain -- "flux/generated/$(TOPOLOGY)" "flux/generated/clusters/$(TOPOLOGY)-$(ENV)-$(RUNTIME)-$(SECRETS_MODE)")"; \
	if [ -n "$$changed" ]; then \
	  echo "Generated Flux manifests changed locally. Commit and push them before continuing:"; \
	  echo "$$changed"; \
	  exit 1; \
	fi

install-flux-operator: require-cluster-api ## Install the pinned Flux Operator chart into flux-system
	@extra_args=""; \
	if [ -n "$(KUBE_CONTEXT)" ]; then \
	  extra_args="--kube-context $(KUBE_CONTEXT)"; \
	fi; \
	helm upgrade --install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
	  $$extra_args \
	  --version $(FLUX_OPERATOR_VERSION) \
	  --namespace flux-system \
	  --create-namespace \
	  --wait \
	  --timeout $(PLATFORM_BOOTSTRAP_TIMEOUT)

install-flux-local: install-flux-operator ## Install Flux Operator into the current cluster

install-flux: install-flux-operator ## Install Flux Operator into the selected/current cluster

bootstrap-flux-instance: require-kubeconfig render-cluster-root ## Apply a FluxInstance that points Flux sync at the remote repo and generated cluster path
	@test -n "$(GIT_REPO_URL)" || (echo "Set GIT_REPO_URL in .env or the environment before bootstrapping Flux." >&2; exit 1)
	@if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then \
	  echo "bootstrap-flux-instance requires a Git worktree." >&2; \
	  exit 1; \
	fi
	@if ! git diff --quiet --ignore-submodules HEAD -- || ! git diff --cached --quiet --ignore-submodules --; then \
	  echo "Refusing Flux bootstrap with a dirty worktree. Commit or stash changes first." >&2; \
	  exit 1; \
	fi
	@normalize_git_url() { \
	  printf '%s' "$$1" | sed -E 's#^[[:alpha:]][[:alnum:]+.-]*://##; s#^git@([^:]+):#\1/#; s#^[^@]+@##; s#\.git$$##'; \
	}; \
	target_repo="$$(normalize_git_url "$(GIT_REPO_URL)")"; \
	remote_name="$$(for remote in $$(git remote); do \
	  remote_url="$$(git remote get-url "$$remote" 2>/dev/null || true)"; \
	  [ -n "$$remote_url" ] || continue; \
	  remote_repo="$$(normalize_git_url "$$remote_url")"; \
	  if [ "$$remote_repo" = "$$target_repo" ]; then \
	    echo "$$remote"; \
	    break; \
	  fi; \
	done)"; \
	if [ -z "$$remote_name" ]; then \
	  echo "No configured Git remote matches GIT_REPO_URL=$(GIT_REPO_URL)" >&2; \
	  exit 1; \
	fi; \
	local_head="$$(git rev-parse HEAD)"; \
	remote_line="$$(git ls-remote --exit-code "$(GIT_REPO_URL)" "refs/heads/$(GIT_BRANCH)")"; \
	remote_head="$${remote_line%%$$(printf '\t')*}"; \
	echo "Flux bootstrap preflight:"; \
	echo "  remote=$$remote_name"; \
	echo "  repo=$(GIT_REPO_URL)"; \
	echo "  branch=$(GIT_BRANCH)"; \
	echo "  local_head=$$local_head"; \
	echo "  remote_head=$$remote_head"; \
	if [ "$$local_head" != "$$remote_head" ]; then \
	  echo "Refusing Flux bootstrap because local HEAD is not the same commit as $(GIT_REPO_URL)@$(GIT_BRANCH)." >&2; \
	  echo "Push the current commit first or change GIT_BRANCH/GIT_REPO_URL intentionally." >&2; \
	  exit 1; \
	fi
	@sed \
	  -e 's|__FLUX_VERSION__|$(FLUX_VERSION)|g' \
	  -e 's|__CLUSTER_DOMAIN__|$(CLUSTER_DOMAIN)|g' \
	  -e 's|__GIT_REPO_URL__|$(GIT_REPO_URL)|g' \
	  -e 's|__GIT_BRANCH__|$(GIT_BRANCH)|g' \
	  -e 's|__FLUX_INSTANCE_SYNC_PATH__|$(FLUX_INSTANCE_SYNC_PATH)|g' \
	  bootstrap/flux-operator/flux-instance.yaml.tmpl | $(KUBECTL) apply -f -
	@$(KUBECTL) -n flux-system wait --for=condition=ready fluxinstance/flux --timeout=$(PLATFORM_ROOT_TIMEOUT)

bootstrap-flux-git: bootstrap-flux-instance ## Deprecated alias for the FluxInstance-based bootstrap flow

reconcile: require-kubeconfig ## Reconcile Flux source and kustomization named 'platform' if present
	@$(FLUX) reconcile source git platform -n flux-system || true
	@if $(KUBECTL) -n flux-system get kustomization platform-bootstrap >/dev/null 2>&1; then \
	  $(FLUX) reconcile kustomization platform-bootstrap -n flux-system --with-source || true; \
	fi
	@token="$$(date -u +"%Y-%m-%dT%H:%M:%SZ")"; \
	for hr in $$($(KUBECTL) -n flux-system get helmrelease -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do \
	  $(KUBECTL) -n flux-system annotate --overwrite helmrelease $$hr \
	    reconcile.fluxcd.io/requestedAt="$$token" \
	    reconcile.fluxcd.io/forceAt="$$token" \
	    reconcile.fluxcd.io/resetAt="$$token" || true; \
	done
	@for k in platform-infrastructure platform-applications platform; do \
	  $(KUBECTL) -n flux-system get kustomization $$k >/dev/null 2>&1 || continue; \
	  $(FLUX) reconcile kustomization $$k -n flux-system --with-source || true; \
	done

verify: require-kubeconfig ## Basic local verification of cluster and Flux state
	$(KUBECTL) get nodes -o wide || true
	$(KUBECTL) get ns || true
	$(KUBECTL) get gitrepositories -A || true
	$(KUBECTL) get kustomizations -A || true
	$(KUBECTL) get helmreleases -A || true

cluster-status: require-kubeconfig ## Show staged Flux, HelmRelease, and pod readiness state
	@KUBECTL_BIN=kubectl FLUX_BIN=flux KUBECONFIG_PATH='$(KUBECONFIG)' STATE_NAMESPACE=flux-system PAUSE_STATE_CONFIGMAP='$(PAUSE_STATE_CONFIGMAP)' PAUSE_NAMESPACES='$(PAUSE_NAMESPACES)' PLATFORM_KUSTOMIZATIONS='$(PLATFORM_KUSTOMIZATIONS)' ./scripts/cluster-status.sh

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
	@$(MAKE) reconcile TOPOLOGY=$(TOPOLOGY) ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) PLATFORM_PROFILE=$(PLATFORM_PROFILE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED)
	@$(MAKE) diagnose-runtime-state TOPOLOGY=$(TOPOLOGY) ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) PLATFORM_PROFILE=$(PLATFORM_PROFILE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED)

render-plaintext-secrets: ## Render local plaintext Kubernetes Secrets from .env into .generated/secrets/<env>
	ENV=$(ENV) ./scripts/render-plaintext-secrets.sh

apply-plaintext-secrets: require-kubeconfig render-plaintext-secrets ## Apply local plaintext secrets directly to the cluster (not committed to Git)
	$(KUBECTL) apply -k .generated/secrets/$(ENV)

delete-plaintext-secrets: require-kubeconfig ## Delete local plaintext secret resources from the cluster
	-$(KUBECTL) delete -k .generated/secrets/$(ENV)

sops-age-key: ## Generate a local age key and update .sops.yaml using the generated public recipient
	./scripts/create-age-key.sh

render-sops-secrets: ## Render plaintext inputs for SOPS from .env into .generated/secrets/<env>
	ENV=$(ENV) ./scripts/render-sops-secrets-from-env.sh

encrypt-secrets: render-sops-secrets ## Encrypt plaintext inputs into flux/secrets/<env>/*.sops.yaml and refresh kustomization.yaml
	ENV=$(ENV) ./scripts/encrypt-secrets.sh

decrypt-secrets: ## Decrypt committed SOPS secrets into .generated/decrypted/<env> for troubleshooting only
	ENV=$(ENV) ./scripts/decrypt-secrets.sh

sops-bootstrap-cluster: require-kubeconfig ## Upload the local age private key into flux-system for SOPS decryption
	./scripts/bootstrap-sops-secret.sh

cluster-pause: require-cluster-api ## Pause platform workloads without uninstalling the cluster
	@PAUSE_NAMESPACES="$(PAUSE_NAMESPACES)" PAUSE_STATE_CONFIGMAP="$(PAUSE_STATE_CONFIGMAP)" STATE_NAMESPACE=flux-system ./scripts/save-paused-workloads.sh
	@for k in $(PLATFORM_KUSTOMIZATIONS); do \
	  $(KUBECTL) -n flux-system get kustomization $$k >/dev/null 2>&1 || continue; \
	  $(FLUX) suspend kustomization $$k -n flux-system || true; \
	done
	@$(FLUX) suspend source git platform -n flux-system || true
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
	@$(FLUX) resume source git platform -n flux-system || true
	@for hr in $$($(KUBECTL) -n flux-system get helmrelease -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do \
	  $(FLUX) resume helmrelease $$hr -n flux-system || true; \
	done
	@for k in $(PLATFORM_KUSTOMIZATIONS); do \
	  $(KUBECTL) -n flux-system get kustomization $$k >/dev/null 2>&1 || continue; \
	  $(FLUX) resume kustomization $$k -n flux-system || true; \
	done
	@$(FLUX) reconcile source git platform -n flux-system || true
	@if $(KUBECTL) -n flux-system get kustomization platform-bootstrap >/dev/null 2>&1; then \
	  $(FLUX) reconcile kustomization platform-bootstrap -n flux-system --with-source || true; \
	fi
	@PAUSE_STATE_CONFIGMAP="$(PAUSE_STATE_CONFIGMAP)" STATE_NAMESPACE=flux-system ./scripts/restore-paused-workloads.sh
	@token="$$(date -u +"%Y-%m-%dT%H:%M:%SZ")"; \
	for hr in $$($(KUBECTL) -n flux-system get helmrelease -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do \
	  $(KUBECTL) -n flux-system annotate --overwrite helmrelease $$hr \
	    reconcile.fluxcd.io/requestedAt="$$token" \
	    reconcile.fluxcd.io/forceAt="$$token" \
	    reconcile.fluxcd.io/resetAt="$$token" || true; \
	done
	@for k in platform-infrastructure platform-applications platform; do \
	  $(KUBECTL) -n flux-system get kustomization $$k >/dev/null 2>&1 || continue; \
	  $(FLUX) reconcile kustomization $$k -n flux-system --with-source || true; \
	done

cluster-stop: ## Deprecated alias for cluster-pause
	@$(MAKE) cluster-pause TOPOLOGY=$(TOPOLOGY) ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED) IAC_TOOL=$(IAC_TOOL) TF_BIN=$(TF_BIN) ANSIBLE_INVENTORY="$(ANSIBLE_INVENTORY)" ANSIBLE_BECOME_FLAGS="$(ANSIBLE_BECOME_FLAGS)"

cluster-start: ## Deprecated alias for cluster-resume
	@$(MAKE) cluster-resume TOPOLOGY=$(TOPOLOGY) ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED) IAC_TOOL=$(IAC_TOOL) TF_BIN=$(TF_BIN) ANSIBLE_INVENTORY="$(ANSIBLE_INVENTORY)" ANSIBLE_BECOME_FLAGS="$(ANSIBLE_BECOME_FLAGS)"

cluster-remove: ## Remove only the cluster from the selected topology and keep infrastructure/resources
	@if [ "$(TOPOLOGY)" = "github-workspace" ]; then \
	  WORKSPACE_CLUSTER_NAME="$(WORKSPACE_CLUSTER_NAME)" ./scripts/cluster-remove-github-workspace.sh; \
	else \
	  $(MAKE) uninstall-k3s TOPOLOGY=$(TOPOLOGY) ANSIBLE_INVENTORY="$(ANSIBLE_INVENTORY)" ANSIBLE_BECOME_FLAGS="$(ANSIBLE_BECOME_FLAGS)"; \
	fi

environment-destroy: ## Remove the cluster and destroy Terraform/OpenTofu infrastructure when the topology uses it
	@$(MAKE) cluster-remove TOPOLOGY=$(TOPOLOGY) ANSIBLE_INVENTORY="$(ANSIBLE_INVENTORY)" ANSIBLE_BECOME_FLAGS="$(ANSIBLE_BECOME_FLAGS)"
	@if [ "$(TOPOLOGY)" != "github-workspace" ]; then \
	  $(MAKE) terraform-destroy TOPOLOGY=$(TOPOLOGY) TF_BIN=$(TF_BIN); \
	fi

preimport-vllm-image-tarball: ## Copy a saved vLLM image tarball into the k3s image import directory on all nodes
	@test -n "$(VLLM_IMAGE_TARBALL)" || (echo "Set VLLM_IMAGE_TARBALL=/path/to/image.tar" >&2; exit 1)
	ansible $(ANSIBLE_BECOME_FLAGS) -i $(ANSIBLE_INVENTORY) all -b -m file -a "path=/var/lib/rancher/k3s/agent/images state=directory mode=0755"
	ansible $(ANSIBLE_BECOME_FLAGS) -i $(ANSIBLE_INVENTORY) all -b -m copy -a "src=$(VLLM_IMAGE_TARBALL) dest=/var/lib/rancher/k3s/agent/images/vllm-image.tar mode=0644"
	ansible $(ANSIBLE_BECOME_FLAGS) -i $(ANSIBLE_INVENTORY) all -b -m shell -a "k3s ctr images import /var/lib/rancher/k3s/agent/images/vllm-image.tar"

preimport-vllm-image-online: ## Pre-pull the vLLM image on all nodes using ctr in k3s containerd
	@test -n "$(VLLM_IMAGE)" || (echo "Set VLLM_IMAGE=repo:tag" >&2; exit 1)
	ansible $(ANSIBLE_BECOME_FLAGS) -i $(ANSIBLE_INVENTORY) all -b -m shell -a "k3s ctr images pull $(VLLM_IMAGE)"

build-echo-mcp-image: ## Build the sample echo-mcp image locally with the configured ECHO_MCP_IMAGE tag
	docker build -t $(ECHO_MCP_IMAGE) mcp/echo-server

save-echo-mcp-image: ## Save the local echo-mcp image to ECHO_MCP_IMAGE_TARBALL
	@test -n "$(ECHO_MCP_IMAGE_TARBALL)" || (echo "Set ECHO_MCP_IMAGE_TARBALL=/tmp/echo-mcp-image.tar" >&2; exit 1)
	docker save $(ECHO_MCP_IMAGE) -o $(ECHO_MCP_IMAGE_TARBALL)

preimport-echo-mcp-image-tarball: ## Import an echo-mcp image tarball into the selected cluster runtime
	@test -n "$(ECHO_MCP_IMAGE_TARBALL)" || (echo "Set ECHO_MCP_IMAGE_TARBALL=/tmp/echo-mcp-image.tar" >&2; exit 1)
	@if [ "$(TOPOLOGY)" = "github-workspace" ]; then \
	  docker load -i $(ECHO_MCP_IMAGE_TARBALL); \
	  k3d image import $(ECHO_MCP_IMAGE) -c $(WORKSPACE_CLUSTER_NAME); \
	else \
	  ansible $(ANSIBLE_BECOME_FLAGS) -i $(ANSIBLE_INVENTORY) all -b -m file -a "path=/var/lib/rancher/k3s/agent/images state=directory mode=0755"; \
	  ansible $(ANSIBLE_BECOME_FLAGS) -i $(ANSIBLE_INVENTORY) all -b -m copy -a "src=$(ECHO_MCP_IMAGE_TARBALL) dest=/var/lib/rancher/k3s/agent/images/echo-mcp-image.tar mode=0644"; \
	  ansible $(ANSIBLE_BECOME_FLAGS) -i $(ANSIBLE_INVENTORY) all -b -m shell -a "k3s ctr images import /var/lib/rancher/k3s/agent/images/echo-mcp-image.tar"; \
	fi

prepare-echo-mcp-image-local: build-echo-mcp-image save-echo-mcp-image preimport-echo-mcp-image-tarball ## Build, save, and import the sample echo-mcp image into k3s nodes without pushing

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
	for stage in platform-bootstrap platform-infrastructure platform-applications; do \
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

test-agentgateway-gemini: require-kubeconfig open-agentgateway check-agentgateway-openai ## Test the canonical OpenAI-compatible route through agentgateway -> LiteLLM -> Gemini
	curl -fsSL -H "Authorization: Bearer $(LITELLM_MASTER_KEY)" http://localhost:$(AGENTGATEWAY_LOCAL_PORT)/v1/models | jq .

test-agentgateway-openai: require-kubeconfig open-agentgateway check-agentgateway-openai ## Test the agentgateway OpenAI-compatible route without requiring provider-specific CLI tools
	curl -fsSL -H "Authorization: Bearer $(LITELLM_MASTER_KEY)" http://localhost:$(AGENTGATEWAY_LOCAL_PORT)/v1/models | jq .

test-litellm: require-kubeconfig open-litellm check-litellm ## List available models directly from the LiteLLM service
	curl -fsSL -H "Authorization: Bearer $(LITELLM_MASTER_KEY)" http://localhost:$(LITELLM_LOCAL_PORT)/v1/models | jq .

test-lmstudio: require-kubeconfig ## Check connectivity from the cluster to the external LM Studio endpoint
	kubectl -n ai-gateway run lmstudio-curl --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
	  curl -fsSL http://lmstudio-external.ai-gateway.svc.cluster.local:1234/v1/models

test-ollama: require-kubeconfig ## Check the in-cluster Ollama endpoint
	kubectl -n ai-models run ollama-curl --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
	  curl -fsSL http://ollama.ai-models.svc.cluster.local:11434/api/tags

test-vllm: require-kubeconfig ## Check the in-cluster vLLM endpoint
	kubectl -n ai-models run vllm-curl --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
	  curl -fsSL http://vllm-openai.ai-models.svc.cluster.local:8000/v1/models
