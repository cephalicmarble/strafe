#!/bin/sh
export STRAFD="/mach/.machines"
export MLAYER="/mach/.journals"
if [ -z "$NOSHL" ] ; then
	exec lxterminal -e "/bin/bash -i -c 'NOSHA=\"$NOSHA\" NOGPG=\"$NOGPG\" NOEPH=\"$NOEPH\" NOIMG=\"$NOIMG\" NOSHL=1 $0 $@'"
	exit
fi

PWD=$(pwd)

. /etc/profile.d/bridge.sh
. wire.sh
. bridge.sh

if [[ $(ifconfig br0 2>&1) =~ "not found" ]] ; then
	SHLVL=1 setup
	SHLVL=1 work
fi

function addfile() { FILES="$FILES '$1'"; touch "$1"; chmod a+rw "$1"; }
function addfifo() { FILES="$FILES '$1'"; mkfifo "$1"; chmod a+rw "$1"; } 
function addlink() { LINKS="$LINKS '$2'"; ln -s "$1" "$2"; }
function trcmd() { echo "$*" | tr ' ' ','; }
function rtcmd() { echo "$*" | tr ',' ' '; }
function addexit() { ONEXIT="$ONEXIT $(trcmd $*)"; }
function addcommand() {	COMMANDS="$COMMANDS $(trcmd $*)"; }
function killcmd() {
	PID=$(ps ax -o pid,command= | grep "$*" | cut -f1 -d\ | sed -e 's/\s+$//')
	if [ -n "$PID" ] && [[ $(( 0 + $PID )) > 0 ]] ; then
		kill -9 $PID 2> /dev/null
	fi
}

COMMAND="$0 $@"

if [ $USER != 'root' ] ; then
	echo "$0 : run as root. [NOGPG, NOSHA, NOIMG to force, NOEPH for persistence, LF for /dev/console]"
	exit
fi
DOG="$1"
if [ -z "$DOG" ] ; then
	echo "Usage : DOG=\$(mktemp <FUNC>-XXXX) ; echo arguments | $0 <watchdog> <FUNC> [MACH] ; rm \$DOG"
	exit
fi
if [ -f "$DOG" ] ; then
	DOG=$(realpath $DOG)
	shift
else
	DOG=""
fi
FUNCVER="$1"
FUNC=${FUNCVER/-*}
MACH="$2"
FILES=""
LINKS=""
COMMANDS=""
if [ -z "$DOG" ] ; then
	DOG=$(realpath ./$FUNC.watchdog)
	touch $DOG
fi
addfile $DOG
function bridgeip() {
	IP=$(ifconfig br0 | grep inet | cut -f2 -dt | cut -f1-2 -d. | cut -f2 -d\ | head -1)
	if [ -z "$IP" ] ; then
		echo "Rebuilding the bridge!"
		bridge.sh
		IP=$(bridgeip)
		if [ -z "$IP" ] ; then
			echo "Bridge is out!"
			exit
		fi
	fi
	echo $IP
}
NET=$(bridgeip)
if [ -z "$FUNC" ] ; then
	FUNC=test
	MACH=base
elif [ -z "$MACH" ] || [[ "$MACH" =~ "--" ]] ; then
	shift
	MACH=$FUNCVER
else
	shift 2
