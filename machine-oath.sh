#!/bin/sh
function genpwd() {
	tr -cd 0-9A-Za-z_ < /dev/urandom | fold -w 16 | head -5
}
function oathfile() {
	F=$MACHINE/etc/oath/users.oath
	if [[ ! -d $(dirname $F) ]] ; then mkdir -p $(dirname $F) ; fi
	touch $F || (echo "$F not writable";exit)
	echo $F
}
function oath() {
	user=$1
	mach=$2
	randomfile=$(mktemp -u)
	HEX=$(genpwd | md5sum | cut -f1 -d- )
	BASE32=$(oathtool -v | grep Base32 | cut -f3 -d\ )
	echo "otpauth:\/\/totp\/$user\@$mach.lan.local\?secret=$BASE32/" | qrencode -t SVG -s 16 | display - 
	read -N 1 -p "Write to file [y/n] ? " writep
	echo
	if [[ $writep == "y" ]] ; then
		cat $randomfile | sed -re "s/(.*)/HOTP\/T30\/6	$user	-	$HEX/" >> $(oathfile $mach)
	fi
	rm $randomfile
}
mach=$1
MACHINE=/mach/machines/$mach
if [[ $mach == 'host' ]] ; then
	MACHINE=
else
	if [[ ! -d $MACHINE ]] ; then
		mkdirp=n
		read -N 1 -i "n" -t 2 -p "Creating machine $MACHINE [y/n]? " mkdirp
		echo
		if [[ $mkdirp =~ "y" ]] ; then
			mkdir -p $MACHINE || (echo "Couldn't mkdir $MACHINE";exit)
		fi
	fi
fi
shift #word
declare -a users
F=$(mktemp -u)
echo "$@" >$F
read -a users < $F #word
unlink $F
shift ${#users[@]}
for user in ${users[*]} ; do
	if grep -E "^$user" $(oathfile $MACHINE) ; then
		echo "$user already listed by $MACHINE users.oath."
		exit
	fi
	catoathp=n
	read -N 1 -p "Adding QR Code for $user in $MACHINE...[y/n]? " catoathp
	echo
	if [[ $catoathp == "y" ]] ; then
		oath $user $MACHINE
	fi
done
echo
