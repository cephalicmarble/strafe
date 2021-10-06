dd if=/dev/random bs=128 count=1 | tr -dc 'a-zA-Z0-9,.<>?;\!\#:@~*()-=_+][{}' | dd bs=63 count=1 | head -1
