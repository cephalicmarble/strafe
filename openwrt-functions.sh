#!/bin/bash

catfile() {
	scp $1 root@$WRT_IP:$2 || (
		echo -n "echo \"" >> $FILE
		cat $1 >> $FILE
		echo -n "\";"
	)
}

importfile() {
	echo -n "uci import < $1 ; " >> $FILE
}

snd_section() {
	catfile $1 $2
	importfile $2
}

path_c() {
	echo -n "$(echo ${1/.openwrt} | sed -E 's/-/\//g')"
}

snd_path() {
	catfile $1 $(path_c $2)
}

rcv_path_c() {
	echo -n "cat $(path_c $1) | tee $1 | nc $RCV_IP $NC_PORT"
}

rcv_section_c() {
	echo -n "rm $1 ; uci export $1 | tee $1 | nc $RCV_IP $NC_PORT"
}

fetchcopy() {
	nc -rl $NC_PORT | tee > $1 &
	$SSH_CMD "$(rcv_path_c $2)"
}

exportconfig() {
	nc -rl $NC_PORT | tee > $1 &
	$SSH_CMD "$(rcv_section_c $2)"
}

