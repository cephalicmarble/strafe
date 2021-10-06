#!/bin/sh
if [[ -f "$1" ]] ; then
	LINE=$(stat "$1" --printf=%n/%y/%s)/$(sha256sum "$1")
	if [[ -w "$2" ]] ; then
		echo $LINE >> "$2"
	else
		echo $LINE
	fi
	exit
fi
if [[ ! -d "$1" ]] ; then
	echo "ddigest-sign.sh <dir> [arguments-to-find] : wrap directory digest file with signature."
	exit
fi
DIR=$(mktemp -u 'ddigestXXXX')
if [[ ! -d "$DIR" ]] ; then mkdir $DIR ; else echo "$DIR exists!"; exit; fi
FILE="$DIR/digest"
touch $FILE
HERE=$(realpath $0)
WHERE="$1"
shift
find "$WHERE" -type f $@ -exec $HERE {} $FILE \;
gpg --detach-sign $FILE
TGZ=`echo $(basename "$WHERE")-$(date +%Y-%m-%H-%M-%S).tar.gz`
tar -zcf "$TGZ" "$DIR"
echo $TGZ
rm $FILE
rm $FILE.sig
rmdir $DIR
