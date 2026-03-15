# Production-ready helper targets for the repository.
# Defaults are optimized for a first local, remote-only startup.

ifneq (,$(wildcard .env))
include .env
export $(shell sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' .env)
endif

TOPOLOGY ?= local
ENV ?= dev
RUNTIME ?= none
ANSIBLE_INVENTORY ?= ansible/generated/$(TOPOLOGY).ini
TF_DIR ?= terraform/environments/$(TOPOLOGY)
TF_VARS_FILE ?= terraform.tfvars
CLUSTER_PATH ?= ./flux/clusters/$(TOPOLOGY)-$(ENV)-$(RUNTIME)
VLLM_IMAGE ?= public.ecr.aws/q9t5s3a7/vllm-cpu-release-repo:latest
VLLM_IMAGE_TARBALL ?=

.PHONY: help terraform-vars terraform-init terraform-plan terraform-apply terraform-destroy 	bootstrap-hosts install-k3s-server join-workers label-llm-nodes kubeconfig uninstall-k3s 	sops-age-key encrypt-secrets decrypt-secrets install-flux-local bootstrap-flux-git 	apply-cluster reconcile port-forward-kagent port-forward-agentgateway test-agentgateway-gemini test-agentgateway-openai test-a2a-agent 	test-ollama test-vllm test-litellm test-lmstudio preimport-vllm-image-online preimport-vllm-image-tarball verify 	cluster-up-local cluster-up-minipc cluster-up-hybrid cluster-up-hybrid-remote

help: ## Show available targets
	@grep -h -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "%-32s %s\n", $$1, $$2}'

terraform-vars: ## Render topology-specific terraform.tfvars from .env
	./scripts/render-terraform-tfvars.sh $(TOPOLOGY)

terraform-init: terraform-vars ## Init Terraform for selected topology
	terraform -chdir=$(TF_DIR) init

terraform-plan: terraform-vars ## Plan topology artifacts and optional external infra
	terraform -chdir=$(TF_DIR) plan -var-file=$(TF_VARS_FILE)

terraform-apply: terraform-vars ## Apply topology artifacts and optional external infra
	terraform -chdir=$(TF_DIR) apply -auto-approve -var-file=$(TF_VARS_FILE)

terraform-destroy: terraform-vars ## Destroy optional external infra and generated artifacts
	terraform -chdir=$(TF_DIR) destroy -auto-approve -var-file=$(TF_VARS_FILE)

bootstrap-hosts: ## Bootstrap OS packages, kernel modules, sysctl and hardening prerequisites
	ansible-playbook -i $(ANSIBLE_INVENTORY) ansible/playbooks/bootstrap-hosts.yml

install-k3s-server: ## Install k3s server on the control-plane host
	ansible-playbook -i $(ANSIBLE_INVENTORY) ansible/playbooks/install-k3s-server.yml

join-workers: ## Join all workers to the cluster
	ansible-playbook -i $(ANSIBLE_INVENTORY) ansible/playbooks/join-k3s-workers.yml

label-llm-nodes: ## Label nodes that are allowed to run self-hosted model runtimes
	ansible-playbook -i $(ANSIBLE_INVENTORY) ansible/playbooks/label-llm-nodes.yml

kubeconfig: ## Export remote kubeconfig into local .kube/generated/<topology>.yaml
	mkdir -p .kube/generated
	ansible-playbook -i $(ANSIBLE_INVENTORY) ansible/playbooks/export-kubeconfig.yml

uninstall-k3s: ## Remove k3s from all hosts in the inventory
	ansible-playbook -i $(ANSIBLE_INVENTORY) ansible/playbooks/uninstall-k3s.yml

sops-age-key: ## Create local age key pair for SOPS secret encryption
	./scripts/create-age-key.sh

encrypt-secrets: ## Encrypt all secret templates for the selected environment
	ENV=$(ENV) ./scripts/encrypt-secrets.sh

decrypt-secrets: ## Decrypt selected environment secrets locally
	ENV=$(ENV) ./scripts/decrypt-secrets.sh

install-flux-local: ## Install Flux controllers into the target cluster from the local workstation
	./scripts/install-flux-local.sh

bootstrap-flux-git: ## Register this Git repository as the Flux source and root Kustomization
	TOPOLOGY=$(TOPOLOGY) ENV=$(ENV) RUNTIME=$(RUNTIME) ./scripts/bootstrap-flux-git.sh

apply-cluster: ## Apply the chosen topology+environment+runtime root kustomization directly
	kubectl apply -k $(CLUSTER_PATH)

reconcile: ## Trigger Flux reconciliation of the root Git source and Kustomization
	flux reconcile source git platform -n flux-system || true
	flux reconcile kustomization platform -n flux-system || true

preimport-vllm-image-online: ## Pre-pull the vLLM image into k3s containerd using the K3s images directory
	ansible all -i $(ANSIBLE_INVENTORY) -b -m file -a "path=/var/lib/rancher/k3s/agent/images state=directory mode=0755"
	ansible all -i $(ANSIBLE_INVENTORY) -b -m copy -a "dest=/var/lib/rancher/k3s/agent/images/vllm-images.txt content='$(VLLM_IMAGE)\n' mode=0644"

