#!/bin/sh
PKGS=/mach/machines/browser.pkgs
pushd /mach/machines
pushd /usr/src/google-chrome/
git pull
GITVER=$(git log -1 | grep pkg: | cut -f2 -dv)
PKGVER=$(ls -t *.zst | head -1 | cut -f3 -d-)
echo "git:$GITVER"
echo "pkg:$PKGVER"
if [ "$GITVER" == "$PKGVER" ] ; then
	exit 1
fi
if ! su amsc -c "makepkg -s" ; then
	exit 1
fi
cp $PKGS{,.bak}
name=$(find $(pwd) -newer $(pwd)/PKGBUILD -name \*.zst)
sed -i -e "s/google-chrome[^/]*\\.zst/$(basename $name)/" $PKGS
popd
strafe rebuild browser
popd
