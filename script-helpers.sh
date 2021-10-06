#!/bin/bash
init_ONCE=0
function init() {
	if [ 0 -lt $init_ONCE ] ; then
		return
	fi
	if [[ "$@" =~ "--debug" ]] ; then
		debugging=1
	else
		debugging=0
	fi
	init_ONCE=1
}

function __closure() {
	# $@ names of env vars apart from this plus taint
	# strip taint
	# remove last
	# engineer vars and closure with taint
	# source file
 	false
}

function __fn() {
	# posw wordf taints
	# do not igrnore taints
	# allow posf to fallow
	true
}

function __initfn() {
	# word $CMD
	# see lf
	true
}

function lf() { # --return --debug
	CMD="$@"
	if [ 0"$debugging" -gt 0 ] || [[ "$@" =~ "--debug" ]] ; then
		echo $CMD
	fi
	if [[ "$@" =~ "--return" ]] ; then
		$CMD
	elif [[ "$@" =~ "--output" ]] ; then
		echo $($CMD)
	fi
}

function spinlock() {
	while [ -f $1.lck ] ; do
		sleep 1
	done
	touch $1.lck
	$2
	rm $1.lck
}
function quoteargs() {
	echo $1 | sed -re 's/\ /\"\ \"/g' | sed -re 's/^/\"/' | sed -re 's/(.*)$/\1\"/'
}
#
#function addfile() { FILES="$FILES '$1'"; touch "$1"; chmod a+rw "$1"; }
#function addfifo() { FILES="$FILES '$1'"; mkfifo "$1"; chmod a+rw "$1"; } 
#function addlink() { LINKS="$LINKS '$2'"; ln -s "$1" "$2"; }
#function trcmd() { echo "$*" | tr ' ' ','; }
#function rtcmd() { echo "$*" | tr ',' ' '; }
#function addexit() { ONEXIT="$ONEXIT $(trcmd $*)"; }
#function addcommand() {	COMMANDS="$COMMANDS $(trcmd $*)"; }
#function killcmd() {
#	PID=$(ps ax -o pid,command= | grep "$*" | cut -f1 -d\ | sed -e 's/\s+$//')
#	if [ -n "$PID" ] && [[ $(( 0 + $PID )) > 0 ]] ; then
#		kill -9 $PID 2> /dev/null
#	fi
#}
#
#function onexit() {
#	if [ -n "$1" ] ; then
#		echo "$1"
#	fi
#	if [ -f $EXITING ] ; then
#		return
#	fi
#	for c in EXIT KILL QUIT TERM ; do
#		trap - $c
#	done
#	if [[ "0$(cat $WATCHDOG)" -lt 3 ]] ; then
#		touch $EXITING
#		rm -f "$WATCHDOG" 2> /dev/null
#			sleep 6
#		machinectl shell $MACHNAME poweroff
#		while [ 0$(machinectl list | grep "$MACHNAME" | wc -l) -gt 0 ] ; do sleep 4 ; done
#		for i in $ONEXIT ; do CMD=$(rtcmd "$i") ; $CMD ; done
#		for i in $COMMANDS ; do killcmd $(rtcmd "$i") ; done
#		# here copy work away
## strafe stop mprune mounts dismount mounts clean $MACHNAME
#		echo "strafe list"
#		strafe list
#		echo "strafe mounts"
#		strafe mounts
#		exit
#	fi
#}
##
#function chain_main() {
#	TMPDIR=
#	trap onexit EXIT TERM
#}
#