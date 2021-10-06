#!/bin/sh
. package-definition.sh
function enum_layers() {
	if [ -n "$1" ] ; then
		TARGET=$1
		if [ -f "$1.pkgs" ] ; then
			PKGF=$(realpath $1.pkgs)
		elif [ -f "$1.pkglist" ] ; then
			PKGF=$(realpath $1.pkglist)
		else
			echo "No PKGF for $TARGET"
			return
		fi
	else
		cat <<-EOF
			Usage: $0 <target> 
				where target has a target.pkgs or target.pkglist
EOF
		return
	fi
	if ! [ -f $TARGET.raw ] ; then
		echo "Missing:${TARGET}"
		if [[ "$@" =~ "--strict" ]] ; then
			exit
		fi
	fi
	echo "$TARGET:$(realpath $TARGET.raw)"
	TARGET="$TARGET" PKGF="$PKGF" enum_layers_impl
}
#
function enum_layers_impl() {
	pkgs=$(TARGET=$TARGET get_packages $PKGF)
	#
	declare -a lsu
	lsu=($(load_pkgs $pkgs))
	echo "lsu = ${lsu[@]}" 1>&2
	Underlayers=${lsu[0]}
	Synchronizable=${lsu[1]}
	Updateable=${lsu[2]}
	echo "L:$Underlayers" 1>&2
	echo "S:$Synchronizable" 1>&2
	echo "U:$Updateable" 1>&2
	pacstrap_impl ${lsu[0]} 1>&2
	echo "M:$(getMounts)" 1>&2
	echo "B:$(getBinds)" 1>&2
	echo "P:$(getPacstrap)" 1>&2
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
		if ! [ -f ${name}.raw ] ; then			
			echo "Missing:${name}"
			if [[ "$@" =~ "--strict" ]] ; then
				exit
			fi
		fi
		echo "${name}:$(realpath ${name}.raw)"
		if ! [ -r ${base} ] ; then
			echo "Error: $base not found!"
			return
		fi
		TARGET="${name}" PKGF="${base}" enum_layers_impl
	done
	#
	#if ! [ -d $CHAIND/$CHAIN/mounts/$TARGET/bind/overlay ] ; then
	#	chain $TARGET $CHAINLIST
	#	echo "Directory -> $DIR"
	#	DIR=$CHAIND/$CHAIN/mounts/$TARGET/bind/overlay
	#	dir=$DIR
	#fi
	#for i in $(getBinds) ; do
	#	declare -a line
	#	line=($(echo $i | head -1 | cut -f1,2 -d:))
	#	case ${#line[*]} in
	#		0)
	#			continue
	#		;;
	#		1)
	#			what=${line[0]}
	#			where=$dir/$what
	#		;;
	#		2);&
	#		*)
	#			what=${line[0]}
	#			where=$dir/${line[1]}
	#		;;
	#	esac
	#	mkdirp $where
	#	mount $what $where -o bind,ro 
	#done
	#DIR="$dir" packages_impl
}