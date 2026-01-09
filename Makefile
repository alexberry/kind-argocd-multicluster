SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c

# Configuration (overridable via environment)
DOCKER_HOST_INTERNAL_ADDRESS ?= host.docker.internal
ENVS := $(shell yq '.clusters|keys[]' templates/cluster_definitions.yaml)

.PHONY: help create-clusters delete-clusters install-argo uninstall-argo \
        get-argo-admin argo-port-forward create-secret add-clusters await-argo bootstrap

# Default target
help: ## Show this help
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# --- Cluster Lifecycle ---

create-clusters: ## Create all KIND clusters from cluster_definitions.yaml
	@for env in $(ENVS); do \
		kind create cluster --name $$env --config configs/kind-config.yaml; \
	done
	@kind create cluster --name argo

delete-clusters: ## Delete all KIND clusters
	@for env in $(ENVS); do \
		kind delete cluster --name $$env || true; \
	done
	@kind delete cluster --name argo || true

bootstrap: delete-clusters create-clusters install-argo create-secret add-clusters ## Full reset: delete, create, configure

# --- ArgoCD ---

await-argo: ## Wait for ArgoCD server and redis to be ready
	@echo "Awaiting argocd server & redis startup"
	@kubectx kind-argo > /dev/null 2>&1
	@kubectl wait -n default deploy/argo-cd-argocd-server --for condition=available --timeout=5m
	@kubectl wait -n default deploy/argo-cd-argocd-redis --for condition=available --timeout=5m

install-argo: ## Install ArgoCD via Helm (waits for readiness)
	@helm repo add argo https://argoproj.github.io/argo-helm
	@kubectx kind-argo > /dev/null 2>&1
	@helm -n default install argo-cd argo/argo-cd
	@$(MAKE) await-argo

uninstall-argo: ## Uninstall ArgoCD
	@kubectx kind-argo > /dev/null 2>&1
	@helm uninstall argo-cd -n default

get-argo-admin: ## Print ArgoCD admin password
	@kubectx kind-argo > /dev/null 2>&1
	@kubectl -n default get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
	@echo ""

argo-port-forward: ## Port-forward to ArgoCD UI (https://localhost:8080)
	@kubectx kind-argo > /dev/null 2>&1
	@echo "Admin user: admin"
	@echo "Admin password: $$(kubectl -n default get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
	@echo "Visit https://localhost:8080"
	@kubectl port-forward service/argo-cd-argocd-server 8080:80 | grep -v "^Handling connection"

# --- Cluster Registration ---

create-secret: ## Create kubeconfig secret for cluster registration
	@kubectx kind-argo > /dev/null 2>&1
	@kubectl delete secret kubecontexts -n default > /dev/null 2>&1 || true
	@templates_dir=$$(mktemp -d); \
	echo "Templates directory: $${templates_dir}"; \
	script_b64=$$(cat templates/cluster_add.sh | base64); \
	cat templates/secret.yaml | yq ".data.\"cluster_add.sh\" = \"$${script_b64}\"" > $${templates_dir}/secret.yaml; \
	for env in $(ENVS); do \
		kubectx kind-$$env > /dev/null 2>&1; \
		raw_context=$$(kubectl config view --minify --raw); \
		port=$$(yq '.clusters[0].cluster.server' <<< "$${raw_context}" | awk -F ':' '{print $$3}'); \
		modified_context_b64=$$(yq "del .clusters[0].cluster.certificate-authority-data | .clusters[0].cluster.insecure-skip-tls-verify = true | .clusters[0].cluster.server = \"https://$(DOCKER_HOST_INTERNAL_ADDRESS):$${port}\"|@yaml|@base64" <<< "$${raw_context}"); \
		yq -i ".data.\"kind-$${env}.yaml\" = \"$${modified_context_b64}\"" $${templates_dir}/secret.yaml; \
	done; \
	kubectx kind-argo > /dev/null 2>&1; \
	echo "Applying manifest $${templates_dir}/secret.yaml"; \
	kubectl apply -n default -f $${templates_dir}/secret.yaml

add-clusters: ## Register/update app clusters in ArgoCD
	@templates_dir=$$(mktemp -d); \
	kubectx kind-argo > /dev/null 2>&1; \
	for env in $(ENVS); do \
		job_name=argocd-add-cluster-$$env; \
		kubectl delete job $$job_name > /dev/null 2>&1 || true; \
		cat templates/job.yaml | yq ".spec.template.spec.containers[0].env[0].value = \"kind-$${env}\" | .metadata.name = \"$${job_name}\"" > $${templates_dir}/job-$$env.yaml; \
		label_args=""; \
		for label in $$(cat templates/cluster_definitions.yaml | yq ".clusters.$${env}.labels|keys[]"); do \
			value=$$(cat templates/cluster_definitions.yaml | yq ".clusters.$${env}.labels.$$label"); \
			label_args="$${label_args}--label $${label}=$${value} "; \
		done; \
		echo -e "$$env:\t$$label_args"; \
		yq -i ".spec.template.spec.containers[0].env[1].value = \"$${label_args}\"" $${templates_dir}/job-$$env.yaml; \
		echo "Applying manifest $${templates_dir}/job-$$env.yaml"; \
		kubectl apply -n default -f $${templates_dir}/job-$$env.yaml; \
	done; \
	for env in $(ENVS); do \
		job_name=argocd-add-cluster-$$env; \
		kubectl wait --for=condition=complete job/$$job_name --timeout=5m; \
	done
