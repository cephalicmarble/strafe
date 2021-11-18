#!/bin/sh
. script-helpers.sh
STRAFD=/mach/.machines
MLAYER=/mach/.journals
SYSTEMD=/usr/lib/systemd/system
CHAIND=/mach/.chains
MOUNTF=$CHAIND/mountfile
#
function addmount() {
 	cat <<-EOF >> $MOUNTF
$(basename $1)
EOF
}
# write a systemd .mount service file
function write_mount_file() {
	WHAT=$1
	TYPE=$2
	WHERE=$3
	OPTIONS=""
	WHERETR=$(echo $WHERE | tr '/' '-' | sed -e 's/^-//')
	if [ "$#" -gt 3 ] ; then 
		shift 3
		OPTIONS="Options=$@"
	fi
	# RO=1 write_mount...(q.v.) protects lower filesystem image
	if [ -n "$RO" ] ; then
		if [ "$#" -gt 3 ] ; then 
			OPTIONS="$OPTIONS,ro"
		else
			OPTIONS="Options=ro"
		fi
	fi
	#if [[ "$OPTIONS" =~ "=ro" ]] || [[ "$OPTIONS" =~ ",ro" ]] ; then	
	#	T=$(dirname $WHERE)/readonlyfs
	#	cp $WHAT $T
	#	WHAT="$T"
	#fi
	MOUNTFILE=$SYSTEMD/$WHERETR.mount
cat << EOF > $MOUNTFILE
[Unit]
Description=$(basename $MOUNTFILE) for $WHAT
ConditionPathIsDirectory=/mach/.chains
ConditionPathIsDirectory=$MNTDIR
ConditionPathIsSymbolicLink=!$WHERE
DefaultDependencies=no
Conflicts=umount.target

[Mount]
What=$WHAT
Where=$WHERE
Type=$TYPE
EOF
	if [ -n "$OPTIONS" ] ; then
		echo $OPTIONS >> $MOUNTFILE
	fi
	# record for later deletion
	spinlock $MOUNTF "addmount $MOUNTFILE"
	# echo location
	echo $MOUNTFILE	
}
# way that chain names are mangles
function chainmangle() {
	echo $1 | tr -d '[:space:]' | tr -c '[:alnum:]' '_'
}
# truncate the mountfile (use on startup)
function flattenfiles() {
	if [[ "$@" =~ "--mountfile" ]] ; then
		if [ -f $MOUNTF ] ; then
			rm $MOUNTF
		fi
		touch $MOUNTF
	fi
}
# call in a shell script to partition the mount-space
function init_chain() {
	CHAINNAME="$CHAIN"
	CHAINDIR="$CHAIND/$(chainmangle $CHAINNAME)"
	LAYER=$MLAYER/chains/$CHAINNAME
	mkdir -p $MLAYER/chains/$CHAINNAME
	mkdir -p $CHAINDIR
	if [ -L $LAYER/$CHAINNAME ] ; then
		unlink $LAYER/$CHAINNAME
	fi
	ln -s $LAYER $CHAINDIR/layer
	MNTDIR=$CHAINDIR/mounts
	if ! [ -d $MNTDIR ] ; then
		mkdir -p $MNTDIR
	fi
	if [ 0 == $(grep $MNTDIR /proc/mounts | wc -l) ] ; then
		mount -t tmpfs tmpfs $MNTDIR
	fi
}
#
function chain() { # name [highest, lower, ...] [--options]
	name="$1"
	shift 1
	if [ -z "$name" ] ; then
		echo "Usage: chain <name> [highest, lower, ...] [--options]"
		return
	fi
	binddir=$MNTDIR/$name/bind
	LOWER=$binddir/lower
	MACHDIR=$binddir/overlay
	UPPER=$LAYER/$name/upper # protective at present HEREIAM
	WORK=$LAYER/$name/work
	LMOUNTF=$LAYER/$name/lmountf
	TMOUNTF=$LAYER/$name/tmountf
	mkdir -p $UPPER
	mkdir -p $WORK
	touch $LMOUNTF
	LOWERS=
	IDX=$(( $# - 1 ))
	for arg in $@ ; do
		declare -a args
		args=($(echo "${arg}" | tr -d "\"" | tr ':' ' '))
		name=${args[0]}
		filesystem=${args[1]}
		echo "Process lower $name:$filesystem..."
		dev=$(realpath $filesystem)
		if [ -b $dev ] ; then
			RO=1 write_mount_file $dev auto ${LOWER}${IDX} >> $TMOUNTF
		elif [ -f $dev ] && [[ "$(file $dev)" =~ "filesystem data" ]] ; then
			RO=1 write_mount_file $dev auto ${LOWER}${IDX} loop >> $TMOUNTF
		elif [ -d $dev ] ; then
			RO=1 write_mount_file $dev auto ${LOWER}${IDX} bind >> $TMOUNTF
		else
			echo "Unknown filesystem object: $dev"
			false
			return
		fi
		if [ -z "$LOWERS" ] ; then
			LOWERS="${LOWER}${IDX}"
		else
			LOWERS="$LOWERS:${LOWER}${IDX}"
		fi
		IDX=$(( $IDX - 1 ))
	done
	echo "Writing mounts..."

	write_mount_file tmpfs tmpfs $binddir >> $TMOUNTF

	tac $TMOUNTF >> $LMOUNTF
	rm $TMOUNTF

	write_mount_file overlay overlay $MACHDIR lowerdir=$LOWERS,upperdir=$UPPER,workdir=$WORK >> $LMOUNTF

	echo "reloading systemd..." 1>&2
	if ! systemctl daemon-reload 1>&2 ; then
		echo "Failed daemon-reload." 1>&2
		false
		removefilesfrom $LMOUNTF
		return
	fi
	#
	echo "Loading systemctl mounts..."
	cat $LMOUNTF | (while true ; do read mountfile ; 
		if [ -z "$mountfile" ] ; then
			break
		fi
		if [[ "$mountfile" =~ ".mount" ]] ; then
			echo "Starting $(basename $mountfile)..."
			if ! systemctl start $(basename $mountfile) 1>&2 ; then
				echo "failed bind mount." 1>&2
				false
				removefilesfrom $LMOUNTF
				return
			fi
		else
			if ! [ -d $mountfile ] ; then
				mkdir -p $mountfile
			fi
		fi
	done)
	echo "chain mount success."
}
#
function removefilesfrom() {
	for i in $@ ; do
		mountf=$i
		name=$(basename $(dirname $mountf))
		tac $mountf | (while true ; do read mountfile ; 
			if [ -z "$mountfile" ] ; then
				break
			fi
			if [[ "$mountfile" =~ ".mount" ]] ; then
				#systemctl status $(basename $mountfile) 1>&2
				echo "removing $mountfile..." 1>&2
				rm $mountfile
			else
				continue
			fi
		done)
		rm $mountf
		umount -R $CHAIND/$CHAIN/mounts/$name/bind
		if [ 0 == $(grep $CHAIND/$CHAIN/mounts/$name/bind /proc/mounts | wc -l) ] ; then
			rm -fr 	$CHAIND/$CHAIN/mounts/$name/bind
		fi
	done
}
#
function unmount() { 
	if [ -z "$1" ] ; then
		name="*"
	else
		name=$1
	fi
	removefilesfrom $LAYER/$name/lmountf
}
function chaintest() {
	echo "test..."
	flattenfiles --mountfile
	CHAIN=test init_chain 
	echo "initialized."
	if ! [ -d test1 ] ; then
		mkdir test1
		echo "blargle" > test1/a
	fi
	if ! [ -d test2 ] ; then
		mkdir test2
		echo "argle" > test2/a
	fi
	echo "chain test1 test2..."
	chain test fs2:./test2 fs1:./test1
	find /mach/.chains/test -name a -exec more {} \;
	blargle="$(cat ./test1/a)"
	argle="$(cat ./test2/a)"
	content="$(cat $(find /mach/.chains/test -name overlay)/a)"
	if [ "$argle" != "$content" ] ; then
		echo "non argle in overlay : $content"
	else
		echo "overlay held : $content"
	fi
	echo "unmount."
	unmount	
	return
	echo "re-initialize"
	CHAIN=test init_chain
	echo "chain fs1 fs2 fs3"
	#chain fs1:$(realpath test.raw) fs2:$(realpath subimg.raw) fs3:$(realpath appk.raw)
	mount overlay -t overlay $CHAIND/$CHAIN/mounts -o lowerdir=$(realpath ./test)
	echo "pacman fs1"
	pacman --root=/mach/.chains/test/mounts/fs1/bind/overlay -Qi tree
	echo "pacman fs2"
	pacman --root=/mach/.chains/test/mounts/fs2/bind/overlay -Qi gnu-netcat
	echo "pacman fs3"
	pacman --root=/mach/.chains/test/mounts/fs3/bind/overlay -Qi psmisc
}
