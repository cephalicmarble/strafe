#!/bin/sh
function mkraw_init() {
	MACH=/mach/machines
	IMGDIR=$(mktemp -d)
	if [ -z "$DATE" ] ; then
		DATE=$(date +%s)
	fi
}
#
function dir2raw() {
	dir=$1
	img=$2
	if [[ ! -d $dir ]] ; then
		echo "$dir does not exist!"
		exit
	fi
	touch $img
	T=$(du -cms $dir | tail -1 | cut -f1 -dt)
	size=$(( $(( $T % (1 << 10) )) + $(( ($T >> 10) << 10 )) + 512 ))
	echo "fs/$T raw/$size"
	#
	echo "Zeroing image..."
	dd if=/dev/zero of=$img bs=$((1 << 20)) count=$size
	#
	echo "Making filesystem..."
	mkfs.ext4 $img -F
	#
	echo "Mounting image..."
	tmp=/tmp/$(basename $0)-imagemount-$DATE
	mkdir $tmp
	mount $img $tmp -o loop
	#
	echo "Syncing filesystem..."
	rsync -vlr $dir/ $tmp/ -q
	#
	echo "Unmounting image..."
	umount $tmp
	rmdir $tmp
	#
	if [[ "$@" =~ "--relabel" ]] ; then
		echo "Relabeling..."
		systemd-nspawn -i $img /usr/bin/restorecon -R /
	fi
	#
	if [[ "$@" =~ "--gpgsign" ]] ; then
		echo "Signing image..."
		gpg --detach-sign $img
	fi
}
#
function mkmachine() {
	name=$1
	if [[ -z "$name" ]] ; then
		echo "Machine with no name!"
		exit
	fi
	machdir=$MACH/$name
	img=$IMGDIR/$name.raw
	IMG=$img
	NAME=$name
	if [[ -f $img ]] ; then
		echo "$img already exists!"
		if zenity --question --text="Rebuild $machdir?" --ok-label="Yes, I mean to!" --cancel-label="No, my mistake!" ; then
			rm -f $img
		else
			exit;
		fi
	else
		if ! zenity --question --text="Build $machdir?" --ok-label="Yes, I meant to!" --cancel-label="No, cancel that!" ; then
			exit;
		fi
	fi

	DIR=/tmp/$(basename $0)-machinemount-$DATE
	if [ -z "$CHAIN" ] ; then
		mkdir $DIR
		DIR=$DIR rebuild-machines.sh $NAME 1>&1
		dir2raw $DIR $IMG
		rm -fr $DIR
	else
		export CHAIN
		DIR=$DIR rebuild-machines.sh $NAME 1>&1
		dir2raw $DIR $IMG
	fi
}
function shrink_raw() {
	echo "fsck and shrink..."
	e2fsck -f $1 1>&2
	resize2fs -M -p $1 1>&2
}
#
if [[ $- == *i* ]] && [ -z "$PKGF" ] ; then
	for i in $@ ; do 
		mkmachine $i
	done
	#
	#echo "Calculating checksum..."
	#sha256sum $@ >> /root/machines.sums
	#
	echo "image is '$IMG'."
	echo "moving to $MACH..."
	mv $IMG $MACH/$NAME.raw
	rm -fr $IMGDIR
	echo "image at $MACH/$NAME.raw"
	echo "Done."
fi