fi
NICKNAME=$FUNCVER/$MACH/$(date +%s)
MACHNAME=$(echo $NICKNAME | tr '/' '-')
MACHLINK="$STRAFD/run/$MACHNAME"
#if ! rebuild-machines.sh $MACH $NICKNAME ; then
#	echo "nspawn.sh exiting..."
#	exit
#fi
# fifo-pump
function pour() {
	while [ -w $WATCHDOG ] ; do read -t 1 -u 0 O; if [ "$O" == "exit" ]; then onexit journaler; fi; done
}
function journaler() {
	PUMP="fifo-pump"
	addcommand $PUMP
	TEE="tee -a $(cat /home/$SUDO_USER/.write.tty)"
	addcommand $TEE

	declare -a BRACKET
	BRACKET=("$NETCAT" "two $PWD/$MACHINE-journal.log")
	
	(for i in ${!BRACKET[*]} ; do
		echo "${BRACKET[$i]}"
	done) > $IN &
	
	($TEE | $PUMP | pour) < $IN

	echo blargle
}
function terminal() {
	N=0; 
	while sleep 1; do
		if ! [ -w $WATCHDOG ] ; then return; fi
		N=$(cat $WATCHDOG)
		if [[ $(( 0 + 0$N )) -gt 0 ]] ; then
			break
		fi
	done
	MACHINE=$(basename ${WATCHDOG/.watchdog})
	echo "Opening shell into $MACHINE..."
	(lxterminal --title="top on ${MACHINE}" --command="/sbin/machinectl shell ${ACCT}@${MACHINE} /bin/top"; onexit lxterminal)
}

