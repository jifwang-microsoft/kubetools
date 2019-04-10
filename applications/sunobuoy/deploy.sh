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

printUsage()
{
    echo "      Usage:"
    echo "      $FILENAME --identity-file id_rsa --master 192.168.102.34 --user azureuser"
    echo  ""
    echo "            -i, --identity-file                         RSA Private Key file to connect kubernetes master VM, it starts with -----BEGIN RSA PRIVATE KEY-----"
    echo "            -m, --master                                Public ip of Kubernetes cluster master VM. Normally VM name starts with k8s-master- "
    echo "            -u, --user                                  User Name of Kubernetes cluster master VM "
    echo "            -o, --output-file                           Summary file providing result status of the deployment."
    exit 1
}

function final_changes {
    if [ ! -f "$OUTPUT_FILE" ]; then
        printf '{"result":"%s"}\n' "fail" > $OUTPUT_FILE
    fi
}

FILENAME=$0

while [[ "$#" -gt 0 ]]
do
    case $1 in
        -i|--identity-file)
            IDENTITYFILE="$2"
        ;;
        -m|--master)
            MASTERVMIP="$2"
        ;;
        -u|--user)
            AZUREUSER="$2"
        ;;
        -o|--output-file)
            OUTPUT_FILE="$2"
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

OUTPUTFOLDER="$(dirname $OUTPUT_FILE)"
LOGFILENAME="$OUTPUTFOLDER/deploy.log"
touch $LOGFILENAME

{
    # Github details.
    GITREPROSITORY="${GITREPROSITORY:-msazurestackworkloads/kubetools}"
    GITBRANCH="${GITBRANCH:-master}"
    
    log_level -i "------------------------------------------------------------------------"
    log_level -i "Input Parameters"
    log_level -i "------------------------------------------------------------------------"
    log_level -i "Identity-file   : $IDENTITYFILE"
    log_level -i "Master IP       : $MASTERVMIP"
    log_level -i "OUTPUT_FILE     : $OUTPUT_FILE"
    log_level -i "User            : $AZUREUSER"
    log_level -i "Git Repository  : $GITREPROSITORY"
    log_level -i "Git Branch      : $GITBRANCH"
    log_level -i "------------------------------------------------------------------------"
    
    log_level -i "Get differnt version details."
    KUBERNETES_VERSION=$(ssh -t -i $IDENTITYFILE $AZUREUSER@$MASTERVMIP 'kubectl version -o json | jq -r .serverVersion.gitVersion | cut -c 2-')
    KUBERNETES_MAJOR_VERSION="${KUBERNETES_VERSION%.*}"
    
    log_level -i "K8sVersion      : $KUBERNETES_VERSION"
    log_level -i "K8sMajorVersion : $KUBERNETES_MAJOR_VERSION"
    
    if [ "$KUBERNETES_MAJOR_VERSION" == "1.11" ]; then
        SONOBUOY_VERSION="0.13.0"
    else
        SONOBUOY_VERSION="0.14.0"
    fi
    
    log_level -i "SONOBUOY Version : $SONOBUOY_VERSION"
    log_level -i "------------------------------------------------------------------------"
    
    curl -o $OUTPUTFOLDER/install_prerequisite.sh \
    https://raw.githubusercontent.com/$GITREPROSITORY/$GITBRANCH/applications/sunobuoy/install_prerequisite.sh
    if [ ! -f $OUTPUTFOLDER/install_prerequisite.sh ]; then
        log_level -e "File(install_prerequisite.sh) failed to download."
        exit 1
    fi

    log_level -i "Copy install file to master VM."
    scp -i $IDENTITYFILE \
    $OUTPUTFOLDER/install_prerequisite.sh \
    $AZUREUSER@$MASTERVMIP:/home/$AZUREUSER/
    
    # Install Golang
    ssh -t -i $IDENTITYFILE $AZUREUSER@$MASTERVMIP "sudo chmod 744 install_prerequisite.sh; "
    ssh -t -i $IDENTITYFILE $AZUREUSER@$MASTERVMIP "./install_prerequisite.sh;"
    
    log_level -i "------------------------------------------------------------------------"
    
    # Install sonobuoy
    ssh -t -i $IDENTITYFILE $AZUREUSER@$MASTERVMIP "wget https://github.com/heptio/sonobuoy/releases/download/v$SONOBUOY_VERSION/sonobuoy_$SONOBUOY_VERSION\_linux_amd64.tar.gz"
    ssh -t -i $IDENTITYFILE $AZUREUSER@$MASTERVMIP "sudo tar -xvf sonobuoy_$SONOBUOY_VERSION\_linux_amd64.tar.gz"
    
    
    # Start sonobuoy tests
    #ssh -t -i $IDENTITYFILE $AZUREUSER@$MASTERVMIP "./sonobuoy run --mode quick;"
    ssh -t -i $IDENTITYFILE $AZUREUSER@$MASTERVMIP "./sonobuoy run;"
    
    result="pass"
    printf '{"result":"%s"}\n' "$result" > $OUTPUT_FILE
    
    # Create result file, even if script ends with an error
    #trap final_changes EXIT
    
} 2>&1 | tee $LOGFILENAME