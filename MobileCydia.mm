/* Cydia - iPhone UIKit Front-End for Debian APT
 * Copyright (C) 2008-2010  Jay Freeman (saurik)
*/

/* Modified BSD License {{{ */
/*
 *        Redistribution and use in source and binary
 * forms, with or without modification, are permitted
 * provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the
 *    above copyright notice, this list of conditions
 *    and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the
 *    above copyright notice, this list of conditions
 *    and the following disclaimer in the documentation
 *    and/or other materials provided with the
 *    distribution.
 * 3. The name of the author may not be used to endorse
 *    or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS''
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING,
 * BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
 * TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
 * ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/
/* }}} */

// XXX: wtf/FastMalloc.h... wtf?
#define USE_SYSTEM_MALLOC 1

/* #include Directives {{{ */
#include "UICaboodle/UCPlatform.h"
#include "UICaboodle/UCLocalize.h"

#include <objc/objc.h>
#include <objc/runtime.h>

#include <CoreGraphics/CoreGraphics.h>
#include <Foundation/Foundation.h>

#if 0
#define DEPLOYMENT_TARGET_MACOSX 1
#define CF_BUILDING_CF 1
#include <CoreFoundation/CFInternal.h>
#endif

#include <CoreFoundation/CFPriv.h>
#include <CoreFoundation/CFUniChar.h>

#include <SystemConfiguration/SystemConfiguration.h>

#include <UIKit/UIKit.h>
#include "iPhonePrivate.h"

#include <IOKit/IOKitLib.h>

#include <WebCore/WebCoreThread.h>

#include <algorithm>
#include <iomanip>
#include <sstream>
#include <string>

#include <ext/stdio_filebuf.h>

#undef ABS

#include <apt-pkg/acquire.h>
#include <apt-pkg/acquire-item.h>
#include <apt-pkg/algorithms.h>
#include <apt-pkg/cachefile.h>
#include <apt-pkg/clean.h>
#include <apt-pkg/configuration.h>
#include <apt-pkg/debindexfile.h>
#include <apt-pkg/debmetaindex.h>
#include <apt-pkg/error.h>
#include <apt-pkg/init.h>
#include <apt-pkg/mmap.h>
#include <apt-pkg/pkgrecords.h>
#include <apt-pkg/sha1.h>
#include <apt-pkg/sourcelist.h>
#include <apt-pkg/sptr.h>
#include <apt-pkg/strutl.h>
#include <apt-pkg/tagfile.h>

#include <apr-1/apr_pools.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/param.h>
#include <sys/mount.h>

#include <fcntl.h>
#include <notify.h>
#include <dlfcn.h>

extern "C" {
#include <mach-o/nlist.h>
}

#include <cstdio>
#include <cstdlib>
#include <cstring>

#include <errno.h>
#include <pcre.h>

#include "UICaboodle/BrowserView.h"

#include "substrate.h"
/* }}} */

/* Profiler {{{ */
struct timeval _ltv;
bool _itv;

#define _timestamp ({ \
    struct timeval tv; \
    gettimeofday(&tv, NULL); \
    tv.tv_sec * 1000000 + tv.tv_usec; \
})

typedef std::vector<class ProfileTime *> TimeList;
TimeList times_;

class ProfileTime {
  private:
    const char *name_;
    uint64_t total_;
    uint64_t count_;

  public:
    ProfileTime(const char *name) :
        name_(name),
        total_(0)
    {
        times_.push_back(this);
    }

    void AddTime(uint64_t time) {
        total_ += time;
        ++count_;
    }

    void Print() {
        if (total_ != 0)
            std::cerr << std::setw(5) << count_ << ", " << std::setw(7) << total_ << " : " << name_ << std::endl;
        total_ = 0;
        count_ = 0;
    }
};

class ProfileTimer {
  private:
    ProfileTime &time_;
    uint64_t start_;

  public:
    ProfileTimer(ProfileTime &time) :
        time_(time),
        start_(_timestamp)
    {
    }

    ~ProfileTimer() {
        time_.AddTime(_timestamp - start_);
    }
};

void PrintTimes() {
    for (TimeList::const_iterator i(times_.begin()); i != times_.end(); ++i)
        (*i)->Print();
    std::cerr << "========" << std::endl;
}

#define _profile(name) { \
    static ProfileTime name(#name); \
    ProfileTimer _ ## name(name);

#define _end }
/* }}} */

#define _pooled _H<NSAutoreleasePool> _pool([[NSAutoreleasePool alloc] init], true);

#define CYPoolStart() \
    NSAutoreleasePool *_pool([[NSAutoreleasePool alloc] init]); \
    do
#define CYPoolEnd() \
    while (false); \
    [_pool release];

static const NSUInteger UIViewAutoresizingFlexibleBoth(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);

void NSLogPoint(const char *fix, const CGPoint &point) {
    NSLog(@"%s(%g,%g)", fix, point.x, point.y);
}

void NSLogRect(const char *fix, const CGRect &rect) {
    NSLog(@"%s(%g,%g)+(%g,%g)", fix, rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
}

static _finline NSString *CydiaURL(NSString *path) {
    char page[25];
    page[0] = 'h'; page[1] = 't'; page[2] = 't'; page[3] = 'p'; page[4] = ':';
    page[5] = '/'; page[6] = '/'; page[7] = 'c'; page[8] = 'y'; page[9] = 'd';
    page[10] = 'i'; page[11] = 'a'; page[12] = '.'; page[13] = 's'; page[14] = 'a';
    page[15] = 'u'; page[16] = 'r'; page[17] = 'i'; page[18] = 'k'; page[19] = '.';
    page[20] = 'c'; page[21] = 'o'; page[22] = 'm'; page[23] = '/'; page[24] = '\0';
    return [[NSString stringWithUTF8String:page] stringByAppendingString:path];
}

static _finline void UpdateExternalStatus(uint64_t newStatus) {
    int notify_token;
    if (notify_register_check("com.saurik.Cydia.status", &notify_token) == NOTIFY_STATUS_OK) {
        notify_set_state(notify_token, newStatus);
        notify_cancel(notify_token);
    }
    notify_post("com.saurik.Cydia.status");
}

/* [NSObject yieldToSelector:(withObject:)] {{{*/
@interface NSObject (Cydia)
- (id) yieldToSelector:(SEL)selector withObject:(id)object;
- (id) yieldToSelector:(SEL)selector;
@end

@implementation NSObject (Cydia)

- (void) doNothing {
}

- (void) _yieldToContext:(NSMutableArray *)context { _pooled
    SEL selector(reinterpret_cast<SEL>([[context objectAtIndex:0] pointerValue]));
    id object([[context objectAtIndex:1] nonretainedObjectValue]);
    volatile bool &stopped(*reinterpret_cast<bool *>([[context objectAtIndex:2] pointerValue]));

    /* XXX: deal with exceptions */
    id value([self performSelector:selector withObject:object]);

    NSMethodSignature *signature([self methodSignatureForSelector:selector]);
    [context removeAllObjects];
    if ([signature methodReturnLength] != 0 && value != nil)
        [context addObject:value];

    stopped = true;

    [self
        performSelectorOnMainThread:@selector(doNothing)
        withObject:nil
        waitUntilDone:NO
    ];
}

- (id) yieldToSelector:(SEL)selector withObject:(id)object {
    /*return [self performSelector:selector withObject:object];*/

    volatile bool stopped(false);

    NSMutableArray *context([NSMutableArray arrayWithObjects:
        [NSValue valueWithPointer:selector],
        [NSValue valueWithNonretainedObject:object],
        [NSValue valueWithPointer:const_cast<bool *>(&stopped)],
    nil]);

    NSThread *thread([[[NSThread alloc]
        initWithTarget:self
        selector:@selector(_yieldToContext:)
        object:context
    ] autorelease]);

    [thread start];

    NSRunLoop *loop([NSRunLoop currentRunLoop]);
    NSDate *future([NSDate distantFuture]);

    while (!stopped && [loop runMode:NSDefaultRunLoopMode beforeDate:future]);

    return [context count] == 0 ? nil : [context objectAtIndex:0];
}

- (id) yieldToSelector:(SEL)selector {
    return [self yieldToSelector:selector withObject:nil];
}

@end
/* }}} */

/* Cydia Action Sheet {{{ */
@interface CYActionSheet : UIAlertView {
    unsigned button_;
}

- (int) yieldToPopupAlertAnimated:(BOOL)animated;
@end

@implementation CYActionSheet

- (id) initWithTitle:(NSString *)title buttons:(NSArray *)buttons defaultButtonIndex:(int)index {
    if ((self = [super init])) {
        [self setTitle:title];
        [self setDelegate:self];
        for (NSString *button in buttons) [self addButtonWithTitle:button];
        [self setCancelButtonIndex:index];
    } return self;
}

- (void) _updateFrameForDisplay {
    [super _updateFrameForDisplay];
    if ([self cancelButtonIndex] == -1) {
        NSArray *buttons = [self buttons];
        if ([buttons count]) {
            UIImage *background = [[buttons objectAtIndex:0] backgroundForState:0];
            for (UIThreePartButton *button in buttons)
                [button setBackground:background forState:0];
        }
    }
}

- (void) alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    button_ = buttonIndex + 1;
}

- (void) dismiss {
    [self dismissWithClickedButtonIndex:-1 animated:YES];
}

- (int) yieldToPopupAlertAnimated:(BOOL)animated {
    [self setRunsModal:YES];
    button_ = 0;
    [self show];
    return button_;
}

@end
/* }}} */

/* NSForcedOrderingSearch doesn't work on the iPhone */
static const NSStringCompareOptions MatchCompareOptions_ = NSLiteralSearch | NSCaseInsensitiveSearch;
static const NSStringCompareOptions LaxCompareOptions_ = NSNumericSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch | NSCaseInsensitiveSearch;
static const CFStringCompareFlags LaxCompareFlags_ = kCFCompareCaseInsensitive | kCFCompareNonliteral | kCFCompareLocalized | kCFCompareNumerically | kCFCompareWidthInsensitive | kCFCompareForcedOrdering;

/* Information Dictionaries {{{ */
@interface NSMutableArray (Cydia)
- (void) addInfoDictionary:(NSDictionary *)info;
@end

@implementation NSMutableArray (Cydia)

- (void) addInfoDictionary:(NSDictionary *)info {
    [self addObject:info];
}

@end

@interface NSMutableDictionary (Cydia)
- (void) addInfoDictionary:(NSDictionary *)info;
@end

@implementation NSMutableDictionary (Cydia)

- (void) addInfoDictionary:(NSDictionary *)info {
    [self setObject:info forKey:[info objectForKey:@"CFBundleIdentifier"]];
}

@end
/* }}} */

#define lprintf(args...) fprintf(stderr, args)

#define ForRelease 1
#define TraceLogging (1 && !ForRelease)
#define HistogramInsertionSort (!ForRelease ? 0 : 0)
#define ProfileTimes (0 && !ForRelease)
#define ForSaurik (0 && !ForRelease)
#define LogBrowser (0 && !ForRelease)
#define TrackResize (0 && !ForRelease)
#define ManualRefresh (1 && !ForRelease)
#define ShowInternals (0 && !ForRelease)
#define IgnoreInstall (0 && !ForRelease)
#define AlwaysReload (0 && !ForRelease)

#if !TraceLogging
#undef _trace
#define _trace(args...)
#endif

#if !ProfileTimes
#undef _profile
#define _profile(name) {
#undef _end
#define _end }
#define PrintTimes() do {} while (false)
#endif

/* Radix Sort {{{ */
typedef uint32_t (*SKRadixFunction)(id, void *);

@interface NSMutableArray (Radix)
- (void) radixSortUsingFunction:(SKRadixFunction)function withContext:(void *)argument;
@end

struct RadixItem_ {
    size_t index;
    uint32_t key;
};

@implementation NSMutableArray (Radix)

- (void) radixSortUsingFunction:(SKRadixFunction)function withContext:(void *)argument {
    size_t count([self count]);
    struct RadixItem_ *swap(new RadixItem_[count * 2]);

    for (size_t i(0); i != count; ++i) {
        RadixItem_ &item(swap[i]);
        item.index = i;

        id object([self objectAtIndex:i]);
        item.key = function(object, argument);
    }

    struct RadixItem_ *lhs(swap), *rhs(swap + count);

    static const size_t width = 32;
    static const size_t bits = 11;
    static const size_t slots = 1 << bits;
    static const size_t passes = (width + (bits - 1)) / bits;

    size_t *hist(new size_t[slots]);

    for (size_t pass(0); pass != passes; ++pass) {
        memset(hist, 0, sizeof(size_t) * slots);

        for (size_t i(0); i != count; ++i) {
            uint32_t key(lhs[i].key);
            key >>= pass * bits;
            key &= _not(uint32_t) >> width - bits;
            ++hist[key];
        }

        size_t offset(0);
        for (size_t i(0); i != slots; ++i) {
            size_t local(offset);
            offset += hist[i];
            hist[i] = local;
        }

        for (size_t i(0); i != count; ++i) {
            uint32_t key(lhs[i].key);
            key >>= pass * bits;
            key &= _not(uint32_t) >> width - bits;
            rhs[hist[key]++] = lhs[i];
        }

        RadixItem_ *tmp(lhs);
        lhs = rhs;
        rhs = tmp;
    }

    delete [] hist;

    const void **values(new const void *[count]);
    for (size_t i(0); i != count; ++i)
        values[i] = [self objectAtIndex:lhs[i].index];
    CFArrayReplaceValues((CFMutableArrayRef) self, CFRangeMake(0, count), values, count);
    delete [] values;

    delete [] swap;
}

@end
/* }}} */
/* Insertion Sort {{{ */

CFIndex SKBSearch_(const void *element, CFIndex elementSize, const void *list, CFIndex count, CFComparatorFunction comparator, void *context) {
    const char *ptr = (const char *)list;
    while (0 < count) {
        CFIndex half = count / 2;
        const char *probe = ptr + elementSize * half;
        CFComparisonResult cr = comparator(element, probe, context);
    if (0 == cr) return (probe - (const char *)list) / elementSize;
        ptr = (cr < 0) ? ptr : probe + elementSize;
        count = (cr < 0) ? half : (half + (count & 1) - 1);
    }
    return (ptr - (const char *)list) / elementSize;
}

CFIndex CFBSearch_(const void *element, CFIndex elementSize, const void *list, CFIndex count, CFComparatorFunction comparator, void *context) {
    const char *ptr = (const char *)list;
    while (0 < count) {
        CFIndex half = count / 2;
        const char *probe = ptr + elementSize * half;
        CFComparisonResult cr = comparator(element, probe, context);
    if (0 == cr) return (probe - (const char *)list) / elementSize;
        ptr = (cr < 0) ? ptr : probe + elementSize;
        count = (cr < 0) ? half : (half + (count & 1) - 1);
    }
    return (ptr - (const char *)list) / elementSize;
}

void CFArrayInsertionSortValues(CFMutableArrayRef array, CFRange range, CFComparatorFunction comparator, void *context) {
    if (range.length == 0)
        return;
    const void **values(new const void *[range.length]);
    CFArrayGetValues(array, range, values);

#if HistogramInsertionSort > 0
    uint32_t total(0), *offsets(new uint32_t[range.length]);
#endif

    for (CFIndex index(1); index != range.length; ++index) {
        const void *value(values[index]);
        //CFIndex correct(SKBSearch_(&value, sizeof(const void *), values, index, comparator, context));
        CFIndex correct(index);
        while (comparator(value, values[correct - 1], context) == kCFCompareLessThan) {
#if HistogramInsertionSort > 1
            NSLog(@"%@ < %@", value, values[correct - 1]);
#endif
            if (--correct == 0)
                break;
        }
        if (correct != index) {
            size_t offset(index - correct);
#if HistogramInsertionSort
            total += offset;
            ++offsets[offset];
            if (offset > 10)
                NSLog(@"Heavy Insertion Displacement: %u = %@", offset, value);
#endif
            memmove(values + correct + 1, values + correct, sizeof(const void *) * offset);
            values[correct] = value;
        }
    }

    CFArrayReplaceValues(array, range, values, range.length);
    delete [] values;

#if HistogramInsertionSort > 0
    for (CFIndex index(0); index != range.length; ++index)
        if (offsets[index] != 0)
            NSLog(@"Insertion Displacement [%u]: %u", index, offsets[index]);
    NSLog(@"Average Insertion Displacement: %f", double(total) / range.length);
    delete [] offsets;
#endif
}

/* }}} */

/* Apple Bug Fixes {{{ */
@implementation UIWebDocumentView (Cydia)

- (void) _setScrollerOffset:(CGPoint)offset {
    UIScroller *scroller([self _scroller]);

    CGSize size([scroller contentSize]);
    CGSize bounds([scroller bounds].size);

    CGPoint max;
    max.x = size.width - bounds.width;
    max.y = size.height - bounds.height;

    // wtf Apple?!
    if (max.x < 0)
        max.x = 0;
    if (max.y < 0)
        max.y = 0;

    offset.x = offset.x < 0 ? 0 : offset.x > max.x ? max.x : offset.x;
    offset.y = offset.y < 0 ? 0 : offset.y > max.y ? max.y : offset.y;

    [scroller setOffset:offset];
}

@end
/* }}} */

@implementation WebScriptObject (NSFastEnumeration)

- (NSUInteger) countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)objects count:(NSUInteger)count {
    size_t length([self count] - state->state);
    if (length <= 0)
        return 0;
    else if (length > count)
        length = count;
    for (size_t i(0); i != length; ++i)
        objects[i] = [self objectAtIndex:state->state++];
    state->itemsPtr = objects;
    state->mutationsPtr = (unsigned long *) self;
    return length;
}

@end

NSUInteger DOMNodeList$countByEnumeratingWithState$objects$count$(DOMNodeList *self, SEL sel, NSFastEnumerationState *state, id *objects, NSUInteger count) {
    size_t length([self length] - state->state);
    if (length <= 0)
        return 0;
    else if (length > count)
        length = count;
    for (size_t i(0); i != length; ++i)
        objects[i] = [self item:state->state++];
    state->itemsPtr = objects;
    state->mutationsPtr = (unsigned long *) self;
    return length;
}

/* Cydia NSString Additions {{{ */
@interface NSString (Cydia)
+ (NSString *) stringWithUTF8BytesNoCopy:(const char *)bytes length:(int)length;
+ (NSString *) stringWithUTF8Bytes:(const char *)bytes length:(int)length withZone:(NSZone *)zone inPool:(apr_pool_t *)pool;
+ (NSString *) stringWithUTF8Bytes:(const char *)bytes length:(int)length;
- (NSComparisonResult) compareByPath:(NSString *)other;
- (NSString *) stringByCachingURLWithCurrentCDN;
- (NSString *) stringByAddingPercentEscapesIncludingReserved;
@end

@implementation NSString (Cydia)

+ (NSString *) stringWithUTF8BytesNoCopy:(const char *)bytes length:(int)length {
    return [[[NSString alloc] initWithBytesNoCopy:const_cast<char *>(bytes) length:length encoding:NSUTF8StringEncoding freeWhenDone:NO] autorelease];
}

+ (NSString *) stringWithUTF8Bytes:(const char *)bytes length:(int)length withZone:(NSZone *)zone inPool:(apr_pool_t *)pool {
    char *data(reinterpret_cast<char *>(apr_palloc(pool, length)));
    memcpy(data, bytes, length);
    return [[[NSString allocWithZone:zone] initWithBytesNoCopy:data length:length encoding:NSUTF8StringEncoding freeWhenDone:NO] autorelease];
}

