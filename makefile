ifndef PKG_TARG
target :=
else
target := $(PKG_TARG)-
endif

all: Cydia

clean:
	rm -f Cydia

Cydia: Cydia.mm ../uicaboodle.m/*.mm ../mobilesubstrate/*.h *.h makefile
	$(target)g++ -march=armv6 -mcpu=arm1176jzf-s -I../uicaboodle.m -I../mobilesubstrate -fobjc-call-cxx-cdtors -g0 -O2 -Wall -Werror -o $@ $(filter %.mm,$^) -framework UIKit -framework IOKit -framework CoreFoundation -framework Foundation -framework CoreGraphics -framework GraphicsServices -framework MessageUI -framework QuartzCore -framework JavaScriptCore -framework WebCore -framework WebKit -lobjc -lapt-pkg -lpcre -fobjc-exceptions -F"$${PKG_ROOT}"/System/Library/PrivateFrameworks -multiply_defined suppress

sign: Cydia
	CODESIGN_ALLOCATE=$$(which "$(target)codesign_allocate") /apl/tel/util/ldid -Slaunch.xml Cydia

.PHONY: all clean sign
