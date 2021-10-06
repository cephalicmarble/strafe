#!/bin/sh
cryptsetup open --type luks /dev/mapper/arch-code code --key-file ~amsc/dev-fedora-code-key-file.bin 
mount /dev/mapper/code /code -o acl,nodev,nosuid
