#!/bin/sh
cgroups=/sys/fs/cgroup
slice="cpu/user.slice"
[[ "x" != x"$1" ]] && slice="$1"
cat $cgroups/$slice/cgroup.procs | clean
