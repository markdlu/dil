#!/bin/bash
#change history:
#initialized Mark Lu on 11/18/2019
#
#
###############################################


function precheck
{
s1=`ssh $host mount |grep /var/log/mysql |awk '{print $1}'`
if [ $? = "0" ] 
  then
    if [ "$s1" == "/dev/mapper/logvg-loglv01" ]
    then echo "$host volume /var/log/mysql already mounted" >> $MAINLOG
    echo "$host volume /var/log/mysql already mounted" 
    #exit 1;
    continue;
    else
    sdc_flag=`ssh $host lsblk |grep sdc |wc -l`
      if [ "$sdc_flag" == "1" ] 
      then
        ssh $host mkdir -p bin 
        scp $HOME/bin/mysql $host:bin/.
        scp ./precheck_save.bash $host:bin/.
        ssh $host sh bin/precheck_save.bash 
        scp $host:log/*_$host $HOME/log/.

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
     else
       echo "no sdc disk on $host " 
       echo "no sdc disk on $host " > $MAILLOG
       echo "no sdc disk on $host " >> ${MAILLOG}_${host}
       mailout;
       exit 1;
       fi
   fi
fi
}

function verify 
{
echo "verifing on $host..."
sleep 90
start=$SECONDS
while [ true ]
do 
   ping -c1 $host >/dev/null 2>&1
   if [ $? != 0 ]; then
    end=$SECONDS
    duration=$(( end - start ))
      if (( $duration > 20 )) 
      then
        echo "after 2 minutes, $host is still not coming up, please check..." 
        echo "after 2 minutes, $host is still not coming up, please check..."  >> $MAILLOG
        echo "after 2 minutes, $host is still not coming up, please check..."  >> ${MAILLOG}_${host}
        mailout;
       exit 1;
      fi
    continue;
   else
     sleep 10
     echo "$host is back..."
     ssh $host mkdir -p bin
     scp $HOME/bin/mysql $host:bin/.
     scp ./aftercheck_save.bash $host:bin/.
     ssh $host sh bin/aftercheck_save.bash
     scp $host:log/after*_$host $HOME/log/.

     size=`ls -l ${AFTERERRORLOG}_${host}  |awk '{print $6}'`
     if [ "$size" != "0" ]
      then
         cat ${AFTERERRORLOG}_${host} > ${MAILLOG}_${host}
         echo "mysql on $host is not up, sending email out..."
         mailout;
         exit 1;
         fi

     before_wrep_local_state_comment=`grep wsrep_local_state_comment  ${OUTPUT2LOG}_${host} | awk '{print $2}'`
     before_wsrep_cluster_status=`grep wsrep_cluster_status ${OUTPUT2LOG}_${host} | awk '{print $2}'`
     before_wsrep_cluster_size=`grep wsrep_cluster_size ${OUTPUT2LOG}_${host} | awk '{print $2}'`

     after_wsrep_local_state_comment=`grep wsrep_local_state_comment  ${AFTER_OUTPUT2LOG}_${host} | awk '{print $2}'`
     after_wsrep_cluster_status=`grep wsrep_cluster_status ${AFTER_OUTPUT2LOG}_${host} | awk '{print $2}'`
     after_wsrep_cluster_size=`grep wsrep_cluster_size ${AFTER_OUTPUT2LOG}_${host} | awk '{print $2}'`

     echo "before: "
     echo $before_wrep_local_state_comment
     echo $before_wsrep_cluster_status
     echo $before_wsrep_cluster_size

     echo "after: "
     echo $after_wsrep_local_state_comment
     echo $after_wsrep_cluster_status
     echo $after_wsrep_cluster_size

     if [ "$before_wrep_local_state_comment" == "$after_wsrep_local_state_comment" ] && [ "$before_wrep_local_state_status" == "$after_wsrep_local_state_status" ] && [ "$before_wsrep_cluster_size" == "$after_wsrep_cluster_size" ]
     then
     echo  "$host is good after adding /tmp and /var/log/mysql "
     echo  "$host is good after adding /tmp and /var/log/mysql "  >> $MAINLOG 
     else
     echo  "$host,please check mysql instance...  "  
     echo  "$host,please check mysql instance...  "  >> $MAINLOG 
     echo  "$host,please check mysql instance...  "  >> ${MAILLOG}_${host} 
     mailout;
     exit 1;
     fi
   fi
  break;
done
}

function mailout
{
if [ -e  ${MAILLOG}_${host} ]
then
echo "something is wrong on $host"
/bin/mail -s "something is wrong on $host,pleae check..."  $MAILINGLIST < ${MAILLOG}_${host}
fi
}



#main 

MAILINGLIST="mlu@diligent.com"

MAINLOG=~/log/mainlog
OUTPUT1LOG=~/log/output1_log
AFTER_OUTPUT1LOG=~/log/after_output1_log
OUTPUT2LOG=~/log/output2_log
AFTER_OUTPUT2LOG=~/log/after_output2_log
ERRORLOG=~/log/error_log
AFTERERRORLOG=~/log/after_error_log
MAILLOG=~/log/mail_log

cat /dev/null > $MAINLOG
cat /dev/null > $OUTPUT1LOG
cat /dev/null > $AFTER_OUTPUT2LOG
cat /dev/null > $ERRORLOG
cat /dev/null > $AFTERERRORLOG
cat /dev/null > $MAILLOG


MYSQLHOSTLIST=~/ansible/config/main_mariadbhost

for host in `cat $MYSQLHOSTLIST |grep -v ^#`; do
 echo "[mydb]" > ~/ansible/config/single_mariadbhost_tmplog
 echo $host >> ~/ansible/config/single_mariadbhost_tmplog
precheck;
ansible-playbook -i /home/mlu@npres.local/ansible/config/single_mariadbhost_tmplog /home/mlu@npres.local/ansible/playbooks/disk-tmplog-uat.yml 
verify;
done
