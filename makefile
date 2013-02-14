dev := $(shell xcode-select --print-path)/Platforms/iPhoneOS.platform/Developer
sdks := $(dev)/SDKs
ioss := $(sort $(patsubst $(sdks)/iPhoneOS%.sdk,%,$(wildcard $(sdks)/iPhoneOS*.sdk)))
ios := $(word $(words $(ioss)),$(ioss))

# if you can tolerate clang, set this to blank
gcc := 4.2

ifeq ($(gcc),)
gxx := $(dev)/usr/bin/clang++
else
gxx := $(dev)/usr/bin/g++
endif

flags := 
link := 
libs := 

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
flags += -I. -isystem sysroot/usr/include
flags += -fmessage-length=0
flags += -g0 -O2
flags += -fvisibility=hidden

flags += -Wall

ifeq ($(gcc),)
flags += -Wno-unknown-warning-option
flags += -Wno-logical-op-parentheses
else
flags += -fobjc-exceptions
flags += -fno-guess-branch-probability
endif

flags += -Wno-deprecated-declarations

xflags :=
xflags += -fobjc-call-cxx-cdtors
xflags += -fvisibility-inlines-hidden

link += -Lsysroot/usr/lib
link += -multiply_defined suppress

libs += -framework CoreFoundation
libs += -framework CoreGraphics
libs += -framework Foundation
libs += -framework GraphicsServices
libs += -framework IOKit
libs += -framework JavaScriptCore
libs += -framework QuartzCore
libs += -framework SpringBoardServices
libs += -framework SystemConfiguration
libs += -framework WebCore
libs += -framework WebKit

libs += -lapr-1
libs += -lapt-pkg
libs += -lpcre

uikit := 
uikit += -framework UIKit

backrow := 
backrow += -FAppleTV -framework BackRow -framework AppleTV

version := $(shell ./version.sh)

cycc = $(gxx) -mthumb -arch armv6 -o $@ -miphoneos-version-min=2.0 -isysroot $(sdk) -idirafter /usr/include -F{sysroot,}/Library/Frameworks
#cycc = cycc -r4.2 -i$(ios) -o$@

ifneq ($(gcc),)
cycc += -Xarch_armv6 -mcpu=arm1176jzf-s
endif

dirs := Menes CyteKit Cydia SDURLCache

