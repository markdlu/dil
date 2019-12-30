#!/bin/bash

for user in eshivakumar 
do
nohup sudo su - ${user}@npres.local;exit &
if [ ! -d /home/npres.local/${user} ]
then
sudo ln -s /home/${user}@npres.local /home/npres.local/${user}
fi

sudo mkdir -p /home/npres.local/${user}/bin
sudo chown "${user}@npres.local":'domain users@npres.local' /home/npres.local/${user}/bin
sudo cp /home/npres.local/mlu/.mylogin.cnf /home/npres.local/$user/
sudo chown   "${user}@npres.local":'domain users@npres.local'  /home/npres.local/${user}/.mylogin.cnf
sudo chmod 0600 /home/npres.local/${user}/.mylogin.cnf
sudo cp /home/npres.local/mlu/bin/mysql* /home/npres.local/$user/bin/.
sudo chown   "${user}@npres.local":'domain users@npres.local'  /home/npres.local/${user}/bin/mysql*
sudo chmod  'u+x'  /home/npres.local/${user}/bin/mysql*
sudo echo "alias myroot='~/bin/mysql --login-path=rootcr --prompt=\"MariaDB [\d]>\_\"'" >> /home/npres.local/$user/.bash_profile
done
