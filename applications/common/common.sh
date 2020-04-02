#!/bin/bash -e

log_level() {
    case "$1" in
        -e)
            echo "$(date) [Err]  " ${@:2}
        ;;
        -w)
            echo "$(date) [Warn] " ${@:2}
        ;;
        -i)
            echo "$(date) [Info] " ${@:2}
        ;;
        *)
            echo "$(date) [Debug] " ${@:2}
        ;;
    esac
}

print_usage() {
    echo "      Usage:"
    echo "      $FILENAME --identity-file id_rsa --master 192.168.102.34 --user azureuser --output-file c:/test/output.json"
    echo ""
    echo "            -i, --identity-file                         RSA Private Key file to connect master VM, it starts with -----BEGIN RSA PRIVATE KEY-----"
    echo "            -m, --master                                Public ip of master VM."
    echo "            -u, --user                                  User Name to be used to connect master VM."
    echo "            -o, --output-file                           Json summary file providing result status of the deployment."
    exit 1
}

parse_commandline_arguments() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -i | --identity-file)
                IDENTITY_FILE="$2"
            ;;
            -m | --master)
                MASTER_IP="$2"
            ;;
            -u | --user)
                USER_NAME="$2"
            ;;
            -o | --output-file)
                OUTPUT_SUMMARYFILE="$2"
            ;;
            -c | --configFile)
                CONFIG_FILE="$2"
            ;;
            *)
                echo ""
                echo "Incorrect parameter $1"
                echo ""
                printUsage
            ;;
        esac
        
        if [ "$#" -ge 2 ]; then
            shift 2
        else
            shift
        fi
    done
}

download_file_locally() {
    local gitRepository=$1
    local gitBranch=$2
    local folderPath=$3
    local outputFolder=$4
    local fileName=$5
    
    if [ ! -f $outputFolder/$fileName ]; then
        # Download file locally.
        curl -o $outputFolder/$fileName \
        https://raw.githubusercontent.com/$gitRepository/$gitBranch/$folderPath/$fileName
        if [ ! -f $outputFolder/$fileName ]; then
            log_level -e "File($fileName) failed to download."
            return 1
        fi
    fi
    log_level -i "Converting parameters file($outputFolder/$fileName) to unix format"
    dos2unix $outputFolder/$fileName
    
    return 0
}

install_helm_chart() {
    local identityFile=$1
    local userName=$2
    local connectionIP=$3
    local testFolder=$4
    local fileName=$5
    
    log_level -i "=========================================================================="
    log_level -i "Installing Helm chart."
    ssh -t -i $identityFile \
    $userName@$connectionIP \
    "sudo chmod 744 $testFolder/$fileName; cd $testFolder; ./$fileName;"
    helmVersion=$(ssh -i $identityFile $userName@$connectionIP "helm version")
    if [ -z "$helmVersion" ]; then
        log_level -e "Helm install was not successfull."
        return 1
    fi
    
    log_level -i "Helm got installed successfully. Helm version is: $helmVersion"

    log_level -i "Adding azs-ecs repo to helm."
    ssh -t -i $identityFile $userName@$connectionIP "helm repo add azs-ecs https://raw.githubusercontent.com/msazurestackworkloads/helm-charts/master/repo/"
    log_level -i "azs-ecs repo added to helm."

    return 0
}

install_helm_app() {
    local identityFile=$1
    local userName=$2
    local connectionIP=$3
    local appName=$4
    local namespace=$5
    
    log_level -i "Installing App($appName)."
    # Install Helm passed app
    if [[ -z $namespace ]]; then
        ssh -t -i $identityFile \
        $userName@$connectionIP \
        "helm install azs-ecs/$appName --generate-name"
    else
        ssh -t -i $identityFile \
        $userName@$connectionIP \
        "helm install azs-ecs/$appName --namespace $namespace --generate-name"
    fi
    appReleaseName=$(ssh -i $identityFile $userName@$connectionIP "helm ls -d -r --all-namespaces | grep 'deployed\(.*\)$appName' | grep -Eo '^[a-z,-]+\w+'")
    if [ -z "$appReleaseName" ]; then
        log_level -e "App($appName) deployment failed using Helm."
        return 1
    fi
    
    log_level -i "Helm deployed app($appName) with deployment name as: $appReleaseName."
    return 0
}

