SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

ifneq (,$(wildcard .env))
include .env
export
endif

TOPOLOGY ?= local
ENV ?= dev
RUNTIME ?= none
SECRETS_MODE ?= external
LMSTUDIO_ENABLED ?= false
INSTALL_K9S ?= true
IAC_TOOL ?= tofu
TF_BIN ?= $(if $(filter tofu,$(IAC_TOOL)),tofu,terraform)
TF_DIR ?= terraform/environments/$(TOPOLOGY)
ANSIBLE_INVENTORY ?= $(or $(wildcard ansible/generated/$(TOPOLOGY).ini),ansible/inventory.ini.example)
ANSIBLE_BECOME_FLAGS ?=
KUBECONFIG_DIR ?= .kube/generated
KUBECONFIG ?= $(abspath $(KUBECONFIG_DIR)/current.yaml)
WORKSPACE_CLUSTER_NAME ?= agentic-native-platform
ECHO_MCP_IMAGE ?= ghcr.io/example/echo-mcp:0.1.0
ECHO_MCP_IMAGE_TARBALL ?= /tmp/echo-mcp-image.tar
PORT_FORWARD_STATE_DIR ?= /tmp/agentic-native-platform-port-forwards
KAGENT_UI_LOCAL_PORT ?= 8080
KAGENT_A2A_LOCAL_PORT ?= 8083
AGENTGATEWAY_LOCAL_PORT ?= 15000
LITELLM_LOCAL_PORT ?= 4000
GRAFANA_LOCAL_PORT ?= 3000
PROMETHEUS_LOCAL_PORT ?= 9090
QDRANT_LOCAL_PORT ?= 6333
LITELLM_MASTER_KEY ?= change-me
PAUSE_STATE_CONFIGMAP ?= cluster-pause-state
PLATFORM_ROOT_TIMEOUT ?= 30m
PLATFORM_BOOTSTRAP_TIMEOUT ?= 10m
PLATFORM_INFRA_TIMEOUT ?= 15m
PLATFORM_APPS_TIMEOUT ?= 20m
export KUBECONFIG
KUBECTL ?= kubectl --kubeconfig "$(KUBECONFIG)"
FLUX ?= flux --kubeconfig "$(KUBECONFIG)"

PAUSE_NAMESPACES ?= ai-gateway ai-models context
PLATFORM_KUSTOMIZATIONS ?= platform-bootstrap platform-infrastructure platform-applications platform

.PHONY: help \
	tools-install-local render-terraform-tfvars terraform-init terraform-apply terraform-destroy \
	bootstrap-hosts install-k3s-server join-workers label-llm-nodes kubeconfig uninstall-k3s \
	cluster-up-local cluster-up-minipc cluster-up-hybrid cluster-up-hybrid-remote cluster-up-github-workspace run-cluster-from-scratch \
	flux-values render-cluster-root ensure-generated-flux-clean install-flux-local bootstrap-flux-git reconcile verify cluster-status \
	render-plaintext-secrets apply-plaintext-secrets delete-plaintext-secrets \
	sops-age-key render-sops-secrets encrypt-secrets decrypt-secrets sops-bootstrap-cluster \
	cluster-pause cluster-resume cluster-stop cluster-start cluster-remove environment-destroy preimport-vllm-image-tarball preimport-vllm-image-online require-kubeconfig \
	build-echo-mcp-image save-echo-mcp-image preimport-echo-mcp-image-tarball prepare-echo-mcp-image-local \
	k9s-local port-forward-agentgateway port-forward-kagent port-forward-kagent-ui port-forward-litellm port-forward-grafana port-forward-prometheus port-forward-qdrant \
	open-kagent-ui close-kagent-ui open-kagent-a2a close-kagent-a2a open-agentgateway close-agentgateway open-litellm close-litellm open-grafana close-grafana open-prometheus close-prometheus open-qdrant close-qdrant open-research-access close-research-access \
	test-a2a-agent test-agentgateway-gemini test-agentgateway-openai test-litellm test-lmstudio test-ollama test-vllm

