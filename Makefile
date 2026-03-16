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

STOP_NAMESPACES ?= metallb-system istio-system kgateway-system agentgateway-system ai-gateway ai-models context kagent observability kserve

.PHONY: help tools-install-local terraform-init terraform-apply terraform-destroy install-flux-local reconcile verify cluster-stop cluster-start

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9_-]+:.*##/ {printf "%-28s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

tools-install-local: ## Install operator tools locally with Ansible (age, sops, kubectl, helm, flux, optional k9s, Terraform/OpenTofu)
	ansible-playbook -i localhost, -c local ansible/playbooks/install-local-tools.yml --extra-vars "iac_tool=$(IAC_TOOL) install_k9s=$(INSTALL_K9S)"

terraform-init: ## Initialize Terraform/OpenTofu in the selected topology directory
	$(TF_BIN) -chdir=$(TF_DIR) init

terraform-apply: ## Apply Terraform/OpenTofu in the selected topology directory
	$(TF_BIN) -chdir=$(TF_DIR) apply -auto-approve

terraform-destroy: ## Destroy Terraform/OpenTofu artifacts in the selected topology directory
	$(TF_BIN) -chdir=$(TF_DIR) destroy -auto-approve

install-flux-local: ## Install Flux controllers into the current cluster
	flux install

reconcile: ## Reconcile Flux source and kustomization named 'platform' if present
	@flux reconcile source git platform -n flux-system || true
	@flux reconcile kustomization platform -n flux-system --with-source || true

verify: ## Basic local verification of cluster and Flux state
	kubectl get nodes -o wide || true
	kubectl get ns || true
	kubectl get gitrepositories -A || true
	kubectl get kustomizations -A || true
	kubectl get helmreleases -A || true

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