# pipes
function onexit() {
	if [ -n "$1" ] ; then
		echo "$1"
	fi
	$ZEROCAT < /dev/zero
	if [ -f $EXITING ] ; then
		return
	fi
	for c in EXIT KILL QUIT TERM ; do
		trap - $c
	done
	if [[ "0$(cat $WATCHDOG)" -lt 3 ]] ; then
		touch $EXITING
		rm -f "$WATCHDOG" 2> /dev/null
		sleep 6
		machinectl shell $MACHNAME poweroff
		while [ 0$(machinectl list | grep "$MACHNAME" | wc -l) -gt 0 ] ; do sleep 4 ; done
		for i in $ONEXIT ; do CMD=$(rtcmd "$i") ; $CMD ; done
		for i in $COMMANDS ; do killcmd $(rtcmd "$i") ; done
		# here copy work away
# strafe stop mprune mounts dismount mounts clean $MACHNAME
		echo "strafe list"
		strafe list
		echo "strafe mounts"
		strafe mounts
		exit
	fi
}
function dospawn() {
	echo "systemd-nspawn $@"

	# waits on 2 > DOG; exits
	(N=0; while [ -w $WATCHDOG ] ; do N=$(cat $WATCHDOG); if [[ 2 == $(( 0 + 0$N )) ]]; then break; fi; sleep 2; done ; onexit dospawn) &

	if [ -n "$TEST" ] ; then
		addfifo $IN 
		addfifo $OUT	

		journaler &
		terminal &
	fi
	
	# main
	addcommand "systemd-nspawn $1 $2 $3 $4"
	if [ -n "$TEST" ] ; then
		$ZEROCAT < /dev/zero
	fi

	if [ -n "$LF" ] ; then
		systemd-nspawn $@
		onexit nspawn
	else
		(systemd-nspawn $@; onexit nspawn) &
		while ! [ -r $READY ] ; do 
			sleep 1
		done
		if [[ "$(cat /usr/src/machine-base/etc/bath-exec)" =~ "$EXEC" ]] ; then
			(strafe shell $MACHNAME /usr/scripts/bath-wrapper) &
		fi
	fi
}
# readpkgfile
function readpkgfile() {
	PKGF=$1
	if [ $(cat $PKGF | head -1) == "#!/bin/sh" ] && [ -f $PKGF ] ; then
		source $PKGF
		${MACH}_${FUNC}
	else
		echo "No description for machine $MACHNAME!"
		exit
	fi
}
# filters
function multimedia_binds() {
	BINDS=""
	for i in $(ls /dev/char/{14,81,116,189}* 2>/dev/null | P=1 clean | RP=1 readloop echo) ; do BINDS="$BINDS --bind=$i" ; done
	for i in $(ls /dev/char/{14,81,116,189}* 2>/dev/null | P=1 clean | readloop echo) ; do BINDS="$BINDS --bind=$i" ; done
	echo $(echo "$BINDS" | sed -e 's/:/\\:/g')
}
function overlay_binds() {
	OVERLAYS=""
	for i in bin boot etc lib lib64 opt root sbin srv system usr var ; do 
		OVERLAYS="$OVERLAYS --overlay=+/$i::/$i"
	done
	echo $OVERLAYS
}
# tmpdir
export TMPDIR=$STRAFD/mounts/$NICKNAME
mkdir -p $TMPDIR
ln -s $TMPDIR $MACHLINK
chmod a+rw $TMPDIR
IN=$TMPDIR/in
OUT=$TMPDIR/out
# display
addfile $TMPDIR/display.sh
cat << EOF > $TMPDIR/display.sh 
export DISPLAY="$DISPLAY"
EOF
DBUS="--bind-ro=/run/dbus/system_bus_socket"
X11="--bind-ro=/tmp/.X11-unix --bind-ro=$TMPDIR/display.sh:/etc/profile.d/display.sh"
# functionality
case "$FUNC" in
	(ide)
		BIND="--bind=/code/JetBrains/system:/system --bind=/home/ide:/root/mnt/ide --bind-ro=/code/JetBrains/apps:/code $X11"
		read -t 1 IDE		
		if [ -z "$IDE" ] ; then
			IDE=php
		fi
		if ! mount | grep -E ^/code ; then
			SUDO_USER=amsc sudo --preserve-env=SUDO_USER code-crypt.sh
			addexit umount /code
		fi
		case $IDE in
			"php")
				ARGS="(PhpStorm phpstorm.sh)"
				;;
			*)
				echo "echo <ide-choice> | $COMMAND"
				exit 
		esac
		ACCT=ide
		EXEC="ide-wrapper"
		;;
	(zoom)
		BIND="--bind-ro=/data/music:/mnt --bind=/tmp/pulse.socket --bind=/home/tonk:/root/mnt/tonk --bind=/dev/audio1 $(multimedia_binds) $X11"
		ACCT=tonk
		EXEC="zoom-wrapper"
		;;
	(skype)
		BIND="--bind-ro=/data/music:/mnt --bind=/tmp/pulse.socket --bind=/home/tonk:/root/mnt/tonk --bind=/dev/audio1 $(multimedia_binds) $X11"
		ACCT=tonk
		EXEC="skypeforlinux"
		;;
	#(browser)
	#	BIND="--bind-ro=/data/music:/mnt --bind=/tmp/pulse.socket --bind=/home/tonk:/root/mnt/tonk --bind=/dev/audio1 $(multimedia_binds) $X11"
	#	# --bind=/run/dbus/system_bus_socket
	#	ACCT=tonk
	#	EXEC="browser-wrapper"
	#	;;
	(firefox)
		BIND="--bind-ro=/data/music:/mnt --bind=/tmp/pulse.socket --bind=/home/tonk:/root/mnt/tonk --bind=/dev/audio1 $(multimedia_binds) $X11"
		ACCT=tonk
		EXEC="firefox"
		;;
	(fetchmail)
		IMG="/mach/machines/fetchmail.raw"
		BIND="--bind=/home/donk:/root/mnt/donk $X11"
		ACCT=donk
		EXEC="xterm"
		#EXEC="fetchmail-wrapper"
		ARGS="--safe-mode --ProfileManager --allow-downgrade"
		;;
	(loffice)
		BIND="--bind=/home/dumb:/root/mnt/dumb --bind-ro=/home/amsc/Documents:/home/dumb/RODocuments $X11"
		ACCT=dumb
		EXEC="soffice"
		;;
	(steam)
		BIND="--bind=/home/steam:/root/mnt/steam $X11"
		ACCT=steam
		EXEC="steam"
		;;	
	(session)
		BIND="--bind=/home/dumb:/root/mnt/dumb"
		ACCT=dumb
		EXEC="lxsession"
		;;
	(base)
		FUNC=test
		MACH=base
		;&
	(test)
		BIND="--bind=/tmp/pulse.socket --port=4713 --bind-ro=/data/music:/mnt --bind=/home/dumb:/root/mnt/test $(multimedia_binds) $X11"
		#BIND="--bind=/code/JetBrains/system:/system --bind=/home/ide:/root/mnt/test --bind-ro=/code/JetBrains/apps:/code $X11"
		ACCT=test
		EXEC="qterminal"
		;;
	*)
		PKGF=/mach/machines/$MACH.pkgs
		readpkgfile $PKGF
