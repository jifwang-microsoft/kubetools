#!/bin/bash

#Clean The sql aris cluster
#Delete PVCS where posible
#Return Output
set -e

log_level()
{
    case "$1" in
        -e) echo "$(date) [Err]  " ${@:2}
        ;;
        -w) echo "$(date) [Warn] " ${@:2}
        ;;
        -i) echo "$(date) [Info] " ${@:2}
        ;;
        *)  echo "$(date) [Debug] " ${@:2}
        ;;
    esac
}

function printUsage
{
    echo "            -c, --configFile                            Parameter file for any extra parameters for the deployment"
    exit 1
}

FILENAME=$0

while [[ "$#" -gt 0 ]]
do
    case $1 in
        -c|--configfile)
            PARAMETER_FILE="$2"
        ;;
        *)
            echo ""
            echo "Incorrect parameter $1"
            echo ""
            printUsage
        ;;
    esac
    
    if [ "$#" -ge 2 ]
    then
        shift 2
    else
        shift
    fi
done

#Checking Variables
if [ ! -f $PARAMETER_FILE ] || [ -z "$PARAMETER_FILE" ]; then
    log_level -e "Parameter file does not exist"
    exit 1
fi

#Cluster settings
CLUSTER_CONTROLLER_USERNAME=`cat "$PARAMETER_FILE" | jq -r '.clusterSettings.controllerUsername'`
CLUSTER_CONTROLLER_PASSWORD=`cat "$PARAMETER_FILE" | jq -r '.clusterSettings.controllerPassword'`
CLUSTER_KNOX_PASSWORD=`cat "$PARAMETER_FILE" | jq -r '.clusterSettings.knoxPassword'`
CLUSTER_MSSQL_SA_PASSWORD=`cat "$PARAMETER_FILE" | jq -r '.clusterSettings.mssqlPassword'`
CLUSTER_NAME=`cat "$PARAMETER_FILE" | jq -r '.clusterSettings.clusterName'`

TEST_DIRECTORY=`cat "$PARAMETER_FILE" | jq -r '.dvmAssetsFolder'`

log_level -i "-----------------------------------------------------------------------------"
log_level -i "Script Parameters"
log_level -i "-----------------------------------------------------------------------------"
log_level -i "CLUSTER_NAME: $CLUSTER_NAME"
log_level -i "CLUSTER_CONTROLLER_USERNAME: $CLUSTER_CONTROLLER_USERNAME"
log_level -i "TEST_DIRECTORY: $TEST_DIRECTORY"
log_level -i "-----------------------------------------------------------------------------"

log_level -i "Finding Kubeconfig"
#There is a dependancy on the _output folder to use to connect to the cluster
KUBE_CONFIG_LOCATION=`sudo find  /var/lib/waagent/custom-script/download/0/ -type f -iname "kubeconfig*"`

log_level -i "Finding Kubeconfig file from path ($KUBE_CONFIG_LOCATION)"
KUBE_CONFIG_FILENAME=$(basename $KUBE_CONFIG_LOCATION)

log_level -i "Copy kubeconfig($KUBE_CONFIG_LOCATION) to home directory"
sudo cp $KUBE_CONFIG_LOCATION $HOME/$TEST_DIRECTORY

log_level -i "Checking if file ($KUBE_CONFIG_FILENAME) exists"
if [[ ! -f $HOME/$TEST_DIRECTORY/$KUBE_CONFIG_FILENAME ]]; then
    log_level -e "File($KUBE_CONFIG_FILENAME) does not exist at $HOME/$TEST_DIRECTORY"
    exit 1
else
    log_level -i "File($KUBE_CONFIG_FILENAME) exist at $HOME/$TEST_DIRECTORY"
fi

log_level -i "Changing permissions of the config file"
sudo chmod a+r $HOME/$TEST_DIRECTORY/$KUBE_CONFIG_FILENAME

log_level -i "Setting Kubectl config variable as per required by k8s"
export KUBECONFIG="$HOME/$TEST_DIRECTORY/$KUBE_CONFIG_FILENAME"

# export environment variables
log_level -i "Exporting enviroment variables for mssqlctl testing"
export CONTROLLER_USERNAME=$CLUSTER_CONTROLLER_USERNAME
export CONTROLLER_PASSWORD=$CLUSTER_CONTROLLER_PASSWORD
export MSSQL_SA_PASSWORD=$CLUSTER_MSSQL_SA_PASSWORD
export KNOX_PASSWORD=$CLUSTER_KNOX_PASSWORD

log_level -i "Setting environment variable for python"
PATH="$PATH:$HOME/.local/bin/"

log_level -i "Deleting Namespace"
mssqlctl cluster delete --name $CLUSTER_NAME -f

echo 0