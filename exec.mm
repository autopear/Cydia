#include <Foundation/Foundation.h>
#include <CoreFoundation/CoreFoundation.h>

#include <sys/types.h>
#include <pwd.h>
#include <unistd.h>

#include <stdio.h>
#include <stdlib.h>

const char *Firmware_ = NULL;

unsigned Major_;
unsigned Minor_;
unsigned BugFix_;

#define FW_LEAST(major, minor, bugfix) \
    (major < Major_ || major == Major_ && \
        (minor < Minor_ || minor == Minor_ && \
            bugfix <= BugFix_))

int main(int argc, char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    if (NSDictionary *sysver = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"]) {
        if (NSString *prover = [sysver valueForKey:@"ProductVersion"]) {
            Firmware_ = strdup([prover UTF8String]);
            NSArray *versions = [prover componentsSeparatedByString:@"."];
            int count = [versions count];
            Major_ = count > 0 ? [[versions objectAtIndex:0] intValue] : 0;
            Minor_ = count > 1 ? [[versions objectAtIndex:1] intValue] : 0;
            BugFix_ = count > 2 ? [[versions objectAtIndex:2] intValue] : 0;
        }
    }

    [pool release];

    const char *user;
    if (FW_LEAST(1,1,3))
        user = "mobile";
    else
        user = "root";

    if (argc == 1)
        printf("%s\n", user);
    else {
        struct passwd *passwd = getpwnam(user);

        if (setreuid(passwd->pw_uid, 0) == -1) {
            perror("setreuid");
            exit(1);
        }

        if (setregid(passwd->pw_gid, 0) == -1) {
            perror("setregid");
            exit(1);
        }

        if (execvp(argv[1], argv + 1) == -1) {
            perror("execvp");
            exit(1);
        }
    }

    return 0;
}
