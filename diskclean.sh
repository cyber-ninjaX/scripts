#!/bin/bash -i
#-------------------------------------------------------------------------------------------------------------------------
scriptVersion=43
# Set to 1 to enable email, 0 to disable (logging must be enabled for email to function)
sendemail=1
#set to 1 to enable logging, 0 to disable (enabling logging disables console output)(this is depracated)
#logging=0
#set to 1 to enable shutdown upon completion, 0 to disable
shutDown=1
#set to 0 for fake shred (sleep 7 seconds) or 1 to enable shred
shredSwitch=1
#email addresses
# emailAddresses=( \
# 	nate@hivelocity.net \
# 	jhoward@hivelocity.net \
# 	vpaduano@hivelocity.net \
# 	vprotich@hivelocity.net \
# 	kfedorenko@hivelocity.net \
# 	lwilusz@hivelocity.net\
# 	)
emailAddresses=( drive.wipes@hivelocity.net )
#universal timeout for running tasks in the script.  's' for seconds (the default), 'm' for minutes, 'h' for hours or 'd' for days.
#timeoutAfter=1d
#time after the attempted soft timeout to kill the process.  's' for seconds (the default), 'm' for minutes, 'h' for hours or 'd' for days.
killAfter=1m
#set shred timeouts:
timeoutold=4h
timeout73=6h
timeout146=6h
timeout300=6h
timeout450=6h
timeout500=6h
timeout600=6h
timeout1000=6h
timeout2000=14h
timeout3000=18h
timeout4000=24h
timeout6000=28h
timeout8000=36h
timeout10000=48h
timeout12000=60h
timeout14000=70h
timeout16000=80h
timeout18000=90h
timeout20000=100h
timeoutUnknown=3d
#time to shred notes:
#---------------------
#8tb shred in Disk /dev/sdi Shredded in 21 Hours and 16 minutes and 26 seconds.
#6tb shred in Disk /dev/sdf Shredded in 11 Hours and 36 minutes and 29 seconds.
#6tb shred in Disk /dev/sdc Shredded in 19 Hours and 57 minutes and 49 seconds.
#3tb shred in Disk /dev/sdd Shredded in 11 Hours and 51 minutes and 42 seconds.
#3tb shred in Disk /dev/sde Shredded in 13 Hours and 57 minutes and 29 seconds.
#2tb shred in Disk /dev/sdd Shredded in 6 Hours and 36 minutes and 8 seconds. (pretty average)
#1tb shred in Disk /dev/sdb Shredded in 3 Hours and 12 minutes and 23 seconds. x 8 (about this long)
#500gb shred in Disk /dev/sde Shredded in 3 Hours and 6 minutes and 43 seconds. x lots. (pretty average time)
#-------------------------------------------------------------------------------------------------------------------------

#wait until active internet connection to run.
until ping -c1 8.8.8.8 &>/dev/null;do :;done

#get system ip address
systemIP=$(ip a sh `ip a sh | grep "state UP" | cut -f2 -d ":"` | grep inet | grep -v inet6 | awk '{print $2}' | cut -f1 -d "/")

#add path and shell so cron works
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/root
TERM=xterm-256color

## Log paths
finallog=/root/logs/final.log
synopsisLog=/root/logs/synopsis.log
errorLog=/root/logs/errors

## Initialize some other variables
complete="false"
status=1
pid=$$
setterm -blank 0

#micron 510dc firmware location (change directory if new version is released.)
micron510dcfirmwaredir="/root/firmware/micron/0013/"
micron510dcfirmware=$(echo $micron510dcfirmwaredir | cut -f5 -d "/")
#-------------------------------------------------------------------------------------------------------------------------
#log
#old log style saved for posterity
#if [[ "$logging" -eq "1" ]]; then
	##log everything
	#rm -rf $log
	#echo "`date +%x-%R` - $pid - Started Disk Clean" >> $log
	#exec >> $log
	#exec 2>&1
	## Everything below will go to the file '/var/log/diskclean.log':
#fi

