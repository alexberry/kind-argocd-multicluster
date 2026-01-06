# Local argocd multicluster with kind

This project sets up a set of clusters and a managing argo-cd cluster, to test gitops approaches using applicationset & clustergenerator. It uses [kind](https://kind.sigs.k8s.io/) & docker to achieve this.

- [Local argocd multicluster with kind](#local-argocd-multicluster-with-kind)
- [Design](#design)
- [Network security note](#network-security-note)
- [Requirements](#requirements)
  - [Notes for linux / podman users](#notes-for-linux--podman-users)
    - [Docker](#docker)
    - [Podman](#podman)
- [`bootstrap.sh` Usage](#bootstrapsh-usage)
  - [Defining your clusters](#defining-your-clusters)
  - [Create Clusters](#create-clusters)
  - [Example rendered manifests](#example-rendered-manifests)
  - [Port-forwarding to argo](#port-forwarding-to-argo)
  - [Confirming cluster addition](#confirming-cluster-addition)
  - [Working with clusters](#working-with-clusters)
  - [Cleaning up](#cleaning-up)
- [Example ArgoCD Manifests](#example-argocd-manifests)

# Design

* clean any historic clusters from this script
* build 3 app clusters `dev staging prod` & an app cluster `argo` with [kind](https://kind.sigs.k8s.io/)
* install argocd with helm in to the argo cluster and wait for it to be available
* create a secret on the `argo` cluster
    * export the kubernetes contexts for each app cluster
    * reconfigure them for use on the argo cluster
      * rewrite `127.0.0.1` to `host.docker.internal`
      * remove key `clusters[0].cluster.certificate-authority-data`
      * add key `clusters[0].cluster.insecure-skip-tls-verify: true`
    * write kubernetes contexts to a secret
    * add cluster addition script to secret
* create a job per app cluster on the `argo` cluster that adds the other clusters to argo
  * create job with kubernetes contexts & cluster addition script mounted from secret
  * run cluster addition script for the app cluster

# Network security note

I have had to configure kind to listen on `0.0.0.0` to be able to route between kind clusters on all platforms, the downside of which is that you will be exposing a cluster to your local network unless firewalled.

# Requirements

You will need the following tools to run this repository:
* `kubectl`
* `kubectx`
* [`yq`](https://mikefarah.gitbook.io/yq) (v4+)
* [`kind`](https://kind.sigs.k8s.io/)
* `docker`
* `helm`

## Notes for linux / podman users

### Docker

This repo works on linux with docker, however a couple of environment & sysctl variables should be set:
```
# Without this configured you may fill your quota before you can build all defined clusters
sudo sysctl fs.inotify.max_user_watches=524288
sudo sysctl fs.inotify.max_user_instances=512
# forces the use of docker if podman is also installed
export KIND_EXPERIMENTAL_PROVIDER=docker
# workaround the fact that host.docker.internal is not available on linux
# this IP is valid unless you modify your default docker network
export DOCKER_HOST_INTERNAL_ADDRESS=172.17.0.1
```

### Podman

**TLDR** this repository is not compatible with podman, only docker.

Ultimately this script does not support podman owing to [differences](https://github.com/containers/podman/issues/10878) in the way podman networking works limiting access to `host.docker.internal` or it's equivalent.

If you try, you may find the script fails to build all the clusters with errors like:
```
too many open files
```
```
 ✗ Preparing nodes 📦
Deleted nodes: ["3-control-plane"]
ERROR: failed to create cluster: could not find a log line that matches "Reached target .*Multi-User System.*|detected cgroup v1"
```
If so, this is a known [issue](https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files) with podman.

# `bootstrap.sh` Usage

## Defining your clusters

Clusters & their labels are defined in the file [templates/cluster_definitions.yaml](templates/cluster_definitions.yaml). By default it adds the label `env` to determine which type of cluster it is (`platform` or `internal-services`), and `tier` to determine the configuration set to apply to the given environment (e.g. `dev`, `staging`, `prod`). You can add additional labels * clusters as you see fit, if you want to modify the labels after initial cluster creation you can apply the changes with the commands:
```
./bootstrap.sh add-clusters
```

## Create Clusters

To create a new set of clusters:
```
$ ./bootstrap.sh bootstrap
Deleting cluster "dev" ...
Deleting cluster "staging" ...
Deleting cluster "prod" ...
Deleting cluster "argo" ...
Creating cluster "dev" ...
 • Ensuring node image (kindest/node:v1.35.0) 🖼  ...
 ✓ Ensuring node image (kindest/node:v1.35.0) 🖼
 • Preparing nodes 📦   ...
 ✓ Preparing nodes 📦 
 • Writing configuration 📜  ...
 ✓ Writing configuration 📜
 • Starting control-plane 🕹️  ...
 ✓ Starting control-plane 🕹️
 • Installing CNI 🔌  ...
 ✓ Installing CNI 🔌
 • Installing StorageClass 💾  ...
 ✓ Installing StorageClass 💾
Set kubectl context to "kind-dev"
You can now use your cluster with:

kubectl cluster-info --context kind-dev

Have a question, bug, or feature request? Let us know! https://kind.sigs.k8s.io/#community 🙂
Creating cluster "staging" ...
 • Ensuring node image (kindest/node:v1.35.0) 🖼  ...
 ✓ Ensuring node image (kindest/node:v1.35.0) 🖼
 • Preparing nodes 📦   ...
 ✓ Preparing nodes 📦 
 • Writing configuration 📜  ...
 ✓ Writing configuration 📜
 • Starting control-plane 🕹️  ...
 ✓ Starting control-plane 🕹️
 • Installing CNI 🔌  ...
 ✓ Installing CNI 🔌
 • Installing StorageClass 💾  ...
 ✓ Installing StorageClass 💾
Set kubectl context to "kind-staging"
You can now use your cluster with:

kubectl cluster-info --context kind-staging

Not sure what to do next? 😅  Check out https://kind.sigs.k8s.io/docs/user/quick-start/
Creating cluster "prod" ...
 • Ensuring node image (kindest/node:v1.35.0) 🖼  ...
 ✓ Ensuring node image (kindest/node:v1.35.0) 🖼
 • Preparing nodes 📦   ...
 ✓ Preparing nodes 📦 
 • Writing configuration 📜  ...
 ✓ Writing configuration 📜
 • Starting control-plane 🕹️  ...
 ✓ Starting control-plane 🕹️
 • Installing CNI 🔌  ...
 ✓ Installing CNI 🔌
 • Installing StorageClass 💾  ...
 ✓ Installing StorageClass 💾
Set kubectl context to "kind-prod"
You can now use your cluster with:

kubectl cluster-info --context kind-prod

Thanks for using kind! 😊
Creating cluster "argo" ...
 • Ensuring node image (kindest/node:v1.35.0) 🖼  ...
 ✓ Ensuring node image (kindest/node:v1.35.0) 🖼
 • Preparing nodes 📦   ...
 ✓ Preparing nodes 📦 
 • Writing configuration 📜  ...
 ✓ Writing configuration 📜
 • Starting control-plane 🕹️  ...
 ✓ Starting control-plane 🕹️
 • Installing CNI 🔌  ...
 ✓ Installing CNI 🔌
 • Installing StorageClass 💾  ...
 ✓ Installing StorageClass 💾
Set kubectl context to "kind-argo"
You can now use your cluster with:

kubectl cluster-info --context kind-argo

Have a nice day! 👋
"argo" has been added to your repositories
NAME: argo-cd
LAST DEPLOYED: Fri Dec 19 21:18:44 2025
NAMESPACE: default
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
TEST SUITE: None
NOTES:
In order to access the server UI you have the following options:

1. kubectl port-forward service/argo-cd-argocd-server -n default 8080:443

    and then open the browser on http://localhost:8080 and accept the certificate

2. enable ingress in the values file `server.ingress.enabled` and either
      - Add the annotation for ssl passthrough: https://argo-cd.readthedocs.io/en/stable/operator-manual/ingress/#option-1-ssl-passthrough
      - Set the `configs.params."server.insecure"` in the values file and terminate SSL at your ingress: https://argo-cd.readthedocs.io/en/stable/operator-manual/ingress/#option-2-multiple-ingress-objects-and-hosts


After reaching the UI the first time you can login with username: admin and the random password generated during the installation. You can find the password by running:

kubectl -n default get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

(You should delete the initial secret afterwards as suggested by the Getting Started Guide: https://argo-cd.readthedocs.io/en/stable/getting_started/#4-login-using-the-cli)
Awaiting argocd server & redis startup
deployment.apps/argo-cd-argocd-server condition met
deployment.apps/argo-cd-argocd-redis condition met
Templates directory: /tmp/tmp.OoVr5jbXGN
Applying manifest /tmp/tmp.OoVr5jbXGN/secret.yaml
secret/kubecontexts created
Applying manifest /tmp/tmp.joxRo9gLAL/job-dev.yaml
job.batch/argocd-add-cluster-dev created
Applying manifest /tmp/tmp.joxRo9gLAL/job-staging.yaml
job.batch/argocd-add-cluster-staging created
Applying manifest /tmp/tmp.joxRo9gLAL/job-prod.yaml
job.batch/argocd-add-cluster-prod created
job.batch/argocd-add-cluster-dev condition met
job.batch/argocd-add-cluster-staging condition met
job.batch/argocd-add-cluster-prod condition met

```

## Example rendered manifests

For an example of the manifests generated on the argo cluster, see [examples/bootstrap-manifests](./examples/bootstrap-manifests)

## Port-forwarding to argo

To port forward to argocd:
```
$ ./bootstrap.sh argo-port-forward
Switched to context "kind-argo".
Admin user: admin
Admin password: fKBWYUgY5sHS4KYB
Visit https://localhost:8080
Forwarding from 127.0.0.1:8080 -> 8080
Forwarding from [::1]:8080 -> 8080
```

## Confirming cluster addition

You should now be able to Navigate to [Settings / Clusters](https://localhost:8080/settings/clusters) & see all three clusters have been added:

![argocd clusters](images/clusters.png)

## Working with clusters
You can use `kubectx` (e.g. `kubectx kind-dev`) to switch between the following kubernetes contexts after running bootstrap:
* `kind-dev`
* `kind-prod`
* `kind-staging`
* `kind-argo`

## Cleaning up

Once you're done, you can remove all your kind clusters with:
```
$ ./bootstrap.sh delete-clusters
Deleting cluster "dev" ...
Deleted nodes: ["dev-control-plane"]
Deleting cluster "staging" ...
Deleted nodes: ["staging-control-plane"]
Deleting cluster "prod" ...
Deleted nodes: ["prod-control-plane"]
Deleting cluster "argo" ...
Deleted nodes: ["argo-control-plane"]
```

# Example ArgoCD Manifests

Now we have a working multi-cluster setup, we can explore manifests such as [ApplicationSet](https://argo-cd.readthedocs.io/en/latest/user-guide/application-set/), while using generators such as the [Cluster Generator](https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/Generators-Cluster/) to target deployments to specific clusters, with specific configuration. I have created some examples that work with the default cluster definitions in [examples/argocdmanifests](examples/argocdmanifests).