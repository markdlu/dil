#!/bin/bash
#history Mark Lu 11/24/2019 initlized
# info: this script will restore the db to db_restore;
#       the /tmp/restore.info file contains path of full and/or incremental backup  
#       there is a schema_only.sql in full backupdir in case there is no 
#       object exists in orignal db          
#  Mark Lu -- modified for above fuction 12/27/2019
#
###############################################################

function set_env
{
export username=`cat $HOME/.pw |grep username |cut -d: -f2 `
export password=`cat $HOME/.pw |grep password |cut -d: -f2 `
}


function restore_db_single
{

targetdir=`cat /tmp/restore.info |grep fullbackupdir |cut -d':' -f2 `
incrementaldir=`cat /tmp/restore.info |grep incbackupdir |cut -d':' -f2`

#prepare full datadir first
echo "targetdir is:"  "$targetdir"
echo "incrementaldir is: " "$incrementaldir"
sudo /usr/bin/mariabackup --prepare --apply-log-only --target-dir=${targetdir}

#then prepare incremental dir
if [ -z "$incrementaldir" ] 
then
echo "no incremental backup yet"
else
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
echo "$0 [ dbname tablename ]" 
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

dbname=$1
tbname=$2

echo "number:"  $#
if [ "$#" != "2" ] 
then
echo "wrong argurment"
usage;
else
set_env;
restore_db_single
fi
