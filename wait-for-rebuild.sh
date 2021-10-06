#!/bin/sh
while (ps -ax | grep md126_resync) ; do 
	date
	sleep 300
done
poweroff
