#!/usr/bin/bash
# Propagate user ssh keys automatically to all hosts in ansible inventory.
# Author: Peter Wang
# Modifier:  Mark Lu

function singlehost 
{
   host=$1
   ping -c1 $host >/dev/null 2>&1
   if [ $? != 0 ]; then
        echo -e "$host : not pingable - SKIPPED!"
   else
        echo -e "\nEnter password for $user -> \c"
        stty -echo
        read -r sshpswd
        stty echo
        echo -e "\n\nCopying authorized_keys for ${user} from $(hostname -f) to :\n"
        echo -e "$host: \c"
        sshpass -p $sshpswd ssh-copy-id -i /home/${user}/.ssh/id_rsa.pub -o StrictHostKeyChecking=no ${user}@${host}
   fi
}

function allhost
{
echo -e "\nEnter password for $user -> \c"
stty -echo
read -r sshpswd
stty echo
echo -e "\n\nCopying authorized_keys for ${user} from $(hostname -f) to :\n"

for host in $(egrep -v '(^#|^\[|^$|^ )' $anshosts|sort|uniq); do
    ping -c1 $host >/dev/null 2>&1
    if [ $? != 0 ]; then
         echo -e "$host : not pingable - SKIPPED!"
    else
         echo -e "$host: \c"
         sshpass -p $sshpswd ssh-copy-id -i /home/${user}/.ssh/id_rsa.pub -o StrictHostKeyChecking=no ${user}@${host}
    fi
done
}


anshosts=~/ansible/config/myansiblehost
user=$(whoami)
sshpswd=""


#main

if [ $# = 1 ];
then
singlehost
elif [ $# -gt 1 ]
then
echo -e "\nUsage: $0 [host]\n"
exit 1
elif [ $# = 0 ]
then
allhost
fi