+ (NSString *) stringWithUTF8Bytes:(const char *)bytes length:(int)length {
    return [[[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding] autorelease];
}

- (NSComparisonResult) compareByPath:(NSString *)other {
    NSString *prefix = [self commonPrefixWithString:other options:0];
    size_t length = [prefix length];

    NSRange lrange = NSMakeRange(length, [self length] - length);
    NSRange rrange = NSMakeRange(length, [other length] - length);

    lrange = [self rangeOfString:@"/" options:0 range:lrange];
    rrange = [other rangeOfString:@"/" options:0 range:rrange];

    NSComparisonResult value;

    if (lrange.location == NSNotFound && rrange.location == NSNotFound)
        value = NSOrderedSame;
    else if (lrange.location == NSNotFound)
        value = NSOrderedAscending;
    else if (rrange.location == NSNotFound)
        value = NSOrderedDescending;
    else
        value = NSOrderedSame;

    NSString *lpath = lrange.location == NSNotFound ? [self substringFromIndex:length] :
        [self substringWithRange:NSMakeRange(length, lrange.location - length)];
    NSString *rpath = rrange.location == NSNotFound ? [other substringFromIndex:length] :
        [other substringWithRange:NSMakeRange(length, rrange.location - length)];

    NSComparisonResult result = [lpath compare:rpath];
    return result == NSOrderedSame ? value : result;
}

- (NSString *) stringByCachingURLWithCurrentCDN {
    return [self
        stringByReplacingOccurrencesOfString:@"://cydia.saurik.com/"
        withString:@"://cache.cydia.saurik.com/"
    ];
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
/* }}} */

/* C++ NSString Wrapper Cache {{{ */
static _finline CFStringRef CYStringCreate(const char *data, size_t size) {
    return size == 0 ? NULL :
        CFStringCreateWithBytesNoCopy(kCFAllocatorDefault, reinterpret_cast<const uint8_t *>(data), size, kCFStringEncodingUTF8, NO, kCFAllocatorNull) ?:
        CFStringCreateWithBytesNoCopy(kCFAllocatorDefault, reinterpret_cast<const uint8_t *>(data), size, kCFStringEncodingISOLatin1, NO, kCFAllocatorNull);
}

static _finline CFStringRef CYStringCreate(const char *data) {
    return CYStringCreate(data, strlen(data));
}

class CYString {
  private:
    char *data_;
    size_t size_;
    CFStringRef cache_;

    _finline void clear_() {
        if (cache_ != NULL) {
            CFRelease(cache_);
            cache_ = NULL;
        }
    }

  public:
    _finline bool empty() const {
        return size_ == 0;
    }

    _finline size_t size() const {
        return size_;
    }

    _finline char *data() const {
        return data_;
    }

    _finline void clear() {
        size_ = 0;
        clear_();
    }

    _finline CYString() :
        data_(0),
        size_(0),
        cache_(NULL)
    {
    }

    _finline ~CYString() {
        clear_();
    }

    void operator =(const CYString &rhs) {
        data_ = rhs.data_;
        size_ = rhs.size_;

        if (rhs.cache_ == nil)
            cache_ = NULL;
        else
            cache_ = reinterpret_cast<CFStringRef>(CFRetain(rhs.cache_));
    }

    void set(apr_pool_t *pool, const char *data, size_t size) {
        if (size == 0)
            clear();
        else {
            clear_();

            char *temp(reinterpret_cast<char *>(apr_palloc(pool, size + 1)));
            memcpy(temp, data, size);
            temp[size] = '\0';
            data_ = temp;
            size_ = size;
        }
    }

    _finline void set(apr_pool_t *pool, const char *data) {
        set(pool, data, data == NULL ? 0 : strlen(data));
    }

    _finline void set(apr_pool_t *pool, const std::string &rhs) {
        set(pool, rhs.data(), rhs.size());
    }

    bool operator ==(const CYString &rhs) const {
        return size_ == rhs.size_ && memcmp(data_, rhs.data_, size_) == 0;
    }

    _finline operator CFStringRef() {
        if (cache_ == NULL)
            cache_ = CYStringCreate(data_, size_);
        return cache_;
    }

    _finline operator id() {
        return (NSString *) static_cast<CFStringRef>(*this);
    }
};
/* }}} */
/* C++ NSString Algorithm Adapters {{{ */
extern "C" {
    CF_EXPORT CFHashCode CFStringHashNSString(CFStringRef str);
}

struct NSStringMapHash :
    std::unary_function<NSString *, size_t>
{
    _finline size_t operator ()(NSString *value) const {
        return CFStringHashNSString((CFStringRef) value);
    }
};

struct NSStringMapLess :
    std::binary_function<NSString *, NSString *, bool>
{
    _finline bool operator ()(NSString *lhs, NSString *rhs) const {
        return [lhs compare:rhs] == NSOrderedAscending;
    }
};

struct NSStringMapEqual :
    std::binary_function<NSString *, NSString *, bool>
{
    _finline bool operator ()(NSString *lhs, NSString *rhs) const {
        return CFStringCompare((CFStringRef) lhs, (CFStringRef) rhs, 0) == kCFCompareEqualTo;
        //CFEqual((CFTypeRef) lhs, (CFTypeRef) rhs);
        //[lhs isEqualToString:rhs];
    }
};
/* }}} */

/* Perl-Compatible RegEx {{{ */
class Pcre {
  private:
    pcre *code_;
    pcre_extra *study_;
    int capture_;
    int *matches_;
    const char *data_;

  public:
    Pcre(const char *regex) :
        study_(NULL)
    {
        const char *error;
        int offset;
        code_ = pcre_compile(regex, 0, &error, &offset, NULL);

        if (code_ == NULL) {
            lprintf("%d:%s\n", offset, error);
            _assert(false);
        }

        pcre_fullinfo(code_, study_, PCRE_INFO_CAPTURECOUNT, &capture_);
        matches_ = new int[(capture_ + 1) * 3];
    }

    ~Pcre() {
        pcre_free(code_);
        delete matches_;
    }

    NSString *operator [](size_t match) {
        return [NSString stringWithUTF8Bytes:(data_ + matches_[match * 2]) length:(matches_[match * 2 + 1] - matches_[match * 2])];
    }

    bool operator ()(NSString *data) {
        // XXX: length is for characters, not for bytes
        return operator ()([data UTF8String], [data length]);
    }

    bool operator ()(const char *data, size_t size) {
        data_ = data;
        return pcre_exec(code_, study_, data, size, 0, 0, matches_, (capture_ + 1) * 3) >= 0;
    }
};
/* }}} */
/* Mime Addresses {{{ */
@interface Address : NSObject {
    NSString *name_;
    NSString *address_;
}

- (NSString *) name;
- (NSString *) address;

- (void) setAddress:(NSString *)address;

+ (Address *) addressWithString:(NSString *)string;
- (Address *) initWithString:(NSString *)string;
@end

@implementation Address

- (void) dealloc {
    [name_ release];
    if (address_ != nil)
        [address_ release];
    [super dealloc];
}

- (NSString *) name {
    return name_;
}

- (NSString *) address {
    return address_;
}

- (void) setAddress:(NSString *)address {
    if (address_ != nil)
        [address_ autorelease];
    if (address == nil)
        address_ = nil;
    else
        address_ = [address retain];
}

+ (Address *) addressWithString:(NSString *)string {
    return [[[Address alloc] initWithString:string] autorelease];
}

+ (NSArray *) _attributeKeys {
    return [NSArray arrayWithObjects:@"address", @"name", nil];
}

- (NSArray *) attributeKeys {
    return [[self class] _attributeKeys];
}

+ (BOOL) isKeyExcludedFromWebScript:(const char *)name {
    return ![[self _attributeKeys] containsObject:[NSString stringWithUTF8String:name]] && [super isKeyExcludedFromWebScript:name];
}

- (Address *) initWithString:(NSString *)string {
    if ((self = [super init]) != nil) {
        const char *data = [string UTF8String];
        size_t size = [string length];

        static Pcre address_r("^\"?(.*)\"? <([^>]*)>$");

        if (address_r(data, size)) {
            name_ = [address_r[1] retain];
            address_ = [address_r[2] retain];
        } else {
            name_ = [string retain];
            address_ = nil;
        }
    } return self;
}

@end
/* }}} */
/* CoreGraphics Primitives {{{ */
class CYColor {
  private:
    CGColorRef color_;

    static CGColorRef Create_(CGColorSpaceRef space, float red, float green, float blue, float alpha) {
        CGFloat color[] = {red, green, blue, alpha};
        return CGColorCreate(space, color);
    }

  public:
    CYColor() :
        color_(NULL)
    {
    }

    CYColor(CGColorSpaceRef space, float red, float green, float blue, float alpha) :
        color_(Create_(space, red, green, blue, alpha))
    {
        Set(space, red, green, blue, alpha);
    }

    void Clear() {
        if (color_ != NULL)
            CGColorRelease(color_);
    }

    ~CYColor() {
        Clear();
    }

    void Set(CGColorSpaceRef space, float red, float green, float blue, float alpha) {
        Clear();
        color_ = Create_(space, red, green, blue, alpha);
    }

    operator CGColorRef() {
        return color_;
    }
};
/* }}} */

/* Random Global Variables {{{ */
static const int PulseInterval_ = 50000;
static const int ButtonBarWidth_ = 60;
static const int ButtonBarHeight_ = 48;
static const float KeyboardTime_ = 0.3f;

static int Finish_;
static NSArray *Finishes_;

#define SpringBoard_ "/System/Library/LaunchDaemons/com.apple.SpringBoard.plist"
#define NotifyConfig_ "/etc/notify.conf"

static bool Queuing_;

static CYColor Blue_;
static CYColor Blueish_;
static CYColor Black_;
static CYColor Off_;
static CYColor White_;
static CYColor Gray_;
static CYColor Green_;
static CYColor Purple_;
static CYColor Purplish_;

static UIColor *InstallingColor_;
static UIColor *RemovingColor_;

static NSString *App_;
static NSString *Home_;

static BOOL Advanced_;
static BOOL Ignored_;

static UIFont *Font12_;
static UIFont *Font12Bold_;
static UIFont *Font14_;
static UIFont *Font18Bold_;
static UIFont *Font22Bold_;

static const char *Machine_ = NULL;
static NSString *System_ = nil;
static NSString *SerialNumber_ = nil;
static NSString *ChipID_ = nil;
static NSString *Token_ = nil;
static NSString *UniqueID_ = nil;
static NSString *PLMN_ = nil;
static NSString *Build_ = nil;
static NSString *Product_ = nil;
static NSString *Safari_ = nil;

static CFLocaleRef Locale_;
static NSArray *Languages_;
static CGColorSpaceRef space_;

static NSDictionary *SectionMap_;
static NSMutableDictionary *Metadata_;
static _transient NSMutableDictionary *Settings_;
static _transient NSString *Role_;
static _transient NSMutableDictionary *Packages_;
static _transient NSMutableDictionary *Sections_;
static _transient NSMutableDictionary *Sources_;
static bool Changed_;
static NSDate *now_;

static bool IsWildcat_;
/* }}} */

/* Display Helpers {{{ */
inline float Interpolate(float begin, float end, float fraction) {
    return (end - begin) * fraction + begin;
}

/* XXX: localize this! */
NSString *SizeString(double size) {
    bool negative = size < 0;
    if (negative)
        size = -size;

    unsigned power = 0;
    while (size > 1024) {
        size /= 1024;
        ++power;
    }

    static const char *powers_[] = {"B", "kB", "MB", "GB"};

    return [NSString stringWithFormat:@"%s%.1f %s", (negative ? "-" : ""), size, powers_[power]];
}

static _finline const char *StripVersion_(const char *version) {
    const char *colon(strchr(version, ':'));
    if (colon != NULL)
        version = colon + 1;
    return version;
}

NSString *LocalizeSection(NSString *section) {
    static Pcre title_r("^(.*?) \\((.*)\\)$");
    if (title_r(section)) {
        NSString *parent(title_r[1]);
        NSString *child(title_r[2]);

        return [NSString stringWithFormat:UCLocalize("PARENTHETICAL"),
            LocalizeSection(parent),
            LocalizeSection(child)
        ];
    }

    return [[NSBundle mainBundle] localizedStringForKey:section value:nil table:@"Sections"];
}

NSString *Simplify(NSString *title) {
    const char *data = [title UTF8String];
    size_t size = [title length];

    static Pcre square_r("^\\[(.*)\\]$");
    if (square_r(data, size))
        return Simplify(square_r[1]);

    static Pcre paren_r("^\\((.*)\\)$");
    if (paren_r(data, size))
        return Simplify(paren_r[1]);

    static Pcre title_r("^(.*?) \\((.*)\\)$");
    if (title_r(data, size))
        return Simplify(title_r[1]);

    return title;
}
/* }}} */

NSString *GetLastUpdate() {
    NSDate *update = [Metadata_ objectForKey:@"LastUpdate"];

    if (update == nil)
        return UCLocalize("NEVER_OR_UNKNOWN");

    CFDateFormatterRef formatter = CFDateFormatterCreate(NULL, Locale_, kCFDateFormatterMediumStyle, kCFDateFormatterMediumStyle);
    CFStringRef formatted = CFDateFormatterCreateStringWithDate(NULL, formatter, (CFDateRef) update);

    CFRelease(formatter);

    return [(NSString *) formatted autorelease];
}

bool isSectionVisible(NSString *section) {
    NSDictionary *metadata([Sections_ objectForKey:section]);
    NSNumber *hidden(metadata == nil ? nil : [metadata objectForKey:@"Hidden"]);
    return hidden == nil || ![hidden boolValue];
}

@class Cydia;

/* Delegate Prototypes {{{ */
@class Package;
@class Source;

@interface NSObject (ProgressDelegate)
@end

@protocol ProgressDelegate
- (void) setProgressError:(NSString *)error withTitle:(NSString *)id;
- (void) setProgressTitle:(NSString *)title;
- (void) setProgressPercent:(float)percent;
- (void) startProgress;
- (void) addProgressOutput:(NSString *)output;
- (bool) isCancelling:(size_t)received;
@end

@protocol ConfigurationDelegate
- (void) repairWithSelector:(SEL)selector;
- (void) setConfigurationData:(NSString *)data;
@end

@class PackageController;

@protocol CydiaDelegate
- (void) setPackageController:(PackageController *)view;
- (void) clearPackage:(Package *)package;
- (void) installPackage:(Package *)package;
- (void) installPackages:(NSArray *)packages;
- (void) removePackage:(Package *)package;
- (void) beginUpdate;
- (BOOL) updating;
- (void) distUpgrade;
- (void) loadData;
- (void) updateData;
- (void) syncData;
- (void) showSettings;
- (UIProgressHUD *) addProgressHUD;
- (BOOL) hudIsShowing;
- (void) removeProgressHUD:(UIProgressHUD *)hud;
- (CYViewController *) pageForPackage:(NSString *)name;
- (PackageController *) packageController;
- (void) showActionSheet:(UIActionSheet *)sheet fromItem:(UIBarButtonItem *)item;
@end
/* }}} */

/* Status Delegation {{{ */
class Status :
    public pkgAcquireStatus
{
  private:
    _transient NSObject<ProgressDelegate> *delegate_;

  public:
    Status() :
        delegate_(nil)
    {
    }

    void setDelegate(id delegate) {
        delegate_ = delegate;
    }

    NSObject<ProgressDelegate> *getDelegate() const {
        return delegate_;
    }

    virtual bool MediaChange(std::string media, std::string drive) {
        return false;
    }

    virtual void IMSHit(pkgAcquire::ItemDesc &item) {
    }

    virtual void Fetch(pkgAcquire::ItemDesc &item) {
        //NSString *name([NSString stringWithUTF8String:item.ShortDesc.c_str()]);
        [delegate_ setProgressTitle:[NSString stringWithFormat:UCLocalize("DOWNLOADING_"), [NSString stringWithUTF8String:item.ShortDesc.c_str()]]];
    }

    virtual void Done(pkgAcquire::ItemDesc &item) {
    }

    virtual void Fail(pkgAcquire::ItemDesc &item) {
        if (
            item.Owner->Status == pkgAcquire::Item::StatIdle ||
            item.Owner->Status == pkgAcquire::Item::StatDone
        )
            return;

        std::string &error(item.Owner->ErrorText);
        if (error.empty())
            return;

        NSString *description([NSString stringWithUTF8String:item.Description.c_str()]);
        NSArray *fields([description componentsSeparatedByString:@" "]);
        NSString *source([fields count] == 0 ? nil : [fields objectAtIndex:0]);

        [delegate_ performSelectorOnMainThread:@selector(_setProgressErrorPackage:)
            withObject:[NSArray arrayWithObjects:
                [NSString stringWithUTF8String:error.c_str()],
                source,
            nil]
            waitUntilDone:YES
        ];
    }

    virtual bool Pulse(pkgAcquire *Owner) {
        bool value = pkgAcquireStatus::Pulse(Owner);

        float percent(
            double(CurrentBytes + CurrentItems) /
            double(TotalBytes + TotalItems)
        );

        [delegate_ setProgressPercent:percent];
        return [delegate_ isCancelling:CurrentBytes] ? false : value;
    }

    virtual void Start() {
        [delegate_ startProgress];
    }

    virtual void Stop() {
    }
};
/* }}} */
/* Progress Delegation {{{ */
class Progress :
    public OpProgress
{
  private:
    _transient id<ProgressDelegate> delegate_;
    float percent_;

  protected:
    virtual void Update() {
        /*if (abs(Percent - percent_) > 2)
            //NSLog(@"%s:%s:%f", Op.c_str(), SubOp.c_str(), Percent);
            percent_ = Percent;
        }*/

        /*[delegate_ setProgressTitle:[NSString stringWithUTF8String:Op.c_str()]];
        [delegate_ setProgressPercent:(Percent / 100)];*/
    }

  public:
    Progress() :
        delegate_(nil),
        percent_(0)
    {
    }

    void setDelegate(id delegate) {
        delegate_ = delegate;
    }

    id getDelegate() const {
        return delegate_;
    }

    virtual void Done() {
        //NSLog(@"DONE");
        //[delegate_ setProgressPercent:1];
    }
};
/* }}} */

/* Database Interface {{{ */
typedef std::map< unsigned long, _H<Source> > SourceMap;

@interface Database : NSObject {
    NSZone *zone_;
    apr_pool_t *pool_;

    unsigned era_;

    pkgCacheFile cache_;
    pkgDepCache::Policy *policy_;
    pkgRecords *records_;
    pkgProblemResolver *resolver_;
    pkgAcquire *fetcher_;
    FileFd *lock_;
    SPtr<pkgPackageManager> manager_;
    pkgSourceList *list_;

    SourceMap sources_;
    CFMutableArrayRef packages_;

    _transient NSObject<ConfigurationDelegate, ProgressDelegate> *delegate_;
    Status status_;
    Progress progress_;

    int cydiafd_;
    int statusfd_;
    FILE *input_;
}

+ (Database *) sharedInstance;
- (unsigned) era;

- (void) _readCydia:(NSNumber *)fd;
- (void) _readStatus:(NSNumber *)fd;
- (void) _readOutput:(NSNumber *)fd;

- (FILE *) input;

- (Package *) packageWithName:(NSString *)name;

- (pkgCacheFile &) cache;
- (pkgDepCache::Policy *) policy;
- (pkgRecords *) records;
- (pkgProblemResolver *) resolver;
- (pkgAcquire &) fetcher;
- (pkgSourceList &) list;
- (NSArray *) packages;
- (NSArray *) sources;
- (void) reloadData;

- (void) configure;
- (bool) prepare;
- (void) perform;
- (bool) upgrade;
- (void) update;

- (void) updateWithStatus:(Status &)status;

- (void) setDelegate:(id)delegate;
- (Source *) getSource:(pkgCache::PkgFileIterator)file;
@end
/* }}} */
/* Delegate Helpers {{{ */
@implementation NSObject (ProgressDelegate)

- (void) _setProgressErrorPackage:(NSArray *)args {
    [self performSelector:@selector(setProgressError:forPackage:)
        withObject:[args objectAtIndex:0]
        withObject:([args count] == 1 ? nil : [args objectAtIndex:1])
    ];
}

- (void) _setProgressErrorTitle:(NSArray *)args {
    [self performSelector:@selector(setProgressError:withTitle:)
        withObject:[args objectAtIndex:0]
        withObject:([args count] == 1 ? nil : [args objectAtIndex:1])
    ];
}

- (void) _setProgressError:(NSString *)error withTitle:(NSString *)title {
    [self performSelectorOnMainThread:@selector(_setProgressErrorTitle:)
        withObject:[NSArray arrayWithObjects:error, title, nil]
        waitUntilDone:YES
    ];
}

- (void) setProgressError:(NSString *)error forPackage:(NSString *)id {
    Package *package = id == nil ? nil : [[Database sharedInstance] packageWithName:id];

    [self performSelector:@selector(setProgressError:withTitle:)
        withObject:error
        withObject:(package == nil ? id : [package name])
    ];
}

@end
/* }}} */

/* Source Class {{{ */
@interface Source : NSObject {
    CYString depiction_;
    CYString description_;
    CYString label_;
    CYString origin_;
    CYString support_;

    CYString uri_;
    CYString distribution_;
    CYString type_;
    CYString version_;

    NSString *host_;
    NSString *authority_;

    CYString defaultIcon_;

    NSDictionary *record_;
    BOOL trusted_;
}

- (Source *) initWithMetaIndex:(metaIndex *)index inPool:(apr_pool_t *)pool;

- (NSComparisonResult) compareByNameAndType:(Source *)source;

- (NSString *) depictionForPackage:(NSString *)package;
- (NSString *) supportForPackage:(NSString *)package;

- (NSDictionary *) record;
- (BOOL) trusted;

- (NSString *) uri;
- (NSString *) distribution;
- (NSString *) type;
- (NSString *) key;
- (NSString *) host;

- (NSString *) name;
- (NSString *) description;
- (NSString *) label;
- (NSString *) origin;
- (NSString *) version;

- (NSString *) defaultIcon;

@end

@implementation Source

- (void) _clear {
    uri_.clear();
    distribution_.clear();
    type_.clear();

    description_.clear();
    label_.clear();
    origin_.clear();
    depiction_.clear();
    support_.clear();
    version_.clear();
    defaultIcon_.clear();

    if (record_ != nil) {
        [record_ release];
        record_ = nil;
    }

    if (host_ != nil) {
        [host_ release];
        host_ = nil;
    }

    if (authority_ != nil) {
        [authority_ release];
        authority_ = nil;
    }
}

- (void) dealloc {
    // XXX: this is a very inefficient way to call these deconstructors
    [self _clear];
    [super dealloc];
}

+ (NSArray *) _attributeKeys {
    return [NSArray arrayWithObjects:@"description", @"distribution", @"host", @"key", @"label", @"name", @"origin", @"trusted", @"type", @"uri", @"version", nil];
}

- (NSArray *) attributeKeys {
    return [[self class] _attributeKeys];
}

+ (BOOL) isKeyExcludedFromWebScript:(const char *)name {
    return ![[self _attributeKeys] containsObject:[NSString stringWithUTF8String:name]] && [super isKeyExcludedFromWebScript:name];
}

- (void) setMetaIndex:(metaIndex *)index inPool:(apr_pool_t *)pool {
    [self _clear];

    trusted_ = index->IsTrusted();

    uri_.set(pool, index->GetURI());
    distribution_.set(pool, index->GetDist());
    type_.set(pool, index->GetType());

    debReleaseIndex *dindex(dynamic_cast<debReleaseIndex *>(index));
    if (dindex != NULL) {
        FileFd fd;
        if (!fd.Open(dindex->MetaIndexFile("Release"), FileFd::ReadOnly))
            _error->Discard();
        else {
            pkgTagFile tags(&fd);

            pkgTagSection section;
            tags.Step(section);

            struct {
                const char *name_;
                CYString *value_;
            } names[] = {
                {"default-icon", &defaultIcon_},
                {"depiction", &depiction_},
                {"description", &description_},
                {"label", &label_},
                {"origin", &origin_},
                {"support", &support_},
                {"version", &version_},
            };

            for (size_t i(0); i != sizeof(names) / sizeof(names[0]); ++i) {
                const char *start, *end;

                if (section.Find(names[i].name_, start, end)) {
                    CYString &value(*names[i].value_);
                    value.set(pool, start, end - start);
                }
            }
        }
    }

    record_ = [Sources_ objectForKey:[self key]];
    if (record_ != nil)
        record_ = [record_ retain];

    NSURL *url([NSURL URLWithString:uri_]);

    host_ = [url host];
    if (host_ != nil)
        host_ = [[host_ lowercaseString] retain];

    if (host_ != nil)
        authority_ = host_;
    else
        authority_ = [url path];

    if (authority_ != nil)
        authority_ = [authority_ retain];
}

- (Source *) initWithMetaIndex:(metaIndex *)index inPool:(apr_pool_t *)pool {
    if ((self = [super init]) != nil) {
        [self setMetaIndex:index inPool:pool];
    } return self;
}

- (NSComparisonResult) compareByNameAndType:(Source *)source {
    NSDictionary *lhr = [self record];
    NSDictionary *rhr = [source record];

    if (lhr != rhr)
        return lhr == nil ? NSOrderedDescending : NSOrderedAscending;

    NSString *lhs = [self name];
    NSString *rhs = [source name];

    if ([lhs length] != 0 && [rhs length] != 0) {
        unichar lhc = [lhs characterAtIndex:0];
        unichar rhc = [rhs characterAtIndex:0];

        if (isalpha(lhc) && !isalpha(rhc))
            return NSOrderedAscending;
        else if (!isalpha(lhc) && isalpha(rhc))
            return NSOrderedDescending;
    }

    return [lhs compare:rhs options:LaxCompareOptions_];
}

- (NSString *) depictionForPackage:(NSString *)package {
    return depiction_.empty() ? nil : [static_cast<id>(depiction_) stringByReplacingOccurrencesOfString:@"*" withString:package];
}

- (NSString *) supportForPackage:(NSString *)package {
    return support_.empty() ? nil : [static_cast<id>(support_) stringByReplacingOccurrencesOfString:@"*" withString:package];
}

- (NSDictionary *) record {
    return record_;
}

- (BOOL) trusted {
    return trusted_;
}

- (NSString *) uri {
    return uri_;
}

- (NSString *) distribution {
    return distribution_;
}

- (NSString *) type {
    return type_;
}

- (NSString *) key {
    return [NSString stringWithFormat:@"%@:%@:%@", (NSString *) type_, (NSString *) uri_, (NSString *) distribution_];
}

- (NSString *) host {
    return host_;
}

- (NSString *) name {
    return origin_.empty() ? authority_ : origin_;
}

- (NSString *) description {
    return description_;
}

- (NSString *) label {
    return label_.empty() ? authority_ : label_;
}

- (NSString *) origin {
    return origin_;
}

- (NSString *) version {
    return version_;
}

- (NSString *) defaultIcon {
    return defaultIcon_;
}

@end
/* }}} */
/* Relationship Class {{{ */
@interface Relationship : NSObject {
    NSString *type_;
    NSString *id_;
}

- (NSString *) type;
- (NSString *) id;
- (NSString *) name;

@end

@implementation Relationship

- (void) dealloc {
    [type_ release];
    [id_ release];
    [super dealloc];
}

- (NSString *) type {
    return type_;
}

- (NSString *) id {
    return id_;
}

- (NSString *) name {
    _assert(false);
    return nil;
}

@end
/* }}} */
/* Package Class {{{ */
@interface Package : NSObject {
    unsigned era_;
    apr_pool_t *pool_;

    pkgCache::VerIterator version_;
    pkgCache::PkgIterator iterator_;
    _transient Database *database_;
    pkgCache::VerFileIterator file_;

    Source *source_;
    bool parsed_;

    CYString section_;
    _transient NSString *section$_;
    bool essential_;
    bool obsolete_;

    NSString *latest_;
    CYString installed_;

    CYString id_;
    CYString name_;
    CYString tagline_;
    CYString icon_;
    CYString depiction_;
    CYString homepage_;

    CYString sponsor_;
    Address *sponsor$_;

    CYString author_;
    Address *author$_;

    CYString bugs_;
    CYString support_;
    NSMutableArray *tags_;
    NSString *role_;

    NSMutableDictionary *metadata_;
    _transient NSDate *firstSeen_;
    _transient NSDate *lastSeen_;
    bool subscribed_;
}

- (Package *) initWithVersion:(pkgCache::VerIterator)version withZone:(NSZone *)zone inPool:(apr_pool_t *)pool database:(Database *)database;
+ (Package *) packageWithIterator:(pkgCache::PkgIterator)iterator withZone:(NSZone *)zone inPool:(apr_pool_t *)pool database:(Database *)database;

- (pkgCache::PkgIterator) iterator;
- (void) parse;

- (NSString *) section;
- (NSString *) simpleSection;

- (NSString *) longSection;
- (NSString *) shortSection;

- (NSString *) uri;

- (Address *) maintainer;
- (size_t) size;
- (NSString *) longDescription;
- (NSString *) shortDescription;
- (unichar) index;

- (NSMutableDictionary *) metadata;
- (NSDate *) seen;
- (BOOL) subscribed;
- (BOOL) ignored;

- (NSString *) latest;
- (NSString *) installed;
- (BOOL) uninstalled;

- (BOOL) valid;
- (BOOL) upgradableAndEssential:(BOOL)essential;
- (BOOL) essential;
- (BOOL) broken;
- (BOOL) unfiltered;
- (BOOL) visible;

- (BOOL) half;
- (BOOL) halfConfigured;
- (BOOL) halfInstalled;
- (BOOL) hasMode;
- (NSString *) mode;

- (NSString *) id;
- (NSString *) name;
- (UIImage *) icon;
- (NSString *) homepage;
- (NSString *) depiction;
- (Address *) author;

- (NSString *) support;

- (NSArray *) files;
- (NSArray *) warnings;
- (NSArray *) applications;

- (Source *) source;
- (NSString *) role;

- (BOOL) matches:(NSString *)text;

- (bool) hasSupportingRole;
- (BOOL) hasTag:(NSString *)tag;
- (NSString *) primaryPurpose;
- (NSArray *) purposes;
- (bool) isCommercial;

- (CYString &) cyname;

- (uint32_t) compareBySection:(NSArray *)sections;

- (void) install;
- (void) remove;

- (bool) isUnfilteredAndSearchedForBy:(NSString *)search;
- (bool) isUnfilteredAndSelectedForBy:(NSString *)search;
- (bool) isInstalledAndUnfiltered:(NSNumber *)number;
- (bool) isVisibleInSection:(NSString *)section;
- (bool) isVisibleInSource:(Source *)source;

@end

uint32_t PackageChangesRadix(Package *self, void *) {
    union {
        uint32_t key;

        struct {
            uint32_t timestamp : 30;
            uint32_t ignored : 1;
            uint32_t upgradable : 1;
        } bits;
    } value;

    bool upgradable([self upgradableAndEssential:YES]);
    value.bits.upgradable = upgradable ? 1 : 0;

    if (upgradable) {
        value.bits.timestamp = 0;
        value.bits.ignored = [self ignored] ? 0 : 1;
        value.bits.upgradable = 1;
    } else {
        value.bits.timestamp = static_cast<uint32_t>([[self seen] timeIntervalSince1970]) >> 2;
        value.bits.ignored = 0;
        value.bits.upgradable = 0;
    }

    return _not(uint32_t) - value.key;
}

_finline static void Stifle(uint8_t &value) {
}

uint32_t PackagePrefixRadix(Package *self, void *context) {
    size_t offset(reinterpret_cast<size_t>(context));
    CYString &name([self cyname]);

    size_t size(name.size());
    if (size == 0)
        return 0;
    char *text(name.data());

    size_t zeros;
    if (!isdigit(text[0]))
        zeros = 0;
    else {
        size_t digits(1);
        while (size != digits && isdigit(text[digits]))
            if (++digits == 4)
                break;
        zeros = 4 - digits;
    }

    uint8_t data[4];

    // 0.607997

    if (offset == 0 && zeros != 0) {
        memset(data, '0', zeros);
        memcpy(data + zeros, text, 4 - zeros);
    } else {
        /* XXX: there's some danger here if you request a non-zero offset < 4 and it gets zero padded */
        if (size <= offset - zeros)
            return 0;

        text += offset - zeros;
        size -= offset - zeros;

        if (size >= 4)
            memcpy(data, text, 4);
        else {
            memcpy(data, text, size);
            memset(data + size, 0, 4 - size);
        }

        for (size_t i(0); i != 4; ++i)
            if (isalpha(data[i]))
                data[i] |= 0x20;
    }

    if (offset == 0)
        if (data[0] == '@')
            data[0] = 0x7f;
        else
            data[0] = (data[0] & 0x1f) | "\x80\x00\xc0\x40"[data[0] >> 6];

    /* XXX: ntohl may be more honest */
    return OSSwapInt32(*reinterpret_cast<uint32_t *>(data));
}

CYString &(*PackageName)(Package *self, SEL sel);

CFComparisonResult PackageNameCompare(Package *lhs, Package *rhs, void *arg) {
    _profile(PackageNameCompare)
        CYString &lhi(PackageName(lhs, @selector(cyname)));
        CYString &rhi(PackageName(rhs, @selector(cyname)));
        CFStringRef lhn(lhi), rhn(rhi);

        if (lhn == NULL)
            return rhn == NULL ? NSOrderedSame : NSOrderedAscending;
        else if (rhn == NULL)
            return NSOrderedDescending;

        _profile(PackageNameCompare$NumbersLast)
            if (!lhi.empty() && !rhi.empty()) {
                UniChar lhc(CFStringGetCharacterAtIndex(lhn, 0));
                UniChar rhc(CFStringGetCharacterAtIndex(rhn, 0));
                bool lha(CFUniCharIsMemberOf(lhc, kCFUniCharLetterCharacterSet));
                if (lha != CFUniCharIsMemberOf(rhc, kCFUniCharLetterCharacterSet))
                    return lha ? NSOrderedAscending : NSOrderedDescending;
            }
        _end

        CFIndex length = CFStringGetLength(lhn);

        _profile(PackageNameCompare$Compare)
            return CFStringCompareWithOptionsAndLocale(lhn, rhn, CFRangeMake(0, length), LaxCompareFlags_, Locale_);
        _end
    _end
}

CFComparisonResult PackageNameCompare_(Package **lhs, Package **rhs, void *context) {
    return PackageNameCompare(*lhs, *rhs, context);
}

struct PackageNameOrdering :
    std::binary_function<Package *, Package *, bool>
{
    _finline bool operator ()(Package *lhs, Package *rhs) const {
        return PackageNameCompare(lhs, rhs, NULL) == NSOrderedAscending;
    }
};

@implementation Package

- (NSString *) description {
    return [NSString stringWithFormat:@"<Package:%@>", static_cast<NSString *>(name_)];
}

- (void) dealloc {
    if (source_ != nil)
        [source_ release];

    if (latest_ != nil)
        [latest_ release];

    if (sponsor$_ != nil)
        [sponsor$_ release];
    if (author$_ != nil)
        [author$_ release];
    if (tags_ != nil)
        [tags_ release];
    if (role_ != nil)
        [role_ release];

    if (metadata_ != nil)
        [metadata_ release];

    [super dealloc];
}

+ (NSString *) webScriptNameForSelector:(SEL)selector {
    if (selector == @selector(hasTag:))
        return @"hasTag";
    else
        return nil;
}

+ (BOOL) isSelectorExcludedFromWebScript:(SEL)selector {
    return [self webScriptNameForSelector:selector] == nil;
}

+ (NSArray *) _attributeKeys {
    return [NSArray arrayWithObjects:@"applications", @"author", @"depiction", @"longDescription", @"essential", @"homepage", @"icon", @"id", @"installed", @"latest", @"longSection", @"maintainer", @"mode", @"name", @"purposes", @"section", @"shortDescription", @"shortSection", @"simpleSection", @"size", @"source", @"sponsor", @"support", @"warnings", nil];
}

- (NSArray *) attributeKeys {
    return [[self class] _attributeKeys];
}

+ (BOOL) isKeyExcludedFromWebScript:(const char *)name {
    return ![[self _attributeKeys] containsObject:[NSString stringWithUTF8String:name]] && [super isKeyExcludedFromWebScript:name];
}

- (void) parse {
    if (parsed_)
        return;
    parsed_ = true;
    if (file_.end())
        return;

    _profile(Package$parse)
        pkgRecords::Parser *parser;

        _profile(Package$parse$Lookup)
            parser = &[database_ records]->Lookup(file_);
        _end

        CYString website;

        _profile(Package$parse$Find)
            struct {
                const char *name_;
                CYString *value_;
            } names[] = {
                {"icon", &icon_},
                {"depiction", &depiction_},
                {"homepage", &homepage_},
                {"website", &website},
                {"bugs", &bugs_},
                {"support", &support_},
                {"sponsor", &sponsor_},
                {"author", &author_},
            };

            for (size_t i(0); i != sizeof(names) / sizeof(names[0]); ++i) {
                const char *start, *end;

                if (parser->Find(names[i].name_, start, end)) {
                    CYString &value(*names[i].value_);
                    _profile(Package$parse$Value)
                        value.set(pool_, start, end - start);
                    _end
                }
            }
        _end

        _profile(Package$parse$Tagline)
            const char *start, *end;
            if (parser->ShortDesc(start, end)) {
                const char *stop(reinterpret_cast<const char *>(memchr(start, '\n', end - start)));
                if (stop == NULL)
                    stop = end;
                while (stop != start && stop[-1] == '\r')
                    --stop;
                tagline_.set(pool_, start, stop - start);
            }
        _end

        _profile(Package$parse$Retain)
            if (homepage_.empty())
                homepage_ = website;
            if (homepage_ == depiction_)
                homepage_.clear();
        _end
    _end
}

- (Package *) initWithVersion:(pkgCache::VerIterator)version withZone:(NSZone *)zone inPool:(apr_pool_t *)pool database:(Database *)database {
    if ((self = [super init]) != nil) {
    _profile(Package$initWithVersion)
        era_ = [database era];
        pool_ = pool;

        version_ = version;

        _profile(Package$initWithVersion$ParentPkg)
            iterator_ = version.ParentPkg();
        _end

        database_ = database;

        _profile(Package$initWithVersion$Latest)
            const char *latest(StripVersion_(version_.VerStr()));
            latest_ = (NSString *) CFStringCreateWithBytes(kCFAllocatorDefault, reinterpret_cast<const uint8_t *>(latest), strlen(latest), kCFStringEncodingASCII, NO);
        _end

        pkgCache::VerIterator current;
        _profile(Package$initWithVersion$Versions)
            current = iterator_.CurrentVer();
            if (!current.end())
                installed_.set(pool_, StripVersion_(current.VerStr()));

            if (!version_.end())
                file_ = version_.FileList();
            else {
                pkgCache &cache([database_ cache]);
                file_ = pkgCache::VerFileIterator(cache, cache.VerFileP);
            }
        _end

        _profile(Package$initWithVersion$Name)
            id_.set(pool_, iterator_.Name());
            name_.set(pool, iterator_.Display());
        _end

        _profile(Package$initWithVersion$lowercaseString)
            char *data(id_.data());
            for (size_t i(0), e(id_.size()); i != e; ++i)
                // XXX: do not use tolower() as this is not locale-specific? :(
                data[i] |= 0x20;
        _end

        _profile(Package$initWithVersion$Tags)
            pkgCache::TagIterator tag(iterator_.TagList());
            if (!tag.end()) {
                tags_ = [[NSMutableArray alloc] initWithCapacity:8];
                do {
                    const char *name(tag.Name());
                    [tags_ addObject:[(NSString *)CYStringCreate(name) autorelease]];
                    if (role_ == nil && strncmp(name, "role::", 6) == 0 /*&& strcmp(name, "role::leaper") != 0*/)
                        role_ = (NSString *) CYStringCreate(name + 6);
                    ++tag;
                } while (!tag.end());
            }
        _end

        bool changed(false);

        _profile(Package$initWithVersion$Metadata)
            metadata_ = [Packages_ objectForKey:id_];

            if (metadata_ == nil) {
                firstSeen_ = now_;

                metadata_ = [[NSMutableDictionary dictionaryWithObjectsAndKeys:
                    firstSeen_, @"FirstSeen",
                    latest_, @"LastVersion",
                nil] mutableCopy];

                changed = true;
            } else {
                firstSeen_ = [metadata_ objectForKey:@"FirstSeen"];
                lastSeen_ = [metadata_ objectForKey:@"LastSeen"];

                if (NSNumber *subscribed = [metadata_ objectForKey:@"IsSubscribed"])
                    subscribed_ = [subscribed boolValue];

                NSString *version([metadata_ objectForKey:@"LastVersion"]);

                if (firstSeen_ == nil) {
                    firstSeen_ = lastSeen_ == nil ? now_ : lastSeen_;
                    [metadata_ setObject:firstSeen_ forKey:@"FirstSeen"];
                    changed = true;
                }

                if (version == nil) {
                    [metadata_ setObject:latest_ forKey:@"LastVersion"];
                    changed = true;
                } else if (![version isEqualToString:latest_]) {
                    [metadata_ setObject:latest_ forKey:@"LastVersion"];
                    lastSeen_ = now_;
                    [metadata_ setObject:lastSeen_ forKey:@"LastSeen"];
                    changed = true;
                }
            }

            metadata_ = [metadata_ retain];

            if (changed) {
                [Packages_ setObject:metadata_ forKey:id_];
                Changed_ = true;
            }
        _end

        _profile(Package$initWithVersion$Section)
            section_.set(pool_, iterator_.Section());
        _end

        _profile(Package$initWithVersion$hasTag)
            obsolete_ = [self hasTag:@"cydia::obsolete"];
            essential_ = ((iterator_->Flags & pkgCache::Flag::Essential) == 0 ? NO : YES) || [self hasTag:@"cydia::essential"];
        _end
    _end } return self;
}

+ (Package *) packageWithIterator:(pkgCache::PkgIterator)iterator withZone:(NSZone *)zone inPool:(apr_pool_t *)pool database:(Database *)database {
    pkgCache::VerIterator version;

    _profile(Package$packageWithIterator$GetCandidateVer)
        version = [database policy]->GetCandidateVer(iterator);
    _end

    if (version.end())
        return nil;

    return [[[Package alloc]
        initWithVersion:version
        withZone:zone
        inPool:pool
        database:database
    ] autorelease];
}

- (pkgCache::PkgIterator) iterator {
    return iterator_;
}

- (NSString *) section {
    if (section$_ == nil) {
        if (section_.empty())
            return nil;

        _profile(Package$section)
            std::replace(section_.data(), section_.data() + section_.size(), '_', ' ');
            NSString *name(section_);
            section$_ = [SectionMap_ objectForKey:name] ?: name;
        _end
    } return section$_;
}

- (NSString *) simpleSection {
    if (NSString *section = [self section])
        return Simplify(section);
    else
        return nil;
}

- (NSString *) longSection {
    return LocalizeSection([self section]);
}

- (NSString *) shortSection {
    return [[NSBundle mainBundle] localizedStringForKey:[self simpleSection] value:nil table:@"Sections"];
}

- (NSString *) uri {
    return nil;
#if 0
    pkgIndexFile *index;
    pkgCache::PkgFileIterator file(file_.File());
    if (![database_ list].FindIndex(file, index))
        return nil;
    return [NSString stringWithUTF8String:iterator_->Path];
    //return [NSString stringWithUTF8String:file.Site()];
    //return [NSString stringWithUTF8String:index->ArchiveURI(file.FileName()).c_str()];
#endif
}

- (Address *) maintainer {
    if (file_.end())
        return nil;
    pkgRecords::Parser *parser = &[database_ records]->Lookup(file_);
    const std::string &maintainer(parser->Maintainer());
    return maintainer.empty() ? nil : [Address addressWithString:[NSString stringWithUTF8String:maintainer.c_str()]];
}

- (size_t) size {
    return version_.end() ? 0 : version_->InstalledSize;
}

- (NSString *) longDescription {
@synchronized (database_) {
    if ([database_ era] != era_ || file_.end())
        return nil;

    pkgRecords::Parser *parser = &[database_ records]->Lookup(file_);
    NSString *description([NSString stringWithUTF8String:parser->LongDesc().c_str()]);

    NSArray *lines = [description componentsSeparatedByString:@"\n"];
    NSMutableArray *trimmed = [NSMutableArray arrayWithCapacity:([lines count] - 1)];
    if ([lines count] < 2)
        return nil;

    NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];
    for (size_t i(1), e([lines count]); i != e; ++i) {
        NSString *trim = [[lines objectAtIndex:i] stringByTrimmingCharactersInSet:whitespace];
        [trimmed addObject:trim];
    }

    return [trimmed componentsJoinedByString:@"\n"];
} }

- (NSString *) shortDescription {
    return tagline_;
}

- (unichar) index {
    _profile(Package$index)
        CFStringRef name((CFStringRef) [self name]);
        if (CFStringGetLength(name) == 0)
            return '#';
        UniChar character(CFStringGetCharacterAtIndex(name, 0));
        if (!CFUniCharIsMemberOf(character, kCFUniCharLetterCharacterSet))
            return '#';
        return toupper(character);
    _end
}

- (NSMutableDictionary *) metadata {
    return metadata_;
}

- (NSDate *) seen {
    if (subscribed_ && lastSeen_ != nil)
        return lastSeen_;
    return firstSeen_;
}

- (BOOL) subscribed {
    return subscribed_;
}

- (BOOL) ignored {
    NSDictionary *metadata([self metadata]);
    if (NSNumber *ignored = [metadata objectForKey:@"IsIgnored"])
        return [ignored boolValue];
    else
        return false;
}

- (NSString *) latest {
    return latest_;
}

- (NSString *) installed {
    return installed_;
}

- (BOOL) uninstalled {
    return installed_.empty();
}

- (BOOL) valid {
    return !version_.end();
}

- (BOOL) upgradableAndEssential:(BOOL)essential {
    _profile(Package$upgradableAndEssential)
        pkgCache::VerIterator current(iterator_.CurrentVer());
        if (current.end())
            return essential && essential_;
        else
            return !version_.end() && version_ != current;
    _end
}

- (BOOL) essential {
    return essential_;
}

- (BOOL) broken {
    return [database_ cache][iterator_].InstBroken();
}

- (BOOL) unfiltered {
    _profile(Package$unfiltered$obsolete)
        if (obsolete_)
            return false;
    _end

    _profile(Package$unfiltered$hasSupportingRole)
        if (![self hasSupportingRole])
            return false;
    _end

    return true;
}

- (BOOL) visible {
    if (![self unfiltered])
        return false;

    NSString *section([self section]);

    _profile(Package$visible$isSectionVisible)
        if (section != nil && !isSectionVisible(section))
            return false;
    _end

    return true;
}

- (BOOL) half {
    unsigned char current(iterator_->CurrentState);
    return current == pkgCache::State::HalfConfigured || current == pkgCache::State::HalfInstalled;
}

- (BOOL) halfConfigured {
    return iterator_->CurrentState == pkgCache::State::HalfConfigured;
}

- (BOOL) halfInstalled {
    return iterator_->CurrentState == pkgCache::State::HalfInstalled;
}

- (BOOL) hasMode {
    pkgDepCache::StateCache &state([database_ cache][iterator_]);
    return state.Mode != pkgDepCache::ModeKeep;
}

- (NSString *) mode {
    pkgDepCache::StateCache &state([database_ cache][iterator_]);

    switch (state.Mode) {
        case pkgDepCache::ModeDelete:
            if ((state.iFlags & pkgDepCache::Purge) != 0)
                return @"PURGE";
            else
                return @"REMOVE";
        case pkgDepCache::ModeKeep:
            if ((state.iFlags & pkgDepCache::ReInstall) != 0)
                return @"REINSTALL";
            /*else if ((state.iFlags & pkgDepCache::AutoKept) != 0)
                return nil;*/
            else
                return nil;
        case pkgDepCache::ModeInstall:
            /*if ((state.iFlags & pkgDepCache::ReInstall) != 0)
                return @"REINSTALL";
            else*/ switch (state.Status) {
                case -1:
                    return @"DOWNGRADE";
                case 0:
                    return @"INSTALL";
                case 1:
                    return @"UPGRADE";
                case 2:
                    return @"NEW_INSTALL";
                _nodefault
            }
        _nodefault
    }
}

- (NSString *) id {
    return id_;
}

- (NSString *) name {
    return name_.empty() ? id_ : name_;
}

- (UIImage *) icon {
    NSString *section = [self simpleSection];

    UIImage *icon(nil);
    if (!icon_.empty())
        if ([static_cast<id>(icon_) hasPrefix:@"file:///"])
            // XXX: correct escaping
            icon = [UIImage imageAtPath:[static_cast<id>(icon_) substringFromIndex:7]];
    if (icon == nil) if (section != nil)
        icon = [UIImage imageAtPath:[NSString stringWithFormat:@"%@/Sections/%@.png", App_, section]];
    if (icon == nil) if (Source *source = [self source]) if (NSString *dicon = [source defaultIcon])
        if ([dicon hasPrefix:@"file:///"])
            // XXX: correct escaping
            icon = [UIImage imageAtPath:[dicon substringFromIndex:7]];
    if (icon == nil)
        icon = [UIImage applicationImageNamed:@"unknown.png"];
    return icon;
}

- (NSString *) homepage {
    return homepage_;
}

- (NSString *) depiction {
    return !depiction_.empty() ? depiction_ : [[self source] depictionForPackage:id_];
}

- (Address *) sponsor {
    if (sponsor$_ == nil) {
        if (sponsor_.empty())
            return nil;
        sponsor$_ = [[Address addressWithString:sponsor_] retain];
    } return sponsor$_;
}

- (Address *) author {
    if (author$_ == nil) {
        if (author_.empty())
            return nil;
        author$_ = [[Address addressWithString:author_] retain];
    } return author$_;
}

- (NSString *) support {
    return !bugs_.empty() ? bugs_ : [[self source] supportForPackage:id_];
}

- (NSArray *) files {
    NSString *path = [NSString stringWithFormat:@"/var/lib/dpkg/info/%@.list", static_cast<NSString *>(id_)];
    NSMutableArray *files = [NSMutableArray arrayWithCapacity:128];

    std::ifstream fin;
    fin.open([path UTF8String]);
    if (!fin.is_open())
        return nil;

    std::string line;
    while (std::getline(fin, line))
        [files addObject:[NSString stringWithUTF8String:line.c_str()]];

    return files;
}

- (NSArray *) warnings {
    NSMutableArray *warnings([NSMutableArray arrayWithCapacity:4]);
    const char *name(iterator_.Name());

    size_t length(strlen(name));
    if (length < 2) invalid:
        [warnings addObject:UCLocalize("ILLEGAL_PACKAGE_IDENTIFIER")];
    else for (size_t i(0); i != length; ++i)
        if (
            /* XXX: technically this is not allowed */
            (name[i] < 'A' || name[i] > 'Z') &&
            (name[i] < 'a' || name[i] > 'z') &&
            (name[i] < '0' || name[i] > '9') &&
            (i == 0 || name[i] != '+' && name[i] != '-' && name[i] != '.')
        ) goto invalid;

    if (strcmp(name, "cydia") != 0) {
        bool cydia = false;
        bool user = false;
        bool _private = false;
        bool stash = false;

        bool repository = [[self section] isEqualToString:@"Repositories"];

        if (NSArray *files = [self files])
            for (NSString *file in files)
                if (!cydia && [file isEqualToString:@"/Applications/Cydia.app"])
                    cydia = true;
                else if (!user && [file isEqualToString:@"/User"])
                    user = true;
                else if (!_private && [file isEqualToString:@"/private"])
                    _private = true;
                else if (!stash && [file isEqualToString:@"/var/stash"])
                    stash = true;

        /* XXX: this is not sensitive enough. only some folders are valid. */
        if (cydia && !repository)
            [warnings addObject:[NSString stringWithFormat:UCLocalize("FILES_INSTALLED_TO"), @"Cydia.app"]];
        if (user)
            [warnings addObject:[NSString stringWithFormat:UCLocalize("FILES_INSTALLED_TO"), @"/User"]];
        if (_private)
            [warnings addObject:[NSString stringWithFormat:UCLocalize("FILES_INSTALLED_TO"), @"/private"]];
        if (stash)
            [warnings addObject:[NSString stringWithFormat:UCLocalize("FILES_INSTALLED_TO"), @"/var/stash"]];
    }

    return [warnings count] == 0 ? nil : warnings;
}

- (NSArray *) applications {
    NSString *me([[NSBundle mainBundle] bundleIdentifier]);

    NSMutableArray *applications([NSMutableArray arrayWithCapacity:2]);

    static Pcre application_r("^/Applications/(.*)\\.app/Info.plist$");
    if (NSArray *files = [self files])
        for (NSString *file in files)
            if (application_r(file)) {
                NSDictionary *info([NSDictionary dictionaryWithContentsOfFile:file]);
                NSString *id([info objectForKey:@"CFBundleIdentifier"]);
                if ([id isEqualToString:me])
                    continue;

                NSString *display([info objectForKey:@"CFBundleDisplayName"]);
                if (display == nil)
                    display = application_r[1];

                NSString *bundle([file stringByDeletingLastPathComponent]);
                NSString *icon([info objectForKey:@"CFBundleIconFile"]);
                if (icon == nil || [icon length] == 0)
                    icon = @"icon.png";
                NSURL *url([NSURL fileURLWithPath:[bundle stringByAppendingPathComponent:icon]]);

                NSMutableArray *application([NSMutableArray arrayWithCapacity:2]);
                [applications addObject:application];

                [application addObject:id];
                [application addObject:display];
                [application addObject:url];
            }

    return [applications count] == 0 ? nil : applications;
}

- (Source *) source {
    if (source_ == nil) {
        @synchronized (database_) {
            if ([database_ era] != era_ || file_.end())
                source_ = (Source *) [NSNull null];
            else
                source_ = [([database_ getSource:file_.File()] ?: (Source *) [NSNull null]) retain];
        }
    }

    return source_ == (Source *) [NSNull null] ? nil : source_;
}

- (NSString *) role {
    return role_;
}

- (BOOL) matches:(NSString *)text {
    if (text == nil)
        return NO;

    NSRange range;

    range = [[self id] rangeOfString:text options:MatchCompareOptions_];
    if (range.location != NSNotFound)
        return YES;

    range = [[self name] rangeOfString:text options:MatchCompareOptions_];
    if (range.location != NSNotFound)
        return YES;

    range = [[self shortDescription] rangeOfString:text options:MatchCompareOptions_];
    if (range.location != NSNotFound)
        return YES;

    return NO;
}

- (bool) hasSupportingRole {
    if (role_ == nil)
        return true;
    if ([role_ isEqualToString:@"enduser"])
        return true;
    if ([Role_ isEqualToString:@"User"])
        return false;
    if ([role_ isEqualToString:@"hacker"])
        return true;
    if ([Role_ isEqualToString:@"Hacker"])
        return false;
    if ([role_ isEqualToString:@"developer"])
        return true;
    if ([Role_ isEqualToString:@"Developer"])
        return false;
    _assert(false);
}

- (BOOL) hasTag:(NSString *)tag {
    return tags_ == nil ? NO : [tags_ containsObject:tag];
}

- (NSString *) primaryPurpose {
    for (NSString *tag in tags_)
        if ([tag hasPrefix:@"purpose::"])
            return [tag substringFromIndex:9];
    return nil;
}

- (NSArray *) purposes {
    NSMutableArray *purposes([NSMutableArray arrayWithCapacity:2]);
    for (NSString *tag in tags_)
        if ([tag hasPrefix:@"purpose::"])
            [purposes addObject:[tag substringFromIndex:9]];
    return [purposes count] == 0 ? nil : purposes;
}

- (bool) isCommercial {
    return [self hasTag:@"cydia::commercial"];
}

- (CYString &) cyname {
    return name_.empty() ? id_ : name_;
}

- (uint32_t) compareBySection:(NSArray *)sections {
    NSString *section([self section]);
    for (size_t i(0), e([sections count]); i != e; ++i) {
        if ([section isEqualToString:[[sections objectAtIndex:i] name]])
            return i;
    }

    return _not(uint32_t);
}

- (void) clear {
@synchronized (database_) {
    pkgProblemResolver *resolver = [database_ resolver];
    resolver->Clear(iterator_);

    pkgCacheFile &cache([database_ cache]);
    cache->SetReInstall(iterator_, false);
    cache->MarkKeep(iterator_, false);
} }

- (void) install {
@synchronized (database_) {
    pkgProblemResolver *resolver = [database_ resolver];
    resolver->Clear(iterator_);
    resolver->Protect(iterator_);

    pkgCacheFile &cache([database_ cache]);
    cache->SetReInstall(iterator_, false);
    cache->MarkInstall(iterator_, false);

    pkgDepCache::StateCache &state((*cache)[iterator_]);
    if (!state.Install())
        cache->SetReInstall(iterator_, true);
} }

- (void) remove {
@synchronized (database_) {
    pkgProblemResolver *resolver = [database_ resolver];
    resolver->Clear(iterator_);
    resolver->Remove(iterator_);
    resolver->Protect(iterator_);

    pkgCacheFile &cache([database_ cache]);
    cache->SetReInstall(iterator_, false);
    cache->MarkDelete(iterator_, true);
} }

- (bool) isUnfilteredAndSearchedForBy:(NSString *)search {
    _profile(Package$isUnfilteredAndSearchedForBy)
        bool value(true);

        _profile(Package$isUnfilteredAndSearchedForBy$Unfiltered)
            value &= [self unfiltered];
        _end

        _profile(Package$isUnfilteredAndSearchedForBy$Match)
            value &= [self matches:search];
        _end

        return value;
    _end
}

- (bool) isUnfilteredAndSelectedForBy:(NSString *)search {
    if ([search length] == 0)
        return false;

    _profile(Package$isUnfilteredAndSelectedForBy)
        bool value(true);

        _profile(Package$isUnfilteredAndSelectedForBy$Unfiltered)
            value &= [self unfiltered];
        _end

        _profile(Package$isUnfilteredAndSelectedForBy$Match)
            value &= [[self name] compare:search options:MatchCompareOptions_ range:NSMakeRange(0, [search length])] == NSOrderedSame;
        _end

        return value;
    _end
}

- (bool) isInstalledAndUnfiltered:(NSNumber *)number {
    return ![self uninstalled] && (![number boolValue] && ![role_ isEqualToString:@"cydia"] || [self unfiltered]);
}

- (bool) isVisibleInSection:(NSString *)name {
    NSString *section([self section]);

    return (
        name == nil ||
        section == nil && [name length] == 0 ||
        [name isEqualToString:section]
    ) && [self visible];
}

- (bool) isVisibleInSource:(Source *)source {
    return [self source] == source && [self visible];
}

@end
/* }}} */
/* Section Class {{{ */
@interface Section : NSObject {
    NSString *name_;
    unichar index_;
    size_t row_;
    size_t count_;
    NSString *localized_;
}

- (NSComparisonResult) compareByLocalized:(Section *)section;
- (Section *) initWithName:(NSString *)name localized:(NSString *)localized;
- (Section *) initWithName:(NSString *)name localize:(BOOL)localize;
- (Section *) initWithName:(NSString *)name row:(size_t)row localize:(BOOL)localize;
- (Section *) initWithIndex:(unichar)index row:(size_t)row;
- (NSString *) name;
- (unichar) index;

- (size_t) row;
- (size_t) count;

- (void) addToRow;
- (void) addToCount;

- (void) setCount:(size_t)count;
- (NSString *) localized;

@end

@implementation Section

- (void) dealloc {
    [name_ release];
    if (localized_ != nil)
        [localized_ release];
    [super dealloc];
}

- (NSComparisonResult) compareByLocalized:(Section *)section {
    NSString *lhs(localized_);
    NSString *rhs([section localized]);

    /*if ([lhs length] != 0 && [rhs length] != 0) {
        unichar lhc = [lhs characterAtIndex:0];
        unichar rhc = [rhs characterAtIndex:0];

        if (isalpha(lhc) && !isalpha(rhc))
            return NSOrderedAscending;
        else if (!isalpha(lhc) && isalpha(rhc))
            return NSOrderedDescending;
    }*/

    return [lhs compare:rhs options:LaxCompareOptions_];
}

- (Section *) initWithName:(NSString *)name localized:(NSString *)localized {
    if ((self = [self initWithName:name localize:NO]) != nil) {
        if (localized != nil)
            localized_ = [localized retain];
    } return self;
}

- (Section *) initWithName:(NSString *)name localize:(BOOL)localize {
    return [self initWithName:name row:0 localize:localize];
}

- (Section *) initWithName:(NSString *)name row:(size_t)row localize:(BOOL)localize {
    if ((self = [super init]) != nil) {
        name_ = [name retain];
        index_ = '\0';
        row_ = row;
        if (localize)
            localized_ = [LocalizeSection(name_) retain];
    } return self;
}

/* XXX: localize the index thingees */
- (Section *) initWithIndex:(unichar)index row:(size_t)row {
    if ((self = [super init]) != nil) {
        name_ = [[NSString stringWithCharacters:&index length:1] retain];
        index_ = index;
        row_ = row;
    } return self;
}

- (NSString *) name {
    return name_;
}

- (unichar) index {
    return index_;
}

- (size_t) row {
    return row_;
}

- (size_t) count {
    return count_;
}

- (void) addToRow {
    ++row_;
}

- (void) addToCount {
    ++count_;
}

- (void) setCount:(size_t)count {
    count_ = count;
}

- (NSString *) localized {
    return localized_;
}

@end
/* }}} */

static NSString *Colon_;
static NSString *Elision_;
static NSString *Error_;
static NSString *Warning_;

/* Database Implementation {{{ */
@implementation Database

+ (Database *) sharedInstance {
    static Database *instance;
    if (instance == nil)
        instance = [[Database alloc] init];
    return instance;
}

- (unsigned) era {
    return era_;
}

- (void) dealloc {
    // XXX: actually implement this thing
    _assert(false);
    NSRecycleZone(zone_);
    // XXX: malloc_destroy_zone(zone_);
    apr_pool_destroy(pool_);
    [super dealloc];
}

- (void) _readCydia:(NSNumber *)fd { _pooled
    __gnu_cxx::stdio_filebuf<char> ib([fd intValue], std::ios::in);
    std::istream is(&ib);
    std::string line;

    static Pcre finish_r("^finish:([^:]*)$");

    while (std::getline(is, line)) {
        const char *data(line.c_str());
        size_t size = line.size();
        lprintf("C:%s\n", data);

        if (finish_r(data, size)) {
            NSString *finish = finish_r[1];
            int index = [Finishes_ indexOfObject:finish];
            if (index != INT_MAX && index > Finish_)
                Finish_ = index;
        }
    }

    _assume(false);
}

- (void) _readStatus:(NSNumber *)fd { _pooled
    __gnu_cxx::stdio_filebuf<char> ib([fd intValue], std::ios::in);
    std::istream is(&ib);
    std::string line;

    static Pcre conffile_r("^status: [^ ]* : conffile-prompt : (.*?) *$");
    static Pcre pmstatus_r("^([^:]*):([^:]*):([^:]*):(.*)$");

    while (std::getline(is, line)) {
        const char *data(line.c_str());
        size_t size(line.size());
        lprintf("S:%s\n", data);

        if (conffile_r(data, size)) {
            [delegate_ setConfigurationData:conffile_r[1]];
        } else if (strncmp(data, "status: ", 8) == 0) {
            NSString *string = [NSString stringWithUTF8String:(data + 8)];
            [delegate_ setProgressTitle:string];
        } else if (pmstatus_r(data, size)) {
            std::string type([pmstatus_r[1] UTF8String]);
            NSString *id = pmstatus_r[2];

            float percent([pmstatus_r[3] floatValue]);
            [delegate_ setProgressPercent:(percent / 100)];

            NSString *string = pmstatus_r[4];

            if (type == "pmerror")
                [delegate_ performSelectorOnMainThread:@selector(_setProgressErrorPackage:)
                    withObject:[NSArray arrayWithObjects:string, id, nil]
                    waitUntilDone:YES
                ];
            else if (type == "pmstatus") {
                [delegate_ setProgressTitle:string];
            } else if (type == "pmconffile")
                [delegate_ setConfigurationData:string];
            else
                lprintf("E:unknown pmstatus\n");
        } else
            lprintf("E:unknown status\n");
    }

    _assume(false);
}

- (void) _readOutput:(NSNumber *)fd { _pooled
    __gnu_cxx::stdio_filebuf<char> ib([fd intValue], std::ios::in);
    std::istream is(&ib);
    std::string line;

    while (std::getline(is, line)) {
        lprintf("O:%s\n", line.c_str());
        [delegate_ addProgressOutput:[NSString stringWithUTF8String:line.c_str()]];
    }

    _assume(false);
}

- (FILE *) input {
    return input_;
}

- (Package *) packageWithName:(NSString *)name {
@synchronized (self) {
    if (static_cast<pkgDepCache *>(cache_) == NULL)
        return nil;
    pkgCache::PkgIterator iterator(cache_->FindPkg([name UTF8String]));
    return iterator.end() ? nil : [Package packageWithIterator:iterator withZone:NULL inPool:pool_ database:self];
} }

- (id) init {
    if ((self = [super init]) != nil) {
        policy_ = NULL;
        records_ = NULL;
        resolver_ = NULL;
        fetcher_ = NULL;
        lock_ = NULL;

        zone_ = NSCreateZone(1024 * 1024, 256 * 1024, NO);
        apr_pool_create(&pool_, NULL);

        packages_ = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);

        int fds[2];

        _assert(pipe(fds) != -1);
        cydiafd_ = fds[1];

        _config->Set("APT::Keep-Fds::", cydiafd_);
        setenv("CYDIA", [[[[NSNumber numberWithInt:cydiafd_] stringValue] stringByAppendingString:@" 1"] UTF8String], _not(int));

        [NSThread
            detachNewThreadSelector:@selector(_readCydia:)
            toTarget:self
            withObject:[NSNumber numberWithInt:fds[0]]
        ];

        _assert(pipe(fds) != -1);
        statusfd_ = fds[1];

        [NSThread
            detachNewThreadSelector:@selector(_readStatus:)
            toTarget:self
            withObject:[NSNumber numberWithInt:fds[0]]
        ];

        _assert(pipe(fds) != -1);
        _assert(dup2(fds[0], 0) != -1);
        _assert(close(fds[0]) != -1);

        input_ = fdopen(fds[1], "a");

        _assert(pipe(fds) != -1);
        _assert(dup2(fds[1], 1) != -1);
        _assert(close(fds[1]) != -1);

        [NSThread
            detachNewThreadSelector:@selector(_readOutput:)
            toTarget:self
            withObject:[NSNumber numberWithInt:fds[0]]
        ];
    } return self;
}

