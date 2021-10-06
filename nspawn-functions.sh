#!/bin/sh
function killcmd() {
	PID=$(ps ax -o pid,command= | grep "$*" | cut -f1 -d\ | sed -e 's/\s+$//')
	if [ -n "$PID" ] && [[ $(( 0 + $PID )) > 0 ]] ; then
		kill -9 $PID 2> /dev/null
	fi
}
function msg() {
	echo "$*" > $(cat /home/$SUDO_USER/.write.tty)
}
function one() {
	echo 1 > $1
}
function two() {
	$1 2>&1 | tee -a $2
	echo exit
}