#!/bin/sh
function get_packages() {
	if ! is_pkgf $1 ; then
		if [[ "$(file $1)" =~ "ASCII text" ]] ; then
			echo "text list..." 1>&2
			pkgs=$(cat $1)
		fi
	else
		echo "shell definition..." 1>&2
		source $1
		pkgs=$($TARGET packages)
	fi
	echo $pkgs
}
#
function is_pkgf() {
	pkgf="$1"
	func="$2"
	if ! [ -f "$pkgf" ] ; then
		false
		return
	fi
	text="$(cat $pkgf)" 
	if [[ "$(file ${pkgf})" =~ "shell script" ]] && [[ "$text" =~ "function $func" ]] ; then
		true
		return
	fi
	false
}
#
#	pkgf="$1"
#	func="$2"
#	echo "load_pkgf $1 $2"
#	if ! is_pkgf $pkgf && [[ "$(file $pkgf)" =~ "ASCII text" ]] ; then
#		echo "text list..."
#		pkgs=$(cat $pkgf)
#	else
#		echo "shell definition..."
#		source $pkgf
#		pkgs=$($func packages)
#	fi
#
function load_pkgs() {
	L=
	S=
	U=
	for i in $@ ; do
		echo "adding $i..." 1>&2
		if [[ "$i" =~ ":" ]] ; then
			if [ -z "$L" ] ; then
				L="$i"
			else
				L="$L $i"
			fi
		elif [ "." == "$(dirname $i)" ] ; then
			if [ -z "$S" ] ; then
				S="$i"
			else
				S="$S $i"
			fi
		else
			if [ -z "$U" ] ; then
				U="$i"
			else
				U="$U $i"
			fi
		fi
	done
	echo "$(echo $L | tr ' ' ',' | sed -re 's/^$/\./') $(echo $S | tr ' ' ',' | sed -re 's/^$/\./') $(echo $U | tr ' ' ',' | sed -re 's/^$/\./')"
}
#
function getUnderlayers() { # $(getUnderlayers)$(getUpdateable)$(getSynchronizable)
	echo "$L"
}
#
function getUpdateable() {
	echo "$U"
}
#
function getSynchronizable() {
	echo "$S"
}
#
#HEREIAM rewrite these
#
function pacstrap_impl() {
	PACS=
	MOUNTS=
	BINDS=
	echo "pacstrap_impl $@" 1>&2
	for i in $(echo $@ | tr ',' ' ') ; do
		p=$(echo $i | cut -f1 -d:)
		w=$(echo $i | cut -f2,3,4 -d: --output-delimiter=:)
		echo "pacstrap_impl p=$p, w=$w" 1>&2
		if [ "$p" == "b" ] ; then
			# binds made available into our overlay mount
			if [ -z "$BINDS" ] ; then
				BINDS="$w"
			else
				BINDS="$BINDS $w"
			fi
		elif [ "$p" == "" ] ; then
			#lower raw mount / pkgf
			if [ -z "$MOUNTS" ] ; then
				MOUNTS="$w"
			else
				echo "PANIC! More than one base mount!" 1>&2
				exit
			fi
		elif [ "$p" == "p" ] ; then
			#pacstrap packages
			PACS=$(recurse_pacstrap $(echo $w | tr ',' ' '))
		fi
	done
	echo "$(echo $BINDS | tr ' ' ',' | sed -re 's/^$/\./' | grep -vE '^\.$' ) $(echo $MOUNTS | tr ' ' ',' | sed -re 's/^$/\./'  | grep -vE '^\.$') $(echo $PACS | tr ' ' ',' | sed -re 's/^$/\./' | grep -vE '^\.$')"
}
function recurse_pacstrap() {
	echo "recurse_pacstrap $@" 1>&2
	for i in $@ ; do 
		if [ "." == $i ] ; then
			continue
		elif  [ "$(pacman -Q $i 2>/dev/null | cut -f1 -d\ )" == "$i" ] ; then 
			pacs="$pacs $i"
			continue
		fi
		echo "recurse_pacstrap i=$i" 1>&2
		if [ -f $i ] ; then
			if [ "$(basename $i .pkglist).pkglist" == "$i" ] ; then
				pacs="$pacs $(cat $i)"
			elif is_pkgf $i $(basename $i .pkgs) ; then
				pacs="$pacs $(recurse_pacstrap_impl $i $(basename $i .pkgs))"
			fi
		fi
	done
	echo $pacs
}
function recurse_pacstrap_impl() {
	rpkgf=$1
	rfunc=$2
	source $rpkgf
	manifest=$($rfunc packages)
	declare -a manif
	manif=($(load_pkgs $manifest))
	echo "recurse_pacstrap_impl manif=$manif" 1>&2
	pacs="$pacs ${manif[1]} ${manif[2]}"
	declare -a rpacs
	rpacs=($(pacstrap_impl ${manif[0]}))
	echo "recurse_pacstrap_impl rpacs=${rpacs[@]}" 1>&2
	if [ -n ${rpacs[2]} ] ; then
		pacs="$(pacs=$pacs recurse_pacstrap $(echo ${rpacs[2]} | tr ',' ' '))"
	fi
	echo "recurse_pacstrap_impl pacs=$pacs" 1>&2
	echo $pacs | tr ',' ' ' | sed -re 's/\ \.\ /\ /'
}
function pacman_impl() { # Synchronizable= Updateable=
	echo "Querying packdef packages..." 1>&2
	SKIP=
	echo "pkgs=$($pacman -Q | cut -f1 -d\ )"
	pkgs=$($pacman -Q | cut -f1 -d\ )
	echo "U -> $Updateable"
	U2=
	for i in $Updateable ; do
		if [ "$i" == "." ] || [ "x$(echo $i | sed -e 's/\ +//')" == "x" ] ; then
			continue
		fi
		if ! [[ $i =~ ".zst" ]] ; then
			i="$i-x86_64.pkg.tar.zst"
		fi
		pkg=$(echo $(basename $i) | sed -re 's/-[0-9]+.*$//' 2>/dev/null)
		A=($(basename "${i/-x86_64.pkg.tar.zst}" | tr '-' ' '))
		pkgver=${A[${#A}]}
		if [[ "$pkgs" =~ "$pkg" ]] &&
			[ "$($pacman -Q "$pkg" | cut -f2 -d\ )" == "$pkgver" ] ; then
			if [ -z "$FWORK" ] ; then
				SKIP="$SKIP $PKG"
				echo "SKipping $PKG"
				continue
			fi
		fi
		U2="$U2 $i"
	done
	U="$U2"
	echo "S -> $Synchronizable"
	S2=
	for i in $Synchronizable ; do
		if [ "$i" == "." ] || [ "x$(echo $i | sed -e 's/\ +//')" == "x" ] ; then
			continue
		fi
		pkg=$(echo $(basename $i) | sed -re 's/-[0-9]+.*$//' 2>/dev/null)
		mver=$(pacman -Q $i | cut -f2 -d\ )
		pver=$($pacman -Q $i | cut -f2 -d\ )
		if [[ "$pkgs" =~ "$i" ]] &&
			[ "$mver" == "$pver" ] ; then
			if [ -z "$FWORK" ] ; then
				echo "Skipping $PKG"
				SKIP="$SKIP $PKG"
				continue
			fi
		fi
		S2="$S2 $i"
	done
	S="$S2"
}
#
function getSkipped() {
	echo "$SKIP"
}
function getBinds() {
	echo "$BINDS"
}
function getMounts() {
	echo "$MOUNTS"
}
function getPacstrap() {
	echo "$PACS"
}
