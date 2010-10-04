ios := 3.2

flags := 
link := 

#dpkg := /Library/Cydia/bin/dpkg-deb -Zlzma
dpkg := dpkg-deb

flags += -F/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS$(ios).sdk/System/Library/PrivateFrameworks
flags += -I. -isystem sysroot/usr/include -Lsysroot/usr/lib
flags += -Wall -Werror -Wno-deprecated-declarations
flags += -fmessage-length=0
flags += -g0 -O2
flags += -fobjc-call-cxx-cdtors -fobjc-exceptions

link += -framework CoreFoundation
link += -framework CoreGraphics
link += -framework Foundation
link += -framework GraphicsServices
link += -framework IOKit
link += -framework JavaScriptCore
link += -framework QuartzCore
link += -framework SystemConfiguration
link += -framework UIKit
link += -framework WebCore
link += -framework WebKit

link += -lapr-1
link += -lapt-pkg
link += -lpcre

link += -multiply_defined suppress

all: Cydia

clean:
	rm -f Cydia

Cydia: Cydia.mm Reachability.mm UICaboodle/*.mm
	cycc -r4.2 -i$(ios) -o$@ -- $(filter %.mm,$^) $(flags) $(link)

package: Cydia
	sudo rm -rf _
	mkdir -p _/var/lib/cydia
	
	mkdir -p _/usr/libexec
	cp -a Library _/usr/libexec/cydia
	cp -a sysroot/usr/bin/du _/usr/libexec/cydia
	
	mkdir -p _/System/Library
	cp -a LaunchDaemons _/System/Library/LaunchDaemons
	
	mkdir -p _/Applications
	cp -a Cydia.app _/Applications/Cydia.app
	cp -a Cydia _/Applications/Cydia.app/Cydia_
	
	mkdir -p _/System/Library/PreferenceBundles
	cp -a CydiaSettings.bundle _/System/Library/PreferenceBundles/CydiaSettings.bundle
	
	mkdir -p _/DEBIAN
	echo "$$(cat control)"$$'\nInstalled-Size: '"$$(du -s _ | cut -f 1)" > _/DEBIAN/control
	
	sudo chown -R 0 _
	sudo chgrp -R 0 _
	sudo chmod 6755 _/Applications/Cydia.app/Cydia_
	
	$(dpkg) -b _ $(shell grep ^Package: control | cut -d ' ' -f 2-)_$(shell grep ^Version: control | cut -d ' ' -f 2)_iphoneos-arm.deb

.PHONY: all clean sign
