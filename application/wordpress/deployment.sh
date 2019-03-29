#! /bin/bash

function printUsage
{
    echo "      Usage:"
    echo "      $FILENAME --identity-file id_rsa --host 192.168.102.34 --user azureuser"
    echo  ""
    echo "            -i, --identity-file                         the RSA Private Key filefile to connect the kubernetes master VM, it starts with -----BEGIN RSA PRIVATE KEY-----"
    echo "            -m, --host                                  public ip or FQDN of the Kubernetes cluster master VM. The VM name starts with k8s-master- "
    echo "            -u, --user                                  user name of the Kubernetes cluster master VM "
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

echo "identity-file: $IDENTITYFILE"
echo "host: $HOST"
echo "user: $AZUREUSER"

# Why multiple ssh commands instead of 1 scp and 1 ssh?
# Pushing up a single script should make things easier to read/understand, review and maintain.

# Install Helm chart
ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "curl -O https://raw.githubusercontent.com/LingyunSu/AzureStack-QuickStart-Templates/master/k8s-post-deployment-validation/install_helm_test.sh; sudo chmod 744 install_helm_test.sh;"
ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "./install_helm_test.sh;"

# Install Wordpress app
ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "curl -O https://raw.githubusercontent.com/Bhuvaneswari-Santharam/AzureStack-QuickStart-Templates/master/k8s-post-deployment-validation/install_wordpress_on_kubernete_in_helm_test.sh; sudo chmod 744 install_wordpress_on_kubernete_in_helm_test.sh;"
ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "./install_wordpress_on_kubernete_in_helm_test.sh;"

# Install Hello world
ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "curl -O https://raw.githubusercontent.com/LingyunSu/AzureStack-QuickStart-Templates/master/k8s-post-deployment-validation/helm_create_helloworld_chart_test.sh; sudo chmod 744 helm_create_helloworld_chart_test.sh;"
ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "./helm_create_helloworld_chart_test.sh;"

FOLDERNAME=$(dirname $FILENAME)
CURRENTDATE=$(date +%d-%m-%Y-%H-%M-%S)
LOGFILEFOLDER="wordpress$CURRENTDATE"
mkdir -p $FOLDERNAME/$LOGFILEFOLDER

ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "mkdir -p var_log"
ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "cp -R /var/log /home/$AZUREUSER/var_log;"
ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "tar -zcvf var_log.tar.gz var_log;"

scp -r -i $IDENTITYFILE $AZUREUSER@$HOST:/home/$AZUREUSER/var_log.tar.gz $FOLDERNAME/$LOGFILEFOLDER

echo "Wordpress logs are copied into $FOLDERNAME/$LOGFILEFOLDER"
