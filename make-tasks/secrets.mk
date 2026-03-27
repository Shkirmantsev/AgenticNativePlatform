.PHONY: render-plaintext-secrets apply-plaintext-secrets delete-plaintext-secrets \
	sops-age-key render-sops-secrets encrypt-secrets decrypt-secrets sops-bootstrap-cluster provision-grafana-mcp-token

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

encrypt-secrets: render-sops-secrets ## Encrypt plaintext inputs into secrets/<topology>/*.sops.yaml and refresh kustomization.yaml
	ENV=$(ENV) TOPOLOGY=$(TOPOLOGY) ./scripts/encrypt-secrets.sh

decrypt-secrets: ## Decrypt committed SOPS secrets into .generated/decrypted/<env> for troubleshooting only
	ENV=$(ENV) TOPOLOGY=$(TOPOLOGY) ./scripts/decrypt-secrets.sh

sops-bootstrap-cluster: require-kubeconfig ## Upload the local age private key into flux-system for SOPS decryption
	ansible-playbook -i localhost, -c local ansible/playbooks/bootstrap-sops-age-secret.yml --extra-vars "kubeconfig_path=$(KUBECONFIG)"

provision-grafana-mcp-token: require-kubeconfig ## Create or refresh the Grafana MCP service account token and apply Secret/kagent-grafana-mcp
	ENV=$(ENV) KUBECONFIG=$(KUBECONFIG) ./scripts/provision-grafana-mcp-token.sh
