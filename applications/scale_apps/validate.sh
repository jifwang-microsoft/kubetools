#!/bin/bash -e

FILENAME=$0
SCRIPT_DIRECTORY="$(dirname $FILE_NAME)"

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
    log_level -i "------------------------------------------------------------------------"
    log_level -i "Input Parameters"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "IDENTITY_FILE         : $IDENTITY_FILE"
    log_level -i "MASTER_IP             : $MASTER_IP"
    log_level -i "OUTPUT_SUMMARYFILE    : $OUTPUT_SUMMARYFILE"
    log_level -i "USER_NAME             : $USER_NAME"
    log_level -i "------------------------------------------------------------------------"
    
    APPLICATION_NAME="scale_apps"
    TEST_DIRECTORY="/home/$USER_NAME/$APPLICATION_NAME"
    EXPECTED_RESULT_FILENAME="expectedresults.json"
    EXPECTED_RESULT_FILE=$SCRIPT_DIRECTORY/$EXPECTED_RESULT_FILENAME
    NGINX_PVC_TEST=true
    NGINX_APP_TEST=true

    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Inner Variables"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "APPLICATION_NAME         : $APPLICATION_NAME"
    log_level -i "EXPECTED_RESULT_FILE     : $EXPECTED_RESULT_FILE"
    log_level -i "EXPECTED_RESULT_FILENAME : $EXPECTED_RESULT_FILENAME"
    log_level -i "NGINX_APP_TEST           : $NGINX_APP_TEST"
    log_level -i "NGINX_PVC_TEST           : $NGINX_PVC_TEST"
    log_level -i "TEST_DIRECTORY           : $TEST_DIRECTORY"
    log_level -i "------------------------------------------------------------------------"

    # INSTALL PREREQUISITE

    apt_install_jq $OUTPUT_DIRECTORY
    if [[ $? != 0 ]]; then
        log_level -e "Install of jq was not successfull."
        printf '{"result":"%s","error":"%s"}\n' "failed" "Install of JQ was not successfull." > $OUTPUT_SUMMARYFILE
        exit 1
    fi

    if [[ $NGINX_PVC_TEST ]]; then
        expectedNginxPvcPodCount=`cat "$EXPECTED_RESULT_FILE" | jq --arg v "NGINX_PVC_TEST_POD_COUNT" '.testSuite[] | select(.testname == $v) | .value' | sed -e 's/^"//' -e 's/"$//'`
        expectedNginxPvcCount=`cat "$EXPECTED_RESULT_FILE" | jq --arg v "NGINX_PVC_TEST_PVC_COUNT" '.testSuite[] | select(.testname == $v) | .value' | sed -e 's/^"//' -e 's/"$//'`
    
        # Check if nginx_pvc_test pods are running and up
        nginxPvcPodCount=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo kubectl get pods --field-selector status.phase=Running,metadata.namespace=default | grep 'web*' > nginx_pvc_pods.txt; wc -l nginx_pvc_pods.txt ")
        if [ $nginxPvcPodCount -ne $expectedNginxPvcPodCount ]; then
            result="failed"
            log_level -e "nginx_pvc_test pods's count are not matching the expected count." "$nginxPvcPodCount" "$expectedNginxPvcPodCount"
        fi
        nginxPvcCount=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo kubectl get pvc --field-selector metadata.namespace=default | grep 'Bound' | grep 'www-web*' > nginx_pvc.txt; wc -l nginx_pvc.txt ")
        if [ $nginxPvcCount -ne $expectedNginxPvcCount ]; then
            result="failed"
            log_level -e "nginx pods's count are not matching the expected count." "$nginxPvcCount" "$expectedNginxPvcCount"
        fi    
    fi

    if [[ $NGINX_APP_TEST ]]; then
        expectedNginxPodCount=`cat "$EXPECTED_RESULT_FILE" | jq --arg v "NGINX_TEST_POD_COUNT" '.testSuite[] | select(.testname == $v) | .value' | sed -e 's/^"//' -e 's/"$//'`

        nginxPodCount=$(ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo kubectl get pods --field-selector status.phase=Running,metadata.namespace=default | grep 'nginx-scale*' > nginx_pods.txt; wc -l nginx_pods.txt ")
        if [ $nginxPodCount -ne $expectedNginxPodCount ]; then
            result="failed"
            log_level -e "nginx pods's count are not matching the expected count." "$nginxPodCount" "$expectedNginxPodCount"
        fi
    fi

    if [[ $result == "failed" ]]; then
       ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo kubectl get all -o wide"
       printf '{"result":"%s","error":"%s","CurrentPvcPodCount":"%s","ExpectedPvcPodCount":"%s","CurrentPvcCount":"%s","ExpectedPvcCount":"%s",,"CurrentPodCount":"%s","ExpectedPodCount":"%s"}\n' "$result" "One of the count are not matching the expected count." "$nginxPvcPodCount" "$expectedNginxPvcPodCount" "$nginxPodCount" "$expectedNginxPodCount" "$nginxPvcCount" "$expectedNginxPvcCount"> $OUTPUT_SUMMARYFILE
       exit 1
    else
        result="pass"
        printf '{"result":"%s"}\n' "$result" > $OUTPUT_SUMMARYFILE
    fi
    
    # Create result file, even if script ends with an error
    #trap final_changes EXIT
} 2>&1 | tee $LOG_FILENAME