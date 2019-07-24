#!/bin/bash
set -e

log_level() {
    case "$1" in
    -e)
        echo "$(date) [Err]  " ${@:2}
        ;;
    -w)
        echo "$(date) [Warn] " ${@:2}
        ;;
    -i)
        echo "$(date) [Info] " ${@:2}
        ;;
    *)
        echo "$(date) [Debug] " ${@:2}
        ;;
    esac
}

FILENAME=$0

while [[ "$#" -gt 0 ]]; do
    case $1 in
    -m | --master)
        HOST="$2"
        ;;
    -t | --test-directory)
        TEST_DIRECTORY="$2"
        ;;
    *)
        log_level -i ""
        log_level -i "Incorrect parameter $1"
        log_level -i ""
        printUsage
        ;;
    esac

    if [ "$#" -ge 2 ]; then
        shift 2
    else
        shift
    fi
done
GIT_BRANCH="${GIT_BRANCH:-master}"

log_level -i "Getting Kubectl signing key"
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

log_level -i "Updating apt repository for kubernetes"
echo 'deb https://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee -a /etc/apt/sources.list.d/kubernetes.list

log_level -i "Install Kubectl"
sudo apt-get update -y
sudo apt-get install -y kubectl

log_level -i "Finding KUBECONFIG_LOCATION"
KUBE_CONFIG_LOCATION=$(sudo find /var/lib/waagent/custom-script/download/0/_output -type f -iname 'kubeconfig*')
log_level -i "KUBE_CONFIG_LOCATION($KUBE_CONFIG_LOCATION)"

KUBE_CONFIG_FILENAME=$(basename $KUBE_CONFIG_LOCATION)
log_level -i "KUBE_CONFIG_FILENAME($KUBE_CONFIG_FILENAME)"

log_level -i "Changing permissions of the config file"

log_level -i "Copy kubeconfig($KUBE_CONFIG_LOCATION) to home directory"
sudo cp $KUBE_CONFIG_LOCATION $TEST_DIRECTORY
sudo chmod a+r $TEST_DIRECTORY/$KUBE_CONFIG_FILENAME

log_level -i "Setting Configuration to ($TEST_DIRECTORY/$KUBE_CONFIG_FILENAME)"
export KUBECONFIG="$TEST_DIRECTORY/$KUBE_CONFIG_FILENAME"

log_level -i "Get Signing Key"
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -

log_level -i "Install apt-transport-https"
echo 'deb https://artifacts.elastic.co/packages/7.x/apt stable main' | sudo tee -a /etc/apt/sources.list.d/elastic-7.x.list

log_level -i "Install elasticsearch"
sudo apt-get update
sudo apt-get --assume-yes install elasticsearch

log_level -i "Running Elasticsearch as a Daemon"
sudo systemctl start elasticsearch.service

log_level -i "Install Nginx to route elasticsearch traffic"
sudo apt-get update
sudo apt-get --assume-yes install nginx

log_level -i "Downloading nginx configuration file"
CONFIG_FILENAME="nginx.conf"
curl -o $CONFIG_FILENAME https://raw.githubusercontent.com/msazurestackworkloads/kubetools/$GIT_BRANCH/applications/hetrogeneous-app/elastic-client/nginx.conf

log_level -i "Install Nginx to route elasticsearch traffic"
sudo fuser -k 5000/tcp
sudo nginx -p $TEST_DIRECTORY -c $CONFIG_FILENAME

log_level -i "Downloading template"
TEMPLATE_NAME="elastic-client.yaml.tmpl"
curl -o $TEMPLATE_NAME https://raw.githubusercontent.com/msazurestackworkloads/kubetools/$GIT_BRANCH/applications/hetrogeneous-app/elastic-client/elastic-client.yaml.tmpl

log_level -i "Generating Deployment Template"
export ELASTIC_PORT=5000
export ELASTIC_HOST=$HOST

envsubst < $TEMPLATE_NAME > elastic-client.yaml

log_level -i "Deploy Template"
kubectl apply -f elastic-client.yaml

log_level -i "Hetrogeneous Application Deployment Complete"

echo 0