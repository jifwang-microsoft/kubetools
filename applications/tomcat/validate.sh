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
LOG_FILENAME="$OUTPUT_FOLDER/validate.log"
touch $LOG_FILENAME

{
    APPLICATION_NAME="tomcat"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Inner Variables"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "APPLICATION_NAME           : $APPLICATION_NAME"
    log_level -i "------------------------------------------------------------------------"
    # Check application pod is up and running
    check_helm_app_pod_running $IDENTITY_FILE \
    $USER_NAME \
    $MASTER_IP \
    $APPLICATION_NAME
    
    if [[ $? != 0 ]]; then
        printf '{"result":"%s","error":"%s"}\n' "failed" "Pod related to App($APPLICATION_NAME) was not successfull." > $OUTPUT_SUMMARYFILE
        exit 1
    fi
    
    # check_app_has_externalip set global variable IP_ADDRESS.
    APPLICATION_RELEASE_NAME=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "helm ls -d -r | grep 'DEPLOYED\(.*\)$APPLICATION_NAME' | grep -Eo '^[a-z,-]+'")
    check_app_has_externalip $IDENTITY_FILE \
    $USER_NAME \
    $MASTER_IP \
    $APPLICATION_NAME \
    $APPLICATION_RELEASE_NAME
    
    if [[ $? != 0 ]]; then
        printf '{"result":"%s","error":"%s"}\n' "failed" "External IP not found for $APPLICATION_NAME." > $OUTPUT_SUMMARYFILE
        exit 1
    fi
    
    # IP_ADDRESS variable is set in check_app_has_externalip function.
    check_app_listening_at_externalip $IP_ADDRESS
    if [[ $? != 0 ]]; then
        printf '{"result":"%s","error":"%s"}\n' "failed" "Not able to communicate to $IP_ADDRESS." > $OUTPUT_SUMMARYFILE
    else
        printf '{"result":"%s"}\n' "pass" > $OUTPUT_SUMMARYFILE
    fi
    
    # Create result file, even if script ends with an error
    #trap final_changes EXIT
    
} 2>&1 | tee $LOG_FILENAME