- (pkgCacheFile &) cache {
    return cache_;
}

- (pkgDepCache::Policy *) policy {
    return policy_;
}

- (pkgRecords *) records {
    return records_;
}

- (pkgProblemResolver *) resolver {
    return resolver_;
}

- (pkgAcquire &) fetcher {
    return *fetcher_;
}

- (pkgSourceList &) list {
    return *list_;
}

- (NSArray *) packages {
    return (NSArray *) packages_;
}

- (NSArray *) sources {
    NSMutableArray *sources([NSMutableArray arrayWithCapacity:sources_.size()]);
    for (SourceMap::const_iterator i(sources_.begin()); i != sources_.end(); ++i)
        [sources addObject:i->second];
    return sources;
}

- (NSArray *) issues {
    if (cache_->BrokenCount() == 0)
        return nil;

    NSMutableArray *issues([NSMutableArray arrayWithCapacity:4]);

    for (Package *package in [self packages]) {
        if (![package broken])
            continue;
        pkgCache::PkgIterator pkg([package iterator]);

        NSMutableArray *entry([NSMutableArray arrayWithCapacity:4]);
        [entry addObject:[package name]];
        [issues addObject:entry];

        pkgCache::VerIterator ver(cache_[pkg].InstVerIter(cache_));
        if (ver.end())
            continue;

        for (pkgCache::DepIterator dep(ver.DependsList()); !dep.end(); ) {
            pkgCache::DepIterator start;
            pkgCache::DepIterator end;
            dep.GlobOr(start, end); // ++dep

            if (!cache_->IsImportantDep(end))
                continue;
            if ((cache_[end] & pkgDepCache::DepGInstall) != 0)
                continue;

            NSMutableArray *failure([NSMutableArray arrayWithCapacity:4]);
            [entry addObject:failure];
            [failure addObject:[NSString stringWithUTF8String:start.DepType()]];

            NSString *name([NSString stringWithUTF8String:start.TargetPkg().Name()]);
            if (Package *package = [self packageWithName:name])
                name = [package name];
            [failure addObject:name];

            pkgCache::PkgIterator target(start.TargetPkg());
            if (target->ProvidesList != 0)
                [failure addObject:@"?"];
            else {
                pkgCache::VerIterator ver(cache_[target].InstVerIter(cache_));
                if (!ver.end())
                    [failure addObject:[NSString stringWithUTF8String:ver.VerStr()]];
                else if (!cache_[target].CandidateVerIter(cache_).end())
                    [failure addObject:@"-"];
                else if (target->ProvidesList == 0)
                    [failure addObject:@"!"];
                else
                    [failure addObject:@"%"];
            }

            _forever {
                if (start.TargetVer() != 0)
                    [failure addObject:[NSString stringWithFormat:@"%s %s", start.CompType(), start.TargetVer()]];
                if (start == end)
                    break;
                ++start;
            }
        }
    }

    return issues;
}

- (bool) popErrorWithTitle:(NSString *)title {
    bool fatal(false);
    std::string message;

    while (!_error->empty()) {
        std::string error;
        bool warning(!_error->PopMessage(error));
        if (!warning)
            fatal = true;
        for (;;) {
            size_t size(error.size());
            if (size == 0 || error[size - 1] != '\n')
                break;
            error.resize(size - 1);
        }
        lprintf("%c:[%s]\n", warning ? 'W' : 'E', error.c_str());

        if (!message.empty())
            message += "\n\n";
        message += error;
    }

    if (fatal && !message.empty())
        [delegate_ _setProgressError:[NSString stringWithUTF8String:message.c_str()] withTitle:[NSString stringWithFormat:Colon_, fatal ? Error_ : Warning_, title]];

    return fatal;
}

- (bool) popErrorWithTitle:(NSString *)title forOperation:(bool)success {
    return [self popErrorWithTitle:title] || !success;
}

- (void) reloadData { CYPoolStart() {
@synchronized (self) {
    ++era_;

    CFArrayApplyFunction(packages_, CFRangeMake(0, CFArrayGetCount(packages_)), reinterpret_cast<CFArrayApplierFunction>(&CFRelease), NULL);
    CFArrayRemoveAllValues(packages_);

    sources_.clear();

    _error->Discard();

    delete list_;
    list_ = NULL;
    manager_ = NULL;
    delete lock_;
    lock_ = NULL;
    delete fetcher_;
    fetcher_ = NULL;
    delete resolver_;
    resolver_ = NULL;
    delete records_;
    records_ = NULL;
    delete policy_;
    policy_ = NULL;

    if (now_ != nil) {
        [now_ release];
        now_ = nil;
    }

    cache_.Close();

    apr_pool_clear(pool_);
    NSRecycleZone(zone_);

    int chk(creat("/tmp/cydia.chk", 0644));
    if (chk != -1)
        close(chk);

    NSString *title(UCLocalize("DATABASE"));

    _trace();
    if (!cache_.Open(progress_, true)) { pop:
        std::string error;
        bool warning(!_error->PopMessage(error));
        lprintf("cache_.Open():[%s]\n", error.c_str());

        if (error == "dpkg was interrupted, you must manually run 'dpkg --configure -a' to correct the problem. ")
            [delegate_ repairWithSelector:@selector(configure)];
        else if (error == "The package lists or status file could not be parsed or opened.")
            [delegate_ repairWithSelector:@selector(update)];
        // else if (error == "Could not open lock file /var/lib/dpkg/lock - open (13 Permission denied)")
        // else if (error == "Could not get lock /var/lib/dpkg/lock - open (35 Resource temporarily unavailable)")
        // else if (error == "The list of sources could not be read.")
        else
            [delegate_ _setProgressError:[NSString stringWithUTF8String:error.c_str()] withTitle:[NSString stringWithFormat:Colon_, warning ? Warning_ : Error_, title]];

        if (warning)
            goto pop;
        _error->Discard();
        return;
    }
    _trace();

    unlink("/tmp/cydia.chk");

    now_ = [[NSDate date] retain];

    policy_ = new pkgDepCache::Policy();
    records_ = new pkgRecords(cache_);
    resolver_ = new pkgProblemResolver(cache_);
    fetcher_ = new pkgAcquire(&status_);
    lock_ = NULL;

    list_ = new pkgSourceList();
    if ([self popErrorWithTitle:title forOperation:list_->ReadMainList()])
        return;

    if (cache_->DelCount() != 0 || cache_->InstCount() != 0) {
        [delegate_ _setProgressError:@"COUNTS_NONZERO_EX" withTitle:title];
        return;
    }

    if ([self popErrorWithTitle:title forOperation:pkgApplyStatus(cache_)])
        return;

    if (cache_->BrokenCount() != 0) {
        if ([self popErrorWithTitle:title forOperation:pkgFixBroken(cache_)])
            return;

        if (cache_->BrokenCount() != 0) {
            [delegate_ _setProgressError:@"STILL_BROKEN_EX" withTitle:title];
            return;
        }

        if ([self popErrorWithTitle:title forOperation:pkgMinimizeUpgrade(cache_)])
            return;
    }

    for (pkgSourceList::const_iterator source = list_->begin(); source != list_->end(); ++source) {
        std::vector<pkgIndexFile *> *indices = (*source)->GetIndexFiles();
        for (std::vector<pkgIndexFile *>::const_iterator index = indices->begin(); index != indices->end(); ++index)
            // XXX: this could be more intelligent
            if (dynamic_cast<debPackagesIndex *>(*index) != NULL) {
                pkgCache::PkgFileIterator cached((*index)->FindInCache(cache_));
                if (!cached.end())
                    sources_[cached->ID] = [[[Source alloc] initWithMetaIndex:*source inPool:pool_] autorelease];
            }
    }

    {
        /*std::vector<Package *> packages;
        packages.reserve(std::max(10000U, [packages_ count] + 1000));
        [packages_ release];
        packages_ = nil;*/

        _trace();

        for (pkgCache::PkgIterator iterator = cache_->PkgBegin(); !iterator.end(); ++iterator)
            if (Package *package = [Package packageWithIterator:iterator withZone:zone_ inPool:pool_ database:self])
                //packages.push_back(package);
                CFArrayAppendValue(packages_, [package retain]);

        _trace();

        /*if (packages.empty())
            packages_ = [[NSArray alloc] init];
        else
            packages_ = [[NSArray alloc] initWithObjects:&packages.front() count:packages.size()];
        _trace();*/

        [(NSMutableArray *) packages_ radixSortUsingFunction:reinterpret_cast<SKRadixFunction>(&PackagePrefixRadix) withContext:reinterpret_cast<void *>(16)];
        [(NSMutableArray *) packages_ radixSortUsingFunction:reinterpret_cast<SKRadixFunction>(&PackagePrefixRadix) withContext:reinterpret_cast<void *>(4)];
        [(NSMutableArray *) packages_ radixSortUsingFunction:reinterpret_cast<SKRadixFunction>(&PackagePrefixRadix) withContext:reinterpret_cast<void *>(0)];

        /*_trace();
        PrintTimes();
        _trace();*/

        _trace();

        /*if (!packages.empty())
            CFQSortArray(&packages.front(), packages.size(), sizeof(packages.front()), reinterpret_cast<CFComparatorFunction>(&PackageNameCompare_), NULL);*/
        //std::sort(packages.begin(), packages.end(), PackageNameOrdering());

        //CFArraySortValues((CFMutableArrayRef) packages_, CFRangeMake(0, [packages_ count]), reinterpret_cast<CFComparatorFunction>(&PackageNameCompare), NULL);

        CFArrayInsertionSortValues(packages_, CFRangeMake(0, CFArrayGetCount(packages_)), reinterpret_cast<CFComparatorFunction>(&PackageNameCompare), NULL);

        //[packages_ sortUsingFunction:reinterpret_cast<NSComparisonResult (*)(id, id, void *)>(&PackageNameCompare) context:NULL];

        _trace();
    }
} } CYPoolEnd() _trace(); }

- (void) clear {
@synchronized (self) {
    delete resolver_;
    resolver_ = new pkgProblemResolver(cache_);

    for (pkgCache::PkgIterator iterator(cache_->PkgBegin()); !iterator.end(); ++iterator) {
        if (!cache_[iterator].Keep()) {
            cache_->MarkKeep(iterator, false);
            cache_->SetReInstall(iterator, false);
        }
    }
} }

- (void) configure {
    NSString *dpkg = [NSString stringWithFormat:@"dpkg --configure -a --status-fd %u", statusfd_];
    system([dpkg UTF8String]);
}

- (bool) clean {
    // XXX: I don't remember this condition
    if (lock_ != NULL)
        return false;

    FileFd Lock;
    Lock.Fd(GetLock(_config->FindDir("Dir::Cache::Archives") + "lock"));

    NSString *title(UCLocalize("CLEAN_ARCHIVES"));

    if ([self popErrorWithTitle:title])
        return false;

    pkgAcquire fetcher;
    fetcher.Clean(_config->FindDir("Dir::Cache::Archives"));

    class LogCleaner :
        public pkgArchiveCleaner
    {
      protected:
        virtual void Erase(const char *File, std::string Pkg, std::string Ver, struct stat &St) {
            unlink(File);
        }
    } cleaner;

    if ([self popErrorWithTitle:title forOperation:cleaner.Go(_config->FindDir("Dir::Cache::Archives") + "partial/", cache_)])
        return false;

    return true;
}

- (bool) prepare {
    fetcher_->Shutdown();

    pkgRecords records(cache_);

    lock_ = new FileFd();
    lock_->Fd(GetLock(_config->FindDir("Dir::Cache::Archives") + "lock"));

    NSString *title(UCLocalize("PREPARE_ARCHIVES"));

    if ([self popErrorWithTitle:title])
        return false;

    pkgSourceList list;
    if ([self popErrorWithTitle:title forOperation:list.ReadMainList()])
        return false;

    manager_ = (_system->CreatePM(cache_));
    if ([self popErrorWithTitle:title forOperation:manager_->GetArchives(fetcher_, &list, &records)])
        return false;

    return true;
}

- (void) perform {
    NSString *title(UCLocalize("PERFORM_SELECTIONS"));

    NSMutableArray *before = [NSMutableArray arrayWithCapacity:16]; {
        pkgSourceList list;
        if ([self popErrorWithTitle:title forOperation:list.ReadMainList()])
            return;
        for (pkgSourceList::const_iterator source = list.begin(); source != list.end(); ++source)
            [before addObject:[NSString stringWithUTF8String:(*source)->GetURI().c_str()]];
    }

    if (fetcher_->Run(PulseInterval_) != pkgAcquire::Continue) {
        _trace();
        return;
    }

    bool failed = false;
    for (pkgAcquire::ItemIterator item = fetcher_->ItemsBegin(); item != fetcher_->ItemsEnd(); item++) {
        if ((*item)->Status == pkgAcquire::Item::StatDone && (*item)->Complete)
            continue;
        if ((*item)->Status == pkgAcquire::Item::StatIdle)
            continue;

        std::string uri = (*item)->DescURI();
        std::string error = (*item)->ErrorText;

        lprintf("pAf:%s:%s\n", uri.c_str(), error.c_str());
        failed = true;

        [delegate_ performSelectorOnMainThread:@selector(_setProgressErrorPackage:)
            withObject:[NSArray arrayWithObjects:
                [NSString stringWithUTF8String:error.c_str()],
            nil]
            waitUntilDone:YES
        ];
    }

    if (failed) {
        _trace();
        return;
    }

    _system->UnLock();
    pkgPackageManager::OrderResult result = manager_->DoInstall(statusfd_);

    if (_error->PendingError()) {
        _trace();
        return;
    }

    if (result == pkgPackageManager::Failed) {
        _trace();
        return;
    }

    if (result != pkgPackageManager::Completed) {
        _trace();
        return;
    }

    NSMutableArray *after = [NSMutableArray arrayWithCapacity:16]; {
        pkgSourceList list;
        if ([self popErrorWithTitle:title forOperation:list.ReadMainList()])
            return;
        for (pkgSourceList::const_iterator source = list.begin(); source != list.end(); ++source)
            [after addObject:[NSString stringWithUTF8String:(*source)->GetURI().c_str()]];
    }

    if (![before isEqualToArray:after])
        [self update];
}

- (bool) upgrade {
    NSString *title(UCLocalize("UPGRADE"));
    if ([self popErrorWithTitle:title forOperation:pkgDistUpgrade(cache_)])
        return false;
    return true;
}

- (void) update {
    [self updateWithStatus:status_];
}

- (void) updateWithStatus:(Status &)status {
    _transient NSObject<ProgressDelegate> *delegate(status.getDelegate());
    NSString *title(UCLocalize("REFRESHING_DATA"));

    pkgSourceList list;
    if (!list.ReadMainList())
        [delegate _setProgressError:@"Unable to read source list." withTitle:title];

    FileFd lock;
    lock.Fd(GetLock(_config->FindDir("Dir::State::Lists") + "lock"));
    if ([self popErrorWithTitle:title])
        return;

    if ([self popErrorWithTitle:title forOperation:ListUpdate(status, list, PulseInterval_)])
        /* XXX: ignore this because users suck and don't understand why refreshing is important: return */
        /* XXX: why the hell is an empty if statement a clang error? */ (void) 0;

    [Metadata_ setObject:[NSDate date] forKey:@"LastUpdate"];
    Changed_ = true;
}

