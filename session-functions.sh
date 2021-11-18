#!/bin/sh

export LOCKF=~/.suspend.lck

function activity() {
	([ -f $LOCKF ] || [ 0$(strafe mlist 2>/dev/null | wc -l) -gt 0 ]) && [ -z "$(pidof xsecurelock)" ]
}

function sleeper() {
	if [ -n "$1" ] ; then
		for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 ; do
			if activity ; then
				rm -f $LOCKF
				false
				return
			fi
			sleep 1
		done
	fi
	(yes y | sudo strafe stop-all mprune prune clean
	sudo network-stop
	sudo -k
	for i in $(cat /proc/acpi/wakeup | grep enabled | cut -f1 -d\ ) ; do echo $i > /proc/acpi/wakeup ; done
	lxqt-leave --suspend) & disown
	true
}

function resumer() {
	touch $LOCKF
	Y=n
	read -t2 -iN -p "restart network [N/y] ?" Y
	if [ "$Y" == "y" ] || [ "$Y" == "Y" ] ; then
		sudo network-restart
		sudo su -c "DOWORK=1 bridge.sh"
	fi
}
