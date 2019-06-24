#!/bin/bash
#Define Console Output Color
RED='\033[0;31m'    # For error
GREEN='\033[0;32m'  # For crucial check success
NC='\033[0m'        # No color, back to normal

echo -e " $(date) [Info] Installing fluent-bit to gather and aggregate data"

# Install helm if it is not available
helmcmd="$(helm)"

#helm install failing
if [[ -z $helmcmd ]]; then
    echo -e  "$(date) [Info] Helm not installed, installing helm"
    
    curl https://raw.githubusercontent.com/msazurestackworkloads/kubetools/enableDiagnostics/applications/common/install_helm.sh > install_helm.sh
    
    chmod 700 install_helm.sh
    dir=$(pwd)
    $dir/install_helm.sh
fi

# # Installing elasticsearch as a backend
# echo -e  "$(date) [Info] Checking if elasticsearch is already deployed"

# INSTALL_STATUS=$(helm ls -d -r | grep 'DEPLOYED\(.*\)elasticsearch' | grep -Eo '^[a-z,-]+')

# if [[ -z $INSTALL_STATUS ]]; then
#     echo -e  "$(date) [Info] Installing elasticsearch"

#     helm repo add elastic https://helm.elastic.co

#     #service type load balancer not working
#     helm install --name elasticsearch elastic/elasticsearch --version 7.1.1 --set service.type=LoadBalancer

#     PODS=$(kubectl get pods -n default -o custom-columns=NAME:.metadata.name --no-headers)

#     if [[ $PODS == *"elasticsearch"* ]]; then
#         echo -e  "$(date) [Info] Elasticserch installed sucessfully"
#     else
#         echo -e "$(date) [Info] Could not install elasticsearch."
#         exit 1
#     fi
# else
#     echo -e  "$(date) [Info] Elasticserch already installed"
# fi



# # Optional debug option of installing kibana

# echo -e  "$(date) [Info] Checking if kibana is already deployed"

# INSTALL_STATUS=$(helm ls -d -r | grep 'DEPLOYED\(.*\)kibana' | grep -Eo '^[a-z,-]+')

# if [[ -z $INSTALL_STATUS ]]; then
#     echo -e  "$(date) [Info] Installing kibana"

#     helm install --name kibana elastic/kibana --version 7.1.1 --set imageTag=7.1.1 --set service.type=LoadBalancer --set service.port=5601

#     PODS=$(kubectl get pods -n default -o custom-columns=NAME:.metadata.name --no-headers)

#     if [[ $PODS == *"kibana"* ]]; then
#         echo -e  "$(date) [Info] Kibana installed sucessfully"
#     else
#         echo -e "$(date) [Info] Could not install kibana."
#         exit 1
#     fi

# else
#     echo -e  "$(date) [Info] Kibana already installed"
# fi



# Configuring fluent-bit

# Installing fluent-bit

echo -e "${NC}$(date) [Info] Fluent-Bit complete"