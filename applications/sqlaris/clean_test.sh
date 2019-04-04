#Clean The sql aris cluster
#Delete PVCS where posible
#Return Output
set -e

log_level()
{
    echo "#####################################################################################"
    case "$1" in
        -e) echo "$(date) [Error]  : " ${@:2}
        ;;
        -w) echo "$(date) [Warning]: " ${@:2}
        ;;
        -i) echo "$(date) [Info]   : " ${@:2}
        ;;
        *)  echo "$(date) [Verbose]: " ${@:2}
        ;;
    esac
    echo "#####################################################################################"
}

function printUsage
{
    echo "            -t, --test-assets                    Location of all test assets"
    exit 1
}

FILENAME=$0

while [[ "$#" -gt 0 ]]
do
    case $1 in
        -t|--test-assets)
            TEST_DIRECTORY="$2"
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

#Checking Variables
if [ -z "$TEST_DIRECTORY" ];
then
    log_level -e "TEST_DIRECTORY not set"
    exit 1
fi

log_level -i "Script Parameters"
echo "TEST_DIRECTORY: $TEST_DIRECTORY"

log_level -i "Setting Kubectl config"
export KUBECONFIG="$HOME/$TEST_DIRECTORY/kubeconfig.local.json"

log_level -i "Deleting Namespace"
kubectl delete namespaces test

echo 0