esac
# trap
for c in EXIT KILL QUIT TERM ; do
	trap onexit $c
done
# towels
addfile $TMPDIR/thing.sh
cat << EOF > $TMPDIR/thing.sh
export ACCT="$ACCT"
export EXEC="$EXEC"
export ARGS=$ARGS
export PIDFILE="/home/$ACCT/wrapper.pid"
export NO_AT_BRIDGE=1
export PULSE_SERVER=unix:/tmp/pulse.socket
export QT_GRAPHICSSYSTEM=native
export QT_DEBUG_PLUGINS=1
export PATH="$PATH:/usr/scripts"
EOF
# args
unset ARGS
#
BIND="--bind-ro=$TMPDIR/thing.sh:/etc/profile.d/towel.sh $BIND"
ARGS="--hostname=$FUNC --network-bridge=br0 --drop-capability=CAP_AUDIT_WRITE $@"
# nameif the internet is made of cats, of what material is ramsgate constructed?
export MACHINE=$FUNC-$MACH
# hostname
HOSTNAME=$TMPDIR/hostname-$MACHINE
addfile $HOSTNAME
cat << EOF > $HOSTNAME
$MACH
EOF
# world
WORLD=$TMPDIR/world
addfile $WORLD
mkdir -p $TMPDIR/flags
chmod 0755 $TMPDIR/flags
cat << EOF > $WORLD
export MACHINE=$FUNC-$MACH
export MACH=$MACH
export HOSTNAME=$FUNC
export MACHNAME=$MACHNAME
export ACCT=$ACCT
export MACHIP=$(machip $MACHNAME)
EOF
#
ARGS="$ARGS -b -M $MACHNAME"
BIND="--bind-ro=$HOSTNAME:/etc/hostname $BIND"
#BIND="$BIND --bind=/xpra/$MACH"
# image
if [ -z "$IMG" ] ; then
	mkraw-machine.sh $MACH
	IMG=/mach/machines/$MACH.raw
fi
# watchdog
export WATCHDOG=$TMPDIR/flags/watchdog
export EXITING=$TMPDIR/flags/exiting
export READY=$TMPDIR/flags/ready
addlink $DOG $WATCHDOG
echo 0 > $WATCHDOG
chmod a+rw $WATCHDOG
BIND="--bind=$TMPDIR/flags:/tmp/flags $BIND"
# journal
addfile $TMPDIR/nspawn-$MACHINE
JOURNALPORT=$(newport)
CONEPORT=$(newport)
cat << EOF > $TMPDIR/nspawn-$MACHINE
JOURNALHOST=$BRIDGEHOST
JOURNALPORT=$JOURNALPORT
CONEHOST=$BRIDGEHOST
CONEPORT=$CONEPORT
EOF
export NETCAT="$(which netcat) -l -p $JOURNALPORT"
addcommand "$NETCAT"
ZEROCAT="$(which netcat) -z localhost $JOURNALPORT"
BIND="--bind-ro=$TMPDIR/nspawn-$MACHINE:/tmp/environmentfile --bind=$TMPDIR/flags:/tmp/flags $BIND"
# sums
#if [ -z "$NOSHA" ] ; then
	#pushd /mach/machines
	#SUM=$(grep $MACH.raw /root/machines.sums)
	#CHK=$(sha256sum $MACH.raw)
	#popd
	#if [ "$SUM" != "$CHK" ] ; then
	#	zenity --warning --text="failed sha256 check..."
	#	echo "actual   ... $CHK"
	#	echo "expected ... $SUM"
	#	exit 1
	#fi
#fi
# volatility
if [ -n "$NOEPH" ] ; then
	true
