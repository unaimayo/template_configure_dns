#!/bin/bash
##------------------------------------------------------------------------------
## Licensed Materials - Property of IBM
## 5737-E67
## (C) Copyright IBM Corporation 2020 All Rights Reserved.
## US Government Users Restricted Rights - Use, duplication or
## disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
##------------------------------------------------------------------------------
## This script is used to configure DNS in the GKE cluster to access MCM hub
##
## Details pertaining to the actions to be taken and target cluster to be
## managed should be provided via the following command-line parameters or <environment variable>:
## Required:
##   -wd|--workdir <WORK_DIR>                       Directory where temporary work files will be created during the action
##   -cn|--clustername <CLUSTER_NAME>               Name of the target cluster
##   -ce|--clusterendpoint <CLUSTER_ENDPOINT>       URL for accessing the target cluster
##   -cu|--clusteruser <CLUSTER_USER>               Username for accessing the target cluster
##   -ck|--clustertoken <CLUSTER_TOKEN>             Authorization token for accessing the target cluster
##   -cc|--clustercreds <CLUSTER_CREDENTIALS>       JSON-formated file containing cluster endpoint, user and token information;
##------------------------------------------------------------------------------

set -e

## Perform cleanup tasks prior to exit
function exitOnError() {
    errMessage=$1
    echo "${WARN_ON}${errMessage}; Exiting...${WARN_OFF}"
    exit 1
}

