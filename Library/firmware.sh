#!/bin/bash

version=$(sw_vers -productVersion)

if grep '^Package: firmware$' /var/lib/dpkg/status >/dev/null; then
    cat /var/lib/dpkg/status | while read -r line; do
        if [[ ${line} == 'Package: firmware' ]]; then
            firmware=
        elif [[ ${line} == '' ]]; then
            unset firmware
        elif [[ ${line} == Version:* && "${firmware+@}" ]]; then
            echo "Version: ${version}"
            continue
        fi

        echo "${line}"
    done >/var/lib/dpkg/status_
else
    cat /var/lib/dpkg/status - >/var/lib/dpkg/status_ <<EOF
Package: firmware
Essential: yes
Status: install ok installed
Priority: required
Section: System
Installed-Size: 0
Maintainer: Jay Freeman (saurik) <saurik@saurik.com>
Architecture: darwin-arm
Version: ${version}
Description: almost impressive Apple frameworks
Name: iPhone Firmware

EOF
fi && mv -f /var/lib/dpkg/status{_,}

echo "/." >/var/lib/dpkg/info/firmware.list

if [[ ${version} = 1.0* || ${version} = 1.1.[012] ]]; then
    user=root
else
    user=mobile
fi

if [[ ! -h /User && -d /User ]]; then
    cp -afT /User /var/"${user}"
fi && rm -rf /User && ln -s "/var/${user}" /User
