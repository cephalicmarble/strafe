#!/bin/sh
PHPVER="$1"
if [ -z "$PHPVER" ] ; then
	exit
fi
OUTPUT=ide-php-$PHPVER.pkgs
ls $OUTPUT && mv $OUTPUT $OUTPUT.bak
# other stuff
cat ide.pkgs | grep -E -v ^php > $OUTPUT 
# php modules from cache
for i in $(cat ide.pkgs | grep -E ^php | sed -re "s/php\$/php-$PHPVER/g" | sed -re "s/php-([[:alpha:]]+).*/php-\\1-$PHPVER/g"); do 
	ls /var/cache/pacman/pkg/$i* | P=1 clean | RP=1 readloop >> $OUTPUT
done
# php modules from list
PHPPKGS=$(mktemp -u --tmpdir=/tmp phppkgsXXXX)
cat ide.pkgs | grep -E ^php > $PHPPKGS
# fill in
for i in $(cat $PHPPKGS | grep -E ^php | sed -re 's/-[-.0-9]+-x86.*$//g') ; do
	if ! grep $i $OUTPUT ; then
		echo $i-$PHPVER >> $OUTPUT
	fi
done
