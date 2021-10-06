#!/bin/sh
I=1
for i in /tmp/chain* ; do
	rm $i
	if [ $I == $(( $(echo $i | sed -re 's/\/tmp\/chain//g' | sed -re 's/[a-zA-Z]+$//g') )) ] ; then
		exit
	fi
	I=$(( $I + 1 ))
done
