#!/bin/sh

STRAFD=/mach/.machines
MLAYER=/mach/.journals
SYSTEMD=/usr/lib/systemd/system
CHAIND=/mach/.chains
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
function write_mount_file() {
	WHAT=$1
	TYPE=$2
	WHERE=$3
	MOUNTFILE=$SYSTEMD/$(echo $WHERE | tr '/' '-' | sed -e 's/^-//').mount
cat << EOF > $MOUNTFILE
[Unit]
Description=chain-functions bind mount for $WHAT
ConditionPathIsMountPoint=/mach
ConditionPathIsDirectory=$TMPDIR
ConditionPathIsSymbolicLink=!$WHERE
DefaultDependencies=no
Conflicts=umount.target

[Mount]
What=$WHAT
Where=$WHERE
Type=$TYPE
EOF
	if [ "$#" -gt 3 ] ; then 
		shift 3
		echo Options=$@ >> $MOUNTFILE
	fi
	echo $MOUNTFILE
}
#
function init_chain() {
	CHAINNAME="$CHAIN"
	CHAINDIR="$CHAIND/$(echo $CHAINNAME | tr -d '[:space:]' | tr -c '[:alnum:]' '_')"
	LAYER=$CHAINDIR/layer
	mkdir -p $MLAYER/chains/$CHAINNAME
	mkdir -p $CHAINDIR
	LAYERF=$CHAINDIR/cakefile
	if [[ "$@" =~ "--cakefile" ]] ; then
		rm $LAYERF
		touch $LAYERF
	fi
	MOUNTF=$CHAINDIR/mountfile
	if [[ "$@" =~ "--mountfile" ]] ; then
		rm $MOUNTF
		touch $MOUNTF
	fi
	ln -s $MLAYER/chains/$CHAINNAME $LAYER
	TMPDIR=$CHAINDIR/mounts
	if ! [ -d $TMPDIR ] ; then
		mkdir -p $TMPDIR
		mount -t tmpfs tmpfs $TMPDIR
	fi
}
#
function overlay {
	WHAT=$1
	LAYERNAME=$2
	CAKE=$3
	# unique directory name
	if [ -z "$LAYERNAME" ] ; then
		echo "No named directory string for $@ - using mktemp" 1>&2
		LAYERNAME=$(mktemp -u -d --tmpdir=$TMPDIR)
	fi
	# mount points
	BINDDIR=$TMPDIR/$LAYERNAME/bind
	LOWER=$BINDDIR/lower
	MACHDIR=$BINDDIR/overlay
	SCRATCHDIR=$BINDDIR/runtime
	UPPER=$LAYER/$LAYERNAME/upper # protective at present HEREIAM
	WORK=$LAYER/$LAYERNAME/work
	mkdir -p $BINDDIR
	mkdir $LOWER
	mkdir $MACHDIR
	mkdir $SCRATCHDIR
	mkdir -p $UPPER
	mkdir -p $WORK
	# 
	echo "writing bind mount..." 1>&2
	BINDMOUNT=$(write_mount_file tmpfs tmpfs $BINDDIR)
	#
	echo "writing $WHAT mount..." 1>&2
	if [ -d $WHAT ] ; then # is lower when overlaying tmpfs
		LOWERMOUNT=$(write_mount_file $WHAT auto $LOWER bind)
	elif [ -f $WHAT ] ; then
		LOWERMOUNT=$(write_mount_file $WHAT auto $LOWER loop)
	else
		echo "$WHAT is neither file nor directory."
		exit
	fi
	#
	if [ -z "$CAKE" ] ; then
		echo "writing runtime tmpfs mount..." 1>&2
		RUNTIMEMOUNT=$(write_mount_file tmpfs tmpfs $SCRATCHDIR)
	else
		if [[ $CAKE =~ "bind/overlay" ]] && grep $CAKE /proc/mounts ; then
			SCRATCHDIR=$CAKE
		else
			RUNTIMEMOUNT=$(write_mount_file $CAKE auto $SCRATCHDIR bind)
			unset CAKE
		fi
	fi
	#
	echo "writing overlay mount service..." 1>&2
	MACHDIRMOUNT=$(write_mount_file $SCRATCHDIR overlay $MACHDIR lowerdir=$LOWER,upperdir=$UPPER,workdir=$WORK)
	#
	if [[ $CAKE =~ "bind/overlay" ]] ; then
		cat <<-EOF >> $MOUNTF
$BINDMOUNT
$LOWERMOUNT
$MACHDIRMOUNT
EOF
	else
		cat <<-EOF >> $MOUNTF	
$BINDMOUNT
$LOWERMOUNT
$RUNTIMEMOUNT
$MACHDIRMOUNT
EOF
	fi

	echo "reloading systemd..." 1>&2
	if ! systemctl daemon-reload 1>&2 ; then
		echo "Failed daemon-reload." 1>&2
		false
		return
	fi
	#
	echo "starting $BINDMOUNT service..." 1>&2
	if ! systemctl start $(basename $BINDMOUNT) 1>&2 ; then
		echo "failed bind mount." 1>&2
		false
		return
	fi
	#
	echo "starting $LOWERMOUNT service..." 1>&2
	if ! systemctl start $(basename $LOWERMOUNT) 1>&2 ; then
		echo "failed mount $WHAT." 1>&2
		false
		return
	fi
	#
	if [ -z "$CAKE" ] ; then
		echo "starting $RUNTIMEMOUNT service..." 1>&2
		if ! systemctl start $(basename $RUNTIMEMOUNT) 1>&2 ; then
			echo "failed runtime tmpfs mount. System OOM?!" 1>&2
			false
			return
		fi
	fi
	#
	echo "starting $MACHDIRMOUNT service..." 1>&2
	if ! systemctl start $(basename $MACHDIRMOUNT) 1>&2 ; then
		echo "failed overlay mount." 1>&2
		false
		return
	fi
	#
	echo $MACHDIR
	if [ -L $CHAINDIR/$LAYERNAME ] ; then
		unlink $CHAINDIR/$LAYERNAME
	fi
	ln -s $MACHDIR $CHAINDIR/$LAYERNAME
	if [ -n "$3" ] ; then
		add_llist $3 $2:$1
	else
		add_llist none $2:$1
	fi
	true
}
#
function add_llist() { # lower upper
	LAYERF=$CHAINDIR/cakefile
	T=$(grep "$1<-" $LAYERF)
	if [ -z "$T" ] ; then
		echo "$1<-$2" >> $LAYERF
	elif ![[ "$T" =~ $2 ]] ; then
		A=$(mktemp)
		cat $LAYERF | sed -re "s/$1<-.*\$//" > $A
		echo "$T $2" >> $A
		mv $A $LAYERF
	fi
}
function rmv_llist() { # lower upper
	LAYERF=$CHAINDIR/cakefile
	T=$(grep "$1<-" $LAYERF)
	if [ -z "$T" ] ; then
		echo "$1 never lower." 1>&2
	else
		A=$(mktemp)
		cat $LAYERF | sed -re "s/^$1<-(.*)\ $2(.*)\$/$1<-\1\2/" -e "s/^$1<-$2\ (.*)\$/$1<-\1/" > $A
		mv $A $LAYERF
		prune_llist
	fi
}
function prune_llist() {
	LAYERF=$CHAINDIR/cakefile
	for i in $(grep -E '^[a-z]+\<\-$' $LAYERF) ; do
		umount -R $CHAINDIR/mounts/${i/<-}/bind
	done
}
#
function clist() {
	CHAIN="$1"
	CAKE="$2"
	if [ -z "$CHAIN" ] ; then
		return
	fi
	if [ -z "$CAKE" ] ; then
		CAKE=none
	fi
	LAYERF=$CHAINDIR/cakefile
	CHAIN=$(echo $1 | tr -d '[:space:]' | tr -c '[:alnum:]' '_')
	for i in $(grep $CAKE $LAYERF | cut -f2 -d\< | tr '-' ' ') ; do
		declare -a args
		args=($(echo "${i}" | tr -d "\"" | tr ':' ' '))
		if [ -z "$3" ] || [[ "${args[0]}" =~ "$3" ]] ; then
			echo $CHAIND/$CHAIN/${args[0]}
		fi
	done
}
#
function chain() { # name:filesystem [, lower]
	CAKE="$2"
	if [ -n "$CAKE" ] ; then
		if [ -d $CAKE ] ; then
			lower=$CAKE
		elif [ -d $CHAINDIR/$CAKE ] ; then
			lower=$CHAINDIR/$CAKE
		elif [ -d $CHAINDIR/$CAKE/bind/overlay ] ; then
			lower=$CHAINDIR/$CAKE/bind/overlay
		else
			echo "lower filesystem not mounted!" 1>&2
			return
		fi
	else
		lower=
	fi
	LAYERS="$1"
	declare -a CAKES
	declare -a args
	CAKES=$(echo $LAYERS | sed -re 's/\ /\"\ \"/' | sed -re 's/^/\"/' | sed -re 's/(.*)$/\1\"/')
	i=0
	for shit in $CAKES ; do
		args=($(echo "${shit}" | tr -d "\"" | tr ':' ' '))
		name=${args[0]}
		filesystem=${args[1]}
		under=$(clist $CHAIN $name)
		if [ -z "$under" ] ; then			
			if [ -n "$lower" ] ; then
				CMD="overlay $(realpath $filesystem) $name $(realpath $lower)"
			else
				CMD="overlay $(realpath $filesystem) $name"
			fi
			if ! $CMD  ; then
				umount -R $TMPDIR/$name/bind
				if [ 0 == $(grep $TMPDIR/${args[0]}/bind /proc/mounts | wc -l) ] ; then
					rm -fr 	$TMPDIR/${args[0]}/bind
				fi
				systemctl status $(basename $BINDMOUNT)
				systemctl status $(basename $LOWERMOUNT)
				systemctl status $(basename $RUNTIMEMOUNT) 
				systemctl status $(basename $MACHDIRMOUNT)
				for i in $BINDMOUNT $LOWERMOUNT $RUNTIMEMOUNT $MACHDIRMOUNT ; do
					sed -i -e "s/^$i\$//" $MOUNTF
				done
				false
				return
			fi
			lower=$MACHDIR
		else
			lower=under
		fi
	done
}
#
function unmount() { # name or lower-name
	if [ $# == 0 ] ; then
		umount -R $CHAINDIR/mounts/*/bind
		umount -R $CHAINDIR/mounts
		return
	fi
	cakes=$(grep $1 $LAYERF | cut -f2 -d=)
	for i in $cakes ; do
		what=$(echo $i | cut -f2 -d:)
		umount ${what/\"}
	done
	for i in $(cat $MOUNTF) ; do
		rm $i
	done
}
function cakefile() {
	LAYERF=$CHAINDIR/cakefile
	cat $LAYERF
}
if [ -n "$TEST" ] ; then
	CHAIN=test init_chain --cakefile
	mkdir test1
	echo "blargle" > test1/a
	mkdir test2
	echo "argle" > test2/a
	chain "fs1:./test1 fs2:./test2"
	clist test test2
	find /mach/.chains/test_/mounts
fi