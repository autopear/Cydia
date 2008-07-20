#!/bin/bash

for dir in \
    /Applications \
    /Library/Ringtones \
    /Library/Wallpaper \
    /System/Library/Fonts \
    /System/Library/TextInput \
    /usr/share
do
    . /usr/libexec/cydia/move.sh "$@" "${dir}"
done
