#include <strings.h>
#include <Sources.h>

#include <sys/types.h>
#include <sys/sysctl.h>

#include <CydiaSubstrate/CydiaSubstrate.h>
#include "CyteKit/PerlCompatibleRegEx.hpp"

_H<NSMutableDictionary> Sources_;
bool Changed_;

_H<NSString> System_;

int main(int argc, const char *argv[]) {
    if (argc < 2 || strcmp(argv[1], "configure") != 0)
        return 0;

    NSAutoreleasePool *pool([[NSAutoreleasePool alloc] init]);

    size_t size;
    sysctlbyname("kern.osversion", NULL, &size, NULL, 0);
    char *osversion = new char[size];
    if (sysctlbyname("kern.osversion", osversion, &size, NULL, 0) != -1)
        System_ = [NSString stringWithUTF8String:osversion];

    NSDictionary *metadata([[[NSMutableDictionary alloc] initWithContentsOfFile:@"/var/lib/cydia/metadata.plist"] autorelease]);
    NSUInteger version(0);

    if (metadata != nil) {
        Sources_ = [metadata objectForKey:@"Sources"];

        if (NSNumber *number = [metadata objectForKey:@"Version"])
            version = [number unsignedIntValue];
    }

    if (Sources_ == nil)
        Sources_ = [NSMutableDictionary dictionaryWithCapacity:8];

    if (version == 0) {
        CydiaAddSource(@"http://apt.thebigboss.org/repofiles/cydia/", @"stable", [NSMutableArray arrayWithObject:@"main"]);
        CydiaAddSource(@"http://apt.modmyi.com/", @"stable", [NSMutableArray arrayWithObject:@"main"]);
        CydiaAddSource(@"http://cydia.zodttd.com/repo/cydia/", @"stable", [NSMutableArray arrayWithObject:@"main"]);
        CydiaAddSource(@"http://repo666.ultrasn0w.com/", @"./");
    }

    CydiaWriteSources();

    [pool release];
    return 0;
}
