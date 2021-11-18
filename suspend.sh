#!/bin/sh
if [ -n "$(pidof suspend.sh)" ] ; then
	echo "suspend.sh"
	exit
fi
. session-functions.sh
if [ -f $LOCKF ] ; then
	rm $LOCKF				#for sleeper
fi
if [ -w /run/faillock/$USER ] ; then
	rm /run/faillock/$USER		#for pam
fi
(N=;while sleeper $N ; do N=$(( 0$N + 1 )) ; sleep 10 ; done) & disown
