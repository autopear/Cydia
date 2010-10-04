#ifndef UICABOODLE_UCSTRING_H
#define UICABOODLE_UCSTRING_H

#import <Foundation/NSString.h>

@interface NSString (UIKit)
- (NSString *) stringByAddingPercentEscapes;
- (NSString *) stringByReplacingCharacter:(unsigned short)arg0 withCharacter:(unsigned short)arg1;
@end

@interface NSString (UICaboodle)
+ (NSString *) stringWithDataSize:(double)size;
- (NSString *) stringByAddingPercentEscapesIncludingReserved;
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

- (NSString *) stringByAddingPercentEscapesIncludingReserved {
    return [(id)CFURLCreateStringByAddingPercentEscapes(
        kCFAllocatorDefault,
        (CFStringRef) self,
        NULL,
        CFSTR(";/?:@&=+$,"),
        kCFStringEncodingUTF8
    ) autorelease];
}

@end

#endif/*UICABOODLE_UCSTRING_H*/
