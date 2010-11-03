ifeq (o,O)
ios := 2.0
gcc := 4.0
else
ios := 3.2
gcc := 4.2
endif

flags := 
link := 

#dpkg := /Library/Cydia/bin/dpkg-deb -Zlzma
dpkg := dpkg-deb

sdk := /Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS$(ios).sdk

flags += -F$(sdk)/System/Library/PrivateFrameworks
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
link += -framework WebCore
link += -framework WebKit

link += -lapr-1
link += -lapt-pkg
link += -lpcre

link += -multiply_defined suppress

uikit := 
uikit += -framework UIKit

backrow := 
backrow += -FAppleTV -framework BackRow -framework AppleTV

#cycc = cycc -r4.2 -i$(ios) -o$@
gxx := /Developer/Platforms/iPhoneOS.platform/Developer/usr/bin/g++-$(gcc)
cycc = $(gxx) -arch armv6 -o $@ -mcpu=arm1176jzf-s -miphoneos-version-min=$(ios) -isysroot $(sdk) -idirafter /usr/include -F/Library/Frameworks

all: MobileCydia

clean:
	rm -f MobileCydia

MobileCydia: MobileCydia.mm UICaboodle/*.h UICaboodle/*.mm iPhonePrivate.h
	$(cycc) $(filter %.mm,$^) $(flags) $(link) $(uikit)
	ldid -Slaunch.xml $@ || { rm -f $@ && false; }

CydiaAppliance: CydiaAppliance.mm
	$(cycc) $(filter %.mm,$^) $(flags) -bundle $(link) $(backrow)

package: MobileCydia
	sudo rm -rf _
	mkdir -p _/var/lib/cydia
	
	mkdir -p _/usr/libexec
	cp -a Library _/usr/libexec/cydia
	cp -a sysroot/usr/bin/du _/usr/libexec/cydia
	
	mkdir -p _/System/Library
	cp -a LaunchDaemons _/System/Library/LaunchDaemons
	
	mkdir -p _/Applications
	cp -a MobileCydia.app _/Applications/Cydia.app
	cp -a MobileCydia _/Applications/Cydia.app/MobileCydia
	
	#mkdir -p _/Applications/Lowtide.app/Appliances
	#cp -a Cydia.frappliance _/Applications/Lowtide.app/Appliances
	#cp -a CydiaAppliance _/Applications/Lowtide.app/Appliances/Cydia.frappliance
	
	mkdir -p _/System/Library/PreferenceBundles
	cp -a CydiaSettings.bundle _/System/Library/PreferenceBundles/CydiaSettings.bundle
	
	mkdir -p _/DEBIAN
	echo "$$(cat control)"$$'\nInstalled-Size: '"$$(du -s _ | cut -f 1)" > _/DEBIAN/control
	
	sudo chown -R 0 _
	sudo chgrp -R 0 _
	sudo chmod 6755 _/Applications/Cydia.app/MobileCydia
	
	$(dpkg) -b _ $(shell grep ^Package: control | cut -d ' ' -f 2-)_$(shell grep ^Version: control | cut -d ' ' -f 2)_iphoneos-arm.deb

.PHONY: all clean sign
