#!/bin/bash
echo -n "$(git describe --tags --dirty="+" --match="v*" | sed -e 's@-\([^-]*\)-\([^-]*\)$@+\1.\2@;s@^v@@')"
grep '#define ForRelease 0' MobileCydia.mm &>/dev/null && echo -n '~srk'
echo