- (void) setDelegate:(id)delegate {
    delegate_ = delegate;
    status_.setDelegate(delegate);
    progress_.setDelegate(delegate);
}

- (Source *) getSource:(pkgCache::PkgFileIterator)file {
    SourceMap::const_iterator i(sources_.find(file->ID));
    return i == sources_.end() ? nil : i->second;
}

@end
/* }}} */

/* Confirmation Controller {{{ */
bool DepSubstrate(const pkgCache::VerIterator &iterator) {
    if (!iterator.end())
        for (pkgCache::DepIterator dep(iterator.DependsList()); !dep.end(); ++dep) {
            if (dep->Type != pkgCache::Dep::Depends && dep->Type != pkgCache::Dep::PreDepends)
                continue;
            pkgCache::PkgIterator package(dep.TargetPkg());
            if (package.end())
                continue;
            if (strcmp(package.Name(), "mobilesubstrate") == 0)
                return true;
        }

    return false;
}
/* }}} */

/* Web Scripting {{{ */
@interface CydiaObject : NSObject {
    id indirect_;
    _transient id delegate_;
}

- (id) initWithDelegate:(IndirectDelegate *)indirect;
@end

@implementation CydiaObject

- (void) dealloc {
    [indirect_ release];
    [super dealloc];
}

- (id) initWithDelegate:(IndirectDelegate *)indirect {
    if ((self = [super init]) != nil) {
        indirect_ = [indirect retain];
    } return self;
}

- (void) setDelegate:(id)delegate {
    delegate_ = delegate;
}

+ (NSArray *) _attributeKeys {
    return [NSArray arrayWithObjects:@"device", @"firewire", @"imei", @"mac", @"serial", nil];
}

- (NSArray *) attributeKeys {
    return [[self class] _attributeKeys];
}

+ (BOOL) isKeyExcludedFromWebScript:(const char *)name {
    return ![[self _attributeKeys] containsObject:[NSString stringWithUTF8String:name]] && [super isKeyExcludedFromWebScript:name];
}

- (NSString *) device {
    return [[UIDevice currentDevice] uniqueIdentifier];
}

#if 0 // XXX: implement!
- (NSString *) mac {
    if (![indirect_ promptForSensitive:@"Mac Address"])
        return nil;
}

- (NSString *) serial {
    if (![indirect_ promptForSensitive:@"Serial #"])
        return nil;
}

- (NSString *) firewire {
    if (![indirect_ promptForSensitive:@"Firewire GUID"])
        return nil;
}

- (NSString *) imei {
    if (![indirect_ promptForSensitive:@"IMEI"])
        return nil;
}
#endif

+ (NSString *) webScriptNameForSelector:(SEL)selector {
    if (selector == @selector(close))
        return @"close";
    else if (selector == @selector(getInstalledPackages))
        return @"getInstalledPackages";
    else if (selector == @selector(getPackageById:))
        return @"getPackageById";
    else if (selector == @selector(installPackages:))
        return @"installPackages";
    else if (selector == @selector(setButtonImage:withStyle:toFunction:))
        return @"setButtonImage";
    else if (selector == @selector(setButtonTitle:withStyle:toFunction:))
        return @"setButtonTitle";
    else if (selector == @selector(setPopupHook:))
        return @"setPopupHook";
    else if (selector == @selector(setSpecial:))
        return @"setSpecial";
    else if (selector == @selector(setToken:))
        return @"setToken";
    else if (selector == @selector(setViewportWidth:))
        return @"setViewportWidth";
    else if (selector == @selector(supports:))
        return @"supports";
    else if (selector == @selector(stringWithFormat:arguments:))
        return @"format";
    else if (selector == @selector(localizedStringForKey:value:table:))
        return @"localize";
    else if (selector == @selector(du:))
        return @"du";
    else if (selector == @selector(statfs:))
        return @"statfs";
    else
        return nil;
}

+ (BOOL) isSelectorExcludedFromWebScript:(SEL)selector {
    return [self webScriptNameForSelector:selector] == nil;
}

- (BOOL) supports:(NSString *)feature {
    return [feature isEqualToString:@"window.open"];
}

- (NSArray *) getInstalledPackages {
    NSArray *packages([[Database sharedInstance] packages]);
    NSMutableArray *installed([NSMutableArray arrayWithCapacity:[packages count]]);
    for (Package *package in packages)
        if ([package installed] != nil)
            [installed addObject:package];
    return installed;
}

- (Package *) getPackageById:(NSString *)id {
    Package *package([[Database sharedInstance] packageWithName:id]);
    [package parse];
    return package;
}

- (NSArray *) statfs:(NSString *)path {
    struct statfs stat;

    if (path == nil || statfs([path UTF8String], &stat) == -1)
        return nil;

    return [NSArray arrayWithObjects:
        [NSNumber numberWithUnsignedLong:stat.f_bsize],
        [NSNumber numberWithUnsignedLong:stat.f_blocks],
        [NSNumber numberWithUnsignedLong:stat.f_bfree],
    nil];
}

- (NSNumber *) du:(NSString *)path {
    NSNumber *value(nil);

    int fds[2];
    _assert(pipe(fds) != -1);

    pid_t pid(ExecFork());
    if (pid == 0) {
        _assert(dup2(fds[1], 1) != -1);
        _assert(close(fds[0]) != -1);
        _assert(close(fds[1]) != -1);
        /* XXX: this should probably not use du */
        execl("/usr/libexec/cydia/du", "du", "-s", [path UTF8String], NULL);
        exit(1);
        _assert(false);
    }

    _assert(close(fds[1]) != -1);

    if (FILE *du = fdopen(fds[0], "r")) {
        char line[1024];
        while (fgets(line, sizeof(line), du) != NULL) {
            size_t length(strlen(line));
            while (length != 0 && line[length - 1] == '\n')
                line[--length] = '\0';
            if (char *tab = strchr(line, '\t')) {
                *tab = '\0';
                value = [NSNumber numberWithUnsignedLong:strtoul(line, NULL, 0)];
            }
        }

        fclose(du);
    } else _assert(close(fds[0]));

    int status;
  wait:
    if (waitpid(pid, &status, 0) == -1)
        if (errno == EINTR)
            goto wait;
        else _assert(false);

    return value;
}

- (void) close {
    [indirect_ close];
}

- (void) installPackages:(NSArray *)packages {
    [delegate_ performSelectorOnMainThread:@selector(installPackages:) withObject:packages waitUntilDone:NO];
}

- (void) setButtonImage:(NSString *)button withStyle:(NSString *)style toFunction:(id)function {
    [indirect_ setButtonImage:button withStyle:style toFunction:function];
}

- (void) setButtonTitle:(NSString *)button withStyle:(NSString *)style toFunction:(id)function {
    [indirect_ setButtonTitle:button withStyle:style toFunction:function];
}

- (void) setSpecial:(id)function {
    [indirect_ setSpecial:function];
}

- (void) setToken:(NSString *)token {
    if (Token_ != nil)
        [Token_ release];
    Token_ = [token retain];

    [Metadata_ setObject:Token_ forKey:@"Token"];
    Changed_ = true;
}

- (void) setPopupHook:(id)function {
    [indirect_ setPopupHook:function];
}

- (void) setViewportWidth:(float)width {
    [indirect_ setViewportWidth:width];
}

- (NSString *) stringWithFormat:(NSString *)format arguments:(WebScriptObject *)arguments {
    //NSLog(@"SWF:\"%@\" A:%@", format, [arguments description]);
    unsigned count([arguments count]);
    id values[count];
    for (unsigned i(0); i != count; ++i)
        values[i] = [arguments objectAtIndex:i];
    return [[[NSString alloc] initWithFormat:format arguments:*(reinterpret_cast<va_list *>(&values))] autorelease];
}

- (NSString *) localizedStringForKey:(NSString *)key value:(NSString *)value table:(NSString *)table {
    if (reinterpret_cast<id>(value) == [WebUndefined undefined])
        value = nil;
    if (reinterpret_cast<id>(table) == [WebUndefined undefined])
        table = nil;
    return [[NSBundle mainBundle] localizedStringForKey:key value:value table:table];
}

@end
/* }}} */

/* Cydia Browser Controller {{{ */
@interface CYBrowserController : BrowserController {
    CydiaObject *cydia_;
}

@end

@implementation CYBrowserController

- (void) dealloc {
    [cydia_ release];
    [super dealloc];
}

- (void) setHeaders:(NSDictionary *)headers forHost:(NSString *)host {
}

- (void) webView:(WebView *)view didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame {
    [super webView:view didClearWindowObject:window forFrame:frame];

    WebDataSource *source([frame dataSource]);
    NSURLResponse *response([source response]);
    NSURL *url([response URL]);
    NSString *scheme([url scheme]);

    NSHTTPURLResponse *http;
    if (scheme != nil && ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]))
        http = (NSHTTPURLResponse *) response;
    else
        http = nil;

    NSDictionary *headers([http allHeaderFields]);
    NSString *host([url host]);
    [self setHeaders:headers forHost:host];

    if (
        [host isEqualToString:@"cydia.saurik.com"] ||
        [host hasSuffix:@".cydia.saurik.com"] ||
        [scheme isEqualToString:@"file"]
    )
        [window setValue:cydia_ forKey:@"cydia"];
}

- (void) _setMoreHeaders:(NSMutableURLRequest *)request {
    if (System_ != NULL)
        [request setValue:System_ forHTTPHeaderField:@"X-System"];
    if (Machine_ != NULL)
        [request setValue:[NSString stringWithUTF8String:Machine_] forHTTPHeaderField:@"X-Machine"];
    if (Token_ != nil)
        [request setValue:Token_ forHTTPHeaderField:@"X-Cydia-Token"];
    if (Role_ != nil)
        [request setValue:Role_ forHTTPHeaderField:@"X-Role"];
}

- (NSURLRequest *) webView:(WebView *)view resource:(id)resource willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response fromDataSource:(WebDataSource *)source {
    NSMutableURLRequest *copy([[super webView:view resource:resource willSendRequest:request redirectResponse:response fromDataSource:source] mutableCopy]);
    [self _setMoreHeaders:copy];
    return copy;
}

- (void) setDelegate:(id)delegate {
    [super setDelegate:delegate];
    [cydia_ setDelegate:delegate];
}

- (id) init {
    if ((self = [super initWithWidth:0 ofClass:[CYBrowserController class]]) != nil) {
        cydia_ = [[CydiaObject alloc] initWithDelegate:indirect_];

        WebView *webview([[webview_ _documentView] webView]);

        Package *package([[Database sharedInstance] packageWithName:@"cydia"]);

        NSString *application = package == nil ? @"Cydia" : [NSString
            stringWithFormat:@"Cydia/%@",
            [package installed]
        ];

        if (Safari_ != nil)
            application = [NSString stringWithFormat:@"Safari/%@ %@", Safari_, application];
        if (Build_ != nil)
            application = [NSString stringWithFormat:@"Mobile/%@ %@", Build_, application];
        if (Product_ != nil)
            application = [NSString stringWithFormat:@"Version/%@ %@", Product_, application];

        [webview setApplicationNameForUserAgent:application];
    } return self;
}

@end
/* }}} */

/* Confirmation {{{ */
@protocol ConfirmationControllerDelegate
- (void) cancelAndClear:(bool)clear;
- (void) confirmWithNavigationController:(UINavigationController *)navigation;
- (void) queue;
@end

@interface ConfirmationController : CYBrowserController {
    _transient Database *database_;
    UIAlertView *essential_;
    NSArray *changes_;
    NSArray *issues_;
    NSArray *sizes_;
    BOOL substrate_;
}

- (id) initWithDatabase:(Database *)database;

@end

@implementation ConfirmationController

- (void) dealloc {
    [changes_ release];
    if (issues_ != nil)
        [issues_ release];
    [sizes_ release];
    if (essential_ != nil)
        [essential_ release];
    [super dealloc];
}

- (void) alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)button {
    NSString *context([alert context]);

    if ([context isEqualToString:@"remove"]) {
        if (button == [alert cancelButtonIndex]) {
            [self dismissModalViewControllerAnimated:YES];
        } else if (button == [alert firstOtherButtonIndex]) {
            if (substrate_)
                Finish_ = 2;
            [delegate_ confirmWithNavigationController:[self navigationController]];
        }

        [alert dismissWithClickedButtonIndex:-1 animated:YES];
    } else if ([context isEqualToString:@"unable"]) {
        [self dismissModalViewControllerAnimated:YES];
        [alert dismissWithClickedButtonIndex:-1 animated:YES];
    } else {
        [super alertView:alert clickedButtonAtIndex:button];
    }
}

- (void) _doContinue {
    [self dismissModalViewControllerAnimated:YES];
    [delegate_ cancelAndClear:NO];
}

- (id) invokeDefaultMethodWithArguments:(NSArray *)args {
    [self performSelectorOnMainThread:@selector(_doContinue) withObject:nil waitUntilDone:NO];
    return nil;
}

- (void) webView:(WebView *)view didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame {
    [super webView:view didClearWindowObject:window forFrame:frame];
    [window setValue:changes_ forKey:@"changes"];
    [window setValue:issues_ forKey:@"issues"];
    [window setValue:sizes_ forKey:@"sizes"];
    [window setValue:self forKey:@"queue"];
}

- (id) initWithDatabase:(Database *)database {
    if ((self = [super init]) != nil) {
        database_ = database;

        [[self navigationItem] setTitle:UCLocalize("CONFIRM")];

        NSMutableArray *installing = [NSMutableArray arrayWithCapacity:16];
        NSMutableArray *reinstalling = [NSMutableArray arrayWithCapacity:16];
        NSMutableArray *upgrading = [NSMutableArray arrayWithCapacity:16];
        NSMutableArray *downgrading = [NSMutableArray arrayWithCapacity:16];
        NSMutableArray *removing = [NSMutableArray arrayWithCapacity:16];

        bool remove(false);

        pkgDepCache::Policy *policy([database_ policy]);

        pkgCacheFile &cache([database_ cache]);
        NSArray *packages = [database_ packages];
        for (Package *package in packages) {
            pkgCache::PkgIterator iterator = [package iterator];
            pkgDepCache::StateCache &state(cache[iterator]);

            NSString *name([package name]);

            if (state.NewInstall())
                [installing addObject:name];
            else if (!state.Delete() && (state.iFlags & pkgDepCache::ReInstall) == pkgDepCache::ReInstall)
                [reinstalling addObject:name];
            else if (state.Upgrade())
                [upgrading addObject:name];
            else if (state.Downgrade())
                [downgrading addObject:name];
            else if (state.Delete()) {
                if ([package essential])
                    remove = true;
                [removing addObject:name];
            } else continue;

            substrate_ |= DepSubstrate(policy->GetCandidateVer(iterator));
            substrate_ |= DepSubstrate(iterator.CurrentVer());
        }

        if (!remove)
            essential_ = nil;
        else if (Advanced_) {
            NSString *parenthetical(UCLocalize("PARENTHETICAL"));

            essential_ = [[UIAlertView alloc]
                initWithTitle:UCLocalize("REMOVING_ESSENTIALS")
                message:UCLocalize("REMOVING_ESSENTIALS_EX")
                delegate:self
                cancelButtonTitle:[NSString stringWithFormat:parenthetical, UCLocalize("CANCEL_OPERATION"), UCLocalize("SAFE")]
                otherButtonTitles:[NSString stringWithFormat:parenthetical, UCLocalize("FORCE_REMOVAL"), UCLocalize("UNSAFE")], nil
            ];

            [essential_ setContext:@"remove"];
        } else {
            essential_ = [[UIAlertView alloc]
                initWithTitle:UCLocalize("UNABLE_TO_COMPLY")
                message:UCLocalize("UNABLE_TO_COMPLY_EX")
                delegate:self
                cancelButtonTitle:UCLocalize("OKAY")
                otherButtonTitles:nil
            ];

            [essential_ setContext:@"unable"];
        }

        changes_ = [[NSArray alloc] initWithObjects:
            installing,
            reinstalling,
            upgrading,
            downgrading,
            removing,
        nil];

        issues_ = [database_ issues];
        if (issues_ != nil)
            issues_ = [issues_ retain];

        sizes_ = [[NSArray alloc] initWithObjects:
            SizeString([database_ fetcher].FetchNeeded()),
            SizeString([database_ fetcher].PartialPresent()),
        nil];

        [self loadURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"confirm" ofType:@"html"]]];

        [[self navigationItem] setLeftBarButtonItem:[[[UIBarButtonItem alloc]
            initWithTitle:UCLocalize("CANCEL")
            // OLD: [NSString stringWithFormat:UCLocalize("SLASH_DELIMITED"), UCLocalize("CANCEL"), UCLocalize("QUEUE")]
            style:UIBarButtonItemStylePlain
            target:self
            action:@selector(cancelButtonClicked)
        ] autorelease]];
    } return self;
}

- (void) applyRightButton {
#if !AlwaysReload && !IgnoreInstall
    if (issues_ == nil && ![self isLoading])
        [[self navigationItem] setRightBarButtonItem:[[[UIBarButtonItem alloc]
            initWithTitle:UCLocalize("CONFIRM")
            style:UIBarButtonItemStylePlain
            target:self
            action:@selector(confirmButtonClicked)
        ] autorelease]];
    else
        [super applyRightButton];
#else
    [[self navigationItem] setRightBarButtonItem:nil];
#endif
}

- (void) cancelButtonClicked {
    [self dismissModalViewControllerAnimated:YES];
    [delegate_ cancelAndClear:YES];
}

#if !AlwaysReload
- (void) confirmButtonClicked {
#if IgnoreInstall
    return;
#endif
    if (essential_ != nil)
        [essential_ show];
    else {
        if (substrate_)
            Finish_ = 2;
        [delegate_ confirmWithNavigationController:[self navigationController]];
    }
}
#endif

@end
/* }}} */

/* Progress Data {{{ */
@interface ProgressData : NSObject {
    SEL selector_;
    // XXX: should these really both be _transient?
    _transient id target_;
    _transient id object_;
}

- (ProgressData *) initWithSelector:(SEL)selector target:(id)target object:(id)object;

- (SEL) selector;
- (id) target;
- (id) object;
@end

@implementation ProgressData

- (ProgressData *) initWithSelector:(SEL)selector target:(id)target object:(id)object {
    if ((self = [super init]) != nil) {
        selector_ = selector;
        target_ = target;
        object_ = object;
    } return self;
}

- (SEL) selector {
    return selector_;
}

- (id) target {
    return target_;
}

- (id) object {
    return object_;
}

@end
/* }}} */
/* Progress Controller {{{ */
@interface ProgressController : CYViewController <
    ConfigurationDelegate,
    ProgressDelegate
> {
    _transient Database *database_;
    UIProgressBar *progress_;
    UITextView *output_;
    UITextLabel *status_;
    UIPushButton *close_;
    BOOL running_;
    SHA1SumValue springlist_;
    SHA1SumValue notifyconf_;
    NSString *title_;
}

- (id) initWithDatabase:(Database *)database delegate:(id)delegate;

- (void) _retachThread;
- (void) _detachNewThreadData:(ProgressData *)data;
- (void) detachNewThreadSelector:(SEL)selector toTarget:(id)target withObject:(id)object title:(NSString *)title;

- (BOOL) isRunning;

@end

@protocol ProgressControllerDelegate
- (void) progressControllerIsComplete:(ProgressController *)sender;
@end

@implementation ProgressController

- (void) dealloc {
    [database_ setDelegate:nil];
    [progress_ release];
    [output_ release];
    [status_ release];
    [close_ release];
    if (title_ != nil)
        [title_ release];
    [super dealloc];
}

- (id) initWithDatabase:(Database *)database delegate:(id)delegate {
    if ((self = [super init]) != nil) {
        database_ = database;
        [database_ setDelegate:self];
        delegate_ = delegate;

        [[self view] setBackgroundColor:[UIColor colorWithRed:0.0f green:0.0f blue:0.0f alpha:1.0f]];

        progress_ = [[UIProgressBar alloc] init];
        [progress_ setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin)];
        [progress_ setStyle:0];

        status_ = [[UITextLabel alloc] init];
        [status_ setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin)];
        [status_ setColor:[UIColor whiteColor]];
        [status_ setBackgroundColor:[UIColor clearColor]];
        [status_ setCentersHorizontally:YES];
        //[status_ setFont:font];

        output_ = [[UITextView alloc] init];

        [output_ setAutoresizingMask:UIViewAutoresizingFlexibleBoth];
        //[output_ setTextFont:@"Courier New"];
        [output_ setFont:[[output_ font] fontWithSize:12]];
        [output_ setTextColor:[UIColor whiteColor]];
        [output_ setBackgroundColor:[UIColor clearColor]];
        [output_ setMarginTop:0];
        [output_ setAllowsRubberBanding:YES];
        [output_ setEditable:NO];
        [[self view] addSubview:output_];

        close_ = [[UIPushButton alloc] init];
        [close_ setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin)];
        [close_ setAutosizesToFit:NO];
        [close_ setDrawsShadow:YES];
        [close_ setStretchBackground:YES];
        [close_ setEnabled:YES];
        [close_ setTitleFont:[UIFont boldSystemFontOfSize:22]];
        [close_ addTarget:self action:@selector(closeButtonPushed) forEvents:UIControlEventTouchUpInside];
        [close_ setBackground:[UIImage applicationImageNamed:@"green-up.png"] forState:0];
        [close_ setBackground:[UIImage applicationImageNamed:@"green-dn.png"] forState:1];
    } return self;
}

- (void) positionViews {
    CGRect bounds = [[self view] bounds];
    CGSize prgsize = [UIProgressBar defaultSize];

    CGRect prgrect = {{
        (bounds.size.width - prgsize.width) / 2,
        bounds.size.height - prgsize.height - 20
    }, prgsize};

    float closewidth = std::min(bounds.size.width - 20, 300.0f);

    [progress_ setFrame:prgrect];
    [status_ setFrame:CGRectMake(
        10,
        bounds.size.height - prgsize.height - 50,
        bounds.size.width - 20,
        24
    )];
    [output_ setFrame:CGRectMake(
        10,
        20,
        bounds.size.width - 20,
        bounds.size.height - 62
    )];
    [close_ setFrame:CGRectMake(
        (bounds.size.width - closewidth) / 2,
        bounds.size.height - prgsize.height - 50,
        closewidth,
        32 + prgsize.height
    )];
}

- (void) viewWillAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [[self navigationItem] setHidesBackButton:YES];
    [[[self navigationController] navigationBar] setBarStyle:UIBarStyleBlack];

    [self positionViews];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [self positionViews];
}

- (void) alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)button {
    NSString *context([alert context]);

    if ([context isEqualToString:@"conffile"]) {
        FILE *input = [database_ input];
        if (button == [alert cancelButtonIndex])
            fprintf(input, "N\n");
        else if (button == [alert firstOtherButtonIndex])
            fprintf(input, "Y\n");
        fflush(input);
    }
}

- (void) closeButtonPushed {
    running_ = NO;

    UpdateExternalStatus(0);

    switch (Finish_) {
        case 0:
            [self dismissModalViewControllerAnimated:YES];
        break;

        case 1:
            [delegate_ terminateWithSuccess];
            /*if ([delegate_ respondsToSelector:@selector(suspendWithAnimation:)])
                [delegate_ suspendWithAnimation:YES];
            else
                [delegate_ suspend];*/
        break;

        case 2:
            system("launchctl stop com.apple.SpringBoard");
        break;

        case 3:
            system("launchctl unload "SpringBoard_"; launchctl load "SpringBoard_);
        break;

        case 4:
            system("reboot");
        break;
    }
}

- (void) _retachThread {
    [[self navigationItem] setTitle:UCLocalize("COMPLETE")];

    [[self view] addSubview:close_];
    [progress_ removeFromSuperview];
    [status_ removeFromSuperview];

    [database_ popErrorWithTitle:title_];
    [delegate_ progressControllerIsComplete:self];

    if (Finish_ < 4) {
        FileFd file;
        if (!file.Open(NotifyConfig_, FileFd::ReadOnly))
            _error->Discard();
        else {
            MMap mmap(file, MMap::ReadOnly);
            SHA1Summation sha1;
            sha1.Add(reinterpret_cast<uint8_t *>(mmap.Data()), mmap.Size());
            if (!(notifyconf_ == sha1.Result()))
                Finish_ = 4;
        }
    }

    if (Finish_ < 3) {
        FileFd file;
        if (!file.Open(SpringBoard_, FileFd::ReadOnly))
            _error->Discard();
        else {
            MMap mmap(file, MMap::ReadOnly);
            SHA1Summation sha1;
            sha1.Add(reinterpret_cast<uint8_t *>(mmap.Data()), mmap.Size());
            if (!(springlist_ == sha1.Result()))
                Finish_ = 3;
        }
    }

    switch (Finish_) {
        case 0: [close_ setTitle:UCLocalize("RETURN_TO_CYDIA")]; break; /* XXX: Maybe UCLocalize("DONE")? */
        case 1: [close_ setTitle:UCLocalize("CLOSE_CYDIA")]; break;
        case 2: [close_ setTitle:UCLocalize("RESTART_SPRINGBOARD")]; break;
        case 3: [close_ setTitle:UCLocalize("RELOAD_SPRINGBOARD")]; break;
        case 4: [close_ setTitle:UCLocalize("REBOOT_DEVICE")]; break;
    }

    system("su -c /usr/bin/uicache mobile");

    UpdateExternalStatus(Finish_ == 0 ? 2 : 0);

    [delegate_ setStatusBarShowsProgress:NO];
}

- (void) _detachNewThreadData:(ProgressData *)data { _pooled
    [[data target] performSelector:[data selector] withObject:[data object]];
    [self performSelectorOnMainThread:@selector(_retachThread) withObject:nil waitUntilDone:YES];
}

- (void) detachNewThreadSelector:(SEL)selector toTarget:(id)target withObject:(id)object title:(NSString *)title {
    UpdateExternalStatus(1);

    if (title_ != nil)
        [title_ release];
    if (title == nil)
        title_ = nil;
    else
        title_ = [title retain];

    [[self navigationItem] setTitle:title_];

    [status_ setText:nil];
    [output_ setText:@""];
    [progress_ setProgress:0];

    [close_ removeFromSuperview];
    [[self view] addSubview:progress_];
    [[self view] addSubview:status_];

    [delegate_ setStatusBarShowsProgress:YES];
    running_ = YES;

    {
        FileFd file;
        if (!file.Open(NotifyConfig_, FileFd::ReadOnly))
            _error->Discard();
        else {
            MMap mmap(file, MMap::ReadOnly);
            SHA1Summation sha1;
            sha1.Add(reinterpret_cast<uint8_t *>(mmap.Data()), mmap.Size());
            notifyconf_ = sha1.Result();
        }
    }

    {
        FileFd file;
        if (!file.Open(SpringBoard_, FileFd::ReadOnly))
            _error->Discard();
        else {
            MMap mmap(file, MMap::ReadOnly);
            SHA1Summation sha1;
            sha1.Add(reinterpret_cast<uint8_t *>(mmap.Data()), mmap.Size());
            springlist_ = sha1.Result();
        }
    }

    [NSThread
        detachNewThreadSelector:@selector(_detachNewThreadData:)
        toTarget:self
        withObject:[[[ProgressData alloc]
            initWithSelector:selector
            target:target
            object:object
        ] autorelease]
    ];
}

- (void) repairWithSelector:(SEL)selector {
    [self
        detachNewThreadSelector:selector
        toTarget:database_
        withObject:nil
        title:UCLocalize("REPAIRING")
    ];
}

- (void) setConfigurationData:(NSString *)data {
    [self
        performSelectorOnMainThread:@selector(_setConfigurationData:)
        withObject:data
        waitUntilDone:YES
    ];
}

- (void) setProgressError:(NSString *)error withTitle:(NSString *)title {
    CYActionSheet *sheet([[[CYActionSheet alloc]
        initWithTitle:title
        buttons:[NSArray arrayWithObjects:UCLocalize("OKAY"), nil]
        defaultButtonIndex:0
    ] autorelease]);

    [sheet setMessage:error];
    [sheet yieldToPopupAlertAnimated:YES];
    [sheet dismiss];
}

- (void) setProgressTitle:(NSString *)title {
    [self
        performSelectorOnMainThread:@selector(_setProgressTitle:)
        withObject:title
        waitUntilDone:YES
    ];
}

- (void) setProgressPercent:(float)percent {
    [self
        performSelectorOnMainThread:@selector(_setProgressPercent:)
        withObject:[NSNumber numberWithFloat:percent]
        waitUntilDone:YES
    ];
}

- (void) startProgress {
}

- (void) addProgressOutput:(NSString *)output {
    [self
        performSelectorOnMainThread:@selector(_addProgressOutput:)
        withObject:output
        waitUntilDone:YES
    ];
}

- (bool) isCancelling:(size_t)received {
    return false;
}

- (void) _setConfigurationData:(NSString *)data {
    static Pcre conffile_r("^'(.*)' '(.*)' ([01]) ([01])$");

    if (!conffile_r(data)) {
        lprintf("E:invalid conffile\n");
        return;
    }

    NSString *ofile = conffile_r[1];
    //NSString *nfile = conffile_r[2];

    UIAlertView *alert = [[[UIAlertView alloc]
        initWithTitle:UCLocalize("CONFIGURATION_UPGRADE")
        message:[NSString stringWithFormat:@"%@\n\n%@", UCLocalize("CONFIGURATION_UPGRADE_EX"), ofile]
        delegate:self
        cancelButtonTitle:UCLocalize("KEEP_OLD_COPY")
        otherButtonTitles:UCLocalize("ACCEPT_NEW_COPY"),
        // XXX: UCLocalize("SEE_WHAT_CHANGED"),
        nil
    ] autorelease];

    [alert setContext:@"conffile"];
    [alert show];
}

- (void) _setProgressTitle:(NSString *)title {
    NSMutableArray *words([[title componentsSeparatedByString:@" "] mutableCopy]);
    for (size_t i(0), e([words count]); i != e; ++i) {
        NSString *word([words objectAtIndex:i]);
        if (Package *package = [database_ packageWithName:word])
            [words replaceObjectAtIndex:i withObject:[package name]];
    }

    [status_ setText:[words componentsJoinedByString:@" "]];
}

- (void) _setProgressPercent:(NSNumber *)percent {
    [progress_ setProgress:[percent floatValue]];
}

- (void) _addProgressOutput:(NSString *)output {
    [output_ setText:[NSString stringWithFormat:@"%@\n%@", [output_ text], output]];
    CGSize size = [output_ contentSize];
    CGRect rect = {{0, size.height}, {size.width, 0}};
    [output_ scrollRectToVisible:rect animated:YES];
}

- (BOOL) isRunning {
    return running_;
}

@end
/* }}} */

/* Cell Content View {{{ */
@protocol ContentDelegate
- (void) drawContentRect:(CGRect)rect;
@end

@interface ContentView : UIView {
    _transient id<ContentDelegate> delegate_;
}

@end

@implementation ContentView

- (id) initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame]) != nil) {
        [self setNeedsDisplayOnBoundsChange:YES];
    } return self;
}

- (void) setDelegate:(id<ContentDelegate>)delegate {
    delegate_ = delegate;
}

- (void) drawRect:(CGRect)rect {
    [super drawRect:rect];
    [delegate_ drawContentRect:rect];
}

@end
/* }}} */
/* Cydia TableView Cell {{{ */
@interface CYTableViewCell : UITableViewCell {
    ContentView *content_;
    bool highlighted_;
}

@end

@implementation CYTableViewCell

- (void) dealloc {
    [content_ release];
    [super dealloc];
}

- (void) _updateHighlightColorsForView:(id)view highlighted:(BOOL)highlighted {
    //NSLog(@"_updateHighlightColorsForView:%@ highlighted:%s [content_=%@]", view, highlighted ? "YES" : "NO", content_);

    if (view == content_) {
        //NSLog(@"_updateHighlightColorsForView:content_ highlighted:%s", highlighted ? "YES" : "NO", content_);
        highlighted_ = highlighted;
    }

    [super _updateHighlightColorsForView:view highlighted:highlighted];
}

- (void) setSelected:(BOOL)selected animated:(BOOL)animated {
    //NSLog(@"setSelected:%s animated:%s", selected ? "YES" : "NO", animated ? "YES" : "NO");
    highlighted_ = selected;

    [super setSelected:selected animated:animated];
    [content_ setNeedsDisplay];
}

@end
/* }}} */
/* Package Cell {{{ */
@interface PackageCell : CYTableViewCell <
    ContentDelegate
> {
    UIImage *icon_;
    NSString *name_;
    NSString *description_;
    bool commercial_;
    NSString *source_;
    UIImage *badge_;
    Package *package_;
    UIImage *placard_;
}

- (PackageCell *) init;
- (void) setPackage:(Package *)package;

+ (int) heightForPackage:(Package *)package;
- (void) drawContentRect:(CGRect)rect;

@end

@implementation PackageCell

- (void) clearPackage {
    if (icon_ != nil) {
        [icon_ release];
        icon_ = nil;
    }

    if (name_ != nil) {
        [name_ release];
        name_ = nil;
    }

    if (description_ != nil) {
        [description_ release];
        description_ = nil;
    }

    if (source_ != nil) {
        [source_ release];
        source_ = nil;
    }

    if (badge_ != nil) {
        [badge_ release];
        badge_ = nil;
    }

    if (placard_ != nil) {
        [placard_ release];
        placard_ = nil;
    }

    [package_ release];
    package_ = nil;
}

- (void) dealloc {
    [self clearPackage];
    [super dealloc];
}

- (PackageCell *) init {
    CGRect frame(CGRectMake(0, 0, 320, 74));
    if ((self = [super initWithFrame:frame reuseIdentifier:@"Package"]) != nil) {
        UIView *content([self contentView]);
        CGRect bounds([content bounds]);

        content_ = [[ContentView alloc] initWithFrame:bounds];
        [content_ setAutoresizingMask:UIViewAutoresizingFlexibleBoth];
        [content addSubview:content_];

        [content_ setDelegate:self];
        [content_ setOpaque:YES];
    } return self;
}

