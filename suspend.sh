#!/bin/sh
if [ -n "$(pidof suspend.sh)" ] ; then
	echo "suspend.sh"
	exit
fi
. session-functions.sh
if [ -n "$1" ] && [ "$1" != "now" ] ; then
	if ! wait_on_activity ; then
		exit
	fi
fi
if [ -f $LOCKF ] ; then
	rm $LOCKF				#for sleeper
fi
if [ -w /run/faillock/$USER ] ; then
	rm /run/faillock/$USER		#for pam
fi
sleeper $@
