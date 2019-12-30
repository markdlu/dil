#!/bin/bash
#this is for grab current state after rolling shutdown
#history:
#init  Mark Lu 11/21/2019
#
#
#
#################################################################


function set_env
{
host=`uname -n |cut -d'.' -f1`
if [ ! -d $HOME/log ]
then
mkdir -p $HOME/log
fi

AFTEROUTPUT1LOG=$HOME/log/after_output1_log
AFTEROUTPUT2LOG=$HOME/log/after_output2_log
AFTERERRORLOG=$HOME/log/after_error_log

cat /dev/null > $AFTEROUTPUT1LOG
cat /dev/null > $AFTEROUTPUT2LOG
cat /dev/null > $AFTERERRORLOG

#username=`cat /etc/my.cnf.d/server.cnf |grep wsrep_sst_auth|awk '{print $3}' |cut -d: -f1 `
#password=`cat /etc/my.cnf.d/server.cnf |grep wsrep_sst_auth|awk '{print $3}' |cut -d: -f2 `
username=mdbbackupuser
password=mdb8qL1E7Ubkup
myconn="/bin/mysql  -u$username -p$password"

}

function aftercheck_save
{
echo " show status like 'wsrep_%'; "  | $myconn |grep -v "Warning:" 1> ${AFTEROUTPUT1LOG}_${host} 2> ${AFTERERRORLOG}_${host}
cat  ${AFTERERRORLOG}_${host} |grep -v "Warning" >  ${AFTERERRORLOG}_${host}
sleep 2

size=`ls -l ${AFTERERRORLOG}_${host}  |awk '{print $6}'`
echo "check error log size:" $size
if [ "$size" != "0" ]
 then
   echo "mysql on $host is not up, sending email out..." 
   echo "mysql on $host is not up, sending email out..." >> ${AFTERERRORLOG}_${host}
   exit 1;
else
 grep wsrep_local_state_comment ${AFTEROUTPUT1LOG}_${host}  > ${AFTEROUTPUT2LOG}_${host}
 grep wsrep_cluster_size ${AFTEROUTPUT1LOG}_${host}  >> ${AFTEROUTPUT2LOG}_${host}
 grep wsrep_cluster_status ${AFTEROUTPUT1LOG}_${host} >> ${AFTEROUTPUT2LOG}_${host}
 echo "after output2"
 cat  ${AFTEROUTPUT2LOG}_${host}
fi
}


#main

set_env;
aftercheck_save;
