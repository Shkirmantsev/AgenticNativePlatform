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
KUBECONFIG_DIR ?= .kube/generated

STOP_NAMESPACES ?= metallb-system istio-system kgateway-system agentgateway-system ai-gateway ai-models context kagent observability kserve kmcp-system

.PHONY: help \
	tools-install-local render-terraform-tfvars terraform-init terraform-apply terraform-destroy \
	bootstrap-hosts install-k3s-server join-workers label-llm-nodes kubeconfig uninstall-k3s \
	cluster-up-local cluster-up-minipc cluster-up-hybrid cluster-up-hybrid-remote \
	flux-values render-cluster-root install-flux-local bootstrap-flux-git reconcile verify \
	render-plaintext-secrets apply-plaintext-secrets delete-plaintext-secrets \
	sops-age-key render-sops-secrets encrypt-secrets decrypt-secrets sops-bootstrap-cluster \
	cluster-stop cluster-start preimport-vllm-image-tarball preimport-vllm-image-online \
	port-forward-agentgateway port-forward-kagent test-a2a-agent test-agentgateway-gemini test-agentgateway-openai test-litellm test-lmstudio test-ollama test-vllm

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9_.-]+:.*##/ {printf "%-32s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

tools-install-local: ## Install local operator tools (age, sops, kubectl, helm, flux, optional k9s, Terraform/OpenTofu)
	ansible-playbook -i localhost, -c local ansible/playbooks/install-local-tools.yml --extra-vars "iac_tool=$(IAC_TOOL) install_k9s=$(INSTALL_K9S)"

render-terraform-tfvars: ## Render local terraform.auto.tfvars from .env for the selected topology
	./scripts/render-terraform-tfvars.sh $(TOPOLOGY)

terraform-init: render-terraform-tfvars ## Initialize Terraform/OpenTofu in the selected topology directory
	$(TF_BIN) -chdir=$(TF_DIR) init

terraform-apply: render-terraform-tfvars ## Apply Terraform/OpenTofu in the selected topology directory
	$(TF_BIN) -chdir=$(TF_DIR) apply -auto-approve

terraform-destroy: render-terraform-tfvars ## Destroy Terraform/OpenTofu artifacts in the selected topology directory
	$(TF_BIN) -chdir=$(TF_DIR) destroy -auto-approve

bootstrap-hosts: ## Prepare the selected hosts for k3s
	ansible-playbook -i $(ANSIBLE_INVENTORY) ansible/playbooks/bootstrap-hosts.yml

install-k3s-server: ## Install the k3s server on the control-plane host
	ansible-playbook -i $(ANSIBLE_INVENTORY) ansible/playbooks/install-k3s-server.yml

join-workers: ## Join worker nodes to the k3s cluster
	ansible-playbook -i $(ANSIBLE_INVENTORY) ansible/playbooks/join-k3s-workers.yml

label-llm-nodes: ## Label worker nodes as runtime-capable for self-hosted LLM workloads
	ansible-playbook -i $(ANSIBLE_INVENTORY) ansible/playbooks/label-llm-nodes.yml

kubeconfig: ## Export kubeconfig from the control-plane host to .kube/generated
	mkdir -p $(KUBECONFIG_DIR)
	ansible-playbook -i $(ANSIBLE_INVENTORY) ansible/playbooks/export-kubeconfig.yml

uninstall-k3s: ## Uninstall k3s from all hosts in the selected topology inventory
	ansible-playbook -i $(ANSIBLE_INVENTORY) ansible/playbooks/uninstall-k3s.yml

cluster-up-local: ## Bootstrap a single-node local topology
	$(MAKE) terraform-init TOPOLOGY=local TF_BIN=$(TF_BIN)
	$(MAKE) terraform-apply TOPOLOGY=local TF_BIN=$(TF_BIN)
	$(MAKE) bootstrap-hosts TOPOLOGY=local
	$(MAKE) install-k3s-server TOPOLOGY=local
	$(MAKE) kubeconfig TOPOLOGY=local

