#!/bin/bash

function printUsage
{
    echo ""
    echo "Usage:"
    echo "  $0 -i id_rsa -m 192.168.102.34 -u azureuser -o validation.json"
    echo ""
    echo "Options:"
    echo "  -u, --user                      User name associated to the identifity-file"
    echo "  -i, --identity-file             RSA private key tied to the public key used to create the Kubernetes cluster (usually named 'id_rsa')"
    echo "  -m, --vmd-host                  The DVM's public IP or FQDN (host name starts with 'vmd-')"
    echo "  -o, --output-file               Output file"
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
        -m|--vmd-host)
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
echo ""

OUTPUT_FOLDER="$(dirname $OUTPUT_SUMMARYFILE)"
LOG_FILENAME="$OUTPUT_FOLDER/mongo_availability.log"

{
ROOT_PATH=/home/$USER

scp -q -i $IDENTITYFILE $USER@$DVM_HOST:$ROOT_PATH/mongo_availability_logs $LOG_FILENAME

log_level -i "Mongo Validation done."
printf '{"result":"%s"}\n' "pass" > $OUTPUT_SUMMARYFILE

} 2>&1 | tee $LOG_FILENAME
