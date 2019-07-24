#!/bin/bash

FILENAME=$0

SCRIPT_LOCATION=$(dirname $FILENAME)
COMMON_SCRIPT_FILENAME="common.sh"
GIT_REPROSITORY="${GIT_REPROSITORY:-msazurestackworkloads/kubetools}"
GIT_BRANCH="${GIT_BRANCH:-master}"

# Download common script file.
curl -o $SCRIPT_directory/$COMMON_SCRIPT_FILENAME \
https://raw.githubusercontent.com/$GIT_REPROSITORY/$GIT_BRANCH/applications/common/$COMMON_SCRIPT_FILENAME
if [ ! -f $SCRIPT_DIRECTORY/$COMMON_SCRIPT_FILENAME ]; then
    echo "File($COMMON_SCRIPT_FILENAME) failed to download."
    exit 1
fi

source $SCRIPT_DIRECTORY/$COMMON_SCRIPT_FILENAME
###########################################################################################################
# The function will read parameters and populate below global variables.
# IDENTITY_FILE, MASTER_IP, OUTPUT_SUMMARYFILE, USER_NAME
parse_commandline_arguments $@


if [ -z "$OUTPUT_SUMMARYFILE" ]; then
    log_level -e "Summary file not set"
    exit 1
fi

OUTPUT_DIRECTORY=$(dirname $OUTPUT_SUMMARYFILE)
LOG_FILE_NAME=$OUTPUT_DIRECTORY/cleanup.log
TEST_DIRECTORY="hetro_app_assets"
touch $LOG_FILE_NAME
IDENTITY_FILE_BACKUP_PATH="/home/$USER_NAME/IDENTITY_FILEBACKUP"


{
    if [[ -z $IDENTITY_FILE ]]; then
        log_level -e "IDENTITY_FILE not set"
        exit 1
    fi
    
    if [[ -z $MASTER_IP ]]; then
        log_level -e "MASTER_IP not set"
        exit 1
    fi
    
    if [[ -z $USER_NAME ]]; then
        log_level -e "USER_NAME not set"
        exit 1
    fi
    
    log_level -i "-----------------------------------------------------------------------------"
    log_level -i "Script Parameters"
    log_level -i "-----------------------------------------------------------------------------"
    log_level -i "GIT_REPROSITORY: $GIT_REPROSITORY"
    log_level -i "GIT_BRANCH: $GIT_BRANCH"
    log_level -i "IDENTITY_FILE: $IDENTITY_FILE"
    log_level -i "IDENTITY_FILE_BACKUP_PATH: $IDENTITY_FILE_BACKUP_PATH"
    log_level -i "LOG_FILE_NAME: $LOG_FILE_NAME"
    log_level -i "MASTER_IP: $MASTER_IP"
    log_level -i "OUTPUT_DIRECTORY: $OUTPUT_DIRECTORY"
    log_level -i "TEST_DIRECTORY: $TEST_DIRECTORY"
    log_level -i "USER: $USER_NAME"
    log_level -i "-----------------------------------------------------------------------------"
    
    log_level -i "Configure Kubectl and get external IP"
    KUBE_CONFIG_LOCATION=$(ssh -q -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo find . -type f -iname 'kubeconfig*'")
    
    log_level -i "Kubeconfig location ($KUBE_CONFIG_LOCATION)"
    KUBE_CONFIG_FILENAME=$(basename $KUBE_CONFIG_LOCATION)
    log_level -i "KUBE_CONFIG_FILENAME($KUBE_CONFIG_FILENAME)"
    
    log_level -i "Deleting Deployment"
    ssh -q -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "export KUBECONFIG='/home/$USER_NAME/$TEST_DIRECTORY/$KUBE_CONFIG_FILENAME'; kubectl delete -f $TEST_DIRECTORY/elastic-client.yaml"
    
    log_level -i "Delete test directory($TEST_DIRECTORY)"
    ssh -q -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo rm -rf $TEST_DIRECTORY"
    
    log_level -i "Release port"
    ssh -q -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo fuser -k 5000/tcp"
    
    
    log_level -i "Clean Up successful"
    result="pass"
    printf '{"result":"%s"}\n' "$result" >$OUTPUT_SUMMARYFILE
    
} \
2>&1 |
tee $LOG_FILE_NAME



