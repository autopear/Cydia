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
flags += -fobjc-exceptions
flags += -fno-guess-branch-probability
flags += -fvisibility=hidden

xflags :=
xflags += -fobjc-call-cxx-cdtors
xflags += -fvisibility-inlines-hidden

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
cycc = $(gxx) -mthumb -arch armv6 -o $@ -mcpu=arm1176jzf-s -miphoneos-version-min=2.0 -isysroot $(sdk) -idirafter /usr/include -F{sysroot,}/Library/Frameworks

flags += -DCYDIA_VERSION='"$(version)"'

dirs := Menes CyteKit Cydia SDURLCache

code := $(foreach dir,$(dirs),$(wildcard $(foreach ext,h hpp c cpp m mm,$(dir)/*.$(ext))))
code := $(filter-out SDURLCache/SDURLCacheTests.m,$(code))
code += MobileCydia.mm iPhonePrivate.h Cytore.hpp lookup3.c

source := $(filter %.m,$(code)) $(filter %.mm,$(code))
source += $(filter %.c,$(code)) $(filter %.cpp,$(code))
header := $(filter %.h,$(code)) $(filter %.hpp,$(code))

object := $(source)
object := $(object:.c=.o)
object := $(object:.cpp=.o)
object := $(object:.m=.o)
object := $(object:.mm=.o)
object := $(object:%=Objects/%)

all: MobileCydia

clean:
	rm -f MobileCydia
	rm -rf Objects/

Objects/%.o: %.c $(header)
	@mkdir -p $(dir $@)
	@echo "[cycc] $<"
	@$(cycc) -c -o $@ -x c $<

Objects/%.o: %.m $(header)
	@mkdir -p $(dir $@)
	@echo "[cycc] $<"
	@$(cycc) -c -o $@ $< $(flags)

Objects/%.o: %.mm $(header)
	@mkdir -p $(dir $@)
	@echo "[cycc] $<"
	@$(cycc) -c -o $@ $< $(flags) $(xflags)

sysroot:
	@echo "Please read compiling.txt: you do not have a ./sysroot/ folder with the on-device requirements." 1>&2
	@echo 1>&2
	@exit 1

MobileCydia: sysroot $(object)
	@echo "[link] $(object:Objects/%=%)"
	@$(cycc) $(filter %.o,$^) $(flags) $(link) $(uikit)
	@echo "[strp] $@"
	@strip -no_uuid $@
	@echo "[sign] $@"
	@ldid -T0 -Slaunch.xml $@ || { rm -f $@ && false; }

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
	
	mkdir -p _/DEBIAN
	./control.sh _ >_/DEBIAN/control
	
	find _ -name '*.png' -exec ./pngcrush.sh '{}' ';'
	find _ -exec touch -t "$$(date -j -f "%s" +"%Y%m%d%H%M.%S" "$$(git show --format='format:%ct' | head -n 1)")" {} ';'
	
	sudo chown -R 0 _
	sudo chgrp -R 0 _
	sudo chmod 6755 _/Applications/Cydia.app/MobileCydia
	
	mkdir -p debs
	ln -sf debs/cydia_$(version)_iphoneos-arm.deb Cydia.deb
	$(dpkg) -b _ Cydia.deb
	@echo "$$(stat -L -f "%z" Cydia.deb) $$(stat -f "%Y" Cydia.deb)"

.PHONY: all clean sign
