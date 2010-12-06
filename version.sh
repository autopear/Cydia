#!/bin/bash

if [[ $# -eq 0 ]]; then
    flags=(--dirty="+")
else
    flags=("$@")
fi

echo -n "$(git describe --tags --match="v*" "${flags[@]}" | sed -e 's@-\([^-]*\)-\([^-]*\)$@+\1.\2@;s@^v@@')"
grep '#define ForRelease 0' MobileCydia.mm &>/dev/null && echo -n '~srk'
echo
