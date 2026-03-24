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
LMSTUDIO_ENABLED ?= false
INSTALL_K9S ?= true
IAC_TOOL ?= tofu
TF_BIN ?= $(if $(filter tofu,$(IAC_TOOL)),tofu,terraform)
TF_DIR = terraform/environments/$(TOPOLOGY)
FLUX_OPERATOR_VERSION ?= 0.45.1
FLUX_VERSION ?= 2.8.3
FLUX_SYNC_SOURCE_NAME ?= flux-system
FLUX_INSTANCE_SYNC_PATH ?= ./clusters/$(TOPOLOGY)-$(ENV)
ifneq ($(filter ./flux/generated/clusters/%,$(FLUX_INSTANCE_SYNC_PATH)),)
override FLUX_INSTANCE_SYNC_PATH := ./clusters/$(TOPOLOGY)-$(ENV)
endif
ANSIBLE_INVENTORY ?= $(or $(wildcard ansible/generated/$(TOPOLOGY).ini),ansible/inventory.ini.example)
ANSIBLE_BECOME_FLAGS ?=
KUBECONFIG_DIR ?= .kube/generated
KUBECONFIG ?= $(abspath $(KUBECONFIG_DIR)/current.yaml)
LITELLM_GENERATED_SECRET_FILE ?= .generated/secrets/$(ENV)/litellm-provider-secrets.yaml
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
ifeq ($(strip $(LITELLM_MASTER_KEY)),)
ifneq (,$(wildcard $(LITELLM_GENERATED_SECRET_FILE)))
override LITELLM_MASTER_KEY := $(strip $(shell awk -F': ' '/LITELLM_MASTER_KEY:/ {print $$2; exit}' $(LITELLM_GENERATED_SECRET_FILE)))
endif
endif
PAUSE_STATE_CONFIGMAP ?= cluster-pause-state
PLATFORM_ROOT_TIMEOUT ?= 30m
PLATFORM_BOOTSTRAP_TIMEOUT ?= 10m
PLATFORM_INFRA_TIMEOUT ?= 15m
PLATFORM_APPS_TIMEOUT ?= 20m
HTTP_PROBE_TIMEOUT ?= 30
HTTP_PROBE_INTERVAL ?= 1
CURL ?= curl
export KUBECONFIG
export LITELLM_MASTER_KEY
KUBECTL ?= kubectl --kubeconfig "$(KUBECONFIG)"
FLUX ?= flux --kubeconfig "$(KUBECONFIG)"

PAUSE_NAMESPACES ?= ai-gateway ai-models context
PLATFORM_KUSTOMIZATIONS ?= platform-infrastructure platform-secrets platform-applications

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

.PHONY: help require-kubeconfig require-cluster-api validate-config

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9_.-]+:.*##/ {printf "%-32s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

require-kubeconfig:
	@test -f "$(KUBECONFIG)" || (echo "Missing kubeconfig: $(KUBECONFIG). Run 'make kubeconfig TOPOLOGY=$(TOPOLOGY)' first." >&2; exit 1)

require-cluster-api: require-kubeconfig
	@./scripts/require-kube-apiserver.sh "$@"

validate-config: ## Run local Helm and Kustomize validation for committed config
	@./scripts/validate-config.sh

include make-tasks/infra.mk
include make-tasks/flux.mk
include make-tasks/secrets.mk
include make-tasks/runtime.mk
include make-tasks/ops.mk
