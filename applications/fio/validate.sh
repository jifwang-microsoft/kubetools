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
    APPLICATION_NAME="fio"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Inner Variables"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "APPLICATION_NAME           : $APPLICATION_NAME"
    log_level -i "------------------------------------------------------------------------"
    # Check application pod is up and running
    check_app_pod_running $IDENTITY_FILE \
    $USER_NAME \
    $MASTER_IP \
    "job-name=$APPLICATION_NAME"
    
    if [[ $? != 0 ]]; then
        printf '{"result":"%s","error":"%s"}\n' "failed" "Pod related to App($APPLICATION_NAME) was not successfull." > $OUTPUT_SUMMARYFILE
        exit 1
    fi
    
    # Wait for pod to stop.
    log_level -i "Wait for pod to complete the tests."
    i=0
    while [ $i -lt 20 ]; do
        appPodstatus=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo kubectl get pods --selector job-name=$APPLICATION_NAME | grep 'Completed' || true")
        if [ -z "$appPodstatus" ]; then
            log_level -i "Pod is still up and running. We we will retry after some time."
            sleep 60s
        else
            log_level -i "Pod run is over ($appPodstatus)."
            break
        fi
        let i=i+1
    done

    if [ -z "$appPodstatus" ]; then
        printf '{"result":"%s","error":"%s"}\n' "failed" "Pod($APPLICATION_NAME) could not complete the test within time." > $OUTPUT_SUMMARYFILE
        exit 1
    fi

    # Todo log parsing.

} 2>&1 | tee $LOG_FILENAME