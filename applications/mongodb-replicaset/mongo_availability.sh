#!/bin/bash

function printUsage
{
    echo ""
    echo "Usage:"
    echo "  $0 -i id_rsa -d 192.168.102.34 -u azureuser --file aks_file --tenant-Id tenant-id --subscription-id subscription-id --disable-host-key-checking"
    echo ""
    echo "Options:"
    echo "  -u, --user                      User name associated to the identifity-file"
    echo "  -i, --identity-file             RSA private key tied to the public key used to create the Kubernetes cluster (usually named 'id_rsa')"
    echo "  -d, --vmd-host                  The DVM's public IP or FQDN (host name starts with 'vmd-')"
    echo "  -o, --output-file               Output file"
    echo "  -a, --app-ip                    MongoDB external LB Ip"
    echo "  -h, --help                      Print the command usage"
    exit 1
}

if [ "$#" -eq 0 ]
then
    printUsage
fi

# Handle named parameters
while [[ "$#" -gt 0 ]]
do
    case $1 in
        -i|--identity-file)
            IDENTITYFILE="$2"
            shift 2
        ;;
        -d|--vmd-host)
            DVM_HOST="$2"
            shift 2
        ;;
        -u|--user)
            USER="$2"
            shift 2
        ;;
        -a|--app-ip)
            APP_IP="$2"
            shift 2
        ;;
        -o|--output-file)
            OUTPUT_SUMMARYFILE="$2"
            shift 2
        ;;
        -h|--help)
            printUsage
        ;;
        *)
            echo ""
            echo "[ERR] Incorrect option $1"
            printUsage
        ;;
    esac
done

# Validate input
if [ -z "$USER" ]
then
    echo ""
    echo "[ERR] --user is required"
    printUsage
fi

if [ -z "$IDENTITYFILE" ]
then
    echo ""
    echo "[ERR] --identity-file is required"
    printUsage
fi

if [ -z "$DVM_HOST" ]
then
    echo ""
    echo "[ERR] --vmd-host should be provided"
    printUsage
fi

if [ -z "$APP_IP" ]
then
    echo ""
    echo "[ERR] --parameter should be provided"
    printusuage
fi

if [ ! -f $IDENTITYFILE ]
then
    echo ""
    echo "[ERR] identity-file not found at $IDENTITYFILE"
    printUsage
    exit 1
else
    cat $IDENTITYFILE | grep -q "BEGIN \(RSA\|OPENSSH\) PRIVATE KEY" \
    || { echo "The identity file $IDENTITYFILE is not a RSA Private Key file."; echo "A RSA private key file starts with '-----BEGIN [RSA|OPENSSH] PRIVATE KEY-----''"; exit 1; }
fi

# Print user input
echo ""
echo "user:             $USER"
echo "identity-file:    $IDENTITYFILE"
echo "vmd-host:         $DVM_HOST"
echo "app-ip:           $APP_IP"
echo ""

# Define all inner varaibles.
OUTPUT_FOLDER="$(dirname $OUTPUT_SUMMARYFILE)"
LOG_FILENAME="$OUTPUT_FOLDER/mongodb.log"
touch $LOG_FILENAME
{
NOW=`date +%Y%m%d%H%M%S`
AZURE_USER="azureuser"
IDENTITY_FILE_BACKUP_PATH="/home/azureuser/IDENTITY_FILEBACKUP"

echo "Backing up identity files at ($IDENTITY_FILE_BACKUP_PATH)"
ssh -t -i $IDENTITYFILE $USER@$DVM_HOST "if [ -f /home/$AZURE_USER/.ssh/id_rsa ]; then mkdir -p $IDENTITY_FILE_BACKUP_PATH;  sudo mv /home/$AZURE_USER/.ssh/id_rsa $IDENTITY_FILE_BACKUP_PATH; fi;"

echo -i "Copying over new identity file"
scp -i $IDENTITYFILE $IDENTITYFILE $USER@$DVM_HOST:/home/$AZURE_USER/.ssh/id_rsa

ROOT_PATH=/home/azureuser

scp -q -i $IDENTITYFILE $SCRIPTSFOLDER/*.sh $USER@$DVM_HOST:$ROOT_PATH
ssh -t -i $IDENTITYFILE $USER@$DVM_HOST "sudo apt install mongodb-clients -y"
ssh -t -i $IDENTITYFILE $USER@$DVM_HOST "cd $ROOT_PATH; echo 'rs.slaveOk()' >>testmongodb.js; echo 'show collections' >>testmongodb.js;echo 'db.fruits.find()' >>testmongodb.js"
ssh -t -i $IDENTITYFILE $USER@$DVM_HOST "mongo --host $APP_IP:27017 < $ROOT_PATH/testmongodb.js > results"
ssh -t -i $IDENTITYFILE $USER@$DVM_HOST "cat /home/azureuser/results | grep '_id' "
scp -q -i $IDENTITYFILE $USER@$DVM_HOST:$ROOT_PATH/results $LOG_FILENAME
ssh -t -i $IDENTITYFILE $USER@$DVM_HOST "while true;do echo $(date +\"%Y-%m-%d-%H:%M:%S\") >> mongo-availability_logs; mongo --host $APP_IP:27017 < /home/azureuser/testmongodb.js >> mongo-availability_logs;sleep 20;done"

} 2>&1 | tee $LOG_FILENAME
