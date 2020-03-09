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

wait_for_apt_locks() {
    i=0
    while fuser /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1; do
        if [ $i -gt 20 ]; then
            log_level -i 'Waiting for release of apt locks timedout with maximum retries'
            exit 1
        else
            log_level -i 'Waiting for release of apt locks'
            sleep 30
        fi
        let i=i+1
    done
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
wait_for_apt_locks
sudo apt-get install -y kubectl
wait_for_apt_locks

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

log_level -i "Copying over apimodel"
API_CONFIG_LOCATION=$(sudo find /var/lib/waagent/custom-script/download/0/_output -type f -iname 'apimodel*')
API_CONFIG_FILENAME=$(basename $API_CONFIG_LOCATION)
sudo cp $API_CONFIG_LOCATION $TEST_DIRECTORY

log_level -i "Changing apimodel permissions"
sudo chmod a+r $TEST_DIRECTORY/$API_CONFIG_FILENAME

API_CONFIG_LOCAL_LOCATION=$TEST_DIRECTORY/$API_CONFIG_FILENAME

log_level -i "Reading variables "
SUBSCRIPTIONS_API_VERSION="2016-06-01"
LOCATION=$(jq -r '.location' ${API_CONFIG_LOCAL_LOCATION})
SERVICE_MANAGEMENT_ENDPOINT=$(jq -r '.properties.customCloudProfile.environment.serviceManagementEndpoint' ${API_CONFIG_LOCAL_LOCATION})
ACTIVE_DIRECTORY_ENDPOINT=$(jq -r '.properties.customCloudProfile.environment.activeDirectoryEndpoint' ${API_CONFIG_LOCAL_LOCATION})
RESOURCE_MANAGER_ENDPOINT=$(jq -r '.properties.customCloudProfile.environment.resourceManagerEndpoint' ${API_CONFIG_LOCAL_LOCATION})
IDENTITY_SYSTEM=$(jq -r '.properties.customCloudProfile.identitySystem' ${API_CONFIG_LOCAL_LOCATION})
SERVICE_PRINCIPAL_CLIENT_ID=$(jq -r '.properties.servicePrincipalProfile.clientId' ${API_CONFIG_LOCAL_LOCATION})
SERVICE_PRINCIPAL_CLIENT_SECRET=$(jq -r '.properties.servicePrincipalProfile.secret' ${API_CONFIG_LOCAL_LOCATION})

log_level -i "Getting tenant id"
TENANT_STRING=$(cat /var/log/azure/deploy-script-dvm.log | grep 'TENANT_ID')
TENANT_ID=${TENANT_STRING##*:}
TENANT_ID=${TENANT_ID//[[:blank:]]/}

log_level -i "Getting resource group name"
RESOURCE_GROUP_STRING=$(cat /var/log/azure/deploy-script-dvm.log | grep 'RESOURCE_GROUP')
RESOURCE_GROUP=${RESOURCE_GROUP_STRING##*:}
RESOURCE_GROUP=${RESOURCE_GROUP//[[:blank:]]/}

if [[ $IDENTITY_SYSTEM == "adfs" ]]; then
    TOKEN_URL="${ACTIVE_DIRECTORY_ENDPOINT}adfs/oauth2/token"
else
    TOKEN_URL="${ACTIVE_DIRECTORY_ENDPOINT}${TENANT_ID}/oauth2/token"
fi

log_level -i "SERVICE_MANAGEMENT_ENDPOINT: $SERVICE_MANAGEMENT_ENDPOINT"
log_level -i "TOKEN_URL: $TOKEN_URL"
log_level -i "ACTIVE_DIRECTORY_ENDPOINT: $ACTIVE_DIRECTORY_ENDPOINT"
log_level -i "IDENTITY_SYSTEM: $IDENTITY_SYSTEM"
log_level -i "RESOURCE_GROUP: $RESOURCE_GROUP"
log_level -i "LOCATION: $LOCATION"
log_level -i "TENANT_ID: $TENANT_ID"

TOKEN=$(curl -s --retry 5 --retry-delay 10 --max-time 60 -f -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials" \
    -d "client_id=$SERVICE_PRINCIPAL_CLIENT_ID" \
    --data-urlencode "client_secret=$SERVICE_PRINCIPAL_CLIENT_SECRET" \
    --data-urlencode "resource=$SERVICE_MANAGEMENT_ENDPOINT" \
${TOKEN_URL} | jq '.access_token' | xargs)

log_level -i "Getting Subscription ID"

SUBSCRIPTIONS=$(curl -s --retry 5 --retry-delay 10 --max-time 60 -f -X GET \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
"${RESOURCE_MANAGER_ENDPOINT}subscriptions?api-version=$SUBSCRIPTIONS_API_VERSION")

SUBSCRIPTION_ID=$(echo $SUBSCRIPTIONS | jq -r '.value[0].subscriptionId')

log_level -i "SUBSCRIPTION_ID:$SUBSCRIPTION_ID"

log_level -i "Getting all network security group names"
NETWORK_API_VERSION="2017-10-01"

PARAMETERS=$( jq -n \
    --arg location "$LOCATION" \
    '{"location":$location,"properties": {"securityRules": [{"name": "Allow5000","properties": {"protocol": "*","sourceAddressPrefix": "*","destinationAddressPrefix": "*","access": "Allow","destinationPortRange": "5000","sourcePortRange": "*","priority": 210,"direction": "Inbound"}},{"name": "ssh","properties": {"protocol": "TCP","sourceAddressPrefix": "*","destinationAddressPrefix": "*","access": "Allow","destinationPortRange": "22","sourcePortRange": "*","priority": 200,"direction": "Inbound"}}]}}'
)

log_level -i "PARAMETERS:$PARAMETERS"

NETWORK_SECURITY_GROUPS=$(curl -s --retry 5 --retry-delay 10 --max-time 60 -f -X GET \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
"${RESOURCE_MANAGER_ENDPOINT}subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/networkSecurityGroups?api-version=$NETWORK_API_VERSION")

VDM_SECURITY_GROUP=$(echo $NETWORK_SECURITY_GROUPS | jq -c '.value | map(select ( .name | contains ("vmd")))')
VDM_SECURITY_GROUP_NAME=$(echo $VDM_SECURITY_GROUP | jq -r '.[0].name')

log_level -i "VDM_SECURITY_GROUP_NAME:$VDM_SECURITY_GROUP_NAME"

RESPONSE=$(curl -s --retry 5 --retry-delay 10 --max-time 60 -f -X PUT \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PARAMETERS" \
"${RESOURCE_MANAGER_ENDPOINT}subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/networkSecurityGroups/$VDM_SECURITY_GROUP_NAME?api-version=$NETWORK_API_VERSION")

log_level -i "Hetrogeneous Application Deployment Complete"

echo 0
