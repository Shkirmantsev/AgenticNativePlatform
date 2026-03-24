.PHONY: profile-fast profile-fast-serving profile-full run-cluster-from-scratch \
	flux-values render-cluster-root ensure-generated-flux-clean install-flux-operator install-flux-local install-flux \
	bootstrap-flux-instance bootstrap-flux-git reconcile verify cluster-status

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
