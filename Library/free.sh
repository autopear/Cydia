#!/bin/bash

for dir in \
    /usr/share \
    /Applications \
    /Library/Wallpaper \
    /Library/Ringtones \
; do
    . /usr/libexec/cydia/move.sh "$@" "${dir}"
done
