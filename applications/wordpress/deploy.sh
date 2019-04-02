#! /bin/bash

function printUsage
{
    echo "      Usage:"
    echo "      $FILENAME --identity-file id_rsa --master 192.168.102.34 --user azureuser"
    echo  ""
    echo "            -i, --identity-file                         RSA Private Key file to connect kubernetes master VM, it starts with -----BEGIN RSA PRIVATE KEY-----"
    echo "            -m, --master                                Public ip of Kubernetes cluster master VM. Normally VM name starts with k8s-master- "
    echo "            -u, --user                                  User Name of Kubernetes cluster master VM "
    echo "            -o, --output                                OutputFolder where all the log files will be put"
    exit 1
}

FILENAME=$0

while [[ "$#" -gt 0 ]]
do
    case $1 in
        -i|--identity-file)
            IDENTITYFILE="$2"
        ;;
        -m|--master)
            HOST="$2"
        ;;
        -u|--user)
            AZUREUSER="$2"
        ;;
        -o|--output)
            OUTPUTFOLDER="$2"
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

LOGFILENAME=$OUTPUTFOLDER/deploy.log

echo "identity-file: $IDENTITYFILE \n" > $LOGFILENAME
echo "host: $HOST \n" >> $LOGFILENAME
echo "user: $AZUREUSER \n" >> $LOGFILENAME
echo "FolderName: $OUTPUTFOLDER \n" >> $LOGFILENAME

# Install Helm chart
ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "curl -O https://raw.githubusercontent.com/msazurestackworkloads/kubetools/master/applications/wordpress/install_helm.sh; sudo chmod 744 install_helm.sh;" >> $LOGFILENAME

ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "./install_helm.sh;" >> $LOGFILENAME

# Install Wordpress app
ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "curl -O https://raw.githubusercontent.com/msazurestackworkloads/kubetools/master/applications/wordpress/install_wordpress_using_helm.sh; sudo chmod 744 install_wordpress_using_helm.sh;" >> $LOGFILENAME

ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "./install_wordpress_using_helm.sh;" >> $LOGFILENAME