- (void) _setBackgroundColor {
    UIColor *color;
    if (NSString *mode = [package_ mode]) {
        bool remove([mode isEqualToString:@"REMOVE"] || [mode isEqualToString:@"PURGE"]);
        color = remove ? RemovingColor_ : InstallingColor_;
    } else
        color = [UIColor whiteColor];

    [content_ setBackgroundColor:color];
    [self setNeedsDisplay];
}

- (void) setPackage:(Package *)package {
    [self clearPackage];
    [package parse];

    Source *source = [package source];

    icon_ = [[package icon] retain];
    name_ = [[package name] retain];

    if (IsWildcat_)
        description_ = [package longDescription];
    if (description_ == nil)
        description_ = [package shortDescription];
    if (description_ != nil)
        description_ = [description_ retain];

    commercial_ = [package isCommercial];

    package_ = [package retain];

    NSString *label = nil;
    bool trusted = false;

    if (source != nil) {
        label = [source label];
        trusted = [source trusted];
    } else if ([[package id] isEqualToString:@"firmware"])
        label = UCLocalize("APPLE");
    else
        label = [NSString stringWithFormat:UCLocalize("SLASH_DELIMITED"), UCLocalize("UNKNOWN"), UCLocalize("LOCAL")];

    NSString *from(label);

    NSString *section = [package simpleSection];
    if (section != nil && ![section isEqualToString:label]) {
        section = [[NSBundle mainBundle] localizedStringForKey:section value:nil table:@"Sections"];
        from = [NSString stringWithFormat:UCLocalize("PARENTHETICAL"), from, section];
    }

    from = [NSString stringWithFormat:UCLocalize("FROM"), from];
    source_ = [from retain];

    if (NSString *purpose = [package primaryPurpose])
        if ((badge_ = [UIImage imageAtPath:[NSString stringWithFormat:@"%@/Purposes/%@.png", App_, purpose]]) != nil)
            badge_ = [badge_ retain];

    if ([package installed] != nil)
        if ((placard_ = [UIImage imageAtPath:[NSString stringWithFormat:@"%@/installed.png", App_]]) != nil)
            placard_ = [placard_ retain];

    [self _setBackgroundColor];
    [content_ setNeedsDisplay];
}

- (void) drawContentRect:(CGRect)rect {
    bool highlighted(highlighted_);
    float width([self bounds].size.width);

#if 0
    CGContextRef context(UIGraphicsGetCurrentContext());
    [([[self selectedBackgroundView] superview] != nil ? [UIColor clearColor] : [self backgroundColor]) set];
    CGContextFillRect(context, rect);
#endif

    if (icon_ != nil) {
        CGRect rect;
        rect.size = [icon_ size];

        rect.size.width /= 2;
        rect.size.height /= 2;

        rect.origin.x = 25 - rect.size.width / 2;
        rect.origin.y = 25 - rect.size.height / 2;

        [icon_ drawInRect:rect];
    }

    if (badge_ != nil) {
        CGSize size = [badge_ size];

        [badge_ drawAtPoint:CGPointMake(
            36 - size.width / 2,
            36 - size.height / 2
        )];
    }

    if (highlighted)
        UISetColor(White_);

    if (!highlighted)
        UISetColor(commercial_ ? Purple_ : Black_);
    [name_ drawAtPoint:CGPointMake(48, 8) forWidth:(width - (placard_ == nil ? 80 : 106)) withFont:Font18Bold_ lineBreakMode:UILineBreakModeTailTruncation];
    [source_ drawAtPoint:CGPointMake(58, 29) forWidth:(width - 95) withFont:Font12_ lineBreakMode:UILineBreakModeTailTruncation];

    if (!highlighted)
        UISetColor(commercial_ ? Purplish_ : Gray_);
    [description_ drawAtPoint:CGPointMake(12, 46) forWidth:(width - 46) withFont:Font14_ lineBreakMode:UILineBreakModeTailTruncation];

    if (placard_ != nil)
        [placard_ drawAtPoint:CGPointMake(width - 52, 9)];
}

+ (int) heightForPackage:(Package *)package {
    return 73;
}

@end
/* }}} */
/* Section Cell {{{ */
@interface SectionCell : CYTableViewCell <
    ContentDelegate
> {
    NSString *basic_;
    NSString *section_;
    NSString *name_;
    NSString *count_;
    UIImage *icon_;
    UISwitch *switch_;
    BOOL editing_;
}

- (void) setSection:(Section *)section editing:(BOOL)editing;

@end

@implementation SectionCell

- (void) clearSection {
    if (basic_ != nil) {
        [basic_ release];
        basic_ = nil;
    }

    if (section_ != nil) {
        [section_ release];
        section_ = nil;
    }

    if (name_ != nil) {
        [name_ release];
        name_ = nil;
    }

    if (count_ != nil) {
        [count_ release];
        count_ = nil;
    }
}

- (void) dealloc {
    [self clearSection];
    [icon_ release];
    [switch_ release];
    [super dealloc];
}

- (id) initWithFrame:(CGRect)frame reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithFrame:frame reuseIdentifier:reuseIdentifier]) != nil) {
        icon_ = [[UIImage applicationImageNamed:@"folder.png"] retain];
        switch_ = [[UISwitch alloc] initWithFrame:CGRectMake(218, 9, 60, 25)];
        [switch_ addTarget:self action:@selector(onSwitch:) forEvents:UIControlEventValueChanged];

        UIView *content([self contentView]);
        CGRect bounds([content bounds]);

        content_ = [[ContentView alloc] initWithFrame:bounds];
        [content_ setAutoresizingMask:UIViewAutoresizingFlexibleBoth];
        [content addSubview:content_];
        [content_ setBackgroundColor:[UIColor whiteColor]];

        [content_ setDelegate:self];
    } return self;
}

- (void) onSwitch:(id)sender {
    NSMutableDictionary *metadata = [Sections_ objectForKey:basic_];
    if (metadata == nil) {
        metadata = [NSMutableDictionary dictionaryWithCapacity:2];
        [Sections_ setObject:metadata forKey:basic_];
    }

    Changed_ = true;
    [metadata setObject:[NSNumber numberWithBool:([switch_ isOn] == NO)] forKey:@"Hidden"];
}

- (void) setSection:(Section *)section editing:(BOOL)editing {
    if (editing != editing_) {
        if (editing_)
            [switch_ removeFromSuperview];
        else
            [self addSubview:switch_];
        editing_ = editing;
    }

    [self clearSection];

    if (section == nil) {
        name_ = [UCLocalize("ALL_PACKAGES") retain];
        count_ = nil;
    } else {
        basic_ = [section name];
        if (basic_ != nil)
            basic_ = [basic_ retain];

        section_ = [section localized];
        if (section_ != nil)
            section_ = [section_ retain];

        name_  = [(section_ == nil || [section_ length] == 0 ? UCLocalize("NO_SECTION") : section_) retain];
        count_ = [[NSString stringWithFormat:@"%d", [section count]] retain];

        if (editing_)
            [switch_ setOn:(isSectionVisible(basic_) ? 1 : 0) animated:NO];
    }

    [self setAccessoryType:editing ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator];
    [self setSelectionStyle:editing ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleBlue];

    [content_ setNeedsDisplay];
}

- (void) setFrame:(CGRect)frame {
    [super setFrame:frame];

    CGRect rect([switch_ frame]);
    [switch_ setFrame:CGRectMake(frame.size.width - 102, 9, rect.size.width, rect.size.height)];
}

- (void) drawContentRect:(CGRect)rect {
    bool highlighted(highlighted_);

    [icon_ drawInRect:CGRectMake(8, 7, 32, 32)];

    if (highlighted)
        UISetColor(White_);

    float width(rect.size.width);
    if (editing_)
        width -= 87;

    if (!highlighted)
        UISetColor(Black_);
    [name_ drawAtPoint:CGPointMake(48, 9) forWidth:(width - 70) withFont:Font22Bold_ lineBreakMode:UILineBreakModeTailTruncation];

    CGSize size = [count_ sizeWithFont:Font14_];

    UISetColor(White_);
    if (count_ != nil)
        [count_ drawAtPoint:CGPointMake(13 + (29 - size.width) / 2, 16) withFont:Font12Bold_];
}

@end
/* }}} */

/* File Table {{{ */
@interface FileTable : CYViewController <
    UITableViewDataSource,
    UITableViewDelegate
> {
    _transient Database *database_;
    Package *package_;
    NSString *name_;
    NSMutableArray *files_;
    UITableView *list_;
}

- (id) initWithDatabase:(Database *)database;
- (void) setPackage:(Package *)package;

@end

@implementation FileTable

- (void) dealloc {
    if (package_ != nil)
        [package_ release];
    if (name_ != nil)
        [name_ release];
    [files_ release];
    [list_ release];
    [super dealloc];
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return files_ == nil ? 0 : [files_ count];
}

/*- (CGFloat) tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 24.0f;
}*/

- (UITableViewCell *) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuseIdentifier = @"Cell";

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (cell == nil) {
        cell = [[[UITableViewCell alloc] initWithFrame:CGRectZero reuseIdentifier:reuseIdentifier] autorelease];
        [cell setFont:[UIFont systemFontOfSize:16]];
    }
    [cell setText:[files_ objectAtIndex:indexPath.row]];
    [cell setSelectionStyle:UITableViewCellSelectionStyleNone];

    return cell;
}

- (id) initWithDatabase:(Database *)database {
    if ((self = [super init]) != nil) {
        database_ = database;

        [[self navigationItem] setTitle:UCLocalize("INSTALLED_FILES")];

        files_ = [[NSMutableArray arrayWithCapacity:32] retain];

        list_ = [[UITableView alloc] initWithFrame:[[self view] bounds]];
        [list_ setAutoresizingMask:UIViewAutoresizingFlexibleBoth];
        [list_ setRowHeight:24.0f];
        [[self view] addSubview:list_];

        [list_ setDataSource:self];
        [list_ setDelegate:self];
    } return self;
}

- (void) setPackage:(Package *)package {
    if (package_ != nil) {
        [package_ autorelease];
        package_ = nil;
    }

    if (name_ != nil) {
        [name_ release];
        name_ = nil;
    }

    [files_ removeAllObjects];

    if (package != nil) {
        package_ = [package retain];
        name_ = [[package id] retain];

        if (NSArray *files = [package files])
            [files_ addObjectsFromArray:files];

        if ([files_ count] != 0) {
            if ([[files_ objectAtIndex:0] isEqualToString:@"/."])
                [files_ removeObjectAtIndex:0];
            [files_ sortUsingSelector:@selector(compareByPath:)];

            NSMutableArray *stack = [NSMutableArray arrayWithCapacity:8];
            [stack addObject:@"/"];

            for (int i(0), e([files_ count]); i != e; ++i) {
                NSString *file = [files_ objectAtIndex:i];
                while (![file hasPrefix:[stack lastObject]])
                    [stack removeLastObject];
                NSString *directory = [stack lastObject];
                [stack addObject:[file stringByAppendingString:@"/"]];
                [files_ replaceObjectAtIndex:i withObject:[NSString stringWithFormat:@"%*s%@",
                    ([stack count] - 2) * 3, "",
                    [file substringFromIndex:[directory length]]
                ]];
            }
        }
    }

    [list_ reloadData];
}

- (void) reloadData {
    [self setPackage:[database_ packageWithName:name_]];
}

@end
/* }}} */
/* Package Controller {{{ */
@interface PackageController : CYBrowserController <
    UIActionSheetDelegate
> {
    _transient Database *database_;
    Package *package_;
    NSString *name_;
    bool commercial_;
    NSMutableArray *buttons_;
    UIBarButtonItem *button_;
}

- (id) initWithDatabase:(Database *)database;
- (void) setPackage:(Package *)package;

@end

@implementation PackageController

- (void) dealloc {
    if (package_ != nil)
        [package_ release];
    if (name_ != nil)
        [name_ release];

    [buttons_ release];

    if (button_ != nil)
        [button_ release];

    [super dealloc];
}

- (void) release {
    if ([self retainCount] == 1)
        [delegate_ setPackageController:self];
    [super release];
}

/* XXX: this is not safe at all... localization of /fail/ */
- (void) _clickButtonWithName:(NSString *)name {
    if ([name isEqualToString:UCLocalize("CLEAR")])
        [delegate_ clearPackage:package_];
    else if ([name isEqualToString:UCLocalize("INSTALL")])
        [delegate_ installPackage:package_];
    else if ([name isEqualToString:UCLocalize("REINSTALL")])
        [delegate_ installPackage:package_];
    else if ([name isEqualToString:UCLocalize("REMOVE")])
        [delegate_ removePackage:package_];
    else if ([name isEqualToString:UCLocalize("UPGRADE")])
        [delegate_ installPackage:package_];
    else _assert(false);
}

- (void) actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)button {
    NSString *context([sheet context]);

    if ([context isEqualToString:@"modify"]) {
        if (button != [sheet cancelButtonIndex]) {
            NSString *buttonName = [buttons_ objectAtIndex:button];
            [self _clickButtonWithName:buttonName];
        }

        [sheet dismissWithClickedButtonIndex:-1 animated:YES];
    }
}

- (void) webView:(WebView *)view didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame {
    [super webView:view didClearWindowObject:window forFrame:frame];
    [window setValue:package_ forKey:@"package"];
}

- (bool) _allowJavaScriptPanel {
    return commercial_;
}

#if !AlwaysReload
- (void) _customButtonClicked {
    int count([buttons_ count]);
    if (count == 0)
        return;

    if (count == 1)
        [self _clickButtonWithName:[buttons_ objectAtIndex:0]];
    else {
        NSMutableArray *buttons = [NSMutableArray arrayWithCapacity:count];
        [buttons addObjectsFromArray:buttons_];

        UIActionSheet *sheet = [[[UIActionSheet alloc]
            initWithTitle:nil
            delegate:self
            cancelButtonTitle:nil
            destructiveButtonTitle:nil
            otherButtonTitles:nil
        ] autorelease];

        for (NSString *button in buttons) [sheet addButtonWithTitle:button];
        if (!IsWildcat_) {
           [sheet addButtonWithTitle:UCLocalize("CANCEL")];
           [sheet setCancelButtonIndex:[sheet numberOfButtons] - 1];
        }
        [sheet setContext:@"modify"];

        [delegate_ showActionSheet:sheet fromItem:[[self navigationItem] rightBarButtonItem]];
    }
}

// We don't want to allow non-commercial packages to do custom things to the install button,
// so it must call customButtonClicked with a custom commercial_ == 1 fallthrough.
- (void) customButtonClicked {
    if (commercial_)
        [super customButtonClicked];
    else
        [self _customButtonClicked];
}

- (void) reloadButtonClicked {
    // Don't reload a package view by clicking the button.
}

- (void) applyLoadingTitle {
    // Don't show "Loading" as the title. Ever.
}

- (UIBarButtonItem *) rightButton {
    return button_;
}
#endif

- (id) initWithDatabase:(Database *)database {
    if ((self = [super init]) != nil) {
        database_ = database;
        buttons_ = [[NSMutableArray alloc] initWithCapacity:4];
        [self loadURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"package" ofType:@"html"]]];
    } return self;
}

- (void) setPackage:(Package *)package {
    if (package_ != nil) {
        [package_ autorelease];
        package_ = nil;
    }

    if (name_ != nil) {
        [name_ release];
        name_ = nil;
    }

    [buttons_ removeAllObjects];

    if (package != nil) {
        [package parse];

        package_ = [package retain];
        name_ = [[package id] retain];
        commercial_ = [package isCommercial];

        if ([package_ mode] != nil)
            [buttons_ addObject:UCLocalize("CLEAR")];
        if ([package_ source] == nil);
        else if ([package_ upgradableAndEssential:NO])
            [buttons_ addObject:UCLocalize("UPGRADE")];
        else if ([package_ uninstalled])
            [buttons_ addObject:UCLocalize("INSTALL")];
        else
            [buttons_ addObject:UCLocalize("REINSTALL")];
        if (![package_ uninstalled])
            [buttons_ addObject:UCLocalize("REMOVE")];
    }

    if (button_ != nil)
        [button_ release];

    NSString *title;
    switch ([buttons_ count]) {
        case 0: title = nil; break;
        case 1: title = [buttons_ objectAtIndex:0]; break;
        default: title = UCLocalize("MODIFY"); break;
    }

    button_ = [[UIBarButtonItem alloc]
        initWithTitle:title
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(customButtonClicked)
    ];

    [self reloadURL];
}

- (bool) isLoading {
    return commercial_ ? [super isLoading] : false;
}

- (void) reloadData {
    [self setPackage:[database_ packageWithName:name_]];
}

@end
/* }}} */
/* Package Table {{{ */
@interface PackageTable : UIView <
    UITableViewDataSource,
    UITableViewDelegate
> {
    _transient Database *database_;
    NSMutableArray *packages_;
    NSMutableArray *sections_;
    UITableView *list_;
    NSMutableArray *index_;
    NSMutableDictionary *indices_;
    // XXX: this target_ seems to be delegate_. :(
    _transient id target_;
    SEL action_;
    // XXX: why do we even have this delegate_?
    _transient id delegate_;
}

- (id) initWithFrame:(CGRect)frame database:(Database *)database target:(id)target action:(SEL)action;

- (void) setDelegate:(id)delegate;

- (void) reloadData;
- (void) resetCursor;

- (UITableView *) list;

- (void) setShouldHideHeaderInShortLists:(BOOL)hide;

- (void) deselectWithAnimation:(BOOL)animated;

@end

@implementation PackageTable

- (void) dealloc {
    [packages_ release];
    [sections_ release];
    [list_ release];
    [index_ release];
    [indices_ release];

    [super dealloc];
}

- (NSInteger) numberOfSectionsInTableView:(UITableView *)list {
    NSInteger count([sections_ count]);
    return count == 0 ? 1 : count;
}

- (NSString *) tableView:(UITableView *)list titleForHeaderInSection:(NSInteger)section {
    if ([sections_ count] == 0)
        return nil;
    return [[sections_ objectAtIndex:section] name];
}

- (NSInteger) tableView:(UITableView *)list numberOfRowsInSection:(NSInteger)section {
    if ([sections_ count] == 0)
        return 0;
    return [[sections_ objectAtIndex:section] count];
}

- (Package *) packageAtIndexPath:(NSIndexPath *)path {
    Section *section([sections_ objectAtIndex:[path section]]);
    NSInteger row([path row]);
    Package *package([packages_ objectAtIndex:([section row] + row)]);
    return package;
}

- (UITableViewCell *) tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    PackageCell *cell((PackageCell *) [table dequeueReusableCellWithIdentifier:@"Package"]);
    if (cell == nil)
        cell = [[[PackageCell alloc] init] autorelease];
    [cell setPackage:[self packageAtIndexPath:path]];
    return cell;
}

- (void) deselectWithAnimation:(BOOL)animated {
    [list_ deselectRowAtIndexPath:[list_ indexPathForSelectedRow] animated:animated];
}

/*- (CGFloat) tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    return [PackageCell heightForPackage:[self packageAtIndexPath:path]];
}*/

- (NSIndexPath *) tableView:(UITableView *)table willSelectRowAtIndexPath:(NSIndexPath *)path {
    Package *package([self packageAtIndexPath:path]);
    package = [database_ packageWithName:[package id]];
    [target_ performSelector:action_ withObject:package];
    return path;
}

- (NSArray *) sectionIndexTitlesForTableView:(UITableView *)tableView {
    return [packages_ count] > 20 ? index_ : nil;
}

- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index {
    return index;
}

- (id) initWithFrame:(CGRect)frame database:(Database *)database target:(id)target action:(SEL)action {
    if ((self = [super initWithFrame:frame]) != nil) {
        database_ = database;

        target_ = target;
        action_ = action;

        index_ = [[NSMutableArray alloc] initWithCapacity:32];
        indices_ = [[NSMutableDictionary alloc] initWithCapacity:32];

        packages_ = [[NSMutableArray arrayWithCapacity:16] retain];
        sections_ = [[NSMutableArray arrayWithCapacity:16] retain];

        list_ = [[UITableView alloc] initWithFrame:[self bounds] style:UITableViewStylePlain];
        [list_ setAutoresizingMask:UIViewAutoresizingFlexibleBoth];
        [list_ setRowHeight:73.0f];
        [self addSubview:list_];

        [list_ setDataSource:self];
        [list_ setDelegate:self];
    } return self;
}

- (void) setDelegate:(id)delegate {
    delegate_ = delegate;
}

- (bool) hasPackage:(Package *)package {
    return true;
}

- (void) reloadData {
    NSArray *packages = [database_ packages];

    [packages_ removeAllObjects];
    [sections_ removeAllObjects];

    _profile(PackageTable$reloadData$Filter)
        for (Package *package in packages)
            if ([self hasPackage:package])
                [packages_ addObject:package];
    _end

    [index_ removeAllObjects];
    [indices_ removeAllObjects];

    Section *section = nil;

    _profile(PackageTable$reloadData$Section)
        for (size_t offset(0), end([packages_ count]); offset != end; ++offset) {
            Package *package;
            unichar index;

            _profile(PackageTable$reloadData$Section$Package)
                package = [packages_ objectAtIndex:offset];
                index = [package index];
            _end

            if (section == nil || [section index] != index) {
                _profile(PackageTable$reloadData$Section$Allocate)
                    section = [[[Section alloc] initWithIndex:index row:offset] autorelease];
                _end

                [index_ addObject:[section name]];
                //[indices_ setObject:[NSNumber numberForInt:[sections_ count]] forKey:index];

                _profile(PackageTable$reloadData$Section$Add)
                    [sections_ addObject:section];
                _end
            }

            [section addToCount];
        }
    _end

    _profile(PackageTable$reloadData$List)
        [list_ reloadData];
    _end
}

- (void) resetCursor {
    [list_ scrollRectToVisible:CGRectMake(0, 0, 0, 0) animated:NO];
}

- (UITableView *) list {
    return list_;
}

- (void) setShouldHideHeaderInShortLists:(BOOL)hide {
    //XXX:[list_ setShouldHideHeaderInShortLists:hide];
}

@end
/* }}} */
/* Filtered Package Table {{{ */
@interface FilteredPackageTable : PackageTable {
    SEL filter_;
    IMP imp_;
    id object_;
}

- (void) setObject:(id)object;
- (void) setObject:(id)object forFilter:(SEL)filter;

- (id) initWithFrame:(CGRect)frame database:(Database *)database target:(id)target action:(SEL)action filter:(SEL)filter with:(id)object;

@end

@implementation FilteredPackageTable

- (void) dealloc {
    if (object_ != nil)
        [object_ release];
    [super dealloc];
}

- (void) setFilter:(SEL)filter {
    filter_ = filter;

    /* XXX: this is an unsafe optimization of doomy hell */
    Method method(class_getInstanceMethod([Package class], filter));
    _assert(method != NULL);
    imp_ = method_getImplementation(method);
    _assert(imp_ != NULL);
}

- (void) setObject:(id)object {
    if (object_ != nil)
        [object_ release];
    if (object == nil)
        object_ = nil;
    else
        object_ = [object retain];
}

- (void) setObject:(id)object forFilter:(SEL)filter {
    [self setFilter:filter];
    [self setObject:object];
}

- (bool) hasPackage:(Package *)package {
    _profile(FilteredPackageTable$hasPackage)
        return [package valid] && (*reinterpret_cast<bool (*)(id, SEL, id)>(imp_))(package, filter_, object_);
    _end
}

- (id) initWithFrame:(CGRect)frame database:(Database *)database target:(id)target action:(SEL)action filter:(SEL)filter with:(id)object {
    if ((self = [super initWithFrame:frame database:database target:target action:action]) != nil) {
        [self setFilter:filter];
        object_ = [object retain];
        [self reloadData];
    } return self;
}

@end
/* }}} */

/* Filtered Package Controller {{{ */
@interface FilteredPackageController : CYViewController {
    _transient Database *database_;
    FilteredPackageTable *packages_;
    NSString *title_;
}

- (id) initWithDatabase:(Database *)database title:(NSString *)title filter:(SEL)filter with:(id)object;

@end

@implementation FilteredPackageController

- (void) dealloc {
    [packages_ release];
    [title_ release];

    [super dealloc];
}

- (void) viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [packages_ deselectWithAnimation:animated];
}

- (void) didSelectPackage:(Package *)package {
    PackageController *view([delegate_ packageController]);
    [view setPackage:package];
    [view setDelegate:delegate_];
    [[self navigationController] pushViewController:view animated:YES];
}

- (NSString *) title { return title_; }

- (id) initWithDatabase:(Database *)database title:(NSString *)title filter:(SEL)filter with:(id)object {
    if ((self = [super init]) != nil) {
        database_ = database;
        title_ = [title copy];
        [[self navigationItem] setTitle:title_];

        packages_ = [[FilteredPackageTable alloc]
            initWithFrame:[[self view] bounds]
            database:database
            target:self
            action:@selector(didSelectPackage:)
            filter:filter
            with:object
        ];

        [packages_ setAutoresizingMask:UIViewAutoresizingFlexibleBoth];
        [[self view] addSubview:packages_];
    } return self;
}

- (void) reloadData {
    [packages_ reloadData];
}

- (void) setDelegate:(id)delegate {
    [super setDelegate:delegate];
    [packages_ setDelegate:delegate];
}

@end

/* }}} */

/* Add Source Controller {{{ */
@interface AddSourceController : CYViewController {
    _transient Database *database_;
}

- (id) initWithDatabase:(Database *)database;

@end

@implementation AddSourceController

- (id) initWithDatabase:(Database *)database {
    if ((self = [super init]) != nil) {
        database_ = database;
    } return self;
}

@end
/* }}} */
/* Source Cell {{{ */
@interface SourceCell : CYTableViewCell <
    ContentDelegate
> {
    UIImage *icon_;
    NSString *origin_;
    NSString *description_;
    NSString *label_;
}

- (void) setSource:(Source *)source;

@end

@implementation SourceCell

- (void) clearSource {
    [icon_ release];
    [origin_ release];
    [description_ release];
    [label_ release];

    icon_ = nil;
    origin_ = nil;
    description_ = nil;
    label_ = nil;
}

- (void) setSource:(Source *)source {
    [self clearSource];

    if (icon_ == nil)
        icon_ = [UIImage applicationImageNamed:[NSString stringWithFormat:@"Sources/%@.png", [source host]]];
    if (icon_ == nil)
        icon_ = [UIImage applicationImageNamed:@"unknown.png"];
    icon_ = [icon_ retain];

    origin_ = [[source name] retain];
    label_ = [[source uri] retain];
    description_ = [[source description] retain];

    [content_ setNeedsDisplay];
}

- (void) dealloc {
    [self clearSource];
    [super dealloc];
}

- (SourceCell *) initWithFrame:(CGRect)frame reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithFrame:frame reuseIdentifier:reuseIdentifier]) != nil) {
        UIView *content([self contentView]);
        CGRect bounds([content bounds]);

        content_ = [[ContentView alloc] initWithFrame:bounds];
        [content_ setAutoresizingMask:UIViewAutoresizingFlexibleBoth];
        [content_ setBackgroundColor:[UIColor whiteColor]];
        [content addSubview:content_];

        [content_ setDelegate:self];
        [content_ setOpaque:YES];
    } return self;
}

- (void) drawContentRect:(CGRect)rect {
    bool highlighted(highlighted_);
    float width(rect.size.width);

    if (icon_ != nil)
        [icon_ drawInRect:CGRectMake(10, 10, 30, 30)];

    if (highlighted)
        UISetColor(White_);

    if (!highlighted)
        UISetColor(Black_);
    [origin_ drawAtPoint:CGPointMake(48, 8) forWidth:(width - 80) withFont:Font18Bold_ lineBreakMode:UILineBreakModeTailTruncation];

    if (!highlighted)
        UISetColor(Blue_);
    [label_ drawAtPoint:CGPointMake(58, 29) forWidth:(width - 95) withFont:Font12_ lineBreakMode:UILineBreakModeTailTruncation];

    if (!highlighted)
        UISetColor(Gray_);
    [description_ drawAtPoint:CGPointMake(12, 46) forWidth:(width - 40) withFont:Font14_ lineBreakMode:UILineBreakModeTailTruncation];
}

@end
/* }}} */
/* Source Table {{{ */
@interface SourceTable : CYViewController <
    UITableViewDataSource,
    UITableViewDelegate
> {
    _transient Database *database_;
    UITableView *list_;
    NSMutableArray *sources_;
    int offset_;

    NSString *href_;
    UIProgressHUD *hud_;
    NSError *error_;

    //NSURLConnection *installer_;
    NSURLConnection *trivial_;
    NSURLConnection *trivial_bz2_;
    NSURLConnection *trivial_gz_;
    //NSURLConnection *automatic_;

    BOOL cydia_;
}

- (id) initWithDatabase:(Database *)database;

- (void) updateButtonsForEditingStatus:(BOOL)editing animated:(BOOL)animated;

@end

@implementation SourceTable

- (void) _releaseConnection:(NSURLConnection *)connection {
    if (connection != nil) {
        [connection cancel];
        //[connection setDelegate:nil];
        [connection release];
    }
}

- (void) dealloc {
    if (href_ != nil)
        [href_ release];
    if (hud_ != nil)
        [hud_ release];
    if (error_ != nil)
        [error_ release];

    //[self _releaseConnection:installer_];
    [self _releaseConnection:trivial_];
    [self _releaseConnection:trivial_gz_];
    [self _releaseConnection:trivial_bz2_];
    //[self _releaseConnection:automatic_];

    [sources_ release];
    [list_ release];
    [super dealloc];
}

- (void) viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [list_ deselectRowAtIndexPath:[list_ indexPathForSelectedRow] animated:animated];
}

- (NSInteger) numberOfSectionsInTableView:(UITableView *)tableView {
    return offset_ == 0 ? 1 : 2;
}

- (NSString *) tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section + (offset_ == 0 ? 1 : 0)) {
        case 0: return UCLocalize("ENTERED_BY_USER");
        case 1: return UCLocalize("INSTALLED_BY_PACKAGE");

        _nodefault
    }
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    int count = [sources_ count];
    switch (section) {
        case 0: return (offset_ == 0 ? count : offset_);
        case 1: return count - offset_;

        _nodefault
    }
}

- (Source *) sourceAtIndexPath:(NSIndexPath *)indexPath {
    unsigned idx = 0;
    switch (indexPath.section) {
        case 0: idx = indexPath.row; break;
        case 1: idx = indexPath.row + offset_; break;

        _nodefault
    }
    return [sources_ objectAtIndex:idx];
}

- (CGFloat) tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    Source *source = [self sourceAtIndexPath:indexPath];
    return [source description] == nil ? 56 : 73;
}

- (UITableViewCell *) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"SourceCell";

    SourceCell *cell = (SourceCell *) [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if(cell == nil) cell = [[[SourceCell alloc] initWithFrame:CGRectZero reuseIdentifier:cellIdentifier] autorelease];
    [cell setSource:[self sourceAtIndexPath:indexPath]];

    return cell;
}

- (UITableViewCellAccessoryType) tableView:(UITableView *)tableView accessoryTypeForRowWithIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellAccessoryDisclosureIndicator;
}

- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    Source *source = [self sourceAtIndexPath:indexPath];

    FilteredPackageController *packages = [[[FilteredPackageController alloc]
        initWithDatabase:database_
        title:[source label]
        filter:@selector(isVisibleInSource:)
        with:source
    ] autorelease];

    [packages setDelegate:delegate_];

    [[self navigationController] pushViewController:packages animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    Source *source = [self sourceAtIndexPath:indexPath];
    return [source record] != nil;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    Source *source = [self sourceAtIndexPath:indexPath];
    [Sources_ removeObjectForKey:[source key]];
    [delegate_ syncData];
}

- (void) complete {
    [Sources_ setObject:[NSDictionary dictionaryWithObjectsAndKeys:
        @"deb", @"Type",
        href_, @"URI",
        @"./", @"Distribution",
    nil] forKey:[NSString stringWithFormat:@"deb:%@:./", href_]];

    [delegate_ syncData];
}

- (NSString *) getWarning {
    NSString *href(href_);
    NSRange colon([href rangeOfString:@"://"]);
    if (colon.location != NSNotFound)
        href = [href substringFromIndex:(colon.location + 3)];
    href = [href stringByAddingPercentEscapes];
    href = [CydiaURL(@"api/repotag/") stringByAppendingString:href];
    href = [href stringByCachingURLWithCurrentCDN];

    NSURL *url([NSURL URLWithString:href]);

    NSStringEncoding encoding;
    NSError *error(nil);

    if (NSString *warning = [NSString stringWithContentsOfURL:url usedEncoding:&encoding error:&error])
        return [warning length] == 0 ? nil : warning;
    return nil;
}

