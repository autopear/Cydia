#!/usr/bin/env bash

if [[ ${BASH_VERSION} != 4* ]]; then
    echo "bash 4.0 required" 1>&2
    exit 1
fi

set -o pipefail
set -e

shopt -s extglob
shopt -s nullglob

for command in unlzma wget; do
    if ! which "${command}" &>/dev/null; then
        echo "Cannot run \`${command}\`. Please read compiling.txt." 1>&2
        exit 1
    fi
done

if tar --help | grep bsdtar &>/dev/null; then
    echo "Running \`tar\` is bsdtar :(. Please read compiling.txt." 1>&2
    exit 1
fi

rm -rf sysroot
mkdir sysroot
cd sysroot

repository=http://apt.saurik.com/
distribution=tangelo
component=main
architecture=iphoneos-arm

declare -A dpkgz
dpkgz[gz]=gunzip
dpkgz[lzma]=unlzma

function extract() {
    package=$1
    url=$2

    wget -O "${package}.deb" "${url}"
    for z in lzma gz; do
        compressed=data.tar.${z}

        if ar -x "${package}.deb" "${compressed}" 2>/dev/null; then
            ${dpkgz[${z}]} "${compressed}"
            break
        fi
    done

    if ! [[ -e data.tar ]]; then
        echo "unable to extract package" 1>&2
        exit 1
    fi

    ls -la data.tar
    tar -xf ./data.tar
    rm -f data.tar
}

wget -qO- "${repository}dists/${distribution}/${component}/binary-${architecture}/Packages.bz2" | bzcat | {
    regex='^([^ \t]*): *(.*)'
    declare -A fields

    while IFS= read -r line; do
        if [[ ${line} == '' ]]; then
            package=${fields[package]}
            if [[ ${package} == *(apr|apr-lib|apt7|apt7-lib|coreutils|mobilesubstrate|pcre) ]]; then
                filename=${fields[filename]}
                extract "${package}" "${repository}${filename}"
            fi

            unset fields
            declare -A fields
        elif [[ ${line} =~ ${regex} ]]; then
            name=${BASH_REMATCH[1],,}
            value=${BASH_REMATCH[2]}
            fields[${name}]=${value}
        fi
    done
}

rm -f *.deb

if substrate=$(readlink usr/include/substrate.h); then
    if [[ ${substrate} == /* ]]; then
        ln -sf "../..${substrate}" usr/include/substrate.h
    fi
fi

mkdir -p usr/include
cd usr/include

mkdir CoreFoundation
wget -O CoreFoundation/CFBundlePriv.h "http://www.opensource.apple.com/source/CF/CF-550/CFBundlePriv.h?txt"
wget -O CoreFoundation/CFPriv.h "http://www.opensource.apple.com/source/CF/CF-550/CFPriv.h?txt"
wget -O CoreFoundation/CFUniChar.h "http://www.opensource.apple.com/source/CF/CF-550/CFUniChar.h?txt"

if true; then
    mkdir -p WebCore
    wget -O WebCore/WebCoreThread.h 'http://www.opensource.apple.com/source/WebCore/WebCore-658.28/wak/WebCoreThread.h?txt'
else
    wget -O WebCore.tgz http://www.opensource.apple.com/tarballs/WebCore/WebCore-658.28.tar.gz
    tar -zx --transform 's@^[^/]*/@WebCore.d/@' -f WebCore.tgz

    mkdir WebCore
    cp -a WebCore.d/{*,rendering/style,platform/graphics/transforms}/*.h WebCore
    cp -a WebCore.d/platform/{animation,graphics,network,text}/*.h WebCore
    cp -a WebCore.d/{accessibility,platform{,/{graphics,network,text}}}/{cf,mac,iphone}/*.h WebCore
    cp -a WebCore.d/bridge/objc/*.h WebCore

    wget -O JavaScriptCore.tgz http://www.opensource.apple.com/tarballs/JavaScriptCore/JavaScriptCore-554.1.tar.gz
    #tar -zx --transform 's@^[^/]*/API/@JavaScriptCore/@' -f JavaScriptCore.tgz $(tar -ztf JavaScriptCore.tgz | grep '/API/[^/]*.h$')
    tar -zx \
        --transform 's@^[^/]*/@@' \
        --transform 's@^icu/@@' \
    -f JavaScriptCore.tgz $(tar -ztf JavaScriptCore.tgz | sed -e '
        /\/icu\/unicode\/.*\.h$/ p;
        /\/profiler\/.*\.h$/ p;
        /\/runtime\/.*\.h$/ p;
        /\/wtf\/.*\.h$/ p;
        d;
    ')
fi

for framework in ApplicationServices CoreServices IOKit IOSurface JavaScriptCore WebKit; do
    ln -s /System/Library/Frameworks/"${framework}".framework/Headers "${framework}"
done

for framework in /System/Library/Frameworks/CoreServices.framework/Frameworks/*.framework; do
    name=${framework}
    name=${name%.framework}
    name=${name##*/}
    ln -s "${framework}/Headers" "${name}"
done

mkdir -p Cocoa
cat >Cocoa/Cocoa.h <<EOF
#define NSImage UIImage
#define NSView UIView
#define NSWindow UIWindow

#define NSPoint CGPoint
#define NSRect CGRect

#define NSPasteboard UIPasteboard
#define NSSelectionAffinity int
@protocol NSUserInterfaceValidations;
EOF

mkdir -p GraphicsServices
cat >GraphicsServices/GraphicsServices.h <<EOF
typedef struct __GSEvent *GSEventRef;
typedef struct __GSFont *GSFontRef;
EOF
