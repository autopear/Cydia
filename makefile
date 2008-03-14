iPhone := 192.168.1.100

all: Cydia exec

test: all
	scp -p Cydia saurik@$(iPhone):/dat
	ssh saurik@$(iPhone) /dat/Cydia

exec: exec.mm makefile
	arm-apple-darwin-g++ -Wall -Werror -o $@ $< -framework Foundation -framework CoreFoundation -lobjc

Cydia-1.2: Cydia.mm *.h makefile
	arm-apple-darwin-g++ -fobjc-abi-version=2 -fobjc-call-cxx-cdtors -g3 -O2 -Wall -o $@ $< -framework UIKit -framework IOKit -framework Foundation -framework CoreFoundation -framework CoreGraphics -framework GraphicsServices -lobjc -lapt-pkg -lpcre -fobjc-exceptions -save-temps -F $(Aspen)/System/Library/Frameworks -I $(Aspen)/usr/include -DTARGET_OS_EMBEDDED -DSRK_ASPEN

Cydia: Cydia.mm *.h makefile
	arm-apple-darwin-g++ -fobjc-call-cxx-cdtors -g3 -O2 -Wall -Werror -o $@ $< -framework UIKit -framework IOKit -framework Foundation -framework CoreFoundation -framework CoreGraphics -framework GraphicsServices -lobjc -lapt-pkg -lpcre -fobjc-exceptions
