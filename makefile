sdks := /Developer/Platforms/iPhoneOS.platform/Developer/SDKs
ioss := $(sort $(patsubst $(sdks)/iPhoneOS%.sdk,%,$(wildcard $(sdks)/iPhoneOS*.sdk)))

ios := $(word $(words $(ioss)),$(ioss))
gcc := 4.2

flags := 
link := 

ifeq (o,O) # gzip is actually better
dpkg := /Library/Cydia/bin/dpkg-deb
ifeq ($(wildcard $(dpkg)),$(dpkg))
dpkg := $(dpkg) -zlzma
else
dpkg := dpkg-deb -zbzip2
endif
else
dpkg := dpkg-deb
endif

sdk := $(sdks)/iPhoneOS$(ios).sdk

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
link += -framework SpringBoardServices
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

version := $(shell ./version.sh)

#cycc = cycc -r4.2 -i$(ios) -o$@
gxx := /Developer/Platforms/iPhoneOS.platform/Developer/usr/bin/g++-$(gcc)
cycc = $(gxx) -mthumb -arch armv6 -o $@ -mcpu=arm1176jzf-s -miphoneos-version-min=2.0 -isysroot $(sdk) -idirafter /usr/include -F/Library/Frameworks

all: MobileCydia

clean:
	rm -f MobileCydia

%.o: %.c
	$(cycc) -c -o $@ -x c $<

sysroot:
	@echo "Please read compiling.txt: you do not have a ./sysroot/ folder with the on-device requirements." 1>&2
	@echo 1>&2
	@exit 1

MobileCydia: sysroot MobileCydia.mm UICaboodle/*.h UICaboodle/*.mm SDURLCache/SDURLCache.h SDURLCache/SDURLCache.m iPhonePrivate.h lookup3.o Cytore.hpp
	$(cycc) $(filter %.mm,$^) $(filter %.o,$^) $(foreach m,$(filter %.m,$^),-x objective-c++ $(m)) $(flags) $(link) $(uikit) -DCYDIA_VERSION='"$(version)"'
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
	./control.sh _ >_/DEBIAN/control
	
	find _ -name '*.png' -exec ./pngcrush.sh '{}' ';'
	
	sudo chown -R 0 _
	sudo chgrp -R 0 _
	sudo chmod 6755 _/Applications/Cydia.app/MobileCydia
	
	mkdir -p debs
	ln -sf debs/cydia_$(version)_iphoneos-arm.deb Cydia.deb
	$(dpkg) -b _ Cydia.deb
	@echo "$$(stat -L -f "%z" Cydia.deb) $$(stat -f "%Y" Cydia.deb)"

.PHONY: all clean sign
