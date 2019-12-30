#!/bin/bash
#this is for grab current state before rolling shutdown
#history:
#init  Mark Lu 11/21/2019
#
#
#
#################################################################


function set_env
{
host=`uname -n  |cut -d'.' -f1`
if [ ! -d $HOME/log ]
then
mkdir -p $HOME/log
fi

OUTPUT1LOG=$HOME/log/output1_log
OUTPUT2LOG=$HOME/log/output2_log
ERRORLOG=$HOME/log/error_log

cat /dev/null > $OUTPUT1LOG
cat /dev/null > $OUTPUT2LOG
cat /dev/null > $ERRORLOG

#username=`cat /etc/my.cnf.d/server.cnf |grep wsrep_sst_auth|awk '{print $3}' |cut -d: -f1 `
#password=`cat /etc/my.cnf.d/server.cnf |grep wsrep_sst_auth|awk '{print $3}' |cut -d: -f2 ` 
username=mdbbackupuser
password=mdb8qL1E7Ubkup
myconn="/bin/mysql  -u$username -p$password"

}


function precheck_save
{
echo " show status like 'wsrep_%'; "  | $myconn |grep -v "Warning:" 1> ${OUTPUT1LOG}_${host} 2> ${ERRORLOG}_${host}
cat  ${ERRORLOG}_${host} |grep -v "Warning" >  ${ERRORLOG}_${host}
sleep 2
if [ -e ${ERRORLOG}_${host} ]
then
size=`ls -l ${ERRORLOG}_${host}  |awk '{print $6}'`
if [ "$size" != "0" ]
then
echo "mysql on $host is not up, sending email out..." >> ${ERRORLOG}_${host}
exit 1;
fi
fi

sleep 5
if [ -e ${OUTPUT1LOG}_${host} ]
then
grep wsrep_local_state_comment ${OUTPUT1LOG}_${host}  > ${OUTPUT2LOG}_${host}
grep wsrep_cluster_size ${OUTPUT1LOG}_${host}  >> ${OUTPUT2LOG}_${host}
grep wsrep_cluster_status ${OUTPUT1LOG}_${host} >> ${OUTPUT2LOG}_${host}

wsrep_local_state_comment=`grep wsrep_local_state_comment  ${OUTPUT2LOG}_${host} | awk '{print $2}'`
wsrep_cluster_status=`grep wsrep_cluster_status ${OUTPUT2LOG}_${host} | awk '{print $2}'`
wsrep_cluster_size=`grep wsrep_cluster_size ${OUTPUT2LOG}_${host} | awk '{print $2}'`

echo $wsrep_local_state_comment
echo $wsrep_cluster_status
echo $wsrep_cluster_size

if [ "$wsrep_local_state_comment" != "Synced" ] || [ "$wsrep_cluster_status" != "Primary" ]
then
echo  "wsrep_local_state_comment: "  $wsrep_local_state_comment >> ${ERRORLOG}_${host} 
echo  "wsrep_cluster_status: "  $wsrep_cluster_status >> ${ERRORLOG}_${host} 
exit 1;
fi
fi

}


#main

set_env;
precheck_save;