- (void) _endConnection:(NSURLConnection *)connection {
    // XXX: the memory management in this method is horribly awkward

    NSURLConnection **field = NULL;
    if (connection == trivial_)
        field = &trivial_;
    else if (connection == trivial_bz2_)
        field = &trivial_bz2_;
    else if (connection == trivial_gz_)
        field = &trivial_gz_;
    _assert(field != NULL);
    [connection release];
    *field = nil;

    if (
        trivial_ == nil &&
        trivial_bz2_ == nil &&
        trivial_gz_ == nil
    ) {
        bool defer(false);

        if (cydia_) {
            if (NSString *warning = [self yieldToSelector:@selector(getWarning)]) {
                defer = true;

                UIAlertView *alert = [[[UIAlertView alloc]
                    initWithTitle:UCLocalize("SOURCE_WARNING")
                    message:warning
                    delegate:self
                    cancelButtonTitle:UCLocalize("CANCEL")
                    otherButtonTitles:UCLocalize("ADD_ANYWAY"), nil
                ] autorelease];

                [alert setContext:@"warning"];
                [alert setNumberOfRows:1];
                [alert show];
            } else
                [self complete];
        } else if (error_ != nil) {
            UIAlertView *alert = [[[UIAlertView alloc]
                initWithTitle:UCLocalize("VERIFICATION_ERROR")
                message:[error_ localizedDescription]
                delegate:self
                cancelButtonTitle:UCLocalize("OK")
                otherButtonTitles:nil
            ] autorelease];

            [alert setContext:@"urlerror"];
            [alert show];
        } else {
            UIAlertView *alert = [[[UIAlertView alloc]
                initWithTitle:UCLocalize("NOT_REPOSITORY")
                message:UCLocalize("NOT_REPOSITORY_EX")
                delegate:self
                cancelButtonTitle:UCLocalize("OK")
                otherButtonTitles:nil
            ] autorelease];

            [alert setContext:@"trivial"];
            [alert show];
        }

        [delegate_ setStatusBarShowsProgress:NO];
        [delegate_ removeProgressHUD:hud_];

        [hud_ autorelease];
        hud_ = nil;

        if (!defer) {
            [href_ release];
            href_ = nil;
        }

        if (error_ != nil) {
            [error_ release];
            error_ = nil;
        }
    }
}

- (void) connection:(NSURLConnection *)connection didReceiveResponse:(NSHTTPURLResponse *)response {
    switch ([response statusCode]) {
        case 200:
            cydia_ = YES;
    }
}

- (void) connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    lprintf("connection:\"%s\" didFailWithError:\"%s\"", [href_ UTF8String], [[error localizedDescription] UTF8String]);
    if (error_ != nil)
        error_ = [error retain];
    [self _endConnection:connection];
}

- (void) connectionDidFinishLoading:(NSURLConnection *)connection {
    [self _endConnection:connection];
}

- (NSString *) title { return UCLocalize("SOURCES"); }

- (NSURLConnection *) _requestHRef:(NSString *)href method:(NSString *)method {
    NSMutableURLRequest *request = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:href]
        cachePolicy:NSURLRequestUseProtocolCachePolicy
        timeoutInterval:120.0
    ];

    [request setHTTPMethod:method];

    if (Machine_ != NULL)
        [request setValue:[NSString stringWithUTF8String:Machine_] forHTTPHeaderField:@"X-Machine"];
    if (UniqueID_ != nil)
        [request setValue:UniqueID_ forHTTPHeaderField:@"X-Unique-ID"];
    if (Role_ != nil)
        [request setValue:Role_ forHTTPHeaderField:@"X-Role"];

    return [[[NSURLConnection alloc] initWithRequest:request delegate:self] autorelease];
}

- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)button {
    NSString *context([alert context]);

    if ([context isEqualToString:@"source"]) {
        switch (button) {
            case 1: {
                NSString *href = [[alert textField] text];

                //installer_ = [[self _requestHRef:href method:@"GET"] retain];

                if (![href hasSuffix:@"/"])
                    href_ = [href stringByAppendingString:@"/"];
                else
                    href_ = href;
                href_ = [href_ retain];

                trivial_ = [[self _requestHRef:[href_ stringByAppendingString:@"Packages"] method:@"HEAD"] retain];
                trivial_bz2_ = [[self _requestHRef:[href_ stringByAppendingString:@"Packages.bz2"] method:@"HEAD"] retain];
                trivial_gz_ = [[self _requestHRef:[href_ stringByAppendingString:@"Packages.gz"] method:@"HEAD"] retain];
                //trivial_bz2_ = [[self _requestHRef:[href stringByAppendingString:@"dists/Release"] method:@"HEAD"] retain];

                cydia_ = false;

                // XXX: this is stupid
                hud_ = [[delegate_ addProgressHUD] retain];
                [hud_ setText:UCLocalize("VERIFYING_URL")];
            } break;

            case 0:
            break;

            _nodefault
        }

        [alert dismissWithClickedButtonIndex:-1 animated:YES];
    } else if ([context isEqualToString:@"trivial"])
        [alert dismissWithClickedButtonIndex:-1 animated:YES];
    else if ([context isEqualToString:@"urlerror"])
        [alert dismissWithClickedButtonIndex:-1 animated:YES];
    else if ([context isEqualToString:@"warning"]) {
        switch (button) {
            case 1:
                [self complete];
            break;

            case 0:
            break;

            _nodefault
        }

        [href_ release];
        href_ = nil;

        [alert dismissWithClickedButtonIndex:-1 animated:YES];
    }
}

- (id) initWithDatabase:(Database *)database {
    if ((self = [super init]) != nil) {
        [[self navigationItem] setTitle:UCLocalize("SOURCES")];
        [self updateButtonsForEditingStatus:NO animated:NO];

        database_ = database;
        sources_ = [[NSMutableArray arrayWithCapacity:16] retain];

        list_ = [[UITableView alloc] initWithFrame:[[self view] bounds] style:UITableViewStylePlain];
        [list_ setAutoresizingMask:UIViewAutoresizingFlexibleBoth];
        [[self view] addSubview:list_];

        [list_ setDataSource:self];
        [list_ setDelegate:self];

        [self reloadData];
    } return self;
}

- (void) reloadData {
    pkgSourceList list;
    if (!list.ReadMainList())
        return;

    [sources_ removeAllObjects];
    [sources_ addObjectsFromArray:[database_ sources]];
    _trace();
    [sources_ sortUsingSelector:@selector(compareByNameAndType:)];
    _trace();

    int count([sources_ count]);
    offset_ = 0;
    for (int i = 0; i != count; i++) {
        if ([[sources_ objectAtIndex:i] record] == nil)
            break;
        offset_++;
    }

    [list_ setEditing:NO];
    [self updateButtonsForEditingStatus:NO animated:NO];
    [list_ reloadData];
}

- (void) addButtonClicked {
    /*[book_ pushPage:[[[AddSourceController alloc]
        initWithBook:book_
        database:database_
    ] autorelease]];*/

    UIAlertView *alert = [[[UIAlertView alloc]
        initWithTitle:UCLocalize("ENTER_APT_URL")
        message:nil
        delegate:self
        cancelButtonTitle:UCLocalize("CANCEL")
        otherButtonTitles:UCLocalize("ADD_SOURCE"), nil
    ] autorelease];

    [alert setContext:@"source"];
    [alert setTransform:CGAffineTransformTranslate([alert transform], 0.0, 100.0)];

    [alert setNumberOfRows:1];
    [alert addTextFieldWithValue:@"http://" label:@""];

    UITextInputTraits *traits = [[alert textField] textInputTraits];
    [traits setAutocapitalizationType:UITextAutocapitalizationTypeNone];
    [traits setAutocorrectionType:UITextAutocorrectionTypeNo];
    [traits setKeyboardType:UIKeyboardTypeURL];
    // XXX: UIReturnKeyDone
    [traits setReturnKeyType:UIReturnKeyNext];

    [alert show];
}

- (void) updateButtonsForEditingStatus:(BOOL)editing animated:(BOOL)animated {
    [[self navigationItem] setLeftBarButtonItem:(editing ? [[[UIBarButtonItem alloc]
        initWithTitle:UCLocalize("ADD")
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(addButtonClicked)
    ] autorelease] : [[self navigationItem] backBarButtonItem]) animated:animated];

    [[self navigationItem] setRightBarButtonItem:[[[UIBarButtonItem alloc]
        initWithTitle:(editing ? UCLocalize("DONE") : UCLocalize("EDIT"))
        style:(editing ? UIBarButtonItemStyleDone : UIBarButtonItemStylePlain)
        target:self
        action:@selector(editButtonClicked)
    ] autorelease] animated:animated];

    if (IsWildcat_ && !editing)
        [[self navigationItem] setLeftBarButtonItem:[[[UIBarButtonItem alloc]
            initWithTitle:UCLocalize("SETTINGS")
            style:UIBarButtonItemStylePlain
            target:self
            action:@selector(settingsButtonClicked)
        ] autorelease]];
}

- (void) settingsButtonClicked {
    [delegate_ showSettings];
}

- (void) editButtonClicked {
    [list_ setEditing:![list_ isEditing] animated:YES];

    [self updateButtonsForEditingStatus:[list_ isEditing] animated:YES];
}

@end
/* }}} */

/* Installed Controller {{{ */
@interface InstalledController : FilteredPackageController {
    BOOL expert_;
}

- (id) initWithDatabase:(Database *)database;

- (void) updateRoleButton;
- (void) queueStatusDidChange;

@end

@implementation InstalledController

- (void) dealloc {
    [super dealloc];
}

- (NSString *) title { return UCLocalize("INSTALLED"); }

- (id) initWithDatabase:(Database *)database {
    if ((self = [super initWithDatabase:database title:UCLocalize("INSTALLED") filter:@selector(isInstalledAndUnfiltered:) with:[NSNumber numberWithBool:YES]]) != nil) {
        [self updateRoleButton];
        [self queueStatusDidChange];
    } return self;
}

#if !AlwaysReload
- (void) queueButtonClicked {
    [delegate_ queue];
}
#endif

- (void) queueStatusDidChange {
#if !AlwaysReload
    if (IsWildcat_) {
        if (Queuing_) {
            [[self navigationItem] setLeftBarButtonItem:[[[UIBarButtonItem alloc]
                initWithTitle:UCLocalize("QUEUE")
                style:UIBarButtonItemStyleDone
                target:self
                action:@selector(queueButtonClicked)
            ] autorelease]];
        } else {
            [[self navigationItem] setLeftBarButtonItem:nil];
        }
    }
#endif
}

- (void) reloadData {
    [packages_ reloadData];
}

- (void) updateRoleButton {
    if (Role_ != nil && ![Role_ isEqualToString:@"Developer"])
        [[self navigationItem] setRightBarButtonItem:[[[UIBarButtonItem alloc]
            initWithTitle:(expert_ ? UCLocalize("EXPERT") : UCLocalize("SIMPLE"))
            style:(expert_ ? UIBarButtonItemStyleDone : UIBarButtonItemStylePlain)
            target:self
            action:@selector(roleButtonClicked)
        ] autorelease]];
}

- (void) roleButtonClicked {
    [packages_ setObject:[NSNumber numberWithBool:expert_]];
    [packages_ reloadData];
    expert_ = !expert_;

    [self updateRoleButton];
}

- (void) setDelegate:(id)delegate {
    [super setDelegate:delegate];
    [packages_ setDelegate:delegate];
}

@end
/* }}} */

/* Home Controller {{{ */
@interface HomeController : CYBrowserController {
}

@end

@implementation HomeController

- (void) _setMoreHeaders:(NSMutableURLRequest *)request {
    [super _setMoreHeaders:request];

    if (ChipID_ != nil)
        [request setValue:ChipID_ forHTTPHeaderField:@"X-Chip-ID"];
    if (UniqueID_ != nil)
        [request setValue:UniqueID_ forHTTPHeaderField:@"X-Unique-ID"];
    if (PLMN_ != nil)
        [request setValue:PLMN_ forHTTPHeaderField:@"X-Carrier-ID"];
}

- (void) aboutButtonClicked {
    UIAlertView *alert([[[UIAlertView alloc] init] autorelease]);

    [alert setTitle:UCLocalize("ABOUT_CYDIA")];
    [alert addButtonWithTitle:UCLocalize("CLOSE")];
    [alert setCancelButtonIndex:0];

    [alert setMessage:
        @"Copyright (C) 2008-2010\n"
        "Jay Freeman (saurik)\n"
        "saurik@saurik.com\n"
        "http://www.saurik.com/"
    ];

    [alert show];
}

- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    //[[self navigationController] setNavigationBarHidden:YES animated:animated];
}

- (void) viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    //[[self navigationController] setNavigationBarHidden:NO animated:animated];
}

- (id) init {
    if ((self = [super init]) != nil) {
        [[self navigationItem] setLeftBarButtonItem:[[[UIBarButtonItem alloc]
            initWithTitle:UCLocalize("ABOUT")
            style:UIBarButtonItemStylePlain
            target:self
            action:@selector(aboutButtonClicked)
        ] autorelease]];
    } return self;
}

@end
/* }}} */
/* Manage Controller {{{ */
@interface ManageController : CYBrowserController {
}

- (void) queueStatusDidChange;
@end

@implementation ManageController

- (id) init {
    if ((self = [super init]) != nil) {
        [[self navigationItem] setTitle:UCLocalize("MANAGE")];

        [[self navigationItem] setLeftBarButtonItem:[[[UIBarButtonItem alloc]
            initWithTitle:UCLocalize("SETTINGS")
            style:UIBarButtonItemStylePlain
            target:self
            action:@selector(settingsButtonClicked)
        ] autorelease]];

        [self queueStatusDidChange];
    } return self;
}

- (void) settingsButtonClicked {
    [delegate_ showSettings];
}

#if !AlwaysReload
- (void) queueButtonClicked {
    [delegate_ queue];
}

- (void) applyLoadingTitle {
    // No "Loading" title.
}

- (void) applyRightButton {
    // No right button.
}
#endif

- (void) queueStatusDidChange {
#if !AlwaysReload
    if (!IsWildcat_ && Queuing_) {
        [[self navigationItem] setRightBarButtonItem:[[[UIBarButtonItem alloc]
            initWithTitle:UCLocalize("QUEUE")
            style:UIBarButtonItemStyleDone
            target:self
            action:@selector(queueButtonClicked)
        ] autorelease]];
    } else {
        [[self navigationItem] setRightBarButtonItem:nil];
    }
#endif
}

- (bool) isLoading {
    return false;
}

@end
/* }}} */

/* Refresh Bar {{{ */
@interface RefreshBar : UINavigationBar {
    UIProgressIndicator *indicator_;
    UITextLabel *prompt_;
    UIProgressBar *progress_;
    UINavigationButton *cancel_;
}

@end

@implementation RefreshBar

- (void) dealloc {
    [indicator_ release];
    [prompt_ release];
    [progress_ release];
    [cancel_ release];
    [super dealloc];
}

- (void) positionViews {
    CGRect frame = [cancel_ frame];
    frame.origin.x = [self frame].size.width - frame.size.width - 5;
    frame.origin.y = ([self frame].size.height - frame.size.height) / 2;
    [cancel_ setFrame:frame];

    CGSize prgsize = {75, 100};
    CGRect prgrect = {{
        [self frame].size.width - prgsize.width - 10,
        ([self frame].size.height - prgsize.height) / 2
    } , prgsize};
    [progress_ setFrame:prgrect];

    CGSize indsize([UIProgressIndicator defaultSizeForStyle:[indicator_ activityIndicatorViewStyle]]);
    unsigned indoffset = ([self frame].size.height - indsize.height) / 2;
    CGRect indrect = {{indoffset, indoffset}, indsize};
    [indicator_ setFrame:indrect];

    CGSize prmsize = {215, indsize.height + 4};
    CGRect prmrect = {{
        indoffset * 2 + indsize.width,
        unsigned([self frame].size.height - prmsize.height) / 2 - 1
    }, prmsize};
    [prompt_ setFrame:prmrect];
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];

    [self positionViews];
}

- (id) initWithFrame:(CGRect)frame delegate:(id)delegate {
    if ((self = [super initWithFrame:frame])) {
        [self setAutoresizingMask:UIViewAutoresizingFlexibleWidth];

        [self setTintColor:[UIColor colorWithRed:0.23 green:0.23 blue:0.23 alpha:1]];
        [self setBarStyle:UIBarStyleBlack];

        UIBarStyle barstyle([self _barStyle:NO]);
        bool ugly(barstyle == UIBarStyleDefault);

        UIProgressIndicatorStyle style = ugly ?
            UIProgressIndicatorStyleMediumBrown :
            UIProgressIndicatorStyleMediumWhite;

        indicator_ = [[UIProgressIndicator alloc] initWithFrame:CGRectZero];
        [indicator_ setStyle:style];
        [indicator_ startAnimation];
        [self addSubview:indicator_];

        prompt_ = [[UITextLabel alloc] initWithFrame:CGRectZero];
        [prompt_ setColor:[UIColor colorWithCGColor:(ugly ? Blueish_ : Off_)]];
        [prompt_ setBackgroundColor:[UIColor clearColor]];
        [prompt_ setFont:[UIFont systemFontOfSize:15]];
        [self addSubview:prompt_];

        progress_ = [[UIProgressBar alloc] initWithFrame:CGRectZero];
        [progress_ setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin];
        [progress_ setStyle:0];
        [self addSubview:progress_];

        cancel_ = [[UINavigationButton alloc] initWithTitle:UCLocalize("CANCEL") style:UINavigationButtonStyleHighlighted];
        [cancel_ setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin];
        [cancel_ addTarget:delegate action:@selector(cancelPressed) forControlEvents:UIControlEventTouchUpInside];
        [cancel_ setBarStyle:barstyle];

        [self positionViews];
    } return self;
}

- (void) cancel {
    [cancel_ removeFromSuperview];
}

- (void) start {
    [prompt_ setText:UCLocalize("UPDATING_DATABASE")];
    [progress_ setProgress:0];
    [self addSubview:cancel_];
}

- (void) stop {
    [cancel_ removeFromSuperview];
}

- (void) setPrompt:(NSString *)prompt {
    [prompt_ setText:prompt];
}

- (void) setProgress:(float)progress {
    [progress_ setProgress:progress];
}

@end
/* }}} */

@class CYNavigationController;

/* Cydia Tab Bar Controller {{{ */
@interface CYTabBarController : UITabBarController {
    _transient Database *database_;
}

@end

@implementation CYTabBarController

/* XXX: some logic should probably go here related to
freeing the view controllers on tab change */

- (void) reloadData {
    size_t count([[self viewControllers] count]);
    for (size_t i(0); i != count; ++i) {
        CYNavigationController *page([[self viewControllers] objectAtIndex:(count - i - 1)]);
        [page reloadData];
    }
}

- (id) initWithDatabase:(Database *)database {
    if ((self = [super init]) != nil) {
        database_ = database;
    } return self;
}

@end
/* }}} */

/* Cydia Navigation Controller {{{ */
@interface CYNavigationController : UINavigationController {
    _transient Database *database_;
    _transient id<UINavigationControllerDelegate> delegate_;
}

- (id) initWithDatabase:(Database *)database;
- (void) reloadData;

@end


@implementation CYNavigationController

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    // Inherit autorotation settings for modal parents.
    if ([self parentViewController] && [[self parentViewController] modalViewController] == self) {
        return [[self parentViewController] shouldAutorotateToInterfaceOrientation:orientation];
    } else {
        return [super shouldAutorotateToInterfaceOrientation:orientation];
    }
}

- (void) dealloc {
    [super dealloc];
}

- (void) reloadData {
    size_t count([[self viewControllers] count]);
    for (size_t i(0); i != count; ++i) {
        CYViewController *page([[self viewControllers] objectAtIndex:(count - i - 1)]);
        [page reloadData];
    }
}

- (void) setDelegate:(id<UINavigationControllerDelegate>)delegate {
    delegate_ = delegate;
}

- (id) initWithDatabase:(Database *)database {
    if ((self = [super init]) != nil) {
        database_ = database;
    } return self;
}

@end
/* }}} */
/* Cydia:// Protocol {{{ */
@interface CydiaURLProtocol : NSURLProtocol {
}

@end

@implementation CydiaURLProtocol

+ (BOOL) canInitWithRequest:(NSURLRequest *)request {
    NSURL *url([request URL]);
    if (url == nil)
        return NO;
    NSString *scheme([[url scheme] lowercaseString]);
    if (scheme == nil || ![scheme isEqualToString:@"cydia"])
        return NO;
    return YES;
}

+ (NSURLRequest *) canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void) _returnPNGWithImage:(UIImage *)icon forRequest:(NSURLRequest *)request {
    id<NSURLProtocolClient> client([self client]);
    if (icon == nil)
        [client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorFileDoesNotExist userInfo:nil]];
    else {
        NSData *data(UIImagePNGRepresentation(icon));

        NSURLResponse *response([[[NSURLResponse alloc] initWithURL:[request URL] MIMEType:@"image/png" expectedContentLength:-1 textEncodingName:nil] autorelease]);
        [client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [client URLProtocol:self didLoadData:data];
        [client URLProtocolDidFinishLoading:self];
    }
}

- (void) startLoading {
    id<NSURLProtocolClient> client([self client]);
    NSURLRequest *request([self request]);

    NSURL *url([request URL]);
    NSString *href([url absoluteString]);

    NSString *path([href substringFromIndex:8]);
    NSRange slash([path rangeOfString:@"/"]);

    NSString *command;
    if (slash.location == NSNotFound) {
        command = path;
        path = nil;
    } else {
        command = [path substringToIndex:slash.location];
        path = [path substringFromIndex:(slash.location + 1)];
    }

    Database *database([Database sharedInstance]);

    if ([command isEqualToString:@"package-icon"]) {
        if (path == nil)
            goto fail;
        path = [path stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        Package *package([database packageWithName:path]);
        if (package == nil)
            goto fail;
        UIImage *icon([package icon]);
        [self _returnPNGWithImage:icon forRequest:request];
    } else if ([command isEqualToString:@"source-icon"]) {
        if (path == nil)
            goto fail;
        path = [path stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        NSString *source(Simplify(path));
        UIImage *icon([UIImage imageAtPath:[NSString stringWithFormat:@"%@/Sources/%@.png", App_, source]]);
        if (icon == nil)
            icon = [UIImage applicationImageNamed:@"unknown.png"];
        [self _returnPNGWithImage:icon forRequest:request];
    } else if ([command isEqualToString:@"uikit-image"]) {
        if (path == nil)
            goto fail;
        path = [path stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        UIImage *icon(_UIImageWithName(path));
        [self _returnPNGWithImage:icon forRequest:request];
    } else if ([command isEqualToString:@"section-icon"]) {
        if (path == nil)
            goto fail;
        path = [path stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        NSString *section(Simplify(path));
        UIImage *icon([UIImage imageAtPath:[NSString stringWithFormat:@"%@/Sections/%@.png", App_, section]]);
        if (icon == nil)
            icon = [UIImage applicationImageNamed:@"unknown.png"];
        [self _returnPNGWithImage:icon forRequest:request];
    } else fail: {
        [client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorResourceUnavailable userInfo:nil]];
    }
}

- (void) stopLoading {
}

@end
/* }}} */

/* Sections Controller {{{ */
@interface SectionsController : CYViewController <
    UITableViewDataSource,
    UITableViewDelegate
> {
    _transient Database *database_;
    NSMutableArray *sections_;
    NSMutableArray *filtered_;
    UITableView *list_;
    UIView *accessory_;
    BOOL editing_;
}

- (id) initWithDatabase:(Database *)database;
- (void) reloadData;
- (void) resetView;

- (void) editButtonClicked;

@end

@implementation SectionsController

- (void) dealloc {
    [list_ setDataSource:nil];
    [list_ setDelegate:nil];

    [sections_ release];
    [filtered_ release];
    [list_ release];
    [accessory_ release];
    [super dealloc];
}

- (void) viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [list_ deselectRowAtIndexPath:[list_ indexPathForSelectedRow] animated:animated];
}

- (Section *) sectionAtIndexPath:(NSIndexPath *)indexPath {
    Section *section = (editing_ ? [sections_ objectAtIndex:[indexPath row]] : ([indexPath row] == 0 ? nil : [filtered_ objectAtIndex:([indexPath row] - 1)]));
    return section;
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return editing_ ? [sections_ count] : [filtered_ count] + 1;
}

/*- (CGFloat) tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 45.0f;
}*/

- (UITableViewCell *) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuseIdentifier = @"SectionCell";

    SectionCell *cell = (SectionCell *) [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (cell == nil)
        cell = [[[SectionCell alloc] initWithFrame:CGRectZero reuseIdentifier:reuseIdentifier] autorelease];

    [cell setSection:[self sectionAtIndexPath:indexPath] editing:editing_];

    return cell;
}

- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editing_)
        return;

    Section *section = [self sectionAtIndexPath:indexPath];
    NSString *name = [section name];
    NSString *title;

    if ([indexPath row] == 0) {
        section = nil;
        name = nil;
        title = UCLocalize("ALL_PACKAGES");
    } else {
        if (name != nil) {
            name = [NSString stringWithString:name];
            title = [[NSBundle mainBundle] localizedStringForKey:Simplify(name) value:nil table:@"Sections"];
        } else {
            name = @"";
            title = UCLocalize("NO_SECTION");
        }
    }

    FilteredPackageController *table = [[[FilteredPackageController alloc]
        initWithDatabase:database_
        title:title
        filter:@selector(isVisibleInSection:)
        with:name
    ] autorelease];

    [table setDelegate:delegate_];

    [[self navigationController] pushViewController:table animated:YES];
}

- (NSString *) title { return UCLocalize("SECTIONS"); }

- (id) initWithDatabase:(Database *)database {
    if ((self = [super init]) != nil) {
        database_ = database;

        [[self navigationItem] setTitle:UCLocalize("SECTIONS")];

        sections_ = [[NSMutableArray arrayWithCapacity:16] retain];
        filtered_ = [[NSMutableArray arrayWithCapacity:16] retain];

        list_ = [[UITableView alloc] initWithFrame:[[self view] bounds]];
        [list_ setAutoresizingMask:UIViewAutoresizingFlexibleBoth];
        [list_ setRowHeight:45.0f];
        [[self view] addSubview:list_];

        [list_ setDataSource:self];
        [list_ setDelegate:self];

        [self reloadData];
    } return self;
}

- (void) reloadData {
    NSArray *packages = [database_ packages];

    [sections_ removeAllObjects];
    [filtered_ removeAllObjects];

    NSMutableDictionary *sections([NSMutableDictionary dictionaryWithCapacity:32]);

    _trace();
    for (Package *package in packages) {
        NSString *name([package section]);
        NSString *key(name == nil ? @"" : name);

        Section *section;

        _profile(SectionsView$reloadData$Section)
            section = [sections objectForKey:key];
            if (section == nil) {
                _profile(SectionsView$reloadData$Section$Allocate)
                    section = [[[Section alloc] initWithName:name localize:YES] autorelease];
                    [sections setObject:section forKey:key];
                _end
            }
        _end

        [section addToCount];

        _profile(SectionsView$reloadData$Filter)
            if (![package valid] || ![package visible])
                continue;
        _end

        [section addToRow];
    }
    _trace();

    [sections_ addObjectsFromArray:[sections allValues]];

    [sections_ sortUsingSelector:@selector(compareByLocalized:)];

    for (Section *section in sections_) {
        size_t count([section row]);
        if (count == 0)
            continue;

        section = [[[Section alloc] initWithName:[section name] localized:[section localized]] autorelease];
        [section setCount:count];
        [filtered_ addObject:section];
    }

    [[self navigationItem] setRightBarButtonItem:[[[UIBarButtonItem alloc]
        initWithTitle:([sections_ count] == 0 ? nil : UCLocalize("EDIT"))
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(editButtonClicked)
    ] autorelease] animated:([[self navigationItem] rightBarButtonItem] != nil)];

    [list_ reloadData];
    _trace();
}

- (void) resetView {
    if (editing_)
        [self editButtonClicked];
}

- (void) editButtonClicked {
    if ((editing_ = !editing_))
        [list_ reloadData];
    else
        [delegate_ updateData];

    [[self navigationItem] setTitle:editing_ ? UCLocalize("SECTION_VISIBILITY") : UCLocalize("SECTIONS")];
    [[[self navigationItem] rightBarButtonItem] setTitle:[sections_ count] == 0 ? nil : editing_ ? UCLocalize("DONE") : UCLocalize("EDIT")];
    [[[self navigationItem] rightBarButtonItem] setStyle:editing_ ? UIBarButtonItemStyleDone : UIBarButtonItemStylePlain];
}

- (UIView *) accessoryView {
    return accessory_;
}

@end
/* }}} */
/* Changes Controller {{{ */
@interface ChangesController : CYViewController <
    UITableViewDataSource,
    UITableViewDelegate
> {
    _transient Database *database_;
    CFMutableArrayRef packages_;
    NSMutableArray *sections_;
    UITableView *list_;
    unsigned upgrades_;
    BOOL hasSentFirstLoad_;
}

- (id) initWithDatabase:(Database *)database delegate:(id)delegate;
- (void) reloadData;

@end

@implementation ChangesController

- (void) dealloc {
    [list_ setDelegate:nil];
    [list_ setDataSource:nil];

    CFRelease(packages_);

    [sections_ release];
    [list_ release];
    [super dealloc];
}

- (void) viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!hasSentFirstLoad_) {
        hasSentFirstLoad_ = YES;
        [self performSelector:@selector(reloadData) withObject:nil afterDelay:0.0];
    } else {
        [list_ deselectRowAtIndexPath:[list_ indexPathForSelectedRow] animated:animated];
    }
}

- (NSInteger) numberOfSectionsInTableView:(UITableView *)list {
    NSInteger count([sections_ count]);
    return count == 0 ? 1 : count;
}

- (NSString *) tableView:(UITableView *)list titleForHeaderInSection:(NSInteger)section {
    if ([sections_ count] == 0)
        return nil;
    return [[sections_ objectAtIndex:section] name];
}

- (NSInteger) tableView:(UITableView *)list numberOfRowsInSection:(NSInteger)section {
    if ([sections_ count] == 0)
        return 0;
    return [[sections_ objectAtIndex:section] count];
}

- (Package *) packageAtIndex:(NSUInteger)index {
    return (Package *) CFArrayGetValueAtIndex(packages_, index);
}

- (Package *) packageAtIndexPath:(NSIndexPath *)path {
    Section *section([sections_ objectAtIndex:[path section]]);
    NSInteger row([path row]);
    return [self packageAtIndex:([section row] + row)];
}

- (UITableViewCell *) tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    PackageCell *cell((PackageCell *) [table dequeueReusableCellWithIdentifier:@"Package"]);
    if (cell == nil)
        cell = [[[PackageCell alloc] init] autorelease];
    [cell setPackage:[self packageAtIndexPath:path]];
    return cell;
}

/*- (CGFloat) tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    return [PackageCell heightForPackage:[self packageAtIndexPath:path]];
}*/

- (NSIndexPath *) tableView:(UITableView *)table willSelectRowAtIndexPath:(NSIndexPath *)path {
    Package *package([self packageAtIndexPath:path]);
    PackageController *view([delegate_ packageController]);
    [view setDelegate:delegate_];
    [view setPackage:package];
    [[self navigationController] pushViewController:view animated:YES];
    return path;
}

- (void) refreshButtonClicked {
    [delegate_ beginUpdate];
    [[self navigationItem] setLeftBarButtonItem:nil animated:YES];
}

- (void) upgradeButtonClicked {
    [delegate_ distUpgrade];
}

- (NSString *) title { return UCLocalize("CHANGES"); }

- (id) initWithDatabase:(Database *)database delegate:(id)delegate {
    if ((self = [super init]) != nil) {
        database_ = database;
        [[self navigationItem] setTitle:UCLocalize("CHANGES")];

        packages_ = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);

        sections_ = [[NSMutableArray arrayWithCapacity:16] retain];

        list_ = [[UITableView alloc] initWithFrame:[[self view] bounds] style:UITableViewStylePlain];
        [list_ setAutoresizingMask:UIViewAutoresizingFlexibleBoth];
        [list_ setRowHeight:73.0f];
        [[self view] addSubview:list_];

        [list_ setDataSource:self];
        [list_ setDelegate:self];

        delegate_ = delegate;
    } return self;
}

- (void) _reloadPackages:(NSArray *)packages {
    _trace();
    for (Package *package in packages)
        if ([package upgradableAndEssential:YES] || [package visible])
            CFArrayAppendValue(packages_, package);

    _trace();
    [(NSMutableArray *) packages_ radixSortUsingFunction:reinterpret_cast<SKRadixFunction>(&PackageChangesRadix) withContext:NULL];
    _trace();
}

- (void) reloadData {
    NSArray *packages = [database_ packages];

    CFArrayRemoveAllValues(packages_);

    [sections_ removeAllObjects];

#if 1
    UIProgressHUD *hud([delegate_ addProgressHUD]);
    [hud setText:UCLocalize("LOADING")];
    //NSLog(@"HUD:%@::%@", delegate_, hud);
    [self yieldToSelector:@selector(_reloadPackages:) withObject:packages];
    [delegate_ removeProgressHUD:hud];
#else
    [self _reloadPackages:packages];
#endif

    Section *upgradable = [[[Section alloc] initWithName:UCLocalize("AVAILABLE_UPGRADES") localize:NO] autorelease];
    Section *ignored = [[[Section alloc] initWithName:UCLocalize("IGNORED_UPGRADES") localize:NO] autorelease];
    Section *section = nil;
    NSDate *last = nil;

    upgrades_ = 0;
    bool unseens = false;

    CFDateFormatterRef formatter(CFDateFormatterCreate(NULL, Locale_, kCFDateFormatterMediumStyle, kCFDateFormatterMediumStyle));

    for (size_t offset = 0, count = CFArrayGetCount(packages_); offset != count; ++offset) {
        Package *package = [self packageAtIndex:offset];

        BOOL uae = [package upgradableAndEssential:YES];

        if (!uae) {
            unseens = true;
            NSDate *seen;

            _profile(ChangesController$reloadData$Remember)
                seen = [package seen];
            _end

            if (section == nil || last != seen && (seen == nil || [seen compare:last] != NSOrderedSame)) {
                last = seen;

                NSString *name;
                if (seen == nil)
                    name = UCLocalize("UNKNOWN");
                else {
                    name = (NSString *) CFDateFormatterCreateStringWithDate(NULL, formatter, (CFDateRef) seen);
                    [name autorelease];
                }

                _profile(ChangesController$reloadData$Allocate)
                    name = [NSString stringWithFormat:UCLocalize("NEW_AT"), name];
                    section = [[[Section alloc] initWithName:name row:offset localize:NO] autorelease];
                    [sections_ addObject:section];
                _end
            }

            [section addToCount];
        } else if ([package ignored])
            [ignored addToCount];
        else {
            ++upgrades_;
            [upgradable addToCount];
        }
    }
    _trace();

    CFRelease(formatter);

    if (unseens) {
        Section *last = [sections_ lastObject];
        size_t count = [last count];
        CFArrayReplaceValues(packages_, CFRangeMake(CFArrayGetCount(packages_) - count, count), NULL, 0);
        [sections_ removeLastObject];
    }

    if ([ignored count] != 0)
        [sections_ insertObject:ignored atIndex:0];
    if (upgrades_ != 0)
        [sections_ insertObject:upgradable atIndex:0];

    [list_ reloadData];

    if (upgrades_ > 0)
        [[self navigationItem] setRightBarButtonItem:[[[UIBarButtonItem alloc]
            initWithTitle:[NSString stringWithFormat:UCLocalize("PARENTHETICAL"), UCLocalize("UPGRADE"), [NSString stringWithFormat:@"%u", upgrades_]]
            style:UIBarButtonItemStylePlain
            target:self
            action:@selector(upgradeButtonClicked)
        ] autorelease]];

    if (![delegate_ updating])
        [[self navigationItem] setLeftBarButtonItem:[[[UIBarButtonItem alloc]
            initWithTitle:UCLocalize("REFRESH")
            style:UIBarButtonItemStylePlain
            target:self
            action:@selector(refreshButtonClicked)
        ] autorelease]];
}

