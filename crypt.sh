#!/bin/sh
sudo cryptsetup open /dev/sdc5 crypt
sudo mount /dev/mapper/crypt /crypt
