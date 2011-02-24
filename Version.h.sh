#!/bin/bash

version=$(./version.sh)

new="#define Cydia_ \"${version}\""
old=$(cat Version.h 2>/dev/null)

if [[ ${old} != ${new} ]]; then
    echo "${new}" >Version.h
fi