define start_port_forward
	@mkdir -p $(PORT_FORWARD_STATE_DIR)
	@if [ -z "$$($(KUBECTL) -n $(3) get endpoints $(4) -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)" ]; then \
	  echo "$(1) cannot open because service $(3)/$(4) has no ready endpoints"; \
	  exit 1; \
	elif [ -f "$(PORT_FORWARD_STATE_DIR)/$(1).pid" ] && kill -0 "$$(cat "$(PORT_FORWARD_STATE_DIR)/$(1).pid")" 2>/dev/null; then \
	  echo "$(1) is already available at $(2)"; \
	else \
	  rm -f "$(PORT_FORWARD_STATE_DIR)/$(1).pid"; \
	  $(KUBECTL) -n $(3) port-forward svc/$(4) $(5):$(6) >"$(PORT_FORWARD_STATE_DIR)/$(1).log" 2>&1 & \
	  echo $$! >"$(PORT_FORWARD_STATE_DIR)/$(1).pid"; \
	  sleep 2; \
	  if ! kill -0 "$$(cat "$(PORT_FORWARD_STATE_DIR)/$(1).pid")" 2>/dev/null; then \
	    echo "$(1) failed to open"; \
	    sed -n '1,40p' "$(PORT_FORWARD_STATE_DIR)/$(1).log"; \
	    rm -f "$(PORT_FORWARD_STATE_DIR)/$(1).pid"; \
	    exit 1; \
	  fi; \
	  echo "$(1) available at $(2)"; \
	fi
endef

define stop_port_forward
	@if [ -f "$(PORT_FORWARD_STATE_DIR)/$(1).pid" ]; then \
	  pid="$$(cat "$(PORT_FORWARD_STATE_DIR)/$(1).pid")"; \
	  if kill -0 "$$pid" 2>/dev/null; then kill "$$pid" 2>/dev/null || true; fi; \
	  rm -f "$(PORT_FORWARD_STATE_DIR)/$(1).pid"; \
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

uninstall-k3s: ## Uninstall k3s from all hosts in the selected topology inventory
	ansible-playbook $(ANSIBLE_BECOME_FLAGS) -i $(ANSIBLE_INVENTORY) ansible/playbooks/uninstall-k3s.yml

cluster-up-local: ## Bootstrap a single-node local topology
	$(MAKE) terraform-init TOPOLOGY=local TF_BIN=$(TF_BIN)
	$(MAKE) terraform-apply TOPOLOGY=local TF_BIN=$(TF_BIN)
	$(MAKE) ensure-generated-flux-clean TOPOLOGY=local ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED)
	$(MAKE) bootstrap-hosts TOPOLOGY=local
	$(MAKE) install-k3s-server TOPOLOGY=local
	$(MAKE) kubeconfig TOPOLOGY=local

cluster-up-minipc: ## Bootstrap a single-node miniPC topology
	$(MAKE) terraform-init TOPOLOGY=minipc TF_BIN=$(TF_BIN)
	$(MAKE) terraform-apply TOPOLOGY=minipc TF_BIN=$(TF_BIN)
	$(MAKE) ensure-generated-flux-clean TOPOLOGY=minipc ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED)
	$(MAKE) bootstrap-hosts TOPOLOGY=minipc
	$(MAKE) install-k3s-server TOPOLOGY=minipc
	$(MAKE) kubeconfig TOPOLOGY=minipc

cluster-up-hybrid: ## Bootstrap a miniPC control-plane plus workstation worker topology
	$(MAKE) terraform-init TOPOLOGY=hybrid TF_BIN=$(TF_BIN)
	$(MAKE) terraform-apply TOPOLOGY=hybrid TF_BIN=$(TF_BIN)
	$(MAKE) ensure-generated-flux-clean TOPOLOGY=hybrid ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED)
	$(MAKE) bootstrap-hosts TOPOLOGY=hybrid
	$(MAKE) install-k3s-server TOPOLOGY=hybrid
	$(MAKE) join-workers TOPOLOGY=hybrid
	$(MAKE) label-llm-nodes TOPOLOGY=hybrid
	$(MAKE) kubeconfig TOPOLOGY=hybrid

cluster-up-hybrid-remote: ## Bootstrap a miniPC control-plane with workstation and remote worker nodes
	$(MAKE) terraform-init TOPOLOGY=hybrid-remote TF_BIN=$(TF_BIN)
	$(MAKE) terraform-apply TOPOLOGY=hybrid-remote TF_BIN=$(TF_BIN)
	$(MAKE) ensure-generated-flux-clean TOPOLOGY=hybrid-remote ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED)
	$(MAKE) bootstrap-hosts TOPOLOGY=hybrid-remote
	$(MAKE) install-k3s-server TOPOLOGY=hybrid-remote
	$(MAKE) join-workers TOPOLOGY=hybrid-remote
	$(MAKE) label-llm-nodes TOPOLOGY=hybrid-remote
	$(MAKE) kubeconfig TOPOLOGY=hybrid-remote

