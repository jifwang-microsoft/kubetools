#!/bin/bash
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

GITURL=`cat "$PARAMETER_FILE" | jq -r '.gitUrl'`
GITTAG=`cat "$PARAMETER_FILE" | jq -r '.gitTag'`

if [[ $GITURL == "https://"* ]]; then
    log_level -i "Giturl is valid"
else
    log_level -e "Giturl is not valid"
    exit 1
fi
#Cluster settings
CLUSTER_CONTROLLER_USERNAME=`cat "$PARAMETER_FILE" | jq -r '.clusterSettings.controllerUsername'`
CLUSTER_CONTROLLER_PASSWORD=`cat "$PARAMETER_FILE" | jq -r '.clusterSettings.controllerPassword'`
CLUSTER_KNOX_PASSWORD=`cat "$PARAMETER_FILE" | jq -r '.clusterSettings.knoxPassword'`
CLUSTER_MSSQL_SA_PASSWORD=`cat "$PARAMETER_FILE" | jq -r '.clusterSettings.mssqlPassword'`
CLUSTER_NAME=`cat "$PARAMETER_FILE" | jq -r '.clusterSettings.clusterName'`

#Docker settings
DOCKER_IMAGE_TAG=`cat "$PARAMETER_FILE" | jq -r '.dockerSettings.imageTag'`
DOCKER_REGISTRY=`cat "$PARAMETER_FILE" | jq -r '.dockerSettings.registry'`
DOCKER_REPOSITORY=`cat "$PARAMETER_FILE" | jq -r '.dockerSettings.repository'`
DOCKER_USERNAME=`cat "$PARAMETER_FILE" | jq -r '.dockerSettings.username'`
DOCKER_PASSWORD=`cat "$PARAMETER_FILE" | jq -r '.dockerSettings.password'`

#Mssqlctl version
MSSQLCTL_VERSION=`cat "$PARAMETER_FILE" | jq -r '.mssqlctlVersion'`

#Test settings
TEST_DIRECTORY=`cat "$PARAMETER_FILE" | jq -r '.dvmAssetsFolder'`



log_level -i "-----------------------------------------------------------------------------"
log_level -i "Script Parameters"
log_level -i "-----------------------------------------------------------------------------"
log_level -i "CLUSTER_NAME: $CLUSTER_NAME"
log_level -i "CLUSTER_CONTROLLER_USERNAME: $CLUSTER_CONTROLLER_USERNAME"
log_level -i "DOCKER_IMAGE_TAG: $DOCKER_IMAGE_TAG"
log_level -i "DOCKER_REGISTRY: $DOCKER_REGISTRY"
log_level -i "DOCKER_REPOSITORY: $DOCKER_REPOSITORY"
log_level -i "GITTAG: $GITTAG"
log_level -i "MSSQLCTL_VERSION: $MSSQLCTL_VERSION"
log_level -i "TEST_DIRECTORY: $TEST_DIRECTORY"
log_level -i "-----------------------------------------------------------------------------"


log_level -i "Installing curl"
sudo apt-get install -y curl

log_level -i "Installing Kubernetes"
sudo apt-get install -y apt-transport-https

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update -y

sudo apt-get install -y kubectl

log_level -i "Install python 3"
sudo apt-get update
sudo apt-get install -y python3
sudo apt-get install -y python3-pip

# Install Mssqlctl
log_level -i "Installing mssqlctl"
MSSQLCTL_URL="https://private-repo.microsoft.com/python/$MSSQLCTL_VERSION/mssqlctl/requirements.txt"
pip3 install -r  $MSSQLCTL_URL

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

# log_level -i "Changing docker settings"
# sudo chmod a+rw /var/run/docker.sock

log_level -i "Changing permissions of the config file"
sudo chmod a+r $HOME/$TEST_DIRECTORY/$KUBE_CONFIG_FILENAME

log_level -i "Setting Kubectl config variable as per required by k8s"
export KUBECONFIG="$HOME/$TEST_DIRECTORY/$KUBE_CONFIG_FILENAME"

log_level -i "Change working directory to test directory ($HOME/$TEST_DIRECTORY)"
cd $HOME/$TEST_DIRECTORY

# export environment variables
log_level -i "Exporting enviroment variables for mssqlctl deployment"
export CONTROLLER_USERNAME=$CLUSTER_CONTROLLER_USERNAME
export CONTROLLER_PASSWORD=$CLUSTER_CONTROLLER_PASSWORD
export DOCKER_REGISTRY=$DOCKER_REGISTRY
export DOCKER_REPOSITORY=$DOCKER_REPOSITORY
export DOCKER_USERNAME=$DOCKER_USERNAME
export DOCKER_PASSWORD=$DOCKER_PASSWORD
export MSSQL_SA_PASSWORD=$CLUSTER_MSSQL_SA_PASSWORD
export KNOX_PASSWORD=$CLUSTER_KNOX_PASSWORD
export DOCKER_IMAGE_TAG=$DOCKER_IMAGE_TAG

log_level -i "Cloning the aris repo"
if [ ! -d $HOME/$TEST_DIRECTORY/aris ]; then
    #Use git clone --branch $GITTAG $GITURL for checking out specific release tags
    git clone $GITURL
fi

log_level -i "Setting environment variable for python"
PATH="$PATH:$HOME/.local/bin/"

log_level -i "Creating Configuration for cluster Deployment"
mssqlctl cluster config init --src aks-dev-test.json --target azurestack.json

log_level -i "Setting Deployment Variables"
mssqlctl cluster config section set --config-file azurestack.json --json-values "metadata.name=$CLUSTER_NAME"

log_level -i "Executing Deploy"
mssqlctl cluster create --config-file azurestack.json --accept-eula yes


log_level -i "SQL Aris Deployment Complete"

echo 0