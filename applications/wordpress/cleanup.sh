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

LOGFILENAME=$OUTPUTFOLDER/cleanup.log

echo "identity-file: $IDENTITYFILE \n" > $LOGFILENAME
echo "host: $HOST \n" >> $LOGFILENAME
echo "user: $AZUREUSER \n" >> $LOGFILENAME
echo "FolderName: $OUTPUTFOLDER \n" >> $LOGFILENAME

# Cleanup Word press app.
ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST 'echo "wordpress=$(kubectl get svc -o name | grep wordpress); kubectl delete \$wordpress" >file.sh; chmod 744 file.sh;'
ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "./file.sh;" >> $LOGFILENAME

ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST 'echo "mariadb=$(kubectl get svc -o name | grep mariadb); kubectl delete \$mariadb" >file.sh; chmod 744 file.sh;'
ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "./file.sh;" >> $LOGFILENAME

ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST 'echo "wordpress=$(kubectl get deployment -o name | grep wordpress); kubectl delete \$wordpress" >file.sh; chmod 744 file.sh;'
ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "./file.sh;" >> $LOGFILENAME

ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST 'echo "mariadb=$(kubectl get statefulset.apps -o name | grep mariadb); kubectl delete \$mariadb" >file.sh; chmod 744 file.sh;'
ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "./file.sh;" >> $LOGFILENAME

ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "mkdir -p var_log" >> $LOGFILENAME
ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "cp -R /var/log /home/$AZUREUSER/var_log;" >> $LOGFILENAME
ssh -t -i $IDENTITYFILE $AZUREUSER@$HOST "tar -zcvf var_log.tar.gz var_log;" >> $LOGFILENAME

scp -r -i $IDENTITYFILE $AZUREUSER@$HOST:/home/$AZUREUSER/var_log.tar.gz $OUTPUTFOLDER
echo "Logs are copied into $OUTPUTFOLDER"