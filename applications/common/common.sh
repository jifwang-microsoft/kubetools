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

check_helm_app_pod_running()
{
    local identityFile=$1;
    local userName=$2;
    local connectionIP=$3;
    local appName=$4;
    
    # Check if pod is up and running
    log_level -i "Validate if pod for $appName app is created and running."
    i=0
    while [ $i -lt 20 ]; do
        appPodstatus=$(ssh -t -i $identityFile $userName@$connectionIP "sudo kubectl get pods --selector app=$appName | grep 'Running' || true")
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





