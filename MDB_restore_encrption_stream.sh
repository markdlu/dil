#!/bin/bash
#history Mark Lu 11/24/2019 initlized
# info: this script will restore the db to db_restore;
#       the /tmp/restore.info file contains path of full and/or incremental backup  
#       there is a schema_only.sql in full backupdir in case there is no 
#       object exists in orignal db          
#  Mark Lu -- modified for above fuction 12/27/2019
#          -- add restore a whole db 
#          -- modify restore db name with _$now 
#          -- modify using a temp backup dir in order to restore more than once
#          -- added ServerSnapshot whole instance restore option 01/16/2020
#
###############################################################

function set_env
{
export username=`cat $HOME/.pw |grep username |cut -d: -f2 `
echo "username: "  $username
export password=`cat $HOME/.pw |grep password |cut -d: -f2 `

export targetdir=`cat /tmp/restore.info |grep ^fullbackupdir |cut -d':' -f2 `
if [ "$targetdir" != "null" ]
then
if [ -d ${targetdir}_current ]
then
sudo rm -rf ${targetdir}_current
fi
sudo cp -rp ${targetdir} ${targetdir}_current 
sudo chmod -R 777 ${targetdir}_current
export targetdir=${targetdir}_current
fi

export incrementaldir=`cat /tmp/restore.info |grep ^incbackupdir |cut -d':' -f2`
if [ "$incrementaldir" != "null" ]
then
if [ -d ${incrementaldir}_current ]
then
sudo rm -rf ${incrementaldir}_current
fi
sudo cp -rp ${incrementaldir} ${incrementaldir}_current
sudo chmod -R 777  ${incrementaldir}_current
export incrementaldir=${incrementaldir}_current
fi

echo "targetdir is:"  "$targetdir"
echo "incrementaldir is: " "$incrementaldir"
now=`date +%Y%d%H%M%S`
#mysql -u${username} -p${password} -e "set global wsrep_on=OFF ;"
}

function de_en
{
gunzip $targetdir/full_stream.enc.gz
sudo bash -c "cd $targetdir; openssl enc -d -aes-256-cbc -k vaBq8D4RqujJvte7mq2OlUfeF8+sr3Nn -in full_stream.enc  | mbstream -x"
}

function restore_whole
{
export targetdir=`cat /tmp/restore.info | grep ^serversnapshotdir |cut -d':' -f2 `
echo "$targetdir"
if [ "$targetdir" != "null" ]
then
if [ -d ${targetdir}_current ]
then
sudo rm -rf ${targetdir}_current
fi
sudo cp -rp ${targetdir} ${targetdir}_current
sudo chmod -R 777 ${targetdir}_current
export targetdir=${targetdir}_current
else
echo "$targetdir is null, please update /tmp/restore.info file"
exit 1;
fi

#to decrypt and uncomress
de_en;
if [ $? != 0 ]
then
echo "de_en failed.."
exit 1
fi

#shutdown mariadb, clear /var/lib/mysql dir
echo "$targetdir"
sudo systemctl stop mariadb
sleep 3
echo "M1"
sudo bash -c "rm -rf /var/lib/mysql/*"

#prepare full datadir first
sudo /usr/bin/mariabackup --prepare --apply-log-only --target-dir=${targetdir}

#finally copy back from full datadir --restore
echo "copy back full to datadir..."
sudo /usr/bin/mariabackup --copy-back --datadir=/var/lib/mysql  --target-dir=$targetdir

sudo chown -R mysql:mysql /var/lib/mysql
sudo /usr/bin/galera_new_cluster
ps -ef |grep mysql
echo "mysql is up now.."
}

