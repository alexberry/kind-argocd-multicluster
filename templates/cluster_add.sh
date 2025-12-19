#! /usr/bin/env bash
argocd login argo-cd-argocd-server.default.svc.cluster.local --insecure --username admin --password $KIND_ARGOCD_ADMIN_PASS
argocd cluster add -y --kubeconfig /kubeconfig/$KIND_CLUSTER_NAME.yaml $KIND_CLUSTER_NAME --insecure --name $KIND_CLUSTER_NAME --upsert