#!/bin/sh
DIRF=$(mktemp)
BRIDGETMPDIR=/$HOME/bridge-tmp
BRIDGECONF=$BRIDGETMPDIR/conf
if ! [ -d $BRIDGETMPDIR ] ; then
	mkdir $BRIDGETMPDIR
fi
touch $BRIDGECONF
function setup() {
	export BRIDGE=169.254.0
	export BRIDGENET=169.254.0.0/24
	export BRIDGEHOST=169.254.0.1
	export BRIDGEADDR=169.254.0.1/24
	export BRIDGEMASK=${BRIDGENET/*\/}
	export DOCKER=172.17.0
	export DOCKERNET=172.17.0.0/16
	export DOCKERHOST=172.17.0.1
	export DOCKERADDR=172.17.0.1/24
	export DOCKERMASK=${DOCKERNET/*\/}
	cat << EOF > /etc/profile.d/bridge.sh
	export BRIDGE=$BRIDGE
	export BRIDGENET=$BRIDGENET
	export BRIDGEHOST=$BRIDGEHOST
	export BRIDGEADDR=$BRIDGEADDR
	export BRIDGEMASK=$BRIDGEMASK
	export DOCKER=$DOCKER
	export DOCKERNET=$DOCKERNET
	export DOCKERHOST=$DOCKERHOST
	export DOCKERADDR=$DOCKERADDR
	export DOCKERMASK=$DOCKERMASK
EOF
	export BRIDGETMPDIR=$BRIDGETMPDIR
	export BRIDGECONF=$BRIDGECONF
	cat <<-EOF > $BRIDGECONF
	s/%BRIDGE%/$BRIDGE/;
	s/%BRIDGENET%/${BRIDGENET/\//\\\/}/;
	s/%BRIDGEHOST%/$BRIDGEHOST/;
	s/%BRIDGEADDR%/${BRIDGEADDR/\//\\\/}/;
	s/%BRIDGEMASK%/${BRIDGEMASK}/;
	s/%DOCKER%/$DOCKER/;
	s/%DOCKERNET%/${DOCKERNET/\//\\\/}/;
	s/%DOCKERHOST%/$DOCKERHOST/;
	s/%DOCKERADDR%/${DOCKERADDR/\//\\\/}/;
	s/%DOCKERMASK%/${DOCKERMASK}/;
EOF
	cat $BRIDGECONF
}
function lf() {
	CMD="$*"
	echo $CMD
	$CMD
}
function chkbr() {
	lf modprobe br_netfilter
	lf ifconfig br0 down
	lf ifconfig br0 up ${BRIDGEHOST}/${BRIDGENET/*\/}
	lf ip link set dev br0 up
	#for i in $(ifconfig -s | grep vb | cut -f1 -d\ ) ; do
	#	brctl addif br0 $i
	#done
	#lf brctl show br0
}
function chkconf() {
	for i in $@ ; do
		if [ -n "$TEST" ] ; then
			echo $i
		fi
		DIR="$BRIDGETMPDIR/$(dirname $i)"
		if ! [ -d $DIR ] ; then
			mkdir -p $DIR
		fi
		OUTPUT="$DIR/$(basename $i .bridge)"
 		cp $i $OUTPUT
		lf sed -i -f $BRIDGECONF $OUTPUT
		if [ -n "$TEST" ] ; then
			more $OUTPUTglobalresearc
		fi
		echo $DIR >> $DIRF
	done
}
function work() {
	for i in $(echo $@) ; do
		case "$1" in
			"host-net")
				chkconf /usr/src/netfilter/*.bridge
				chkconf /usr/src/hosts.bridge
				chkconf /usr/src/network/*.bridge
				chkconf /usr/src/pulse/*.bridge
				rsync -lr $BRIDGETMPDIR/usr/src/pulse/ /etc/pulse/
				rsync -lr $BRIDGETMPDIR/usr/src/netfilter/ /etc/netfilter/
				rsync -vlr $BRIDGETMPDIR/usr/src/network/ /etc/systemd/network/
				nft flush ruleset ; nft -f - < /etc/nftables.conf
				mv $BRIDGETMPDIR/usr/src/hosts /etc/hosts
				chkbr
			;;
			"guest-net")
				chkconf $(find /usr/src/machine-base -name \*.bridge)
				find $BRIDGETMPDIR/usr/src/machine-base/network/ -name \*.network -exec cp {} /usr/src/machine-base/network/ \;
			;;
		esac
	done
	cat $DIRF | uniq
	#
	if [ -n "$NORM" ] ; then
		find $BRIDGETMPDIR -type f -exec rm {} \;
		for i in $(find $BRIDGETMPDIR -type d | tac) ; do rmdir $i ; done
		rm -f $DIRF
	fi
}
#
if [ -n "$DOWORK" ] || ([ $SHLVL == 1 ] && [ -z "$NOWORK" ]) ; then
	setup
	work host-net 
	work guest-net
fi
#
function shiftname() {
	export MACHL=$(find /mach/.machines/run/ -maxdepth 1 -name $1 -or -name $1\* -or -name \*-$1-\*)
	echo $MACHL
}
