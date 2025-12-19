# local argocd multicluster with kind

This project sets up a set of clusters and a managing argo-cd cluster, to test gitops approaches using applicationset & clustergenerator. It uses [kind](https://kind.sigs.k8s.io/) & docker to achieve this.

## Design

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


# Requirements:

You will need the following tools to run this repository:
* `kubectl`
* `kubectx`
* [`yq`](https://mikefarah.gitbook.io/yq) (v4+)
* [`kind`](https://kind.sigs.k8s.io/)
* `docker`

## Usage

### Create Clusters

To create a new set of clusters:
```
$ ./bootstrap.sh bootstrap
Deleting cluster "dev" ...
Deleted nodes: ["dev-control-plane"]
Deleting cluster "staging" ...
Deleted nodes: ["staging-control-plane"]
Deleting cluster "prod" ...
Deleted nodes: ["prod-control-plane"]
Deleting cluster "argo" ...
Deleted nodes: ["argo-control-plane"]
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

Not sure what to do next? 😅  Check out https://kind.sigs.k8s.io/docs/user/quick-start/
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

Have a nice day! 👋
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

Thanks for using kind! 😊
NAME: argo-cd
LAST DEPLOYED: Fri Dec 19 18:12:35 2025
NAMESPACE: default
STATUS: deployed
REVISION: 1
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
Templates directory: /var/folders/wl/r9gvddvj5gs7vg94hm2jzdgh0000gp/T/tmp.9Y8oiKbVI8
Applying manifest /var/folders/wl/r9gvddvj5gs7vg94hm2jzdgh0000gp/T/tmp.9Y8oiKbVI8/secret.yaml
secret/kubecontexts created
Applying manifest /var/folders/wl/r9gvddvj5gs7vg94hm2jzdgh0000gp/T/tmp.dC3Bs3VkTH/job-dev.yaml
job.batch/argocd-add-cluster-dev created
Applying manifest /var/folders/wl/r9gvddvj5gs7vg94hm2jzdgh0000gp/T/tmp.dC3Bs3VkTH/job-staging.yaml
job.batch/argocd-add-cluster-staging created
Applying manifest /var/folders/wl/r9gvddvj5gs7vg94hm2jzdgh0000gp/T/tmp.dC3Bs3VkTH/job-prod.yaml
job.batch/argocd-add-cluster-prod created
job.batch/argocd-add-cluster-prod condition met
job.batch/argocd-add-cluster-prod condition met
job.batch/argocd-add-cluster-prod condition met
```

### Port-forwarding to argo

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

### Confirming cluster addition

You should now be able to Navigate to [Settings / Clusters](https://localhost:8080/settings/clusters) & see all three clusters have been added:

![argocd clusters](images/clusters.png)

### Working with clusters
You can use `kubectx` (e.g. `kubectx kind-dev`) to switch between the following kubernetes contexts after running bootstrap:
* `kind-dev`
* `kind-prod`
* `kind-staging`
* `kind-argo`

### Cleaning up

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
