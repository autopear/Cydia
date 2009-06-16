#ifndef UICABOODLE_UCLOCALIZE_H
#define UICABOODLE_UCLOCALIZE_H

#import <Foundation/Foundation.h>

static inline NSString *UCLocalizeEx(NSString *key, NSString *value = nil) {
    return [[NSBundle mainBundle] localizedStringForKey:key value:value table:nil];
}

#define UCLocalize(key) UCLocalizeEx(@ key)

#endif/*UICABOODLE_UCLOCALIZE_H*/
