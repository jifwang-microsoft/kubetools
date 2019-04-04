set -e

log_level()
{
    echo "#####################################################################################"
    case "$1" in
        -e) echo "$(date) [Error]  : " ${@:2}
        ;;
        -w) echo "$(date) [Warning]: " ${@:2}
        ;;
        -i) echo "$(date) [Info]   : " ${@:2}
        ;;
        *)  echo "$(date) [Verbose]: " ${@:2}
        ;;
    esac
    echo "#####################################################################################"
}

function printUsage
{
    echo "            -u, --giturl                         Github repo url for sql aris"
    echo "            -t, --test-assets                    Location of all test assets"
    exit 1
}

FILENAME=$0

while [[ "$#" -gt 0 ]]
do
    case $1 in
        -u|--giturl)
            GITURL="$2"
        ;;
        -t|--test-assets)
            TEST_DIRECTORY="$2"
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
if [ -z "$GITURL" ];
then
    log_level -e "GITURL not set"
    exit 1
fi

if [ -z "$TEST_DIRECTORY" ];
then
    log_level -e "TEST_DIRECTORY not set"
    exit 1
fi

log_level -i "Script Parameters"
echo "TEST_DIRECTORY: $TEST_DIRECTORY"


log_level -i "Installing curl"
sudo apt-get install -y curl

log_level -i "Installing Kubernetes"
sudo apt-get install -y apt-transport-https

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update -y

sudo apt-get install -y kubectl

log_level -i "Installing Ht"
curl -Sqsfk https://helsinki.redmond.corp.microsoft.com/ht-bootstrap.sh  | sudo -H bash

log_level -i "Holding walinuxagent"
sudo apt-mark hold walinuxagent

log_level -i "Preparing dev machine for deployment"
sudo -H ht machine prepare ubuntu-aris

log_level -i "Unholding walinuxagent"
sudo apt-mark unhold walinuxagent

log_level -i "Cloning the aris repo"
git clone $GITURL

log_level -i "Finding Kubeconfig"
KUBE_CONFIG_LOCATION=`sudo find  /var/lib/waagent/custom-script/download/0/aks-engine/_output/ -type f -iname "kubeconfig*"`

log_level -i "Copy kubeconfig to home"
sudo cp $KUBE_CONFIG_LOCATION $HOME/$TEST_DIRECTORY

log_level -i "Changing docker settings"
sudo chmod a+rw /var/run/docker.sock

log_level -i "Changing permissions of the config file"
sudo chmod a+r $HOME/$TEST_DIRECTORY/kubeconfig.local.json

log_level -i "Setting the Environment variables"
export KUBECONFIG="$HOME/$TEST_DIRECTORY/kubeconfig.local.json"
export DOCKER_IMAGE_TAG=latest

log_level -i "Changing directories into aris"
cd aris

log_level -i "Deploying SQL Aris"
make deploy-azure

log_level -i "SQL Aris Deployment Complete"

log_level -i "Running SQL Aris Tests"
make run-tests-azure

log_level -i "SQL Aris Tests Completed"

echo 0