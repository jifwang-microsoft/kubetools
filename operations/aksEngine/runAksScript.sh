#!/bin/bash

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
function printUsage
{
    echo ""
    echo "Usage:"
    echo "  $0 -i id_rsa -d 192.168.102.34 -u azureuser --file aks_file --tenant-Id tenant-id --subscription-id subscription-id --disable-host-key-checking"
    echo ""
    echo "Options:"
    echo "  -u, --user                      User name associated to the identifity-file"
    echo "  -i, --identity-file             RSA private key tied to the public key used to create the Kubernetes cluster (usually named 'id_rsa')"
    echo "  -d, --vmd-host                  The DVM's public IP or FQDN (host name starts with 'vmd-')"
    echo "  -t, --tenant-id                 The Tenant ID used by aks engine"
    echo "  -s, --subscription-id           The Subscription ID used by aks engine"
    echo "  -f, --file                      Aks Engine Scale or Upgrade script to run on dvm"
    echo "  -p, --parameter                 For scale node_count should be passed and for upgrade version should be passed"
    echo "  -h, --help                      Print the command usage"
    exit 1
}

function download_scripts
{
    ARTIFACTSURL=$1
    script=$2
    
    echo "[$(date +%Y%m%d%H%M%S)][INFO] Pulling aks script from this repo: $ARTIFACTSURL"
        
    curl -fs $ARTIFACTSURL -o $SCRIPTSFOLDER/$script
        
    if [ ! -f $SCRIPTSFOLDER/$script ]; then
        echo "[$(date +%Y%m%d%H%M%S)][ERROR] Required script not available. URL: $ARTIFACTSURL"
        exit 1
    fi
    
}

if [ "$#" -eq 0 ]
then
    printUsage
fi

# Handle named parameters
while [[ "$#" -gt 0 ]]
do
    case $1 in
        -i|--identity-file)
            IDENTITYFILE="$2"
            shift 2
        ;;
        -m|--master-host)
            MASTER_HOST="$2"
            shift 2
        ;;
        -d|--vmd-host)
            DVM_HOST="$2"
            shift 2
        ;;
        -u|--user)
            USER="$2"
            shift 2
        ;;
        -t|--tenant-id)
            TENANT_ID="$2"
            shift 2
        ;;
        -s|--subscription-id)
            SUBSCRIPTION_ID="$2"
            shift 2
        ;;
        -f|--file)
            FILE="$2"
            shift 2
        ;;
        -p|--parameter)
            PARAMETER="$2"
            shift 2
        ;;
        -o|--operation)
            OPERATION="$2"
            shift 2
        ;;
        -h|--help)
            printUsage
        ;;
        *)
            log_level -e  "Incorrect option $1"
            printUsage
        ;;
    esac
done

# Validate input
if [ -z "$USER" ]
then
    log_level -e "--user is required"
    printUsage
fi

if [ -z "$IDENTITYFILE" ]
then
    log_level -e "--identity-file is required"
    printUsage
fi

if [ -z "$DVM_HOST" ]
then    
    log_level -e "--vmd-host should be provided"
    printUsage
fi

if [ -z "$PARAMETER" ]
then  
    log_level -e "--parameter should be provided"
    printusuage
fi

if [ -z "$OPERATION" ]
then
    log_level -e "--operation should be provided"
    printusuage
fi

if [ ! -f $IDENTITYFILE ]
then
    log_level -e "identity-file not found at $IDENTITYFILE"
    printUsage
    exit 1
else
    cat $IDENTITYFILE | grep -q "BEGIN \(RSA\|OPENSSH\) PRIVATE KEY" \
    || { echo "The identity file $IDENTITYFILE is not a RSA Private Key file."; echo "A RSA private key file starts with '-----BEGIN [RSA|OPENSSH] PRIVATE KEY-----''"; exit 1; }
fi

# Print user input
log_level -i ""
log_level -i "user:             $USER"
log_level -i "identity-file:    $IDENTITYFILE"
log_level -i "vmd-host:         $DVM_HOST"
log_level -i "tenant-id:        $TENANT_ID"
log_level -i "subscription-id:  $SUBSCRIPTION_ID"
log_level -i "file:             $FILE"
log_level -i "parameter:        $PARAMETER"
log_level -i "operation:        $OPERATION"
log_level -i ""

NOW=`date +%Y%m%d%H%M%S`
SCRIPTSFOLDER="./AksEngineScripts/scripts"

if [ ! -d $SCRIPTSFOLDER ]; then
    mkdir -p $SCRIPTSFOLDER
fi
log_level -i "script folder: $SCRIPTSFOLDER"

AZURE_USER=$USER

IDENTITY_FILE_BACKUP_PATH="/home/$AZURE_USER/IDENTITY_FILEBACKUP"

echo "Backing up identity files at ($IDENTITY_FILE_BACKUP_PATH)"
ssh -t -i $IDENTITYFILE $USER@$DVM_HOST "if [ -f /home/$AZURE_USER/.ssh/id_rsa ]; then mkdir -p $IDENTITY_FILE_BACKUP_PATH;  sudo mv /home/$AZURE_USER/.ssh/id_rsa $IDENTITY_FILE_BACKUP_PATH; fi;"

echo -i "Copying over new identity file"
scp -i $IDENTITYFILE $IDENTITYFILE $USER@$DVM_HOST:/home/$AZURE_USER/.ssh/id_rsa

ROOT_PATH=/home/$AZURE_USER
FILENAME=$(basename $FILE)
download_scripts $FILE $FILENAME

scp -q -i $IDENTITYFILE $SCRIPTSFOLDER/*.sh $USER@$DVM_HOST:$ROOT_PATH

if [ $OPERATION == "scale" ] ; then
    ssh -t -i $IDENTITYFILE $USER@$DVM_HOST "./$FILENAME --tenant-id $TENANT_ID --subscription-id $SUBSCRIPTION_ID --node-count $PARAMETER --user $AZURE_USER"
fi

if [ $OPERATION == "upgrade" ] ; then
    ssh -t -i $IDENTITYFILE $USER@$DVM_HOST "./$FILENAME --tenant-id $TENANT_ID --subscription-id $SUBSCRIPTION_ID --upgrade-version $PARAMETER --user $AZURE_USER ;"
fi
