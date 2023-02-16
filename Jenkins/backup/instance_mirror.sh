#!/bin/bash
#
### mirror from Prod 5G towards 5G secondary server: esling136.emea.nsn-net.net
###
### Vladimir Pavlovic e-mail:vladimir.pavlovic@nokia.com March 2017 ###
##passhprase jenkinsadm
### Global VARS ###

NUMBER=`ps -edf | grep instance_mirror | grep -v vi | grep -v tail |  grep -v grep | wc -l`
ps -edf | grep instance_mirror | grep -v vi | grep -v tail |  grep -v grep
echo ${NUMBER}
if [ ${NUMBER} -ge 4 ];then
exit 555
fi

SIZE=`ssh esling135.emea.nsn-net.net "df -h /var/fpwork" |tail -1 |awk '{print $5}' | sed 's/%//g' |awk '{print $1}'`
if [ ${SIZE} -ge 96 ];then
exit 444
fi

export SSH='/usr/bin/ssh'
PWD='/home/ca_scmjenkinsadm/Jenkins_tools/scripts'
RSYNC='/usr/bin/rsync'
rsync_opt='-r -l -p -o -t -h -g -a -z -D --stats --del'
rsync_opt_add="--out-format='%i %n%L'" #add more verbosity
rsync_dbg_opt='-v --progress'
rsync_exclude='--exclude '/Jenkins_Home/webapps/bin/instance.rc''
SSH='/usr/bin/ssh'
#dbg_mode_on=0
MIRROR_DIR='/var/fpwork/'
CFG_INSTANCE='/home/ca_scmjenkinsadm/Jenkins_tools/scripts/instances_list.cfg'
SCRIPT_NAME='instance_mirror.sh'
#### ON/OFF Debug ###


### Date used for hourly backup log file ###
NOW=$(date +"%m-%d-%Y-%T")
START_TIME=`date +"%T"`
### Send email with log file content ###
function mail_notify_home {
#mailto="vladimir.pavlovic@alcatel-lucent.com,strahinja.sarovic.ext@nokia.com,tamara.gengo.ext@nokia.com,stephane.gouverne-maingault@nokia.com"      #jean_luc.pinardon@alcatel-lucent.com,tijana.sutara@alcatel-lucent.com,nenad.sladojevic@alcatel-lucent.com"    #,jean_luc.pinardon@alcatel-lucent.com" # ,aleksandar.milovac@alcatel-lucent.com"  #this one adds other persons (+ comma)julien.errera@alcatel-lucent.com,jean_luc.pinardon@alcatel-lucent.com
#mailto="stephane.gouverne-maingault@nokia.com richard.raynaud@nokia.com alain.treille@nokia.com"
mailto="jenkins-solution@list.nokia.com"
#jean_luc.pinardon@alcatel-lucent.com,tijana.sutara@alcatel-lucent.com,nenad.sladojevic@alcatel-lucent.com"    #,jean_luc.pinardon@alcatel-lucent.com" # ,aleksandar.milovac@alcatel-lucent.com"  #this one adds other persons (+ comma)julien.errera@alcatel-lucent.com,jean_luc.pinardon@alcatel-lucent.com
#mailto_from="mts-support-elsys-design@acos.alcatel-lucent.com"
mailto_from="jenkins-solution@list.nokia.com"
subject="Jenkins 5G Instances Mirroring" 
file_to_send=`cat $MIRROR_DIR/$NOW.log`
deamon=`cat $MIRROR_DIR/$NOW.log | mailx -r $mailto_from -s "$subject" $mailto`
}

### Get PID of the running program ###
PIDFILE="/tmp/${SCRIPT_NAME}.pid"
ps hf -opid -C "${SCRIPT_NAME}" | awk '{ print $1;exit }' > "${PIDFILE}"
get_pid=`cat $PIDFILE`

if [ -s $PIDFILE ]; then
echo "===========================================================================
Starting Rsync Backup with PID => $get_pid" >> $MIRROR_DIR/$NOW.log 2>&1
else "PID File does not exist please check if script is started correctly" >> $MIRROR_DIR/$NOW.log 2>&1
mail_notify_home                                #send mail with error and exit
exit
fi
echo "START_TIME => $START_TIME" >> $MIRROR_DIR/$NOW.log 2>&1
### DISK SPACE BEFORE RSYNC ###
du_before=`df -h /var/fpwork |tail -1 |awk '{print "DISK_SIZE="$1, "DISK_USED="$2, "DISK_FREE="$3, "PERC_USED="$4}'`
echo "DISK Usage /var/fpwork BEFORE Rsync backup => $du_before" >> $MIRROR_DIR/$NOW.log 2>&1

