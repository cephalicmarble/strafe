#!/bin/sh

export LOCKF=~/.suspend.lck

function activity() {
	([ -f $LOCKF ] || [ 0$(strafe mlist 2>/dev/null | wc -l) -gt 0 ]) && [ -z "$(pidof xsecurelock)" ]
}

function wait_on_activity() {
	for j in 1 2 3 ; do
		for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 ; do
			if activity ; then
				rm -f $LOCKF
				false
				return
			fi
			sleep 1
		done
	done
	true
}

function suspension() {
	#for i in $(cat /proc/acpi/wakeup | grep enabled | cut -f1 -d\ ) ; do echo $i > /proc/acpi/wakeup ; done
	(yes y | strafe stop-all mprune prune clean
	network-stop
	sudo su -c lxlocker	&	
	sudo -k
	systemctl suspend) & disown
}

function sleeper() {
	if [ "$1" != "now" ] ; then
		if wait_on_activity ; then
			suspension
		else
			exit	
		fi
	else
		suspension
	fi
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
