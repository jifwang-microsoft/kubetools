#!/bin/bash -e

log_level()
{
    case "$1" in
        -e) echo "$(date) [Err]  " ${@:2}
        ;;
        -w) echo "$(date) [Warn] " ${@:2}
        ;;
        -i) echo "$(date) [Info] " ${@:2}
        ;;
        *)  echo "$(date) [Debug] " ${@:2}
        ;;
    esac
}

print_usage()
{
    echo "      Usage:"
    echo "      $FILENAME --identity-file id_rsa --master 192.168.102.34 --user azureuser --output-file c:/test/output.json"
    echo  ""
    echo "            -i, --identity-file                         RSA Private Key file to connect master VM, it starts with -----BEGIN RSA PRIVATE KEY-----"
    echo "            -m, --master                                Public ip of master VM."
    echo "            -u, --user                                  User Name to be used to connect master VM."
    echo "            -o, --output-file                           Json summary file providing result status of the deployment."
    exit 1
}

parse_commandline_arguments()
{
    while [[ "$#" -gt 0 ]]
    do
        case $1 in
            -i|--identity-file)
                IDENTITY_FILE="$2"
            ;;
            -m|--master)
                MASTER_IP="$2"
            ;;
            -u|--user)
                USER_NAME="$2"
            ;;
            -o|--output-file)
                OUTPUT_SUMMARYFILE="$2"
            ;;
            -c|--configFile)
                CONFIG_FILE="$2"
            ;;
            *)
                echo ""
                echo "Incorrect parameter $1"
                echo ""
                printUsage
            ;;
        esac
        
        if [ "$#" -ge 2 ]
        then
            shift 2
        else
            shift
        fi
    done
}

download_file_locally()
{
    local gitRepository=$1;
    local gitBranch=$2;
    local folderPath=$3;
    local outputFolder=$4;
    local fileName=$5;
    
    # Download file locally.
    curl -o $outputFolder/$fileName \
    https://raw.githubusercontent.com/$gitRepository/$gitBranch/$folderPath/$fileName
    if [ ! -f $outputFolder/$fileName ]; then
        log_level -e "File($fileName) failed to download."
        return 1
    fi
    
    return 0
}

install_helm_chart()
{
    local identityFile=$1;
    local userName=$2;
    local connectionIP=$3;
    local testFolder=$4;
    local fileName=$5;
    
    log_level -i "=========================================================================="
    log_level -i "Installing Helm chart."
    ssh -t -i $identityFile \
    $userName@$connectionIP \
    "sudo chmod 744 $testFolder/$fileName; cd $testFolder; ./$fileName;"
    helmServerVer=$(ssh -t -i $identityFile $userName@$connectionIP "helm version | grep -o 'Server: \(.*\)[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}'")
    if [ -z "$helmServerVer" ]; then
        log_level -e "Helm install was not successfull."
        return 1
    fi
    
    log_level -i "Helm got installed successfully. Helm version is: $helmServerVer"
    return 0
}

install_helm_app()
{
    local identityFile=$1;
    local userName=$2;
    local connectionIP=$3;
    local appName=$4;
    
    log_level -i "Installing App($appName)."
    # Install Helm passed app
    ssh -t -i $identityFile \
    $userName@$connectionIP \
    "helm install stable/$appName"
    
    appReleaseName=$(ssh -t -i $identityFile $userName@$connectionIP "helm ls -d -r | grep 'DEPLOYED\(.*\)$appName' | grep -Eo '^[a-z,-]+'")
    if [ -z "$appReleaseName" ]; then
        log_level -e "App($appName) deployment failed using Helm."
        return 1
    fi
    
    log_level -i "Helm deployed app($appName) with deployment name as: $appReleaseName."
    return 0
}

check_app_pod_running()
{
    local identityFile=$1;
    local userName=$2;
    local connectionIP=$3;
    local appName=$4;
    
    # Check if pod is up and running
    log_level -i "Validate if pod for $appName app is created and running."
    i=0
    while [ $i -lt 20 ]; do
        appPodstatus=$(ssh -t -i $identityFile $userName@$connectionIP "sudo kubectl get pods --selector $appName | grep 'Running' || true")
        if [ -z "$appPodstatus" ]; then
            log_level -i "Pod is not up. We we will retry after some time."
            sleep 30s
        else
            log_level -i "Pod is up ($appPodstatus)."
            break
        fi
        let i=i+1
    done
    
    if [ -z "$appPodstatus" ]; then
        log_level -e "Validation failed because $appName pod not running."
        return 1
    fi
    
    log_level -i "$appName pod is up and running."
    return 0
}

check_app_has_externalip()
{
    local identityFile=$1;
    local userName=$2;
    local connectionIP=$3;
    local appName=$4;
    local releaseName=$5;
    local serviceName=$releaseName"-"$appName
    # Check if App got external IP
    log_level -i "Validate if service($serviceName) got external IP address."
    i=0
    while [ $i -lt 20 ];do
        IP_ADDRESS=$(ssh -t -i $identityFile $userName@$connectionIP "sudo kubectl get services $serviceName -o=custom-columns=NAME:.status.loadBalancer.ingress[0].ip | grep -oP '(\d{1,3}\.){1,3}\d{1,3}'")
        if [ -z "$IP_ADDRESS" ]; then
            log_level -i "External IP is not assigned. We we will retry after some time."
            sleep 30s
        else
            break
        fi
        let i=i+1
    done
    
    if [ -z "$IP_ADDRESS" ]; then
        log_level -e "External IP not found for $appName."
        return 1
    fi
    
    log_level -i "Found external IP address($IP_ADDRESS) assign to $appName."
    return 0
}