function restore_db
{

de_en;

#prepare full datadir first
sudo /usr/bin/mariabackup --prepare --apply-log-only --target-dir=${targetdir}

#then prepare incremental dir
if [ "$incrementaldir" == "null" ]
then
echo "no incremental backup yet"
else
echo "apply incremental to full..."
echo "targetdir is:"  "$targetdir"
echo "incrementaldir is: " "$incrementaldir"
sudo /usr/bin/mariabackup --prepare --apply-log-only --target-dir=${targetdir} --incremental-dir=${incrementaldir}
if [ $? != 0 ]
then
echo "incremental prepare failed.."
exit 1
fi
fi


#finally copy back from full datadir --restore
mysql -u${username} -p${password} -e "drop database ${dbname}_$now ;" 
grep "CREATE TABLE" $targetdir/schema_only.sql |cut -d' ' -f3 |sed 's/`//g' > table_all.txt
for i in `cat table_all.txt`
do
export tbname=$i
echo "table name is : " $tbname
create_object;
done

echo "copy table to new database ${dbname}_$now dir..."
sudo bash -c "cp -rp $targetdir/$dbname/* /var/lib/mysql/${dbname}_$now/."
sudo chown -R mysql:mysql /var/lib/mysql/${dbname}_$now/

for i in `cat table_all.txt`
do
export tbname=$i
mysql -u${username} -p${password} -e "ALTER TABLE ${dbname}_$now.$i IMPORT TABLESPACE;"
mysql -u${username} -p${password} -e "use ${dbname}_$now;select * from $i ;"
done

echo "restore db is done"

}


function restore_table
{

#decrpte and uncompress
de_en;

#prepare full datadir first
sudo /usr/bin/mariabackup --prepare --apply-log-only --target-dir=${targetdir}

#then prepare incremental dir
if [  "$incrementaldir" == "null" ]
then
echo "no incremental backup yet"
else
echo "apply incremental to full..."
echo "targetdir is:"  "$targetdir"
echo "incrementaldir is: " "$incrementaldir"
sudo /usr/bin/mariabackup --prepare --apply-log-only --target-dir=${targetdir} --incremental-dir=${incrementaldir}
if [ $? != 0 ]
then 
echo "incremental prepare failed.."
exit 1
fi
fi

#finally copy back from full datadir --restore
create_object;
echo "copy signgle table $tbname to new database ${dbname}_$now dir..."
sudo bash -c "cp -rp $targetdir/$dbname/$tbname.* /var/lib/mysql/${dbname}_$now/."
sudo chown -R mysql:mysql /var/lib/mysql/${dbname}_$now/
mysql -u${username} -p${password} -e "ALTER TABLE ${dbname}_$now.$tbname IMPORT TABLESPACE;"
mysql -u${username} -p${password} -e "use ${dbname}_$now;select * from $tbname ;"
echo "restore table is done"
}

function usage
{
echo "usage: "
echo "$0 whole all " 
echo "or"
echo "$0 db dbname " 
echo "or"
echo "$0 table dbname tablename " 
exit 1
}

function create_object
{
echo "running create object function..."
mysql -u${username} -p${password} -e "create database if not exists ${dbname}_$now ;" 
mysql -u${username} -p${password} -e "use ${dbname}_$now; drop table if exists ${tbname} ;" 
mysql -u${username} -p${password} -e "use $dbname;show create table ${tbname};" > create_tb.tmp
echo "use ${dbname}_$now;" > creat_tb.sql
tail -1 create_tb.tmp  | awk '{$1= ""; print $0}' >> creat_tb.sql 
fkflag=`cat creat_tb.sql |grep "FOREIGN KEY" |wc -l` 
if [ "$fkflag" == "1" ]
then
fk=`cat creat_tb.sql | grep -o -P '(?<=CONSTRAINT).*(?=FOREIGN)'`
echo ";alter table ${dbname}_$now.${tbname} drop FOREIGN KEY $fk;" >> creat_tb.sql 
echo "ALTER TABLE ${dbname}_$now.${tbname} DISCARD TABLESPACE; " >> creat_tb.sql
else
echo ";ALTER TABLE ${dbname}_$now.${tbname} DISCARD TABLESPACE; " >> creat_tb.sql
fi
mysql -u${username} -p${password} < creat_tb.sql > create_tb.out 2>&1
err=`cat create_tb.out |grep error |wc -l`
if [ "$err" != "0" ]
then
echo "table created failed, need to check..."
cat create_tb.out
exit 1
else 
echo "table $dbanme created in ${dbname}_$now"
fi
}

#main

restore_mode=$1
dbname=$2
tbname=$3

echo $#
if [ "$#" -lt "2" ] 
then
echo "wrong arguments"
usage;
fi

if [ "${restore_mode}" == "whole" ] && [ "${dbname}" == "all" ]
then
set_env;
restore_whole
elif [ "${restore_mode}" == "db" ]
then
set_env;
restore_db
elif  [ "${restore_mode}" == "table" ]
then
set_env;
restore_table
else
echo "Wrong restore_mode"
usage;
fi
