#!/bin/sh
MACHINEBASE=/usr/src/machine-base
#
function rig() {
	type=$1
	want=$2
	unit=$3
	ln -s /usr/lib/systemd/$type/$unit $DIR/etc/systemd/$type/$want
}
#
function doctor_ns() {
	if [ "$mach/etc/$1" != "/etc/$1" ] ; then
		T=$(mktemp)
		cat $mach/etc/$1 | grep -v -E '^(amsc|git|wrt|ceph|rpc|postfix|ntp)' > $T
		mv $T $mach/etc/$1
	fi
	chmod 0644 $mach/etc/$1
	chown root $mach/etc/$1
}
#
function init_machine() {
	mach="$DIR"
	. $PKGF
	${TARGET} machine
}
#
function systemd_services() {
	if debug ; then
		echo "${FUNCNAME[0]}"
		return
	fi
	echo "systemd services from machine-base..." 1>&2
	mkdir -p $mach/usr/lib/systemd/system
	for i in systemd-journald.service onready.service homes.service wrapper@.service poweroff.service poweroff.target console-getty@.service ; do
		echo system/$i
		cp $MACHINEBASE/usr-lib-systemd/system/$i $mach/usr/lib/systemd/system/$i
	done
	mkdir -p $mach/usr/lib/systemd/user
	for i in wrapper@.service xpra-zoom.service ; do
		echo user/$i
		cp $MACHINEBASE/usr-lib-systemd/user/$i $mach/usr/lib/systemd/user/$i
	done
}
#
function base_config() {
	if debug ; then
		echo "${FUNCNAME[0]}"
		return
	fi
	echo "machine-base config..." 1>&2
	rsync -q -vlr $MACHINEBASE/etc/ $mach/etc/
	rsync -q -vlr $MACHINEBASE/usr-lib-systemd/ $mach/usr/lib/systemd/
	mkdir -p $mach/usr/scripts
	rsync -q -vlr $MACHINEBASE/scripts/ $mach/usr/scripts/
	for i in group shadow ; do
		cp /etc/{$i,${i}-} $mach/etc/
	done
}
#
function userdb() {
	if debug ; then
		echo "${FUNCNAME[0]}"
		return
	fi
	# uid/gid
	echo "users and groups..." 1>&2
	for i in user exec ; do 
		cp /usr/src/machine-base/etc/bath-$i $mach/etc/
	done
	if [ "/etc/passwd" != "$mach/etc/passwd" ] ; then
		echo "disallow non-useful shells..." 1>&2
		T=$(mktemp)
		cat /etc/passwd | sed -r -e 's/\/bin\/bash/\/bin\/nologin/' -e 's/\/root:\/bin\/nologin/\/root:\/bin\/bash/' > $T
		mv $T $mach/etc/passwd
		echo "permit useful shells..." 1>&2
		for i in $(cat $mach/etc/bath-user) ; do
			sed -re "s/:\/bin\/nologin/:\/bin\/bash/" -i $mach/etc/passwd
			mkdir -p $mach/home/$i
			mkdir -p $mach/root/mnt/$i
		done
		echo "fix our transferred passwd, shadow and group databases..." 1>&2
		doctor_ns passwd
		doctor_ns shadow
		doctor_ns group		
		doctor_ns gshadow
	fi
	echo "remove unused group entries..." 1>&2
	SEDCMD=$(mktemp)
	for i in amsc git wrt ceph rpc postfix ntp ; do
		echo "s/$i,*//" >> $SEDCMD
	done
	sed -r -f $SEDCMD -i $mach/etc/group
	rm $SEDCMD
}
#
function enable_services() {
	if debug ; then
		echo "${FUNCNAME[0]}"
		return
	fi
	echo "enabling systemd services..." 1>&2
	systemctl="systemctl --root=$(realpath $mach)"
	cp $MACHINEBASE/resolved.conf $mach/etc/systemd/resolved.conf
	$systemctl enable homes
	$systemctl enable onready
	$systemctl set-default multi-user.target 
	rig system multi-user.target.wants getty.target
	$systemctl disable getty@tty1
	for i in $(cat $mach/etc/bath-user) ; do
		$systemctl enable console-getty@$i
	done	
	$systemctl enable systemd-resolved
	$systemctl enable systemd-networkd
	cat <<-EOF > $mach/etc/rc.local
		#!/bin/sh
		find /usr/lib/systemd/network/ -name \*.network -exec rm {} \;
		echo "nameserver 127.0.0.53" > /etc/resolv.conf
EOF
	chmod 0744 $mach/etc/rc.local
	chown root $mach/etc/rc.local
	$systemctl enable rc-local
}
#
function networking() {
	if debug ; then
		echo "${FUNCNAME[0]}"
		return
	fi
	# all machines...
	echo "networking..." 1>&2
	if [ -d $mach/usr/lib/systemd/network ] ; then
		find $mach/usr/lib/systemd/network/ -name \*.network -exec rm {} \;
	fi
	if [ -d $mach/etc/systemd/network ] ; then
		find $mach/etc/systemd/network -name \*.network -exec rm {} \;
	else
		mkdir -p $mach/etc/systemd/network
	fi
	if [ -z "$BOOTSTRAP" ] ; then
		rsync $MACHINEBASE/network/*.network $mach/etc/systemd/network/
	fi
}