cluster-up-github-workspace: ## Bootstrap a GitHub workspace / Codespaces topology with k3d
	$(MAKE) ensure-generated-flux-clean TOPOLOGY=github-workspace ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED)
	WORKSPACE_CLUSTER_NAME="$(WORKSPACE_CLUSTER_NAME)" ./scripts/cluster-up-github-workspace.sh

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
	@$(MAKE) bootstrap-flux-git TOPOLOGY=$(TOPOLOGY) ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED)
	@$(MAKE) reconcile TOPOLOGY=$(TOPOLOGY) ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED)
	@$(MAKE) cluster-status TOPOLOGY=$(TOPOLOGY)

flux-values: ## Render non-secret Flux ConfigMaps for the selected topology
	./scripts/render-flux-values.sh $(TOPOLOGY)

render-cluster-root: ## Render the Flux root kustomization for the selected topology/env/runtime/secrets mode
	TOPOLOGY=$(TOPOLOGY) ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED) PLATFORM_BOOTSTRAP_TIMEOUT=$(PLATFORM_BOOTSTRAP_TIMEOUT) PLATFORM_INFRA_TIMEOUT=$(PLATFORM_INFRA_TIMEOUT) PLATFORM_APPS_TIMEOUT=$(PLATFORM_APPS_TIMEOUT) ./scripts/render-cluster-kustomization.sh

ensure-generated-flux-clean: flux-values render-cluster-root ## Render tracked Flux inputs and fail before cluster install continues if GitOps inputs need commit/push
	@changed="$$(git status --porcelain -- "flux/generated/$(TOPOLOGY)" "flux/generated/clusters/$(TOPOLOGY)-$(ENV)-$(RUNTIME)-$(SECRETS_MODE)")"; \
	if [ -n "$$changed" ]; then \
	  echo "Generated Flux manifests changed locally. Commit and push them before continuing:"; \
	  echo "$$changed"; \
	  exit 1; \
	fi

install-flux-local: require-kubeconfig ## Install Flux controllers into the current cluster
	$(FLUX) install

install-flux: require-kubeconfig ## Install Flux controllers into the selected/current cluster
	@if [ -n "$(KUBE_CONTEXT)" ]; then \
		echo "Installing Flux into context $(KUBE_CONTEXT)"; \
		flux --kubeconfig "$(KUBECONFIG)" --context "$(KUBE_CONTEXT)" install; \
	else \
		echo "Installing Flux into current context"; \
		$(FLUX) install; \
	fi

bootstrap-flux-git: require-kubeconfig flux-values render-cluster-root ## Apply Flux GitRepository and root Kustomization pointing to the remote repo
	TOPOLOGY=$(TOPOLOGY) ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED) PLATFORM_ROOT_TIMEOUT=$(PLATFORM_ROOT_TIMEOUT) PLATFORM_BOOTSTRAP_TIMEOUT=$(PLATFORM_BOOTSTRAP_TIMEOUT) PLATFORM_INFRA_TIMEOUT=$(PLATFORM_INFRA_TIMEOUT) PLATFORM_APPS_TIMEOUT=$(PLATFORM_APPS_TIMEOUT) ./scripts/bootstrap-flux-git.sh

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
	$(FLUX) get kustomizations -A || true
	$(FLUX) get helmreleases -A || true
	$(KUBECTL) get pods -A || true

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

cluster-pause: require-kubeconfig ## Pause platform workloads without uninstalling the cluster
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

cluster-resume: require-kubeconfig ## Resume platform workloads from Git desired state
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

