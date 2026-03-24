.PHONY: tools-install-local render-terraform-tfvars terraform-init terraform-apply terraform-destroy \
	bootstrap-hosts install-k3s-server join-workers label-llm-nodes kubeconfig uninstall-k3s \
	cluster-up-local cluster-up-minipc cluster-up-hybrid cluster-up-hybrid-remote cluster-up-github-workspace

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
