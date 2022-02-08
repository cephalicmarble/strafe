#!/bin/bash

CONFIGDIR=/usr/src/docker/config

if [ "$1" == "registry" ] ; then
	cp $CONFIGDIR/daemon.json.registry /etc/docker/daemon.json
	if ! systemctl restart docker-registry ; then
		systemctl status docker-registry
		exit
	fi
else
	cp $CONFIGDIR/daemon.json.safe /etc/docker/daemon.json
fi

systemctl restart docker