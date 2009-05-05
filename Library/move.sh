#!/bin/bash

shopt -s extglob nullglob

if [[ ${1:0:1} == - ]]; then
    v=$1
    shift 1
else
    v=
fi

function df_() {
    free=$(df -B1 "$1")
    free=${free% *%*}
    free=${free%%*( )}
    free=${free##* }
    echo "${free}"
}

function mv_() {
    src=$1

    mkdir -p /var/stash
    dst=$(mktemp -d /var/stash/"${src##*/}".XXXXXX)

    if [[ -e ${src} ]]; then
        chmod --reference="${src}" "${dst}"
        chown --reference="${src}" "${dst}"

        cp -aT $v "${src}" "${dst}" || {
            rm -rf "${dst}"
            exit 1
        }

        rm -rf $v "${src}"
    else
        chmod 775 "${dst}"
        chown root.admin "${dst}"
    fi

    ln -s "${dst}" "${src}"
}

function shift_() {
    dir=${1%/}

    if [[ -d ${dir} && ! -h ${dir} ]]; then
        used=$(/usr/libexec/cydia/du -bs "${dir}")
        used=${used%%$'\t'*}
        free=$(df_ /var)

        if [[ $((used + 524288)) -lt ${free} ]]; then
            mv_ "${dir}"
        fi
    elif [[ ! -e ${dir} ]]; then
        rm -f "${dir}"
        mv_ "${dir}"
    fi
}

shift_ "$@"
