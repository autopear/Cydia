#!/bin/bash
set -e

version=$(sw_vers -productVersion)

cat /var/lib/dpkg/status | {

while IFS= read -r line; do
    #echo "#${firmware+@}/${blank+@} ${line}" 1>&2

    if [[ ${line} == '' && "${blank+@}" ]]; then
        continue
    else
        unset blank
    fi

    if [[ ${line} == 'Package: firmware' ]]; then
        firmware=
    elif [[ ${line} == '' ]]; then
        blank=
    fi

    if [[ "${firmware+@}" ]]; then
        if [[ "${blank+@}" ]]; then
            unset firmware
        fi
        continue
    fi

    #echo "${firmware+@}/${blank+@} ${line}" 1>&2
    echo "${line}"
done

#echo "#${firmware+@}/${blank+@} EOF" 1>&2
if ! [[ "${blank+@}" || "${firmware+@}" ]]; then
    echo
fi

cat <<EOF
Package: firmware
Essential: yes
Status: install ok installed
Priority: required
Section: System
Installed-Size: 0
Maintainer: Jay Freeman (saurik) <saurik@saurik.com>
Architecture: iphoneos-arm
Version: ${version}
Description: almost impressive Apple frameworks
Name: iPhone Firmware

EOF

} >/var/lib/dpkg/status_

mv -f /var/lib/dpkg/status{_,}

echo "/." >/var/lib/dpkg/info/firmware.list

if [[ ${version} = 1.0* || ${version} = 1.1.[012] ]]; then
    user=root
else
    user=mobile
fi

if [[ ! -h /User && -d /User ]]; then
    cp -afT /User /var/"${user}"
fi && rm -rf /User && ln -s "/var/${user}" /User
