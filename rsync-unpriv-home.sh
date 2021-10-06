#!/bin/sh
MACHHOME=/mach/machines/email/home/
MACHUSER=dumb
function home() {
	case $1 in
		("amsc")
			echo /home/amsc;;
		(*)
			echo "I know what you did last summer!"
			exit 1;
	esac
}
declare -a HOMESUBDIRS
HOMESUBDIRS=(
	'Desktop',
	'.config',
	'.local'
)
USR=$USER
if [[ -n $SUDO_USER ]] ; then
	USR=$SUDO_USER
fi
if [[ $SUDO_USER == 'root' ]] ; then
	echo "Running as root!"
	exit
fi
for i in ${HOMESUBDIRS[*]} ; do 
	if [[ ! -d /home/$MACHUSER/$i/ ]] ; then
		rsync -vlr $(home $USR)/$i /home/$MACHUSER/
	else
		rsync -vlr $(home $USR)/$i/ /home/$MACHUSER/
	fi
done
# rebuild user/group database guest-side
# build in home directories guest-side
# shuffle files host-side