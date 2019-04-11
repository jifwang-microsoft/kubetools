#Clean The sql aris cluster
#Delete PVCS where posible
#Return Output
set -e

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

log_level -i "-----------------------------------------------------------------------------"
log_level -i "Script Parameters"
log_level -i "-----------------------------------------------------------------------------"
log_level -i "TEST_DIRECTORY: $TEST_DIRECTORY"
log_level -i "-----------------------------------------------------------------------------"

log_level -i "Finding Kubeconfig file"
KUBE_CONFIG_LOCATION=`sudo find  $HOME/$TEST_DIRECTORY/ -type f -iname "kubeconfig*"`

log_level -i "Finding Kubeconfig file from path ($KUBE_CONFIG_LOCATION)"
KUBE_CONFIG_FILENAME=$(basename $KUBE_CONFIG_LOCATION)

log_level -i "Checking if file ($KUBE_CONFIG_FILENAME) exists"
if [[ ! -f $HOME/$TEST_DIRECTORY/$KUBE_CONFIG_FILENAME ]]; then
    log_level -e "File($KUBE_CONFIG_FILENAME) does not exist at $HOME/$TEST_DIRECTORY"
    exit 1
else
    log_level -i "File($KUBE_CONFIG_FILENAME) exist at $HOME/$TEST_DIRECTORY"
fi

log_level -i "Setting Kubectl config variable as per required by k8s"
export KUBECONFIG="$HOME/$TEST_DIRECTORY/$KUBE_CONFIG_FILENAME"

log_level -i "Deleting Namespace"
kubectl delete namespaces test

echo 0