## Download and install the kubectl and helm utilities
function installKubectlAndHelmLocally() {
    ## This script should be running with a unique HOME directory; Initialize '.kube' directory
    rm -rf   ${HOME}/.kube
    mkdir -p ${HOME}/.kube

    ## Install kubectl, if necessary
    if [ ! -x ${WORK_DIR}/bin/kubectl ]; then
        kversion=$(wget -qO- https://storage.googleapis.com/kubernetes-release/release/stable.txt)

        echo "Installing kubectl (version ${kversion}) into ${WORK_DIR}..."
        wget --quiet https://storage.googleapis.com/kubernetes-release/release/${kversion}/bin/linux/amd64/kubectl -P ${WORK_DIR}/bin
        chmod +x ${WORK_DIR}/bin/kubectl
    else
        echo "kubectl has already been installed; No action taken"
    fi

    ## Install helm, if necessary
    if [ ! -x ${WORK_DIR}/bin/helm ]; then
        echo "Installing helm into ${WORK_DIR}..."
        wget --quiet https://mirror.openshift.com/pub/openshift-v4/clients/helm/latest/helm-linux-amd64 -P ${WORK_DIR}
        mv ${WORK_DIR}/helm-linux-amd64 ${WORK_DIR}/bin/helm
        chmod +x ${WORK_DIR}/bin/helm
    else
        echo "helm has already been installed; No action taken"
    fi
}

## Parse the cluster credentials from specified file
function parseTargetClusterCredentials() {
    echo "Parsing cluster credentials from ${CLUSTER_CREDENTIALS}..."
    if [ -f "${CLUSTER_CREDENTIALS}" ]; then
         ## Credentials provided via JSON file; Parse endpoint, user and token from file for later verification
         CLUSTER_ENDPOINT=$(cat ${CLUSTER_CREDENTIALS} | jq -r '.endpoint')
         CLUSTER_USER=$(cat ${CLUSTER_CREDENTIALS}     | jq -r '.user')
         CLUSTER_TOKEN=$(cat ${CLUSTER_CREDENTIALS}    | jq -r '.token')
    fi
}

## Verify the information needed to access the target cluster
function verifyTargetClusterInformation() {
    ## Verify details for accessing to the target cluster
    if [ -z "$(echo "${CLUSTER_NAME}" | tr -d '[:space:]')" ]; then
        exitOnError "Cluster name has not been specified"
    fi
    if [ -z "$(echo "${CLUSTER_ENDPOINT}" | tr -d '[:space:]')" ]; then
        exitOnError "Cluster server URL has not been specified"
    fi
    if [ -z "$(echo "${CLUSTER_USER}" | tr -d '[:space:]')" ]; then
        exitOnError "Cluster user has not been specified"
    fi
    if [ -z "$(echo "${CLUSTER_TOKEN}" | tr -d '[:space:]')" ]; then
        exitOnError "Authorization token has not been specified"
    fi

    ## Configure kubectl
    installKubectlAndHelmLocally
    ${WORK_DIR}/bin/kubectl config set-cluster     ${CLUSTER_NAME} --insecure-skip-tls-verify=true --server=${CLUSTER_ENDPOINT}
    ${WORK_DIR}/bin/kubectl config set-credentials ${CLUSTER_USER} --token=${CLUSTER_TOKEN}
    ${WORK_DIR}/bin/kubectl config set-context     ${CLUSTER_NAME} --user=${CLUSTER_USER} --namespace=kube-system --cluster=${CLUSTER_NAME}
    ${WORK_DIR}/bin/kubectl config use-context     ${CLUSTER_NAME}

    ## Generate KUBECONFIG file to be used when accessing the target cluster
    ${WORK_DIR}/bin/kubectl config view --minify=true --flatten=true > ${KUBECONFIG_FILE}

    verifyTargetClusterAccess
}

## Verify the target cluster can be accessed
function verifyTargetClusterAccess() {
    set +e
    echo "Verifying access to target cluster..."
    export KUBECONFIG=${KUBECONFIG_FILE}
    ${WORK_DIR}/bin/kubectl get nodes
    if [ $? -ne 0 ]; then
        exitOnError "Unable to access the target cluster"
    fi
    unset KUBECONFIG
    set -e
}

##------------------------------------------------------------------------------------------------
##************************************************************************************************
##------------------------------------------------------------------------------------------------

## Prepare work directory
mkdir -p ${WORK_DIR}/bin
export PATH=${WORK_DIR}/bin:${PATH}

## Set default variable values
KUBECONFIG_FILE=${WORK_DIR}/kubeconfig.yaml
WARN_ON='\033[0;31m'
WARN_OFF='\033[0m'

## Prepare work directory and install common utilities
mkdir -p ${WORK_DIR}/bin
export PATH=${WORK_DIR}/bin:${PATH}

## Check provided target cluster information
parseTargetClusterCredentials
verifyTargetClusterInformation
if [ -z "$(echo "${CLUSTER_NAME}" | tr -d '[:space:]')" ]; then
    exitOnError "Target cluster name was not provided"
fi

echo "Configuring dns for cluster ${CLUSTER_NAME}..."
export KUBECONFIG=${KUBECONFIG_FILE}
# create namespace
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: coredns
EOF
# install coredns
helm repo add stable https://kubernetes-charts.storage.googleapis.com
helm install coredns --namespace=coredns stable/coredns
# update coredns configuration
kubectl get -o yaml configmap coredns-coredns -n coredns > ${WORK_DIR}/cm-coredns.yaml
sed -i "s/prometheus/hosts {\n          ${MCM_HUB_IP} cp-proxy.apps.cloudgarden.telefonica.com cp-console.apps.cloudgarden.telefonica.com api.cloudgarden.telefonica.com\n          fallthrough\n        }\n        prometheus/" ${WORK_DIR}/cm-coredns.yaml
kubectl apply -f ${WORK_DIR}/cm-coredns.yaml
# update kubedns configuration
clusterIP=`kubectl -n coredns get service coredns-coredns -o jsonpath='{.spec.clusterIP}'`
kubectl -n kube-system get cm kube-dns -o yaml > ${WORK_DIR}/cm-kube.yaml
sed -i "s/metadata/data:\n  stubDomains: |\n    {\"cloudgarden.telefonica.com\": [\"$clusterIP\"]}\nmetadata/" ${WORK_DIR}/cm-kube.yaml
kubectl apply -f ${WORK_DIR}/cm-kube.yaml
unset KUBECONFIG
echo "${CLUSTER_NAME} dns configured!"