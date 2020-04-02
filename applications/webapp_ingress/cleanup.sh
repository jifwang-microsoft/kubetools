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

OUTPUT_FOLDER="$(dirname $OUTPUT_SUMMARYFILE)"
LOG_FILENAME="$OUTPUT_FOLDER/cleanup.log"
touch $LOG_FILENAME

{
    APPLICATION_NAME="ingress"
    NAMESPACE_NAME="ingress-basic"
    TEST_FOLDER="/home/$USER_NAME/$APPLICATION_NAME"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Inner Variables"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "APPLICATION_NAME           : $APPLICATION_NAME"
    log_level -i "NAMESPACE_NAME             : $NAMESPACE_NAME"
    log_level -i "TEST_FOLDER                : $TEST_FOLDER"
    log_level -i "------------------------------------------------------------------------"
    
    # Cleanup.
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "kubectl delete namespace $NAMESPACE_NAME || true"
    # Wait for Namespace to be deleted.
    
    releaseNames=$(ssh -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "helm ls -d -r --all-namespaces | grep 'deployed\(.*\)$APPLICATION_NAME' | grep -Eo '^[a-z0-9,-]+\w+' || true")
    if [ -z "$releaseNames" ]; then
        log_level -w "No deployment found."
    else
        for releaseName in $releaseNames
        do
            releaseName=$(echo "$releaseName" | tr -d '"')
            log_level -i "Removing helm deployment($releaseName)"
            ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "helm delete --purge $releaseName"
        done 
        log_level -i "Wait for 30s for all pods to be deleted and removed."
        sleep 30s
    fi

    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo rm -rf $TEST_FOLDER;"
    if [[ $? != 0 ]]; then
        printf '{"result":"%s","error":"%s"}\n' "failed" "App($APPLICATION_NAME) cleanup was not successfull" > $OUTPUT_SUMMARYFILE
    else
        printf '{"result":"%s"}\n' "pass" > $OUTPUT_SUMMARYFILE
    fi

    # Create result file, even if script ends with an error
    #trap final_changes EXIT
} 2>&1 | tee $LOG_FILENAME