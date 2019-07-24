#!/bin/bash

set -e

FILENAME=$0

SCRIPT_LOCATION=$(dirname $FILENAME)
COMMON_SCRIPT_FILENAME="common.sh"
GIT_REPROSITORY="${GIT_REPROSITORY:-msazurestackworkloads/kubetools}"
GIT_BRANCH="${GIT_BRANCH:-master}"

# Download common script file.
curl -o $SCRIPT_DIRECTORY/$COMMON_SCRIPT_FILENAME \
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
LOG_FILE_NAME=$OUTPUT_DIRECTORY/validate.log
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
    log_level -i "MASTER_IP: $MASTER_IP"
    log_level -i "IDENTITY_FILE: $IDENTITY_FILE"
    log_level -i "IDENTITY_FILE_BACKUP_PATH: $IDENTITY_FILE_BACKUP_PATH"
    log_level -i "LOG_FILE_NAME: $LOG_FILE_NAME"
    log_level -i "OUTPUT_DIRECTORY: $OUTPUT_DIRECTORY"
    log_level -i "USER: $USER_NAME"
    log_level -i "TEST_DIRECTORY: $TEST_DIRECTORY"
    log_level -i "-----------------------------------------------------------------------------"
    
    log_level -i "Configure Kubectl and get external IP"
    KUBE_CONFIG_LOCATION=$(ssh -q -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo find . -type f -iname 'kubeconfig*'")
    
    log_level -i "Kubeconfig location ($KUBE_CONFIG_LOCATION)"
    KUBE_CONFIG_FILENAME=$(basename $KUBE_CONFIG_LOCATION)
    log_level -i "KUBE_CONFIG_FILENAME($KUBE_CONFIG_FILENAME)"
    
    EXTERNAL_IP=$(ssh -q -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "export KUBECONFIG='/home/$USER_NAME/$TEST_DIRECTORY/$KUBE_CONFIG_FILENAME'; kubectl get services -o custom-columns=IP:.status.loadBalancer.ingress[0].ip --no-headers  --field-selector metadata.name=elastic-client-service")
    log_level -i "EXTERNAL_IP($EXTERNAL_IP)"
    
    log_level -i "Checking if Elasticsearch client is running"
    APP_CHECK_STATUS=$(ssh -q -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "curl http://$EXTERNAL_IP:3000")
    
    if [[ $APP_CHECK_STATUS == *"Yup"* ]]; then
        log_level -i "Elasticsearch client is up and running"
    else
        log_level -e "Elasticsearch client is not running"
        printf '{"result":"%s","error":"%s"}\n' "failed" "Elasticsearch client is not running" >$OUTPUT_SUMMARYFILE
        exit 1
    fi
    
    log_level -i "Checking if client can insert data"
    APP_INSERT_STATUS=$(ssh -q -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "curl http://$EXTERNAL_IP:3000/insertData")
    
    if [[ $APP_INSERT_STATUS == *"created"* ]]; then
        log_level -i "Elasticsearch client insert data test passed"
    else
        log_level -e "Elasticsearch client insert data test failed"
        printf '{"result":"%s","error":"%s"}\n' "failed" "Elasticsearch client could not insert data to database" >$OUTPUT_SUMMARYFILE
        exit 1
    fi
    
    log_level -i "Checking if client can read data"
    APP_READ_STATUS=$(ssh -q -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "curl http://$EXTERNAL_IP:3000/readData")
    
    if [[ $APP_READ_STATUS == *"Daenerys Targaryen"* ]]; then
        log_level -i "Elasticsearch client read data test passed"
    else
        log_level -e "Elasticsearch client read data test failed"
        printf '{"result":"%s","error":"%s"}\n' "failed" "Elasticsearch client could not read data from database" >$OUTPUT_SUMMARYFILE
        exit 1
    fi
    
    log_level -i "All tests passed"
    result="pass"
    printf '{"result":"%s"}\n' "$result" >$OUTPUT_SUMMARYFILE
    
} \
2>&1 |
tee $LOG_FILE_NAME
