storageuri=${1}
storagekey=${2}
epoch=$(date +%s)
hostname=$(hostname)
foldername=$hostname$epoch
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
sudo ./install.sh

sudo chmod -R ugo+rw /var/log/azurestack
sudo cp -r /var/log/ /var/log/azurestack/"$foldername"
sudo cp -r /var/lib/docker/containers /var/log/azurestack/"$foldername"
sudo tar -zcvf /var/log/azurestack/$foldername.tar.gz /var/log/azurestack/"$foldername"


azcopy --source /var/log/azurestack/$foldername.tar.gz --destination "$storageuri"/"$foldername".tar.gz --dest-key $storagekey
sudo rm -Rf /var/log/azurestack/"$foldername"
