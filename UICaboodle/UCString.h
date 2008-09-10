#ifndef UICABOODLE_UCSTRING_H
#define UICABOODLE_UCSTRING_H

#import <Foundation/NSString.h>

@interface NSString (UICaboodle)
+ (NSString *) stringWithDataSize:(double)size;
@end

@implementation NSString (UICaboodle)

+ (NSString *) stringWithDataSize:(double)size {
    unsigned power = 0;
    while (size > 1024) {
        size /= 1024;
        ++power;
    }

    static const char *powers_[] = {"B", "KiB", "MiB", "GiB"};

    return [NSString stringWithFormat:@"%.1f%s", size, powers_[power]];
}

@end

#endif/*UICABOODLE_UCSTRING_H*/