cluster-up-minipc: ## Bootstrap a single-node miniPC topology
	$(MAKE) terraform-init TOPOLOGY=minipc TF_BIN=$(TF_BIN)
	$(MAKE) terraform-apply TOPOLOGY=minipc TF_BIN=$(TF_BIN)
	$(MAKE) bootstrap-hosts TOPOLOGY=minipc
	$(MAKE) install-k3s-server TOPOLOGY=minipc
	$(MAKE) kubeconfig TOPOLOGY=minipc

cluster-up-hybrid: ## Bootstrap a miniPC control-plane plus workstation worker topology
	$(MAKE) terraform-init TOPOLOGY=hybrid TF_BIN=$(TF_BIN)
	$(MAKE) terraform-apply TOPOLOGY=hybrid TF_BIN=$(TF_BIN)
	$(MAKE) bootstrap-hosts TOPOLOGY=hybrid
	$(MAKE) install-k3s-server TOPOLOGY=hybrid
	$(MAKE) join-workers TOPOLOGY=hybrid
	$(MAKE) label-llm-nodes TOPOLOGY=hybrid
	$(MAKE) kubeconfig TOPOLOGY=hybrid

cluster-up-hybrid-remote: ## Bootstrap a miniPC control-plane with workstation and remote worker nodes
	$(MAKE) terraform-init TOPOLOGY=hybrid-remote TF_BIN=$(TF_BIN)
	$(MAKE) terraform-apply TOPOLOGY=hybrid-remote TF_BIN=$(TF_BIN)
	$(MAKE) bootstrap-hosts TOPOLOGY=hybrid-remote
	$(MAKE) install-k3s-server TOPOLOGY=hybrid-remote
	$(MAKE) join-workers TOPOLOGY=hybrid-remote
	$(MAKE) label-llm-nodes TOPOLOGY=hybrid-remote
	$(MAKE) kubeconfig TOPOLOGY=hybrid-remote

flux-values: ## Render non-secret Flux ConfigMaps for the selected topology
	./scripts/render-flux-values.sh $(TOPOLOGY)

render-cluster-root: ## Render the Flux root kustomization for the selected topology/env/runtime/secrets mode
	TOPOLOGY=$(TOPOLOGY) ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED) ./scripts/render-cluster-kustomization.sh

install-flux-local: ## Install Flux controllers into the current cluster
	flux install

bootstrap-flux-git: flux-values render-cluster-root ## Apply Flux GitRepository and root Kustomization pointing to the remote repo
	TOPOLOGY=$(TOPOLOGY) ENV=$(ENV) RUNTIME=$(RUNTIME) SECRETS_MODE=$(SECRETS_MODE) LMSTUDIO_ENABLED=$(LMSTUDIO_ENABLED) ./scripts/bootstrap-flux-git.sh

reconcile: ## Reconcile Flux source and kustomization named 'platform' if present
	@flux reconcile source git platform -n flux-system || true
	@flux reconcile kustomization platform -n flux-system --with-source || true

verify: ## Basic local verification of cluster and Flux state
	kubectl get nodes -o wide || true
	kubectl get ns || true
	kubectl get gitrepositories -A || true
	kubectl get kustomizations -A || true
	kubectl get helmreleases -A || true

render-plaintext-secrets: ## Render local plaintext Kubernetes Secrets from .env into .generated/secrets/<env>
	ENV=$(ENV) ./scripts/render-plaintext-secrets.sh

apply-plaintext-secrets: render-plaintext-secrets ## Apply local plaintext secrets directly to the cluster (not committed to Git)
	kubectl apply -k .generated/secrets/$(ENV)

delete-plaintext-secrets: ## Delete local plaintext secret resources from the cluster
	-kubectl delete -k .generated/secrets/$(ENV)

sops-age-key: ## Generate a local age key and update .sops.yaml using the generated public recipient
	./scripts/create-age-key.sh

render-sops-secrets: ## Render plaintext inputs for SOPS from .env into .generated/secrets/<env>
	ENV=$(ENV) ./scripts/render-sops-secrets-from-env.sh

encrypt-secrets: render-sops-secrets ## Encrypt plaintext inputs into flux/secrets/<env>/*.sops.yaml and refresh kustomization.yaml
	ENV=$(ENV) ./scripts/encrypt-secrets.sh

