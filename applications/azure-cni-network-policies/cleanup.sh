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

OUTPUT_FOLDER="$(dirname $OUTPUT_SUMMARYFILE)"
LOG_FILENAME="$OUTPUT_FOLDER/cleanup.log"
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

    APPLICATION_NAME="azure-cni-network-policies"
    TEST_DIRECTORY="/home/$USER_NAME/$APPLICATION_NAME"
    NGINX_DEPLOY_FILENAME="nginx_deploy.yaml"
    BUSYBOX_DEPLOY_FILENAME="busybox_deploy.yaml"
    NETWORK_POLICY_FILENAME="network_policy.yaml"
    
    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Script Parameters"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "GIT_REPROSITORY:          : $GIT_REPROSITORY"
    log_level -i "GIT_BRANCH:               : $GIT_BRANCH"
    log_level -i "IDENTITY_FILE             : $IDENTITY_FILE"
    log_level -i "MASTER_IP                 : $MASTER_IP"
    log_level -i "OUTPUT_SUMMARYFILE        : $OUTPUT_SUMMARYFILE"
    log_level -i "USER_NAME                 : $USER_NAME"
    log_level -i "APPLICATION_NAME          : $APPLICATION_NAME"
    log_level -i "TEST_DIRECTORY            : $TEST_DIRECTORY"
    log_level -i "NGINX_DEPLOY_FILENAME     : $NGINX_DEPLOY_FILENAME"
    log_level -i "BUSYBOX_DEPLOY_FILENAME   : $BUSYBOX_DEPLOY_FILENAME"
    log_level -i "NETWORK_POLICY_FILENAME   : $NETWORK_POLICY_FILENAME"
    log_level -i "------------------------------------------------------------------------"
    
    log_level -i "Deleting Deployment"
    nginx_delete=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY;kubectl delete -f $NGINX_DEPLOY_FILENAME")
    busybox_delete=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY;kubectl delete -f $BUSYBOX_DEPLOY_FILENAME")
    network_policy_delete=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY;kubectl delete -f $NETWORK_POLICY_FILENAME";sleep 60)
    
    log_level -i "Removing test directory"
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo rm -rf $TEST_DIRECTORY;"
    
    if [[ $? != 0 ]]; then
        printf '{"result":"%s","error":"%s"}\n' "failed" "($APPLICATION_NAME) cleanup was not successfull" >$OUTPUT_SUMMARYFILE
    else
        printf '{"result":"%s"}\n' "pass" >$OUTPUT_SUMMARYFILE
    fi

    log_level -i "Clean up successfully." 
    log_level -i "=========================================================================="

} 2>&1 | tee $LOG_FILENAME
