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
	# bath-user[i] from /etc/passwd to $mach/etc/passwd
	# bath-user[i] from /etc/group to $mach/etc/group
	# doctor_ns shadow and gshadow
	if [ "/etc/passwd" != "$mach/etc/passwd" ] ; then
		echo "disallow non-useful shells..." 1>&2
		
		# add extras nologin  (include our (u|r)bac from host)
		EEXPR="^($(cat $mach/etc/passwd | grep -E '^[a-z]' | cut -f1 -d: | clean | tr ',' '|')xyzzy)"
		cat /etc/passwd | grep -v -E $EEXPR | sed -r -e 's/\/bin\/bash/\/bin\/nologin/' >> $mach/etc/passwd
		# make some say hello 
		echo "permit useful shells..." 1>&2
		for i in $(cat $mach/etc/bath-user) ; do
			if ! usermod -R $(realpath $mach) -s /bin/bash $i ; then
				useradd -R $(realpath $mach) -s /bin/bash -d /home/$i $i
			fi
			mkdir -p $mach/home/$i
			mkdir -p $mach/root/mnt/$i
		done
		
		# bring over the groups removing at least video group. (systemd-sysusers bug)
		EEXPR="^($(cat $mach/etc/group | grep -E '^[a-z]' | cut -f1 -d: | clean | tr ',' '|')video)"
		echo "Thinning out gshadow (disabled)..." 1>&2
		echo $EEXPR 1>&2
		#cat /etc/group | grep -v -E $EEXPR >> $mach/etc/group
		#cat /etc/gshadow | grep -v -E $EEXPR >> $mach/etc/gshadow

		echo "fix our transferred passwd databases..." 1>&2
		yes y | pwck -R $(realpath $mach)

		echo "fix our transferred group databases..." 1>&2
		yes y | grpck -R $(realpath $mach)
		for i in group passwd ; do
			chmod 0644 $mach/etc/$i
			chown root $mach/etc/group
		done
	fi
	#echo "remove unused group entries..." 1>&2
	#SEDCMD=$(mktemp)
	#for i in amsc git wrt ceph rpc postfix ntp $(cat /usr/src/machine-base/etc/bath-user) ; do
	#	echo "s/$i,*//" >> $SEDCMD
	#done
	#sed -r -f $SEDCMD -i $mach/etc/group
	#rm $SEDCMD
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
	#
	$systemctl disable systemd-resolved
	rm $(realpath $mach)/etc/resolv.conf
		
	#ln -s /run/systemd/resolve/stub-resolv.conf $(realpath $mach)/etc/resolv.conf
	#
	$systemctl enable systemd-networkd
	cat <<-EOF > $mach/etc/rc.local
		#!/bin/sh
		find /usr/lib/systemd/network/ -name \*.network -exec rm {} \;
		echo "nameserver 169.254.0.1" > /etc/resolv.conf
EOF
	chmod 0744 $mach/etc/rc.local
	chown root $mach/etc/rc.local
	$systemctl enable rc-local
}
#
function enable_service() {
	if debug ; then
		echo "${FUNCNAME[0]}"
		return
	fi
	echo "enabling services : $@..." 1>&2
	systemctl="systemctl --root=$(realpath $mach)"
	for i in $@ ; do 
	 	$systemctl enable $i
	done
}
#
function mariadb_install() {
	echo "mariadb configuration..." 1>&2
	cp $MACHINEBASE/etc/my.cnf $(realpath $mach)/etc/my.cnf
	rsync -q -vlr $MACHINEBASE/etc/my.cnf.d/ $(realpath $mach)/etc/my.cnf.d/
	echo "enabling mariadb services..." 1>&2
	rsync -q -vlr $MACHINEBASE/systemd-mariadb/system/ $mach/usr/lib/systemd/system/
	systemctl="systemctl --root=$(realpath $mach)"
	$systemctl enable mariadb.service
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
	rsync $MACHINEBASE/network/*.network $mach/etc/systemd/network/
}