check_app_pod_status() {
    local identityFile=$1
    local userName=$2
    local connectionIP=$3
    local appName=$4
    local appStatus=$5
    local namespace=$6
    
    # Check if pod is up and running
    log_level -i "Validate if pod for $appName app is created and running."
    i=0
    while [ $i -lt 20 ]; do
        if [[ -z $namespace ]]; then
            appPodstatus=$(ssh -i $identityFile $userName@$connectionIP "sudo kubectl get pods --selector $appName | grep '$appStatus' || true")
        else
            appPodstatus=$(ssh -i $identityFile $userName@$connectionIP "sudo kubectl get pods --namespace $namespace | grep '$appStatus' || true")
        fi

        if [ -z "$appPodstatus" ]; then
            log_level -i "Pod is not in expected state($appStatus). We we will retry after some time."
            sleep 30s
        else
            log_level -i "Pod status is in expected state: $appPodstatus."
            break
        fi
        let i=i+1
    done
    
    if [ -z "$appPodstatus" ]; then
        log_level -e "Validation failed because $appName pod is not in state $appStatus."
        return 1
    fi
    
    log_level -i "$appName pod is in expected state($appStatus)."
    return 0
}

check_app_has_externalip() {
    local identityFile=$1
    local userName=$2
    local connectionIP=$3
    local appName=$4
    local serviceName=$5
    local namespace=$6
    # Check if App got external IP
    log_level -i "Validate if service($serviceName) got external IP address."
    i=0
    while [ $i -lt 20 ]; do
        if [[ -z $namespace ]]; then
            IP_ADDRESS=$(ssh -i $identityFile $userName@$connectionIP "sudo kubectl get services $serviceName -o=custom-columns=NAME:.status.loadBalancer.ingress[0].ip | grep -oP '(\d{1,3}\.){1,3}\d{1,3}' || true")
        else
            IP_ADDRESS=$(ssh -i $identityFile $userName@$connectionIP "sudo kubectl get services -n $namespace $serviceName -o=custom-columns=NAME:.status.loadBalancer.ingress[0].ip | grep -oP '(\d{1,3}\.){1,3}\d{1,3}' || true")
        fi
        
        log_level -i $IP_ADDRESS
        if [ -z "$IP_ADDRESS" ]; then
            log_level -i "External IP is not assigned. We we will retry after some time."
            sleep 30s
        else
            break
        fi
        let i=i+1
    done
    
    if [ -z "$IP_ADDRESS" ]; then
        log_level -e "External IP not found for $serviceName."
        return 1
    fi
    
    log_level -i "Found external IP address($IP_ADDRESS) assign to $serviceName."
    return 0
}

check_app_listening_at_externalip() {
    local externalIp=$1
    i=0
    while [ $i -lt 20 ]; do
        portalState=$(
            curl --connect-timeout 30 http://${externalIp}
            if [ $? -eq 0 ]; then echo "HTTP OK 200"; fi
        )
        if [ -z "$portalState" ]; then
            log_level -i "Endpoint communication validation failed. We we will retry after some time."
            sleep 30s
        else
            break
        fi
        let i=i+1
    done
    
    if [ -z "$portalState" ]; then
        log_level -e "Not able to communicate web endpoint($externalIp). Please check if app is up and running."
        return 1
    fi
    
    log_level -i "Able to communicate web endpoint($portalState)"
    return 0
    
}

check_helm_app_release_cleanup() {
    
    local identityFile=$1
    local userName=$2
    local connectionIP=$3
    local appName=$4
    
    # Rechecking to make sure deployment cleanup done successfully.
    i=0
    while [ $i -lt 20 ]; do
        releaseName=$(ssh -i $identityFile $userName@$connectionIP "helm ls -d -r --all-namespaces | grep 'deployed\(.*\)$appName' | grep -Eo '^[a-z,-]+\w+' || true")
        if [ ! -z "$releaseName" ]; then
            log_level -i "Removal of app($appName) with release name($releaseName) is in progress."
            sleep 30s
        else
            break
        fi
        let i=i+1
    done
    
    if [ ! -z "$releaseName" ]; then
        log_level -e "Removal of app($releaseName) failed."
        return 1
    fi
    
    log_level -i "App($appName) removed successfully."
    return 0
}

