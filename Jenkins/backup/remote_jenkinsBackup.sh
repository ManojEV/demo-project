#!/bin/bash

#usage: jenkinsBackup.sh <config file>
#Author: Strahinja SAROVIC strahinja.sarovic.ext@nokia.com



#initialization
checkConditions=0
s=$0
fullScriptName="${s##*/}"
scriptName="${fullScriptName%.*}"

scriptPath=`pwd -P`
mail_body=""
mail_body_error=""
rsync_options=""


#send email function
function sendEmail {
	if [ "$mail_enabled" = "true" ]; then
		if [ "$1" = 1 ]; then
			if [ -n "$mail_body_error" ]; then
				echo $mail_body_error | mail -r $mailFrom -s "$subject_error $instanceName" $mailTo
			fi
		fi
		
		if [ "$1" = 0 ]; then
				cat $logFile | sed 's/^/ /g'  | mail -r $mailFrom -s "$subject $instanceName" $mailTo
		fi
	fi
}



#check if config file is available and readable

configFile=$1

if [ -r "$configFile" ]; then
	checkConditions=$((checkConditions+1))
	source $configFile   #load config file
else	
	echo "ERROR: config file is not available"
	exit $?
fi

#find builds directory under jobs to exclude while rsync
find $instanceRootDir -type d -name "builds" | sed 's/\/var\/fpwork\/5G_CIMASTER_3\///g' > /tmp/temp.txt

#check if rsync is available

if type "$rsync_bin" &> /dev/null; then
	checkConditions=$((checkConditions+1))
else 
	echo "ERROR: The script was unable to find rsync binary"
	mail_body_error="$mail_body_error 
	ERROR: The script was unable to find rsync binary"
	sendEmail 1 
	exit $?
fi


#ckeck if log dir exists, if not: make it and double check

if ! [ -d "$logPath" ]; then
	echo "Making $logPath directory to store logs into... "
	mkdir -p "$logPath"
fi

if [ -d "$logPath" ]; then
	checkConditions=$((checkConditions+1))
else 
	echo "ERROR: The script was unable to make log directory $logPath"
	mail_body_error="$mail_body_error 
	ERROR: The script was unable to make log directory $logPath"
	sendEmail 1 
	exit $? 
fi


if ! [ "$checkConditions"=3 ]; then
	#Send email and exit
	mail_body_error="$mail_body_error 
	ERROR: error code: $checkConditions"
	sendEmail 1
	exit $?

else

	if ! [ -d "$instanceRootDir" ]; then
		mail_body_error="$mail_body_error 
		ERROR: Instance root dir: $instanceRootDir does not exist"
		sendEmail 1
		exit $?;
	fi

	###if ! [ -d "$instanceBackupDir" ]; then
		####mail_body="$mail_body \n INFO: Making insatance bacup dir: $instanceBackupDir "
		###mkdir -p "$instanceBackupDir"   #Make backup dir
	###fi	
	ssh $server "mkdir -p $instanceBackupDir"

	#echo "Instance backup dir: $instanceBackupDir"	
	#Backup starts here
	BACKUP_START_TIME=$SECONDS
	
	logFile="$logPath/$logFilePrefix"
	date=`date +%Y-%m-%d_%H-%M-%S`
	logFile="$logPath/$logFilePrefix"
	logFile="$logFile"_"$date".log
	
	echo -ne ">>>> Backup of instance $instanceName started. Time: `date`\n\n" > $logFile

	echo "------------------------------------------------------------------------------" >>$logFile
	echo  -ne ">>>> RSYNC:  `date`\n\n" >>$logFile
	
	#check if we should exclude BuildData
	
	if [ "$excludeBuildData" = "true" ]; then
	#	$rsync_bin -av --exclude={Jenkins_BuildData,Jenkins_Home/jobs/**/workspace*} --delete --stats  $instanceRootDir/  $server:$instanceBackupDir/current >> $logFile
	        $rsync_bin -av --exclude-from='/tmp/temp.txt' --delete --stats  $instanceRootDir/  $server:$instanceBackupDir/current >> $logFile
	else
		$rsync_bin -av --delete --stats $instanceRootDir/  $server:$instanceBackupDir/current >> $logFile
	fi
	
	
	#$rsync_bin $rsync_options $instanceRootDir/  $instanceBackupDir/current >> $logFile
	echo "------------------------------------------------------------------------------" >>$logFile
	
	#Hardlinking
	echo  -ne ">>>> Hardlinking: `date`  \n\n" >> $logFile
	ssh $server "mkdir $instanceBackupDir/$date"
	ssh $server "cp -al $instanceBackupDir/current/* $instanceBackupDir/$date/"
	echo "Current backup of instance $instanceName: $server:$instanceBackupDir/$date " >> $logFile
	echo "finished @ `date`" >> $logFile
	echo "------------------------------------------------------------------------------" >>$logFile
	#Cleaning
	echo ">>>> Doing auto clean...." >> $logFile
	echo -ne "\t Backups: removing older than $keepBackup\n">> $logFile
	echo -ne "\t Logs: removing older than $keepLog\n">> $logFile
	# ssarovic: fix permissions - noted on ET isntance
	ssh $server "find $instanceBackupDir/* -maxdepth 0 -type d ! -name \"current*\" -mtime +$keepBackup -exec /bin/chmod -R +w {} \;"
	ssh $server "find $instanceBackupDir/* -maxdepth 0 -type d ! -name \"current*\" -mtime +$keepBackup -exec /bin/rm -rf {} \;"
	find $logPath/* -maxdepth 0 -type f -mtime +$keepLog -exec /bin/rm -rf {} \;
	echo "finished @ `date`" >> $logFile
	echo "------------------------------------------------------------------------------" >> $logFile
	
	BACKUP_ELAPSED_TIME=$(($SECONDS - $BACKUP_START_TIME))
	echo -ne "\n\nDONE in: $(($BACKUP_ELAPSED_TIME/60)) min $(($BACKUP_ELAPSED_TIME%60)) sec\n\n" >> $logFile
	
	#format log file:
	header="Backup of instance $instanceName FINISHED (`date`)\nThis backup is placed in $instanceBackupDir/$date\n\nInfo:\n\n\tInstance URL: $instanceURL\n\tRoot dir: $instanceRootDir\n\tBackup path: $instanceBackupDir\n\tTotal execution time: $(($BACKUP_ELAPSED_TIME/60)) min $(($BACKUP_ELAPSED_TIME%60)) sec\n\nDetails: \n"
	
	echo -ne "$header\n$(cat $logFile)\n" > $logFile
	racine=`dirname $instanceBackupDir`
	ssh $server "mkdir -p $racine/log"
	scp $logFile "$server:$racine/log"
	ssh $server "find $racine/log/* -maxdepth 0 -type f -mtime +$keepLog -exec /bin/rm -rf {} \;"

	sendEmail 0
	
fi
