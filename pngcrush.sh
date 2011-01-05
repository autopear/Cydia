#!/bin/bash

png=$1
steps=()

function step() {
    "$@"
    mv -f {_,}_.png
    steps+=($(stat -f "%z" _.png))
}

pngcrush=/Developer/Platforms/iPhoneOS.platform/Developer/usr/bin/pngcrush

grep CgBI "${png}" &>/dev/null && exit 0

step cp -fa "${png}" __.png

#step "${pngcrush}" -q -rem alla -reduce -brute -iphone {,_}_.png

#step "${pngcrush}" -q -rem alla -reduce -brute {,_}_.png
#step pincrush {,_}_.png

step "${pngcrush}" -q -rem alla -reduce -iphone {,_}_.png

#"${pngcrush}" -q -rem alla -reduce -brute -iphone "${png}" 1.png
#"${pngcrush}" -q -iphone _.png 2.png
#ls -la 1.png 2.png

mv -f _.png "${png}"

echo -n "${png##*/} "
for ((i = 0; i != ${#steps[@]}; ++i)); do
    if [[ $i != 0 ]]; then
        echo -n " "
    fi

    echo -n "${steps[i]}"
done

printf $' %.0f%%\n' "$((steps[${#steps[@]}-1] * 100 / steps[0]))"
