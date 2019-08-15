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
    
    i=0
    while [ $i -lt 20 ]; do
        EXTERNAL_IP=$(ssh -q -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "export KUBECONFIG='/home/$USER_NAME/$TEST_DIRECTORY/$KUBE_CONFIG_FILENAME'; kubectl get services -o custom-columns=IP:.status.loadBalancer.ingress[0].ip --no-headers  --field-selector metadata.name=elastic-client-service | grep -oP '(\d{1,3}\.){1,3}\d{1,3}' || true")
        if [ -z "$EXTERNAL_IP" ]; then
            log_level -i "External IP is not assigned. We we will retry after some time."
            sleep 30s
        else
            break
        fi
        let i=i+1
    done
    
    log_level -i "EXTERNAL_IP($EXTERNAL_IP)"
    if [ -z "$EXTERNAL_IP" ]; then
        log_level -e "External IP not found."
        printf '{"result":"%s","error":"%s"}\n' "failed" "External IP not found." >$OUTPUT_SUMMARYFILE
        exit 1
    fi

    log_level -i "Checking if Elasticsearch client is running"
    check_app_listening_at_externalip "$EXTERNAL_IP:3000"
    if [[ $? != 0 ]]; then
        log_level -e "Elasticsearch client is not running"
        printf '{"result":"%s","error":"%s"}\n' "failed" "Elasticsearch client is not running" >$OUTPUT_SUMMARYFILE
        exit 1
    else
        log_level -i "Elasticsearch client is up and running"
    fi

    log_level -i "Checking if client can insert data"
    APP_INSERT_STATUS=$(curl http://$EXTERNAL_IP:3000/insertData)
    log_level -i "App insert result status: $APP_INSERT_STATUS"
    if [[ $APP_INSERT_STATUS == *"created"* ]]; then
        log_level -i "Elasticsearch client insert data test passed. "
    else
        log_level -e "Elasticsearch client insert data test failed"
        printf '{"result":"%s","error":"%s"}\n' "failed" "Elasticsearch client could not insert data to database" >$OUTPUT_SUMMARYFILE
        exit 1
    fi
    
    log_level -i "Checking if client can read data"
    i=0
    while [ $i -lt 20 ]; do
        APP_READ_STATUS=$(
            curl http://$EXTERNAL_IP:3000/readData
            if [ $? -eq 0 ]; then echo "HTTP OK 200"; fi
        )
        if [[ $APP_READ_STATUS != *"Daenerys Targaryen"* ]]; then
            log_level -i "Read data failed. We we will retry after some time."
            sleep 10s
        else
            break
        fi
        let i=i+1
    done
    
    log_level -e "Elasticsearch client read data value: $APP_READ_STATUS"
    if [[ $APP_READ_STATUS == *"Daenerys Targaryen"* ]]; then
        log_level -i "Elasticsearch client read data test passed"
        printf '{"result":"%s"}\n' "pass" >$OUTPUT_SUMMARYFILE
    else
        log_level -e "Elasticsearch client read data test failed."
        printf '{"result":"%s","error":"%s"}\n' "failed" "Elasticsearch client could not read data from database" >$OUTPUT_SUMMARYFILE
        exit 1
    fi
    
    log_level -i "All tests passed"    
} \
2>&1 |
tee $LOG_FILE_NAME
