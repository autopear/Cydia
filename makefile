ifndef PKG_TARG
target :=
else
target := $(PKG_TARG)-
endif

frameworks :=

ifneq ($(wildcard $(PKG_ROOT)/System/Library/*Frameworks/LayerKit.framework),)
frameworks += -framework LayerKit
endif

all: Cydia exec

clean:
	rm -f Cydia exec

exec: exec.mm makefile
	$(target)g++ -Wall -Werror -o $@ $< -framework Foundation -framework CoreFoundation -lobjc

Cydia: Cydia.mm ../uicaboodle.m/*.mm *.h makefile
	$(target)g++ -march=armv6 -mcpu=arm1176jzf-s -I../uicaboodle.m -fobjc-call-cxx-cdtors -g0 -O2 -Wall -Werror -o $@ $(filter %.mm,$^) -framework UIKit -framework IOKit -framework CoreFoundation -framework Foundation -framework CoreGraphics -framework GraphicsServices $(frameworks) -lobjc -lapt-pkg -lpcre -fobjc-exceptions -I/apl/i20 -F"$${PKG_ROOT}"/System/Library/PrivateFrameworks

sign: Cydia
	CODESIGN_ALLOCATE=$$(which "$(target)codesign_allocate") /apl/tel/util/ldid -S Cydia

.PHONY: all clean sign
