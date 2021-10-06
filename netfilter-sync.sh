#!/bin/sh

. /usr/local/scripts/bridge.sh
setup
work

sudo su -c 'rsync -lr /usr/src/netfilter/*.rules /etc/netfilter/; rsync -lr /usr/src/netfilter/*.chains /etc/netfilter/; nft flush ruleset; nft -f - < /etc/nftables.conf'
