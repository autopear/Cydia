ifndef PKG_TARG
target :=
else
target := $(PKG_TARG)-
endif

all: Cydia

clean:
	rm -f Cydia

Cydia: Cydia.mm UICaboodle/*.mm ../mobilesubstrate/*.h #makefile
	$(target)g++ -march=armv6 -mcpu=arm1176jzf-s -mthumb -I. -I../mobilesubstrate -fobjc-call-cxx-cdtors -g0 -O2 -Wall -Werror -o $@ $(filter %.mm,$^) -framework UIKit -framework IOKit -framework CoreFoundation -framework Foundation -framework CoreGraphics -framework GraphicsServices -framework QuartzCore -framework JavaScriptCore -framework WebCore -framework WebKit -lobjc -lapt-pkg -lpcre -fobjc-exceptions -F"$${PKG_ROOT}"/System/Library/PrivateFrameworks -multiply_defined suppress -lapr-1

sign: Cydia
	CODESIGN_ALLOCATE=$$(which "$(target)codesign_allocate") ldid -Slaunch.xml Cydia

package: sign
	rm -rf _
	mkdir -p _/var/lib/cydia
	
	mkdir -p _/usr/libexec
	svn export Library _/usr/libexec/cydia
	cp -a /apl/tel/dest/iphoneos-arm/coreutils/usr/bin/du _/usr/libexec/cydia
	
	mkdir -p _/System/Library
	svn export LaunchDaemons _/System/Library/LaunchDaemons
	
	mkdir -p _/Applications
	svn export Cydia.app _/Applications/Cydia.app
	cp -a Cydia _/Applications/Cydia.app/Cydia_
	chmod 6755 _/Applications/Cydia.app/Cydia_
	
	mkdir -p _/System/Library/PreferenceBundles
	svn export CydiaSettings.bundle _/System/Library/PreferenceBundles/CydiaSettings.bundle
	
	mkdir -p _/DEBIAN
	echo "$$(cat control)"$$'\nInstalled-Size: '"$$(du -s _ | cut -f 1)" > _/DEBIAN/control
	
	dpkg-deb -Zlzma -b _ $(shell grep ^Package: control | cut -d ' ' -f 2-)_$(shell grep ^Version: control | cut -d ' ' -f 2)_iphoneos-arm.deb

.PHONY: all clean sign