@end
/* }}} */
/* Search Controller {{{ */
@interface SearchController : FilteredPackageController <
    UISearchBarDelegate
> {
    UISearchBar *search_;
}

- (id) initWithDatabase:(Database *)database;
- (void) reloadData;

@end

@implementation SearchController

- (void) dealloc {
    [search_ release];
    [super dealloc];
}

- (void) searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [packages_ setObject:[search_ text] forFilter:@selector(isUnfilteredAndSearchedForBy:)];
    [search_ resignFirstResponder];
    [self reloadData];
}

- (void) searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
    [packages_ setObject:text forFilter:@selector(isUnfilteredAndSelectedForBy:)];
    [self reloadData];
}

- (NSString *) title { return nil; }

- (id) initWithDatabase:(Database *)database {
    return [super initWithDatabase:database title:UCLocalize("SEARCH") filter:@selector(isUnfilteredAndSearchedForBy:) with:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!search_) {
        search_ = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, [[self view] bounds].size.width, 44.0f)];
        [search_ layoutSubviews];
        [search_ setPlaceholder:UCLocalize("SEARCH_EX")];
        UITextField *textField = [search_ searchField];
        [textField setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin];
        [search_ setDelegate:self];
        [textField setEnablesReturnKeyAutomatically:NO];
        [[self navigationItem] setTitleView:textField];
    }
}

- (void) _reloadData {
}

- (void) reloadData {
    _profile(SearchController$reloadData)
        [packages_ reloadData];
    _end
    PrintTimes();
    [packages_ resetCursor];
}

- (void) didSelectPackage:(Package *)package {
    [search_ resignFirstResponder];
    [super didSelectPackage:package];
}

@end
/* }}} */
/* Settings Controller {{{ */
@interface SettingsController : CYViewController <
    UITableViewDataSource,
    UITableViewDelegate
> {
    _transient Database *database_;
    NSString *name_;
    Package *package_;
    UITableView *table_;
    UISwitch *subscribedSwitch_;
    UISwitch *ignoredSwitch_;
    UITableViewCell *subscribedCell_;
    UITableViewCell *ignoredCell_;
}

- (id) initWithDatabase:(Database *)database package:(NSString *)package;

@end

@implementation SettingsController

- (void) dealloc {
    [name_ release];
    if (package_ != nil)
        [package_ release];
    [table_ release];
    [subscribedSwitch_ release];
    [ignoredSwitch_ release];
    [subscribedCell_ release];
    [ignoredCell_ release];

    [super dealloc];
}

- (NSInteger) numberOfSectionsInTableView:(UITableView *)tableView {
    if (package_ == nil)
        return 0;

    return 1;
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (package_ == nil)
        return 0;

    return 1;
}

- (NSString *) tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return UCLocalize("SHOW_ALL_CHANGES_EX");
}

- (void) onSomething:(BOOL)value withKey:(NSString *)key {
    if (package_ == nil)
        return;

    NSMutableDictionary *metadata([package_ metadata]);

    BOOL before;
    if (NSNumber *number = [metadata objectForKey:key])
        before = [number boolValue];
    else
        before = NO;

    if (value != before) {
        [metadata setObject:[NSNumber numberWithBool:value] forKey:key];
        Changed_ = true;
        [delegate_ updateData];
    }
}

- (void) onSubscribed:(id)control {
    [self onSomething:(int) [control isOn] withKey:@"IsSubscribed"];
}

- (void) onIgnored:(id)control {
    [self onSomething:(int) [control isOn] withKey:@"IsIgnored"];
}

- (UITableViewCell *) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (package_ == nil)
        return nil;

    switch ([indexPath row]) {
        case 0: return subscribedCell_;
        case 1: return ignoredCell_;

        _nodefault
    }

    return nil;
}

- (NSString *) title { return UCLocalize("SETTINGS"); }

- (id) initWithDatabase:(Database *)database package:(NSString *)package {
    if ((self = [super init])) {
        database_ = database;
        name_ = [package retain];

        [[self navigationItem] setTitle:UCLocalize("SETTINGS")];

        table_ = [[UITableView alloc] initWithFrame:[[self view] bounds] style:UITableViewStyleGrouped];
        [table_ setAutoresizingMask:UIViewAutoresizingFlexibleBoth];
        [[self view] addSubview:table_];

        subscribedSwitch_ = [[UISwitch alloc] initWithFrame:CGRectMake(0, 0, 50, 20)];
        [subscribedSwitch_ setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin];
        [subscribedSwitch_ addTarget:self action:@selector(onSubscribed:) forEvents:UIControlEventValueChanged];

        ignoredSwitch_ = [[UISwitch alloc] initWithFrame:CGRectMake(0, 0, 50, 20)];
        [ignoredSwitch_ setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin];
        [ignoredSwitch_ addTarget:self action:@selector(onIgnored:) forEvents:UIControlEventValueChanged];

        subscribedCell_ = [[UITableViewCell alloc] init];
        [subscribedCell_ setText:UCLocalize("SHOW_ALL_CHANGES")];
        [subscribedCell_ setAccessoryView:subscribedSwitch_];
        [subscribedCell_ setSelectionStyle:UITableViewCellSelectionStyleNone];

        ignoredCell_ = [[UITableViewCell alloc] init];
        [ignoredCell_ setText:UCLocalize("IGNORE_UPGRADES")];
        [ignoredCell_ setAccessoryView:ignoredSwitch_];
        [ignoredCell_ setSelectionStyle:UITableViewCellSelectionStyleNone];

        [table_ setDataSource:self];
        [table_ setDelegate:self];
        [self reloadData];
    } return self;
}

- (void) reloadData {
    if (package_ != nil)
        [package_ autorelease];
    package_ = [database_ packageWithName:name_];
    if (package_ != nil) {
        [package_ retain];
        [subscribedSwitch_ setOn:([package_ subscribed] ? 1 : 0) animated:NO];
        [ignoredSwitch_ setOn:([package_ ignored] ? 1 : 0) animated:NO];
    }

    [table_ reloadData];
}

@end
/* }}} */
/* Signature Controller {{{ */
@interface SignatureController : CYBrowserController {
    _transient Database *database_;
    NSString *package_;
}

- (id) initWithDatabase:(Database *)database package:(NSString *)package;

@end

@implementation SignatureController

- (void) dealloc {
    [package_ release];
    [super dealloc];
}

- (void) webView:(WebView *)view didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame {
    // XXX: dude!
    [super webView:view didClearWindowObject:window forFrame:frame];
}

- (id) initWithDatabase:(Database *)database package:(NSString *)package {
    if ((self = [super init]) != nil) {
        database_ = database;
        package_ = [package retain];
        [self reloadData];
    } return self;
}

- (void) reloadData {
    [self loadURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"signature" ofType:@"html"]]];
}

@end
/* }}} */

/* Role Controller {{{ */
@interface RoleController : CYViewController <
    UITableViewDataSource,
    UITableViewDelegate
> {
    _transient Database *database_;
    // XXX: ok, "roledelegate_"?...
    _transient id roledelegate_;
    UITableView *table_;
    UISegmentedControl *segment_;
    UIView *container_;
}

- (void) showDoneButton;
- (void) resizeSegmentedControl;

@end

@implementation RoleController
- (void) dealloc {
    [table_ release];
    [segment_ release];
    [container_ release];

    [super dealloc];
}

- (id) initWithDatabase:(Database *)database delegate:(id)delegate {
    if ((self = [super init])) {
        database_ = database;
        roledelegate_ = delegate;

        [[self navigationItem] setTitle:UCLocalize("WHO_ARE_YOU")];

        NSArray *items = [NSArray arrayWithObjects:
            UCLocalize("USER"),
            UCLocalize("HACKER"),
            UCLocalize("DEVELOPER"),
        nil];
        segment_ = [[UISegmentedControl alloc] initWithItems:items];
        container_ = [[UIView alloc] initWithFrame:CGRectMake(0, 0, [[self view] frame].size.width, 44.0f)];
        [container_ addSubview:segment_];

        int index = -1;
        if ([Role_ isEqualToString:@"User"]) index = 0;
        if ([Role_ isEqualToString:@"Hacker"]) index = 1;
        if ([Role_ isEqualToString:@"Developer"]) index = 2;
        if (index != -1) {
            [segment_ setSelectedSegmentIndex:index];
            [self showDoneButton];
        }

        [segment_ addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
        [self resizeSegmentedControl];

        table_ = [[UITableView alloc] initWithFrame:[[self view] bounds] style:UITableViewStyleGrouped];
        [table_ setAutoresizingMask:UIViewAutoresizingFlexibleBoth];
        [table_ setDelegate:self];
        [table_ setDataSource:self];
        [[self view] addSubview:table_];
        [table_ reloadData];
    } return self;
}

- (void) resizeSegmentedControl {
    CGFloat width = [[self view] frame].size.width;
    [segment_ setFrame:CGRectMake(width / 32.0f, 0, width - (width / 32.0f * 2.0f), 44.0f)];
}

- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self resizeSegmentedControl];
}

- (void) willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation duration:(NSTimeInterval)duration {
    [self resizeSegmentedControl];
}

- (void) didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [self resizeSegmentedControl];
}

- (void) save {
    NSString *role(nil);

    switch ([segment_ selectedSegmentIndex]) {
        case 0: role = @"User"; break;
        case 1: role = @"Hacker"; break;
        case 2: role = @"Developer"; break;

        _nodefault
    }

    if (![role isEqualToString:Role_]) {
        bool rolling(Role_ == nil);
        Role_ = role;

        Settings_ = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            Role_, @"Role",
        nil];

        [Metadata_ setObject:Settings_ forKey:@"Settings"];

        Changed_ = true;

        if (rolling)
            [roledelegate_ loadData];
        else
            [roledelegate_ updateData];
    }
}

- (void) segmentChanged:(UISegmentedControl *)control {
    [self showDoneButton];
}

- (void) saveAndClose {
    [self save];

    [[self navigationItem] setRightBarButtonItem:nil];
    [[self navigationController] dismissModalViewControllerAnimated:YES];
}

- (void) doneButtonClicked {
    UIActivityIndicatorView *spinner = [[[UIActivityIndicatorView alloc] initWithFrame:CGRectMake(0, 0, 20.0f, 20.0f)] autorelease];
    [spinner startAnimating];
    UIBarButtonItem *spinItem = [[[UIBarButtonItem alloc] initWithCustomView:spinner] autorelease];
    [[self navigationItem] setRightBarButtonItem:spinItem];

    [self performSelector:@selector(saveAndClose) withObject:nil afterDelay:0];
}

- (void) showDoneButton {
    [[self navigationItem] setRightBarButtonItem:[[[UIBarButtonItem alloc]
        initWithTitle:UCLocalize("DONE")
        style:UIBarButtonItemStyleDone
        target:self
        action:@selector(doneButtonClicked)
    ] autorelease] animated:([[self navigationItem] rightBarButtonItem] == nil)];
}

- (NSInteger) numberOfSectionsInTableView:(UITableView *)tableView {
    // XXX: For not having a single cell in the table, this sure is a lot of sections.
    return 6;
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 0; // :(
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    return nil; // This method is required by the protocol.
}

- (NSString *) tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1)
        return UCLocalize("ROLE_EX");
    if (section == 4)
        return [NSString stringWithFormat:
            @"%@: %@\n%@: %@\n%@: %@",
            UCLocalize("USER"), UCLocalize("USER_EX"),
            UCLocalize("HACKER"), UCLocalize("HACKER_EX"),
            UCLocalize("DEVELOPER"), UCLocalize("DEVELOPER_EX")
        ];
    else return nil;
}

- (CGFloat) tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return section == 3 ? 44.0f : 0;
}

- (UIView *) tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return section == 3 ? container_ : nil;
}

@end
/* }}} */
/* Stash Controller {{{ */
@interface CYStashController : CYViewController {
    // XXX: just delete these things
    _transient UIActivityIndicatorView *spinner_;
    _transient UILabel *status_;
    _transient UILabel *caption_;
}
@end

@implementation CYStashController
- (id) init {
    if ((self = [super init])) {
        [[self view] setBackgroundColor:[UIColor viewFlipsideBackgroundColor]];

        spinner_ = [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge] autorelease];
        CGRect spinrect = [spinner_ frame];
        spinrect.origin.x = ([[self view] frame].size.width / 2) - (spinrect.size.width / 2);
        spinrect.origin.y = [[self view] frame].size.height - 80.0f;
        [spinner_ setFrame:spinrect];
        [spinner_ setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin];
        [[self view] addSubview:spinner_];
        [spinner_ startAnimating];

        CGRect captrect;
        captrect.size.width = [[self view] frame].size.width;
        captrect.size.height = 40.0f;
        captrect.origin.x = 0;
        captrect.origin.y = ([[self view] frame].size.height / 2) - (captrect.size.height * 2);
        caption_ = [[[UILabel alloc] initWithFrame:captrect] autorelease];
        [caption_ setText:@"Initializing Filesystem"];
        [caption_ setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin];
        [caption_ setFont:[UIFont boldSystemFontOfSize:28.0f]];
        [caption_ setTextColor:[UIColor whiteColor]];
        [caption_ setBackgroundColor:[UIColor clearColor]];
        [caption_ setShadowColor:[UIColor blackColor]];
        [caption_ setTextAlignment:UITextAlignmentCenter];
        [[self view] addSubview:caption_];

        CGRect statusrect;
        statusrect.size.width = [[self view] frame].size.width;
        statusrect.size.height = 30.0f;
        statusrect.origin.x = 0;
        statusrect.origin.y = ([[self view] frame].size.height / 2) - statusrect.size.height;
        status_ = [[[UILabel alloc] initWithFrame:statusrect] autorelease];
        [status_ setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin];
        [status_ setText:@"(Cydia will exit when complete.)"];
        [status_ setFont:[UIFont systemFontOfSize:16.0f]];
        [status_ setTextColor:[UIColor whiteColor]];
        [status_ setBackgroundColor:[UIColor clearColor]];
        [status_ setShadowColor:[UIColor blackColor]];
        [status_ setTextAlignment:UITextAlignmentCenter];
        [[self view] addSubview:status_];
    } return self;
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return IsWildcat_ || orientation == UIInterfaceOrientationPortrait;
}
@end
/* }}} */

/* Cydia Container {{{ */
@interface CYContainer : UIViewController <ProgressDelegate> {
    _transient Database *database_;
    RefreshBar *refreshbar_;

    bool dropped_;
    bool updating_;
    // XXX: ok, "updatedelegate_"?...
    _transient NSObject<CydiaDelegate> *updatedelegate_;
    // XXX: can't we query for this variable when we need it?
    _transient UITabBarController *root_;
}

- (void) setTabBarController:(UITabBarController *)controller;

- (void) dropBar:(BOOL)animated;
- (void) beginUpdate;
- (void) raiseBar:(BOOL)animated;
- (BOOL) updating;

@end

@implementation CYContainer

- (BOOL) _reallyWantsFullScreenLayout {
    return YES;
}

// NOTE: UIWindow only sends the top controller these messages,
//       So we have to forward them on.

- (void) viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [root_ viewDidAppear:animated];
}

- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [root_ viewWillAppear:animated];
}

- (void) viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [root_ viewDidDisappear:animated];
}

- (void) viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [root_ viewWillDisappear:animated];
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return ![updatedelegate_ hudIsShowing] && (IsWildcat_ || orientation == UIInterfaceOrientationPortrait);
}

- (void) setTabBarController:(UITabBarController *)controller {
    root_ = controller;
    [[self view] addSubview:[root_ view]];
}

- (void) setUpdate:(NSDate *)date {
    [self beginUpdate];
}

- (void) beginUpdate {
    [self dropBar:YES];
    [refreshbar_ start];

    updating_ = true;

    [NSThread
        detachNewThreadSelector:@selector(performUpdate)
        toTarget:self
        withObject:nil
    ];
}

- (void) performUpdate { _pooled
    Status status;
    status.setDelegate(self);
    [database_ updateWithStatus:status];

    [self
        performSelectorOnMainThread:@selector(completeUpdate)
        withObject:nil
        waitUntilDone:NO
    ];
}

- (void) completeUpdate {
    if (!updating_)
        return;
    updating_ = false;

    [self raiseBar:YES];
    [refreshbar_ stop];
    [updatedelegate_ performSelector:@selector(reloadData) withObject:nil afterDelay:0];
}

- (void) cancelUpdate {
    updating_ = false;
    [self raiseBar:YES];
    [refreshbar_ stop];
    [updatedelegate_ performSelector:@selector(updateData) withObject:nil afterDelay:0];
}

- (void) cancelPressed {
    [self cancelUpdate];
}

- (BOOL) updating {
    return updating_;
}

- (void) setProgressError:(NSString *)error withTitle:(NSString *)title {
    [refreshbar_ setPrompt:[NSString stringWithFormat:UCLocalize("COLON_DELIMITED"), UCLocalize("ERROR"), error]];
}

- (void) startProgress {
}

- (void) setProgressTitle:(NSString *)title {
    [self
        performSelectorOnMainThread:@selector(_setProgressTitle:)
        withObject:title
        waitUntilDone:YES
    ];
}

- (bool) isCancelling:(size_t)received {
    return !updating_;
}

- (void) setProgressPercent:(float)percent {
    [self
        performSelectorOnMainThread:@selector(_setProgressPercent:)
        withObject:[NSNumber numberWithFloat:percent]
        waitUntilDone:YES
    ];
}

- (void) addProgressOutput:(NSString *)output {
    [self
        performSelectorOnMainThread:@selector(_addProgressOutput:)
        withObject:output
        waitUntilDone:YES
    ];
}

- (void) _setProgressTitle:(NSString *)title {
    [refreshbar_ setPrompt:title];
}

- (void) _setProgressPercent:(NSNumber *)percent {
    [refreshbar_ setProgress:[percent floatValue]];
}

- (void) _addProgressOutput:(NSString *)output {
}

- (void) setUpdateDelegate:(id)delegate {
    updatedelegate_ = delegate;
}

- (CGFloat) statusBarHeight {
    if (UIInterfaceOrientationIsPortrait([self interfaceOrientation])) {
        return [[UIApplication sharedApplication] statusBarFrame].size.height;
    } else {
        return [[UIApplication sharedApplication] statusBarFrame].size.width;
    }
}

- (void) dropBar:(BOOL)animated {
    if (dropped_)
        return;
    dropped_ = true;

    [[self view] addSubview:refreshbar_];

    CGFloat sboffset = [self statusBarHeight];

    CGRect barframe = [refreshbar_ frame];
    barframe.origin.y = sboffset;
    [refreshbar_ setFrame:barframe];

    if (animated)
        [UIView beginAnimations:nil context:NULL];
    CGRect viewframe = [[root_ view] frame];
    viewframe.origin.y += barframe.size.height + sboffset;
    viewframe.size.height -= barframe.size.height + sboffset;
    [[root_ view] setFrame:viewframe];
    if (animated)
        [UIView commitAnimations];

    // Ensure bar has the proper width for our view, it might have changed
    barframe.size.width = viewframe.size.width;
    [refreshbar_ setFrame:barframe];

    // XXX: fix Apple's layout bug
    [[root_ selectedViewController] _updateLayoutForStatusBarAndInterfaceOrientation];
}

- (void) raiseBar:(BOOL)animated {
    if (!dropped_)
        return;
    dropped_ = false;

    [refreshbar_ removeFromSuperview];

    CGFloat sboffset = [self statusBarHeight];

    if (animated)
        [UIView beginAnimations:nil context:NULL];
    CGRect barframe = [refreshbar_ frame];
    CGRect viewframe = [[root_ view] frame];
    viewframe.origin.y -= barframe.size.height + sboffset;
    viewframe.size.height += barframe.size.height + sboffset;
    [[root_ view] setFrame:viewframe];
    if (animated)
        [UIView commitAnimations];

    // XXX: fix Apple's layout bug
    [[root_ selectedViewController] _updateLayoutForStatusBarAndInterfaceOrientation];
}

- (void) willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation duration:(NSTimeInterval)duration {
    // XXX: fix Apple's layout bug
    [[root_ selectedViewController] _updateLayoutForStatusBarAndInterfaceOrientation];
}

- (void) didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    if (dropped_) {
        [self raiseBar:NO];
        [self dropBar:NO];
    }

    // XXX: fix Apple's layout bug
    [[root_ selectedViewController] _updateLayoutForStatusBarAndInterfaceOrientation];
}

- (void) statusBarFrameChanged:(NSNotification *)notification {
    if (dropped_) {
        [self raiseBar:NO];
        [self dropBar:NO];
    }
}

- (void) dealloc {
    [refreshbar_ release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (id) initWithDatabase:(Database *)database {
    if ((self = [super init]) != nil) {
        database_ = database;

        [[self view] setAutoresizingMask:UIViewAutoresizingFlexibleBoth];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusBarFrameChanged:) name:UIApplicationDidChangeStatusBarFrameNotification object:nil];

        refreshbar_ = [[RefreshBar alloc] initWithFrame:CGRectMake(0, 0, [[self view] frame].size.width, [UINavigationBar defaultSize].height) delegate:self];
    } return self;
}

@end
/* }}} */

typedef enum {
    kCydiaTag = 0,
    kSectionsTag = 1,
    kChangesTag = 2,
    kManageTag = 3,
    kInstalledTag = 4,
    kSourcesTag = 5,
    kSearchTag = 6
} CYTabTag;

@interface Cydia : UIApplication <
    ConfirmationControllerDelegate,
    ProgressControllerDelegate,
    CydiaDelegate,
    UINavigationControllerDelegate,
    UITabBarControllerDelegate
> {
    // XXX: evaluate all fields for _transient

    UIWindow *window_;
    CYContainer *container_;
    CYTabBarController *tabbar_;

    NSMutableArray *essential_;
    NSMutableArray *broken_;

    Database *database_;

    int tag_;

    UIKeyboard *keyboard_;
    int huds_;

    SectionsController *sections_;
    ChangesController *changes_;
    ManageController *manage_;
    SearchController *search_;
    SourceTable *sources_;
    InstalledController *installed_;
    id queueDelegate_;

    CYStashController *stash_;

    bool loaded_;
}

- (CYViewController *) _pageForURL:(NSURL *)url withClass:(Class)_class;
- (void) setPage:(CYViewController *)page;
- (void) loadData;

@end

static _finline void _setHomePage(Cydia *self) {
    [self setPage:[self _pageForURL:[NSURL URLWithString:CydiaURL(@"")] withClass:[HomeController class]]];
}

@implementation Cydia

- (void) beginUpdate {
    [container_ beginUpdate];
}

- (BOOL) updating {
    return [container_ updating];
}

- (UIView *) rotatingContentViewForWindow:(UIWindow *)window {
    return window_;
}

- (void) _loaded {
    if ([broken_ count] != 0) {
        int count = [broken_ count];

        UIAlertView *alert = [[[UIAlertView alloc]
            initWithTitle:(count == 1 ? UCLocalize("HALFINSTALLED_PACKAGE") : [NSString stringWithFormat:UCLocalize("HALFINSTALLED_PACKAGES"), count])
            message:UCLocalize("HALFINSTALLED_PACKAGE_EX")
            delegate:self
            cancelButtonTitle:UCLocalize("FORCIBLY_CLEAR")
            otherButtonTitles:UCLocalize("TEMPORARY_IGNORE"), nil
        ] autorelease];

        [alert setContext:@"fixhalf"];
        [alert show];
    } else if (!Ignored_ && [essential_ count] != 0) {
        int count = [essential_ count];

        UIAlertView *alert = [[[UIAlertView alloc]
            initWithTitle:(count == 1 ? UCLocalize("ESSENTIAL_UPGRADE") : [NSString stringWithFormat:UCLocalize("ESSENTIAL_UPGRADES"), count])
            message:UCLocalize("ESSENTIAL_UPGRADE_EX")
            delegate:self
            cancelButtonTitle:UCLocalize("TEMPORARY_IGNORE")
            otherButtonTitles:UCLocalize("UPGRADE_ESSENTIAL"), UCLocalize("COMPLETE_UPGRADE"), nil
        ] autorelease];

        [alert setContext:@"upgrade"];
        [alert show];
    }
}

- (void) _saveConfig {
    if (Changed_) {
        _trace();
        NSString *error(nil);
        if (NSData *data = [NSPropertyListSerialization dataFromPropertyList:Metadata_ format:NSPropertyListBinaryFormat_v1_0 errorDescription:&error]) {
            _trace();
            NSError *error(nil);
            if (![data writeToFile:@"/var/lib/cydia/metadata.plist" options:NSAtomicWrite error:&error])
                NSLog(@"failure to save metadata data: %@", error);
            _trace();
        } else {
            NSLog(@"failure to serialize metadata: %@", error);
            return;
        }

        Changed_ = false;
    }
}

- (void) _updateData {
    [self _saveConfig];

    /* XXX: this is just stupid */
    if (tag_ != 1 && sections_ != nil)
        [sections_ reloadData];
    if (tag_ != 2 && changes_ != nil)
        [changes_ reloadData];
    if (tag_ != 4 && search_ != nil)
        [search_ reloadData];

    [(CYNavigationController *)[tabbar_ selectedViewController] reloadData];
}

- (int)indexOfTabWithTag:(int)tag {
    int i = 0;
    for (UINavigationController *controller in [tabbar_ viewControllers]) {
        if ([[controller tabBarItem] tag] == tag)
            return i;
        i += 1;
    }

    return -1;
}

- (void) _refreshIfPossible {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    bool recently = false;
    NSDate *update([Metadata_ objectForKey:@"LastUpdate"]);
    if (update != nil) {
        NSTimeInterval interval([update timeIntervalSinceNow]);
        if (interval <= 0 && interval > -(15*60))
            recently = true;
    }

    // Don't automatic refresh if:
    //  - We already refreshed recently.
    //  - We already auto-refreshed this launch.
    //  - Auto-refresh is disabled.
    if (recently || loaded_ || ManualRefresh) {
        [self performSelectorOnMainThread:@selector(_loaded) withObject:nil waitUntilDone:NO];

        // If we are cancelling due to ManualRefresh or a recent refresh
        // we need to make sure it knows it's already loaded.
        loaded_ = true;
        return;
    } else {
        // We are going to load, so remember that.
        loaded_ = true;
    }

    SCNetworkReachabilityFlags flags; {
        SCNetworkReachabilityRef reachability(SCNetworkReachabilityCreateWithName(NULL, "cydia.saurik.com"));
        SCNetworkReachabilityGetFlags(reachability, &flags);
        CFRelease(reachability);
    }

    // XXX: this elaborate mess is what Apple is using to determine this? :(
    // XXX: do we care if the user has to intervene? maybe that's ok?
    bool reachable(
        (flags & kSCNetworkReachabilityFlagsReachable) != 0 && (
            (flags & kSCNetworkReachabilityFlagsConnectionRequired) == 0 || (
                (flags & kSCNetworkReachabilityFlagsConnectionOnDemand) != 0 ||
                (flags & kSCNetworkReachabilityFlagsConnectionOnTraffic) != 0
            ) && (flags & kSCNetworkReachabilityFlagsInterventionRequired) == 0 ||
            (flags & kSCNetworkReachabilityFlagsIsWWAN) != 0
        )
    );

    // If we can reach the server, auto-refresh!
    if (reachable)
        [container_ performSelectorOnMainThread:@selector(setUpdate:) withObject:update waitUntilDone:NO];

    [pool release];
}

- (void) refreshIfPossible {
    [NSThread detachNewThreadSelector:@selector(_refreshIfPossible) toTarget:self withObject:nil];
}

- (void) _reloadData {
    UIProgressHUD *hud(loaded_ ? [self addProgressHUD] : nil);
    [hud setText:UCLocalize("RELOADING_DATA")];

    [database_ yieldToSelector:@selector(reloadData) withObject:nil];

    if (hud != nil)
        [self removeProgressHUD:hud];

    size_t changes(0);

    [essential_ removeAllObjects];
    [broken_ removeAllObjects];

    NSArray *packages([database_ packages]);
    for (Package *package in packages) {
        if ([package half])
            [broken_ addObject:package];
        if ([package upgradableAndEssential:NO]) {
            if ([package essential])
                [essential_ addObject:package];
            ++changes;
        }
    }

    UITabBarItem *changesItem = [[[tabbar_ viewControllers] objectAtIndex:[self indexOfTabWithTag:kChangesTag]] tabBarItem];
    if (changes != 0) {
        NSString *badge([[NSNumber numberWithInt:changes] stringValue]);
        [changesItem setBadgeValue:badge];
        [changesItem setAnimatedBadge:([essential_ count] > 0)];

        if ([self respondsToSelector:@selector(setApplicationBadge:)])
            [self setApplicationBadge:badge];
        else
            [self setApplicationBadgeString:badge];
    } else {
        [changesItem setBadgeValue:nil];
        [changesItem setAnimatedBadge:NO];

        if ([self respondsToSelector:@selector(removeApplicationBadge)])
            [self removeApplicationBadge];
        else // XXX: maybe use setApplicationBadgeString also?
            [self setApplicationIconBadgeNumber:0];
    }

    [self _updateData];

    [self refreshIfPossible];
}

- (void) updateData {
    [self _updateData];
}

- (void) update_ {
    [database_ update];
}

- (void) syncData {
    FILE *file(fopen("/etc/apt/sources.list.d/cydia.list", "w"));
    _assert(file != NULL);

    for (NSString *key in [Sources_ allKeys]) {
        NSDictionary *source([Sources_ objectForKey:key]);

        fprintf(file, "%s %s %s\n",
            [[source objectForKey:@"Type"] UTF8String],
            [[source objectForKey:@"URI"] UTF8String],
            [[source objectForKey:@"Distribution"] UTF8String]
        );
    }

    fclose(file);

    [self _saveConfig];

    ProgressController *progress = [[[ProgressController alloc] initWithDatabase:database_ delegate:self] autorelease];
    CYNavigationController *navigation = [[[CYNavigationController alloc] initWithRootViewController:progress] autorelease];
    if (IsWildcat_)
        [navigation setModalPresentationStyle:UIModalPresentationFormSheet];
    [container_ presentModalViewController:navigation animated:YES];

    [progress
        detachNewThreadSelector:@selector(update_)
        toTarget:self
        withObject:nil
        title:UCLocalize("UPDATING_SOURCES")
    ];
}

- (void) reloadData {
    @synchronized (self) {
        [self _reloadData];
    }
}

- (void) resolve {
    pkgProblemResolver *resolver = [database_ resolver];

    resolver->InstallProtect();
    if (!resolver->Resolve(true))
        _error->Discard();
}

- (CGRect) popUpBounds {
    return [[tabbar_ view] bounds];
}

- (bool) perform {
    if (![database_ prepare])
        return false;

    ConfirmationController *page([[[ConfirmationController alloc] initWithDatabase:database_] autorelease]);
    [page setDelegate:self];
    CYNavigationController *confirm_([[[CYNavigationController alloc] initWithRootViewController:page] autorelease]);
    [confirm_ setDelegate:self];

    if (IsWildcat_)
        [confirm_ setModalPresentationStyle:UIModalPresentationFormSheet];
    [container_ presentModalViewController:confirm_ animated:YES];

    return true;
}

- (void) queue {
    @synchronized (self) {
        [self perform];
    }
}

- (void) clearPackage:(Package *)package {
    @synchronized (self) {
        [package clear];
        [self resolve];
        [self perform];
    }
}

- (void) installPackages:(NSArray *)packages {
    @synchronized (self) {
        for (Package *package in packages)
            [package install];
        [self resolve];
        [self perform];
    }
}

- (void) installPackage:(Package *)package {
    @synchronized (self) {
        [package install];
        [self resolve];
        [self perform];
    }
}

- (void) removePackage:(Package *)package {
    @synchronized (self) {
        [package remove];
        [self resolve];
        [self perform];
    }
}

- (void) distUpgrade {
    @synchronized (self) {
        if (![database_ upgrade])
            return;
        [self perform];
    }
}

- (void) complete {
    @synchronized (self) {
        [self _reloadData];
    }
}

- (void) confirmWithNavigationController:(UINavigationController *)navigation {
    ProgressController *progress = [[[ProgressController alloc] initWithDatabase:database_ delegate:self] autorelease];

    if (navigation != nil) {
        [navigation pushViewController:progress animated:YES];
    } else {
        navigation = [[[CYNavigationController alloc] initWithRootViewController:progress] autorelease];
        if (IsWildcat_)
            [navigation setModalPresentationStyle:UIModalPresentationFormSheet];
        [container_ presentModalViewController:navigation animated:YES];
    }

    [progress
        detachNewThreadSelector:@selector(perform)
        toTarget:database_
        withObject:nil
        title:UCLocalize("RUNNING")
    ];
}

