#!/bin/sh
DOG=./watchdog
touch $DOG
function onexit() { rm $DOG; }
for c in EXIT KILL QUIT TERM ; do
	trap onexit $c
done
echo php | (nspawn.sh $DOG ide-php-7.4.14)