#-------------------------------------------------------------------------------------------------------------------------
#determine disk info
#-------------------------------------------------------------------------------------------------------------------------
#Fill variables for discovered disks
function getDriveInfo() {
	unset device
	unset vendor
	unset deviceModel
	unset model
	unset serial
	unset firmware
	unset capacity
	unset status
	if [[ `echo $driveInterface` == "SATA" ]];then
		vendor=$(smartctl -i $diskPath | grep "Vendor" |cut -f2 -d ":"| sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
		model=$(msecli -L -n $diskPath | grep Model | cut -f2 -d ":"| sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
		deviceModel=$(smartctl -i $diskPath | grep "Device Model" |cut -f2 -d ":"| sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
		serial=$(msecli -L -n $diskPath | sed -n -e 4p | cut -f2 -d ":" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
		firmware=$(msecli -L -n $diskPath | sed -n -e 5p | cut -f2 -d ":" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
		capacity=$(msecli -L -n $diskPath | sed -n -e 6p | cut -f2 -d ":" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
		status=$(smartctl -H $diskPath | tail -2 | head -1)
	elif [[ `echo $driveInterface` == "SAS" ]];then
		vendor=$(smartctl -i $diskPath | grep "Vendor" |cut -f2 -d ":"| sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
		model=$(smartctl -i $diskPath | grep "Product" |cut -f2 -d ":"| sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
		deviceModel=$(smartctl -i $diskPath | grep "Device Model" |cut -f2 -d ":"| sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
		serial=$(udevadm info --query=all --name=$diskPath | grep "ID_SCSI_SERIAL" | cut -f2 -d "=")
		firmware=$(udevadm info --query=all --name=$diskPath | grep "ID_REVISION" | cut -f2 -d "=")
		capacity=$(parted -l 2> /dev/null |grep $diskPath | cut -f2 -d ":" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
		status=$(smartctl -H $diskPath | tail -2 | head -1)
	elif [[ `echo $driveInterface` == "NVME" ]];then
		vendor="Intel"
		model=$(isdct show -a -intelssd | grep ProductFamily | cut -f2 -d ":" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
		deviceModel=$(isdct show -a -intelssd | grep ModelNumber | cut -f2 -d ":" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
		serial=$(isdct show -a -intelssd | grep SerialNumber | cut -f2 -d ":" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
		firmware=$(isdct show -a -intelssd | grep Firmware | head -n 1 | cut -f2 -d ":" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
		capacity=$(expr `isdct show -a -intelssd | grep PhysicalSize | cut -f2 -d ":" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'` / 1000000000)
		status=$(isdct show -a -intelssd | grep DeviceStatus | cut -f2 -d ":" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
	else
		vendor=$(smartctl -i $diskPath | grep "Vendor" |cut -f2 -d ":"| sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
		model=$(msecli -L -n $diskPath | grep Model | cut -f2 -d ":"| sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
		deviceModel=$(smartctl -i $diskPath | grep "Device Model" |cut -f2 -d ":"| sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
		serial=$(msecli -L -n $diskPath | sed -n -e 4p | cut -f2 -d ":" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
		firmware=$(msecli -L -n $diskPath | sed -n -e 5p | cut -f2 -d ":" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
		capacity=$(msecli -L -n $diskPath | sed -n -e 6p | cut -f2 -d ":" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
		status=$(smartctl -H $diskPath | tail -2 | head -1)
	fi
}
function getDriveType() {
	if [[ `echo $driveInterface` == "SATA" ]];then
		driveTypeCheck=$(hdparm -I $diskPath | grep Nominal | grep Solid 2>/dev/null)
		if [[ -n $driveTypeCheck ]];then
			driveType=ssd
			driveTypeH=SSD
		elif [[ `echo $driveInterface` == "NVME" ]];then
			driveType=ssd
			driveTypeH=SSD			
		else
			driveType=hdd
			driveTypeH=HDD
		fi
	elif [[ `echo $driveInterface` == "SAS" ]];then
		driveType=hdd
		driveTypeH=HDD
	else
		driveType=unknown
	fi
}

function getDriveCount () {
	#determine boot disk so it isn't destroyed
	bootVolume=$(df -h |grep boot | awk '{print $1}' | sed s/1//g | cut -f3 -d "/")
	#load available disks into variable
	driveArrayPrimer=$(lsblk | grep disk |grep -v boot | awk '{print $1}' | grep -v $bootVolume | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/ /g')
	#dump variable into array
	driveArray=( `echo $driveArrayPrimer` )
	#set number of available disks
	driveCount=${#driveArray[*]}
	#echo drive count to log
	echo
	echo "Drives in System ($driveCount):" > $synopsisLog 
	echo ""  > $synopsisLog
}

#-------------------------------------------------------------------------------------------------------------------------
#check for failures
#-------------------------------------------------------------------------------------------------------------------------
function failureCheck() {
	errorcode=$?
	if [[ $errorcode != 0 ]];then		
		echo "Non-zero exit status. Command failed."
		#(( failures += 1 ))
		failures=`cat /root/logs/failures`
		failures=$((failures+1))
		echo $failures > /root/logs/failures
		echo Drive $serial errored
		echo "failing command was: $lastCommand, with error code $errorcode"
	fi
}
function incrementError() {
	failures=`cat /root/logs/failures`
	failures=$((failures+1))
	echo $failures > /root/logs/failures
}
#-------------------------------------------------------------------------------------------------------------------------
#determine drive manufacturer
#-------------------------------------------------------------------------------------------------------------------------
function determineManufacturer() {
	unset manufacturer
	unset manufacturerh
	if [[ `echo "$vendor" | grep -i kingston` ]] || [[ `echo "$model" | grep -i kingston` ]] || [[ `echo "$deviceModel" | grep -i kingston` ]];then
		manufacturer=kingston
		manufacturerh=Kingston
	elif [[ `echo "$vendor" | grep -i intel` ]] || [[ `echo "$model" | grep -i intel` ]] || [[ `echo "$deviceModel" | grep -i intel` ]]; then
		manufacturer=intel
		manufacturerh=Intel
	elif [[ `echo "$vendor" | grep -i micron` ]] || [[ `echo "$model" | grep -i micron` ]] || [[ `echo "$deviceModel" | grep -i micron` ]]; then
		manufacturer=micron
		manufacturerh=Micron
	elif [[ `echo "$vendor" | grep -i samsung` ]] || [[ `echo "$model" | grep -i samsung` ]] || [[ `echo "$deviceModel" | grep -i samsung` ]]; then
		manufacturer=samsung
		manufacturerh=Samsung
	elif [[ `echo "$vendor" | grep -i hgst` ]] || [[ `echo "$model" | grep -i hgst` ]] || [[ `echo "$deviceModel" | grep -i hgst` ]]; then
		manufacturer=hgst
		manufacturerh=HGST
	elif [[ `echo "$vendor" | grep -i hitachi` ]] || [[ `echo "$model" | grep -i hitachi` ]] || [[ `echo "$deviceModel" | grep -i hitachi` ]]; then
		manufacturer=hitachi
		manufacturerh=Hitachi
	elif [[ `echo "$vendor" | grep -i wd` ]] || [[ `echo "$model" | grep -i wd` ]] || [[ `echo "$deviceModel" | grep -i wd` ]]; then
		manufacturer=wd
		manufacturerh="Western Digital"
	elif [[ `echo "$vendor" | grep -i st` ]] || [[ `echo "$model" | grep -i st` ]] || [[ `echo "$deviceModel" | grep -i st` ]]; then
		manufacturer=seagate
		manufacturerh=Seagate
	elif [[ `echo "$vendor" | grep -i fujitsu` ]] || [[ `echo "$model" | grep -i fujitsu` ]] || [[ `echo "$deviceModel" | grep -i fujitsu` ]]; then
		manufacturer=fujitsu
		manufacturerh="Fujitsu"
	else
		manufacturer=unknown
		manufacturerh="Unknown Manufacturer"
	fi
}
#run tasks based on discovered manufacturer
function runManufacturerSpecificTasks() {
	if [[ `echo "$manufacturer" | grep -i kingston` ]];then
		kingstonDrive
	elif [[ `echo "$manufacturer" | grep -i intel` ]]; then
		intelDrive
	elif [[ `echo "$manufacturer" | grep -i micron` ]]; then
		micronDrive
	elif [[ `echo "$manufacturer" | grep -i samsung` ]]; then
		samsungDrive
	elif [[ `echo "$manufacturer" | grep -i wd` ]]; then
		wdDrive
	elif [[ `echo "$manufacturer" | grep -i seagate` ]]; then
		seagateDrive
	elif [[ `echo "$manufacturer" | grep -i fujitsu` ]]; then
		fujitsuDrive
	elif [[ `echo "$manufacturer" | egrep -i 'hgst|hitachi'` ]]; then
		hdDrive
	elif [[ `echo "$manufacturer" | grep -i unknown` ]]; then
		genericDrive
	fi
}
#-------------------------------------------------------------------------------------------------------------------------
#Perform tasks for specific manufacturers
#-------------------------------------------------------------------------------------------------------------------------
#micron specific functions
function micronDrive() {
	#determine micron drive model
	if [[ `echo $model | grep -i 510DC` ]]; then
		echo 510DC SSD detected
		microndrive=510dc
	else
		echo Unknown Micron SSD detected.
	fi
	#get and print remaining ssd life.  Micron uses raw value as percent remaining.
	lifeRemaining=$(smartctl -A $diskPath | grep "202 Unknown_SSD_Attribute" | awk '{print $4}'| sed 's/^0*//')
	ssdWear
	#510DC flashing
	if [[ `echo $microndrive` == "510dc" ]]; then
		if [ $firmware -lt "$micron510dcfirmware" ];then
			rm -rf cat /root/logs/micronlog-$disk.txt
			echo Firmware is version $firmware
			echo flashing 510DC SSD
			msecli -U -i $micron510dcfirmwaredir -S 0 -n $diskPath -r -s /root/logs/micronlog-$disk.txt
			cat /root/logs/micronlog-$disk.txt | sed -n -e 5p
			failureCheck
		elif [ $firmware -ge "$micron510dcfirmware" ];then
			echo Firmware is version $firmware
			echo Firmware is up to date, not flashing.
		fi
	fi
	ssdSmart
	start=`date +%s`
	#perform secure erase
	rm -rf cat /root/logs/micronerase-$disk.txt
	msecli -X -p password -n $diskPath -r -s /root/logs/micronerase-$disk.txt
	failureCheck
	cat /root/logs/micronerase-$disk.txt | sed -n -e 4p
	end=`date +%s`
	calculateTime
	echo "Secure erase operation completed in $runtime."
}
#intel specific functions
function intelDrive() {
	lifeRemaining=$(smartctl -A $diskPath | grep "233 Media_Wearout_Indicator" | awk '{print $4}' | sed 's/^0*//')
	#check for old 520 series SSD.
	if [[ `smartctl -i $diskPath | grep "Model Family" | grep 520` ]];then
		dcDrive="no"
	fi
	#get and print remaining ssd life
	ssdWear
	ssdSmart
	#Flash firmware
	if [[ $dcDrive == no ]];then
		secureErase
	elif [[ `echo $driveInterface` == "NVME" ]];then
		isdct start -f -intelssd $serial -nvmeformat | grep Status
		isdct load -f -intelssd $serial | grep Status
		echo "Wear:`isdct show -a -intelssd | grep EnduranceAnalyzer | cut -f2 -d ":"`"
	else
		isdct load -f -intelssd $serial | grep Status
		secureErase
	fi
}
#kingston specific functions
function kingstonDrive() {
	echo "Kingston doesn't support linux firmware updates. Those fucks."
	lifeRemaining=$(smartctl -A $diskPath | grep "231 Temperature_Celsius" | awk '{print $10}')
	ssdWear
	ssdSmart
	secureErase	
}
#samsung specific functions
function samsungDrive() {
	samsungSoftware="/root/tools/samsung_ddf_dc_toolkit/64/Samsung_SSD_DC_Toolkit_V1_x64"
	#check if it's a hdd or an ssd
	if [[ `smartctl -a $diskPath | grep Rotation | grep Solid` ]];then
		#drive is an ssd
		#only one instance of samsung software can run at a time, wait for others to finish.
		while ps aux | grep Samsung_SSD | grep -v grep > /dev/null;do
			sleep 1
		done
		#check for dc samsung drive
		samsungDcCheck=$($samsungSoftware -L | grep $serial)
		#if drive is not dc, run normal utilities
		if [[ -z $samsungDcCheck ]];then
			echo "Not a Samsung DC drive. Falling back to standard utilities."
			unset samsungDcCheck
			dcDrive=no
			lifeRemaining=$(smartctl -A $diskPath | grep "177 Wear_Leveling_Count" | awk '{print $4}' | sed 's/^0*//')
			ssdWear
			ssdSmart
			secureErase
		#if drive is dc drive, use samsung utilities.
		elif [[ -n $samsungDcCheck ]];then
			echo "Samsung DC class drive detected. Using samsung utilities."
			#get samsung disk number
			samsungDiskNumber=$($samsungSoftware -L | grep $serial | awk '{print $2}')
			lifeRemaining=$(smartctl -A $diskPath | grep "177 Wear_Leveling_Count" | awk '{print $4}' | sed 's/^0*//')
			ssdWear
			ssdSmart
			#perform secure erase
			$samsungSoftware -E -d $samsungDiskNumber --force | grep "Erase"
		fi
	else
		#drive is a hdd
		if [[ `echo $driveInterface` == "SATA" ]];then
			hddSmart > /dev/null
		elif [[ `echo $driveInterface` == "SAS" ]];then
			sasSmart > /dev/null
		fi
		entType=3
		whatToDoHddCheck
		if [[ `echo $driveInterface` == "SATA" ]];then
			hddSmart
		elif [[ `echo $driveInterface` == "SAS" ]];then
			sasSmart
		fi
		diskShred
	fi
}
function hdDrive() {
	if [[ `echo $model | egrep -i "HDS"` ]];then
		entTypeH="Not an Enterprise"
		entType="0"
	elif [[ `echo $model | egrep -i "HUA"` ]];then
		entTypeH="an Enterprise"
		entType="1"
	fi
	hddSmart > /dev/null
	whatToDoHddCheck
	hddSmart
	diskShred	
}
function wdDrive() {
	hddSmart > /dev/null
	wdModel=$(echo $model | sed 's/WDC WD//g' | cut -f1 -d "-" | sed 's/[^A-Z]*//g')
	wdCapacity="${wdModel:0:1}"
	entType="${wdModel:1:1}"
	#determine if enterprise or not
	if [[ `echo "$entType" | egrep -i 'B|D|K|L|Y'` ]];then 
		entTypeH="an Enterprise"
		entType="1"
	else
		entTypeH="Not an Enterprise"
		entType="0"
	fi
	#do maths on hours and sectors
	whatToDoHddCheck
	#gather smart info to log
	hddSmart
	#shred the disk
	diskShred
	
}
function seagateDrive() {
	if [[ `echo $driveInterface` == "SATA" ]];then
		hddSmart > /dev/null
	elif [[ `echo $driveInterface` == "SAS" ]];then
		sasSmart > /dev/null
	fi
	sgModel=$(echo $model | sed 's/ST//g' | sed 's/[^A-Z]*//g')
	#determine if enterprise or not
	if [[ `echo "$sgModel" | egrep -i 'NM|NS'` ]];then 
		entTypeH="an Enterprise"
		entType=1
	elif [[ `echo "$sgModel" | egrep -i 'SS'` ]];then
		entTypeH="an Enterprise 15k RPM"
		entType=2
	elif [[ `echo "$sgModel" | egrep -i 'DM'` ]];then
		entTypeH="Not an Enterprise"
		entType=0
	else
		entTypeH="Unknown if Enterprise"
		entType=3
	fi
	#do maths on hours
	whatToDoHddCheck
	#shred the disk	
	if [[ `echo $driveInterface` == "SATA" ]];then
		hddSmart
	elif [[ `echo $driveInterface` == "SAS" ]];then
		sasSmart
	fi
	diskShred
	#gather smart info to log
}
function fujitsuDrive() {
	rotationRate=$(smartctl -a $diskPath | grep Rotation | cut -f2 -d ":" )
	if [[ `echo "$driveType" | grep -i hdd` ]];then
		if [[ `echo $driveInterface` == "SATA" ]];then
			hddSmart > /dev/null
		elif [[ `echo $driveInterface` == "SAS" ]];then
			sasSmart > /dev/null
		fi
		diskShred
		if [[ -n `echo $rotationRate | grep 15` ]];then
			entType=2
		elif [[ -n `echo $rotationRate | grep 72` ]];then
			entType=1
		else
			entType=3
		fi	
		whatToDoHddCheck
		if [[ `echo $driveInterface` == "SATA" ]];then
			hddSmart
		elif [[ `echo $driveInterface` == "SAS" ]];then
			sasSmart
		fi
	elif [[ `echo "$driveType" | grep -i ssd` ]];then
		secureErase
		ssdSmart
	fi
	echo "Port: $lsiSlotIdNumber, $diskPath, $manufacturerh $driveInterface drive $model serial: $serial....Fujitsu Drive, Recycle." >> $synopsisLog
}
function genericDrive() {
	if [[ `echo "$driveType" | grep -i hdd` ]];then
		if [[ `echo $driveInterface` == "SATA" ]];then
			hddSmart
		elif [[ `echo $driveInterface` == "SAS" ]];then
			sasSmart
		fi
		diskShred		
		entType=3
		whatToDoHddCheck
		if [[ `echo $driveInterface` == "SATA" ]];then
			hddSmart
		elif [[ `echo $driveInterface` == "SAS" ]];then
			sasSmart
		fi
	elif [[ `echo "$driveType" | grep -i ssd` ]];then
		ssdWear
		secureErase
		ssdSmart
	else
		echo "Port: $lsiSlotIdNumber, $diskPath, $manufacturerh $driveInterface drive $model serial: $serial....I have no idea what this is." >> $synopsisLog
	fi
}

#-------------------------------------------------------------------------------------------------------------------------
#drive functions
#-------------------------------------------------------------------------------------------------------------------------
function whatToDoHddCheck() {
	#do maths on hours.
	#entType 0 = desktop class drive
	#entType 1 = enterprise class drive
	#entType 2 = enterprise 15k RPM class drive
	#entType 3 = unknown
	#desktop sell at 15k hours, enterprise sell at 20k hours, 15k rpm sell at 25k hours
	if [[ `echo $smartFail` == 1 ]];then
		whatToDo="SMART Fail, destroy drive."
	elif [[ `echo $ReallocatedSectorCt` -gt "0" ]];then
		whatToDo="Recycle for sector count"
	elif [[ `echo $entType` -eq 1 ]] && [[ `echo $powerOnHours` -ge 20000 ]];then
		overHours=1
		overHoursH="is over hours"
		whatToDo="Sell for over hours"
	elif [[ `echo $entType` -eq 1 ]] && [[ `echo $powerOnHours` -lt 20000 ]];then
		overHours=0
		overHoursH="is under hours"
		whatToDo="Return to inventory"
	elif [[ `echo $entType` -eq 2 ]] && [[ `echo $powerOnHours` -ge 25000 ]];then
		overHours=1
		overHoursH="is over hours"
		whatToDo="Sell for over hours"
	elif [[ `echo $entType` -eq 2 ]] && [[ `echo $powerOnHours` -lt 25000 ]];then
		overHours=0
		overHoursH="is under hours"
		whatToDo="Return to inventory"
	elif [[ `echo $entType` -eq 0 ]] && [[ `echo $powerOnHours` -ge 15000 ]];then
		overHours=1
		overHoursH="is over hours"
		whatToDo="Sell for over hours"
	elif [[ `echo $entType` -eq 0 ]] && [[ `echo $powerOnHours` -lt 15000 ]];then
		overHours=0
		overHoursH="is under hours"
		whatToDo="Return to inventory"
	elif [[ `echo $entType` -eq 3 ]] && [[ `echo $powerOnHours` -ge 15000 ]];then
		overHours=1
		overHoursH="is over hours"
		whatToDo="Unknown Drive Class, check manually."
	else
		whatToDo="Unknown Drive Class, Unkown hours. check manually."
	fi
	#we sell or scrap all 500's
	capacityN=`echo $capacity | cut -f1 -d "." | sed 's/[^0-9]*//g'`
	if [[ $capacityN == 500 ]];then
		whatToDo="Sell since it's a 500"
		if [[ `echo $ReallocatedSectorCt` -gt "0" ]];then
		whatToDo="Recycle for sector count"
		fi
	fi
	#echo "Port: $lsiSlotIdNumber, $diskPath, $manufacturerh drive $model serial: $serial is $sgTypeH drive at $powerOnHours hours $overHoursH." >> $synopsisLog
	echo "Port: $lsiSlotIdNumber, $diskPath, $manufacturerh $driveInterface drive $model serial: $serial....$whatToDo." >> $synopsisLog
	unset entType
}

#hdparm secure erase
function secureErase() {
	echo "Secure erase operation for $disk started at `date`"
	start=`date +%s`
	sleep 10
	hdparm --user-master u --security-set-pass hvvc $diskPath > /dev/null || failureCheck
	sleep 10
	lastCommand="hdparm --user-master u --security-erase hvvc $diskPath" ; hdparm --user-master u --security-erase hvvc $diskPath > /dev/null || failureCheck
	end=`date +%s`
	calculateTime
	echo "Secure erase operation completed in $runtime."
}
#Print disk info to screen
function echoDiskInfo() {
	echo $manufacturerh drive detected at $diskPath.
	echo Device: "$diskPath"
	echo Model: "$model"
	echo Serial: "$serial"
	echo Firmware Version: "$firmware"
	echo Capacity: "$capacity"
	echo Health Status: "$status"
	echo ATA Security Lock: "$ataLock"
}
function diskShred() {
	setTimeout
	echo "Disk shred for disk $diskPath started at `date`"
	echo "Disk shred for disk $diskPath started at `date`" > /dev/console
	if [[ `echo $shredSwitch` == "0" ]];then
		start=`date +%s`
		sleep 10	#fake shred
		end=`date +%s`
	elif [[ `echo $shredSwitch` == "1" ]];then
		start=`date +%s`
		logCheck &
		timeout -k $killAfter $timeoutAfter shred -n 1 -z $diskPath    #real shred
		end=`date +%s`
	fi
	calculateTime
	#report shred time to log/console
	echo "Disk $diskPath Shredded in $runtime."
	echo "Disk $diskPath Shredded in $runtime." > /dev/console
	#check if shred hit timeout and report to log if so.
	if [[ $runtimeMath == $timeoutSeconds ]];then
		echo "Shred hit Timeout, something's wrong."
	fi
}
#Hard drive SMART functions
function hddSmart() {
	#get power on hours
	powerOnHours=$(smartctl -A $diskPath | grep Power_On_Hours | awk '{print $10}')
	#get retired NAND count
	ReallocatedSectorCt=$(smartctl -A $diskPath | grep Reallocated_Sector_Ct | awk '{print $10}')
	#print to console
	echo "Power on Hours: $powerOnHours"
	echo "Reallocated Sectors: $ReallocatedSectorCt"
	if [[ `echo "$status" | grep -i passed` ]];then
		echo passed
		smartFail=0
	elif [[ `echo "$status" | grep -i failure` ]];then
		echo failure	
		smartFail=1
	fi

}
#SSD SMART functions
function ssdSmart() {
	#get power on hours
	powerOnHours=$(smartctl -A $diskPath | grep Power_On_Hours | awk '{print $10}')
	#get retired NAND count
	RetiredNAND=$(smartctl -A $diskPath | grep Reallocated_Sector_Ct | awk '{print $10}')
	#print to console
	echo "Power on Hours: $powerOnHours"
	echo "Retired NAND Count: $RetiredNAND"
}
function sasSmart() {
	if [[ `echo "$manufacturer" | grep -i seagate` ]]; then
		powerOnHours=$(smartctl -A $diskPath | grep hours | cut -f2 -d "=" | cut -f1 -d "." | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
	fi
	if [[ `echo "$status" | grep -i passed` ]];then
		echo passed
		smartFail=0
	elif [[ `echo "$status" | grep -i failure` ]];then
		echo failure	
		smartFail=1
	fi
}
function ssdWear() {
	echo "Life Remaining: $lifeRemaining%"
	if [[ `echo $dcDrive` == "no" ]];then
		whatToDo="Non-DC Drive, sell."
	elif [[ -z `echo $lifeRemaining` ]];then
		whatToDo="unable to determine wear."
	elif [[ `echo $lifeRemaining` -gt "5" ]];then
		whatToDo="Return to Inventory"
	elif [[ `echo $lifeRemaining` -le "5" ]];then
		whatToDo="Recycle for high wear"
	fi
	echo "Port: $lsiSlotIdNumber, $diskPath, $manufacturerh $driveInterface drive $model serial: $serial....$whatToDo." >> $synopsisLog
	unset lifeRemaining
}
#-------------------------------------------------------------------------------------------------------------------------
#calculate time for logs.
#-------------------------------------------------------------------------------------------------------------------------
function calculateTime() {
	unset runtimeSeconds
	unset runtimeMinutes
	unset runtimeHours
	runtimeMath=$((end-start))
	runtimeSeconds=$(date -u -d @${runtimeMath} +"%S" | sed 's/^0*//')
	if [[ -n $runtimeSeconds ]];then
		runtimeSeconds="$runtimeSeconds seconds"
	else
		runtimeSeconds="no seconds"
	fi
	runtimeMinutes=$(date -u -d @${runtimeMath} +"%M" | sed 's/^0*//')
	if [[ -n $runtimeMinutes ]];then
		if [[ $runtimeMinutes == "1" ]];then
		runtimeMinutes="$runtimeMinutes minute and "
		else
		runtimeMinutes="$runtimeMinutes minutes and "
		fi
	else
		runtimeMinutes=""
	fi
	runtimeHours=$(date -u -d @${runtimeMath} +"%H" | sed 's/^0*//')
	if [[ -n $runtimeHours ]];then
		if [[ $runtimeHours == "1" ]];then
		runtimeHours="$runtimeHours hour and "
		else
		runtimeHours="$runtimeHours Hours and "
		fi
	else
		runtimeHours=""
	fi
	runtime="$runtimeHours$runtimeMinutes$runtimeSeconds"
}
function calculateScriptTime() {
	unset runtimeSeconds
	unset runtimeMinutes
	unset runtimeHours
	runtimeMath=$((scriptEnd-scriptStart))
	runtimeSeconds=$(date -u -d @${runtimeMath} +"%S" | sed 's/^0*//')
	if [[ -n $runtimeSeconds ]];then
		runtimeSeconds="$runtimeSeconds seconds"
	else
		runtimeSeconds="no seconds"
	fi
	runtimeMinutes=$(date -u -d @${runtimeMath} +"%M" | sed 's/^0*//')
	if [[ -n $runtimeMinutes ]];then
		if [[ $runtimeMinutes == "1" ]];then
		runtimeMinutes="$runtimeMinutes minute and "
		else
		runtimeMinutes="$runtimeMinutes minutes and "
		fi
	else
		runtimeMinutes=""
	fi
	runtimeHours=$(date -u -d @${runtimeMath} +"%H" | sed 's/^0*//')
	if [[ -n $runtimeHours ]];then
		if [[ $runtimeHours == "1" ]];then
		runtimeHours="$runtimeHours hour and "
		else
		runtimeHours="$runtimeHours Hours and "
		fi
	else
		runtimeHours=""
	fi
	scriptRuntime="$runtimeHours$runtimeMinutes$runtimeSeconds"
}
#-------------------------------------------------------------------------------------------------------------------------
#lsi stuff
#-------------------------------------------------------------------------------------------------------------------------
#set path to megacli
megacli="/opt/MegaRAID/MegaCli/MegaCli64"

function lsiInfo () {
	#get number of drives from lsi card
	lsiNumberOfDrives=$($megacli -EncInfo -aALL | grep "Number of Physical Drives" | cut -f2 -d ":" | tr -d '[:space:]')
	lsiNumberOfSlots=$($megacli -EncInfo -aALL | grep "Number of Slots" | cut -f2 -d ":" | tr -d '[:space:]')
	lsiSlotCount=`expr $lsiNumberOfSlots - 1`
	#get lsi card device id
	lsiDeviceId=$($megacli -pdlist -aAll | grep Enclosure |head -1 | cut -f2 -d ":" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
	#set up array for available disks
	lsiDriveArrayPrimer=$(eval echo {0..$lsiSlotCount})
	lsiDriveArray=( `echo $lsiDriveArrayPrimer`)
	lsiFailedDisks=$($megacli -AdpAllInfo  -aAll | grep -i "failed disks" | cut -f2 -d ":" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
	lsicardcheck=$($megacli -EncInfo -aALL | grep "Number of Slots" | cut -f2 -d ":" | tr -d '[:space:]')
}

#is there an lsi card in the system?
lsicardcheck=$($megacli -EncInfo -aALL | grep "Number of Slots" | cut -f2 -d ":" | tr -d '[:space:]')
if [[ -z $lsicardcheck ]];then
	echo "No LSI card in JBOD mode found in system." >> $synopsisLog
else 
	lsiInfo
	#print number of drives the lsi card can see
	echo "LSI number of drives: $lsiNumberOfDrives" >> $synopsisLog
	echo "LSI number of slots: $lsiNumberOfSlots" >> $synopsisLog
	echo "LSI number of failed disks: $lsiFailedDisks" >> $synopsisLog
fi

if [[ $lsiFailedDisks -gt 0 ]];then
	echo "LSI card has detected $lsiFailedDisks failed disks attached." >> /root/logs/errors
	failures=`cat /root/logs/failures`
	failures=$((failures+1))
	echo $failures > /root/logs/failures
fi

function lsiFunction() {	
	#is there an lsi card in the system?  If so, do the LSI stuff.
	lsicardcheck=$($megacli -EncInfo -aALL | grep "Number of Slots" | cut -f2 -d ":" | tr -d '[:space:]')
	if [[ -n $lsicardcheck ]];then
		#if lsi card detected, do lsi stuff
		for lsiSlotId in "${lsiDriveArray[@]}";do
			wwn=$($megacli -pdinfo -PhysDrv [$lsiDeviceId:$lsiSlotId] -aAll |grep WWN | cut -f2 -d ":" | tr -d '[:space:]')
			wwnCheck=$(sdparm --inquiry $diskPath | grep -i `echo $wwn` 2> /dev/null)		
			if [[ -n `echo $wwnCheck` ]];then
				#echo "$lsiSlotId is $diskPath" >> $synopsisLog
				lsiSlotIdNumber=$lsiSlotId
				driveInterface=$($megacli -pdinfo -physdrv [$lsiDeviceId:$lsiSlotId] -aAll | grep "PD Type" | cut -f2 -d ":" |  tr -d '[:space:]')
				echo "Drive interface is: $driveInterface" >> $disklog
				echo "LSI Slot ID: $lsiSlotIdNumber" >> $disklog
			fi
		done
	elif [[ -z $lsicardcheck ]];then
		#if no lsi card is detected, we ned to get the disks interface type another way.
		#if smartctl sees the drive isnt sata
		if [[ -z `smartctl -a $diskPath | grep SATA` ]];then
			#see if it's sas
			sascheck=$(smartctl -a $diskPath | grep Transport | cut -f2 -d ':' | tr -d '[:space:]')
			if [[ `echo $sascheck` ]];then
				#if sas detected, set drive interface variable
				driveInterface=$sascheck
			elif [[ `echo $diskPath | grep nvme` ]];then
				driveInterface=NVME
			else
				#otherwise admit we don't know
				driveInterface="Unknwon Interface"
			fi
		#if smartctl sees it's sata
		elif [[ -n `smartctl -a $diskPath | grep SATA` ]];then
			#see if it's sata for sure
			satacheck=$(smartctl -a $diskPath | grep SATA)
			if [[ `echo $satacheck` ]];then
				#if sata is detected, set the variable
				driveInterface=$(smartctl -a $diskPath | grep SATA | cut -f2 -d ':' | awk '{print $1}'| tr -d '[:space:]')
			else
				#otherwise admit we don't know
				driveInterface="Unknwon Interface"
			fi
		fi
	fi	
}

function lsiSlotTestFunction() {
	lsiAttachhedSlots=()
	for lsiSlotId in "${lsiDriveArray[@]}";do
		lsiSlotTest=$($megacli -PDInfo -PhysDrv [$lsiDeviceId:$lsiSlotId] -aAll | grep -i "not found" 2> /dev/null)
		if [[ -n `echo $lsiSlotTest` ]];then
	 		echo "Port: $lsiSlotId is not attached."
	 	elif [[ -z `echo $lsiSlotTest` ]];then
	 		#echo "Port: $lsiSlotId is attached."
	 		lsiAttachhedSlots+=("$lsiSlotId")
		fi
	done
}
function clearForeign() {
	#clear foreign configs
	$megacli -CfgForeign -Clear -aALL > /dev/null
	#delete all virtual drives
	$megacli -cfglddel -lall -aall > /dev/null
	#make all drives jbod
	for lsiSlotId in "${lsiDriveArray[@]}";do
		$megacli -pdmakejbod -physdrv [$lsiDeviceId:$lsiSlotId] -aAll > /dev/null
	done
}
function fixJBOD () {
if [[ -n $lsicardcheck ]];then
	jbodCounter=0
	runtimeMath=0
	start=`date +%s`
	until (( "$jbodCounter" == "$lsiNumberOfDrives" || $runtimeMath >= 300 ));do
		clear
		jbodCounter=0
		echo "LSI number of drives: $lsiNumberOfDrives"
		echo "LSI number of slots: $lsiNumberOfSlots"
		echo "LSI number of failed disks: $lsiFailedDisks"
		echo waiting...
		for lsiSlotId in "${lsiAttachhedSlots[@]}";do
			fwstate=$($megacli -pdinfo -PhysDrv [$lsiDeviceId:$lsiSlotId] -aall| grep "Firmware state" | sed s/"Firmware state:"//g | sed s/" "//g)
			if [[ "$fwstate" != "JBOD" ]];then
				echo "Port: $lsiSlotId: is not JBOD"
				clearForeign
			else
				echo "Port: $lsiSlotId: is JBOD"
				jbodCounter=$((jbodCounter+1))
			fi
		done
		end=`date +%s`
		runtimeMath=$((end-start))
		timeRemaining=$((300-$runtimeMath))
		nonJbodDrives=$(($lsiNumberOfDrives-$jbodCounter))
		echo "Waiting on $nonJbodDrives drives to switch over."
		echo "Giving up in $timeRemaining Seconds."	
		echo "Time since start of script: $runtimeMath"
		echo "JBOD drives in system: $jbodCounter"
		sleep 5
	done
fi
}
function matchSystemAndLsiCount () {
	lsicardcheck=$($megacli -EncInfo -aALL | grep "Number of Slots" | cut -f2 -d ":" | tr -d '[:space:]')
	lsiInfo
	clear
	runtimeMath=0
	start=`date +%s`
	#echo $scsiHostCount
	#echo $systemHostCount
	#echo $driveCount
	if [[ -n $lsicardcheck ]];then
		end=`date +%s`
		runtimeMath=$((end-start))
		echo "Waiting for the system to see all available drives."
		drivesRemaining=$(($lsiNumberOfDrives-$driveCount))
		timeRemaining=$((300-$runtimeMath))
		if [[ -n $timeRemaining ]];then
			timeRemaining=0
		fi
		if [[ -n $drivesRemaining ]];then
			drivesRemaining=0
		fi
		echo "Giving up in $timeRemaining Seconds. $drivesRemaining drives are unaccounted for."
		echo "System drives visible: $driveCount."
		echo "LSI card reports $lsiNumberOfDrives drives."
		until (( "$lsiNumberOfDrives" == "$driveCount" || $runtimeMath >= 300 ));do
			clear
			scsiHostCount=$(ls /sys/class/scsi_host/ | wc -l)
			for lsiSlotId in "${lsiDriveArray[@]}";do
				echo "- - -" > /sys/class/scsi_host/host$lsiSlotId/scan
			done
			end=`date +%s`
			runtimeMath=$((end-start))
			echo "Waiting for the system to see all available drives."
			drivesRemaining=$(($lsiNumberOfDrives-$driveCount))
			timeRemaining=$((300-$runtimeMath))
			if [[ -n $timeRemaining ]];then
				timeRemaining=0
			fi
			if [[ -n $drivesRemaining ]];then
				drivesRemaining=0
			fi
			echo "Giving up in $timeRemaining Seconds. $drivesRemaining drives are unaccounted for."
			echo "System drives visible: $driveCount."
			echo "LSI card reports $lsiNumberOfDrives drives."
			getDriveCount
			sleep 5
		done
	fi
}
#-------------------------------------------------------------------------------------------------------------------------
#kill it!!!
#-------------------------------------------------------------------------------------------------------------------------
function killItWithFire() {
	for proc in `ps aux | egrep -i 'disk|sleep|shred|smartctl|msecli|isdct|Samsung_SSD_DC_Toolkit_V1_x64|hdparm' | awk '{print $2}'`;do
		kill -9 $proc
	done
	shutdown -c
}
#-------------------------------------------------------------------------------------------------------------------------
#unlock any disks.
#-------------------------------------------------------------------------------------------------------------------------
function ataUnlock() {
for disk in "${driveArray[@]}";do
	diskPath=/dev/$disk
	disklog="/root/logs/$disk.log"
	if [[ `hdparm -I $diskPath | grep locked | grep -v not`  ]];then
		ataLock="Locked"
		ataLockid=1
		echo "$diskPath is locked, unlocking." >> $disklog
		echo "$diskPath is locked, unlocking." 
		hdparm --security-disable password $diskPath
		if [[ `hdparm -I $diskPath | grep locked | grep -v not` ]];then
			echo "$diskPath unlocking failed." >> $disklog
			echo "$diskPath unlocking failed." 
		elif [[ `hdparm -I $diskPath | grep locked | grep not` ]];then 
			echo "$diskPath unlocking was successful." >> $disklog
			echo "$diskPath unlocking was successful." 
		fi
	elif [[ `hdparm -I $diskPath | grep locked | grep not` ]];then
		ataLock="Unlocked"
		ataLockid=0
	fi
	if [[ `hdparm -I $diskPath | grep frozen | grep -v not` ]];then
		echo "$diskPath is frozen." >> $disklog
		echo "$diskPath is frozen." 
	fi
done
}
#-------------------------------------------------------------------------------------------------------------------------
#set shred timeout based on disk capacity.
#-------------------------------------------------------------------------------------------------------------------------
function setTimeout() {
	#'s' for seconds (the default), 'm' for minutes, 'h' for hours or 'd' for days.
	capacityN=`echo $capacity | cut -f1 -d "." | sed 's/[^0-9]*//g'`
	if [[ `smartctl -a $diskPath | grep Rotation | grep Solid` ]];then
		echo "SSD detected, skipping timeout"
	else
		if [[ -n $timeoutAfter ]];then
			# if timeout already set via switch.
			timeoutAfter=$timeoutAfter
		elif [[ $capacityN == 73 ]];then
			timeoutAfter=$timeout73
			echo "73GB drive detected, timeout set to $timeoutAfter"
		elif [[ $capacityN == 146 ]];then
			timeoutAfter=$timeout146
			echo "146GB drive detected, timeout set to $timeoutAfter"
		elif [[ $capacityN == 300 ]];then
			timeoutAfter=$timeout300
			echo "300GB drive detected, timeout set to $timeoutAfter"
		elif [[ $capacityN == 450 ]];then
			timeoutAfter=$timeout450
			echo "450GB drive detected, timeout set to $timeoutAfter"
		elif [[ $capacityN == 500 ]] || [[ `echo $capacityN | egrep '(49[0-9])' | awk 'length($1) == 3'` ]] || [[ `echo $capacityN | egrep '(5[0-1][0-9])' | awk 'length($1) == 3'` ]];then
			timeoutAfter=$timeout500
			echo "500GB drive detected, timeout set to $timeoutAfter"
		elif [[ $capacityN == 600 ]];then
			timeoutAfter=$timeout600
			echo "600GB drive detected, timeout set to $timeoutAfter"
		elif [[ $capacityN == 1000 ]] || [[ `echo $capacityN | egrep '(1[0-1][0-9][0-9])' | awk 'length($1) == 4'` ]] || [[ `echo $capacityN | egrep '(9[0-9][0-9])' | awk 'length($1) == 3'` ]];then
			echo 1TB detected
			timeoutAfter=$timeout1000
			echo "1 TB drive detected, timeout set to $timeoutAfter"
		elif [[ $capacityN == 2000 ]] || [[ `echo $capacityN | egrep '(19[0-9][0-9])' | awk 'length($1) == 4'` ]] || [[ `echo $capacityN | egrep '(2[0-1][0-9][0-9])' | awk 'length($1) == 4'` ]];then
			#2TB
			timeoutAfter=$timeout2000
			echo "2 TB drive detected, timeout set to $timeoutAfter"
		elif [[ $capacityN == 3000 ]] || [[ `echo $capacityN | egrep '(29[0-9][0-9])' | awk 'length($1) == 4'` ]] || [[ `echo $capacityN | egrep '(3[0-1][0-9][0-9])' | awk 'length($1) == 4'` ]];then
			#3TB
			timeoutAfter=$timeout3000
			echo "3 TB drive detected, timeout set to $timeoutAfter"
		elif [[ $capacityN == 4000 ]] || [[ `echo $capacityN | egrep '(39[0-9][0-9])' | awk 'length($1) == 4'` ]] || [[ `echo $capacityN | egrep '(4[0-1][0-9][0-9])' | awk 'length($1) == 4'` ]];then
			#4TB
			timeoutAfter=$timeout4000
			echo "4 TB drive detected, timeout set to $timeoutAfter"
		elif [[ $capacityN == 6000 ]] || [[ `echo $capacityN | egrep '(59[0-9][0-9])' | awk 'length($1) == 4'` ]] || [[ `echo $capacityN | egrep '(6[0-1][0-9][0-9])' | awk 'length($1) == 4'` ]];then
			#6TB
			timeoutAfter=$timeout6000
			echo "6 TB drive detected, timeout set to $timeoutAfter"
		elif [[ $capacityN == 8000 ]] || [[ `echo $capacityN | egrep '(79[0-9][0-9])' | awk 'length($1) == 4'` ]] || [[ `echo $capacityN | egrep '(8[0-1][0-9][0-9])' | awk 'length($1) == 4'` ]];then
			#8TB
			timeoutAfter=$timeout8000
			echo "8 TB drive detected, timeout set to $timeoutAfter"
		elif [[ $capacityN == 10000 ]] || [[ `echo $capacityN | egrep '(79[0-9][0-9])' | awk 'length($1) == 4'` ]] || [[ `echo $capacityN | egrep '(8[0-1][0-9][0-9])' | awk 'length($1) == 4'` ]];then
			#10TB
			timeoutAfter=$timeout10000
			echo "10 TB drive detected, timeout set to $timeoutAfter"
		elif [[ $capacityN == 12000 ]] || [[ `echo $capacityN | egrep '(79[0-9][0-9])' | awk 'length($1) == 4'` ]] || [[ `echo $capacityN | egrep '(8[0-1][0-9][0-9])' | awk 'length($1) == 4'` ]];then
			#12TB
			timeoutAfter=$timeout12000
			echo "12 TB drive detected, timeout set to $timeoutAfter"
		elif [[ $capacityN == 12000 ]] || [[ `echo $capacityN | egrep '(79[0-9][0-9])' | awk 'length($1) == 4'` ]] || [[ `echo $capacityN | egrep '(8[0-1][0-9][0-9])' | awk 'length($1) == 4'` ]];then
			#14TB
			timeoutAfter=$timeout14000
			echo "14 TB drive detected, timeout set to $timeoutAfter"
		elif [[ $capacityN == 12000 ]] || [[ `echo $capacityN | egrep '(79[0-9][0-9])' | awk 'length($1) == 4'` ]] || [[ `echo $capacityN | egrep '(8[0-1][0-9][0-9])' | awk 'length($1) == 4'` ]];then
			#16TB
			timeoutAfter=$timeout16000
			echo "16 TB drive detected, timeout set to $timeoutAfter"
		elif [[ $capacityN == 18000 ]] || [[ `echo $capacityN | egrep '(79[0-9][0-9])' | awk 'length($1) == 4'` ]] || [[ `echo $capacityN | egrep '(8[0-1][0-9][0-9])' | awk 'length($1) == 4'` ]];then
			#18TB
			timeoutAfter=$timeout18000
			echo "12 TB drive detected, timeout set to $timeoutAfter"
		elif [[ $capacityN == 20000 ]] || [[ `echo $capacityN | egrep '(79[0-9][0-9])' | awk 'length($1) == 4'` ]] || [[ `echo $capacityN | egrep '(8[0-1][0-9][0-9])' | awk 'length($1) == 4'` ]];then
			#20TB
			timeoutAfter=$timeout20000
			echo "12 TB drive detected, timeout set to $timeoutAfter"
		elif [[ `echo $capacityN | egrep '([1-3][0-9][0-9])' | awk 'length($1) == 3'` ]] || [[ `echo $capacityN | egrep '([0-9][0-9])' | awk 'length($1) == 2'` ]];then
			#old
			timeoutAfter=$timeoutold
			echo "old drive / small size detected, timeout set to $timeoutAfter"
		else
			#unkown size, default
			timeoutAfter=$timeoutUnknown
			echo "Unknown size drive detected, timeout set to $timeoutAfter"
		fi
		#convert timeout to seconds for timeout check calculation
		if [[ `echo $timeoutAfter | grep "d"` ]];then
			timeoutSeconds=$(echo $timeoutAfter | awk '{print ($1 * 86400)}')
		elif [[ `echo $timeoutAfter | grep "m"` ]];then
			timeoutSeconds=$(echo $timeoutAfter | awk '{print ($1 * 3600)}')
		elif [[ `echo $timeoutAfter | grep "s"` ]];then
			timeoutSeconds=$(echo $timeoutAfter | sed 's/[^0-9]*//g')
		fi

	fi
}

#monitor the log files and kill the shred if they get too big.
function logCheck() {
	echo "sleeping" >> /root/logs/logcheck.log
	sleep 30
	while ps aux | egrep -i 'shred' | grep $diskPath | egrep -v 'grep|sleep 5' > /dev/null;do
		echo "shred detected, sleeping" >> /root/logs/logcheck.log
		sleep 60
		if [[ `wc -c $disklog | awk '{print $1}'` -ge "2000" ]];then
			incrementError
			echo "full log detected for $diskPath, attempting kill" >> /root/logs/logcheck.log
			psid=$(ps aux | grep $diskPath | egrep -v 'grep|timeout' | awk '{print $2}')
			kill -9 $psid
			sleep 5
			while ps aux | grep $psid |grep -v grep> /dev/null;do
				echo "kill failed for $diskPath, sleeping, then reattempt." >> /root/logs/logcheck.log
				sleep 5
				kill -9 $psid
			done
			cat $disklog | head -n 20 > $disklog.temp
			cat $disklog.temp > $disklog
			echo "Killed Shred for $diskPath as the log was filling up with junk." >> $disklog
			echo "Killed Shred for $diskPath as the log was filling up with junk." >> $errorLog
		fi
	done
	echo "closing logcheck for $diskPath" >> /root/logs/logcheck.log
}
#-------------------------------------------------------------------------------------------------------------------------
#switches
#-------------------------------------------------------------------------------------------------------------------------
function printUsage() {
    cat <<EOF

Synopsis
    Script to automate wiping, shredding, testing etc of SSDs and HDDs.

    -i Interactive mode.  No email, no shutdown.

    -d Debug mode. No email, no shutdown, no shred.

    -u run ATA unlock on all disks only.

    -s No shutdown.

    -x Kill it with fire.  Kills everything even remotely related to this script.

    -t timeout
       	Chhanges the drive shred timeout to somethhing other than default.
       	Set to 0 to disable timeout.
       	DURATION is a floating point number with an optional suffix:
		's' for seconds (the default), 'm' for minutes, 'h' for hours or 'd' for days.
        Default value: $timeoutAfter.

    -k KillAfter
        Also send a KILL signal if COMMAND is still running
        this long after the initial signal was sent.
        Default value: $killAfter.

    -e email.address
        Add an additional e-mail recipient for this run beyond the standard
        Standard recipients: ${emailAddresses[@]}

    -h This menu

EOF
}

# Options.
while getopts "a:t:k:e:idsxuh" option; do
    case "$option" in
        a) exit 1 ;;
        t) timeoutAfter=$OPTARG ;;
        k) killAfter=$OPTARG ;;
        e) emailAddresses+=(''$OPTARG'') ;;
		i)	sendemail=0
			shutDown=0
			shredSwitch=1
			;;
		d)	sendemail=0
			shutDown=0
			shredSwitch=0
			;;
		s)	shutDown=0 ;;
		x)	killItWithFire
			exit 0 ;;
		u)	ataUnlock
			exit 0
			;;
		h) printUsage
			exit 1
			;;
    esac
done
shift $((OPTIND - 1))

#-------------------------------------------------------------------------------------------------------------------------
#menu
#-------------------------------------------------------------------------------------------------------------------------

function menu () {
if [[ `echo $shutDown` == 1 ]];then
	clear
fi
menuRun=1
PS3='Please enter your choice(s): '
options=("Run" "Print Last Log" "Toggle Shutdown" "Toggle Email" "Toggle Shred" "Run ATA Unlock Only" "Set Drive Timeout" "Change KillAfter Timeout" "Add Email Address Recipient" "Run once new version updates on scripts server" "Quit")
echo "-==HiVelocity HD Test Script==-"
echo ""
			echo "The following options are set:"
			if [[ `echo $sendemail` == 1 ]];then
				echo "E-mail = yes."
			else
				echo "E-mail = No."
			fi
			if [[ `echo $shutDown` == 1 ]];then
				echo "Shutdown = Yes"
			else
				echo "Shutdown = No."
			fi
			if [[ `echo $shredSwitch` == 1 ]];then
				echo "Shred = Yes."
			else
				echo "Shred = No."
			fi
			echo
			echo "E-mail Recipients:"
			for adminmail in "${emailAddresses[@]}";do
				echo $adminmail
			done
			echo
			if [[ -n `echo $timeoutAfter` ]];then
				echo "Override timout set to $timeoutAfter."
			else
				echo "Override timeout not set."
			fi
			echo "Kill hung processes if timeout fails after $killAfter."
echo ""
select opt in "${options[@]}"
do
    case $opt in
    	"Run")
			clear
			echo "The following options are set:"
			if [[ `echo $sendemail` == 1 ]];then
				echo "E-mail = yes."
			else
				echo "E-mail = No."
			fi
			if [[ `echo $shutDown` == 1 ]];then
				echo "Shutdown = Yes"
			else
				echo "Shutdown = No."
			fi
			if [[ `echo $shredSwitch` == 1 ]];then
				echo "Shred = Yes."
			else
				echo "Shred = No."
			fi
			echo
			echo "E-mail Recipients:"
			for adminmail in "${emailAddresses[@]}";do
				echo $adminmail
			done
			echo
			if [[ -n `echo $timeoutAfter` ]];then
				echo "Override timout set to $timeoutAfter."
			else
				echo "Override timeout not set."
			fi
			echo "Kill hung processes if timeout fails after $killAfter."
			echo ""
			echo "Continue? (y/yes/n/no)"
			read go
			if [[ `echo $go | egrep '(y|yes|Y|YES)'` ]]; then
				menuRun=1
            	doTheThing
        	elif [[ `echo $go | egrep -i '(n|no)'` ]]; then
        		menu
        	fi
			;;
        "Print Last Log")
			echo "print last log"
			less /root/logs/final.log
            ;;
        "Toggle Shutdown")
			if [[ `echo $shutDown` == 1 ]];then
				echo "Shutdown = Yes"
				echo "Toggle? (y/n)"
				read toggle
				if [[ `echo $toggle | egrep -i y` ]];then
					shutDown=0
				fi
			elif [[ `echo $shutDown` == 0 ]];then
				echo "Shutdown = No"
				echo "Toggle? (y/n)"
				read toggle
				if [[ `echo $toggle | egrep -i y` ]];then
					shutDown=1
				fi
			fi
			if [[ `echo $shutDown` == 1 ]];then
				echo "Shutdown = Yes"
			else
				echo "Shutdown = No."
			fi
            ;;
        "Toggle Email")
			if [[ `echo $sendemail` == 1 ]];then
				echo "E-mail = yes."
				echo "Toggle? (y/n)"
				read toggle
				if [[ `echo $toggle | egrep -i y` ]];then
					sendemail=0
				fi
			elif [[ `echo $sendemail` == 0 ]];then
				echo "E-mail = No"
				echo "Toggle? (y/n)"
				read toggle
				if [[ `echo $toggle | egrep -i y` ]];then
					sendemail=1
				fi
			fi
			if [[ `echo $sendemail` == 1 ]];then
				echo "E-mail = yes."
			else
				echo "E-mail = No."
			fi
            ;;
        "Toggle Shred")
			if [[ `echo $shredSwitch` == 1 ]];then
				echo "Shred = yes."
				echo "Toggle? (y/n)"
				read toggle
				if [[ `echo $toggle | egrep -i y` ]];then
					shredSwitch=0
				fi
			elif [[ `echo $shredSwitch` == 0 ]];then
				echo "Shred = No"
				echo "Toggle? (y/n)"
				read toggle
				if [[ `echo $toggle | egrep -i y` ]];then
					shredSwitch=1
				fi
			fi
			if [[ `echo $shredSwitch` == 1 ]];then
				echo "Shred = Yes."
			else
				echo "Shred = No."
			fi
		
		;;
        "Run ATA Unlock Only")
			echo "ata unlock only"
			ataUnlock
            ;;
        "Set Drive Timeout")
			clear
			echo "Set drive timeout"
			echo "Changes the drive shred timeout to somethhing other than default."
      		echo "Set to 0 to disable timeout."
			echo "DURATION is a floating point number with an optional suffix:"
			echo "'s' for seconds (the default), 'm' for minutes, 'h' for hours or 'd' for days."
			echo "example: 10m for ten minutes.  10 for ten seconds."
			read timeoutAfter
			echo "Timeout set to $timeoutAfter."

            ;;
        "Change KillAfter Timeout")
			clear
			echo "Kill hung processes if timeout fails after $killAfter."
			echo "Please enter a new killafter value:"
			read killAfter
			echo "Kill hung processes if timeout fails after $killAfter."
            ;;
        "Add Email Address Recipient")
			echo "add email recipient"
			clear
			echo "Enter e-mail recipient to add to the list and press enter:"
			read newemail
			emailAddresses+=(''$newemail'')
			unset newemail
			echo "E-mail Recipients:"
			for adminmail in "${emailAddresses[@]}";do
			echo $adminmail
			done

            ;;
        "Run once new version updates on scripts server")
			echo "Current Script Version: $scriptVersion"
			newversion=$((scriptVersion+1))
        	until cat diskclean.sh | grep -i scriptVersion | grep $newversion;do
        		clear
        		echo "Waiting for new script version to update."
        		echo "Current Script Version: $scriptVersion"
        		echo "Waiting for version $newversion to appear."
        		rm -rf diskclean.sh*
        		wget scripts.hivelocity.net/utils/diskclean.sh 2> /dev/null
        		chmod +x /root/diskclean.sh
        		sleep 5
        	done
        	/root/diskclean.sh
        ;;
		"Quit")
			echo ""
			echo "Really Quit? (y/yes/n/no)"
			read go
			if [ `echo $go | egrep '(y|yes|Y|YES)'` ]; then
            	exit
            fi
            ;;
        *) echo invalid option;;
    esac
done

}

#-------------------------------------------------------------------------------------------------------------------------
#perform tasks and build logs and output
#-------------------------------------------------------------------------------------------------------------------------
function doTheThing () {
	
	#delete old logs and setup failure log
	rm -rf /root/logs/*
	failures=0
	echo $failures > /root/logs/failures
	
	#get drives system can see
	getDriveCount
	
	#clear foreign configs
	lsiSlotTestFunction
	#make all drives jbod
	fixJBOD
	#make all drives visible to system
	matchSystemAndLsiCount
	
	#run ata unlock
	ataUnlock
	
	#check for empty ports on the lsi card
	lsiSlotTestFunction >> $synopsisLog
	
	#set the start date for the script.
	scriptStart=`date +%s`
	
	#loop the loop
	for disk in "${driveArray[@]}";do
		set +e
		diskPath=/dev/$disk
		disklog="/root/logs/$disk.log"
		#use megacli to pull adapter info and match adapter port to disk
		lsiFunction 2>> /root/logs/errors >> $synopsisLog
		#use utilities to pull drive info
		getDriveInfo 2>> /root/logs/errors >> $disklog 2>&1
		#determine if ssd or hdd
		getDriveType
		#determine who made the drive
		determineManufacturer 2>> /root/logs/errors >> $disklog 2>&1
		#print disk info to log
		echoDiskInfo 2>> /root/logs/errors >> $disklog 2>&1
		#set timeout based on drive capacity	
		#print to console
		echo "$driveTypeH $disk with serial $serial and capacity $capacity by $manufacturerh detected." > /dev/console
		runManufacturerSpecificTasks 2>> /root/logs/errors >> $disklog 2>&1 &
		set -e
	done
	
	#do drive count checks if LSI card is installed.
	if [[ -n $lsicardcheck ]];then
		#if lsi card detected, do lsi stuff
		#check if lsi card see same number of drives and report to error log if not
		if [[ $lsiNumberOfSlots != $lsiNumberOfDrives ]];then
			echo "LSI card does not see all ports in use." >> $errorLog
			failures=`cat /root/logs/failures`
			failures=$((failures+1))
			echo $failures > /root/logs/failures
		fi
		#check if system and lsi card see same number of drives and report to error log if not
		if [[ "$driveCount" != "$lsiNumberOfDrives" ]];then
			echo "LSI card and System do not see the same number of drives." >> $errorLog
			failures=`cat /root/logs/failures`
			failures=$((failures+1))
			echo $failures > /root/logs/failures
		fi
	fi
	
	#wait for disk jobs to complete and print status to console.
	clear > /dev/console
	clear
	while ps aux | egrep -i 'sleep|shred|smartctl|msecli|isdct|Samsung_SSD_DC_Toolkit_V1_x64|hdparm' | grep -v grep| grep -v 'sleep 5' > /dev/null;do
  	echo "Waiting for jobs to complete." #> /dev/console
  	echo #> /dev/console
  	echo "System IP: $systemIP" #> /dev/console
  	cat $synopsisLog | sort #> /dev/console
  	echo "Script Version:$scriptVersion"
  	echo #> /dev/console
  	echo "Waiting for the following jobs to complete:" #> /dev/console
  	ps aux | egrep -i 'sleep|shred|smartctl|msecli|isdct|Samsung_SSD_DC_Toolkit_V1_x64|hdparm' | egrep -v 'grep|timeout|sleep' | cut -f3 -d ":" | cut -f2-20 -d " "
  	echo
  	scriptEnd=`date +%s`
  	calculateScriptTime
  	echo "Script has been running for $scriptRuntime"
	
  	sleep 5
  	clear #> /dev/console
	done
	
	
	#build final log file
	cat $synopsisLog | sort >> $finallog
	echo >> $finallog
	echo `hostname` >> $finallog
	
	failures=`cat /root/logs/failures`
	echo "Errors ($failures):" >> $finallog
	cat /root/logs/errors >> $finallog
	echo  >> $finallog
	
	for disk in "${driveArray[@]}";do
		echo "-------------------------------" >> $finallog
		echo "Drive information for $disk" >> $finallog
		echo "-------------------------------" >> $finallog
    	cat /root/logs/$disk.log >> $finallog
    	echo >> $finallog
	done
	
	echo Failures: $failures >> $finallog
	echo "System IP: $systemIP" >> $finallog
	echo >> $finallog
	echo "Errors:" >> $finallog
	cat /root/logs/errors >> $finallog
	
	
	
	#-------------------------------------------------------------------------------------------------------------------------
	
	# Subject is the subject of our email
	subject="Disk Clean Finished with $failures errors on `hostname` at `date`."
	
	#send the email(s)
	if [[ -x /usr/bin/mail && "$sendemail" -eq "1" ]]; then
		for adminmail in "${emailAddresses[@]}";do
			/usr/bin/mail -s "$subject" "$adminmail" < $finallog
		done
	fi

	#delete some junk
	rm -rf /root/{0..9}*
	
	#shutdown the system at the end
	if [[ "$shutDown" -eq "1" ]]; then
		shutdown -h 2
		echo > /dev/console
		echo "All jobs completed at `date`.  Shutting down in 2 minutes. Login and run 'shutdown -c' to cancel shutdown" > /dev/console
	elif [[ "$shutDown" -eq "0" ]]; then
		echo
		cat $finallog
		echo  > /dev/console
		echo "Automatic shutdown is disabled." > /dev/console
		if [[ $menuRun == 1 ]];then
			menu
		fi
	fi
}

#clear the screen
clear	
#wake up the console first.
echo "" > /dev/console
echo "System IP: $systemIP" > /dev/console
echo ""	
echo "Press "y" then enter to enter menu or press just enter to continue."
echo "There is a 1 minute timeout and it will continue on it's own."
read -t 60 answer
if [[ -n `echo $answer | egrep -i 'y|yes'` ]];then
	menu
fi

doTheThing



