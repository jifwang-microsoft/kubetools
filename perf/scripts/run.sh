storageuri=${1}
storagekey=${2}
name1=${3}
name2=${4}
name3=${5}
epoch=$(date +%s)
hostname=$(hostname)
foldername=$hostname$epoch

wget -O - http://cdn.primatelabs.com/Geekbench-4.1.0-Linux.tar.gz | tar zx --strip-components=2
sudo ./Geekbench-4.1.0-Linux/geekbench4 > geekbench.log

sudo rm -Rf /var/log/azurestack/"$foldername"
mkdir -p  /var/log/azurestack/"$foldername"

mkdir -p  /var/log/azurestack/azcopy
cd /var/log/azurestack/azcopy

curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
sudo mv microsoft.gpg /etc/apt/trusted.gpg.d/microsoft.gpg
sudo sh -c 'echo "deb [arch=amd64] https://packages.microsoft.com/repos/microsoft-ubuntu-xenial-prod xenial main" > /etc/apt/sources.list.d/dotnetdev.list'
sudo apt-get -y update
sudo apt-get -y install dotnet-sdk-2.0.2
wget -O azcopy.tar.gz https://aka.ms/downloadazcopyprlinux
tar -xf azcopy.tar.gz
./install.sh

azcopy --source /geekbench.log --destination "$storageuri"/"$foldername"/"$name1"/"$name2"/"$name3".geekbench.log --dest-key $storagekey
