#!/bin/bash -e

FILE_NAME=$0

SCRIPT_FOLDER="$(dirname $FILE_NAME)"
GIT_REPROSITORY="${GIT_REPROSITORY:-msazurestackworkloads/kubetools}"
GIT_BRANCH="${GIT_BRANCH:-master}"
COMMON_SCRIPT_FILENAME="common.sh"

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
[[ -z "$OUTPUT_SUMMARYFILE" ]]; then
    log_level -e "One of mandatory parameter is not passed correctly."
    print_usage
    exit 1
fi

###########################################################################################################
# Define all inner varaibles.
OUTPUT_FOLDER="$(dirname $OUTPUT_SUMMARYFILE)"
LOG_FILENAME="$OUTPUT_FOLDER/cleanup.log"
touch $LOG_FILENAME

{

    GO_FOLDER="/home/$USER_NAME/go"
    APPLICATION_NAME="netperf"
    TEST_FOLDER="/home/$USER_NAME/$APPLICATION_NAME"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Inner Variables"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "APPLICATION_NAME           : $APPLICATION_NAME"
    log_level -i "GO_FOLDER                  : $GO_FOLDER"
    log_level -i "TEST_FOLDER                : $TEST_FOLDER"
    log_level -i "------------------------------------------------------------------------"

    # ----------------------------------------------------------------------------------------
    log_level -i "Cleanup go folder ($GO_FOLDER)."
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo rm -rf $GO_FOLDER;"

    log_level -i "Cleanup the test folder($TEST_FOLDER)"
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo rm -rf $TEST_FOLDER;"
    
    log_level -i "Netbench app cleanup done."
    printf '{"result":"%s"}\n' "pass" > $OUTPUT_SUMMARYFILE
} 2>&1 | tee $LOG_FILENAME