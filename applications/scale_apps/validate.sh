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
    APPLICATION_NAME="scale_apps"
    TEST_DIRECTORY="/home/$USER_NAME/$APPLICATION_NAME"
    EXPECTED_RESULT_FILENAME="expectedresults.json"
    EXPECTED_RESULT_FILE=$SCRIPT_FOLDER/$EXPECTED_RESULT_FILENAME
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
    
    result="pass"
    if [[ "$NGINX_PVC_TEST" == "true" ]]; then
        expectedNginxPvcPodCount=`cat "$EXPECTED_RESULT_FILE" | jq --arg v "NGINX_PVC_TEST_POD_COUNT" '.testSuite[] | select(.testname == $v) | .value' | sed -e 's/^"//' -e 's/"$//'`
        expectedNginxPvcCount=`cat "$EXPECTED_RESULT_FILE" | jq --arg v "NGINX_PVC_TEST_PVC_COUNT" '.testSuite[] | select(.testname == $v) | .value' | sed -e 's/^"//' -e 's/"$//'`
        nginxPvcPodName=$(ssh -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "kubectl get pods -o=name | sed 's/^.\{4\}//' | grep web")
        
        for pod in $nginxPvcPodName
        do
            podName=$(echo $pod|tr -d '\r')
            #write to pvc
            i=0
            while [ $i -lt 10 ]; do
                log_level -i "Write to pvc on pod :$podName"
                ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "kubectl exec $podName -- sh -c 'cp /etc/hostname /usr/share/nginx/html/index.html'"
                #validate write operation
                podHostName=$(ssh -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "kubectl exec -it $podName -- curl localhost")

                if [[ "$podHostName" != "$podName" ]]; then
                    log_level -i "Disk write validation failed. Pod Hostname:$podName, disk  Hostname:$podHostName"
                else
                    log_level -i "Disk write validation passed for pod Hostname:$podName, disk  Hostname:$podHostName"
                    break
                fi
                sleep 30s
                let i=i+1
            done

            if [[ "$podHostName" != "$podName" ]]; then
                result="failed"
                log_level -e "Disk write validation failed for Pod :$podName"
            else
                log_level -i "Disk write validation passed for pod Hostname:$podName, disk  Hostname:$podHostName"
            fi
        done
        
        # Check if nginx_pvc_test pods are running and up
        i=0
        while [ $i -lt 20 ]; do
            nginxPvcPodCount=$(ssh -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo kubectl get pods --field-selector status.phase=Running,metadata.namespace=default | grep 'web' > $TEST_DIRECTORY/nginx_pvc_pods.txt; wc -l $TEST_DIRECTORY/nginx_pvc_pods.txt | cut -d' ' -f1")
            if [[ "$nginxPvcPodCount" == "$expectedNginxPvcPodCount" ]]; then
                break
            else
                log_level -i "nginx_pvc_test pods's count($nginxPvcPodCount) are not matching the expected count($expectedNginxPvcPodCount). Trying again."
            fi
            
            sleep 30s
            let i=i+1
        done
        
        if [[ "$nginxPvcPodCount" != "$expectedNginxPvcPodCount" ]]; then
            result="failed"
            log_level -e "PVC pods's count($nginxPvcPodCount) are not matching expected count($expectedNginxPvcPodCount)."
        else
            log_level -i "PVC pods's count($nginxPvcPodCount) are matching expected count($expectedNginxPvcPodCount)."
        fi
        
        i=0
        while [ $i -lt 20 ]; do
            nginxPvcCount=$(ssh -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo kubectl get pvc --field-selector metadata.namespace=default | grep 'Bound' | grep 'www-web' > $TEST_DIRECTORY/nginx_pvc.txt; wc -l $TEST_DIRECTORY/nginx_pvc.txt | cut -d' ' -f1")
            if [[ "$nginxPvcCount" == "$expectedNginxPvcCount" ]]; then
                break
            else
                log_level -i "nginx pods's count($nginxPvcCount) are not matching the expected count($expectedNginxPvcCount). Trying again."
            fi
            
            sleep 30s
            let i=i+1
        done
        
        if [[ "$nginxPvcCount" != "$expectedNginxPvcCount" ]]; then
            result="failed"
            log_level -e "Nginx pods's count($nginxPvcCount) are not matching the expected count($expectedNginxPvcCount)."
        else
            log_level -i "Nginx pods's count($nginxPvcCount) matched expected count($expectedNginxPvcCount)."
        fi
    fi
    
    if [[ "$NGINX_APP_TEST" == "true" ]]; then
        serviceNames=$(ssh -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo kubectl get svc -o=name | sed 's/^.\{8\}//' | grep nginxservice*")
        
        for svc in $serviceNames
        do
            SERVICE_NAME=$(echo $svc|tr -d '\r')
            APPLICATION_NAME="nginxtest"
            
            log_level -i "Get public IP address for service($SERVICE_NAME)."
            check_app_has_externalip $IDENTITY_FILE \
            $USER_NAME \
            $MASTER_IP \
            $APPLICATION_NAME \
            $SERVICE_NAME
            
            if [[ $? != 0 ]]; then
                result="failed"
                log_level -e "Public IP address did not get assigned for service($SERVICE_NAME)."
            else
                check_app_listening_at_externalip $IP_ADDRESS
                if [[ $? != 0 ]]; then
                    result="failed"
                    log_level -e "Not able to communicate to public IP($IP_ADDRESS) for service($SERVICE_NAME)."
                fi
            fi
        done
        
        expectedNginxPodCount=`cat "$EXPECTED_RESULT_FILE" | jq --arg v "NGINX_TEST_POD_COUNT" '.testSuite[] | select(.testname == $v) | .value' | sed -e 's/^"//' -e 's/"$//'`
        
        i=0
        while [ $i -lt 20 ]; do
            nginxPodCount=$(ssh -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo kubectl get pods --field-selector status.phase=Running,metadata.namespace=default | grep 'nginx-scale' > $TEST_DIRECTORY/nginx_pods.txt; wc -l $TEST_DIRECTORY/nginx_pods.txt | cut -d' ' -f1")
            if [[ "$nginxPodCount" == "$expectedNginxPodCount" ]]; then
                break
            else
                log_level -e "nginx pods's count($nginxPodCount) are not matching the expected count($expectedNginxPodCount). Trying again to validate the count."
            fi
            sleep 30s
            let i=i+1
        done
        
        if [[ "$nginxPodCount" != "$expectedNginxPodCount" ]]; then
            result="failed"
            log_level -e "Nginx pods's count($nginxPodCount) are not matching the expected count($expectedNginxPodCount)."
        else
            log_level -i "Nginx pods's count($nginxPodCount) matched expected count($expectedNginxPodCount)."
        fi
    fi
    
    if [[ "$result" == "failed" ]]; then
        ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "sudo kubectl get all -o wide"
        printf '{"result":"%s","error":"%s"}\n' "$result" "One or more validation failed. Please refer to log file for more details."> $OUTPUT_SUMMARYFILE
        exit 1
    else
        result="pass"
        printf '{"result":"%s"}\n' "$result" > $OUTPUT_SUMMARYFILE
    fi
    
    # Create result file, even if script ends with an error
    #trap final_changes EXIT
} 2>&1 | tee $LOG_FILENAME