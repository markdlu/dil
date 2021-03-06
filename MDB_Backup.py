#!/usr/bin/python
#history:
#  Brian Ackerman   -- initial
#  Shumaila Saleem  -- adding incremental backup
#  Mark Lu          -- adding log_check1 function of full backup 12/26/2019
#                   -- adding nodata schema via mysqldump to full backup dir 12/26/2019
#                   -- reformat content  12/26/2019
#                   -- adding backup ServerSnapshot backup 01/16/2020
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
def retention_cleanup(dir, databse):
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

def log_check1(bkp_db_name, filename, path, bkptype):
  global status
  status = "completed" if "complete" in open(filename).read() else "failed"


def do_backup():
  get_connection()
  #Begin Backup Loop
  for r in result:
    #IF Read Only is OFF
    if "OFF" in r:
    #Get DB List (Returns a TUPLE)
      cur.execute(dblist)
      snpshot_bkp_path = backup_root_dir + hostname + "/ServerSnapshot" + time.strftime("/%Y-%m-%d-%H%M/")
      #snpsht_bkp_cmd = "mariabackup --backup --target-dir=" + snpshot_bkp_path + "  --user mdbbackupuser --password=MdB8qL1E7Pbup --no-lock --open-files-limit 3500 2> " + snpshot_bkp_path + "backup_logfile.log"
      snpsht_bkp_cmd = "mariabackup --backup --target-dir=" + snpshot_bkp_path + "  --user mdbbackupuser --password=mdb8qL1E7Ubkup --no-lock --open-files-limit 3500 2> " + snpshot_bkp_path + "backup_logfile.log"
      snpshot_ret_path = backup_root_dir + hostname + "/ServerSnapshot"
      backup_folder(snpshot_bkp_path)
      os.system(snpsht_bkp_cmd)
      log_check("ServerSnapShot", snpshot_bkp_path + "backup_logfile.log",snpshot_ret_path,"full")
      retention_cleanup(snpshot_ret_path,"ServerSnapshot")
      dbs = cur.fetchall()
      for d in dbs:
        #Convert Tuple to String and concatonate with path and command. Path Created will be /backuplocation/dbname/year/month-day/24hrtime
        dbstr = ''.join(d)
        targetdir_bkp_path = backup_root_dir + hostname + "/" + dbstr +"/" + time.strftime("/%Y-%m%d/") + "/" +  time.strftime("/%Y-%m-%d-%H%M/")
        basedir_bkp_path = backup_root_dir + hostname + "/" + dbstr + "/" + time.strftime("/%Y-%m%d/") + "/" + time.strftime("/%Y-%m-%d/")
        #basedir_bkp_path = "/mysqltstbackup/chc01mysql01/mybackuptest1/2019-11-20/"
        db_ret_path = backup_root_dir + hostname + "/" + dbstr
        # ---------- CHANGE TO APPROPRIATE CREDENTIALS

        inc_bkp_cmd = "/usr/bin/mariabackup --backup --databases='"+dbstr+"' --target-dir='" + targetdir_bkp_path + "'  --incremental-basedir='"+basedir_bkp_path+"'  --user mdbbackupuser --password=mdb8qL1E7Ubkup --no-lock 2> " +targetdir_bkp_path+ "inc_backup_logfile.log"
        full_bkp_cmd = "/usr/bin/mariabackup --backup --databases='"+dbstr+"' --target-dir='" + basedir_bkp_path + "'  --user mdbbackupuser --password=mdb8qL1E7Ubkup --no-lock 2> " +basedir_bkp_path+ "backup_logfile.log"
        mysqldump_schema= "/usr/bin/mysqldump  --user mdbbackupuser --password=mdb8qL1E7Ubkup  --no-data " + dbstr + " > "+basedir_bkp_path+"schema_only.sql"


        if os.path.exists(basedir_bkp_path):
	  log_check1(dbstr, basedir_bkp_path + "backup_logfile.log", basedir_bkp_path ,"full")
          if status == "completed":
            backup_folder(targetdir_bkp_path)
            os.system(inc_bkp_cmd)
            if dbstr != "mysql" and dbstr !="information_schema" and dbstr != "performance_schema":
              os.system(mysqldump_schema)
            print(dbstr)
            print("incremenal backup")
	    log_check(dbstr, targetdir_bkp_path + "inc_backup_logfile.log", targetdir_bkp_path ,"inc")
            retention_cleanup(basedir_bkp_path,d)
          else:
            print(dbstr)
            shutil.rmtree(basedir_bkp_path)   
            print("full backup, fixing")
            backup_folder(basedir_bkp_path) 
            os.system(full_bkp_cmd)   
            if dbstr != "mysql" and dbstr !="information_schema" and dbstr != "performance_schema":
              os.system(mysqldump_schema)
	    log_check(dbstr, basedir_bkp_path + "backup_logfile.log", basedir_bkp_path ,"full")
            retention_cleanup(basedir_bkp_path,d)
        else: 
          print(dbstr)
          backup_folder(basedir_bkp_path) 
     	  os.system(full_bkp_cmd) 	
          if dbstr != "mysql" and dbstr !="information_schema" and dbstr != "performance_schema":
     	    os.system(mysqldump_schema) 	
          print("full backup")
	  log_check(dbstr, basedir_bkp_path + "backup_logfile.log", basedir_bkp_path ,"full")
          retention_cleanup(basedir_bkp_path,d)
			
                      
def main():
  do_backup()

if __name__=="__main__":
  main()
