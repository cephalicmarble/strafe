#!/bin/sh
CLASSLINES=$(grep -E '^\s*class\s+[_a-zA-Z0-9]+.*$' . -rn)
CLASSES=$(grep -E '^\s*class\s+[_a-zA-Z0-9]+.*$' . -r | cut -f2 -d: | sed -re 's/class\s+([_a-zA-Z0-9]+)\s+.*$/\1/')
CLASSFILES=$(grep -E '^\s*class\s+[_a-zA-Z0-9]+.*$' . -rn | cut -f1 -d:)
#echo CLASSLINES
#echo $CLASSLINES
#echo CLASSES
#echo $CLASSES
#echo CLASSFILES
#echo $CLASSFILES
for c in $CLASSES ; do
	grep -E "^(\\s*(public|private|protected))?\\s*function\\s+$c\\s*\\(.*\$" $CLASSFILES -rn;
done