code := $(foreach dir,$(dirs),$(wildcard $(foreach ext,h hpp c cpp m mm,$(dir)/*.$(ext))))
code := $(filter-out SDURLCache/SDURLCacheTests.m,$(code))
code += MobileCydia.mm Version.mm iPhonePrivate.h Cytore.hpp lookup3.c Sources.h Sources.mm

source := $(filter %.m,$(code)) $(filter %.mm,$(code))
source += $(filter %.c,$(code)) $(filter %.cpp,$(code))
header := $(filter %.h,$(code)) $(filter %.hpp,$(code))

object := $(source)
object := $(object:.c=.o)
object := $(object:.cpp=.o)
object := $(object:.m=.o)
object := $(object:.mm=.o)
object := $(object:%=Objects/%)

images := $(shell find MobileCydia.app/ -type f -name '*.png')
images := $(images:%=Images/%)

lproj_deb := debs/cydia-lproj_$(version)_iphoneos-arm.deb

all: MobileCydia

clean:
	rm -f MobileCydia postinst
	rm -rf Objects/ Images/

Objects/%.o: %.c $(header)
	@mkdir -p $(dir $@)
	@echo "[cycc] $<"
	@$(cycc) -c -x c $<

Objects/%.o: %.m $(header)
	@mkdir -p $(dir $@)
	@echo "[cycc] $<"
	@$(cycc) -c $< $(flags)

Objects/%.o: %.mm $(header)
	@mkdir -p $(dir $@)
	@echo "[cycc] $<"
	@$(cycc) -c $< $(flags) $(xflags)

Objects/Version.o: Version.h

Images/%.png: %.png
	@mkdir -p $(dir $@)
	@echo "[pngc] $<"
	@./pngcrush.sh $< $@

sysroot: sysroot.sh
	@echo "Your ./sysroot/ is either missing or out of date. Please read compiling.txt for help." 1>&2
	@echo 1>&2
	@exit 1

MobileCydia: sysroot $(object) entitlements.xml
	@echo "[link] $(object:Objects/%=%)"
	@$(cycc) $(filter %.o,$^) $(flags) $(link) $(libs) $(uikit)
	@mkdir -p bins
	@cp -a $@ bins/$@-$(version)
	@echo "[strp] $@"
	@strip -no_uuid $@
	@echo "[sign] $@"
	@ldid -T0 -Sentitlements.xml $@ || { rm -f $@ && false; }

CydiaAppliance: CydiaAppliance.mm
	$(cycc) $(filter %.mm,$^) $(flags) $(link) -bundle $(libs) $(backrow)

cfversion: cfversion.mm
	$(cycc) $(filter %.mm,$^) $(flags) -framework CoreFoundation
	@ldid -T0 -S $@

postinst: postinst.mm Sources.mm Sources.h CyteKit/stringWithUTF8Bytes.mm CyteKit/stringWithUTF8Bytes.h CyteKit/UCPlatform.h
	$(cycc) $(filter %.mm,$^) $(flags) $(link) -framework CoreFoundation -framework Foundation -framework UIKit -lpcre
	@ldid -T0 -S $@

debs/cydia_$(version)_iphoneos-arm.deb: MobileCydia preinst postinst cfversion $(images) $(shell find MobileCydia.app) cydia.control Library/firmware.sh Library/startup
	sudo rm -rf _
	mkdir -p _/var/lib/cydia
	
	mkdir -p _/etc/apt
	cp -a Trusted.gpg _/etc/apt/trusted.gpg.d
	cp -a Sources.list _/etc/apt/sources.list.d
	
	mkdir -p _/usr/libexec
	cp -a Library _/usr/libexec/cydia
	cp -a sysroot/usr/bin/du _/usr/libexec/cydia
	cp -a cfversion _/usr/libexec/cydia
	
	mkdir -p _/System/Library
	cp -a LaunchDaemons _/System/Library/LaunchDaemons
	
	mkdir -p _/Applications
	cp -a MobileCydia.app _/Applications/Cydia.app
	rm -rf _/Applications/Cydia.app/*.lproj
	cp -a MobileCydia _/Applications/Cydia.app/MobileCydia
	
	cd MobileCydia.app && find . -name '*.png' -exec cp -af ../Images/MobileCydia.app/{} ../_/Applications/Cydia.app/{} ';'
	
	mkdir -p _/Applications/Cydia.app/Sources
	ln -s /usr/share/bigboss/icons/bigboss.png _/Applications/Cydia.app/Sources/apt.bigboss.us.com.png
	ln -s /usr/share/bigboss/icons/planetiphones.png _/Applications/Cydia.app/Sections/"Planet-iPhones Mods.png"
	
	#mkdir -p _/Applications/AppleTV.app/Appliances
	#cp -a Cydia.frappliance _/Applications/AppleTV.app/Appliances
	#cp -a CydiaAppliance _/Applications/AppleTV.app/Appliances/Cydia.frappliance
	
	#mkdir -p _/Applications/Lowtide.app/Appliances
	#ln -s {/Applications/AppleTV,_/Applications/Lowtide}.app/Appliances/Cydia.frappliance
	
	mkdir -p _/DEBIAN
	./control.sh cydia.control _ >_/DEBIAN/control
	cp -a preinst postinst _/DEBIAN/
	
	find _ -exec touch -t "$$(date -j -f "%s" +"%Y%m%d%H%M.%S" "$$(git show --format='format:%ct' | head -n 1)")" {} ';'
	
	sudo chown -R 0 _
	sudo chgrp -R 0 _
	sudo chmod 6755 _/Applications/Cydia.app/MobileCydia
	
	mkdir -p debs
	ln -sf debs/cydia_$(version)_iphoneos-arm.deb Cydia.deb
	$(dpkg) -b _ Cydia.deb
	@echo "$$(stat -L -f "%z" Cydia.deb) $$(stat -f "%Y" Cydia.deb)"

$(lproj_deb): $(shell find MobileCydia.app -name '*.strings') cydia-lproj.control
	sudo rm -rf __
	mkdir -p __/Applications/Cydia.app
	
	cp -a MobileCydia.app/*.lproj __/Applications/Cydia.app
	
	mkdir -p __/DEBIAN
	./control.sh cydia-lproj.control __ >__/DEBIAN/control
	
	sudo chown -R 0 __
	sudo chgrp -R 0 __
	
	mkdir -p debs
	ln -sf debs/cydia-lproj_$(version)_iphoneos-arm.deb Cydia_.deb
	$(dpkg) -b __ Cydia_.deb
	@echo "$$(stat -L -f "%z" Cydia_.deb) $$(stat -f "%Y" Cydia_.deb)"
	
package: debs/cydia_$(version)_iphoneos-arm.deb $(lproj_deb)

.PHONY: all clean package
