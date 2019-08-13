#!/bin/bash -e

FILE_NAME=$0

SCRIPT_FOLDER="$(dirname $FILE_NAME)"
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
log_level -i "MASTER_IP           : $MASTER_IP"
log_level -i "OUTPUT_SUMMARYFILE  : $OUTPUT_SUMMARYFILE"
log_level -i "USER_NAME           : $USER_NAME"
log_level -i "------------------------------------------------------------------------"

if
[[ -z "$IDENTITY_FILE" ]] || \
[[ -z "$MASTER_IP" ]] || \
[[ -z "$USER_NAME" ]] || \
[[ -z "$OUTPUT_SUMMARYFILE" ]]
then
    log_level -e "One of mandatory parameter is not passed correctly."
    print_usage
    exit 1
fi

OUTPUT_FOLDER="$(dirname $OUTPUT_SUMMARYFILE)"
LOG_FILENAME="$OUTPUT_FOLDER/cleanup.log"
touch $LOG_FILENAME
{
    APPLICATION_NAME="scale_apps"
    TEST_DIRECTORY="/home/$USER_NAME/$APPLICATION_NAME"

    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Inner Variables"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "APPLICATION_NAME         : $APPLICATION_NAME"
    log_level -i "TEST_DIRECTORY           : $TEST_DIRECTORY"
    log_level -i "------------------------------------------------------------------------"
    
    # Todo cleanup apps.
    log_level -i "Removing test directory"
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo rm -rf $TEST_DIRECTORY;"

    if [[ $? != 0 ]]; then
        printf '{"result":"%s","error":"%s"}\n' "failed" "App($APPLICATION_NAME) cleanup was not successfull" >$OUTPUT_SUMMARYFILE
    else
        printf '{"result":"%s"}\n' "pass" >$OUTPUT_SUMMARYFILE
    fi

    # Create result file, even if script ends with an error
    #trap final_changes EXIT
} 2>&1 | tee $LOG_FILENAME