- (void) progressControllerIsComplete:(ProgressController *)progress {
    [self complete];
}

- (void) setPage:(CYViewController *)page {
    [page setDelegate:self];

    CYNavigationController *navController = (CYNavigationController *) [tabbar_ selectedViewController];
    [navController setViewControllers:[NSArray arrayWithObject:page]];
    for (CYNavigationController *page in [tabbar_ viewControllers])
        if (page != navController)
            [page setViewControllers:nil];
}

- (CYViewController *) _pageForURL:(NSURL *)url withClass:(Class)_class {
    CYBrowserController *browser = [[[_class alloc] init] autorelease];
    [browser loadURL:url];
    return browser;
}

- (SectionsController *) sectionsController {
    if (sections_ == nil)
        sections_ = [[SectionsController alloc] initWithDatabase:database_];
    return sections_;
}

- (ChangesController *) changesController {
    if (changes_ == nil)
        changes_ = [[ChangesController alloc] initWithDatabase:database_ delegate:self];
    return changes_;
}

- (ManageController *) manageController {
    if (manage_ == nil) {
        manage_ = (ManageController *) [[self
            _pageForURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"manage" ofType:@"html"]]
            withClass:[ManageController class]
        ] retain];
        if (!IsWildcat_)
            queueDelegate_ = manage_;
    }
    return manage_;
}

- (SearchController *) searchController {
    if (search_ == nil)
        search_ = [[SearchController alloc] initWithDatabase:database_];
    return search_;
}

- (SourceTable *) sourcesController {
    if (sources_ == nil)
        sources_ = [[SourceTable alloc] initWithDatabase:database_];
    return sources_;
}

- (InstalledController *) installedController {
    if (installed_ == nil) {
        installed_ = [[InstalledController alloc] initWithDatabase:database_];
        if (IsWildcat_)
            queueDelegate_ = installed_;
    }
    return installed_;
}

- (void) tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController {
    int tag = [[viewController tabBarItem] tag];
    if (tag == tag_) {
        [(CYNavigationController *)[tabbar_ selectedViewController] popToRootViewControllerAnimated:YES];
        return;
    } else if (tag_ == 1) {
        [[self sectionsController] resetView];
    }

    switch (tag) {
        case kCydiaTag: _setHomePage(self); break;

        case kSectionsTag: [self setPage:[self sectionsController]]; break;
        case kChangesTag: [self setPage:[self changesController]]; break;
        case kManageTag: [self setPage:[self manageController]]; break;
        case kInstalledTag: [self setPage:[self installedController]]; break;
        case kSourcesTag: [self setPage:[self sourcesController]]; break;
        case kSearchTag: [self setPage:[self searchController]]; break;

        _nodefault
    }

    tag_ = tag;
}

- (void) showSettings {
    RoleController *role = [[[RoleController alloc] initWithDatabase:database_ delegate:self] autorelease];
    CYNavigationController *nav = [[[CYNavigationController alloc] initWithRootViewController:role] autorelease];
    if (IsWildcat_)
        [nav setModalPresentationStyle:UIModalPresentationFormSheet];
    [container_ presentModalViewController:nav animated:YES];
}

- (void) setPackageController:(PackageController *)view {
    WebThreadLock();
    [view setPackage:nil];
    WebThreadUnlock();
}

- (PackageController *) _packageController {
    return [[[PackageController alloc] initWithDatabase:database_] autorelease];
}

- (PackageController *) packageController {
    return [self _packageController];
}

// Returns the navigation controller for the queuing badge.
- (id) queueBadgeController {
    int index = [self indexOfTabWithTag:kManageTag];
    if (index == -1)
        index = [self indexOfTabWithTag:kInstalledTag];

    return [[tabbar_ viewControllers] objectAtIndex:index];
}

- (void) cancelAndClear:(bool)clear {
    @synchronized (self) {
        if (clear) {
            [database_ clear];

            // Stop queuing.
            Queuing_ = false;
            [[[self queueBadgeController] tabBarItem] setBadgeValue:nil];
        } else {
            // Start queuing.
            Queuing_ = true;
            [[[self queueBadgeController] tabBarItem] setBadgeValue:UCLocalize("Q_D")];
        }

        [self _updateData];
        [queueDelegate_ queueStatusDidChange];
    }
}

- (void) alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)button {
    NSString *context([alert context]);

    if ([context isEqualToString:@"fixhalf"]) {
        if (button == [alert firstOtherButtonIndex]) {
            @synchronized (self) {
                for (Package *broken in broken_) {
                    [broken remove];

                    NSString *id = [broken id];
                    unlink([[NSString stringWithFormat:@"/var/lib/dpkg/info/%@.prerm", id] UTF8String]);
                    unlink([[NSString stringWithFormat:@"/var/lib/dpkg/info/%@.postrm", id] UTF8String]);
                    unlink([[NSString stringWithFormat:@"/var/lib/dpkg/info/%@.preinst", id] UTF8String]);
                    unlink([[NSString stringWithFormat:@"/var/lib/dpkg/info/%@.postinst", id] UTF8String]);
                }

                [self resolve];
                [self perform];
            }
        } else if (button == [alert cancelButtonIndex]) {
            [broken_ removeAllObjects];
            [self _loaded];
        }

        [alert dismissWithClickedButtonIndex:-1 animated:YES];
    } else if ([context isEqualToString:@"upgrade"]) {
        if (button == [alert firstOtherButtonIndex]) {
            @synchronized (self) {
                for (Package *essential in essential_)
                    [essential install];

                [self resolve];
                [self perform];
            }
        } else if (button == [alert firstOtherButtonIndex] + 1) {
            [self distUpgrade];
        } else if (button == [alert cancelButtonIndex]) {
            Ignored_ = YES;
        }

        [alert dismissWithClickedButtonIndex:-1 animated:YES];
    }
}

- (void) system:(NSString *)command { _pooled
    system([command UTF8String]);
}

- (void) applicationWillSuspend {
    [database_ clean];
    [super applicationWillSuspend];
}

- (BOOL) hudIsShowing {
    return (huds_ > 0);
}

- (void) applicationSuspend:(__GSEvent *)event {
    // Use external process status API internally.
    // This is probably a really bad idea.
    uint64_t status = 0;
    int notify_token;
    if (notify_register_check("com.saurik.Cydia.status", &notify_token) == NOTIFY_STATUS_OK) {
        notify_get_state(notify_token, &status);
        notify_cancel(notify_token);
    }

    if (![self hudIsShowing] && status == 0)
        [super applicationSuspend:event];
}

- (void) _animateSuspension:(BOOL)arg0 duration:(double)arg1 startTime:(double)arg2 scale:(float)arg3 {
    if (![self hudIsShowing])
        [super _animateSuspension:arg0 duration:arg1 startTime:arg2 scale:arg3];
}

- (void) _setSuspended:(BOOL)value {
    if (![self hudIsShowing])
        [super _setSuspended:value];
}

- (UIProgressHUD *) addProgressHUD {
    UIProgressHUD *hud([[[UIProgressHUD alloc] initWithWindow:window_] autorelease]);
    [hud setAutoresizingMask:UIViewAutoresizingFlexibleBoth];

    [window_ setUserInteractionEnabled:NO];
    [hud show:YES];

    UIViewController *target = container_;
    while ([target modalViewController] != nil) target = [target modalViewController];
    [[target view] addSubview:hud];

    huds_++;
    return hud;
}

- (void) removeProgressHUD:(UIProgressHUD *)hud {
    [hud show:NO];
    [hud removeFromSuperview];
    [window_ setUserInteractionEnabled:YES];
    huds_--;
}

- (CYViewController *) pageForPackage:(NSString *)name {
    if (Package *package = [database_ packageWithName:name]) {
        PackageController *view([self packageController]);
        [view setPackage:package];
        return view;
    } else {
        NSURL *url([NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"unknown" ofType:@"html"]]);
        url = [NSURL URLWithString:[[url absoluteString] stringByAppendingString:[NSString stringWithFormat:@"?%@", name]]];
        return [self _pageForURL:url withClass:[CYBrowserController class]];
    }
}

- (CYViewController *) pageForURL:(NSURL *)url hasTag:(int *)tag {
    if (tag != NULL)
        *tag = -1;

    NSString *href([url absoluteString]);
    if ([href hasPrefix:@"apptapp://package/"])
        return [self pageForPackage:[href substringFromIndex:18]];

    NSString *scheme([[url scheme] lowercaseString]);
    if (![scheme isEqualToString:@"cydia"])
        return nil;
    NSString *path([url absoluteString]);
    if ([path length] < 8)
        return nil;
    path = [path substringFromIndex:8];
    if (![path hasPrefix:@"/"])
        path = [@"/" stringByAppendingString:path];

    if ([path isEqualToString:@"/add-source"])
        return [[[AddSourceController alloc] initWithDatabase:database_] autorelease];
    else if ([path isEqualToString:@"/storage"])
        return [self _pageForURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"storage" ofType:@"html"]] withClass:[CYBrowserController class]];
    else if ([path isEqualToString:@"/sources"])
        return [[[SourceTable alloc] initWithDatabase:database_] autorelease];
    else if ([path isEqualToString:@"/packages"])
        return [[[InstalledController alloc] initWithDatabase:database_] autorelease];
    else if ([path hasPrefix:@"/url/"])
        return [self _pageForURL:[NSURL URLWithString:[path substringFromIndex:5]] withClass:[CYBrowserController class]];
    else if ([path hasPrefix:@"/launch/"])
        [self launchApplicationWithIdentifier:[path substringFromIndex:8] suspended:NO];
    else if ([path hasPrefix:@"/package-settings/"])
        return [[[SettingsController alloc] initWithDatabase:database_ package:[path substringFromIndex:18]] autorelease];
    else if ([path hasPrefix:@"/package-signature/"])
        return [[[SignatureController alloc] initWithDatabase:database_ package:[path substringFromIndex:19]] autorelease];
    else if ([path hasPrefix:@"/package/"])
        return [self pageForPackage:[path substringFromIndex:9]];
    else if ([path hasPrefix:@"/files/"]) {
        NSString *name = [path substringFromIndex:7];

        if (Package *package = [database_ packageWithName:name]) {
            FileTable *files = [[[FileTable alloc] initWithDatabase:database_] autorelease];
            [files setPackage:package];
            return files;
        }
    }

    return nil;
}

- (void) applicationOpenURL:(NSURL *)url {
    [super applicationOpenURL:url];
    int tag;
    if (CYViewController *page = [self pageForURL:url hasTag:&tag]) {
        [self setPage:page];
        tag_ = tag;
        [tabbar_ setSelectedViewController:(tag_ == -1 ? nil : [[tabbar_ viewControllers] objectAtIndex:tag_])];
    }
}

- (void) applicationWillResignActive:(UIApplication *)application {
    // Stop refreshing if you get a phone call or lock the device.
    if ([container_ updating])
        [container_ cancelUpdate];

    if ([[self superclass] instancesRespondToSelector:@selector(applicationWillResignActive:)])
        [super applicationWillResignActive:application];
}

- (void) addStashController {
    stash_ = [[CYStashController alloc] init];
    [window_ addSubview:[stash_ view]];
}

- (void) removeStashController {
    [[stash_ view] removeFromSuperview];
    [stash_ release];
}

- (void) stash {
    [self setIdleTimerDisabled:YES];

    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackOpaque];
    [self setStatusBarShowsProgress:YES];
    UpdateExternalStatus(1);

    [self yieldToSelector:@selector(system:) withObject:@"/usr/libexec/cydia/free.sh"];

    UpdateExternalStatus(0);
    [self setStatusBarShowsProgress:NO];

    [self removeStashController];

    if (ExecFork() == 0) {
        execlp("launchctl", "launchctl", "stop", "com.apple.SpringBoard", NULL);
        perror("launchctl stop");
    }
}

- (void) setupTabBarController {
    tabbar_ = [[CYTabBarController alloc] initWithDatabase:database_];
    [tabbar_ setDelegate:self];

    NSMutableArray *items([NSMutableArray arrayWithObjects:
        [[[UITabBarItem alloc] initWithTitle:@"Cydia" image:[UIImage applicationImageNamed:@"home.png"] tag:kCydiaTag] autorelease],
        [[[UITabBarItem alloc] initWithTitle:UCLocalize("SECTIONS") image:[UIImage applicationImageNamed:@"install.png"] tag:kSectionsTag] autorelease],
        [[[UITabBarItem alloc] initWithTitle:UCLocalize("CHANGES") image:[UIImage applicationImageNamed:@"changes.png"] tag:kChangesTag] autorelease],
        [[[UITabBarItem alloc] initWithTitle:UCLocalize("SEARCH") image:[UIImage applicationImageNamed:@"search.png"] tag:kSearchTag] autorelease],
    nil]);

    if (IsWildcat_) {
        [items insertObject:[[[UITabBarItem alloc] initWithTitle:UCLocalize("SOURCES") image:[UIImage applicationImageNamed:@"source.png"] tag:kSourcesTag] autorelease] atIndex:3];
        [items insertObject:[[[UITabBarItem alloc] initWithTitle:UCLocalize("INSTALLED") image:[UIImage applicationImageNamed:@"manage.png"] tag:kInstalledTag] autorelease] atIndex:3];
    } else {
        [items insertObject:[[[UITabBarItem alloc] initWithTitle:UCLocalize("MANAGE") image:[UIImage applicationImageNamed:@"manage.png"] tag:kManageTag] autorelease] atIndex:3];
    }

    NSMutableArray *controllers([NSMutableArray array]);

    for (UITabBarItem *item in items) {
        CYNavigationController *controller([[[CYNavigationController alloc] initWithDatabase:database_] autorelease]);
        [controller setTabBarItem:item];
        [controllers addObject:controller];
    }

    [tabbar_ setViewControllers:controllers];
}

- (void) applicationDidFinishLaunching:(id)unused {
    [CYBrowserController _initialize];

    [NSURLProtocol registerClass:[CydiaURLProtocol class]];

    Font12_ = [[UIFont systemFontOfSize:12] retain];
    Font12Bold_ = [[UIFont boldSystemFontOfSize:12] retain];
    Font14_ = [[UIFont systemFontOfSize:14] retain];
    Font18Bold_ = [[UIFont boldSystemFontOfSize:18] retain];
    Font22Bold_ = [[UIFont boldSystemFontOfSize:22] retain];

    tag_ = 0;

    essential_ = [[NSMutableArray alloc] initWithCapacity:4];
    broken_ = [[NSMutableArray alloc] initWithCapacity:4];

    UIScreen *screen([UIScreen mainScreen]);

    window_ = [[UIWindow alloc] initWithFrame:[screen bounds]];
    [window_ orderFront:self];
    [window_ makeKey:self];
    [window_ setHidden:NO];

    if (
        readlink("/Applications", NULL, 0) == -1 && errno == EINVAL ||
        readlink("/Library/Ringtones", NULL, 0) == -1 && errno == EINVAL ||
        readlink("/Library/Wallpaper", NULL, 0) == -1 && errno == EINVAL ||
        //readlink("/usr/bin", NULL, 0) == -1 && errno == EINVAL ||
        readlink("/usr/include", NULL, 0) == -1 && errno == EINVAL ||
        readlink("/usr/lib/pam", NULL, 0) == -1 && errno == EINVAL ||
        readlink("/usr/libexec", NULL, 0) == -1 && errno == EINVAL ||
        readlink("/usr/share", NULL, 0) == -1 && errno == EINVAL ||
        //readlink("/var/lib", NULL, 0) == -1 && errno == EINVAL ||
        false
    ) {
        [self addStashController];
        // XXX: this would be much cleaner as a yieldToSelector:
        // that way the removeStashController could happen right here inline
        // we also could no longer require the useless stash_ field anymore
        [self performSelector:@selector(stash) withObject:nil afterDelay:0];
        return;
    }

    database_ = [Database sharedInstance];

    [self setupTabBarController];

    container_ = [[CYContainer alloc] initWithDatabase:database_];
    [container_ setUpdateDelegate:self];
    [container_ setTabBarController:tabbar_];
    [window_ addSubview:[container_ view]];

    // Show pinstripes while loading data.
    [[container_ view] setBackgroundColor:[UIColor pinStripeColor]];

    [self performSelector:@selector(loadData) withObject:nil afterDelay:0];
_trace();
}

- (void) loadData {
_trace();
    if (Role_ == nil) {
        [self showSettings];
        return;
    }

    [window_ setUserInteractionEnabled:NO];

    UIView *container = [[[UIView alloc] init] autorelease];
    [container setAutoresizingMask:UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin];

    UIActivityIndicatorView *spinner = [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray] autorelease];
    [spinner startAnimating];
    [container addSubview:spinner];

    UILabel *label = [[[UILabel alloc] init] autorelease];
    [label setFont:[UIFont boldSystemFontOfSize:15.0f]];
    [label setBackgroundColor:[UIColor clearColor]];
    [label setTextColor:[UIColor blackColor]];
    [label setShadowColor:[UIColor whiteColor]];
    [label setShadowOffset:CGSizeMake(0, 1)];
    [label setText:[NSString stringWithFormat:Elision_, UCLocalize("LOADING"), nil]];
    [container addSubview:label];

    CGSize viewsize = [[tabbar_ view] frame].size;
    CGSize spinnersize = [spinner bounds].size;
    CGSize textsize = [[label text] sizeWithFont:[label font]];
    float bothwidth = spinnersize.width + textsize.width + 5.0f;

    CGRect containrect = {
        CGPointMake(floorf((viewsize.width / 2) - (bothwidth / 2)), floorf((viewsize.height / 2) - (spinnersize.height / 2))),
        CGSizeMake(bothwidth, spinnersize.height)
    };
    CGRect textrect = {
        CGPointMake(spinnersize.width + 5.0f, floorf((spinnersize.height / 2) - (textsize.height / 2))),
        textsize
    };
    CGRect spinrect = {
        CGPointZero,
        spinnersize
    };

    [container setFrame:containrect];
    [spinner setFrame:spinrect];
    [label setFrame:textrect];
    [[container_ view] addSubview:container];

    [self reloadData];
    PrintTimes();

    // Show the home page
    [tabbar_ setSelectedIndex:0];
    _setHomePage(self);
    [window_ setUserInteractionEnabled:YES];

    // XXX: does this actually slow anything down?
    [[container_ view] setBackgroundColor:[UIColor clearColor]];
    [container removeFromSuperview];
}

- (void) showActionSheet:(UIActionSheet *)sheet fromItem:(UIBarButtonItem *)item {
    if (item != nil && IsWildcat_) {
        [sheet showFromBarButtonItem:item animated:YES];
    } else {
        [sheet showInView:window_];
    }
}

@end

/*IMP alloc_;
id Alloc_(id self, SEL selector) {
    id object = alloc_(self, selector);
    lprintf("[%s]A-%p\n", self->isa->name, object);
    return object;
}*/

/*IMP dealloc_;
id Dealloc_(id self, SEL selector) {
    id object = dealloc_(self, selector);
    lprintf("[%s]D-%p\n", self->isa->name, object);
    return object;
}*/

Class $WebDefaultUIKitDelegate;

MSHook(void, UIWebDocumentView$_setUIKitDelegate$, UIWebDocumentView *self, SEL _cmd, id delegate) {
    if (delegate == nil && $WebDefaultUIKitDelegate != nil)
        delegate = [$WebDefaultUIKitDelegate sharedUIKitDelegate];
    return _UIWebDocumentView$_setUIKitDelegate$(self, _cmd, delegate);
}

static NSNumber *shouldPlayKeyboardSounds;

Class $UIHardware;

MSHook(void, UIHardware$_playSystemSound$, Class self, SEL _cmd, int sound) {
    switch (sound) {
        case 1104: // Keyboard Button Clicked
        case 1105: // Keyboard Delete Repeated
            if (shouldPlayKeyboardSounds == nil) {
                NSDictionary *dict([[[NSDictionary alloc] initWithContentsOfFile:@"/var/mobile/Library/Preferences/com.apple.preferences.sounds.plist"] autorelease]);
                shouldPlayKeyboardSounds = [([dict objectForKey:@"keyboard"] ?: (id) kCFBooleanTrue) retain];
            }

            if (![shouldPlayKeyboardSounds boolValue])
                break;

        default:
            _UIHardware$_playSystemSound$(self, _cmd, sound);
    }
}

int main(int argc, char *argv[]) { _pooled
    _trace();

    if (Class $UIDevice = objc_getClass("UIDevice")) {
        UIDevice *device([$UIDevice currentDevice]);
        IsWildcat_ = [device respondsToSelector:@selector(isWildcat)] && [device isWildcat];
    } else
        IsWildcat_ = false;

    PackageName = reinterpret_cast<CYString &(*)(Package *, SEL)>(method_getImplementation(class_getInstanceMethod([Package class], @selector(cyname))));

    /* Library Hacks {{{ */
    class_addMethod(objc_getClass("DOMNodeList"), @selector(countByEnumeratingWithState:objects:count:), (IMP) &DOMNodeList$countByEnumeratingWithState$objects$count$, "I20@0:4^{NSFastEnumerationState}8^@12I16");

    $WebDefaultUIKitDelegate = objc_getClass("WebDefaultUIKitDelegate");
    Method UIWebDocumentView$_setUIKitDelegate$(class_getInstanceMethod([WebView class], @selector(_setUIKitDelegate:)));
    if (UIWebDocumentView$_setUIKitDelegate$ != NULL) {
        _UIWebDocumentView$_setUIKitDelegate$ = reinterpret_cast<void (*)(UIWebDocumentView *, SEL, id)>(method_getImplementation(UIWebDocumentView$_setUIKitDelegate$));
        method_setImplementation(UIWebDocumentView$_setUIKitDelegate$, reinterpret_cast<IMP>(&$UIWebDocumentView$_setUIKitDelegate$));
    }

    $UIHardware = objc_getClass("UIHardware");
    Method UIHardware$_playSystemSound$(class_getClassMethod($UIHardware, @selector(_playSystemSound:)));
    if (UIHardware$_playSystemSound$ != NULL) {
        _UIHardware$_playSystemSound$ = reinterpret_cast<void (*)(Class, SEL, int)>(method_getImplementation(UIHardware$_playSystemSound$));
        method_setImplementation(UIHardware$_playSystemSound$, reinterpret_cast<IMP>(&$UIHardware$_playSystemSound$));
    }
    /* }}} */
    /* Set Locale {{{ */
    Locale_ = CFLocaleCopyCurrent();
    Languages_ = [NSLocale preferredLanguages];
    //CFStringRef locale(CFLocaleGetIdentifier(Locale_));
    //NSLog(@"%@", [Languages_ description]);

    const char *lang;
    if (Languages_ == nil || [Languages_ count] == 0)
        // XXX: consider just setting to C and then falling through?
        lang = NULL;
    else {
        lang = [[Languages_ objectAtIndex:0] UTF8String];
        setenv("LANG", lang, true);
    }

    //std::setlocale(LC_ALL, lang);
    NSLog(@"Setting Language: %s", lang);
    /* }}} */

    apr_app_initialize(&argc, const_cast<const char * const **>(&argv), NULL);

    /* Parse Arguments {{{ */
    bool substrate(false);

    if (argc != 0) {
        char **args(argv);
        int arge(1);

        for (int argi(1); argi != argc; ++argi)
            if (strcmp(argv[argi], "--") == 0) {
                arge = argi;
                argv[argi] = argv[0];
                argv += argi;
                argc -= argi;
                break;
            }

        for (int argi(1); argi != arge; ++argi)
            if (strcmp(args[argi], "--substrate") == 0)
                substrate = true;
            else
                fprintf(stderr, "unknown argument: %s\n", args[argi]);
    }
    /* }}} */

    App_ = [[NSBundle mainBundle] bundlePath];
    Home_ = NSHomeDirectory();
    Advanced_ = YES;

    setuid(0);
    setgid(0);

    /*Method alloc = class_getClassMethod([NSObject class], @selector(alloc));
    alloc_ = alloc->method_imp;
    alloc->method_imp = (IMP) &Alloc_;*/

    /*Method dealloc = class_getClassMethod([NSObject class], @selector(dealloc));
    dealloc_ = dealloc->method_imp;
    dealloc->method_imp = (IMP) &Dealloc_;*/

    /* System Information {{{ */
    size_t size;

    int maxproc;
    size = sizeof(maxproc);
    if (sysctlbyname("kern.maxproc", &maxproc, &size, NULL, 0) == -1)
        perror("sysctlbyname(\"kern.maxproc\", ?)");
    else if (maxproc < 64) {
        maxproc = 64;
        if (sysctlbyname("kern.maxproc", NULL, NULL, &maxproc, sizeof(maxproc)) == -1)
            perror("sysctlbyname(\"kern.maxproc\", #)");
    }

    sysctlbyname("kern.osversion", NULL, &size, NULL, 0);
    char *osversion = new char[size];
    if (sysctlbyname("kern.osversion", osversion, &size, NULL, 0) == -1)
        perror("sysctlbyname(\"kern.osversion\", ?)");
    else
        System_ = [NSString stringWithUTF8String:osversion];

    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char *machine = new char[size];
    if (sysctlbyname("hw.machine", machine, &size, NULL, 0) == -1)
        perror("sysctlbyname(\"hw.machine\", ?)");
    else
        Machine_ = machine;

    if (CFMutableDictionaryRef dict = IOServiceMatching("IOPlatformExpertDevice")) {
        if (io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault, dict)) {
            if (CFTypeRef serial = IORegistryEntryCreateCFProperty(service, CFSTR(kIOPlatformSerialNumberKey), kCFAllocatorDefault, 0)) {
                SerialNumber_ = [NSString stringWithString:(NSString *)serial];
                CFRelease(serial);
            }

            if (CFTypeRef ecid = IORegistryEntrySearchCFProperty(service, kIODeviceTreePlane, CFSTR("unique-chip-id"), kCFAllocatorDefault, kIORegistryIterateRecursively)) {
                NSData *data((NSData *) ecid);
                size_t length([data length]);
                uint8_t bytes[length];
                [data getBytes:bytes];
                char string[length * 2 + 1];
                for (size_t i(0); i != length; ++i)
                    sprintf(string + i * 2, "%.2X", bytes[length - i - 1]);
                ChipID_ = [NSString stringWithUTF8String:string];
                CFRelease(ecid);
            }

            IOObjectRelease(service);
        }
    }

    UniqueID_ = [[UIDevice currentDevice] uniqueIdentifier];

    CFStringRef (*$CTSIMSupportCopyMobileSubscriberCountryCode)(CFAllocatorRef);
    $CTSIMSupportCopyMobileSubscriberCountryCode = reinterpret_cast<CFStringRef (*)(CFAllocatorRef)>(dlsym(RTLD_DEFAULT, "CTSIMSupportCopyMobileSubscriberCountryCode"));
    CFStringRef mcc($CTSIMSupportCopyMobileSubscriberCountryCode == NULL ? NULL : (*$CTSIMSupportCopyMobileSubscriberCountryCode)(kCFAllocatorDefault));

    CFStringRef (*$CTSIMSupportCopyMobileSubscriberNetworkCode)(CFAllocatorRef);
    $CTSIMSupportCopyMobileSubscriberNetworkCode = reinterpret_cast<CFStringRef (*)(CFAllocatorRef)>(dlsym(RTLD_DEFAULT, "CTSIMSupportCopyMobileSubscriberCountryCode"));
    CFStringRef mnc($CTSIMSupportCopyMobileSubscriberNetworkCode == NULL ? NULL : (*$CTSIMSupportCopyMobileSubscriberNetworkCode)(kCFAllocatorDefault));

    if (mcc != NULL && mnc != NULL)
        PLMN_ = [NSString stringWithFormat:@"%@%@", mcc, mnc];

    if (mnc != NULL)
        CFRelease(mnc);
    if (mcc != NULL)
        CFRelease(mcc);

    if (NSDictionary *system = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"])
        Build_ = [system objectForKey:@"ProductBuildVersion"];
    if (NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:@"/Applications/MobileSafari.app/Info.plist"]) {
        Product_ = [info objectForKey:@"SafariProductVersion"];
        Safari_ = [info objectForKey:@"CFBundleVersion"];
    }
    /* }}} */
    /* Load Database {{{ */
    _trace();
    Metadata_ = [[[NSMutableDictionary alloc] initWithContentsOfFile:@"/var/lib/cydia/metadata.plist"] autorelease];
    _trace();
    SectionMap_ = [[[NSDictionary alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Sections" ofType:@"plist"]] autorelease];

    if (Metadata_ == NULL)
        Metadata_ = [NSMutableDictionary dictionaryWithCapacity:2];
    else {
        Settings_ = [Metadata_ objectForKey:@"Settings"];

        Packages_ = [Metadata_ objectForKey:@"Packages"];
        Sections_ = [Metadata_ objectForKey:@"Sections"];
        Sources_ = [Metadata_ objectForKey:@"Sources"];

        Token_ = [Metadata_ objectForKey:@"Token"];
    }

    if (Settings_ != nil)
        Role_ = [Settings_ objectForKey:@"Role"];

    if (Packages_ == nil) {
        Packages_ = [[[NSMutableDictionary alloc] initWithCapacity:128] autorelease];
        [Metadata_ setObject:Packages_ forKey:@"Packages"];
    }

    if (Sections_ == nil) {
        Sections_ = [[[NSMutableDictionary alloc] initWithCapacity:32] autorelease];
        [Metadata_ setObject:Sections_ forKey:@"Sections"];
    }

    if (Sources_ == nil) {
        Sources_ = [[[NSMutableDictionary alloc] initWithCapacity:0] autorelease];
        [Metadata_ setObject:Sources_ forKey:@"Sources"];
    }
    /* }}} */

    Finishes_ = [NSArray arrayWithObjects:@"return", @"reopen", @"restart", @"reload", @"reboot", nil];

    if (substrate && access("/Library/MobileSubstrate/DynamicLibraries/SimulatedKeyEvents.dylib", F_OK) == 0)
        dlopen("/Library/MobileSubstrate/DynamicLibraries/SimulatedKeyEvents.dylib", RTLD_LAZY | RTLD_GLOBAL);
    if (substrate && access("/Applications/WinterBoard.app/WinterBoard.dylib", F_OK) == 0)
        dlopen("/Applications/WinterBoard.app/WinterBoard.dylib", RTLD_LAZY | RTLD_GLOBAL);
    /*if (substrate && access("/Library/MobileSubstrate/MobileSubstrate.dylib", F_OK) == 0)
        dlopen("/Library/MobileSubstrate/MobileSubstrate.dylib", RTLD_LAZY | RTLD_GLOBAL);*/

    int version([[NSString stringWithContentsOfFile:@"/var/lib/cydia/firmware.ver"] intValue]);

    if (access("/tmp/.cydia.fw", F_OK) == 0) {
        unlink("/tmp/.cydia.fw");
        goto firmware;
    } else if (access("/User", F_OK) != 0 || version < 2) {
      firmware:
        _trace();
        system("/usr/libexec/cydia/firmware.sh");
        _trace();
    }

    _assert([[NSFileManager defaultManager]
        createDirectoryAtPath:@"/var/cache/apt/archives/partial"
        withIntermediateDirectories:YES
        attributes:nil
        error:NULL
    ]);

    if (access("/tmp/cydia.chk", F_OK) == 0) {
        if (unlink("/var/cache/apt/pkgcache.bin") == -1)
            _assert(errno == ENOENT);
        if (unlink("/var/cache/apt/srcpkgcache.bin") == -1)
            _assert(errno == ENOENT);
    }

    /* APT Initialization {{{ */
    _assert(pkgInitConfig(*_config));
    _assert(pkgInitSystem(*_config, _system));

    if (lang != NULL)
        _config->Set("APT::Acquire::Translation", lang);

    // XXX: this timeout might be important :(
    //_config->Set("Acquire::http::Timeout", 15);

    _config->Set("Acquire::http::MaxParallel", 3);
    /* }}} */
    /* Color Choices {{{ */
    space_ = CGColorSpaceCreateDeviceRGB();

    Blue_.Set(space_, 0.2, 0.2, 1.0, 1.0);
    Blueish_.Set(space_, 0x19/255.f, 0x32/255.f, 0x50/255.f, 1.0);
    Black_.Set(space_, 0.0, 0.0, 0.0, 1.0);
    Off_.Set(space_, 0.9, 0.9, 0.9, 1.0);
    White_.Set(space_, 1.0, 1.0, 1.0, 1.0);
    Gray_.Set(space_, 0.4, 0.4, 0.4, 1.0);
    Green_.Set(space_, 0.0, 0.5, 0.0, 1.0);
    Purple_.Set(space_, 0.0, 0.0, 0.7, 1.0);
    Purplish_.Set(space_, 0.4, 0.4, 0.8, 1.0);

    InstallingColor_ = [UIColor colorWithRed:0.88f green:1.00f blue:0.88f alpha:1.00f];
    RemovingColor_ = [UIColor colorWithRed:1.00f green:0.88f blue:0.88f alpha:1.00f];
    /* }}}*/
    /* UIKit Configuration {{{ */
    void (*$GSFontSetUseLegacyFontMetrics)(BOOL)(reinterpret_cast<void (*)(BOOL)>(dlsym(RTLD_DEFAULT, "GSFontSetUseLegacyFontMetrics")));
    if ($GSFontSetUseLegacyFontMetrics != NULL)
        $GSFontSetUseLegacyFontMetrics(YES);

    // XXX: I have a feeling this was important
    //UIKeyboardDisableAutomaticAppearance();
    /* }}} */

    Colon_ = UCLocalize("COLON_DELIMITED");
    Elision_ = UCLocalize("ELISION");
    Error_ = UCLocalize("ERROR");
    Warning_ = UCLocalize("WARNING");

    _trace();
    int value(UIApplicationMain(argc, argv, @"Cydia", @"Cydia"));

    CGColorSpaceRelease(space_);
    CFRelease(Locale_);

    return value;
}
