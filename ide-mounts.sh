#!/bin/sh
mount /code/JetBrains/system /system -o bind
pushd $(pwd)
cd ~ide
if [[ -z "$@" ]] ; then
	su ide
else
	su ide -c "$@"
fi
popd
umount /system