else
	if [ -n "$NOTMP" ] ; then
		ARGS="$ARGS --ephemeral"
		MACHDIR=$MACH
	else
		# mount points
		BINDDIR=$TMPDIR/bind		
		LOWER=$BINDDIR/lower
		LAYER=$MLAYER/$NICKNAME/layer
		MACHDIR=$BINDDIR/machine
		SCRATCHDIR=$BINDDIR/runtime
		UPPER=$LAYER/upper
		WORK=$LAYER/work
		DOCNAME=$NICKNAME
		mkdir $BINDDIR
		mkdir $LOWER
		mkdir $MACHDIR
		mkdir -p $UPPER
		mkdir -p $WORK
		SYSTEMD=/usr/lib/systemd/system
		# 
		echo "writing bind mount..."
		BINDMOUNT=$SYSTEMD/$(echo $BINDDIR | tr '/' '-' | sed -e 's/^-//').mount
cat << EOF > $BINDMOUNT
[Unit]
Description=$DOCNAME bind mount
ConditionPathIsMountPoint=/mach
ConditionPathIsDirectory=$TMPDIR
ConditionPathIsSymbolicLink=!$BINDDIR
DefaultDependencies=no
Conflicts=umount.target

[Mount]
What=tmpfs
Where=$BINDDIR
Type=tmpfs
EOF
		#
		echo "writing raw machine mount..."
		LOWERMOUNT=$SYSTEMD/$(echo $LOWER | tr '/' '-' | sed -e 's/^-//').mount
cat << EOF > $LOWERMOUNT
[Unit]
Description=$DOCNAME lower mount
ConditionPathIsMountPoint=/mach
ConditionPathIsDirectory=$TMPDIR
ConditionPathIsSymbolicLink=!$LOWER
DefaultDependencies=no
Conflicts=umount.target

[Mount]
What=/mach/machines/$MACH.raw
Where=$LOWER
Type=ext4
Options=loop
EOF
		#
		echo "writing runtime tmpfs mount..."
		RUNTIMEMOUNT=$SYSTEMD/$(echo $SCRATCHDIR | tr '/' '-' | sed -e 's/^-//').mount
cat << EOF > $RUNTIMEMOUNT
[Unit]
Description=$DOCNAME runtime mount
ConditionPathIsMountPoint=/mach
ConditionPathIsDirectory=$TMPDIR
ConditionPathIsSymbolicLink=!$SCRATCHDIR
DefaultDependencies=no
Conflicts=umount.target

[Mount]
What=tmpfs
Where=$SCRATCHDIR
Type=tmpfs
EOF
		#
		echo "writing overlay mount service..."
		MACHDIRMOUNT=$SYSTEMD/$(echo $MACHDIR | tr '/' '-' | sed -e 's/^-//').mount
cat << EOF > $MACHDIRMOUNT
[Unit]
Description=$DOCNAME machine mount
ConditionPathIsMountPoint=/mach
ConditionPathIsDirectory=$TMPDIR
ConditionPathIsSymbolicLink=!$MACHDIR
DefaultDependencies=no
Conflicts=umount.target

[Mount]
What=$SCRATCHDIR
Where=$MACHDIR
Type=overlay
Options=lowerdir=$LOWER,upperdir=$UPPER,workdir=$WORK
EOF
		#
		echo "reloading systemd..."
		systemctl daemon-reload
		#
		echo "starting overlay service..."
		systemctl start $(basename $BINDMOUNT)
		systemctl start $(basename $LOWERMOUNT)
		systemctl start $(basename $RUNTIMEMOUNT)
		systemctl start $(basename $MACHDIRMOUNT)
	fi
fi
#
echo "systemd-nspawn..."
dospawn -D $MACHDIR $ARGS $BIND $@
#
addcommand "sleep 5"
while [ -w $WATCHDOG ] ; do sleep 5; S=$(cat $WATCHDOG); if [[ 2 -lt $(( 0 + 0$S )) ]] ; then break; fi; done
onexit eof