preimport-vllm-image-tarball: ## Copy a pre-saved vLLM image tarball into k3s containerd image store on each node
	@test -n "$(VLLM_IMAGE_TARBALL)" || (echo "Set VLLM_IMAGE_TARBALL=/path/to/vllm-image.tar"; exit 1)
	ansible all -i $(ANSIBLE_INVENTORY) -b -m file -a "path=/var/lib/rancher/k3s/agent/images state=directory mode=0755"
	ansible all -i $(ANSIBLE_INVENTORY) -b -m copy -a "src=$(VLLM_IMAGE_TARBALL) dest=/var/lib/rancher/k3s/agent/images/$(notdir $(VLLM_IMAGE_TARBALL)) mode=0644"

port-forward-kagent: ## Expose kagent A2A endpoint and UI locally
	kubectl port-forward svc/kagent-controller -n kagent 8083:8083 &
	kubectl port-forward svc/kagent-ui -n kagent 8080:8080

port-forward-agentgateway: ## Expose agentgateway standalone API and UI locally
	kubectl port-forward svc/agentgateway-standalone -n ai-gateway 3000:3000 15000:15000

test-agentgateway-gemini: ## Verify agentgateway standalone Gemini route via x-provider header
	curl -s http://localhost:3000/v1/models -H 'x-provider: gemini' | jq .

test-agentgateway-openai: ## Verify agentgateway standalone OpenAI route via x-provider header
	curl -s http://localhost:3000/v1/models -H 'x-provider: openai' | jq .

test-a2a-agent: ## Verify the sample embedded A2A agent card
	curl -s http://localhost:8083/api/a2a/kagent/k8s-a2a-agent/.well-known/agent.json | jq .

test-ollama: ## Verify the self-hosted Ollama endpoint
	kubectl port-forward svc/ollama -n ai-models 11434:11434 &
	sleep 2
	curl -s http://localhost:11434/api/tags | jq .

test-vllm: ## Verify the self-hosted vLLM endpoint when RUNTIME=vllm is deployed
	kubectl port-forward svc/vllm-openai -n ai-models 8000:8000 &
	sleep 4
	curl -s http://localhost:8000/health

test-litellm: ## Verify the LiteLLM readiness endpoint
	kubectl port-forward svc/litellm -n ai-gateway 4000:4000 &
	sleep 2
	curl -s http://localhost:4000/health/readiness | jq .

test-lmstudio: ## Verify that the external LM Studio endpoint is reachable from inside the cluster
	kubectl run -n ai-gateway lmstudio-probe --rm --restart=Never --image=curlimages/curl:8.10.1 -- http://lmstudio-external.ai-gateway.svc.cluster.local:1234/v1/models

verify: ## Quick cluster health check
	kubectl get nodes -o wide
	kubectl get pods -A
	kubectl get gatewayclass || true
	kubectl get gateways -A || true

cluster-up-local: ## Bootstrap local topology end-to-end up to kubeconfig export
	$(MAKE) terraform-init TOPOLOGY=local
	$(MAKE) terraform-apply TOPOLOGY=local
	$(MAKE) bootstrap-hosts TOPOLOGY=local
	$(MAKE) install-k3s-server TOPOLOGY=local
	$(MAKE) kubeconfig TOPOLOGY=local

cluster-up-minipc: ## Bootstrap miniPC topology end-to-end up to kubeconfig export
	$(MAKE) terraform-init TOPOLOGY=minipc
	$(MAKE) terraform-apply TOPOLOGY=minipc
	$(MAKE) bootstrap-hosts TOPOLOGY=minipc
	$(MAKE) install-k3s-server TOPOLOGY=minipc
	$(MAKE) kubeconfig TOPOLOGY=minipc

cluster-up-hybrid: ## Bootstrap hybrid topology end-to-end up to kubeconfig export
	$(MAKE) terraform-init TOPOLOGY=hybrid
	$(MAKE) terraform-apply TOPOLOGY=hybrid
	$(MAKE) bootstrap-hosts TOPOLOGY=hybrid
	$(MAKE) install-k3s-server TOPOLOGY=hybrid
	$(MAKE) join-workers TOPOLOGY=hybrid
	$(MAKE) label-llm-nodes TOPOLOGY=hybrid
	$(MAKE) kubeconfig TOPOLOGY=hybrid

cluster-up-hybrid-remote: ## Bootstrap hybrid-remote topology end-to-end up to kubeconfig export
	$(MAKE) terraform-init TOPOLOGY=hybrid-remote
	$(MAKE) terraform-apply TOPOLOGY=hybrid-remote
	$(MAKE) bootstrap-hosts TOPOLOGY=hybrid-remote
	$(MAKE) install-k3s-server TOPOLOGY=hybrid-remote
	$(MAKE) join-workers TOPOLOGY=hybrid-remote
	$(MAKE) label-llm-nodes TOPOLOGY=hybrid-remote
	$(MAKE) kubeconfig TOPOLOGY=hybrid-remote
