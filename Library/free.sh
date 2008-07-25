#!/bin/bash

for dir in \
    /Applications \
    /Library/Wallpaper \
    /Library/Ringtones \
    /usr/include \
    /usr/libexec \
    /usr/share \
; do
    . /usr/libexec/cydia/move.sh "$@" "${dir}"
done

sync
