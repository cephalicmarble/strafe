#!/bin/sh

if ! [ -d /mach ] ; then
	. /tmp/environmentfile
	if [ -d /mach ] ; then
		netcat -z $JOURNALHOST $JOURNALPORT < /dev/zero
	fi
	#. /etc/profile.d/thing.sh
	#. /etc/profile.d/display.sh
fi
