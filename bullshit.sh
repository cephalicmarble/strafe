#!/bin/sh
REPO=/home/amsc/containerd
for i in pipe docker containerd stdout ; do
	grep -i $i $REPO -rn > $i.grep
    cat $i.grep | grep -E -v .\*go\:.\* | grep -vi MAILMAP | grep -vi PLUGINS | grep -vi .CONF | grep -vie \*.md | grep -vi NOTICE | grep -vi Vagrantfile | cut -f1 -d: | uniq > $i.nogo
	cat $i.nogo | cut -f2 -d\ | uniq > $i.dirs
done
for i in $(cat stdout.dirs) ; do 
	grep $i pipe.dirs 2>&1 > /dev/null && grep $i docker.dirs 2>&1 > /dev/null && echo $i >> stdout.venn
done
