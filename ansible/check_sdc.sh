#!/bin/bash

cat /dev/null > ./check_sdc.log
for i in `cat testhost `;
do 
echo $i
echo $i >> ./check_sdc.log
ssh $i mkdir -p bin
scp ~/ansible/bin/precheck_save.bash $i:bin/.
ssh $i lsblk |grep sdc >> ./check_sdc.log
ssh $i bin/precheck_save.bash >>  ./check_sdc.log 2>&1
done
