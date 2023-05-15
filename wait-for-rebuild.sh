#!/bin/sh
if [ 0 == "$#" ] ; then
	CMD="poweroff"
else
	CMD="$@"
fi
while [ $(ps -ax | grep md126_resync | wc -l) != '1' ] ; do 
	date
	sleep 300
done
$CMD
