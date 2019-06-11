#!/bin/bash -e

FILE_NAME=$0

SCRIPT_FOLDER="$(dirname $FILE_NAME)"
GIT_REPROSITORY="${GIT_REPROSITORY:-msazurestackworkloads/kubetools}"
GIT_BRANCH="${GIT_BRANCH:-master}"
COMMON_SCRIPT_FILENAME="common.sh"

# Download common script file.
curl -o $SCRIPT_FOLDER/$COMMON_SCRIPT_FILENAME \
https://raw.githubusercontent.com/$GIT_REPROSITORY/$GIT_BRANCH/applications/common/$COMMON_SCRIPT_FILENAME
if [ ! -f $SCRIPT_FOLDER/$COMMON_SCRIPT_FILENAME ]; then
    log_level -e "File($COMMON_SCRIPT_FILENAME) failed to download."
    exit 1
fi

source $SCRIPT_FOLDER/$COMMON_SCRIPT_FILENAME
###########################################################################################################
# The function will read parameters and populate below global variables.
# IDENTITY_FILE, MASTER_IP, OUTPUT_SUMMARYFILE, USER_NAME
parse_commandline_arguments $@

log_level -i "------------------------------------------------------------------------"
log_level -i "                Input Parameters"
log_level -i "------------------------------------------------------------------------"
log_level -i "IDENTITY_FILE       : $IDENTITY_FILE"
log_level -i "CONFIG_FILE         : $CONFIG_FILE"
log_level -i "MASTER_IP           : $MASTER_IP"
log_level -i "OUTPUT_SUMMARYFILE  : $OUTPUT_SUMMARYFILE"
log_level -i "USER_NAME           : $USER_NAME"
log_level -i "------------------------------------------------------------------------"

if [[ -z "$IDENTITY_FILE" ]] || \
[[ -z "$MASTER_IP" ]] || \
[[ -z "$USER_NAME" ]] || \
[[ -z "$CONFIG_FILE" ]] || \
[[ -z "$OUTPUT_SUMMARYFILE" ]]; then
    log_level -e "One of the mandatory parameter is not passed correctly."
    print_usage
    exit 1
fi

###########################################################################################################
# Define all inner varaibles.
OUTPUT_FOLDER="$(dirname $OUTPUT_SUMMARYFILE)"
LOG_FILENAME="$OUTPUT_FOLDER/deploy.log"
touch $LOG_FILENAME

{

    # Github details.
    APPLICATION_NAME="fio"
    APP_DEPLOYMENT_FILE="fio_deployment.yaml"
    TEST_FOLDER="/home/$USER_NAME/$APPLICATION_NAME"

    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Inner Variables"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "APPLICATION_NAME           : $APPLICATION_NAME"
    log_level -i "APP_DEPLOYMENT_FILE        : $APP_DEPLOYMENT_FILE"
    log_level -i "TEST_FOLDER                : $TEST_FOLDER"
    log_level -i "------------------------------------------------------------------------"    

    # ----------------------------------------------------------------------------------------
    # INSTALL PREREQUISITE

    curl -o $SCRIPT_FOLDER/$INSTALL_PREREQUISITE_FILE \
    https://raw.githubusercontent.com/$GIT_REPROSITORY/$GIT_BRANCH/applications/$APPLICATION_NAME/$APP_DEPLOYMENT_FILE
    if [ ! -f $SCRIPT_FOLDER/$INSTALL_PREREQUISITE_FILE ]; then
        log_level -e "File($APP_DEPLOYMENT_FILE) failed to download."
        printf '{"result":"%s","error":"%s"}\n' "failed" "File($APP_DEPLOYMENT_FILE) failed to download." > $OUTPUT_SUMMARYFILE
        exit 1
    fi
    
    log_level -i "Create test folder($TEST_FOLDER)"
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "mkdir -p $TEST_FOLDER"
    log_level -i "Copy file($APP_DEPLOYMENT_FILE) to VM."
    scp -i $IDENTITY_FILE \
    $SCRIPT_FOLDER/$APP_DEPLOYMENT_FILE \
    $USER_NAME@$MASTER_IP:$TEST_FOLDER/

    # Launch fio app
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_FOLDER; kubectl apply -f $APP_DEPLOYMENT_FILE;"
    if [[ $? != 0 ]]; then
        log_level -e "No fio file got deployed."
        printf '{"result":"%s","error":"%s"}\n' "failed" "No fio file got deployed." > $OUTPUT_SUMMARYFILE
        exit 1
    else
        printf '{"result":"%s"}\n' "pass" > $OUTPUT_SUMMARYFILE
    fi

} 2>&1 | tee $LOG_FILENAME