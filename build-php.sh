#!/bin/sh
if [ -z "$PKGVER" ] ; then
	pushd /usr/src/php-src
	git branch -a | less
	PKGVER=8.0.9
	read -i$PKGVER -t10 PKGVER
	popd
fi
pushd /usr/src/php
cat PKGBUILD.in | sed -e "s/%PKGVER%/$PKGVER/" > PKGBUILD
makepkg $@
popd
