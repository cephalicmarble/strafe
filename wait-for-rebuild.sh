#!/bin/sh
while [ $(ps -ax | grep sync | wc -l) != '1' ] ; do 
	date
	sleep 300
done
poweroff
