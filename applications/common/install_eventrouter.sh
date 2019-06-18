#!/bin/bash
#Define Console Output Color
RED='\033[0;31m'    # For error
GREEN='\033[0;32m'  # For crucial check success
NC='\033[0m'        # No color, back to normal

echo -e " $(date) [Info] Install Eventrouter to collect the events for all kubernetes deployments"

# Install helm if it is not available
helmcmd="$(helm)"

if [[ -z $helmcmd ]]; then
    curl https://raw.githubusercontent.com/msazurestackworkloads/kubetools/eventrouter/applications/common/install_helm.sh | bash
else
    #Installing eventrouter to send input to stdout
    echo -e  "$(date) [Info] Install eventrouter"
    helm install stable/eventrouter --set sink=stdout

    #Checking if eventrouter is deployed
    INSTALL_STATUS=$(helm ls -d -r | grep 'DEPLOYED\(.*\)eventrouter' | grep -Eo '^[a-z,-]+')
    
    if [[ -z $INSTALL_STATUS ]]; then
        echo -e  " ${RED}$(date) [Err] App(eventrouter) deployment failed using Helm."
        return 1
    else
        echo -e  " ${GREEN}$(date) [Info] App(eventrouter) deployment successfull."
    fi
fi