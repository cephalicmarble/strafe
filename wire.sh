#!/bin/sh

if [ -z "$STRAFD" ] ; then
	STRAFD=/mach/.machines
fi
WIRE=$STRAFD/.wire
LOCKF=$STRAFD/.wirelock

function lockwire() {
	ARG=$1
	if [ -n "$ARG" ] ; then
		shift
	fi
	case $ARG in
		"lock")
			if ! [ -f $LOCKF ] ; then
				echo $PPID > $LOCKF
				return
			fi
			if [[ $PPID -eq $(cat $LOCKF) ]] ; then
				true
				return
			fi
			;;
		"unlock")
			lockwire try rm $LOCKF
			;;
		"locked")
			if ! [ -f $LOCKF ] ; then
				echo yes
				return
			else
				if [[ $PPID -eq $(cat $LOCKF) ]] ; then
					echo yes
					return
				else
					echo no
					return
				fi
			fi
			echo no
			;;
		"try")
			if [ "yes" == $(lockwire locked) ] ; then
				$@
			fi
			;;
		"patiently")
			while [ -f $LOCKF ] && [ $PPID != $(cat $LOCKF) ] ; do
				sleep 1
			done
			echo $PPID > $LOCKF
			$@
			rm $LOCKF
			;;
		*)
			echo "error: $0 $ARG $@"
			test -f $LOCKF
	esac
}

function newport() {
	lockwire lock
	if [[ $(wc -l < $WIRE) -gt 9 ]] ; then
		echo "$WIRE : Too many ports!"
		exit
	fi
	PORT="#top"
	while true ; do
		PORT=$(( 65533 - $(( 0$(dd if=/dev/random bs=128 count=1 2>/dev/null | tr -dc '0-5' | dd bs=2 count=1 2>/dev/null | head -1) )) ))
		if ! grep -E $PORT $WIRE &>/dev/null && ! grep -E $(( $PORT + 1 )) $WIRE &>/dev/null ; then
			break
		fi
	done
	echo $PORT | tee -a $WIRE
	lockwire unlock
}

function setport() {
	if [ -z "$PORT" ] ; then
		PORT=$1
	fi
}

function _delimpl() {
	PORT=$1
	PORTF=$(mktemp)
	(cat $WIRE | grep -v $PORT > $PORTF; mv $PORTF $WIRE)
}

function delport() {
	lockwire patiently _delimpl $1
}

function tellport() {
	setport
	echo "echo $1 | netcat $HOST $PORT"
	return
	flushport
}

function flushport() {
	# need to find the machine name
	netcat -l localhost $(( $PORT + 1 ))
}

function closeport() {
	netcat -z localhost $PORT < /dev/zero
}

function listports() {
	cat $WIRE
}
