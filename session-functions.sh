#!/bin/sh

export LOCKF=~/.suspend.lck

function activity() {
	[ -f $LOCKF ] || [ 0$(strafe mlist | wc -l) -gt 0 ]
}

function sleeper() {
	SLEEP=$(( 0$1 ))
	(if [ $SLEEP -gt 0 ] ; then
		for i in 1 2 3 4 5 6 7 8 9 10 ; do
			if activity ; then
				rm -f $LOCKF
				return
			fi
			sleep $SLEEP
		done
	fi;
	if activity ; then
		rm -f $LOCKF
		return
	fi
	yes y | sudo strafe stop-all mprune prune clean
	sudo network-stop
	sudo -k
	for i in $(cat /proc/acpi/wakeup | grep enabled | cut -f1 -d\ ) ; do echo $i > /proc/acpi/wakeup ; done
	systemctl hibernate
	) & disown
}

function resumer() {
	touch $LOCKF
	Y=n
	read -t2 -iN -p "restart network [N/y] ?" Y
	if [ "$Y" == "y" ] || [ "$Y" == "Y" ] ; then
		sudo network-restart
	fi
}
