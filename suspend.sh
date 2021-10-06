#!/bin/sh
if [ -n "$(pidof suspend.sh)" ] ; then
	echo "suspend.sh"
	exit
fi
. session-functions.sh
if [ -f $LOCKF ] ; then
	rm $LOCKF				#for sleeper
fi
rm /run/faillock/$USER		#for pam
sleeper			   			#to suspend
sudo lxlocker 				#invoke pam
sleeper 60				    #sleepover then suspend
