#! /bin/bash
set -e

log_level() 
{ 
    case "$1" in
       -e) echo "$(date) [Err]  : " ${@:2}
          ;;
       -w) echo "$(date) [Warn]: " ${@:2}
          ;;       
       -i) echo "$(date) [Info]   : " ${@:2}
          ;;
       *)  echo "$(date) [Debug]: " ${@:2}
          ;;
    esac
}


while [[ "$#" -gt 0 ]]
do
    case $1 in
        --tenant-id)
            TENANT_ID="$2"
            shift 2
        ;;
        --subscription-id)
            TENANT_SUBSCRIPTION_ID="$2"
            shift 2
        ;;
        --node-count)
            NODE_COUNT="$2"
            shift 2
        ;;
        --user)
            USER="$2"
            shift 2
        ;;
        *)

    esac
done

# Validate input

if [ -z "$TENANT_ID" ]
then
    log_level -e "--tenant-id is required"
    printUsage
fi

if [ -z "$TENANT_SUBSCRIPTION_ID" ]
then
    log_level -e "--subscription-id is required"
    printUsage
fi

if [ -z "$NODE_COUNT" ]
then
    log_level -e "--node-count is required"
    printUsage
fi

if [ -z "$USER" ]
then
    log_level -e "--user is required"
    printUsage
fi

# Basic details of the system
log_level -i "Running  script as : $(whoami)"

log_level -i "System information: $(sudo uname -a)"

K8S_PATH=/var/lib/waagent
sudo chown -R $USER $K8S_PATH
sudo chmod -R u=rwx $K8S_PATH

ROOT_PATH=$K8S_PATH/custom-script/download/0
cd $ROOT_PATH

log_level -i "Getting Resource group and region"

export CLUSTER_FOLDER=`ls -dt1 _output/* | head -n 1 | cut -d/ -f2 | cut -d. -f1`
export RESOURCE_GROUP=`ls -dt1 _output/* | head -n 1 | cut -d/ -f2 | cut -c-11`
export APIMODEL_FILE=$CLUSTER_FOLDER.json

if [ $RESOURCE_GROUP == "" ] ; then
    log_level -e "Resource group not found.Scale can not be performed"
    exit 1
fi

cd $ROOT_PATH/_output

CLIENT_ID=$(cat $ROOT_PATH/_output/$CLUSTER_FOLDER/apimodel.json | jq '.properties.servicePrincipalProfile.clientId'| tr -d '"')
FQDN_ENDPOINT_SUFFIX=$(cat $ROOT_PATH/_output/$CLUSTER_FOLDER/apimodel.json | jq '.properties.customCloudProfile.environment.resourceManagerVMDNSSuffix' | tr -d '"')
IDENTITY_SYSTEM=$(cat $ROOT_PATH/_output/$CLUSTER_FOLDER/apimodel.json | jq '.properties.customCloudProfile.identitySystem' | tr -d '"')
AUTH_METHOD=$(cat $ROOT_PATH/_output/$CLUSTER_FOLDER/apimodel.json | jq '.properties.customCloudProfile.authenticationMethod' | tr -d '"')
ENDPOINT_ACTIVE_DIRECTORY_RESOURCEID=$(cat $ROOT_PATH/_output/$CLUSTER_FOLDER/apimodel.json | jq '.properties.customCloudProfile.environment.serviceManagementEndpoint' | tr -d '"')
TENANT_ENDPOINT=$(cat $ROOT_PATH/_output/$CLUSTER_FOLDER/apimodel.json | jq '.properties.customCloudProfile.environment.resourceManagerEndpoint' | tr -d '"')
ENDPOINT_ACTIVE_DIRECTORY_ENDPOINT=$(cat $ROOT_PATH/_output/$CLUSTER_FOLDER/apimodel.json | jq '.properties.customCloudProfile.environment.activeDirectoryEndpoint' | tr -d '"')
ENDPOINT_GALLERY=$(cat $ROOT_PATH/_output/$CLUSTER_FOLDER/apimodel.json | jq '.properties.customCloudProfile.environment.galleryEndpoint' | tr -d '"')
ENDPOINT_GRAPH_ENDPOINT=$(cat $ROOT_PATH/_output/$CLUSTER_FOLDER/apimodel.json | jq '.properties.customCloudProfile.environment.graphEndpoint' | tr -d '"')
SUFFIXES_STORAGE_ENDPOINT=$(cat $ROOT_PATH/_output/$CLUSTER_FOLDER/apimodel.json | jq '.properties.customCloudProfile.environment.storageEndpointSuffix' | tr -d '"')
SUFFIXES_KEYVAULT_DNS=$(cat $ROOT_PATH/_output/$CLUSTER_FOLDER/apimodel.json | jq '.properties.customCloudProfile.environment.keyVaultDNSSuffix' | tr -d '"')
ENDPOINT_PORTAL=$(cat $ROOT_PATH/_output/$CLUSTER_FOLDER/apimodel.json | jq '.properties.customCloudProfile.portalURL' | tr -d '"')
REGION=$(cat $ROOT_PATH/_output/$CLUSTER_FOLDER/apimodel.json | jq '.location' | tr -d '"')
AZURE_ENV="AzureStackCloud"


if [ $CLIENT_ID == "" ] ; then
    log_level -e "Client ID not found.Scale can not be performed"
    exit 1
fi

if [ $REGION == "" ] ; then
    log_level -e "Region not found.Scale can not be performed"
    exit 1
fi

export CLIENT_ID=$CLIENT_ID
export CLIENT_SECRET=""
export NAME=$RESOURCE_GROUP
export REGION=$REGION
export TENANT_ID=$TENANT_ID
export SUBSCRIPTION_ID=$TENANT_SUBSCRIPTION_ID
export OUTPUT=$ROOT_PATH/_output/$CLUSTER_FOLDER/apimodel.json
export AGENT_POOL="linuxpool"

log_level -i "CLIENT_ID: $CLIENT_ID"
log_level -i "NAME:$RESOURCE_GROUP"
log_level -i "REGION:$REGION"
log_level -i "TENANT_ID:$TENANT_ID"
log_level -i "SUBSCRIPTION_ID:$TENANT_SUBSCRIPTION_ID"
log_level -i "IDENTITY_SYSTEM:$IDENTITY_SYSTEM"
log_level -i "NODE_COUNT:$NODE_COUNT"
log_level -i "RESOURCE_GROUP:$RESOURCE_GROUP"

cd $ROOT_PATH

CLIENT_SECRET=$(cat $ROOT_PATH/_output/$CLUSTER_FOLDER/apimodel.json | jq '.properties.servicePrincipalProfile.secret' | tr -d '"')
export CLIENT_SECRET=$CLIENT_SECRET

if [ $CLIENT_SECRET == "" ] ; then
   log_level -e "Client Secret not found.Scale can not be performed"
   exit 1
fi

./bin/aks-engine scale \
        --azure-env $AZURE_ENV \
        --subscription-id $SUBSCRIPTION_ID \
        --api-model $OUTPUT \
        --location $REGION \
        --resource-group $RESOURCE_GROUP  \
        --master-FQDN $FQDN_ENDPOINT_SUFFIX \
        --node-pool $AGENT_POOL \
        --new-node-count $NODE_COUNT \
        --auth-method $AUTH_METHOD \
        --client-id $CLIENT_ID \
        --client-secret $CLIENT_SECRET \
        --identity-system $IDENTITY_SYSTEM || exit 1    
    

log_level -i "Scaling of kubernetes cluster completed."
