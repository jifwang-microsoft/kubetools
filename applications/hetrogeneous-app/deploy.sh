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
LOG_FILE_NAME=$OUTPUT_DIRECTORY/deploy.log
TEST_DIRECTORY="hetro_app_assets"
touch $LOG_FILE_NAME
IDENTITY_FILE_BACKUP_PATH="/home/$USER_NAME/IDENTITY_FILEBACKUP"
DEPLOYMENT_SCRIPT="dvm_deploy.sh"
DEPLOY_DVM_LOG_FILE="dvm_deploy.log"

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
    log_level -i "DEPLOYMENT_SCRIPT: $DEPLOYMENT_SCRIPT"
    log_level -i "DEPLOY_DVM_LOG_FILE: $DEPLOY_DVM_LOG_FILE"
    log_level -i "GIT_REPROSITORY: $GIT_REPROSITORY"
    log_level -i "GIT_BRANCH: $GIT_BRANCH"
    log_level -i "MASTER_IP: $MASTER_IP"
    log_level -i "IDENTITY_FILE: $IDENTITY_FILE"
    log_level -i "IDENTITY_FILE_BACKUP_PATH: $IDENTITY_FILE_BACKUP_PATH"
    log_level -i "LOG_FILE_NAME: $LOG_FILE_NAME"
    log_level -i "OUTPUT_DIRECTORY: $OUTPUT_DIRECTORY"
    log_level -i "TEST_DIRECTORY: $TEST_DIRECTORY"
    log_level -i "-----------------------------------------------------------------------------"
    
    #if file exists, do not download
    if [ ! -f $SCRIPT_LOCATION/$DEPLOYMENT_SCRIPT ]; then
        log_level -i "Deployment script does not exist downloading"
        curl -o $SCRIPT_LOCATION/$DEPLOYMENT_SCRIPT https://raw.githubusercontent.com/$GIT_REPROSITORY/$GIT_BRANCH/applications/hetrogeneous-app/$DEPLOYMENT_SCRIPT
        
        if [ ! -f $SCRIPT_LOCATION/$DEPLOYMENT_SCRIPT ]; then
            log_level -e "File($DEPLOYMENT_SCRIPT) failed to download."
            result="failed"
            printf '{"result":"%s","error":"%s"}\n' "$result" "Download of file($DEPLOYMENT_SCRIPT) was not successfull." >$OUTPUT_SUMMARYFILE
            exit 1
        fi
    fi
    
    log_level -i "Backing up identity files at ($IDENTITY_FILE_BACKUP_PATH)"
    ssh -q -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "if [ -f /home/$USER_NAME/.ssh/id_rsa ]; then mkdir -p $IDENTITY_FILE_BACKUP_PATH;  sudo mv /home/$USER_NAME/.ssh/id_rsa $IDENTITY_FILE_BACKUP_PATH; fi;"
    
    log_level -i "Copying over new identity file"
    scp -i $IDENTITY_FILE $IDENTITY_FILE $USER_NAME@$MASTER_IP:/home/$USER_NAME/.ssh/id_rsa
    
    log_level -i "Create test directory($TEST_DIRECTORY)"
    ssh -q -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "mkdir -p $TEST_DIRECTORY"
    
    log_level -i "Install and Modify to unix format"
    dos2unix $SCRIPT_LOCATION/$DEPLOYMENT_SCRIPT;
    
    log_level -i "Copy script($DEPLOYMENT_SCRIPT) to test directory($TEST_DIRECTORY)"
    scp -i $IDENTITY_FILE $SCRIPT_LOCATION/$DEPLOYMENT_SCRIPT $USER_NAME@$MASTER_IP:/home/$USER_NAME/$TEST_DIRECTORY
    
    log_level -i "Run deployment and test"
    ssh -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY; chmod +x ./$DEPLOYMENT_SCRIPT; ./$DEPLOYMENT_SCRIPT -m $MASTER_IP -t /home/$USER_NAME/$TEST_DIRECTORY 2>&1 | tee $DEPLOY_DVM_LOG_FILE;"
    
    log_level -i "Copying over deployment logs locally"
    scp -i $IDENTITY_FILE $USER_NAME@$MASTER_IP:/home/$USER_NAME/$TEST_DIRECTORY/$DEPLOY_DVM_LOG_FILE $OUTPUT_DIRECTORY
    
    #Checking status of the deployment
    DEPLOYMENT_STATUS=`awk '/./{line=$0} END{print line}' $OUTPUT_DIRECTORY/$DEPLOY_DVM_LOG_FILE`
    
    if [ "$DEPLOYMENT_STATUS" == "0" ];
    then
        result="pass"
        printf '{"result":"%s"}\n' "$result" > $OUTPUT_SUMMARYFILE
    else
        result="failed"
        printf '{"result":"%s","error":"%s"}\n' "$result" "$DEPLOYMENT_STATUS" > $OUTPUT_SUMMARYFILE
    fi
} \
2>&1 |
tee $LOG_FILE_NAME