open-kagent-ui: require-kubeconfig ## Open the kagent UI at http://localhost:8080
	$(call start_port_forward,kagent-ui,http://localhost:$(KAGENT_UI_LOCAL_PORT),kagent,kagent-kagent-ui,$(KAGENT_UI_LOCAL_PORT),8080)

close-kagent-ui: ## Close the kagent UI port-forward
	$(call stop_port_forward,kagent-ui)

open-kagent-a2a: require-kubeconfig ## Open the kagent controller API at http://localhost:8083
	$(call start_port_forward,kagent-a2a,http://localhost:$(KAGENT_A2A_LOCAL_PORT),kagent,kagent-kagent-controller,$(KAGENT_A2A_LOCAL_PORT),8083)

close-kagent-a2a: ## Close the kagent controller API port-forward
	$(call stop_port_forward,kagent-a2a)

open-agentgateway: require-kubeconfig ## Open AgentGateway at http://localhost:15000
	$(call start_port_forward,agentgateway,http://localhost:$(AGENTGATEWAY_LOCAL_PORT),agentgateway-system,agentgateway-proxy,$(AGENTGATEWAY_LOCAL_PORT),8080)

close-agentgateway: ## Close the AgentGateway port-forward
	$(call stop_port_forward,agentgateway)

open-litellm: require-kubeconfig ## Open LiteLLM at http://localhost:4000
	$(call start_port_forward,litellm,http://localhost:$(LITELLM_LOCAL_PORT),ai-gateway,litellm,$(LITELLM_LOCAL_PORT),4000)

close-litellm: ## Close the LiteLLM port-forward
	$(call stop_port_forward,litellm)

open-grafana: require-kubeconfig ## Open Grafana at http://localhost:3000
	$(call start_port_forward,grafana,http://localhost:$(GRAFANA_LOCAL_PORT),observability,observability-kube-prometheus-stack-grafana,$(GRAFANA_LOCAL_PORT),80)

close-grafana: ## Close the Grafana port-forward
	$(call stop_port_forward,grafana)

open-prometheus: require-kubeconfig ## Open Prometheus at http://localhost:9090
	$(call start_port_forward,prometheus,http://localhost:$(PROMETHEUS_LOCAL_PORT),observability,observability-kube-prometh-prometheus,$(PROMETHEUS_LOCAL_PORT),9090)

close-prometheus: ## Close the Prometheus port-forward
	$(call stop_port_forward,prometheus)

open-qdrant: require-kubeconfig ## Open Qdrant at http://localhost:6333
	$(call start_port_forward,qdrant,http://localhost:$(QDRANT_LOCAL_PORT),context,context-qdrant,$(QDRANT_LOCAL_PORT),6333)

close-qdrant: ## Close the Qdrant port-forward
	$(call stop_port_forward,qdrant)

open-research-access: require-kubeconfig ## Open the main local research endpoints on localhost
	$(MAKE) open-kagent-ui
	$(MAKE) open-kagent-a2a
	$(MAKE) open-agentgateway
	$(MAKE) open-litellm
	$(MAKE) open-grafana
	$(MAKE) open-prometheus
	$(MAKE) open-qdrant

close-research-access: ## Close all background localhost research endpoints
	$(MAKE) close-kagent-ui
	$(MAKE) close-kagent-a2a
	$(MAKE) close-agentgateway
	$(MAKE) close-litellm
	$(MAKE) close-grafana
	$(MAKE) close-prometheus
	$(MAKE) close-qdrant

test-a2a-agent: ## Fetch the sample agent card from kagent
	curl -fsSL http://localhost:8083/api/a2a/kagent/k8s-a2a-agent/.well-known/agent.json | jq .

test-agentgateway-gemini: ## Test the canonical OpenAI-compatible route through agentgateway -> LiteLLM -> Gemini
	curl -fsSL -H "Authorization: Bearer $(LITELLM_MASTER_KEY)" http://localhost:$(AGENTGATEWAY_LOCAL_PORT)/v1/models | jq .

test-agentgateway-openai: ## Test the agentgateway OpenAI-compatible route without requiring provider-specific CLI tools
	curl -fsSL -H "Authorization: Bearer $(LITELLM_MASTER_KEY)" http://localhost:$(AGENTGATEWAY_LOCAL_PORT)/v1/models | jq .

test-litellm: require-kubeconfig ## List available models directly from the LiteLLM service
	kubectl -n ai-gateway port-forward svc/litellm $(LITELLM_LOCAL_PORT):4000 >/tmp/litellm-pf.log 2>&1 & echo $$! > /tmp/litellm-pf.pid; \
	sleep 3; \
	curl -fsSL -H "Authorization: Bearer $(LITELLM_MASTER_KEY)" http://localhost:$(LITELLM_LOCAL_PORT)/v1/models | jq .; \
	kill $$(cat /tmp/litellm-pf.pid)

test-lmstudio: require-kubeconfig ## Check connectivity from the cluster to the external LM Studio endpoint
	kubectl -n ai-gateway run lmstudio-curl --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
	  curl -fsSL http://lmstudio-external.ai-gateway.svc.cluster.local:1234/v1/models

test-ollama: require-kubeconfig ## Check the in-cluster Ollama endpoint
	kubectl -n ai-models run ollama-curl --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
	  curl -fsSL http://ollama.ai-models.svc.cluster.local:11434/api/tags

test-vllm: require-kubeconfig ## Check the in-cluster vLLM endpoint
	kubectl -n ai-models run vllm-curl --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
	  curl -fsSL http://vllm-openai.ai-models.svc.cluster.local:8000/v1/models
