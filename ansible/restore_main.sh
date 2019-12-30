#!/bin/bash
#history Mark Lu 11/24/2019
#
#
###############################################################

function set_env
{
export username=`cat $HOME/.pw |grep username |cut -d: -f2 `
export password=`cat $HOME/.pw |grep password |cut -d: -f2 `
}

function restore_db_full 
{
sudo systemctl stop mariadb
sleep 3
echo "M1"
sudo rm -rf /var/lib/mysql/*

targetdir=`cat /tmp/mariabackup_full.log |grep fullbackupdir |cut -d':' -f2 ` 
incrementaldir=`cat /tmp/mariabackup_incremental.log |grep incbackupdir |cut -d':' -f2`
timestampfull=`cat /tmp/mariabackup_full.log  |grep fullbackuptime |cut -d':' -f2`
timestampinc=`cat /tmp/mariabackup_incremental.log  |grep incbackuptime |cut -d':' -f2`

#prepare full datadir first
echo "$targetdir"
echo "$incrementaldir"
sudo /usr/bin/mariabackup --prepare --apply-log-only --target-dir=${targetdir}

#then prepare incremental dir
diff=$(($timestampinc-$timestampfull))
echo $diff
if [ $diff -gt 30 ];
then 
echo "apply incremental to full..."
sudo /usr/bin/mariabackup --prepare --apply-log-only --target-dir=${targetdir} --incremental-dir=${incrementaldir}
fi

#finally copy back from full datadir --restore
echo "copy back full to datadir..."
sudo /usr/bin/mariabackup --copy-back --datadir=/var/lib/mysql  --target-dir=$targetdir

sudo chown -R mysql:mysql /var/lib/mysql
sudo /usr/bin/galera_new_cluster
ps -ef |grep mysql
echo "mysql is up now.."
}


function restore_db_single
{

targetdir=`cat /tmp/mariabackup_full.log |grep fullbackupdir |cut -d':' -f2 `
incrementaldir=`cat /tmp/mariabackup_incremental.log |grep incbackupdir |cut -d':' -f2`
timestampfull=`cat /tmp/mariabackup_full.log  |grep fullbackuptime |cut -d':' -f2`
timestampinc=`cat /tmp/mariabackup_incremental.log  |grep incbackuptime |cut -d':' -f2`

#prepare full datadir first
echo "$targetdir"
echo "$incrementaldir"
sudo /usr/bin/mariabackup --prepare --apply-log-only --target-dir=${targetdir}

#then prepare incremental dir
diff=$(($timestampinc-$timestampfull))
echo $diff
if [ $diff -gt 30 ];
then
echo "apply incremental to full..."
sudo /usr/bin/mariabackup --prepare --apply-log-only --target-dir=${targetdir} --incremental-dir=${incrementaldir}
fi

#finally copy back from full datadir --restore
create_object;
echo "copy signgle table $tbname to new database ${dbname}_restore dir..."
sudo cp "$targetdir/$dbname/${tbname}.frm" /var/lib/mysql/${dbname}_restore/.
sudo cp "$targetdir/$dbname/${tbname}.ibd" /var/lib/mysql/${dbname}_restore/.
sudo chown -R mysql:mysql /var/lib/mysql/${dbname}_restore/
mysql -u${username} -p${password} -e "ALTER TABLE ${dbname}_restore.$tbname IMPORT TABLESPACE;"
echo "done"
}

function usage
{
echo "$0 [full | single ]" 
}

function create_object
{
mysql -u${username} -p${password} -e "create database if not exists ${dbname}_restore ;" 
mysql -u${username} -p${password} -e "use $dbname;show create table ${tbname};" > create_tb.tmp
echo "use ${dbname}_restore;" > creat_tb.sql
tail -1 create_tb.tmp  | awk '{$1= ""; print $0}' >> creat_tb.sql 
fkflag=`cat creat_tb.sql |grep "FOREIGN KEY" |wc -l` 
if [ "$fkflag" == "1" ]
then
fk=`cat creat_tb.sql | grep -o -P '(?<=CONSTRAINT).*(?=FOREIGN)'`
echo ";alter table ${dbname}_restore.${tbname} drop FOREIGN KEY $fk;" >> creat_tb.sql 
echo "ALTER TABLE ${dbname}_restore.${tbname} DISCARD TABLESPACE; " >> creat_tb.sql
else
echo ";ALTER TABLE ${dbname}_restore.${tbname} DISCARD TABLESPACE; " >> creat_tb.sql
fi
mysql -u${username} -p${password} < creat_tb.sql > create_tb.out 2>&1
err=`grep -i error create_tb.out |wc -l`
if [ "$err" != "0" ]
then
echo "table created failed, need to check..."
cat create_tb.out
exit 1
fi
}

#main

restore_mode=$1
dbname=$2
tbname=$3

set_env;

if [ "$restore_mode" == "full" ] 
then
restore_db_full;
elif [ "$restore_mode" == "single" ]
then
restore_db_single
else
echo "wrong arugment: "
usage;
fi
