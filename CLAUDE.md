# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository creates a local multi-cluster ArgoCD environment using KIND (Kubernetes in Docker) for testing GitOps approaches with ApplicationSet and Cluster Generator patterns. It provisions multiple application clusters and a management cluster running ArgoCD.

**Default clusters** (defined in `templates/cluster_definitions.yaml`):
- `dev` - tier: dev, env: platform
- `dev2` - tier: dev, env: platform (demonstrates ephemeral env without override file)
- `staging` - tier: staging, env: platform
- `prod` - tier: prod, env: platform
- `argo` - management cluster running ArgoCD

## Architecture

### Cluster Bootstrap Flow

1. **Cluster Creation**: KIND clusters are created from definitions in [templates/cluster_definitions.yaml](templates/cluster_definitions.yaml)
2. **ArgoCD Installation**: Helm installs ArgoCD into the `kind-argo` management cluster
3. **Kubeconfig Secret**: Kubecontexts from app clusters are:
   - Exported from each cluster
   - Modified for Docker networking (`127.0.0.1` → `host.docker.internal` or `172.17.0.1` on Linux)
   - TLS verification disabled (`insecure-skip-tls-verify: true`)
   - Stored as base64-encoded secrets in the ArgoCD cluster
4. **Cluster Registration**: Kubernetes Jobs run [templates/cluster_add.sh](templates/cluster_add.sh) to register each app cluster with ArgoCD using labels from cluster definitions

### Key Components

- **[bootstrap.sh](bootstrap.sh)**: Main orchestration script with functions for each lifecycle operation
- **[templates/cluster_definitions.yaml](templates/cluster_definitions.yaml)**: Defines all clusters and their labels (tier, env, etc.)
- **[templates/job.yaml](templates/job.yaml)**: Job template for adding clusters to ArgoCD
- **[templates/cluster_add.sh](templates/cluster_add.sh)**: Script executed in jobs to authenticate and register clusters
- **[templates/secret.yaml](templates/secret.yaml)**: Secret template holding kubeconfigs and registration script
- **[configs/kind-config.yaml](configs/kind-config.yaml)**: KIND configuration (enables `0.0.0.0` binding for cross-cluster routing)

### Example Charts

- **[examples/charts/http-echo](examples/charts/http-echo)**: Test chart using `mendhak/http-https-echo` image that echoes all environment variables back - useful for validating that correct values are applied per cluster

## Common Commands

### Full Environment Setup
```bash
./bootstrap.sh bootstrap  # Deletes existing clusters, creates new ones, installs ArgoCD, registers clusters
```

### Individual Operations
```bash
./bootstrap.sh create-clusters      # Create KIND clusters only
./bootstrap.sh delete-clusters      # Delete all KIND clusters
./bootstrap.sh install-argo         # Install ArgoCD via Helm
./bootstrap.sh uninstall-argo       # Uninstall ArgoCD
./bootstrap.sh create-secret        # Create kubeconfig secret
./bootstrap.sh add-clusters         # Register clusters with ArgoCD (also used to update labels)
./bootstrap.sh await-argo           # Wait for ArgoCD to be ready
./bootstrap.sh argo-port-forward    # Port-forward to ArgoCD UI (https://localhost:8080)
./bootstrap.sh get-argo-admin       # Get ArgoCD admin password
```

### Working with Clusters
```bash
kubectx kind-dev                    # Switch to dev cluster
kubectx kind-argo                   # Switch to ArgoCD management cluster
kubectl config view --minify       # View current cluster config
```

### Deploying Example Applications
```bash
kubectx kind-argo

# Simple cluster generator examples
kubectl apply -f examples/argocdmanifests/applicationset/guestbook-applicationset.yaml
kubectl apply -f examples/argocdmanifests/applicationset/http-echo-applicationset.yaml

# Matrix generator with GitOps config pattern
kubectl apply -f examples/gitops-config/applicationsets/http-echo.yaml
```

## Platform-Specific Notes

### Linux with Docker
Must set before running:
```bash
sudo sysctl fs.inotify.max_user_watches=524288
sudo sysctl fs.inotify.max_user_instances=512
export KIND_EXPERIMENTAL_PROVIDER=docker
export DOCKER_HOST_INTERNAL_ADDRESS=172.17.0.1  # Replaces host.docker.internal
```

### Podman
Not supported due to networking limitations with `host.docker.internal` equivalent.

## Modifying Cluster Definitions

1. Edit [templates/cluster_definitions.yaml](templates/cluster_definitions.yaml)
2. To add/modify clusters after initial creation:
   ```bash
   ./bootstrap.sh delete-clusters
   ./bootstrap.sh create-clusters
   ./bootstrap.sh install-argo
   ./bootstrap.sh create-secret
   ./bootstrap.sh add-clusters
   ```
3. To update labels only on existing clusters:
   ```bash
   ./bootstrap.sh add-clusters  # Uses --upsert flag in cluster_add.sh
   ```

## ApplicationSet Patterns

### Simple Cluster Generator
Examples in [examples/argocdmanifests](examples/argocdmanifests) use [Cluster Generator](https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/Generators-Cluster/) to deploy applications based on cluster labels.

### Matrix Generator with GitOps Config
Examples in [examples/gitops-config](examples/gitops-config) demonstrate production-ready patterns:

```
examples/gitops-config/
├── versions.yaml                    # Central version manifest
├── applicationsets/
│   └── http-echo.yaml              # Matrix generator ApplicationSet
├── base/
│   └── http-echo/
│       └── values.yaml             # Shared defaults for ALL clusters
└── environments/
    ├── dev/http-echo.yaml          # Optional overrides for cluster "dev"
    ├── staging/http-echo.yaml      # Optional overrides for cluster "staging"
    └── prod/http-echo.yaml         # Optional overrides for cluster "prod"
```

**Key patterns:**
- **Matrix Generator**: Combines Git generator (versions.yaml) + Cluster generator
- **Multi-source Helm**: Chart + values files via `$values` ref
- **Base + Override**: All clusters get base values, optional per-cluster overrides
- **Ephemeral environments**: `ignoreMissingValueFiles: true` allows clusters without explicit config
- **Cluster name as identifier**: Overrides keyed by `{{.name}}` not tier labels

**Deploy:**
```bash
kubectx kind-argo
kubectl apply -f examples/gitops-config/applicationsets/http-echo.yaml
```

**Version management:** CI updates `versions.yaml` on build, ArgoCD syncs automatically. This replaces terraform-state-as-KV-store patterns.

## Security Notes

- KIND clusters bind to `0.0.0.0` for cross-cluster routing, exposing them to the local network
- TLS verification is disabled for cluster registration (development environment only)
- ArgoCD admin password: `kubectl -n default get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`
