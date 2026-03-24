.PHONY: preimport-vllm-image-tarball preimport-vllm-image-online \
	build-echo-mcp-image save-echo-mcp-image preimport-echo-mcp-image-tarball prepare-echo-mcp-image-local \
	test-lmstudio test-ollama test-vllm

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
	@if [ "$(TOPOLOGY)" = "github-codespace" ]; then \
	  docker load -i $(ECHO_MCP_IMAGE_TARBALL); \
	  k3d image import $(ECHO_MCP_IMAGE) -c $(WORKSPACE_CLUSTER_NAME); \
	else \
	  ansible $(ANSIBLE_BECOME_FLAGS) -i $(ANSIBLE_INVENTORY) all -b -m file -a "path=/var/lib/rancher/k3s/agent/images state=directory mode=0755"; \
	  ansible $(ANSIBLE_BECOME_FLAGS) -i $(ANSIBLE_INVENTORY) all -b -m copy -a "src=$(ECHO_MCP_IMAGE_TARBALL) dest=/var/lib/rancher/k3s/agent/images/echo-mcp-image.tar mode=0644"; \
	  ansible $(ANSIBLE_BECOME_FLAGS) -i $(ANSIBLE_INVENTORY) all -b -m shell -a "k3s ctr images import /var/lib/rancher/k3s/agent/images/echo-mcp-image.tar"; \
	fi

prepare-echo-mcp-image-local: build-echo-mcp-image save-echo-mcp-image preimport-echo-mcp-image-tarball ## Build, save, and import the sample echo-mcp image into k3s nodes without pushing

test-lmstudio: require-kubeconfig ## Check connectivity from the cluster to the external LM Studio endpoint
	kubectl -n ai-gateway run lmstudio-curl --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
	  curl -fsSL http://lmstudio-external.ai-gateway.svc.cluster.local:1234/v1/models

test-ollama: require-kubeconfig ## Check the in-cluster Ollama endpoint
	kubectl -n ai-models run ollama-curl --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
	  curl -fsSL http://ollama.ai-models.svc.cluster.local:11434/api/tags

test-vllm: require-kubeconfig ## Check the in-cluster vLLM endpoint
	kubectl -n ai-models run vllm-curl --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- \
	  curl -fsSL http://vllm-openai.ai-models.svc.cluster.local:8000/v1/models