perf_process_net_files() {
    local directoryName=$1
    local outputFileName=$2
    local FILENAME_LIST=$(ls $directoryName/*.csv)
    declare -A RESULT_MAP
    local testCaseCount=0
    while [ $testCaseCount -lt 14 ]; do
        RESULT_MAP[$testCaseCount]=0.00
        let testCaseCount=testCaseCount+1
    done
    local iteration=0
    for resultFileName in $FILENAME_LIST; do
        log_level -i "Processing file $resultFileName."
        testCaseCount=0
        while IFS= read -r line; do
            currentLine=$(echo $line | tr -d " ")
            currentLine=$(echo $currentLine | tr "," " ")
            currentLine=($currentLine)
            if [[ $testCaseCount != 0 ]]; then
                RESULT_MAP[$testCaseCount]=$(echo ${RESULT_MAP[$testCaseCount]}+${currentLine[1]} | bc)
            fi
            let testCaseCount=testCaseCount+1
        done <$resultFileName
        let iteration=iteration+1
    done
    
    testCaseCount=1
    while [ $testCaseCount -lt 14 ]; do
        RESULT_MAP[$testCaseCount]=$(echo ${RESULT_MAP[$testCaseCount]}/$iteration | bc)
        let testCaseCount=testCaseCount+1
    done
    json_string='{ "testSuite": [ {"testname":"Iperf_TCP_SameVM_Pod_IP", "value":"%s" },{"testname":"Iperf_TCP_SameVM_Virtual_IP", "value":"%s"},'
    json_string=$json_string'{"testname":"Iperf_TCP_RemoteVM_Pod_IP", "value":"%s"},{"testname":"Iperf_TCP_RemoteVM_Virtual_IP", "value":"%s"},'
    json_string=$json_string'{"testname":"Iperf_TCP_Hairpin_Pod_IP", "value":"%s"},{"testname":"Iperf_UDP_SameVM_Pod_IP", "value":"%s"},'
    json_string=$json_string'{"testname":"Iperf_UDP_SameVM_Virtual_IP", "value":"%s"},{"testname":"Iperf_UDP_RemoteVM_Pod_IP", "value":"%s"},'
    json_string=$json_string'{"testname":"Iperf_UDP_RemoteVM_Virtual_IP", "value":"%s"},{"testname":"NetPerf_SameVM_Pod_IP", "value":"%s"},'
    json_string=$json_string'{"testname":"NetPerf_SameVM_Virtual_IP", "value":"%s"},{"testname":"NetPerf_RemoteVM_Pod_IP", "value":"%s"},'
    json_string=$json_string'{"testname":"NetPerf_RemoteVM_Virtual_IP", "value":"%s"} ] }'
    printf "$json_string" "${RESULT_MAP[1]}" "${RESULT_MAP[2]}" \
    "${RESULT_MAP[3]}" "${RESULT_MAP[4]}" \
    "${RESULT_MAP[5]}" "${RESULT_MAP[6]}" \
    "${RESULT_MAP[7]}" "${RESULT_MAP[8]}" \
    "${RESULT_MAP[9]}" "${RESULT_MAP[10]}" \
    "${RESULT_MAP[11]}" "${RESULT_MAP[12]}" \
    "${RESULT_MAP[13]}" >$directoryName/$outputFileName
}

apt_install_jq() {
    local JQ_INSTALL_LINK="https://github.com/stedolan/jq/releases/download/jq-1.6/jq-win64.exe"
    cd $1
    log_level -i "Install jq on local machine."
    curl -O -L $JQ_INSTALL_LINK
    if [ ! -f jq-win64.exe ]; then
        log_level -e "File(jq-win64.exe) failed to download."
        return 1
    fi
    mv jq-win64.exe /usr/bin/jq
    return 0
}

validate_testcase_result() {
    local resultFileName=$1
    local expectedResultFileName=$2
    local testCaseName=$3
    
    TEST_RESULT=$(cat "$resultFileName" | jq --arg v "$testCaseName" '.testSuite[] | select(.testname == $v) | .value' | sed -e 's/^"//' -e 's/"$//')
    TESTCASE_RANGE_VALUE=$(cat "$expectedResultFileName" | jq --arg v "$testCaseName" '.testSuite[] | select(.testname == $v) | .value' | sed -e 's/^"//' -e 's/"$//')
    CONDITION_TYPE=$(cat "$expectedResultFileName" | jq --arg v "$testCaseName" '.testSuite[] | select(.testname == $v) | .conditionType' | sed -e 's/^"//' -e 's/"$//')
    TESTCASE_STATUS="fail"
    
    if [[ -z $TESTCASE_RANGE_VALUE ]] || [[ -z $TEST_RESULT ]]; then
        log_level -e "Empty values found for (TEST_RESULT=$TEST_RESULT) with (TESTCASE_RANGE_VALUE=$TESTCASE_RANGE_VALUE)"
    else
        log_level -i "Comparing $TEST_RESULT with $TESTCASE_RANGE_VALUE with condition as $CONDITION_TYPE."
        if [[ -z "$CONDITION_TYPE" ]] || [[ "$CONDITION_TYPE" == "gt" ]]; then
            log_level -i "Comparing values for greater case."
            value=$(awk -v RESULT=$TEST_RESULT -v CASE_RANGE_VALUE=$TESTCASE_RANGE_VALUE 'BEGIN {print (RESULT >= CASE_RANGE_VALUE)}')
            log_level -i "Comparison result value is $value."
            if [[ $value != 0 ]]; then
                TESTCASE_STATUS="pass"
                log_level -i "Test case \"$testCaseName\" passed with value $TEST_RESULT as it is greater than $TESTCASE_RANGE_VALUE."
            fi
        else
            log_level -i "Comparing values for less than case."
            value=$(awk -v RESULT=$TEST_RESULT -v CASE_RANGE_VALUE=$TESTCASE_RANGE_VALUE 'BEGIN {print (RESULT <= CASE_RANGE_VALUE)}')
            log_level -i "Comparison result value is $value."
            if [[ $value != 0 ]]; then
                TESTCASE_STATUS="pass"
                log_level -i "Test case \"$testCaseName\" passed with value $TEST_RESULT as it is less than $TESTCASE_RANGE_VALUE."
            fi
        fi
    fi
    log_level -i "Comparison done now checking the status."
    if [ $TESTCASE_STATUS == "fail" ]; then
        FAILED_CASES="$FAILED_CASES,$testCaseName"
        log_level -e "Test case \"$testCaseName\" failed for value $TEST_RESULT in comparison with range value:$TESTCASE_RANGE_VALUE."
    fi
}

check_Kubernetes_events() {
    local expectedEventName=$1
    local objectName=$2
    local objectKind=$3
    i=0
    while [ $i -lt 50 ]; do
        kubeEvents=$(kubectl get events --field-selector involvedObject.kind==$objectKind -o json | jq --arg items "$objectName" '.items[] | select(.involvedObject.name == $items) | .reason' | grep $expectedEventName)
        if [ -z "$kubeEvents" ]; then
            log_level -i "$expectedEventName event has not reached for $objectName $objectKind."
            sleep 30s
        else
            break
        fi
        let i=i+1
    done
    
    if [ -z "$kubeEvents" ]; then
        log_level -e "$expectedEventName has not reached for $objectName $objectKind."
        return 1
    fi
    
    log_level -i "$expectedEventName event has reached for $objectName $objectKind."
    return 0
}

deploy_and_measure_event_time() {
    local deploymentFileName=$1
    local startEventName=$2
    local expectedEventName=$3
    local name=$4
    local objectKind=$5
    local waitTime=${6:-120}
    
    kubectl apply -f $deploymentFileName
    i=0
    while [ $i -lt 50 ]; do
        kubeEvents=$(kubectl get events --field-selector involvedObject.kind==$objectKind -o json | jq --arg items "$name" '.items[] | select(.involvedObject.name == $items) | .reason' | grep $expectedEventName)
        if [ -z "$kubeEvents" ]; then
            log_level -i "$expectedEventName event has not reached for $name $objectKind."
            sleep 10s
        else
            break
        fi
        let i=i+1
    done
    
    if [ -z "$kubeEvents" ]; then
        log_level -e "$expectedEventName has not reached for $name $objectKind."
        exit 1
    else
        kubeEvents=$(kubectl get events --field-selector involvedObject.kind==$objectKind -o json)
        log_level -i "$kubeEvents"
        startEventTime=$(echo $kubeEvents | jq --arg items "$startEventName" '.items[] | select(.reason == $items) | .firstTimestamp' | tail -1 | sed -e 's/^"//' -e 's/"$//')
        endEventTime=$(echo $kubeEvents | jq --arg items "$expectedEventName" '.items[] | select(.reason == $items) | .firstTimestamp' | tail -1 | sed -e 's/^"//' -e 's/"$//')
        startEventTime=$(date +%s -d $startEventTime)
        endEventTime=$(date +%s -d $endEventTime)
        let difference=$(echo "$endEventTime - $startEventTime" | bc)
        log_level -i "Event ($startEventName) started at $startEventTime and event ($expectedEventName) arrived at $endEventTime."
        log_level -i "Total time taken to reach from $startEventName to $expectedEventName event is $difference"
        sleep $waitTime
        json_string='{ "Time":"%s" }'
        printf "$json_string" "$difference" >$name.log
    fi
}

deploy_application() {
    local deploymentFileName=$1
    local expectedEventName=$2
    local deploymentName=$3
    local objectKind=$4
    local totalReplicaCount=$5
    
    if [[ -z $totalReplicaCount ]]; then
        $totalReplicaCount=1
    fi
    
    kubectl apply -f $deploymentFileName
    replicaCount=0
    deploymentStatus="pass"
    log_level -i "Validate deployment has all replica(count=$totalReplicaCount) in running state."
    
    if [[ "$objectKind" == "Pod" ]]; then
        while [ $replicaCount -lt $totalReplicaCount ]; do
            i=0
            name=$deploymentName-$replicaCount
            check_Kubernetes_events $expectedEventName $name $objectKind
            if [[ $? != 0 ]]; then
                log_level -e "Could not reach event($expectedEventName) for $name $objectKind."
                deploymentStatus="fail"
            fi
            
            let replicaCount=replicaCount+1
        done
        
        if [[ "$deploymentStatus" != "pass" ]]; then
            log_level -e "$expectedEventName has not reached for $deploymentName $objectKind with replica count $totalReplicaCount."
            exit 1
        fi
    else
        check_Kubernetes_events $expectedEventName $deploymentName $objectKind
        if [[ $? != 0 ]]; then
            log_level -e "Could not reach event($expectedEventName) for $deploymentName $objectKind."
            exit 1
        fi
    fi
}

cleanup_deployment() {
    local deploymentFileName=$1
    local waitTime=${2:-300}
    kubectl delete -f $deploymentFileName
    sleep 10s
    #Currently assume single PVC
    pvcName=$(kubectl get pvc -o json | jq '.items[] | .metadata.name' | sed -e 's/^"//' -e 's/"$//')
    if [ -z "$pvcName" ]; then
        log_level -i "No pvc found."
    else
        log_level -i "Delete pvc:$pvcName."
        kubectl delete pvc $pvcName
        sleep $waitTime
    fi
}

rename_string_infile() {
    local fileName=$1
    local findstring=$2
    local replaceString=$3
    
    file_contents=$(<$fileName)
    echo "${file_contents//$findstring/$replaceString}" >$fileName
}

process_perflog_files() {
    local directoryName=$1
    local outputFileName=$2
    local testCaseName=$3
    local fileNameStartwith=$4
    local FILENAME_LIST=$(ls $directoryName/$fileNameStartwith*.log)
    totalTimeTaken=0
    local iteration=0
    if [ -z "$FILENAME_LIST" ]; then
        log_level -i "No file found."
        exit 1
    else
        for resultFileName in $FILENAME_LIST; do
            log_level -i "Processing file $resultFileName."
            totalTime=$(cat $resultFileName | jq '.Time' | sed -e 's/^"//' -e 's/"$//')
            totalTimeTaken=$(echo $totalTimeTaken+$totalTime | bc)
            let iteration=iteration+1
        done
        averageTimeTaken=$(echo $totalTimeTaken/$iteration | bc)
        json_string='{ "testSuite": [ {"testname":"%s", "value":"%s" } ] }'
        printf "$json_string" "$testCaseName" "$averageTimeTaken" >$directoryName/$outputFileName
    fi
}

create_cert() {
    local crtFileName=$1
    local keyFileName=$2
    local cnName=$3
    local organizationName=$4
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -out $crtFileName -keyout $keyFileName -subj "/CN=$cnName/O=$organizationName"
}