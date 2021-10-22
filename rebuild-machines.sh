#!/bin/sh
echo "$0 $@"
MACHD="/mach/machines"
STRAFD="/mach/.machines"
MLAYER="/mach/.journals"
CHAIND="/mach/.chains"
NICKNAME="$2"
REBUILDBASE=/mach/machines/rebuild
if [[ "$@" =~ "--debug" ]] ; then
	export debugging=1
else
	true
fi
function debug() {
	if [ -n "$debugging" ] ; then
		true
		return
	fi
	false
}
if [ ! -d $REBUILDBASE ] ; then
	mkdir $REBUILDBASE
fi
if [ -z "$DATE" ] ; then
	DATE=$(date +%s)
fi

if [ -z "$1" ] && [ -z "$NICKNAME" ] && [ -z "$SOURCE" ] ; then
	echo "$0 : <MACH.pkgs> $(ls ./*.pkgs)"
	exit
fi
#
function onexit() {
	echo "$1..." 1>&2
	if ! debug ; then
		find /mach/.chains/$CHAIN -name bind -type d -exec umount -R {} \;
		find /mach/.chains/$CHAIN -name mounts -type d -exec umount -R {} \;
		rm -fr /mach/.journals/chains/$CHAIN
	fi
	echo "Done." 1>&2
	exit
}
#
. script-helpers.sh
. package-definition.sh
# cookie idea?
function mkdirp() {
	if ! [ -d "$1" ] ; then 
		echo "creating directory $1..."
		mkdir -p $1
	fi
}
#
function call_pacstrap() {
	echo "Checking definition..."
	#
	pkgs=$(TARGET=$TARGET get_packages $PKGF)
	#
	declare -a lsu
	lsu=($(load_pkgs $pkgs))
	echo "lsu = ${lsu[@]}" 1>&2
	Underlayers=$(echo ${lsu[0]} | tr ',' '  ' | sed -e 's/^\ ?\.\ ?$//')
	Synchronizable=$(echo ${lsu[1]} | tr ',' '  ' | sed -e 's/^\ ?\.\ ?$//')
	Updateable=$(echo ${lsu[2]} | tr ',' ' ' | sed -e 's/^\ ?\.\ ?$//')
	cat << EOF > $REBUILDBASE/$TARGET.sh
#!/bin/sh
export Synchronizable="$Synchronizable"
export Updateable="$Updateable"
export Underlayers="$Underlayers"
EOF
	echo "L:$Underlayers" 1>&2
	echo "S:$Synchronizable" 1>&2
	echo "U:$Updateable" 1>&2
	pacstrap_impl $Underlayers
	echo "M:$(getMounts)" 1>&2
	echo "B:$(getBinds)" 1>&2
	echo "P:$(getPacstrap)" 1>&2
	read -p "continue? [Y/n]" -t 4 N
	if [ -n $N ] && [ "$N" == "n" ] ; then
		exit
	fi
	
	if [ -z "$(getBinds)$(getMounts)" ] ; then
		echo "$PKGF just listed packages."
		JUSTPACKAGES=1
		if [ ! -d $DIR ] ; then
			mkdirp $DIR
		fi
		if [[ ! -r $DIR/usr/lib/os-release ]] && [[ ! -r $DIR/etc/os-release ]] ; then
			echo "Building $TARGET from $PKGF in $DIR with pacstrap..." 1>&2
			if ! debug ; then
				pacstrap -c -M -G $DIR base
			fi
			BOOTSTRAP=1
			#rsync -q /etc/pacman.d/mirrorlist $DIR/etc/pacman.d/mirrorlist
		fi
		if ! debug ; then
			pacman="pacman --root=$DIR --cachedir=/var/cache/pacman/pkg --noconfirm --overwrite=*"
		else
			pacman="lf pacman"
		fi
#		if [ -n "${Synchronizable/.}" ] ; then
#			if ! $pacman -S $Synchronizable ; then
#				false
#				return
#			fi
#		fi
#		if [ -n "${Updateable/.}" ] ; then
#			if ! $pacman -U $Updateable ; then
#				false
#				return
#			fi
#		fi
		DIR="$DIR" packages_impl
		true
		return
	fi
	#
	for i in $(getMounts) ; do
		declare -a line
		line=($(echo $i | head -1 | cut -f1,2 -d:))
		echo "line=${line[@]}" 1>&2
		case ${#line[*]} in
			1)
				name=${line[0]}
				if [[ "$name" =~ "." ]] ; then
					base=$name
					name=$(echo $base | cut -f1 -d.)
				else
					base=$name
					if [ -f "${base}.pkgs" ] ; then
						base=${base}.pkgs
					elif [ -f "${base}.pkglist" ] ; then
						base=${base}.pkglist
					elif [ -f "${base}.raw" ] ; then
						base=${base}.raw
					fi
				fi
			;;
			2);&
			*)
				name=${line[0]} 
				base=${line[1]} # -z -> base is pacstrap or omit
			;;
		esac
		base=$(basename $base)
		name=$(basename $name)

		echo "base-mount=$base name=$name" 1>&2
		# setup dummy directory
		subdir=/tmp/$(basename $0)-$base-$DATE
		if [ "$base" == "none" ] ; then
			ln -s $subdir $DIR
		elif [ ! -f ${base} ] ; then
			echo "Could not find sub-image or non-shell and non-text definition ($line)." 1>&2
			exit
		fi
		# deal with pre-existing
		if [ -n "$FORCE" ] && [ -f ${name}.raw ] ; then
			mv ${name}.raw ${name}.raw.bak
		fi
		if [ -f ${name}.raw ] ; then
			CHAINLIST="${name}:$(realpath ${name}.raw) $CHAINLIST"
		else
			# rebuild
			if [ -f ${base} ] && [ "$(file ${base} | cut -f2 -d:)" == " ASCII text" ] ; then
				echo "building $base base-image from pkglist in $subdir..." 1>&2
				TMPCHAIN=$CHAIN
				unset -v CHAIN
				DIR="$subdir" PKGF="$(realpath ${base})" TARGET="$name" prepare_machine 1>&2 2>&2
				CHAIN=$TMPCHAIN
			elif [ -f $base ] ; then
				echo "building $base base-image from definition in $subdir..." 1>&2
				CHAIN="$CHAIN" DIR="$subdir" PKGF="$(realpath ${base})" TARGET="$name" prepare_machine 1>&2 2>&2
			fi
			# mount
			if [ -f $base ] && [[ "$(file "$base")" =~ "ext4 filesystem data" ]] ; then
				CHAINLIST="$CHAINITEM $CHAINLIST"
			elif [ -f ${name}.raw ] && [[ "$(file "${name}.raw")" =~ "ext4 filesystem data" ]] ; then
				CHAINLIST="$CHAINITEM $CHAINLIST"
			fi			
		fi
		#
		echo "$TARGET - CHAINLIST : $CHAINLIST"
		dir=$CHAIND/$CHAIN/mounts/$name/bind/overlay
	done
	#
	if ! [ -d $CHAIND/$CHAIN/mounts/$TARGET/bind/overlay ] ; then
		chain $TARGET $CHAINLIST
		echo "Directory -> $DIR"
		ln -s $CHAIND/$CHAIN/mounts/$TARGET/bind/overlay $DIR
		if [ -d $DIR/overlay ] ; then
			DIR=$DIR/overlay
		fi
		dir=$DIR
	fi
	for i in $(getBinds) ; do
		declare -a line
		line=($(echo $i | head -1 | cut -f1,2 -d:))
		case ${#line[*]} in
			0)
				continue
			;;
			1)
				what=${line[0]}
				where=$dir/$what
			;;
			2);&
			*)
				what=${line[0]}
				where=$dir/${line[1]}
			;;
		esac
		mkdirp $where
		mount $what $where -o bind,ro 
	done
	DIR="$dir" packages_impl
	if [ 0"$SELINUX" -gt 0 ] ; then 
		echo "Installing software..." 1>&2
		yes y | $pacman -U /usr/src/selinux/*/*.zst --confirm
		$pacman -R sudo-selinux
		$pacman -R openssh-selinux
	fi
	true
}
#
function packages_impl() {
	#true
	#return
	echo "Querying rebuild packages..." 1>&2
	pacman="pacman --root=$DIR --cachedir=/var/cache/pacman/pkg --noconfirm"
	if debug ; then
		pacman="lf pacman"
	fi
	source $REBUILDBASE/$TARGET.sh
	echo "source $REBUILDBASE/$TARGET.sh"
	cat $REBUILDBASE/$TARGET.sh
	echo "pacman=\"$pacman\" pacman_impl"
	Synchronizable="$Synchronizable" Updateable="$Updateable" pacman="$pacman" pacman_impl
	SKIP=$(getSkipped)
	echo "Skipping $SKIP"
	if [ -n "$S" ] ; then
		echo "Installing cached software..." 1>&2
		echo "$pacman --overwrite=* -S $S" 1>&2
		if ! $pacman --overwrite=* -S $S ; then
			echo "Problems synchronizing with pacman." 1>&2
			false
			return
		fi
	fi
	if [ -n "$U" ] ; then
		echo "Installing local software..." 1>&2
		echo "$pacman --overwrite=* -U $U" 1>&2
		if ! $pacman --overwrite=* -U $U ; then
			echo "Problems updating with pacman." 1>&2
			false
			return
		fi
	fi
	true
}
#
function command_not_found_handle() {
	true
	echo "Missing eponymous $1 function!"
	return
}
function call_machine() {
	MACHINEBASE=/usr/src/machine-base
	mach=$DIR
	if [ -z "$mach" ] ; then 
		echo "PANIC! No directory to machine!" 1>&2
		exit
	fi
	for i in system code home ; do 
		if ! [ -d $mach/$i ] ; then mkdirp $mach/$i;  fi
	done
	#if [ "$TARGET" != "base" ] ; then
	#	iecho "Syncing config from base..."
	#	if [ 0"$SELINUX" -gt 0 ] ; then
	#		mkdirp $mach/etc/selinux
	#		cp /etc/selinux/config.nspawn $mach/etc/selinux/config

#		make_and_sync $mach etc/selinux/refpolicy-arch
	#	fi
	#fi
	#scripts
	. machine-functions.sh
	if [ -n "$BOOTSTRAP" ] ; then
		echo "Removing systemd networking stubs..."
		networking
		true
		echo "Avoiding machine functions as bootstrap image."
		return
	fi
	# close on shell definition
	echo "PATH= DIR=\"$mach\" TARGET=\"$TARGET\" PKGF=\"$PKGF\" init_machine"
	DIR="$mach" TARGET="$TARGET" PKGF="$PKGF" init_machine
}
# main_impl
function prepare_machine() {
	if ! DIR="$DIR" TARGET="$TARGET" CHAIN="$CHAIN" PKGF="$PKGF" call_pacstrap ; then		
		echo "Failed to mount machine. Not making raw image."
		onexit pacstrap
	fi	
	if ! TARGET="$TARGET" DIR="$DIR" PKGF="$PKGF" call_machine ; then
		echo "Failed tuning config. Not making raw image."
		onexit machine
	fi
	
	img=/tmp/$(basename $0)-$TARGET.raw
	raw=/mach/machines/$TARGET.raw

	echo "compiling raw image..." 1>&2
	if debug ; then
		echo "${FUNCNAME[0]}"
		return
	fi
	if [ -z "$CHAIN" ] || [ "$JUSTPACKAGES" == 1 ] ; then
		dir2raw $DIR $img 1>&2
		rm -fr $DIR 1>&2
	else
		TIP=$CHAIND/$CHAIN/layer/$TARGET/upper
		dir2raw $TIP $img 1>&2
	fi
	echo "image is '$img'." 1>&2
	echo "moving to $PWD..." 1>&2
	mv $img $raw
	echo "image at $(realpath ./$TARGET.raw)" 1>&2
	echo "Done building $TARGET." 1>&2
	shrink_raw ./$TARGET.raw 1>&2
	CHAINITEM="$TARGET:$(realpath ./$TARGET.raw)"
}
# rebuild-machines
function main() {
	. chain-functions.sh
	CHAIN=$(chainmangle $(basename $0)-$TARGET)
	find /mach/.chains/$CHAIN -name bind   -exec umount -R {} \;
	find /mach/.chains/$CHAIN -name mounts -exec umount -R {} \;
	echo "rebuild-machines.sh#main" 1>&2
	SELINUX=0 
	for i in $@ ; do
		if [[ "$i" =~ '--' ]] ; then
			continue
		fi
		CHAINLIST=
		TARGET=$(basename "$i")
		if [[ "$TARGET" == "." ]] ; then
			echo "Usage: $(basename $0) <machine-name (.pkgs shell-script or .pkglist text file in working directory)>, ..."
			return
		fi
		if [ -z "$PKGF" ] ; then
			PKGF=/mach/machines/$TARGET.pkgs
			if [ ! -r $PKGF ] ; then
				PKGF=/mach/machines/$TARGET.pkglist
				if [ ! -r $PKGF ] ; then
					echo "Cannot find definition for $TARGET."
					exit
				fi
			fi
		fi
		if [ -z "$DIR" ] ; then	
			if is_pkgf $PKGF ; then
				CHAIN="$CHAIN" init_chain
				flattenfiles --cakefile --mountfile 
				DIR=/tmp/$CHAIN
			else
				CHAIN=
				DIR=/tmp/$(basename $0)-$TARGET				
			fi
		fi
		if [[ "$DIR" =~ "^/tmp/.*$" ]] && [ -d $DIR ] ; then
			if ! rmdir $DIR ; then
				rm -fr $DIR
			fi
		elif [ -L $DIR ] ; then
			unlink $DIR
			rm $DIR
		fi

		echo "DIR=\"$DIR\" TARGET=\"$TARGET\" PKGF=\"$PKGF\" CHAIN=\"$CHAIN\" prepare_machine" 1>&2

		DIR="$DIR" TARGET="$TARGET" PKGF="$PKGF" CHAIN="$CHAIN" prepare_machine
	done

	if [[ "$DIR" =~ "^/tmp/.*$" ]] && [ -d $DIR ] ; then
		if ! rmdir $DIR ; then
			rm -fr $DIR
		fi
	elif [ -L $DIR ] ; then
		unlink $DIR
		rm $DIR
	fi

	return
	if [[ -z "$NOSHA" ]] ; then
		sha256sum *.raw > /root/machines.sums
	fi
	break
}
if [ -z "$SOURCE" ] && ([[ $- != *i* ]] || [ -f $MACHD/$1.pkgs ] || [ -f $MACHD/$1.pkglist ]) ; then
	. mkraw-machine.sh
	mkraw_init
	main $@
	onexit unmounting
fi
