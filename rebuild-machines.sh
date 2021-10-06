#!/bin/sh
echo "$0 $@"
env | grep -E "(CHAIN|PKGF|DIR)"
STRAFD="/mach/.machines"
MLAYER="/mach/.journals"
CHAIND="/mach/.chains"
NICKNAME="$2"
MACHINEBASE=/usr/src/machine-base
if [ -z "$DATE" ] ; then
	DATE=$(date +%s)
fi

if [ -z "$1" ] && [ -z "$NICKNAME" ] ; then
	echo "$0 : <MACH.pkgs> $(ls ./*.pkgs)"
	exit
fi
# cookie idea?
function mkdirp() {
	if ! [ -d "$1" ] ; then 
		echo "creating directory $1..."
		mkdir -p $1
	fi
}
#
READY=0
function readychain() {
	if [ "$READY" -gt 0 ] ; then
		return
	fi
	READY=1
	. chain-functions.sh
	init_chain --cakefile
}
#
function call_pacstrap() {
	echo "Checking definition..."
	if [ -z "$CHAIN" ] ; then # use PKGF
		echo "No chain..."
		# if we have a shell definition
#		if [ -f "$PKGF" ] ; then
#			if [ $(head -1 $PKGF) == "#!/bin/sh" ] ; then
#				echo "Shell definition..."
#				source $PKGF
#				PACKAGES=$($TARGET | tail -n +2)
#			else
#				PACKAGES="$PKGF"
#			fi
#		fi
#		# base packages are specified 
#		if [ -f "$PACKAGES" ] ; then
#			PACKAGES=$(cat $PACKAGES)
#		fi
#		if [ -z "$PACKAGES" ] ; then
#			PACKAGES=$(cat /mach/machines/pacstrap.pkglist)
#		fi		
#		pacstrap=/mach/machines/pacstrap
		pacman="pacman --root=$DIR --cachedir=/var/cache/pacman/pkg --noconfirm"
		if [[ ! -r $DIR/usr/lib/os-release ]] && [[ ! -r $DIR/etc/os-release ]] ; then
			pacstrap -c -M -G $DIR base pacman
			rsync -q /etc/pacman.d/mirrorlist $DIR/etc/pacman.d/mirrorlist
			#$pacman -S pacman
			#$pacman -Syu
			#rsync -q /etc/pacman.d/mirrorlist $pacstrap/etc/pacman.d/mirrorlist
		fi
	else # use PKGF
		# if we have a shell definition
		if [[ "$(file ${PKGF})" =~ "shell script" ]] ; then
			echo "Found shell script package file $PKGF"
			source ./$(basename $PKGF)
			declare -a line
			line=($($TARGET | head -1 | cut -f2,3 -d: -s))
			case ${#line[*]} in
				0)
					pacstrap=pacstrap
					name=pacstrap
				;;
				1)
					name=${line[0]}
					if [[ "$name" =~ "." ]] ; then
						pacstrap=$name
						name=$(echo $pacstrap | cut -f1 -d.)
					else
						pacstrap=$name
						if [ -f "${pacstrap}.pkgs" ] ; then
							pacstrap=${pacstrap}.pkgs
						elif [ -f "${pacstrap}.pkglist" ] ; then
							pacstrap=${pacstrap}.pkglist
						elif [ -f "${pacstrap}.raw" ] ; then
							pacstrap=${pacstrap}.raw
						fi
					fi
				;;
				2);&
				*)
					name=${line[0]} 
					pacstrap=${line[1]} # -z -> base is pacstrap or omit
				;;
			esac
			pacstrap=$(basename $pacstrap)
			name=$(basename $name)
			
			echo "pacstrap=$pacstrap name=$name"
			# setup dummy directory
			readychain
			subdir=/tmp/$(basename $0)-$pacstrap-$DATE
			mkdir $subdir
			if [ "$pacstrap" == "none" ] ; then
				ln -s $subdir $DIR
			elif [ ! -f ${pacstrap} ] ; then
				echo "Could not find sub-image or non-shell and non-text definition ($line)."
				exit
			fi
			# deal with pre-existing
			if [ -f ${name}.raw ] ; then
				if [ -n "$FORCE" ] ; then
					mv ${name}.raw ${name}.raw.bak
				else
					echo "underlaying $name:${name}.raw..."
					chain $name:${name}.raw
				fi
			else
				# rebuild
				if [ -f ${pacstrap} ] && [ "$(file ${pacstrap} | cut -f2 -d:)" == " ASCII text" ] ; then
					echo "building $pacstrap base-image from pkglist in $subdir..."
					TMPCHAIN=$CHAIN
					unset CHAIN
					DIR=$subdir PKGF=$(realpath ${pacstrap}) TARGET=$name prepare_machine
					CHAIN=$TMPCHAIN
				elif [ -f $pacstrap ] ; then
					echo "building $pacstrap base-image from definition in $subdir..."
					CHAIN=$CHAIN DIR=$subdir PKGF=$(realpath ${pacstrap}) TARGET=$name prepare_machine
				fi
				# mount
				if [ -f $pacstrap ] && [[ "$(file "$pacstrap")" =~ "ext4 filesystem data" ]] ; then
					echo "overlaying $name:$(realpath $pacstrap)..."
					chain $name:$(realpath $pacstrap)
				elif [ -f ${name}.raw ] && [[ "$(file "${name}.raw")" =~ "ext4 filesystem data" ]] ; then
					echo "overlaying $name:$(realpath ${name}.raw)..."
					chain $name:$(realpath ${name}.raw)
				fi			
			fi
			#
			overlay $CHAIND/$CHAIN/mounts/$name/bind/overlay $TARGET
			if [ -L $DIR ] ; then 
				unlink $DIR
			elif [ -r $DIR ] ; then
				rmdir $DIR
			fi
			if ! ln -s $CHAIND/$CHAIN/mounts/$TARGET/bind/overlay $DIR ; then
				echo "Bailing."
				exit
			fi
		else
			echo "$PKGF is not a shell script."
			exit
		fi
	fi
	if [ 0"$SELINUX" -gt 0 ] ; then 
		echo "Installing software..."
		yes y | $pacman -U /usr/src/selinux/*/*.zst --confirm
		$pacman -R sudo-selinux
		$pacman -R openssh-selinux
	fi
	true
}
#
function packages_impl() {
	echo "Querying installed packages..."
	pacman="pacman --root=$DIR --cachedir=/var/cache/pacman/pkg --noconfirm"
	U=
	S=
	SKIP=
	PKGS=$($pacman -Q | cut -f1 -d\ )
	for i in which $PACKAGES ; do
		if [[ "$i" =~ ":" ]] ; then
			continue
		fi
		if [[ "." != "$(dirname $i)" ]] ; then
			if ! [[ $i =~ ".zst" ]] ; then
				i="$i-x86_64.pkg.tar.zst"
			fi
			PKG=$(echo $(basename $i) | sed -re 's/-[0-9]+.*$//')
			A=($(basename "${i/-x86_64.pkg.tar.zst}" | tr '-' ' '))
			PKGVER=${A[${#A}]}
			if [[ "$PKGS" =~ "$PKG" ]] &&
				[ "$($pacman -Q "$PKG" | cut -f2 -d\ )" == "$PKGVER" ] ; then
				if [ -z "$FWORK" ] ; then
					SKIP="$SKIP $PKG"
					continue
				fi
			fi
			U="$U $i"
		else
			PKG=$(echo $(basename $i) | sed -re 's/-[0-9]+.*$//' 2>/dev/null)
			MVER=$(pacman -Q $i | cut -f2 -d\ )
			PVER=$($pacman -Q $i | cut -f2 -d\ )
			if [[ "$PKGS" =~ "$i" ]] &&
				[ "$MVER" == "$PVER" ] ; then
				if [ -z "$FWORK" ] ; then
					SKIP="$SKIP $PKG"
				fi
				continue
			fi
			S="$S $i"
		fi
	done
	echo "Skipping $SKIP"
	if [ -n "$S" ] ; then
		echo "Installing cached software..."
		echo "$pacman --overwrite=$DIR/* -S $S"
		$pacman --overwrite=$DIR/* -S $S
	fi
	if [ -n "$U" ] ; then
		echo "Installing local software..."
		echo "$pacman --overwrite=$DIR/* -U $U"
		$pacman --overwrite=$DIR/* -U $U
	fi
}
#
function packages() {
	pacman="pacman --root=$mach --cachedir=/var/cache/pacman/pkg --noconfirm"
	echo "Checking package file ($PKGF)..."
	if [[ "$(file ${PKGF})" =~ "shell script" ]] ; then
		source $PKGF
		if [[ "$($1 | head -1)" =~ ":" ]] ; then
			PACKAGES="$($1 | tee -a /dev/fd/2 | tail -n +2)" DIR=$2 packages_impl
		fi
	else
		PACKAGES="$(cat $PKGF | tee -a /dev/fd/2)" DIR=$2 packages_impl
	fi
}
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
}
#
function machine() {
	mach=$1
	#if [ "$TARGET" != "base" ] ; then
	#	iecho "Syncing config from base..."
	#	if [ 0"$SELINUX" -gt 0 ] ; then
	#		mkdirp $mach/etc/selinux
	#		cp /etc/selinux/config.nspawn $mach/etc/selinux/config

#		make_and_sync $mach etc/selinux/refpolicy-arch
	#	fi
	#fi
	if [ $TARGET != "pacstrap" ] ; then
		echo "systemd services from machine-base..."
		for i in systemd-journald.service onready.service homes.service wrapper@.service poweroff.service poweroff.target console-getty@.service ; do
			echo system/$i
			cp $MACHINEBASE/usr-lib-systemd/system/$i $mach/usr/lib/systemd/system/$i
		done
		for i in wrapper@.service xpra-zoom.service ; do
			echo user/$i
			cp $MACHINEBASE/usr-lib-systemd/user/$i $mach/usr/lib/systemd/user/$i
		done
	fi
	#scripts
	for i in system code home ; do 
		if ! [ -d $mach/$i ] ; then mkdirp $mach/$i;  fi
	done
	if [ $TARGET != "pacstrap" ] ; then
		echo "machine-base config..."
		rsync -q -vlr $MACHINEBASE/etc/ $mach/etc/
		rsync -q -vlr $MACHINEBASE/usr-lib-systemd/ $mach/usr/lib/systemd/
		mkdirp $mach/usr/scripts
		rsync -q -vlr $MACHINEBASE/scripts/ $mach/usr/scripts/
		for i in group shadow ; do
			cp /etc/{$i,${i}-} $mach/etc/
		done
		# uid/gid
		echo "users and groups..."
		for i in user exec ; do 
			cp /usr/src/machine-base/etc/bath-$i $mach/etc/
		done
		if [ "/etc/passwd" != "$mach/etc/passwd" ] ; then
			echo "disallow non-useful shells..."
			T=$(mktemp)
			cat /etc/passwd | sed -r -e 's/\/bin\/bash/\/bin\/nologin/' -e 's/\/root:\/bin\/nologin/\/root:\/bin\/bash/' > $T
			mv $T $mach/etc/passwd
			echo "permit useful shells..."
			for i in $(cat $mach/etc/bath-user) ; do
				sed -re "s/:\/bin\/nologin/:\/bin\/bash/" -i $mach/etc/passwd
				mkdirp $mach/home/$i
				mkdirp $mach/root/mnt/$i
			done
			echo "fix our transferred passwd, shadow and group databases..."
			doctor_ns passwd
			doctor_ns shadow
			doctor_ns group		
		fi
	else
		return
	fi
	# all machines...
	echo "networking..."
	DEFNET=$mach/usr/lib/systemd/network/80-container-host0.network
	if [ -f $DEFNET ] ; then rm $DEFNET ; fi
	find $mach/etc/systemd/network -name \*.network -exec rm {} \;
	find $MACHINEBASE/network -name \*.network -exec cp {} $mach/usr/lib/systemd/network \;
	SEDCMD=$(mktemp)
	for i in amsc git wrt ceph rpc postfix ntp ; do
		echo "s/$i,*//" >> $SEDCMD
	done
	echo "remove unused group entries..."
	sed -r -f $SEDCMD -i $mach/etc/group
	rm $SEDCMD
	# systemd
	echo "enabling systemd services..."
	cp $MACHINEBASE/resolved.conf $mach/etc/systemd/resolved.conf
	systemctl="systemctl --root=$mach"
	$systemctl enable systemd-networkd
	$systemctl enable systemd-resolved
	$systemctl enable homes
	$systemctl enable onready
	#$systemctl set-default getty.target 
	rig system multi-user.target.wants getty.target
	$systemctl disable getty@tty1
	for i in $(cat $mach/etc/bath-user) ; do
		$systemctl enable console-getty@$i
	done
	#roll image
	#echo "Rolling image..."
	#mkraw-machine.sh $mach
}
# main_impl
function prepare_machine() {
	DIR=$DIR call_pacstrap

	PKGF=$PKGF packages $TARGET $DIR
	TARGET=$TARGET machine $DIR

	img=/tmp/$(basename $0)-$TARGET.raw
	raw=/mach/machines/$TARGET.raw

	echo "compiling raw image..."
	if [ -z "$CHAIN" ] ; then
		dir2raw $DIR $img
		rm -fr $DIR
	else
		TIP=$CHAIND/$CHAIN/layer/$TARGET/upper
		dir2raw $TIP $img
	fi
	echo "image is '$img'."
	echo "moving to $PWD..."
	mv $img $raw
	echo "image at $(realpath ./$TARGET.raw)"
	echo "Done building $TARGET."
}
# rebuild-machines
function main() {
	SELINUX=0 
	for i in $@ ; do	
		TARGET=$(basename "$i")
		if [[ "$TARGET" == "." ]] ; then
			echo "Usage: $(basename $0) <machine-name (.pkgs shell-script or .pkglist text file in working directory)>, ..."
			return
		fi
		if [ -z "$PKGF" ] ; then
			PKGF=/mach/machines/$TARGET.pkgs
		fi
		if [ -z "$DIR" ] ; then	
			if [ -n "$CHAIN" ] ; then
				echo "DIR not set but CHAIN is set!"
				return
			else
				DIR=/mach/machines/$TARGET
			fi
		fi
		DIR=$DIR TARGET=$TARGET PKGF=$PKGF prepare_machine
	done
#echo $NICKNAME > $TARGET/etc/hostname
	return
#	else
#		for i in *.pkgs; do
#			M=${i/.pkgs}
#			call_pacstrap $M
#			packages $M
#			machine $M
#		done
	if [[ -z "$NOSHA" ]] ; then
		sha256sum *.raw > /root/machines.sums
	fi
	break
}
. mkraw-machine.sh
mkraw_init
main $@
exit
echo "unmounting..."
T=$(mktemp)
for i in $(cakefile | cut -f1 -d=) ; do
	declare -a chain
	chain=($(grep $i cakefile | cut -f2 -d=))
	for i in ${chain[*]} ; do
		find /mach/.chains/$CHAIN_/mounts/$i/bind -name bind -exec umount -R {} \;
	done
done
find /mach/.chains/$CHAIN_/mounts -exec umount -R {} \;
echo "Done."