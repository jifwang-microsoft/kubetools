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
        -m|--host)
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

# Cleanup wordpress and mariadb deployment.
ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "wordpress=$(kubectl get svc -o name | grep wordpress); kubectl delete $wordpress"
ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "mariadb=$(kubectl get svc -o name | grep mariadb); kubectl delete $mariadb"
ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "wordpress=$(kubectl get deployment -o name | grep wordpress); kubectl delete $wordpress"
ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "mariadb=$(kubectl get statefulset.apps -o name | grep mariadb); kubectl delete $mariadb"

# Cleanup hello world app deployment.
ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "helloworld=$(kubectl get deployment -o name | grep helloworld); kubectl delete $helloworld"
ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "helloworld=$(kubectl get svc -o name | grep helloworld); kubectl delete $helloworld"

echo "Wordpress and hello world cleanup done."
