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

    # Details.
    APPLICATION_NAME="operationperf"
    EXPECTED_RESULT_FILE="expectedresults.json"
    DEPLOYMENT_PVC_FILE="nginx_pvc_test.yaml"
    DEPLOYMENT_LOADBALANCER_FILE="nginx_loadbalancer.yaml"
    DEPLOYMENT_LOADBALANCER_FILE_2="nginx_loadbalancer_2.yaml"
    INSTALL_PREREQUISITE="install_prerequisite.sh"
    TEST_DIRECTORY="/home/$USER_NAME/$APPLICATION_NAME"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Inner Variables"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "APPLICATION_NAME               : $APPLICATION_NAME"
    log_level -i "DEPLOYMENT_PVC_FILE            : $DEPLOYMENT_PVC_FILE"
    log_level -i "DEPLOYMENT_LOADBALANCER_FILE   : $DEPLOYMENT_LOADBALANCER_FILE"
    log_level -i "DEPLOYMENT_LOADBALANCER_FILE_2 : $DEPLOYMENT_LOADBALANCER_FILE_2"
    log_level -i "EXPECTED_RESULT_FILE           : $EXPECTED_RESULT_FILE"
    log_level -i "INSTALL_PREREQUISITE           : $INSTALL_PREREQUISITE"
    log_level -i "GIT_BRANCH                     : $GIT_BRANCH"
    log_level -i "GIT_REPROSITORY                : $GIT_REPROSITORY"
    log_level -i "TEST_DIRECTORY                 : $TEST_DIRECTORY"
    log_level -i "------------------------------------------------------------------------"    

    # ----------------------------------------------------------------------------------------
    # INSTALL PREREQUISITE
    apt_install_jq $OUTPUT_DIRECTORY
    if [[ $? != 0 ]]; then
        log_level -e "Install of jq was not successfull."
        printf '{"result":"%s","error":"%s"}\n' "failed" "Install of JQ was not successfull." > $OUTPUT_SUMMARYFILE
        exit 1
    fi

    download_file_locally $GIT_REPROSITORY \
    $GIT_BRANCH \
    "applications/common" \
    $SCRIPT_DIRECTORY \
    $INSTALL_PREREQUISITE

    download_file_locally $GIT_REPROSITORY $GIT_BRANCH \
    "applications/$APPLICATION_NAME" \
    $SCRIPT_DIRECTORY \
    $EXPECTED_RESULT_FILE

    download_file_locally $GIT_REPROSITORY $GIT_BRANCH \
    "applications/$APPLICATION_NAME/deploymentConfig/linux" \
    $SCRIPT_DIRECTORY \
    $DEPLOYMENT_PVC_FILE

    download_file_locally $GIT_REPROSITORY $GIT_BRANCH \
    "applications/$APPLICATION_NAME/deploymentConfig/linux" \
    $SCRIPT_DIRECTORY \
    $DEPLOYMENT_LOADBALANCER_FILE

    download_file_locally $GIT_REPROSITORY $GIT_BRANCH \
    "applications/$APPLICATION_NAME/deploymentConfig/linux" \
    $SCRIPT_DIRECTORY \
    $DEPLOYMENT_LOADBALANCER_FILE_2
    
    # ----------------------------------------------------------------------------------------
    # Copy all files inside master VM for execution.
    log_level -i "Create test directory($TEST_DIRECTORY)"
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "mkdir -p $TEST_DIRECTORY"

    log_level -i "Copy file($INSTALL_PREREQUISITE) to VM."
    scp -i $IDENTITY_FILE \
    $SCRIPT_DIRECTORY/$INSTALL_PREREQUISITE \
    $USER_NAME@$MASTER_IP:$TEST_DIRECTORY/

    log_level -i "Copy file($COMMON_SCRIPT_FILENAME) to VM."
    scp -i $IDENTITY_FILE \
    $SCRIPT_DIRECTORY/$COMMON_SCRIPT_FILENAME \
    $USER_NAME@$MASTER_IP:$TEST_DIRECTORY/

    log_level -i "Copy file($DEPLOYMENT_PVC_FILE) to VM."
    scp -i $IDENTITY_FILE \
    $SCRIPT_DIRECTORY/$DEPLOYMENT_PVC_FILE \
    $USER_NAME@$MASTER_IP:$TEST_DIRECTORY/

    log_level -i "Copy file($DEPLOYMENT_LOADBALANCER_FILE) to VM."
    scp -i $IDENTITY_FILE \
    $SCRIPT_DIRECTORY/$DEPLOYMENT_LOADBALANCER_FILE \
    $USER_NAME@$MASTER_IP:$TEST_DIRECTORY/

    log_level -i "Copy file($DEPLOYMENT_LOADBALANCER_FILE_2) to VM."
    scp -i $IDENTITY_FILE \
    $SCRIPT_DIRECTORY/$DEPLOYMENT_LOADBALANCER_FILE_2 \
    $USER_NAME@$MASTER_IP:$TEST_DIRECTORY/

    # INSTALL PREREQUISITE
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo chmod 744 $TEST_DIRECTORY/$INSTALL_PREREQUISITE; "
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cd $TEST_DIRECTORY; source $INSTALL_PREREQUISITE; apt_install_prerequisite_packages ;"

    log_level -i "Operational perf setup done."
    printf '{"result":"%s"}\n' "pass" > $OUTPUT_SUMMARYFILE
} 2>&1 | tee $LOG_FILENAME