#!/bin/sh
PKGS=/mach/machines/browser.pkgs
pushd /mach/machines
pushd /usr/src/google-chrome/
git pull
GITVER=$(git log -1 | tail -1 | cut -f2 -dv)
PKGVER=$(ls -t *.zst | head -1 | cut -f3 -d-)
if [ $GITVER == $PKGVER ] ; then
	exit 1
fi
su amsc -c "makepkg -s"
cp $PKGS{,.bak}
sed -i -e "s/\/usr\/src\/google-chrome.*\.zst/$(find $(pwd) -newer $(pwd)/PKGBUILD -name \*.zst)/" $PKGS
popd
strafe rebuild browser
popd
