#!/bin/bash
#Define Console Output Color
RED='\033[0;31m'    # For error
GREEN='\033[0;32m'  # For crucial check success
NC='\033[0m'        # No color, back to normal

echo "Install Helm to check the health of Kubernete deployment..."

# Adding rbac - required for aks-engine from verison 0.40.0
kubectl create clusterrolebinding add-on-cluster-admin --clusterrole=cluster-admin --serviceaccount=kube-system:default

# Install helm if it is not available
helmcmd="$(helm)"

if [[ -z $helmcmd ]]; then
    echo "Helm is not available, install helm..."
    
    # Create a folder for installation
    echo "Preparing directory for Helm installation..."
    cd ~
    mkdir helm
    cd ./helm
    
    # Download and install helm
    echo "Download installation script..."
    
    HELM_VERSION="v3.1.0"
    #curl https://storage.googleapis.com/kubernetes-helm/helm-v${HELM_VERSION}-linux-amd64.tar.gz > helm-v${HELM_VERSION}-linux-amd64.tar.gz
    #tar -zxvf helm-v${HELM_VERSION}-linux-amd64.tar.gz
    #sudo mv linux-amd64/helm /usr/local/bin/helm
    #helm version
    #helm init || true
    
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh --version ${HELM_VERSION}
    
    # Check again, if still not available, test fail
    helmcmd="$(helm)"
    if [[ -z "$helmcmd" ]]; then
        echo  -e "${RED}Validation failed. Unable to install helm client. ${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Helm client has been installed.${NC}"
fi

echo -e "${GREEN}Helm client is ready.${NC}"

# Initial helm
echo "Initial helm..."
#helm init --upgrade

echo "Check Helm client availability..."
sleep 10s

# Check helm status
echo "Monitoring helm status..."
i=0
isHelmReady=0
while [ $i -lt 20 ]; do
    helmVersion="$(helm version)"
    
    if [[ -z "$helmVersion" ]]; then
        echo "Tracking helm status ..."
        sleep 10s
    else
        echo -e "${GREEN}Helm is ready.${NC}"
        isHelmReady=1
        break
    fi
    let i=i+1
done

if [ $isHelmReady -ne 1 ]; then
    echo  -e "${RED}Validation failed. Helm initial failed.${NC}"
    exit 1
fi

echo -e "${GREEN}Validation Pass! Helm has been initialed.${NC}"
exit 0