check_app_listening_at_externalip()
{
    local externalIp=$1;
    i=0
    while [ $i -lt 20 ];do
        portalState=$(curl --connect-timeout 30 http://${externalIp}; if [ $? -eq 0 ]; then echo "HTTP OK 200"; fi;)
        if [ -z "$portalState" ]; then
            log_level -i "Portal communication validation failed. We we will retry after some time."
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

check_helm_app_release_cleanup()
{
    
    local identityFile=$1;
    local userName=$2;
    local connectionIP=$3;
    local appName=$4;
    
    # Rechecking to make sure deployment cleanup done successfully.
    i=0
    while [ $i -lt 20 ];do
        releaseName=$(ssh -t -i $identityFile $userName@$connectionIP "helm ls -d -r | grep 'DEPLOYED\(.*\)$appName' | grep -Eo '^[a-z,-]+' || true")
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

# Avoids apt failures by first checking if the lock files are around
# Function taken from the AKSe's code based
wait_for_apt_locks()
{
    while fuser /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1; do
        echo 'Waiting for release of apt locks'
        sleep 3
    done
}

# Avoid transcient apt-update failures
# Function taken from gallery code based
apt_get_update()
{
    log_level -i "Updating apt cache."
    
    retries=10
    apt_update_output=/tmp/apt-get-update.out
    
    for i in $(seq 1 $retries); do
        wait_for_apt_locks
        sudo dpkg --configure -a
        sudo apt-get -f -y install
        sudo apt-get update 2>&1 | tee $apt_update_output | grep -E "^([WE]:.*)|([eE]rr.*)$"
        [ $? -ne 0  ] && cat $apt_update_output && break || \
        cat $apt_update_output
        if [ $i -eq $retries ]; then
            return 1
        else
            sleep 30
        fi
    done
    
    echo "Executed apt-get update $i time/s"
    wait_for_apt_locks
}

# Avoids transcient apt-install failures
# Function taken from gallery code based
apt_get_install()
{
    retries=$1; wait_sleep=$2; timeout=$3;
    shift && shift && shift
    
    for i in $(seq 1 $retries); do
        wait_for_apt_locks
        sudo dpkg --configure -a
        sudo apt-get install --no-install-recommends -y ${@}
        [ $? -eq 0  ] && break || \
        if [ $i -eq $retries ]; then
            return 1
        else
            sleep $wait_sleep
            apt_get_update
        fi
    done
    
    echo "Executed apt-get install --no-install-recommends -y \"$@\" $i times";
    wait_for_apt_locks
}

perf_process_net_files()
{
    directoryName=$1
    outputFileName=$2
    FILENAME_LIST=$(ls $directoryName/*.csv)
    declare -A RESULT_MAP
    testCaseCount=0
    while [ $testCaseCount -lt 14 ];do
        RESULT_MAP[$testCaseCount]=0.00
        let testCaseCount=testCaseCount+1
    done
    iteration=0
    for resultFileName in $FILENAME_LIST
    do
        log_level -i "Processing file $resultFileName."
        testCaseCount=0
        while IFS= read -r line;
        do
            currentLine=$(echo $line | tr -d " ");
            currentLine=$(echo $currentLine | tr "," " ");
            currentLine=($currentLine);
            if [[ $testCaseCount != 0 ]]; then
                RESULT_MAP[$testCaseCount]=$(echo ${RESULT_MAP[$testCaseCount]}+${currentLine[1]}| bc);
            fi
            let testCaseCount=testCaseCount+1
        done < $resultFileName
        let iteration=iteration+1
    done
    
    testCaseCount=1
    while [ $testCaseCount -lt 14 ];do
        RESULT_MAP[$testCaseCount]=$(echo ${RESULT_MAP[$testCaseCount]}/$iteration| bc);
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
                          "${RESULT_MAP[13]}" > $directoryName/$outputFileName
}

apt_install_jq()
{
    jq_Link=$1
    log_level -i "Install jq on local machine."
    curl -O -L $jq_Link
    if [ ! -f jq-win64.exe ]; then
        log_level -e "File(jq-win64.exe) failed to download."
        exit 1
    fi
    mv jq-win64.exe /usr/bin/jq
}

validate_testcase_result()
{
    resultFileName=$1
    expectedResultFileName=$2
    testCaseName=$3
    
    TESTRESULT=`cat "$resultFileName" | jq --arg v "$testCaseName" '.testSuite[] | select(.testname == $v) | .value'`
    TESTCASE_MINVALUE=`cat "$expectedResultFileName" | jq --arg v "$testCaseName" '.testSuite[] | select(.testname == $v) | .minvalue'`
    if (( $(awk 'BEGIN {print ("'$TESTRESULT'" >= "'$TESTCASE_MINVALUE'")}') )); then
        log_level -i "Test case \"$testCaseName\" passed with value $TESTRESULT as it is greater than $TESTCASE_MINVALUE."
    else 
        FAILED_CASES="$FAILED_CASES,$testCaseName"
        log_level -e "Test case \"$testCaseName\" failed for value $TESTRESULT as it is less than $TESTCASE_MINVALUE."
    fi
}

