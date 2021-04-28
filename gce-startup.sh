#!/bin/bash

#Change password for VNC and RStudio
#Make password strong!!
PASSWRD="chris123"

#install gcloud
# Create an environment variable for the correct distribution
export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)"

# Add the Cloud SDK distribution URI as a package source
echo "deb http://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list

# Import the Google Cloud Platform public key
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

# Update the package list and install the Cloud SDK
sudo apt-get update && sudo apt-get install google-cloud-sdk


gcloud init


#all other parameters populated by exiting data
USER=$(echo `whoami`)
RAND_NUM=$RANDOM
STATIC_NAME="external-static-$RAND_NUM"
INSTANCE_NAME=$(gcloud compute instances list --format="value(name)")
REGION=$(gcloud config list --format="flattened(compute.region)" | cut -d':' -f2 | tr -d [:space:])
ZONE=$(gcloud config list --format="flattened(compute.zone)" | cut -d':' -f2 | tr -d [:space:])
PROJECT=$(gcloud config list --format="flattened(core.project)" | cut -d':' -f2 | tr -d [:space:])
RSTUDIO="rstudio"
VNC_SERVER="vnc-server"
BUCKET_GEN="gen-storage-$RAND_NUM"
BUCKET_R="r-storage-$RAND_NUM"

echo user: $USER
echo rand: $RAND_NUM
echo static: $STATIC_NAME
echo instance: $INSTANCE_NAME
echo region: $REGION
echo zone: $ZONE
echo project: $PROJECT
echo rstudio fwall: $RSTUDIO
echo vnc fwall: $VNC_SERVER
echo gen-bucket: $BUCKET_GEN
echo gen-bucket-R: $BUCKET_R





#create user password - GCE don't have pswd by default
echo "$USER:$PASSWRD" | sudo chpasswd

cd $HOME

mkdir -p $HOME/run

#if ! [GREP $HOME/run .bashrc]:
#echo 'export PATH=$PATH:$HOME/run' >> ~/.bashrc
#source ~/.bashrc

#Promote ephemeral external IP to staticinstance
EPHERMERAL=$(gcloud compute instances describe $INSTANCE_NAME --zone us-central1-a --format="flattened(networkInterfaces[0].accessConfigs[0].natIP)" | cut -d':' -f2 | tr -d [:space:])
echo $EPHERMERAL

gcloud compute addresses create $STATIC_NAME --addresses $EPHERMERAL --region $REGION


#install GSC fuse
export GCSFUSE_REPO=gcsfuse-`lsb_release -c -s`
echo "deb http://packages.cloud.google.com/apt $GCSFUSE_REPO main" | sudo tee /etc/apt/sources.list.d/gcsfuse.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

sudo apt-get update
sudo apt-get install gcsfuse


#create buckets
gsutil mb -c regional -l us-central1 gs://$BUCKET_GEN/
gsutil mb -c regional -l us-central1 gs://$BUCKET_R/

#alter /mnt permissions so can create folders
sudo chmod -R 777 /mnt/

#make all transfer folders
mkdir /mnt/gcs-bucket /mnt/gcs-bucket-R gcs-put gcs-put-R gcs-working

#make symbolic links to access data from buckets
PRESDIR=$(eval echo "~")
ln -s /mnt/gcs-bucket $HOME/gcs-bucket
ln -s /mnt/gcs-bucket-R $HOME/gcs-bucket-R


#cron runs in subshell so it won't print test cases like echo "hello"
(crontab -l 2>/dev/null; echo "@reboot gcsfuse $BUCKET_GEN /mnt/gcs-bucket") | crontab -
(crontab -l 2>/dev/null; echo "@reboot gcsfuse $BUCKET_R /mnt/gcs-bucket-R") | crontab -
(crontab -l 2>/dev/null; echo "*/10 * * * * gsutil mv $HOME/gcs-put/* gs://$BUCKET_GEN") | crontab -
(crontab -l 2>/dev/null; echo "*/10 * * * * gsutil mv $HOME/gcs-put-R/* gs://$BUCKET_R") | crontab -
(crontab -l 2>/dev/null; echo "") | crontab -


#set firewall rules
#rstudio
gcloud compute firewall-rules create $RSTUDIO --allow tcp:8787

#vnc server
gcloud compute firewall-rules create $VNC_SERVER --allow tcp:5901


#install vnc server
sudo apt-get --yes install tightvncserver

#add vncserver password from bash:
#https://stackoverflow.com/questions/30606655/set-up-tightvnc-programmatically-with-bash

# Configure VNC password
# use safe default permissions
umask 0077

# create config directory
mkdir -p "$HOME/.vnc"

# enforce safe permissions
chmod go-rwx "$HOME/.vnc"