### Remove last log file (from previous backup) to have clean env ###
if [ -f $MIRROR_DIR/*last ]; then
        echo "Old logs" >> $MIRROR_DIR/$NOW.log 2>&1
cd $MIRROR_DIR
ls -la |grep last |awk '{print $9}' |xargs rm -rfv  >> $MIRROR_DIR/$NOW.log 2>&1
else
        echo "Log File does not exist" >> $MIRROR_DIR/$NOW.log 2>&1
fi
cd $PWD

### Check if Backup dir is mounted on NAS,trigger automount as well ###
cd $MIRROR_DIR
rc_cd=$?
if [ $rc_cd == 0 ]; then
        echo "OK - Can chdir into => $MIRROR_DIR " >> $MIRROR_DIR/$NOW.log 2>&1
else
        echo "CRITICAL CANNOT Change dir into $MIRROR_DIR, please check why /var/fpwork is not accessible ERROR CODE = $rc" >> $MIRROR_DIR/$NOW.log 2>&1
mail_notify_home                                #send mail with error and exit
exit
fi

### Get Nas location in report ###
mount_check=`/bin/mount |grep "/var/fpwork"| awk '{print $1, $3}'`   
rc_mount=$?
if [[ "$mount_check" =~ "/dev/mapper/vg01-lvol1 /var/fpwork" ]] || [[ "$mount_check" =~ "/dev/vdb /var/fpwork" ]]; then
        echo "NAS Location OK => $mount_check" >> $MIRROR_DIR/$NOW.log 2>&1
else
        echo "NAS Location Not mounted Please check why /var/fpwork is not mounted"  >> $MIRROR_DIR/$NOW.log 2>&1
mail_notify_home                                #send mail with error and exit
exit
fi

cd $PWD

### check if config file exist ###
if [ ! -f $CFG_INSTANCE ]; then
        echo "Config file does not exist please check environment **CANNOT START BACKUP**" >>  $MIRROR_DIR/$NOW.log 2>&1
mail_notify_home                                #send mail with error and exit
exit
else
        echo "Config file exist => $CFG_INSTANCE" >>  $MIRROR_DIR/$NOW.log 2>&1
        echo "All ENV checks are OK, proceeding with Rsync Backup
" >>  $MIRROR_DIR/$NOW.log 2>&1
fi
rm $PIDFILE
### Read instance config from file, do ssh & rsync in one dir on each hour (just deltas) ###
for instance in $(cat $CFG_INSTANCE); do
# Forget line starting with #
if [ ${instance:0:1} == '#' ]; then
        continue
fi
real_isntance=`echo $instance | awk -F"/" '{print $4}'`
TIMEFORMAT=EXEC_TIME_$real_isntance=%Rsec
        echo "===========================================================================
Archiving instance $real_isntance
Mirror location: $MIRROR_DIR/$real_isntance
" >> $MIRROR_DIR/$NOW.log 2>&1

rsync_cmd=`{ time $RSYNC $rsync_opt $instance $MIRROR_DIR/$real_isntance; }  >>  $MIRROR_DIR/$NOW.log 2>&1`
rc=$?

### Get return code from rsync cmd ###
if [ $rc == 0 ]; then
        echo "
RSYNC BACKUP for $real_isntance OK
" >> $MIRROR_DIR/$NOW.log 2>&1
else
        echo "RSYNC BACKUP for $real_isntance NOK ERROR CODE = $rc
" >> $MIRROR_DIR/$NOW.log 2>&1
fi

done

### Calculate complete exec time after rsync,parse EXEC_TIME from log file ###
TOTAL_exec=`cat $MIRROR_DIR/$NOW.log | grep "EXEC_TIME" | cut -d "=" -f2 |cut -d "=" -f2 | cut -d "." -f1 |xargs | sed -e 's/ /+/g' | bc`
hour=`echo $TOTAL_exec/3600 |bc`
minute=`echo $TOTAL_exec%3600/60 |bc`
seconds=`echo $TOTAL_exec%60 |bc `
echo "===========================================================================
Complete backup execution took $TOTAL_exec seconds => $hour hour $minute minute $seconds seconds
LOG file => $MIRROR_DIR/$NOW.log_last" >> $MIRROR_DIR/$NOW.log 2>&1

### DISK Usage after RSUNC BACKUP ###
du_after=`df -h /var/fpwork |tail -1 |awk '{print "DISK_SIZE="$1, "DISK_USED="$2, "DISK_FREE="$3, "PERC_USED="$4}'`
END_TIME=`date +"%T"`
echo "DISK Usage /var/fpwork AFTER Rsync backup => $du_after" >> $MIRROR_DIR/$NOW.log 2>&1
echo "END_TIME => $END_TIME
===========================================================================
" >> $MIRROR_DIR/$NOW.log 2>&1

sleep 2
### Call functions ###
mail_notify_home

### Move last log file for Debug purpose ###
mv $MIRROR_DIR/$NOW.log $MIRROR_DIR/log_last/$NOW.log_last

