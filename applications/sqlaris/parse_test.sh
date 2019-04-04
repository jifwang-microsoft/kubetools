#merge junit test into one
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
    echo "            -o, --output                         Location for test output files "
    echo "            -t, --test-assets                    Location of all test assets"
    exit 1
}

FILENAME=$0

while [[ "$#" -gt 0 ]]
do
    case $1 in
        -o|--output)
            TEST_OUTPUT_DIRECTORY="$2"
        ;;
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

if [ -z "$TEST_OUTPUT_DIRECTORY" ];
then
    log_level -e "TEST_OUTPUT_DIRECTORY not set"
    exit 1
fi

if [ -z "$TEST_DIRECTORY" ];
then
    log_level -e "TEST_DIRECTORY not set"
    exit 1
fi

log_level -i "Script Parameters"
echo "TEST_DIRECTORY: $TEST_DIRECTORY"
echo "TEST_OUTPUT_DIRECTORY: $TEST_OUTPUT_DIRECTORY"



log_level -i "Making output directory"
mkdir $HOME/$TEST_DIRECTORY/$TEST_OUTPUT_DIRECTORY

log_level -i "Moving Test Results into a test directory"
sudo cp -r $HOME/$TEST_DIRECTORY/aris/projects/test/output/junit/* $HOME/$TEST_DIRECTORY/$TEST_OUTPUT_DIRECTORY

log_level -i "Change directory to test output folder"
cd $TEST_OUTPUT_DIRECTORY

log_level -i "Collecting junit merge file"
curl -O https://gist.githubusercontent.com/cgoldberg/4320815/raw/efcf6830f516f79b82e7bd631b076363eda3ed99/merge_junit_results.py

log_level -i "Merge junit files"
FILES=""
for entry in *
do
    if [ $entry == "merge_junit_results.py" ];
    then
        echo Not Merging $entry
    else
        echo Merging $entry
        FILES="$FILES $entry"
    fi
done
python merge_junit_results.py $FILES > results.xml

log_level -i "Remove merger script"
rm -rf merge_junit_results.py

echo 0

