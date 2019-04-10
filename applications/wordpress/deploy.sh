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
        -c|--configFile)
            PARAMETERFILE="$2"
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
    
    curl -o $OUTPUTFOLDER/install_helm.sh \
    https://raw.githubusercontent.com/$GITREPROSITORY/$GITBRANCH/applications/wordpress/install_helm.sh
    if [ ! -f $OUTPUTFOLDER/install_helm.sh ]; then
        log_level -e "File(install_helm.sh) failed to download."
        exit 1
    fi
    
    curl -o $OUTPUTFOLDER/install_wordpress_using_helm.sh \
    https://raw.githubusercontent.com/$GITREPROSITORY/$GITBRANCH/applications/wordpress/install_wordpress_using_helm.sh
    if [ ! -f $OUTPUTFOLDER/install_wordpress_using_helm.sh ]; then
        log_level -e "File(install_wordpress_using_helm.sh) failed to download."
        exit 1
    fi
    
    log_level -i "Copy install file to master VM."
    scp -i $IDENTITYFILE \
    $OUTPUTFOLDER/install_helm.sh \
    $OUTPUTFOLDER/install_wordpress_using_helm.sh \
    $AZUREUSER@$MASTERVMIP:/home/$AZUREUSER/
    
    # Install Helm chart
    ssh -t -i $IDENTITYFILE \
    $AZUREUSER@$MASTERVMIP \
    "sudo chmod 744 install_helm.sh; ./install_helm.sh;"
    log_level -i "------------------------------------------------------------------------"
    helmServerVer=$(ssh -t -i $IDENTITYFILE $AZUREUSER@$MASTERVMIP "helm version | grep -o 'Server: \(.*\)[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}'")
    if [ -z "$helmServerVer" ]; then
        log_level -e "Helm install failed."
        exit 1
    fi
    
    # Install Wordpress app
    ssh -t -i $IDENTITYFILE \
    $AZUREUSER@$MASTERVMIP \
    "sudo chmod 744 install_wordpress_using_helm.sh; ./install_wordpress_using_helm.sh;"
    wpRelease=$(ssh -t -i $IDENTITYFILE $AZUREUSER@$MASTERVMIP "helm ls -d -r | grep 'DEPLOYED\(.*\)wordpress' | grep -Eo '^[a-z,-]+'")
    if [ -z "$wpRelease" ]; then
        log_level -e "Wordpress deployment failed using Helm."
        exit 1
    else
        log_level -e "Helm deployed wordpress app with deployment name as: $wpRelease."
    fi
    
    result="pass"
    printf '{"result":"%s"}\n' "$result" > $OUTPUT_FILE
    # Create result file, even if script ends with an error
    #trap final_changes EXIT
} 2>&1 | tee $LOGFILENAME