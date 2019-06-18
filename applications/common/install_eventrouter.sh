#!/bin/bash
#Define Console Output Color
RED='\033[0;31m'    # For error
GREEN='\033[0;32m'  # For crucial check success
NC='\033[0m'        # No color, back to normal

echo -e " $(date) [Info] Installing eventrouter to collect the events for all kubernetes deployments"

# Install helm if it is not available
helmcmd="$(helm)"

if [[ -z $helmcmd ]]; then
    echo -e  "$(date) [Info] Helm not installed, installing helm"
    
    curl https://raw.githubusercontent.com/msazurestackworkloads/kubetools/eventrouter/applications/common/install_helm.sh | bash
else
    #Installing eventrouter to send input to stdout
    echo -e  "$(date) [Info] Checking if eventrouter is already deployed"
    
    #Checking if eventrouter is deployed
    INSTALL_STATUS=$(helm ls -d -r | grep 'DEPLOYED\(.*\)eventrouter' | grep -Eo '^[a-z,-]+')
    
    if [[ -z $INSTALL_STATUS ]]; then
        echo -e  "$(date) [Info] Installing eventrouter"
        
        if helm install stable/eventrouter --set sink=stdout;  then
            echo -e  "${GREEN}$(date) [Info] Eventrouter installing sucessfully"
        else
            echo -e  "${RED}$(date) [Err] Eventrouter failed to install"
        fi 
    else
        echo -e  "${GREEN}$(date) [Info] App (eventrouter) already installed"
    fi
fi