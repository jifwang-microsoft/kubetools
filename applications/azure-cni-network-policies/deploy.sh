#!/bin/bash -e

FILE_NAME=$0

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
    log_level -e "Summary file not set."
    echo "Summary file not set."
    exit 1
fi

###########################################################################################################
# Define all inner varaibles.

OUTPUT_FOLDER=$(dirname $OUTPUT_SUMMARYFILE)
LOG_FILENAME="$OUTPUT_FOLDER/deploy.log"
touch $LOG_FILENAME

{
    if [[ -z $IDENTITY_FILE ]]; then
        log_level -e "IDENTITY_FILE not set."
        printf "IDENTITY_FILE not set." > $OUTPUT_SUMMARYFILE
        exit 1
    fi
    
    if [[ -z $MASTER_IP ]]; then
        log_level -e "MASTER_IP not set."
        printf "MASTER_IP not set." > $OUTPUT_SUMMARYFILE
        exit 1
    fi
    
    if [[ -z $USER_NAME ]]; then
        log_level -e "USER_NAME not set."
        printf "USER_NAME not set." > $OUTPUT_SUMMARYFILE
        exit 1
    fi

    TEST_DIRECTORY="/home/$USER_NAME/azure-cni-network-policies"
    NGINX_DEPLOY_FILENAME="nginx_deploy.yaml"
    BUSYBOX_DEPLOY_FILENAME="busybox_deploy.yaml"
    NETWORK_POLICY_FILENAME="network_policy.yaml"

    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Script Parameters"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "IDENTITY_FILE               : $IDENTITY_FILE"
    log_level -i "GIT_BRANCH                  : $GIT_BRANCH"
    log_level -i "GIT_REPROSITORY             : $GIT_REPROSITORY"
    log_level -i "MASTER_IP                   : $MASTER_IP"
    log_level -i "OUTPUT_SUMMARYFILE          : $OUTPUT_SUMMARYFILE"
    log_level -i "USER_NAME                   : $USER_NAME"
    log_level -i "TEST_DIRECTORY              : $TEST_DIRECTORY"
    log_level -i "NGINX_DEPLOY_FILENAME       : $NGINX_DEPLOY_FILENAME"
    log_level -i "BUSYBOX_DEPLOY_FILENAME     : $BUSYBOX_DEPLOY_FILENAME"
    log_level -i "NETWORK_POLICY_FILENAME     : $NETWORK_POLICY_FILENAME"
    log_level -i "------------------------------------------------------------------------"
    
    curl -o $OUTPUT_FOLDER/$NGINX_DEPLOY_FILENAME \
    https://raw.githubusercontent.com/$GIT_REPROSITORY/$GIT_BRANCH/applications/azure-cni-network-policies/$NGINX_DEPLOY_FILENAME
    if [ ! -f $OUTPUT_FOLDER/$NGINX_DEPLOY_FILENAME ]; then
        log_level -e "File($NGINX_DEPLOY_FILENAME) failed to download."
        result="failed"
        printf '{"result":"%s","error":"%s"}\n' "$result" "Download of file($NGINX_DEPLOY_FILENAME) was not successfull." > $OUTPUT_SUMMARYFILE
        exit 1
    fi

    curl -o $OUTPUT_FOLDER/$BUSYBOX_DEPLOY_FILENAME \
    https://raw.githubusercontent.com/$GIT_REPROSITORY/$GIT_BRANCH/applications/azure-cni-network-policies/$BUSYBOX_DEPLOY_FILENAME
    if [ ! -f $OUTPUT_FOLDER/$BUSYBOX_DEPLOY_FILENAME ]; then
        log_level -e "File($BUSYBOX_DEPLOY_FILENAME) failed to download."
        result="failed"
        printf '{"result":"%s","error":"%s"}\n' "$result" "Download of file($BUSYBOX_DEPLOY_FILENAME) was not successfull." > $OUTPUT_SUMMARYFILE
        exit 1
    fi

    curl -o $OUTPUT_FOLDER/$NETWORK_POLICY_FILENAME \
    https://raw.githubusercontent.com/$GIT_REPROSITORY/$GIT_BRANCH/applications/azure-cni-network-policies/$NETWORK_POLICY_FILENAME
    if [ ! -f $OUTPUT_FOLDER/$NETWORK_POLICY_FILENAME ]; then
        log_level -e "File($NETWORK_POLICY_FILENAME) failed to download."
        result="failed"
        printf '{"result":"%s","error":"%s"}\n' "$result" "Download of file($NETWORK_POLICY_FILENAME) was not successfull." > $OUTPUT_SUMMARYFILE
        exit 1
    fi
    
    log_level -i "Create test folder($TEST_DIRECTORY)"
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "mkdir -p $TEST_DIRECTORY"

    log_level -i "Copy files to K8s master node."
    scp -i $IDENTITY_FILE \
    $OUTPUT_FOLDER/$NGINX_DEPLOY_FILENAME \
    $USER_NAME@$MASTER_IP:$TEST_DIRECTORY/
    scp -i $IDENTITY_FILE \
    $OUTPUT_FOLDER/$BUSYBOX_DEPLOY_FILENAME \
    $USER_NAME@$MASTER_IP:$TEST_DIRECTORY/
    scp -i $IDENTITY_FILE \
    $OUTPUT_FOLDER/$NETWORK_POLICY_FILENAME \
    $USER_NAME@$MASTER_IP:$TEST_DIRECTORY/
    
    log_level -i "=========================================================================="
    log_level -i "Installing nginx and busybox."

    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo chmod 744 $TEST_DIRECTORY/$NGINX_DEPLOY_FILENAME; cd $TEST_DIRECTORY;"
    nginx=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY;kubectl create -f $NGINX_DEPLOY_FILENAME";sleep 60)
    nginx_deploy=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY;kubectl get deployment -o json > nginx_deploy.json")
    nginx_status=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY;cat nginx_deploy.json | jq '.items[0]."status"."conditions"[0].type'" | grep "Available";sleep 2m)

    if [ $? == 0 ]; then
        log_level -i "Deployed nginx app."
    else    
        log_level -e "Nginx deployment failed."
        result="failed"
        printf '{"result":"%s","error":"%s"}\n' "$result" "Nginx deployment was not successfull." > $OUTPUT_SUMMARYFILE
        exit 1
    fi 

    nginx_services=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY;kubectl get services nginx -o json > nginx_service.json")

    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo chmod 744 $TEST_DIRECTORY/$BUSYBOX_DEPLOY_FILENAME; cd $TEST_DIRECTORY;"
    busybox=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY;kubectl create -f $BUSYBOX_DEPLOY_FILENAME";sleep 30)
    busybox_deploy=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY;kubectl get pod busybox -o json > busybox_pod.json")
    busybox_status=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY;cat busybox_pod.json | jq '.items[0]."status"."conditions"[1].type'" | grep "Ready")

    if [ $? == 0 ]; then
        log_level -i "Deployed busybox pod."
    else    
        log_level -e "Busybox deployment failed."
        result="failed"
        printf '{"result":"%s","error":"%s"}\n' "$result" "Busybox deployment was not successfull." > $OUTPUT_SUMMARYFILE
        exit 1
    fi 

    busybox_log=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY;kubectl logs busybox > busybox_log.txt")
    
    log_level -i "=========================================================================="
    result="pass"
    printf '{"result":"%s"}\n' "$result" > $OUTPUT_SUMMARYFILE

} 2>&1 | tee $LOG_FILENAME