# generate and write a password
#use same password as used for GCE, rstudio
vncpasswd -f <<<"$PASSWRD" >"$HOME/.vnc/passwd"


#install GUI
#select desktop to install using shell options
#https://stackoverflow.com/questions/14513305/how-to-write-unix-shell-scripts-with-options
if  [[ $1 = "-b" ]] || [[ $1 = "--base" ]]
then
echo "Option -base gnome turned on"

#start/stop vnc server to generate startup file
vncserver
vncserver -kill :1

sudo apt-get --yes install gnome-core
cat >>$HOME/.vnc/xstartup <<EOL

metacity &
gnome-settings-daemon &
gnome-panel &
nautilus &
EOL

elif [[ $1 = "-f" ]] || [[ $1 = "--full" ]]
then
echo "Option -full gnome turned on"
sudo apt-get update && sudo apt-get --yes upgrade
sudo apt-get --yes install ubuntu-desktop gnome-panel gnome-settings-daemon metacity nautilus gnome-terminal

#create startup file
cat >$HOME/.vnc/xstartup <<EOL
#!/bin/sh

#xrdb $HOME/.Xresources
[ -x /etc/vnc/xstartup ] && exec /etc/vnc/xstartup
[ -r $HOME/.Xresources ] && xrdb $HOME/.Xresources
xsetroot -solid grey
#vncconfig -iconic &
#vncconfig -geometry 1366x768 &
#x-terminal-emulator -geometry 80x24+10+10 -ls -title "$VNCDESKTOP Desktop" &
#x-window-manager &
# Fix to make GNOME work
export XKL_XMODMAP_DISABLE=1
/etc/X11/Xsession

gnome-panel &
gnome-settings-daemon &
metacity &
nautilus &
EOL

chmod 755 $HOME/.vnc/xstartup

else
    echo "Option -xfce turned on"
    #light install - xfce desktop
    sudo apt-get --yes install xfce4 xfce4-goodies
    sudo apt-get --yes install gnome-icon-theme
fi


#create vnc startup entry in /etc/rc.local file
sudo sed -i -e '$i \su - currentuser -c "/usr/bin/vncserver :1" &\n' /etc/rc.local
sudo sed -i "s/currentuser/$USER/g" /etc/rc.local


#start services for immediate use
vncserver
gcsfuse $BUCKET_GEN /mnt/gcs-bucket
gcsfuse $BUCKET_R /mnt/gcs-bucket-R

# Install R 3.6 
# credits:https://askubuntu.com/questions/1162051/i-am-unable-to-install-latest-version-of-r
# Primeiro, remove a versão instalada do R (caso haja):
sudo apt purge r-base
# Adicionar o repositório, a chave e a atualização como um comando de terminal de uma linha :
sudo bash -c 'echo "deb https://cloud.r-project.org/bin/linux/ubuntu xenial-cran35/" >> /etc/apt/sources.list' && sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E298A3A825C0D65DFD57CBB651716619E084DAB9 && sudo apt update
sudo apt install r-base

# You can then install R using the following command:
# update indices
#sudo apt purge r-base
#sudo apt update -qq
#sudo apt install --no-install-recommends software-properties-common dirmngr
#sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E298A3A825C0D65DFD57CBB651716619E084DAB9
#sudo add-apt-repository "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/"
#sudo apt install --no-install-recommends r-base
#sudo add-apt-repository ppa:c2d4u.team/c2d4u4.0+
#sudo apt install --no-install-recommends r-cran-rstan

#sudo apt-get install r-base

# rstudio
sudo apt-get install gdebi-core
wget https://download2.rstudio.org/server/xenial/amd64/rstudio-server-1.4.1106-amd64.deb
sudo gdebi rstudio-server-1.4.1106-amd64.deb


#need a seperate delete instance script:

cat >$HOME/run/cleanup_gce.sh <<EOL
#!/bin/sh

#delete static IP
STATIC_NAME="$STATIC_NAME"
PROJECT="$PROJECT"
gcloud compute addresses delete $STATIC_NAME --project $PROJECT --region $REGION --quiet

#delete firewall rules "rstudio"
RSTUDIO="$RSTUDIO"
gcloud compute firewall-rules delete $RSTUDIO --quiet

#delete firewall rules "vnc-server"
VNC_SERVER="$VNC_SERVER"
gcloud compute firewall-rules delete $VNC_SERVER --quiet

#delete bucket "general storage"
BUCKET_GEN="$BUCKET_GEN"
gsutil rm gs://$BUCKET_GEN/**
gsutil rb gs://$BUCKET_GEN

#delect bucket "R storage"
BUCKET_R="$BUCKET_R"
gsutil rm gs://$BUCKET_R/**
gsutil rb gs://$BUCKET_R

EOL


chmod 755 $HOME/run/cleanup_gce.sh



