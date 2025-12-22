#! /usr/bin/env bash
set -e

createClusters() {
    for env in $envs; do
        # Config file required so that the port is routable from docker networks on linux
        kind create cluster --name $env --config configs/kind-config.yaml
    done
    kind create cluster --name argo
}

deleteClusters() {
    for env in $envs; do
        kind delete cluster --name $env || true
    done
    kind delete cluster --name argo || true
}

awaitArgo() {
    echo "Awaiting argocd server & redis startup"
    kubectx kind-argo > /dev/null 2>&1
    kubectl wait -n "$ns" deploy/argo-cd-argocd-server --for condition=available --timeout=5m
    kubectl wait -n "$ns" deploy/argo-cd-argocd-redis  --for condition=available --timeout=5m
}

helmInstallArgo() {
    helm repo add argo https://argoproj.github.io/argo-helm
    kubectx kind-argo > /dev/null 2>&1
    helm -n default install argo-cd argo/argo-cd
    awaitArgo
}

helmUninstallArgo() {
    kubectx kind-argo > /dev/null 2>&1
    helm uninstall argo-cd -n default
}

getArgoAdmin() {
    kubectx kind-argo > /dev/null 2>&1
    argo_pass=$(kubectl -n default get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    echo $argo_pass
}

argoPortForward() {
    kubectx kind-argo > /dev/null 2>&1
    argo_pass=$(getArgoAdmin)
    echo "Admin user: admin"
    echo "Admin password: $argo_pass"
    echo "Visit https://localhost:8080"
    kubectl port-forward service/argo-cd-argocd-server 8080:80 | grep -v "^Handling connection"
}

createSecret() {
    kubectx kind-argo > /dev/null 2>&1
    kubectl delete secret kubecontexts -n default > /dev/null 2>&1 || true
    templates_dir=$(mktemp -d)
    echo "Templates directory: ${templates_dir}"
    script_b64=$(cat templates/cluster_add.sh | base64)
    # Create the secret manifest from template and add the cluster_add script to it
    cat templates/secret.yaml | yq ".data.\"cluster_add.sh\" = \"${script_b64}\"" > $templates_dir/secret.yaml
    for env in $envs; do
        kubectx kind-$env > /dev/null 2>&1
        # Generates only the config for the current cluster
        raw_context=$(kubectl config view --minify --raw)
        # Find the port number this cluster runs with
        port=$(yq '.clusters[0].cluster.server' <<< "${raw_context}" | awk -F ':' '{print $3}')
        # remove the certificate-authority-data key, add insecure-skip-tls-verify (they are mutually exclusive), reconfigure host to a docker-friendly address
        modified_context_b64=$(yq "del .clusters[0].cluster.certificate-authority-data | .clusters[0].cluster.insecure-skip-tls-verify = true | .clusters[0].cluster.server = \"https://${DOCKER_HOST_INTERNAL_ADDRESS}:${port}\"|@yaml|@base64" <<< "${raw_context}")
        # add the context for this environment as a secret to the secret manifest
        yq -i ".data.\"kind-${env}.yaml\" = \"${modified_context_b64}\"" $templates_dir/secret.yaml
    done
    kubectx kind-argo > /dev/null 2>&1
    echo "Applying manifest $templates_dir/secret.yaml"
    kubectl apply -n default -f $templates_dir/secret.yaml
}

addClusters() {
    templates_dir=$(mktemp -d)
    kubectx kind-argo > /dev/null 2>&1
    for env in $envs; do
        job_name=argocd-add-cluster-$env
        kubectl delete job argocd-add-cluster-$env > /dev/null 2>&1 || true
        # Generate a new job manifest for this environment
        cat templates/job.yaml| yq ".spec.template.spec.containers[0].env[0].value = \"kind-${env}\"|.metadata.name = \"${job_name}\"" > $templates_dir/job-$env.yaml
        # Generate the labels arguments string for the cluster
        unset label_args
        for label in $(cat templates/cluster_definitions.yaml | yq ".clusters.${env}.labels|keys[]");do 
            value=$(cat templates/cluster_definitions.yaml | yq ".clusters.${env}.labels.$label")
            label_args="${label_args}--label ${label}=${value} "
        done
        echo -e "$env:\t$label_args"
        # Add label args to job manifest
        yq -i ".spec.template.spec.containers[0].env[1].value = \"${label_args}\"" $templates_dir/job-$env.yaml
        echo "Applying manifest $templates_dir/job-$env.yaml"
        kubectl apply -n default -f $templates_dir/job-$env.yaml
    done
    for env in $envs; do
        job_name=argocd-add-cluster-$env
        kubectl wait --for=condition=complete job/$job_name
    done
}

# Allow for overriding the Docker host internal address, as this does not exist on linux installs of docker
if [ -z "${DOCKER_HOST_INTERNAL_ADDRESS}" ]; then
    DOCKER_HOST_INTERNAL_ADDRESS="host.docker.internal"
fi

envs=$(cat templates/cluster_definitions.yaml | yq '.clusters|keys[]')
choices=( create-clusters delete-clusters install-argo uninstall-argo get-argo-admin argo-port-forward create-secret add-clusters await-argo bootstrap )

case $1 in

    # create-clusters
    "${choices[0]}")
        createClusters
        ;;

    # delete-clusters
    "${choices[1]}")
        deleteClusters
        ;;

    # install-argo
    "${choices[2]}")
        helmInstallArgo
        ;;

    # uninstall-argo
    "${choices[3]}")
        helmUninstallArgo
        ;;

    # get-argo-admin
    "${choices[4]}")
        getArgoAdmin
        ;;

    # argo-port-forward
    "${choices[5]}")
        argoPortForward
        ;;


    # create-secret
    "${choices[6]}")
        createSecret
        ;;

    # add-clusters
    "${choices[7]}")
        addClusters
        ;;

    # await-argo
    "${choices[8]}")
        awaitArgo
        ;;

    # bootstrap
    # will clean existing clusters and rebuild a new argo cluster, set of app clusters, and configure argo to connect to the app clusters
    "${choices[9]}")
        deleteClusters
        createClusters
        helmInstallArgo
        createSecret
        addClusters
        ;;

    *)
        echo "Please choose from args ${choices[@]}"
        exit 1
        ;;
esac