decrypt-secrets: ## Decrypt committed SOPS secrets into .generated/decrypted/<env> for troubleshooting only
	ENV=$(ENV) ./scripts/decrypt-secrets.sh

sops-bootstrap-cluster: ## Upload the local age private key into flux-system for SOPS decryption
	./scripts/bootstrap-sops-secret.sh

cluster-stop: ## Pause platform workloads without uninstalling the cluster
	@flux suspend source git platform -n flux-system || true
	@flux suspend kustomization platform -n flux-system || true
	@for ns in $(STOP_NAMESPACES); do \
	  kubectl get ns $$ns >/dev/null 2>&1 || continue; \
	  kubectl -n $$ns get deploy -o name 2>/dev/null | xargs -r -n1 kubectl -n $$ns scale --replicas=0; \
	  kubectl -n $$ns get statefulset -o name 2>/dev/null | xargs -r -n1 kubectl -n $$ns scale --replicas=0; \
	done

cluster-start: ## Resume platform workloads from Git desired state
	@flux resume source git platform -n flux-system || true
	@flux resume kustomization platform -n flux-system || true
	@flux reconcile kustomization platform -n flux-system --with-source || true

preimport-vllm-image-tarball: ## Copy a saved vLLM image tarball into the k3s image import directory on all nodes
	@test -n "$(VLLM_IMAGE_TARBALL)" || (echo "Set VLLM_IMAGE_TARBALL=/path/to/image.tar" >&2; exit 1)
	ansible -i $(ANSIBLE_INVENTORY) all -b -m copy -a "src=$(VLLM_IMAGE_TARBALL) dest=/var/lib/rancher/k3s/agent/images/vllm-image.tar mode=0644"

preimport-vllm-image-online: ## Pre-pull the vLLM image on all nodes using ctr in k3s containerd
	@test -n "$(VLLM_IMAGE)" || (echo "Set VLLM_IMAGE=repo:tag" >&2; exit 1)
	ansible -i $(ANSIBLE_INVENTORY) all -b -m shell -a "k3s ctr images pull $(VLLM_IMAGE)"

port-forward-agentgateway: ## Port-forward the Kubernetes agentgateway service to localhost:15000
	kubectl -n agentgateway-system port-forward svc/agentgateway 15000:15000

port-forward-kagent: ## Port-forward kagent controller to localhost:8083
	kubectl -n kagent port-forward svc/kagent-controller 8083:8083

test-a2a-agent: ## Fetch the sample agent card from kagent
	curl -fsSL http://localhost:8083/api/a2a/kagent/k8s-a2a-agent/.well-known/agent.json | jq .

test-agentgateway-gemini: ## Test the canonical OpenAI-compatible route through agentgateway -> LiteLLM -> Gemini
	curl -fsSL http://localhost:15000/v1/models | jq .

test-agentgateway-openai: ## Test the agentgateway OpenAI-compatible route without requiring provider-specific CLI tools
	curl -fsSL http://localhost:15000/v1/models | jq .

test-litellm: ## List available models directly from the LiteLLM service
	kubectl -n ai-gateway port-forward svc/litellm 4000:4000 >/tmp/litellm-pf.log 2>&1 & echo $$! > /tmp/litellm-pf.pid; \
	sleep 3; \
	curl -fsSL http://localhost:4000/v1/models | jq .; \
	kill $$(cat /tmp/litellm-pf.pid)

test-lmstudio: ## Check connectivity from the cluster to the external LM Studio endpoint
	kubectl -n ai-gateway run lmstudio-curl --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
	  curl -fsSL http://lmstudio-external.ai-gateway.svc.cluster.local:1234/v1/models

test-ollama: ## Check the in-cluster Ollama endpoint
	kubectl -n ai-models run ollama-curl --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
	  curl -fsSL http://ollama.ai-models.svc.cluster.local:11434/api/tags

test-vllm: ## Check the in-cluster vLLM endpoint
	kubectl -n ai-models run vllm-curl --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
	  curl -fsSL http://vllm-openai.ai-models.svc.cluster.local:8000/v1/models
