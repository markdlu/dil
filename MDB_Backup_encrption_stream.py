#!/usr/bin/python
#history:
#  Brian Ackerman   -- initial
#  Shumaila Saleem  -- adding incremental backup
#  Mark Lu          -- adding log_check1 function of full backup 12/26/2019
#                   -- adding nodata schema via mysqldump to full backup dir 12/26/2019
#                   -- reformat content  12/26/2019
#
#
import os, shutil
import datetime, time
import mysql.connector as mariadb
import socket
from influxdb import InfluxDBClient



#influx connection
def get_influx():
  sec_influx_host = 'sec01u0inf01.npres.local'  # Sec NonProd Influx server
  #sec_influx_host = 'sec11p2podinf01.res.local' #Sec Prod Influx server
  my_database = 'backuptest'
  my_retpol = '4_weeks'
  use_ssl = False
  verify_ssl = False
  #influx_client = InfluxDBClient(sec_influx_host, 8086, 'dbuptime', 'PWHere', my_database, use_ssl, verify_ssl) #Prod
  global influx_client
  influx_client = InfluxDBClient(sec_influx_host, 8086, 'pytest', 'pytest', my_database, use_ssl, verify_ssl) #Non-Prod

#Data set for backup logging
def inf_data(host, bkpstatus, databasename, path, bkptype):
  json_data=[{
    "measurement":"mariaDB_backups",
    "tags": { "host": host },
    "fields":{ 
      "bkpstatus": bkpstatus,
      "host": host,
      "database": databasename,
      "path": path,
      "bkptype": bkptype
    }}]
  return json_data

#data set for backup deletion logging
def del_log(host, path, dbname):
  json_data=[{
    "measurement":"mariaDB_backup_deletions",
    "tags": { "host": host },
    "fields":{
      "host": host,
      "path": path,
      "dbname": dbname
     }}]
  return json_data

#Backup retention Function
def retention_cleanup(dir, database):
  now = time.time()
  for d in os.listdir(dir):
    dirname = os.path.join(dir, d)
    if os.stat(dirname).st_mtime < now - 1 * 86400:
      json_data = del_log(hostname, dirname, database)
      influx_client.write_points(json_data)
      print(dirname)
      shutil.rmtree(dirname)


def get_connection():
  #Connection Parameter - can be replaced with hostname or list
  unix_socket = "/var/lib/mysql/mysql.sock" #(socket.gethostname())
  global backup_root_dir
  backup_root_dir = "/mysqltstbackup/"
  currentdate = datetime.datetime.now()
  global hostname
  hostname = socket.gethostname()
  print(hostname)
  #bkp_path = time.strftime("/%Y/%m-%d/%H%M")
  #Query to determine if host is read only
  ro_status = ("show global variables like 'read_only%'")
  #Query to pull DB list
  global dblist
  dblist = ("show databases")
  #DB Connection string ----------- CHANGE TO APPROPRIATE CREDENTIALS
  #db = mariadb.connect(user='mdbbackupuser', password='MdB8qL1E7Pbup', unix_socket=unix_socket)
  global db
  db = mariadb.connect(user='mdbbackupuser', password='mdb8qL1E7Ubkup', unix_socket=unix_socket)
  #Define Cursor to run query to see if host is Read only or not
  global cur
  cur = db.cursor()
  cur.execute(ro_status)
  global result
  result = cur.fetchall()

def backup_folder(foldername):
  try:
    os.stat(foldername)
  except:
    os.makedirs(foldername)
    os.chmod(foldername,0o777)

#Logging function
def log_check(bkp_db_name, filename, path, bkptype):
  get_influx()
  try:
    status = "completed" if "complete" in open(filename).read() else "failed"
    json_data = inf_data(hostname, status, bkp_db_name, path , bkptype)
    influx_client.write_points(json_data)
  except:
    print("Unable to check log file on " + hostname)

def do_backup():
  get_connection()
  #Begin Backup Loop
  for r in result:
    #IF Read Only is OFF
    if "OFF" in r:
    #Get DB List (Returns a TUPLE)
      cur.execute(dblist)
      snpshot_bkp_path = backup_root_dir + hostname + "/ServerSnapshot" + time.strftime("/%Y-%m-%d-%H%M/")
      #snpsht_bkp_cmd = "mariabackup --backup --target-dir=" + snpshot_bkp_path + "  --user mdbbackupuser --password=mdb8qL1E7Ubkup --no-lock --open-files-limit 3500 2> " + snpshot_bkp_path + "backup_logfile.log"
      snpsht_backup_log = snpshot_bkp_path+'backup_logfile.log'
      snpsht_bkp_cmd = "/usr/bin/mariabackup --backup  --user mdbbackupuser --password=mdb8qL1E7Ubkup --no-lock --open-files-limit 3500 --stream=xbstream |openssl  enc -aes-256-cbc -k vaBq8D4RqujJvte7mq2OlUfeF8+sr3Nn |gzip  > " +snpshot_bkp_path+ "full_stream.enc.gz"
      run_snpsht_bkp_cmd = 'eval ' + '"' +snpsht_bkp_cmd + '"' + " > " + snpsht_backup_log + " 2>&1"
      snpshot_ret_path = backup_root_dir + hostname + "/ServerSnapshot"
      backup_folder(snpshot_bkp_path)
      os.system(run_snpsht_bkp_cmd)
      log_check("ServerSnapShot", snpshot_bkp_path + "backup_logfile.log",snpshot_ret_path,"full")
      retention_cleanup(snpshot_ret_path,"ServerSnapshot")
      dbs = cur.fetchall()
      for d in dbs:
        dbstr = ''.join(d)
        targetdir_bkp_path = backup_root_dir + hostname + "/" + dbstr +"/" + time.strftime("/%Y-%m%d/") + "/" +  time.strftime("/%Y-%m-%d-%H%M/")
        basedir_bkp_path = backup_root_dir + hostname + "/" + dbstr + "/" + time.strftime("/%Y-%m%d/") + "/" + time.strftime("/%Y-%m-%d/")
        db_ret_path = backup_root_dir + hostname + "/" + dbstr

        backupfile = targetdir_bkp_path+'full_stream.enc.gz'
        backup_log = targetdir_bkp_path+'backup_logfile.log'
        full_bkp_cmd = "/usr/bin/mariabackup --backup --databases='"+dbstr+"'  --user mdbbackupuser --password=mdb8qL1E7Ubkup --no-lock --stream=xbstream |openssl  enc -aes-256-cbc -k vaBq8D4RqujJvte7mq2OlUfeF8+sr3Nn |gzip  > " +targetdir_bkp_path+ "full_stream.enc.gz"
        run_full_bkp_cmd = 'eval ' + '"' +full_bkp_cmd + '"' + " > " + backup_log + " 2>&1"
        mysqldump_schema= "/usr/bin/mysqldump  --user mdbbackupuser --password=mdb8qL1E7Ubkup  --no-data " + dbstr + " > "+targetdir_bkp_path+"schema_only.sql"


        print(dbstr)
        backup_folder(targetdir_bkp_path) 
     	os.system(run_full_bkp_cmd) 	
        if dbstr != "mysql" and dbstr !="information_schema" and dbstr != "performance_schema":
     	  os.system(mysqldump_schema) 	
        print("full backup")
     	os.system("cd " + targetdir_bkp_path + "; pwd; ls -l " + targetdir_bkp_path) 	
	log_check(dbstr, targetdir_bkp_path + "backup_logfile.log", targetdir_bkp_path ,"full")
        retention_cleanup(targetdir_bkp_path,d)
			
                      
def main():
  do_backup()

if __name__=="__main__":
  main()
