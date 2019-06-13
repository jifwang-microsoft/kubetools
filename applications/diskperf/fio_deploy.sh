#!/bin/bash -e

FILE_NAME=$0

SCRIPT_DIRECTORY="$(dirname $FILE_NAME)"
GIT_REPROSITORY="${GIT_REPROSITORY:-msazurestackworkloads/kubetools}"
GIT_BRANCH="${GIT_BRANCH:-master}"
COMMON_SCRIPT_FILENAME="common.sh"

# Download common script file.
curl -o $SCRIPT_DIRECTORY/$COMMON_SCRIPT_FILENAME \
https://raw.githubusercontent.com/$GIT_REPROSITORY/$GIT_BRANCH/applications/common/$COMMON_SCRIPT_FILENAME
if [ ! -f $SCRIPT_DIRECTORY/$COMMON_SCRIPT_FILENAME ]; then
    log_level -e "File($COMMON_SCRIPT_FILENAME) failed to download."
    exit 1
fi

source $SCRIPT_DIRECTORY/$COMMON_SCRIPT_FILENAME
###########################################################################################################
# The function will read parameters and populate below global variables.
# IDENTITY_FILE, MASTER_IP, OUTPUT_SUMMARYFILE, USER_NAME
parse_commandline_arguments $@

log_level -i "------------------------------------------------------------------------"
log_level -i "                Input Parameters"
log_level -i "------------------------------------------------------------------------"
log_level -i "IDENTITY_FILE       : $IDENTITY_FILE"
log_level -i "MASTER_IP           : $MASTER_IP"
log_level -i "OUTPUT_SUMMARYFILE  : $OUTPUT_SUMMARYFILE"
log_level -i "USER_NAME           : $USER_NAME"
log_level -i "------------------------------------------------------------------------"

if [[ -z "$IDENTITY_FILE" ]] || \
[[ -z "$MASTER_IP" ]] || \
[[ -z "$USER_NAME" ]] || \
[[ -z "$OUTPUT_SUMMARYFILE" ]]; then
    log_level -e "One of the mandatory parameter is not passed correctly."
    print_usage
    exit 1
fi

###########################################################################################################
# Define all inner varaibles.
OUTPUT_DIRECTORY="$(dirname $OUTPUT_SUMMARYFILE)"
LOG_FILENAME="$OUTPUT_DIRECTORY/deploy.log"
touch $LOG_FILENAME

{
    # Github details.
    APPLICATION_NAME="fio"
    APP_DEPLOYMENT_FILE="fio_deployment.yaml"
    TEST_DIRECTORY="/home/$USER_NAME/$APPLICATION_NAME"
    EXPECTED_RESULT_FILE="expectedresults.json"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Inner Variables"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "APPLICATION_NAME           : $APPLICATION_NAME"
    log_level -i "APP_DEPLOYMENT_FILE        : $APP_DEPLOYMENT_FILE"
    log_level -i "EXPECTED_RESULT_FILE       : $EXPECTED_RESULT_FILE"
    log_level -i "TEST_DIRECTORY             : $TEST_DIRECTORY"
    log_level -i "------------------------------------------------------------------------"    

    # ----------------------------------------------------------------------------------------
    # INSTALL PREREQUISITE
    apt_install_jq
    download_file_locally $GIT_REPROSITORY $GIT_BRANCH \
    "applications/diskperf" \
    $SCRIPT_DIRECTORY \
    $EXPECTED_RESULT_FILE

    download_file_locally $GIT_REPROSITORY $GIT_BRANCH \
    "applications/diskperf" \
    $SCRIPT_DIRECTORY \
    $APP_DEPLOYMENT_FILE 
    
    if [[ $? != 0 ]]; then
        log_level -e "Download of file($APP_DEPLOYMENT_FILE) failed."
        printf '{"result":"%s","error":"%s"}\n' "failed" "Download of file($APP_DEPLOYMENT_FILE) was not successfull." > $OUTPUT_SUMMARYFILE
        exit 1
    fi
    
    log_level -i "Create test DIRECTORY($TEST_DIRECTORY)"
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "mkdir -p $TEST_DIRECTORY"
    log_level -i "Copy file($APP_DEPLOYMENT_FILE) to VM."
    scp -i $IDENTITY_FILE \
    $SCRIPT_DIRECTORY/$APP_DEPLOYMENT_FILE \
    $USER_NAME@$MASTER_IP:$TEST_DIRECTORY/

    # Launch fio app
    log_level -i "Deploy application using file($APP_DEPLOYMENT_FILE)"
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY; kubectl apply -f $APP_DEPLOYMENT_FILE;"

    check_app_pod_status $IDENTITY_FILE \
    $USER_NAME \
    $MASTER_IP \
    "job-name=$APPLICATION_NAME" \
    "Running"
    
    if [[ $? != 0 ]]; then
        printf '{"result":"%s","error":"%s"}\n' "failed" "Pod related to App($APPLICATION_NAME) was not successfull." > $OUTPUT_SUMMARYFILE
        exit 1
    else
        printf '{"result":"%s"}\n' "pass" > $OUTPUT_SUMMARYFILE
    fi

} 2>&1 | tee $LOG_FILENAME