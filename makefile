gxx := $(shell xcrun --sdk iphoneos -f g++)
sdk := $(shell xcodebuild -sdk iphoneos -version Path)

flags := 
link := 
libs := 

dpkg := dpkg-deb -Zlzma

flags += -F$(sdk)/System/Library/PrivateFrameworks
flags += -I. -isystem sysroot/usr/include
flags += -fmessage-length=0
flags += -g0 -O2
flags += -fvisibility=hidden

flags += -idirafter icu/icuSources/common
flags += -idirafter icu/icuSources/i18n

flags += -Wall

flags += -Wno-unknown-warning-option
flags += -Wno-logical-op-parentheses
flags += -Wno-dangling-else
flags += -Wno-shift-op-parentheses
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
libs += -framework QuartzCore
libs += -framework SpringBoardServices
libs += -framework SystemConfiguration
libs += -framework WebCore
libs += -framework WebKit

libs += -lapt-pkg
libs += -licucore

uikit := 
uikit += -framework UIKit

version := $(shell ./version.sh)

cycc = $(gxx) -arch armv6 -o $@ -miphoneos-version-min=2.0 -isysroot $(sdk) -idirafter /usr/include -F{sysroot,}/Library/Frameworks

cycc += -marm # @synchronized
cycc += -mcpu=arm1176jzf-s
cycc += -mllvm -arm-reserve-r9
link += -lgcc_s.1

dirs := Menes CyteKit Cydia SDURLCache

code := $(foreach dir,$(dirs),$(wildcard $(foreach ext,h hpp c cpp m mm,$(dir)/*.$(ext))))
code := $(filter-out SDURLCache/SDURLCacheTests.m,$(code))
code += MobileCydia.mm Version.mm iPhonePrivate.h Cytore.hpp lookup3.c Sources.h Sources.mm DiskUsage.cpp

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

Objects/%.o: %.cpp $(header)
	@mkdir -p $(dir $@)
	@echo "[cycc] $<"
	@$(cycc) -std=c++11 -c $< $(flags) $(xflags)

Objects/%.o: %.mm $(header)
	@mkdir -p $(dir $@)
	@echo "[cycc] $<"
	@$(cycc) -std=c++11 -c $< $(flags) $(xflags)

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
	@$(cycc) $(filter %.o,$^) $(flags) $(link) $(libs) $(uikit) -Wl,-sdk_version,8.0
	@mkdir -p bins
	@cp -a $@ bins/$@-$(version)
	@echo "[strp] $@"
	@strip $@
	@echo "[uikt] $@"
	@./uikit.sh $@
	@echo "[sign] $@"
	@ldid -T0 -Sentitlements.xml $@ || { rm -f $@ && false; }

cfversion: cfversion.mm
	$(cycc) $(filter %.mm,$^) $(flags) $(link) -framework CoreFoundation
	@ldid -T0 -S $@

setnsfpn: setnsfpn.cpp
	$(cycc) $(filter %.cpp,$^) $(flags) $(link)
	@ldid -T0 -S $@

cydo: cydo.cpp
	$(cycc) -std=c++11 $(filter %.cpp,$^) $(flags) $(link) -Wno-deprecated-writable-strings
	@ldid -T0 -S $@

postinst: postinst.mm CyteKit/stringWithUTF8Bytes.mm CyteKit/stringWithUTF8Bytes.h CyteKit/UCPlatform.h
	$(cycc) -std=c++11 $(filter %.mm,$^) $(flags) $(link) -framework CoreFoundation -framework Foundation -framework UIKit
	@ldid -T0 -S $@

debs/cydia_$(version)_iphoneos-arm.deb: MobileCydia preinst postinst cfversion setnsfpn cydo $(images) $(shell find MobileCydia.app) cydia.control Library/firmware.sh Library/move.sh Library/startup
	sudo rm -rf _
	mkdir -p _/var/lib/cydia
	
	mkdir -p _/etc/apt
	cp -a Trusted.gpg _/etc/apt/trusted.gpg.d
	cp -a Sources.list _/etc/apt/sources.list.d
	
	mkdir -p _/usr/libexec
	cp -a Library _/usr/libexec/cydia
	cp -a sysroot/usr/bin/du _/usr/libexec/cydia
	cp -a cfversion _/usr/libexec/cydia
	cp -a setnsfpn _/usr/libexec/cydia
	
	cp -a cydo _/usr/libexec/cydia
	sudo chmod 6755 _/usr/libexec/cydia/cydo
	
	mkdir -p _/Library
	cp -a LaunchDaemons _/Library/LaunchDaemons
	
	mkdir -p _/Applications
	cp -a MobileCydia.app _/Applications/Cydia.app
	rm -rf _/Applications/Cydia.app/*.lproj
	cp -a MobileCydia _/Applications/Cydia.app/Cydia
	
	cd MobileCydia.app && find . -name '*.png' -exec cp -af ../Images/MobileCydia.app/{} ../_/Applications/Cydia.app/{} ';'
	
	mkdir -p _/Applications/Cydia.app/Sources
	ln -s /usr/share/bigboss/icons/bigboss.png _/Applications/Cydia.app/Sources/apt.bigboss.us.com.png
	ln -s /usr/share/bigboss/icons/planetiphones.png _/Applications/Cydia.app/Sections/"Planet-iPhones Mods.png"
	
	mkdir -p _/DEBIAN
	./control.sh cydia.control _ >_/DEBIAN/control
	cp -a preinst postinst _/DEBIAN/
	
	find _ -exec touch -t "$$(date -j -f "%s" +"%Y%m%d%H%M.%S" "$$(git show --format='format:%ct' | head -n 1)")" {} ';'
	
	sudo chown -R 0 _
	sudo chgrp -R 0 _
	
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
