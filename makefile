iPhone := 192.168.1.100

target := $${PKG_TARG}-

all: Cydia exec

clean:
	rm -f Cydia exec

test: all
	scp -p Cydia saurik@$(iPhone):/dat
	ssh saurik@$(iPhone) /dat/Cydia

exec: exec.mm makefile
	$(target)g++ -Wall -Werror -o $@ $< -framework Foundation -framework CoreFoundation -lobjc

Cydia: Cydia.mm *.h makefile
	$(target)g++ -fobjc-call-cxx-cdtors -g3 -O2 -Wall -Werror -o $@ $< -framework UIKit -framework IOKit -framework CoreFoundation -framework Foundation -framework CoreGraphics -framework GraphicsServices -framework LayerKit -lobjc -lapt-pkg -lpcre -fobjc-exceptions -I/apl/i20 -F$${PKG_ROOT}/System/Library/PrivateFrameworks

.PHONY: all clean test
