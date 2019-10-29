#!/bin/bash -e

FILE_NAME=$0
SCRIPT_DIRECTORY="$(dirname $FILE_NAME)"

COMMON_SCRIPT_FILENAME="common.sh"
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

OUTPUT_FOLDER="$(dirname $OUTPUT_SUMMARYFILE)"
LOG_FILENAME="$OUTPUT_FOLDER/validate.log"
touch $LOG_FILENAME

{
    APPLICATION_NAME="aspnet"
    TEST_DIRECTORY="/home/$USER_NAME/$APPLICATION_NAME"
    DEPLOYMENT_ASPNET_FILE="aspnet.yaml"
    DEPLOYMENT_ASPNET_PVC_FILE="aspnet_pvc.yaml"
    ASPNET_SERVICENAME="aspnetappservice"
    ASPNET_APPNAME="aspnetapp"
    ASPNET_PVC_LABEL="aspnetpvc"

    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Inner Variables"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "APPLICATION_NAME           : $APPLICATION_NAME"    
    log_level -i "ASPNET_APPNAME             : $ASPNET_APPNAME"
    log_level -i "ASPNET_PVC_LABEL           : $ASPNET_PVC_LABEL"
    log_level -i "ASPNET_SERVICENAME         : $ASPNET_SERVICENAME"
    log_level -i "DEPLOYMENT_ASPNET_FILE     : $DEPLOYMENT_ASPNET_FILE"
    log_level -i "DEPLOYMENT_ASPNET_PVC_FILE : $DEPLOYMENT_ASPNET_PVC_FILE"
    log_level -i "TEST_DIRECTORY             : $TEST_DIRECTORY"
    log_level -i "------------------------------------------------------------------------"
    
    result="pass"
    replicaCount=$(cat $SCRIPT_DIRECTORY/$DEPLOYMENT_ASPNET_PVC_FILE | grep replicas | cut -d':' -f2 | xargs |  cut -d' ' -f1)
    i=0
    while [ $i -lt 20 ]; do
        pvcPodCount=$(ssh -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "kubectl get pods --field-selector status.phase=Running,metadata.namespace=default | grep '$ASPNET_PVC_LABEL*' > $TEST_DIRECTORY/pvc_pods.txt; wc -l $TEST_DIRECTORY/pvc_pods.txt | cut -d' ' -f1")
        if [[ "$pvcPodCount" == "$replicaCount" ]]; then
            log_level -i "Pods's count($pvcPodCount) matched expected count($replicaCount)."
            break
        else
            log_level -i "Pods running count($pvcPodCount) are not matching the expected count($replicaCount). Trying again."
        fi        
        sleep 30s
        let i=i+1
    done
    
    if [[ "$pvcPodCount" != "$replicaCount" ]]; then
        result="failed"
        log_level -e "PVC pods running count($pvcPodCount) are not matching expected count($replicaCount)."
    else
        log_level -i "PVC pods running count($pvcPodCount) matched expected count($replicaCount)."
    fi
    
    # Validation of IP address and multiple replica count for ASPnet application.
    replicaCount=$(cat $SCRIPT_DIRECTORY/$DEPLOYMENT_ASPNET_FILE | grep replicas | cut -d':' -f2 | xargs |  cut -d' ' -f1)
    i=0
    while [ $i -lt 20 ]; do
        podCount=$(ssh -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "kubectl get pods --field-selector status.phase=Running,metadata.namespace=default | grep '$ASPNET_APPNAME*' > $TEST_DIRECTORY/pods.txt; wc -l $TEST_DIRECTORY/pods.txt | cut -d' ' -f1")
        if [[ "$podCount" == "$replicaCount" ]]; then
            log_level -i "Pods's count($podCount) matched expected count($replicaCount)."
            break
        else
            log_level -e "Pods's count($podCount) are not matching the expected count($replicaCount). Trying again to validate the count."
        fi
        
        sleep 60s
        let i=i+1
    done
    
    if [[ "$podCount" != "$replicaCount" ]]; then
        result="failed"
        log_level -e "Pods's count($podCount) didnot matched expected count($replicaCount)."
    else
        check_app_has_externalip $IDENTITY_FILE \
        $USER_NAME \
        $MASTER_IP \
        $APPLICATION_NAME \
        $ASPNET_SERVICENAME
        
        if [[ $? != 0 ]]; then
            result="failed"
            log_level -e "Not able to get public IP address for service($ASPNET_SERVICENAME)."
        else
            check_app_listening_at_externalip $IP_ADDRESS
            if [[ $? != 0 ]]; then
                result="failed"
                log_level -e "Not able to communicate to public IP address($IP_ADDRESS) for service($ASPNET_SERVICENAME)."
            fi
        fi
    fi

    if [[ "$result" == "failed" ]]; then
        ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "kubectl get all -o wide"
        printf '{"result":"%s","error":"%s"}\n' "$result" "One or more validation failed. Please refer to log file for more details."> $OUTPUT_SUMMARYFILE
        exit 1
    else
        result="pass"
        printf '{"result":"%s"}\n' "$result" > $OUTPUT_SUMMARYFILE
    fi
    
    # Create result file, even if script ends with an error
    #trap final_changes EXIT
} 2>&1 | tee $LOG_FILENAME