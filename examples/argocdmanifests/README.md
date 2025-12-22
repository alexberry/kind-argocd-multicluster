# Example ArgoCD Manifests

Each folder here contains an example ArgoCD manifest that targets a multi-cluster/multitenant setup. They should be applied with kubectl against the argocd cluster, e.g.:
```
kubectl kind-argo
kubectx default
kubectl apply -f examples/argocdmanifests/applicationset/guestbook-applicationset.yaml
```

## ApplicationSet

In [applicationset/guestbook-applicationset.yaml](applicationset/guestbook-applicationset.yaml) I have defined one of argocd's example apps and targeted deployments to certain clusters using [ApplicationSet](https://argo-cd.readthedocs.io/en/latest/user-guide/application-set/) & [Cluster Generator](https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/Generators-Cluster/). This has the effect of deploying the application to clusters that match labels `env=platform, tier=[dev,staging]`.