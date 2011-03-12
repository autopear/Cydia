#include <strings.h>
#include <Sources.h>

#include <UIKit/UIKit.h>
#include <CydiaSubstrate/CydiaSubstrate.h>
#include "CyteKit/PerlCompatibleRegEx.hpp"

_H<NSMutableDictionary> Sources_;
_H<NSString> CydiaSource_;
bool Changed_;

_H<NSString> Firmware_;

int main(int argc, const char *argv[]) {
    if (argc < 2 || strcmp(argv[1], "configure") != 0)
        return 0;

    NSAutoreleasePool *pool([[NSAutoreleasePool alloc] init]);

    Pcre pattern("^([0-9]+\\.[0-9]+)");

    if (pattern([[UIDevice currentDevice] systemVersion]))
        Firmware_ = pattern[1];

    NSDictionary *metadata([[[NSMutableDictionary alloc] initWithContentsOfFile:@"/var/lib/cydia/metadata.plist"] autorelease]);
    NSUInteger version(0);

    if (metadata != nil) {
        Sources_ = [metadata objectForKey:@"Sources"];
        CydiaSource_ = [metadata objectForKey:@"CydiaSource"];

        if (NSNumber *number = [metadata objectForKey:@"Version"])
            version = [number unsignedIntValue];
    }

    if (CydiaSource_ == nil)
        CydiaSource_ = @"apt.saurik.com";

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
