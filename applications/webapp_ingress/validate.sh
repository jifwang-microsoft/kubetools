#!/bin/bash 

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
    APPLICATION_NAME="ingress"
    TEST_FOLDER="/home/$USER_NAME/$APPLICATION_NAME"
    NAMESPACE_NAME="ingress-basic"
    CN_NAME="test.azurestack.com"    
    CERT_FILENAME="azs-ingress-tls.crt"
    SECRETKEY_FILEANME="azs-ingress-tls.key"
    MAX_INGRESS_COUNT=2
    MAX_INGRESS_SERVICE_COUNT=8
    log_level -i "------------------------------------------------------------------------"
    log_level -i "                Inner Variables"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "APPLICATION_NAME          : $APPLICATION_NAME"
    log_level -i "CERT_FILENAME             : $CERT_FILENAME"
    log_level -i "CN_NAME                   : $CN_NAME"
    log_level -i "MAX_INGRESS_COUNT         : $MAX_INGRESS_COUNT"
    log_level -i "MAX_INGRESS_SERVICE_COUNT : $MAX_INGRESS_SERVICE_COUNT"
    log_level -i "NAMESPACE_NAME            : $NAMESPACE_NAME"
    log_level -i "SECRETKEY_FILEANME        : $SECRETKEY_FILEANME"
    log_level -i "TEST_FOLDER               : $TEST_FOLDER"
    log_level -i "------------------------------------------------------------------------"
    
    # get external ip
    i=1
    FAILED_SERVICES=""
    FAILED_INGRESS_SERVERS=""
    
    log_level -i "Get all objects from given namespace."
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "kubectl get all -n $NAMESPACE_NAME"
    log_level -i "Get ingress details."
    ssh -t -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "kubectl get ingress -n $NAMESPACE_NAME -o json"

    while [ $i -le $MAX_INGRESS_COUNT ]; do
        ingressName=$APPLICATION_NAME-$i

        certificateFileName=$OUTPUT_FOLDER/$ingressName-$CERT_FILENAME
        secretkeyFileName=$OUTPUT_FOLDER/$ingressName-$SECRETKEY_FILEANME
        ipAddress=$(ssh -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "kubectl get services -n $NAMESPACE_NAME -o json | jq --arg release $ingressName --arg component 'controller' '.items[] | select(.metadata.labels.component == \$component) | select(.metadata.labels.release == \$release) | .status.loadBalancer.ingress[0].ip' | grep -oP '(\d{1,3}\.){1,3}\d{1,3}' || true")
        if [ -z "$ipAddress" ]; then
            log_level -e "External IP not found for ingress $ingressName."
            FAILED_INGRESS_SERVERS="$FAILED_INGRESS_SERVERS$ingressName,"
            let i=i+1
            continue            
        fi
        ipAddress=$(echo "$ipAddress" | tr -d '"')
        ipAddress="${ipAddress## }"
        ipAddress="${ipAddress%% }"

        log_level -i "IP address of $ingressName is $ipAddress"
        cnName=$(ssh -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cname=\$(kubectl get ingress -n $NAMESPACE_NAME -o json | jq --arg name $ingressName '.items[] | select(.metadata.name == \$name) | .spec.rules[0].host'); echo \$cname")
        if [ -z "$cnName" ]; then
            log_level -e "CN Name can not be found for ingress($ingressName)."
            FAILED_INGRESS_SERVERS="$FAILED_INGRESS_SERVERS$ingressName,"
            let i=i+1
            continue
        fi
        cnName=$(echo "$cnName" | tr -d '"')
        cnName="${cnName## }"
        cnName="${cnName%% }"
        log_level -i "CN Name of $ingressName is $cnName"
        serviceNames=$(ssh -i $IDENTITY_FILE $USER_NAME@$MASTER_IP "cname=\$(kubectl get ingress -n $NAMESPACE_NAME -o json | jq --arg name $ingressName '.items[] | select(.metadata.name == \$name) | .spec.rules[0].http.paths[] | .backend.serviceName'); echo \$cname")
        if [ -z "$serviceNames" ]; then
            log_level -e "No services found for ingress($ingressName)."
            FAILED_INGRESS_SERVERS="$FAILED_INGRESS_SERVERS$ingressName,"
            let i=i+1
            continue
        fi

        for serviceName in $serviceNames
        do
            pathName=$(echo "$serviceName" | tr -d '"')
            pathName="${pathName## }"
            pathName="${pathName%% }"
            log_level -i "Communicating to service($pathName) using below command."
            log_level -i "curl -key $secretkeyFileName --cacert $certificateFileName -k --resolve ${cnName}:443:${ipAddress} https://${cnName}/${pathName}"
            j=0
            while [ $j -lt 10 ]; do
                applicationState=$(curl -key $secretkeyFileName --cacert $certificateFileName -k --resolve ${cnName}:443:${ipAddress} https://${cnName}/${pathName}; if [ $? -eq 0 ]; then echo "HTTP OK 200"; fi;)
                log_level -i "Curl reply is: $applicationState"
                if [ -z "$applicationState" ]; then
                    log_level -e "Not able to communicate service: $pathName for ingress($ingressName) we will retry again."
                else
                    log_level -i "Able to communicate service: ${pathName}"
                    break
                fi
                sleep 15s
                let j=j+1
            done

            if [ -z "$applicationState" ]; then
                FAILED_SERVICES="$FAILED_SERVICES,$pathName"
            fi
        done

        let i=i+1
    done

    if [ -z "$FAILED_INGRESS_SERVERS" ]; then
        if [ -z "$FAILED_SERVICES" ]; then
            printf '{"result":"%s"}\n' "pass" > $OUTPUT_SUMMARYFILE
        else
            printf '{"result":"%s","error":"%s"}\n' "failed" "Communication to ingress services($FAILED_SERVICES) was not successfull." > $OUTPUT_SUMMARYFILE
        fi
    else
        printf '{"result":"%s","error":"%s"}\n' "failed" "Communication to ingress server ($FAILED_INGRESS_SERVERS) was not successfull." > $OUTPUT_SUMMARYFILE
    fi
    # Create result file, even if script ends with an error
    #trap final_changes EXIT
    
} 2>&1 | tee $LOG_FILENAME