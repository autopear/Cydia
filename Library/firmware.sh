#!/bin/bash
set -e

version=$(sw_vers -productVersion)

cat /var/lib/dpkg/status | while IFS= read -r line; do
    if [[ ${line} == 'Package: firmware' ]]; then
        firmware=
    elif [[ ${line} == '' ]]; then
        unset firmware
    elif [[ "${firmware+@}" ]]; then
        continue
    fi

    echo "${line}"
done >/var/lib/dpkg/status_

cat >>/var/lib/dpkg/status_ <<EOF
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
