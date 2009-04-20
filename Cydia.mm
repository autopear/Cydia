/* Cydia - iPhone UIKit Front-End for Debian APT
 * Copyright (C) 2008  Jay Freeman (saurik)
*/

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

// XXX: wtf/FastMalloc.h... wtf?
#define USE_SYSTEM_MALLOC 1

/* #include Directives {{{ */
#import "UICaboodle.h"

#include <objc/message.h>
#include <objc/objc.h>
#include <objc/runtime.h>

#include <CoreGraphics/CoreGraphics.h>
#include <GraphicsServices/GraphicsServices.h>
#include <Foundation/Foundation.h>

#if 0
#define DEPLOYMENT_TARGET_MACOSX 1
#define CF_BUILDING_CF 1
#include <CoreFoundation/CFInternal.h>
#endif

#include <CoreFoundation/CFPriv.h>
#include <CoreFoundation/CFUniChar.h>

#import <QuartzCore/CALayer.h>
#import <UIKit/UIKit.h>

#include <WebCore/WebCoreThread.h>
#import <WebKit/WebDefaultUIKitDelegate.h>

#include <algorithm>
#include <iomanip>
#include <sstream>
#include <string>

#include <ext/stdio_filebuf.h>

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

#include <apr-1/apr_pools.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/param.h>
#include <sys/mount.h>

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

#include <ext/hash_map>

#import "BrowserView.h"
#import "ResetView.h"

#import "substrate.h"
/* }}} */

//#define _finline __attribute__((force_inline))
#define _finline inline

struct timeval _ltv;
bool _itv;

#define _limit(count) do { \
    static size_t _count(0); \
    if (++_count == count) \
        exit(0); \
} while (false)

/* Profiler {{{ */
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
/* Objective-C Handle<> {{{ */
template <typename Type_>
class _H {
    typedef _H<Type_> This_;

  private:
    Type_ *value_;

    _finline void Retain_() {
        if (value_ != nil)
            [value_ retain];
    }

    _finline void Clear_() {
        if (value_ != nil)
            [value_ release];
    }

  public:
    _finline _H(Type_ *value = NULL, bool mended = false) :
        value_(value)
    {
        if (!mended)
            Retain_();
    }

    _finline ~_H() {
        Clear_();
    }

    _finline operator Type_ *() const {
        return value_;
    }

    _finline This_ &operator =(Type_ *value) {
        if (value_ != value) {
            Type_ *old(value_);
            value_ = value;
            Retain_();
            if (old != nil)
                [old release];
        } return *this;
    }
};
/* }}} */

#define _pooled _H<NSAutoreleasePool> _pool([[NSAutoreleasePool alloc] init], true);

void NSLogPoint(const char *fix, const CGPoint &point) {
    NSLog(@"%s(%g,%g)", fix, point.x, point.y);
}

void NSLogRect(const char *fix, const CGRect &rect) {
    NSLog(@"%s(%g,%g)+(%g,%g)", fix, rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
}

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

/* NSForcedOrderingSearch doesn't work on the iPhone */
static const NSStringCompareOptions MatchCompareOptions_ = NSLiteralSearch | NSCaseInsensitiveSearch;
static const NSStringCompareOptions LaxCompareOptions_ = NSNumericSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch | NSCaseInsensitiveSearch;
static const CFStringCompareFlags LaxCompareFlags_ = kCFCompareCaseInsensitive | kCFCompareNonliteral | kCFCompareLocalized | kCFCompareNumerically | kCFCompareWidthInsensitive | kCFCompareForcedOrdering;

/* iPhoneOS 2.0 Compatibility {{{ */
#ifdef __OBJC2__
@interface UITextView (iPhoneOS)
- (void) setTextSize:(float)size;
@end

@implementation UITextView (iPhoneOS)

- (void) setTextSize:(float)size {
    [self setFont:[[self font] fontWithSize:size]];
}

@end
#endif
/* }}} */

extern NSString * const kCAFilterNearest;

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
    NSString *bundle = [info objectForKey:@"CFBundleIdentifier"];
    [self setObject:info forKey:bundle];
}

@end
/* }}} */
/* Pop Transitions {{{ */
@interface PopTransitionView : UITransitionView {
}

@end

@implementation PopTransitionView

- (void) transitionViewDidComplete:(UITransitionView *)view fromView:(UIView *)from toView:(UIView *)to {
    if (from != nil && to == nil)
        [self removeFromSuperview];
}

@end

@implementation UIView (PopUpView)

- (void) popFromSuperviewAnimated:(BOOL)animated {
    [[self superview] transition:(animated ? UITransitionPushFromTop : UITransitionNone) toView:nil];
}

- (void) popSubview:(UIView *)view {
    UITransitionView *transition([[[PopTransitionView alloc] initWithFrame:[self bounds]] autorelease]);
    [transition setDelegate:transition];
    [self addSubview:transition];

    UIView *blank = [[[UIView alloc] initWithFrame:[transition bounds]] autorelease];
    [transition transition:UITransitionNone toView:blank];
    [transition transition:UITransitionPushFromBottom toView:view];
}

@end
/* }}} */

#define lprintf(args...) fprintf(stderr, args)

#define ForRelease 0
#define TraceLogging (1 && !ForRelease)
#define HistogramInsertionSort (0 && !ForRelease)
#define ProfileTimes (1 && !ForRelease)
#define ForSaurik (0 && !ForRelease)
#define LogBrowser (0 && !ForRelease)
#define TrackResize (0 && !ForRelease)
#define ManualRefresh (1 && !ForRelease)
#define ShowInternals (0 && !ForRelease)
#define IgnoreInstall (0 && !ForRelease)
#define RecycleWebViews 0
#define AlwaysReload (1 && !ForRelease)

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
- (void) radixSortUsingSelector:(SEL)selector withObject:(id)object;
- (void) radixSortUsingFunction:(SKRadixFunction)function withContext:(void *)argument;
@end

struct RadixItem_ {
    size_t index;
    uint32_t key;
};

static void RadixSort_(NSMutableArray *self, size_t count, struct RadixItem_ *swap) {
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

    NSMutableArray *values([NSMutableArray arrayWithCapacity:count]);
    for (size_t i(0); i != count; ++i)
        [values addObject:[self objectAtIndex:lhs[i].index]];
    [self setArray:values];

    delete [] swap;
}

@implementation NSMutableArray (Radix)

- (void) radixSortUsingSelector:(SEL)selector withObject:(id)object {
    size_t count([self count]);
    if (count == 0)
        return;

#if 0
    NSInvocation *invocation([NSInvocation invocationWithMethodSignature:[NSMethodSignature signatureWithObjCTypes:"L12@0:4@8"]]);
    [invocation setSelector:selector];
    [invocation setArgument:&object atIndex:2];
#else
    /* XXX: this is an unsafe optimization of doomy hell */
    Method method(class_getInstanceMethod([[self objectAtIndex:0] class], selector));
    _assert(method != NULL);
    uint32_t (*imp)(id, SEL, id) = reinterpret_cast<uint32_t (*)(id, SEL, id)>(method_getImplementation(method));
    _assert(imp != NULL);
#endif

    struct RadixItem_ *swap(new RadixItem_[count * 2]);

    for (size_t i(0); i != count; ++i) {
        RadixItem_ &item(swap[i]);
        item.index = i;

        id object([self objectAtIndex:i]);

#if 0
        [invocation setTarget:object];
        [invocation invoke];
        [invocation getReturnValue:&item.key];
#else
        item.key = imp(object, selector, object);
#endif
    }

    RadixSort_(self, count, swap);
}

- (void) radixSortUsingFunction:(SKRadixFunction)function withContext:(void *)argument {
    size_t count([self count]);
    struct RadixItem_ *swap(new RadixItem_[count * 2]);

    for (size_t i(0); i != count; ++i) {
        RadixItem_ &item(swap[i]);
        item.index = i;

        id object([self objectAtIndex:i]);
        item.key = function(object, argument);
    }

    RadixSort_(self, count, swap);
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

#if HistogramInsertionSort
    uint32_t total(0), *offsets(new uint32_t[range.length]);
#endif

    for (CFIndex index(1); index != range.length; ++index) {
        const void *value(values[index]);
        //CFIndex correct(SKBSearch_(&value, sizeof(const void *), values, index, comparator, context));
        CFIndex correct(index);
        while (comparator(value, values[correct - 1], context) == kCFCompareLessThan)
            if (--correct == 0)
                break;
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

#if HistogramInsertionSort
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

typedef enum {
    kUIControlEventMouseDown = 1 << 0,
    kUIControlEventMouseMovedInside = 1 << 2, // mouse moved inside control target
    kUIControlEventMouseMovedOutside = 1 << 3, // mouse moved outside control target
    kUIControlEventMouseUpInside = 1 << 6, // mouse up inside control target
    kUIControlEventMouseUpOutside = 1 << 7, // mouse up outside control target
    kUIControlAllEvents = (kUIControlEventMouseDown | kUIControlEventMouseMovedInside | kUIControlEventMouseMovedOutside | kUIControlEventMouseUpInside | kUIControlEventMouseUpOutside)
} UIControlEventMasks;

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

@interface NSString (UIKit)
- (NSString *) stringByAddingPercentEscapes;
- (NSString *) stringByReplacingCharacter:(unsigned short)arg0 withCharacter:(unsigned short)arg1;
@end

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
        stringByReplacingOccurrencesOfString:@"://"
        withString:@"://ne.edgecastcdn.net/8003A4/"
        options:0
        /* XXX: this is somewhat inaccurate */
        range:NSMakeRange(0, 10)
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

static inline NSString *CYLocalizeEx(NSString *key, NSString *value = nil) {
    return [[NSBundle mainBundle] localizedStringForKey:key value:value table:nil];
}

#define CYLocalize(key) CYLocalizeEx(@ key)

class CYString {
  private:
    char *data_;
    size_t size_;
    CFStringRef cache_;

    _finline void clear_() {
        if (cache_ != nil)
            CFRelease(cache_);
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
        cache_(nil)
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

    operator CFStringRef() {
        if (cache_ == NULL) {
            if (size_ == 0)
                return nil;
            cache_ = CFStringCreateWithBytesNoCopy(kCFAllocatorDefault, reinterpret_cast<uint8_t *>(data_), size_, kCFStringEncodingUTF8, NO, kCFAllocatorNull);
        } return cache_;
    }

    _finline operator id() {
        return (NSString *) static_cast<CFStringRef>(*this);
    }
};

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
class CGColor {
  private:
    CGColorRef color_;

  public:
    CGColor() :
        color_(NULL)
    {
    }

    CGColor(CGColorSpaceRef space, float red, float green, float blue, float alpha) :
        color_(NULL)
    {
        Set(space, red, green, blue, alpha);
    }

    void Clear() {
        if (color_ != NULL)
            CGColorRelease(color_);
    }

    ~CGColor() {
        Clear();
    }

    void Set(CGColorSpaceRef space, float red, float green, float blue, float alpha) {
        Clear();
        float color[] = {red, green, blue, alpha};
        color_ = CGColorCreate(space, color);
    }

    operator CGColorRef() {
        return color_;
    }
};
/* }}} */

extern "C" void UISetColor(CGColorRef color);

/* Random Global Variables {{{ */
static const int PulseInterval_ = 50000;
static const int ButtonBarHeight_ = 48;
static const float KeyboardTime_ = 0.3f;

#define SpringBoard_ "/System/Library/LaunchDaemons/com.apple.SpringBoard.plist"
#define SandboxTemplate_ "/usr/share/sandbox/SandboxTemplate.sb"
#define NotifyConfig_ "/etc/notify.conf"

static bool Queuing_;

static CGColor Blue_;
static CGColor Blueish_;
static CGColor Black_;
static CGColor Off_;
static CGColor White_;
static CGColor Gray_;
static CGColor Green_;
static CGColor Purple_;
static CGColor Purplish_;

static UIColor *InstallingColor_;
static UIColor *RemovingColor_;

static NSString *App_;
static NSString *Home_;
static BOOL Sounds_Keyboard_;

static BOOL Advanced_;
static BOOL Loaded_;
static BOOL Ignored_;

static UIFont *Font12_;
static UIFont *Font12Bold_;
static UIFont *Font14_;
static UIFont *Font18Bold_;
static UIFont *Font22Bold_;

static const char *Machine_ = NULL;
static const NSString *UniqueID_ = nil;
static const NSString *Build_ = nil;
static const NSString *Product_ = nil;
static const NSString *Safari_ = nil;

CFLocaleRef Locale_;
NSArray *Languages_;
CGColorSpaceRef space_;

bool bootstrap_;
bool reload_;

static NSDictionary *SectionMap_;
static NSMutableDictionary *Metadata_;
static _transient NSMutableDictionary *Settings_;
static _transient NSString *Role_;
static _transient NSMutableDictionary *Packages_;
static _transient NSMutableDictionary *Sections_;
static _transient NSMutableDictionary *Sources_;
static bool Changed_;
static NSDate *now_;

#if RecycleWebViews
static NSMutableArray *Documents_;
#endif

NSString *GetLastUpdate() {
    NSDate *update = [Metadata_ objectForKey:@"LastUpdate"];

    if (update == nil)
        return CYLocalize("NEVER_OR_UNKNOWN");

    CFDateFormatterRef formatter = CFDateFormatterCreate(NULL, Locale_, kCFDateFormatterMediumStyle, kCFDateFormatterMediumStyle);
    CFStringRef formatted = CFDateFormatterCreateStringWithDate(NULL, formatter, (CFDateRef) update);

    CFRelease(formatter);

    return [(NSString *) formatted autorelease];
}
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

static _finline CFStringRef CFCString(const char *value) {
    return CFStringCreateWithBytesNoCopy(kCFAllocatorDefault, reinterpret_cast<const uint8_t *>(value), strlen(value), kCFStringEncodingUTF8, NO, kCFAllocatorNull);
}

CFStringRef StripVersion(const char *version) {
    const char *colon(strchr(version, ':'));
    if (colon != NULL)
        version = colon + 1;
    return CFCString(version);
}

NSString *LocalizeSection(NSString *section) {
    static Pcre title_r("^(.*?) \\((.*)\\)$");
    if (title_r(section)) {
        NSString *parent(title_r[1]);
        NSString *child(title_r[2]);

        return [NSString stringWithFormat:CYLocalize("PARENTHETICAL"),
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

bool isSectionVisible(NSString *section) {
    NSDictionary *metadata([Sections_ objectForKey:section]);
    NSNumber *hidden(metadata == nil ? nil : [metadata objectForKey:@"Hidden"]);
    return hidden == nil || ![hidden boolValue];
}

/* Delegate Prototypes {{{ */
@class Package;
@class Source;

@interface NSObject (ProgressDelegate)
@end

@implementation NSObject(ProgressDelegate)

- (void) _setProgressError:(NSArray *)args {
    [self performSelector:@selector(setProgressError:forPackage:)
        withObject:[args objectAtIndex:0]
        withObject:([args count] == 1 ? nil : [args objectAtIndex:1])
    ];
}

@end

@protocol ProgressDelegate
- (void) setProgressError:(NSString *)error forPackage:(NSString *)id;
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

@class PackageView;

@protocol CydiaDelegate
- (void) setPackageView:(PackageView *)view;
- (void) clearPackage:(Package *)package;
- (void) installPackage:(Package *)package;
- (void) removePackage:(Package *)package;
- (void) slideUp:(UIActionSheet *)alert;
- (void) distUpgrade;
- (void) updateData;
- (void) syncData;
- (void) askForSettings;
- (UIProgressHUD *) addProgressHUD;
- (void) removeProgressHUD:(UIProgressHUD *)hud;
- (RVPage *) pageForURL:(NSURL *)url hasTag:(int *)tag;
- (RVPage *) pageForPackage:(NSString *)name;
- (void) openMailToURL:(NSURL *)url;
- (void) clearFirstResponder;
- (PackageView *) packageView;
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

    virtual bool MediaChange(std::string media, std::string drive) {
        return false;
    }

    virtual void IMSHit(pkgAcquire::ItemDesc &item) {
    }

    virtual void Fetch(pkgAcquire::ItemDesc &item) {
        //NSString *name([NSString stringWithUTF8String:item.ShortDesc.c_str()]);
        [delegate_ setProgressTitle:[NSString stringWithUTF8String:("Downloading " + item.ShortDesc).c_str()]];
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

        [delegate_ performSelectorOnMainThread:@selector(_setProgressError:)
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

  protected:
    virtual void Update() {
        /*[delegate_ setProgressTitle:[NSString stringWithUTF8String:Op.c_str()]];
        [delegate_ setProgressPercent:(Percent / 100)];*/
    }

  public:
    Progress() :
        delegate_(nil)
    {
    }

    void setDelegate(id delegate) {
        delegate_ = delegate;
    }

    virtual void Done() {
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
    NSMutableArray *packages_;

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
- (void) prepare;
- (void) perform;
- (void) upgrade;
- (void) update;

- (void) updateWithStatus:(Status &)status;

- (void) setDelegate:(id)delegate;
- (Source *) getSource:(pkgCache::PkgFileIterator)file;
@end
/* }}} */

/* Source Class {{{ */
@interface Source : NSObject {
    NSString *description_;
    NSString *label_;
    NSString *origin_;
    NSString *support_;

    NSString *uri_;
    NSString *distribution_;
    NSString *type_;
    NSString *version_;

    NSString *defaultIcon_;

    NSDictionary *record_;
    BOOL trusted_;
}

- (Source *) initWithMetaIndex:(metaIndex *)index;

- (NSComparisonResult) compareByNameAndType:(Source *)source;

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

#define _clear(field) \
    if (field != nil) \
        [field release]; \
    field = nil;

- (void) _clear {
    _clear(uri_)
    _clear(distribution_)
    _clear(type_)

    _clear(description_)
    _clear(label_)
    _clear(origin_)
    _clear(support_)
    _clear(version_)
    _clear(defaultIcon_)
    _clear(record_)
}

- (void) dealloc {
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

- (void) setMetaIndex:(metaIndex *)index {
    [self _clear];

    trusted_ = index->IsTrusted();

    uri_ = [[NSString stringWithUTF8String:index->GetURI().c_str()] retain];
    distribution_ = [[NSString stringWithUTF8String:index->GetDist().c_str()] retain];
    type_ = [[NSString stringWithUTF8String:index->GetType()] retain];

    debReleaseIndex *dindex(dynamic_cast<debReleaseIndex *>(index));
    if (dindex != NULL) {
        std::ifstream release(dindex->MetaIndexFile("Release").c_str());
        std::string line;
        while (std::getline(release, line)) {
            std::string::size_type colon(line.find(':'));
            if (colon == std::string::npos)
                continue;

            std::string name(line.substr(0, colon));
            std::string value(line.substr(colon + 1));
            while (!value.empty() && value[0] == ' ')
                value = value.substr(1);

            if (name == "Default-Icon")
                defaultIcon_ = [[NSString stringWithUTF8String:value.c_str()] retain];
            else if (name == "Description")
                description_ = [[NSString stringWithUTF8String:value.c_str()] retain];
            else if (name == "Label")
                label_ = [[NSString stringWithUTF8String:value.c_str()] retain];
            else if (name == "Origin")
                origin_ = [[NSString stringWithUTF8String:value.c_str()] retain];
            else if (name == "Support")
                support_ = [[NSString stringWithUTF8String:value.c_str()] retain];
            else if (name == "Version")
                version_ = [[NSString stringWithUTF8String:value.c_str()] retain];
        }
    }

    record_ = [Sources_ objectForKey:[self key]];
    if (record_ != nil)
        record_ = [record_ retain];
}

- (Source *) initWithMetaIndex:(metaIndex *)index {
    if ((self = [super init]) != nil) {
        [self setMetaIndex:index];
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

- (NSString *) supportForPackage:(NSString *)package {
    return support_ == nil ? nil : [support_ stringByReplacingOccurrencesOfString:@"*" withString:package];
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
    return [NSString stringWithFormat:@"%@:%@:%@", type_, uri_, distribution_];
}

- (NSString *) host {
    return [[[NSURL URLWithString:[self uri]] host] lowercaseString];
}

- (NSString *) name {
    return origin_ == nil ? [self host] : origin_;
}

- (NSString *) description {
    return description_;
}

- (NSString *) label {
    return label_ == nil ? [self host] : label_;
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
    bool cached_;
    bool parsed_;

    CYString section_;
    NSString *section$_;
    bool essential_;
    bool visible_;

    NSString *latest_;
    NSString *installed_;

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

    CYString support_;
    NSMutableArray *tags_;
    NSString *role_;

    NSArray *relationships_;

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
- (NSArray *) relationships;
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

- (uint32_t) compareForChanges;

- (void) install;
- (void) remove;

- (bool) isUnfilteredAndSearchedForBy:(NSString *)search;
- (bool) isInstalledAndVisible:(NSNumber *)number;
- (bool) isVisiblyUninstalledInSection:(NSString *)section;
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
                data[i] &= 0xdf;
    }

    if (offset == 0)
        data[0] = (data[0] & 0x3f) | "\x80\x00\xc0\x40"[data[0] >> 6];

    /* XXX: ntohl may be more honest */
    return OSSwapInt32(*reinterpret_cast<uint32_t *>(data));
}

CYString &(*PackageName)(Package *self, SEL sel);

CFComparisonResult PackageNameCompare(Package *lhs, Package *rhs, void *arg) {
    _profile(PackageNameCompare)
        CYString &lhi(PackageName(lhs, @selector(cyname)));
        CYString &rhi(PackageName(rhs, @selector(cyname)));
        CFStringRef lhn(lhi), rhn(rhi);

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
    if (section$_ != nil)
        [section$_ release];

    if (latest_ != nil)
        [latest_ release];
    if (installed_ != nil)
        [installed_ release];

    if (sponsor$_ != nil)
        [sponsor$_ release];
    if (author$_ != nil)
        [author$_ release];
    if (tags_ != nil)
        [tags_ release];
    if (role_ != nil)
        [role_ release];

    if (relationships_ != nil)
        [relationships_ release];
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
            if (!homepage_.empty())
                homepage_ = website;
            if (homepage_ == depiction_)
                homepage_.clear();
        _end
    _end
}

- (Package *) initWithVersion:(pkgCache::VerIterator)version withZone:(NSZone *)zone inPool:(apr_pool_t *)pool database:(Database *)database {
    if ((self = [super init]) != nil) {
    _profile(Package$initWithVersion)
    @synchronized (database) {
        era_ = [database era];
        pool_ = pool;

        version_ = version;
        iterator_ = version.ParentPkg();
        database_ = database;

        _profile(Package$initWithVersion$Latest)
            latest_ = (NSString *) StripVersion(version_.VerStr());
        _end

        pkgCache::VerIterator current;
        _profile(Package$initWithVersion$Versions)
            current = iterator_.CurrentVer();
            if (!current.end())
                installed_ = (NSString *) StripVersion(current.VerStr());

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

        if (!file_.end()) {
            _profile(Package$initWithVersion$Source)
                source_ = [database_ getSource:file_.File()];
                if (source_ != nil)
                    [source_ retain];
                cached_ = true;
            _end
        }

        _profile(Package$initWithVersion$Tags)
            pkgCache::TagIterator tag(iterator_.TagList());
            if (!tag.end()) {
                tags_ = [[NSMutableArray alloc] initWithCapacity:8];
                do {
                    const char *name(tag.Name());
                    [tags_ addObject:(NSString *)CFCString(name)];
                    if (role_ == nil && strncmp(name, "role::", 6) == 0)
                        role_ = (NSString *) CFCString(name + 6);
                    ++tag;
                } while (!tag.end());
            }
        _end

        bool changed(false);
        NSString *key([id_ lowercaseString]);

        _profile(Package$initWithVersion$Metadata)
            metadata_ = [Packages_ objectForKey:key];

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
                [Packages_ setObject:metadata_ forKey:key];
                Changed_ = true;
            }
        _end

        _profile(Package$initWithVersion$Section)
            section_.set(pool_, iterator_.Section());
        _end

        essential_ = ((iterator_->Flags & pkgCache::Flag::Essential) == 0 ? NO : YES) || [self hasTag:@"cydia::essential"];
        visible_ = [self hasSupportingRole] && [self unfiltered];
    } _end } return self;
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

        std::replace(section_.data(), section_.data() + section_.size(), ' ', '_');
        NSString *name(section_);

      lookup:
        if (NSDictionary *value = [SectionMap_ objectForKey:name])
            if (NSString *rename = [value objectForKey:@"Rename"]) {
                name = rename;
                goto lookup;
            }

        section$_ = [[name stringByReplacingCharacter:'_' withCharacter:' '] retain];
    } return section$_;
}

- (NSString *) simpleSection {
    if (NSString *section = [self section])
        return Simplify(section);
    else
        return nil;
}

- (NSString *) longSection {
    return LocalizeSection(section_);
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
    if (file_.end())
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
}

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

- (BOOL) valid {
    return !version_.end();
}

- (BOOL) upgradableAndEssential:(BOOL)essential {
    _profile(Package$upgradableAndEssential)
        pkgCache::VerIterator current(iterator_.CurrentVer());
        if (current.end())
            return essential && essential_ && visible_;
        else
            return !version_.end() && version_ != current;// && (!essential || ![database_ cache][iterator_].Keep());
    _end
}

- (BOOL) essential {
    return essential_;
}

- (BOOL) broken {
    return [database_ cache][iterator_].InstBroken();
}

- (BOOL) unfiltered {
    NSString *section([self section]);
    return section == nil || isSectionVisible(section);
}

- (BOOL) visible {
    return visible_;
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
                default:
                    _assert(false);
            }
        default:
            _assert(false);
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
        if ([icon_ hasPrefix:@"file:///"])
            icon = [UIImage imageAtPath:[icon_ substringFromIndex:7]];
    if (icon == nil) if (section != nil)
        icon = [UIImage imageAtPath:[NSString stringWithFormat:@"%@/Sections/%@.png", App_, section]];
    if (icon == nil) if (source_ != nil) if (NSString *dicon = [source_ defaultIcon])
        if ([dicon hasPrefix:@"file:///"])
            icon = [UIImage imageAtPath:[dicon substringFromIndex:7]];
    if (icon == nil)
        icon = [UIImage applicationImageNamed:@"unknown.png"];
    return icon;
}

- (NSString *) homepage {
    return homepage_;
}

- (NSString *) depiction {
    return depiction_;
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
    return !support_.empty() ? support_ : [[self source] supportForPackage:id_];
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

- (NSArray *) relationships {
    return relationships_;
}

- (NSArray *) warnings {
    NSMutableArray *warnings([NSMutableArray arrayWithCapacity:4]);
    const char *name(iterator_.Name());

    size_t length(strlen(name));
    if (length < 2) invalid:
        [warnings addObject:CYLocalize("ILLEGAL_PACKAGE_IDENTIFIER")];
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
        bool _private = false;
        bool stash = false;

        bool repository = [[self section] isEqualToString:@"Repositories"];

        if (NSArray *files = [self files])
            for (NSString *file in files)
                if (!cydia && [file isEqualToString:@"/Applications/Cydia.app"])
                    cydia = true;
                else if (!_private && [file isEqualToString:@"/private"])
                    _private = true;
                else if (!stash && [file isEqualToString:@"/var/stash"])
                    stash = true;

        /* XXX: this is not sensitive enough. only some folders are valid. */
        if (cydia && !repository)
            [warnings addObject:[NSString stringWithFormat:CYLocalize("FILES_INSTALLED_TO"), @"Cydia.app"]];
        if (_private)
            [warnings addObject:[NSString stringWithFormat:CYLocalize("FILES_INSTALLED_TO"), @"/private"]];
        if (stash)
            [warnings addObject:[NSString stringWithFormat:CYLocalize("FILES_INSTALLED_TO"), @"/var/stash"]];
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
    if (!cached_) {
        @synchronized (database_) {
            if ([database_ era] != era_ || file_.end())
                source_ = nil;
            else {
                source_ = [database_ getSource:file_.File()];
                if (source_ != nil)
                    [source_ retain];
            }

            cached_ = true;
        }
    }

    return source_;
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

- (uint32_t) compareForChanges {
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

- (void) clear {
    pkgProblemResolver *resolver = [database_ resolver];
    resolver->Clear(iterator_);
    resolver->Protect(iterator_);
}

- (void) install {
    pkgProblemResolver *resolver = [database_ resolver];
    resolver->Clear(iterator_);
    resolver->Protect(iterator_);
    pkgCacheFile &cache([database_ cache]);
    cache->MarkInstall(iterator_, false);
    pkgDepCache::StateCache &state((*cache)[iterator_]);
    if (!state.Install())
        cache->SetReInstall(iterator_, true);
}

- (void) remove {
    pkgProblemResolver *resolver = [database_ resolver];
    resolver->Clear(iterator_);
    resolver->Protect(iterator_);
    resolver->Remove(iterator_);
    [database_ cache]->MarkDelete(iterator_, true);
}

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

- (bool) isInstalledAndVisible:(NSNumber *)number {
    return (![number boolValue] || [self visible]) && [self installed] != nil;
}

- (bool) isVisiblyUninstalledInSection:(NSString *)name {
    NSString *section = [self section];

    return
        [self visible] &&
        [self installed] == nil && (
            name == nil ||
            section == nil && [name length] == 0 ||
            [name isEqualToString:section]
        );
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
        name_ = [(index == '#' ? @"123" : [NSString stringWithCharacters:&index length:1]) retain];
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

static int Finish_;
static NSArray *Finishes_;

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

    _assert(false);
}

- (void) _readStatus:(NSNumber *)fd { _pooled
    __gnu_cxx::stdio_filebuf<char> ib([fd intValue], std::ios::in);
    std::istream is(&ib);
    std::string line;

    static Pcre conffile_r("^status: [^ ]* : conffile-prompt : (.*?) *$");
    static Pcre pmstatus_r("^([^:]*):([^:]*):([^:]*):(.*)$");

    while (std::getline(is, line)) {
        const char *data(line.c_str());
        size_t size = line.size();
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
                [delegate_ performSelectorOnMainThread:@selector(_setProgressError:)
                    withObject:[NSArray arrayWithObjects:string, id, nil]
                    waitUntilDone:YES
                ];
            else if (type == "pmstatus") {
                [delegate_ setProgressTitle:string];
            } else if (type == "pmconffile")
                [delegate_ setConfigurationData:string];
            else _assert(false);
        } else _assert(false);
    }

    _assert(false);
}

- (void) _readOutput:(NSNumber *)fd { _pooled
    __gnu_cxx::stdio_filebuf<char> ib([fd intValue], std::ios::in);
    std::istream is(&ib);
    std::string line;

    while (std::getline(is, line)) {
        lprintf("O:%s\n", line.c_str());
        [delegate_ addProgressOutput:[NSString stringWithUTF8String:line.c_str()]];
    }

    _assert(false);
}

- (FILE *) input {
    return input_;
}

- (Package *) packageWithName:(NSString *)name {
    if (static_cast<pkgDepCache *>(cache_) == NULL)
        return nil;
    pkgCache::PkgIterator iterator(cache_->FindPkg([name UTF8String]));
    return iterator.end() ? nil : [Package packageWithIterator:iterator withZone:NULL inPool:pool_ database:self];
}

- (Database *) init {
    if ((self = [super init]) != nil) {
        policy_ = NULL;
        records_ = NULL;
        resolver_ = NULL;
        fetcher_ = NULL;
        lock_ = NULL;

        zone_ = NSCreateZone(1024 * 1024, 256 * 1024, NO);
        apr_pool_create(&pool_, NULL);

        packages_ = [[NSMutableArray alloc] init];

        int fds[2];

        _assert(pipe(fds) != -1);
        cydiafd_ = fds[1];

        _config->Set("APT::Keep-Fds::", cydiafd_);
        setenv("CYDIA", [[[[NSNumber numberWithInt:cydiafd_] stringValue] stringByAppendingString:@" 1"] UTF8String], _not(int));

        [NSThread
            detachNewThreadSelector:@selector(_readCydia:)
            toTarget:self
            withObject:[[NSNumber numberWithInt:fds[0]] retain]
        ];

        _assert(pipe(fds) != -1);
        statusfd_ = fds[1];

        [NSThread
            detachNewThreadSelector:@selector(_readStatus:)
            toTarget:self
            withObject:[[NSNumber numberWithInt:fds[0]] retain]
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
            withObject:[[NSNumber numberWithInt:fds[0]] retain]
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
    return packages_;
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

    for (Package *package in packages_) {
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

            Package *package([self packageWithName:[NSString stringWithUTF8String:start.TargetPkg().Name()]]);
            [failure addObject:[package name]];

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

- (void) reloadData { _pooled
    @synchronized (self) {
        ++era_;
    }

    [packages_ removeAllObjects];
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

    _trace();
    if (!cache_.Open(progress_, true)) {
        std::string error;
        if (!_error->PopMessage(error))
            _assert(false);
        _error->Discard();
        lprintf("cache_.Open():[%s]\n", error.c_str());

        if (error == "dpkg was interrupted, you must manually run 'dpkg --configure -a' to correct the problem. ")
            [delegate_ repairWithSelector:@selector(configure)];
        else if (error == "The package lists or status file could not be parsed or opened.")
            [delegate_ repairWithSelector:@selector(update)];
        // else if (error == "Could not open lock file /var/lib/dpkg/lock - open (13 Permission denied)")
        // else if (error == "Could not get lock /var/lib/dpkg/lock - open (35 Resource temporarily unavailable)")
        // else if (error == "The list of sources could not be read.")
        else _assert(false);

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
    _assert(list_->ReadMainList());

    _assert(cache_->DelCount() == 0 && cache_->InstCount() == 0);
    _assert(pkgApplyStatus(cache_));

    if (cache_->BrokenCount() != 0) {
        _assert(pkgFixBroken(cache_));
        _assert(cache_->BrokenCount() == 0);
        _assert(pkgMinimizeUpgrade(cache_));
    }

    _trace();

    for (pkgSourceList::const_iterator source = list_->begin(); source != list_->end(); ++source) {
        std::vector<pkgIndexFile *> *indices = (*source)->GetIndexFiles();
        for (std::vector<pkgIndexFile *>::const_iterator index = indices->begin(); index != indices->end(); ++index)
            // XXX: this could be more intelligent
            if (dynamic_cast<debPackagesIndex *>(*index) != NULL) {
                pkgCache::PkgFileIterator cached((*index)->FindInCache(cache_));
                if (!cached.end())
                    sources_[cached->ID] = [[[Source alloc] initWithMetaIndex:*source] autorelease];
            }
    }

    _trace();

    {
        /*std::vector<Package *> packages;
        packages.reserve(std::max(10000U, [packages_ count] + 1000));
        [packages_ release];
        packages_ = nil;*/

        _trace();

        for (pkgCache::PkgIterator iterator = cache_->PkgBegin(); !iterator.end(); ++iterator)
            if (Package *package = [Package packageWithIterator:iterator withZone:zone_ inPool:pool_ database:self])
                //packages.push_back(package);
                [packages_ addObject:package];

        _trace();

        /*if (packages.empty())
            packages_ = [[NSArray alloc] init];
        else
            packages_ = [[NSArray alloc] initWithObjects:&packages.front() count:packages.size()];
        _trace();*/

        [packages_ radixSortUsingFunction:reinterpret_cast<SKRadixFunction>(&PackagePrefixRadix) withContext:reinterpret_cast<void *>(16)];
        [packages_ radixSortUsingFunction:reinterpret_cast<SKRadixFunction>(&PackagePrefixRadix) withContext:reinterpret_cast<void *>(4)];
        [packages_ radixSortUsingFunction:reinterpret_cast<SKRadixFunction>(&PackagePrefixRadix) withContext:reinterpret_cast<void *>(0)];

        /*_trace();
        PrintTimes();
        _trace();*/

        _trace();

        /*if (!packages.empty())
            CFQSortArray(&packages.front(), packages.size(), sizeof(packages.front()), reinterpret_cast<CFComparatorFunction>(&PackageNameCompare_), NULL);*/
        //std::sort(packages.begin(), packages.end(), PackageNameOrdering());

        //CFArraySortValues((CFMutableArrayRef) packages_, CFRangeMake(0, [packages_ count]), reinterpret_cast<CFComparatorFunction>(&PackageNameCompare), NULL);

        CFArrayInsertionSortValues((CFMutableArrayRef) packages_, CFRangeMake(0, [packages_ count]), reinterpret_cast<CFComparatorFunction>(&PackageNameCompare), NULL);

        //[packages_ sortUsingFunction:reinterpret_cast<NSComparisonResult (*)(id, id, void *)>(&PackageNameCompare) context:NULL];

        _trace();
    }
}

- (void) configure {
    NSString *dpkg = [NSString stringWithFormat:@"dpkg --configure -a --status-fd %u", statusfd_];
    system([dpkg UTF8String]);
}

- (void) clean {
    if (lock_ != NULL)
        return;

    FileFd Lock;
    Lock.Fd(GetLock(_config->FindDir("Dir::Cache::Archives") + "lock"));
    _assert(!_error->PendingError());

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

    if (!cleaner.Go(_config->FindDir("Dir::Cache::Archives") + "partial/", cache_)) {
        std::string error;
        while (_error->PopMessage(error))
            lprintf("ArchiveCleaner: %s\n", error.c_str());
    }
}

- (void) prepare {
    pkgRecords records(cache_);

    lock_ = new FileFd();
    lock_->Fd(GetLock(_config->FindDir("Dir::Cache::Archives") + "lock"));
    _assert(!_error->PendingError());

    pkgSourceList list;
    // XXX: explain this with an error message
    _assert(list.ReadMainList());

    manager_ = (_system->CreatePM(cache_));
    _assert(manager_->GetArchives(fetcher_, &list, &records));
    _assert(!_error->PendingError());
}

- (void) perform {
    NSMutableArray *before = [NSMutableArray arrayWithCapacity:16]; {
        pkgSourceList list;
        _assert(list.ReadMainList());
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

        std::string uri = (*item)->DescURI();
        std::string error = (*item)->ErrorText;

        lprintf("pAf:%s:%s\n", uri.c_str(), error.c_str());
        failed = true;

        [delegate_ performSelectorOnMainThread:@selector(_setProgressError:)
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
        _assert(list.ReadMainList());
        for (pkgSourceList::const_iterator source = list.begin(); source != list.end(); ++source)
            [after addObject:[NSString stringWithUTF8String:(*source)->GetURI().c_str()]];
    }

    if (![before isEqualToArray:after])
        [self update];
}

- (void) upgrade {
    _assert(pkgDistUpgrade(cache_));
}

- (void) update {
    [self updateWithStatus:status_];
}

- (void) updateWithStatus:(Status &)status {
    pkgSourceList list;
    _assert(list.ReadMainList());

    FileFd lock;
    lock.Fd(GetLock(_config->FindDir("Dir::State::Lists") + "lock"));
    _assert(!_error->PendingError());

    pkgAcquire fetcher(&status);
    _assert(list.GetIndexes(&fetcher));

    if (fetcher.Run(PulseInterval_) != pkgAcquire::Failed) {
        bool failed = false;
        for (pkgAcquire::ItemIterator item = fetcher.ItemsBegin(); item != fetcher.ItemsEnd(); item++)
            if ((*item)->Status != pkgAcquire::Item::StatDone) {
                (*item)->Finished();
                failed = true;
            }

        if (!failed && _config->FindB("APT::Get::List-Cleanup", true) == true) {
            _assert(fetcher.Clean(_config->FindDir("Dir::State::lists")));
            _assert(fetcher.Clean(_config->FindDir("Dir::State::lists") + "partial/"));
        }

        [Metadata_ setObject:[NSDate date] forKey:@"LastUpdate"];
        Changed_ = true;
    }
}

- (void) setDelegate:(id)delegate {
    delegate_ = delegate;
    status_.setDelegate(delegate);
    progress_.setDelegate(delegate);
}

- (Source *) getSource:(pkgCache::PkgFileIterator)file {
    return sources_[file->ID];
}

@end
/* }}} */

/* PopUp Windows {{{ */
@interface PopUpView : UIView {
    _transient id delegate_;
    UITransitionView *transition_;
    UIView *overlay_;
}

- (void) cancel;
- (id) initWithView:(UIView *)view delegate:(id)delegate;

@end

@implementation PopUpView

- (void) dealloc {
    [transition_ setDelegate:nil];
    [transition_ release];
    [overlay_ release];
    [super dealloc];
}

- (void) cancel {
    [transition_ transition:UITransitionPushFromTop toView:nil];
}

- (void) transitionViewDidComplete:(UITransitionView*)view fromView:(UIView*)from toView:(UIView*)to {
    if (from != nil && to == nil)
        [self removeFromSuperview];
}

- (id) initWithView:(UIView *)view delegate:(id)delegate {
    if ((self = [super initWithFrame:[view bounds]]) != nil) {
        delegate_ = delegate;

        transition_ = [[UITransitionView alloc] initWithFrame:[self bounds]];
        [self addSubview:transition_];

        overlay_ = [[UIView alloc] initWithFrame:[transition_ bounds]];

        [view addSubview:self];

        [transition_ setDelegate:self];

        UIView *blank = [[[UIView alloc] initWithFrame:[transition_ bounds]] autorelease];
        [transition_ transition:UITransitionNone toView:blank];
        [transition_ transition:UITransitionPushFromBottom toView:overlay_];
    } return self;
}

@end
/* }}} */

#if 0
/* Mail Composition {{{ */
@interface MailToView : PopUpView {
    MailComposeController *controller_;
}

- (id) initWithView:(UIView *)view delegate:(id)delegate url:(NSURL *)url;

@end

@implementation MailToView

- (void) dealloc {
    [controller_ release];
    [super dealloc];
}

- (void) mailComposeControllerWillAttemptToSend:(MailComposeController *)controller {
    NSLog(@"will");
}

- (void) mailComposeControllerDidAttemptToSend:(MailComposeController *)controller mailDelivery:(id)delivery {
    NSLog(@"did:%@", delivery);
// [UIApp setStatusBarShowsProgress:NO];
if ([controller error]){
NSArray *buttons = [NSArray arrayWithObjects:CYLocalize("OK"), nil];
UIActionSheet *mailAlertSheet = [[UIActionSheet alloc] initWithTitle:CYLocalize("ERROR") buttons:buttons defaultButtonIndex:0 delegate:self context:self];
[mailAlertSheet setBodyText:[controller error]];
[mailAlertSheet popupAlertAnimated:YES];
}
}

- (void) showError {
    NSLog(@"%@", [controller_ error]);
    NSArray *buttons = [NSArray arrayWithObjects:CYLocalize("OK"), nil];
    UIActionSheet *mailAlertSheet = [[UIActionSheet alloc] initWithTitle:CYLocalize("ERROR") buttons:buttons defaultButtonIndex:0 delegate:self context:self];
    [mailAlertSheet setBodyText:[controller_ error]];
    [mailAlertSheet popupAlertAnimated:YES];
}

- (void) deliverMessage { _pooled
    setuid(501);
    setgid(501);

    if (![controller_ deliverMessage])
        [self performSelectorOnMainThread:@selector(showError) withObject:nil waitUntilDone:NO];
}

- (void) mailComposeControllerCompositionFinished:(MailComposeController *)controller {
    if ([controller_ needsDelivery])
        [NSThread detachNewThreadSelector:@selector(deliverMessage) toTarget:self withObject:nil];
    else
        [self cancel];
}

- (id) initWithView:(UIView *)view delegate:(id)delegate url:(NSURL *)url {
    if ((self = [super initWithView:view delegate:delegate]) != nil) {
        controller_ = [[MailComposeController alloc] initForContentSize:[overlay_ bounds].size];
        [controller_ setDelegate:self];
        [controller_ initializeUI];
        [controller_ setupForURL:url];

        UIView *view([controller_ view]);
        [overlay_ addSubview:view];
    } return self;
}

@end
/* }}} */
#endif

/* Confirmation View {{{ */
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

@protocol ConfirmationViewDelegate
- (void) cancel;
- (void) confirm;
- (void) queue;
@end

@interface ConfirmationView : BrowserView {
    _transient Database *database_;
    UIActionSheet *essential_;
    NSArray *changes_;
    NSArray *issues_;
    NSArray *sizes_;
    BOOL substrate_;
}

- (id) initWithBook:(RVBook *)book database:(Database *)database;

@end

@implementation ConfirmationView

- (void) dealloc {
    [changes_ release];
    if (issues_ != nil)
        [issues_ release];
    [sizes_ release];
    if (essential_ != nil)
        [essential_ release];
    [super dealloc];
}

- (void) cancel {
    [delegate_ cancel];
    [book_ popFromSuperviewAnimated:YES];
}

- (void) alertSheet:(UIActionSheet *)sheet buttonClicked:(int)button {
    NSString *context([sheet context]);

    if ([context isEqualToString:@"remove"]) {
        switch (button) {
            case 1:
                [self cancel];
                break;
            case 2:
                if (substrate_)
                    Finish_ = 2;
                [delegate_ confirm];
                break;
            default:
                _assert(false);
        }

        [sheet dismiss];
    } else if ([context isEqualToString:@"unable"]) {
        [self cancel];
        [sheet dismiss];
    } else
        [super alertSheet:sheet buttonClicked:button];
}

- (void) webView:(WebView *)sender didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame {
    [super webView:sender didClearWindowObject:window forFrame:frame];
    [window setValue:changes_ forKey:@"changes"];
    [window setValue:issues_ forKey:@"issues"];
    [window setValue:sizes_ forKey:@"sizes"];
}

- (id) initWithBook:(RVBook *)book database:(Database *)database {
    if ((self = [super initWithBook:book]) != nil) {
        database_ = database;

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
        else if (Advanced_ || true) {
            NSString *parenthetical(CYLocalize("PARENTHETICAL"));

            essential_ = [[UIActionSheet alloc]
                initWithTitle:CYLocalize("REMOVING_ESSENTIALS")
                buttons:[NSArray arrayWithObjects:
                    [NSString stringWithFormat:parenthetical, CYLocalize("CANCEL_OPERATION"), CYLocalize("SAFE")],
                    [NSString stringWithFormat:parenthetical, CYLocalize("FORCE_REMOVAL"), CYLocalize("UNSAFE")],
                nil]
                defaultButtonIndex:0
                delegate:self
                context:@"remove"
            ];

#ifndef __OBJC2__
            [essential_ setDestructiveButton:[[essential_ buttons] objectAtIndex:0]];
#endif
            [essential_ setBodyText:CYLocalize("REMOVING_ESSENTIALS_EX")];
        } else {
            essential_ = [[UIActionSheet alloc]
                initWithTitle:CYLocalize("UNABLE_TO_COMPLY")
                buttons:[NSArray arrayWithObjects:CYLocalize("OKAY"), nil]
                defaultButtonIndex:0
                delegate:self
                context:@"unable"
            ];

            [essential_ setBodyText:CYLocalize("UNABLE_TO_COMPLY_EX")];
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
            SizeString([database_ cache]->UsrSize()),
        nil];

        [self loadURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"confirm" ofType:@"html"]]];
    } return self;
}

- (NSString *) backButtonTitle {
    return CYLocalize("CONFIRM");
}

- (NSString *) leftButtonTitle {
    return [NSString stringWithFormat:CYLocalize("SLASH_DELIMITED"), CYLocalize("CANCEL"), CYLocalize("QUEUE")];
}

- (id) rightButtonTitle {
    return issues_ != nil ? nil : [super rightButtonTitle];
}

- (id) _rightButtonTitle {
#if AlwaysReload || IgnoreInstall
    return [super _rightButtonTitle];
#else
    return CYLocalize("CONFIRM");
#endif
}

- (void) _leftButtonClicked {
    [self cancel];
}

#if !AlwaysReload
- (void) _rightButtonClicked {
#if IgnoreInstall
    return [super _rightButtonClicked];
#endif
    if (essential_ != nil)
        [essential_ popupAlertAnimated:YES];
    else {
        if (substrate_)
            Finish_ = 2;
        [delegate_ confirm];
    }
}
#endif

@end
/* }}} */

/* Progress Data {{{ */
@interface ProgressData : NSObject {
    SEL selector_;
    id target_;
    id object_;
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
/* Progress View {{{ */
@interface ProgressView : UIView <
    ConfigurationDelegate,
    ProgressDelegate
> {
    _transient Database *database_;
    UIView *view_;
    UIView *background_;
    UITransitionView *transition_;
    UIView *overlay_;
    UINavigationBar *navbar_;
    UIProgressBar *progress_;
    UITextView *output_;
    UITextLabel *status_;
    UIPushButton *close_;
    id delegate_;
    BOOL running_;
    SHA1SumValue springlist_;
    SHA1SumValue notifyconf_;
    SHA1SumValue sandplate_;
}

- (void) transitionViewDidComplete:(UITransitionView*)view fromView:(UIView*)from toView:(UIView*)to;

- (id) initWithFrame:(struct CGRect)frame database:(Database *)database delegate:(id)delegate;
- (void) setContentView:(UIView *)view;
- (void) resetView;

- (void) _retachThread;
- (void) _detachNewThreadData:(ProgressData *)data;
- (void) detachNewThreadSelector:(SEL)selector toTarget:(id)target withObject:(id)object title:(NSString *)title;

- (BOOL) isRunning;

@end

@protocol ProgressViewDelegate
- (void) progressViewIsComplete:(ProgressView *)sender;
@end

@implementation ProgressView

- (void) dealloc {
    [transition_ setDelegate:nil];
    [navbar_ setDelegate:nil];

    [view_ release];
    if (background_ != nil)
        [background_ release];
    [transition_ release];
    [overlay_ release];
    [navbar_ release];
    [progress_ release];
    [output_ release];
    [status_ release];
    [close_ release];
    [super dealloc];
}

- (void) transitionViewDidComplete:(UITransitionView*)view fromView:(UIView*)from toView:(UIView*)to {
    if (bootstrap_ && from == overlay_ && to == view_)
        exit(0);
}

- (id) initWithFrame:(struct CGRect)frame database:(Database *)database delegate:(id)delegate {
    if ((self = [super initWithFrame:frame]) != nil) {
        database_ = database;
        delegate_ = delegate;

        transition_ = [[UITransitionView alloc] initWithFrame:[self bounds]];
        [transition_ setDelegate:self];

        overlay_ = [[UIView alloc] initWithFrame:[transition_ bounds]];

        if (bootstrap_)
            [overlay_ setBackgroundColor:[UIColor blackColor]];
        else {
            background_ = [[UIView alloc] initWithFrame:[self bounds]];
            [background_ setBackgroundColor:[UIColor blackColor]];
            [self addSubview:background_];
        }

        [self addSubview:transition_];

        CGSize navsize = [UINavigationBar defaultSize];
        CGRect navrect = {{0, 0}, navsize};

        navbar_ = [[UINavigationBar alloc] initWithFrame:navrect];
        [overlay_ addSubview:navbar_];

        [navbar_ setBarStyle:1];
        [navbar_ setDelegate:self];

        UINavigationItem *navitem = [[[UINavigationItem alloc] initWithTitle:nil] autorelease];
        [navbar_ pushNavigationItem:navitem];

        CGRect bounds = [overlay_ bounds];
        CGSize prgsize = [UIProgressBar defaultSize];

        CGRect prgrect = {{
            (bounds.size.width - prgsize.width) / 2,
            bounds.size.height - prgsize.height - 20
        }, prgsize};

        progress_ = [[UIProgressBar alloc] initWithFrame:prgrect];
        [progress_ setStyle:0];

        status_ = [[UITextLabel alloc] initWithFrame:CGRectMake(
            10,
            bounds.size.height - prgsize.height - 50,
            bounds.size.width - 20,
            24
        )];

        [status_ setColor:[UIColor whiteColor]];
        [status_ setBackgroundColor:[UIColor clearColor]];

        [status_ setCentersHorizontally:YES];
        //[status_ setFont:font];
        _trace();

        output_ = [[UITextView alloc] initWithFrame:CGRectMake(
            10,
            navrect.size.height + 20,
            bounds.size.width - 20,
            bounds.size.height - navsize.height - 62 - navrect.size.height
        )];
        _trace();

        //[output_ setTextFont:@"Courier New"];
        [output_ setTextSize:12];

        [output_ setTextColor:[UIColor whiteColor]];
        [output_ setBackgroundColor:[UIColor clearColor]];

        [output_ setMarginTop:0];
        [output_ setAllowsRubberBanding:YES];
        [output_ setEditable:NO];

        [overlay_ addSubview:output_];

        close_ = [[UIPushButton alloc] initWithFrame:CGRectMake(
            10,
            bounds.size.height - prgsize.height - 50,
            bounds.size.width - 20,
            32 + prgsize.height
        )];

        [close_ setAutosizesToFit:NO];
        [close_ setDrawsShadow:YES];
        [close_ setStretchBackground:YES];
        [close_ setEnabled:YES];

        UIFont *bold = [UIFont boldSystemFontOfSize:22];
        [close_ setTitleFont:bold];

        [close_ addTarget:self action:@selector(closeButtonPushed) forEvents:kUIControlEventMouseUpInside];
        [close_ setBackground:[UIImage applicationImageNamed:@"green-up.png"] forState:0];
        [close_ setBackground:[UIImage applicationImageNamed:@"green-dn.png"] forState:1];
    } return self;
}

- (void) setContentView:(UIView *)view {
    view_ = [view retain];
}

- (void) resetView {
    [transition_ transition:6 toView:view_];
}

- (void) alertSheet:(UIActionSheet *)sheet buttonClicked:(int)button {
    NSString *context([sheet context]);

    if ([context isEqualToString:@"error"])
        [sheet dismiss];
    else if ([context isEqualToString:@"conffile"]) {
        FILE *input = [database_ input];

        switch (button) {
            case 1:
                fprintf(input, "N\n");
                fflush(input);
                break;
            case 2:
                fprintf(input, "Y\n");
                fflush(input);
                break;
            default:
                _assert(false);
        }

        [sheet dismiss];
    }
}

- (void) closeButtonPushed {
    running_ = NO;

    switch (Finish_) {
        case 0:
            [self resetView];
        break;

        case 1:
            [delegate_ suspendWithAnimation:YES];
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
    UINavigationItem *item = [navbar_ topItem];
    [item setTitle:CYLocalize("COMPLETE")];

    [overlay_ addSubview:close_];
    [progress_ removeFromSuperview];
    [status_ removeFromSuperview];

    [delegate_ progressViewIsComplete:self];

    if (Finish_ < 4) {
        FileFd file(SandboxTemplate_, FileFd::ReadOnly);
        MMap mmap(file, MMap::ReadOnly);
        SHA1Summation sha1;
        sha1.Add(reinterpret_cast<uint8_t *>(mmap.Data()), mmap.Size());
        if (!(sandplate_ == sha1.Result()))
            Finish_ = 4;
    }

    if (Finish_ < 4) {
        FileFd file(NotifyConfig_, FileFd::ReadOnly);
        MMap mmap(file, MMap::ReadOnly);
        SHA1Summation sha1;
        sha1.Add(reinterpret_cast<uint8_t *>(mmap.Data()), mmap.Size());
        if (!(notifyconf_ == sha1.Result()))
            Finish_ = 4;
    }

    if (Finish_ < 3) {
        FileFd file(SpringBoard_, FileFd::ReadOnly);
        MMap mmap(file, MMap::ReadOnly);
        SHA1Summation sha1;
        sha1.Add(reinterpret_cast<uint8_t *>(mmap.Data()), mmap.Size());
        if (!(springlist_ == sha1.Result()))
            Finish_ = 3;
    }

    switch (Finish_) {
        case 0: [close_ setTitle:CYLocalize("RETURN_TO_CYDIA")]; break;
        case 1: [close_ setTitle:CYLocalize("CLOSE_CYDIA")]; break;
        case 2: [close_ setTitle:CYLocalize("RESTART_SPRINGBOARD")]; break;
        case 3: [close_ setTitle:CYLocalize("RELOAD_SPRINGBOARD")]; break;
        case 4: [close_ setTitle:CYLocalize("REBOOT_DEVICE")]; break;
    }

#define Cache_ "/User/Library/Caches/com.apple.mobile.installation.plist"

    if (NSMutableDictionary *cache = [[NSMutableDictionary alloc] initWithContentsOfFile:@ Cache_]) {
        [cache autorelease];

        NSFileManager *manager = [NSFileManager defaultManager];
        NSError *error = nil;

        id system = [cache objectForKey:@"System"];
        if (system == nil)
            goto error;

        struct stat info;
        if (stat(Cache_, &info) == -1)
            goto error;

        [system removeAllObjects];

        if (NSArray *apps = [manager contentsOfDirectoryAtPath:@"/Applications" error:&error]) {
            for (NSString *app in apps)
                if ([app hasSuffix:@".app"]) {
                    NSString *path = [@"/Applications" stringByAppendingPathComponent:app];
                    NSString *plist = [path stringByAppendingPathComponent:@"Info.plist"];
                    if (NSMutableDictionary *info = [[NSMutableDictionary alloc] initWithContentsOfFile:plist]) {
                        [info autorelease];
                        if ([info objectForKey:@"CFBundleIdentifier"] != nil) {
                            [info setObject:path forKey:@"Path"];
                            [info setObject:@"System" forKey:@"ApplicationType"];
                            [system addInfoDictionary:info];
                        }
                    }
                }
        } else goto error;

        [cache writeToFile:@Cache_ atomically:YES];

        if (chown(Cache_, info.st_uid, info.st_gid) == -1)
            goto error;
        if (chmod(Cache_, info.st_mode) == -1)
            goto error;

        if (false) error:
            lprintf("%s\n", error == nil ? strerror(errno) : [[error localizedDescription] UTF8String]);
    }

    notify_post("com.apple.mobile.application_installed");

    [delegate_ setStatusBarShowsProgress:NO];
}

- (void) _detachNewThreadData:(ProgressData *)data { _pooled
    [[data target] performSelector:[data selector] withObject:[data object]];
    [data release];

    [self performSelectorOnMainThread:@selector(_retachThread) withObject:nil waitUntilDone:YES];
}

- (void) detachNewThreadSelector:(SEL)selector toTarget:(id)target withObject:(id)object title:(NSString *)title {
    UINavigationItem *item = [navbar_ topItem];
    [item setTitle:title];

    [status_ setText:nil];
    [output_ setText:@""];
    [progress_ setProgress:0];

    [close_ removeFromSuperview];
    [overlay_ addSubview:progress_];
    [overlay_ addSubview:status_];

    [delegate_ setStatusBarShowsProgress:YES];
    running_ = YES;

    {
        FileFd file(SandboxTemplate_, FileFd::ReadOnly);
        MMap mmap(file, MMap::ReadOnly);
        SHA1Summation sha1;
        sha1.Add(reinterpret_cast<uint8_t *>(mmap.Data()), mmap.Size());
        sandplate_ = sha1.Result();
    }

    {
        FileFd file(NotifyConfig_, FileFd::ReadOnly);
        MMap mmap(file, MMap::ReadOnly);
        SHA1Summation sha1;
        sha1.Add(reinterpret_cast<uint8_t *>(mmap.Data()), mmap.Size());
        notifyconf_ = sha1.Result();
    }

    {
        FileFd file(SpringBoard_, FileFd::ReadOnly);
        MMap mmap(file, MMap::ReadOnly);
        SHA1Summation sha1;
        sha1.Add(reinterpret_cast<uint8_t *>(mmap.Data()), mmap.Size());
        springlist_ = sha1.Result();
    }

    [transition_ transition:6 toView:overlay_];

    [NSThread
        detachNewThreadSelector:@selector(_detachNewThreadData:)
        toTarget:self
        withObject:[[ProgressData alloc]
            initWithSelector:selector
            target:target
            object:object
        ]
    ];
}

- (void) repairWithSelector:(SEL)selector {
    [self
        detachNewThreadSelector:selector
        toTarget:database_
        withObject:nil
        title:CYLocalize("REPAIRING")
    ];
}

- (void) setConfigurationData:(NSString *)data {
    [self
        performSelectorOnMainThread:@selector(_setConfigurationData:)
        withObject:data
        waitUntilDone:YES
    ];
}

- (void) setProgressError:(NSString *)error forPackage:(NSString *)id {
    Package *package = id == nil ? nil : [database_ packageWithName:id];

    UIActionSheet *sheet = [[[UIActionSheet alloc]
        initWithTitle:(package == nil ? id : [package name])
        buttons:[NSArray arrayWithObjects:CYLocalize("OKAY"), nil]
        defaultButtonIndex:0
        delegate:self
        context:@"error"
    ] autorelease];

    [sheet setBodyText:error];
    [sheet popupAlertAnimated:YES];
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

    _assert(conffile_r(data));

    NSString *ofile = conffile_r[1];
    //NSString *nfile = conffile_r[2];

    UIActionSheet *sheet = [[[UIActionSheet alloc]
        initWithTitle:CYLocalize("CONFIGURATION_UPGRADE")
        buttons:[NSArray arrayWithObjects:
            CYLocalize("KEEP_OLD_COPY"),
            CYLocalize("ACCEPT_NEW_COPY"),
            // XXX: CYLocalize("SEE_WHAT_CHANGED"),
        nil]
        defaultButtonIndex:0
        delegate:self
        context:@"conffile"
    ] autorelease];

    [sheet setBodyText:[NSString stringWithFormat:@"%@\n\n%@", CYLocalize("CONFIGURATION_UPGRADE_EX"), ofile]];
    [sheet popupAlertAnimated:YES];
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

/* Package Cell {{{ */
@interface PackageCell : UITableCell {
    UIImage *icon_;
    NSString *name_;
    NSString *description_;
    bool commercial_;
    NSString *source_;
    UIImage *badge_;
    bool cached_;
    Package *package_;
#ifdef USE_BADGES
    UITextLabel *status_;
#endif
}

- (PackageCell *) init;
- (void) setPackage:(Package *)package;

+ (int) heightForPackage:(Package *)package;

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

    [package_ release];
    package_ = nil;
}

- (void) dealloc {
    [self clearPackage];
#ifdef USE_BADGES
    [status_ release];
#endif
    [super dealloc];
}

- (PackageCell *) init {
    if ((self = [super init]) != nil) {
#ifdef USE_BADGES
        status_ = [[UITextLabel alloc] initWithFrame:CGRectMake(48, 68, 280, 20)];
        [status_ setBackgroundColor:[UIColor clearColor]];
        [status_ setFont:small];
#endif
    } return self;
}

- (void) setPackage:(Package *)package {
    [self clearPackage];
    [package parse];

    Source *source = [package source];

    icon_ = [[package icon] retain];
    name_ = [[package name] retain];
    description_ = [[package shortDescription] retain];
    commercial_ = [package isCommercial];

    package_ = [package retain];

    NSString *label = nil;
    bool trusted = false;

    if (source != nil) {
        label = [source label];
        trusted = [source trusted];
    } else if ([[package id] isEqualToString:@"firmware"])
        label = CYLocalize("APPLE");
    else
        label = [NSString stringWithFormat:CYLocalize("SLASH_DELIMITED"), CYLocalize("UNKNOWN"), CYLocalize("LOCAL")];

    NSString *from(label);

    NSString *section = [package simpleSection];
    if (section != nil && ![section isEqualToString:label]) {
        section = [[NSBundle mainBundle] localizedStringForKey:section value:nil table:@"Sections"];
        from = [NSString stringWithFormat:CYLocalize("PARENTHETICAL"), from, section];
    }

    from = [NSString stringWithFormat:CYLocalize("FROM"), from];
    source_ = [from retain];

    if (NSString *purpose = [package primaryPurpose])
        if ((badge_ = [UIImage imageAtPath:[NSString stringWithFormat:@"%@/Purposes/%@.png", App_, purpose]]) != nil)
            badge_ = [badge_ retain];

#ifdef USE_BADGES
    if (NSString *mode = [package mode]) {
        [badge_ setImage:[UIImage applicationImageNamed:
            [mode isEqualToString:@"REMOVE"] || [mode isEqualToString:@"PURGE"] ? @"removing.png" : @"installing.png"
        ]];

        [status_ setText:[NSString stringWithFormat:CYLocalize("QUEUED_FOR"), CYLocalize(mode)]];
        [status_ setColor:[UIColor colorWithCGColor:Blueish_]];
    } else if ([package half]) {
        [badge_ setImage:[UIImage applicationImageNamed:@"damaged.png"]];
        [status_ setText:CYLocalize("PACKAGE_DAMAGED")];
        [status_ setColor:[UIColor redColor]];
    } else {
        [badge_ setImage:nil];
        [status_ setText:nil];
    }
#endif

    cached_ = false;
}

- (void) drawRect:(CGRect)rect {
    if (!cached_) {
        UIColor *color;

        if (NSString *mode = [package_ mode]) {
            bool remove([mode isEqualToString:@"REMOVE"] || [mode isEqualToString:@"PURGE"]);
            color = remove ? RemovingColor_ : InstallingColor_;
        } else
            color = [UIColor whiteColor];

        [self setBackgroundColor:color];
        cached_ = true;
    }

    [super drawRect:rect];
}

- (void) drawBackgroundInRect:(CGRect)rect withFade:(float)fade {
    if (fade == 0) {
        CGContextRef context(UIGraphicsGetCurrentContext());
        [[self backgroundColor] set];
        CGRect back(rect);
        back.size.height -= 1;
        CGContextFillRect(context, back);
    }

    [super drawBackgroundInRect:rect withFade:fade];
}

- (void) drawContentInRect:(CGRect)rect selected:(BOOL)selected {
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

    if (selected)
        UISetColor(White_);

    if (!selected)
        UISetColor(commercial_ ? Purple_ : Black_);
    [name_ drawAtPoint:CGPointMake(48, 8) forWidth:240 withFont:Font18Bold_ ellipsis:2];
    [source_ drawAtPoint:CGPointMake(58, 29) forWidth:225 withFont:Font12_ ellipsis:2];

    if (!selected)
        UISetColor(commercial_ ? Purplish_ : Gray_);
    [description_ drawAtPoint:CGPointMake(12, 46) forWidth:280 withFont:Font14_ ellipsis:2];

    [super drawContentInRect:rect selected:selected];
}

- (void) setSelected:(BOOL)selected withFade:(BOOL)fade {
    cached_ = false;
    [super setSelected:selected withFade:fade];
}

+ (int) heightForPackage:(Package *)package {
    return 73;
}

@end
/* }}} */
/* Section Cell {{{ */
@interface SectionCell : UISimpleTableCell {
    NSString *section_;
    NSString *name_;
    NSString *count_;
    UIImage *icon_;
    _UISwitchSlider *switch_;
    BOOL editing_;
}

- (id) init;
- (void) setSection:(Section *)section editing:(BOOL)editing;

@end

@implementation SectionCell

- (void) clearSection {
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

- (id) init {
    if ((self = [super init]) != nil) {
        icon_ = [[UIImage applicationImageNamed:@"folder.png"] retain];

        switch_ = [[_UISwitchSlider alloc] initWithFrame:CGRectMake(218, 9, 60, 25)];
        [switch_ addTarget:self action:@selector(onSwitch:) forEvents:kUIControlEventMouseUpInside];
    } return self;
}

- (void) onSwitch:(id)sender {
    NSMutableDictionary *metadata = [Sections_ objectForKey:section_];
    if (metadata == nil) {
        metadata = [NSMutableDictionary dictionaryWithCapacity:2];
        [Sections_ setObject:metadata forKey:section_];
    }

    Changed_ = true;
    [metadata setObject:[NSNumber numberWithBool:([switch_ value] == 0)] forKey:@"Hidden"];
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
        name_ = [CYLocalize("ALL_PACKAGES") retain];
        count_ = nil;
    } else {
        section_ = [section localized];
        if (section_ != nil)
            section_ = [section_ retain];
        name_  = [(section_ == nil ? CYLocalize("NO_SECTION") : section_) retain];
        count_ = [[NSString stringWithFormat:@"%d", [section count]] retain];

        if (editing_)
            [switch_ setValue:(isSectionVisible(section_) ? 1 : 0) animated:NO];
    }
}

- (void) drawContentInRect:(CGRect)rect selected:(BOOL)selected {
    [icon_ drawInRect:CGRectMake(8, 7, 32, 32)];

    if (selected)
        UISetColor(White_);

    if (!selected)
        UISetColor(Black_);
    [name_ drawAtPoint:CGPointMake(48, 9) forWidth:(editing_ ? 164 : 250) withFont:Font22Bold_ ellipsis:2];

    CGSize size = [count_ sizeWithFont:Font14_];

    UISetColor(White_);
    if (count_ != nil)
        [count_ drawAtPoint:CGPointMake(13 + (29 - size.width) / 2, 16) withFont:Font12Bold_];

    [super drawContentInRect:rect selected:selected];
}

@end
/* }}} */

/* File Table {{{ */
@interface FileTable : RVPage {
    _transient Database *database_;
    Package *package_;
    NSString *name_;
    NSMutableArray *files_;
    UITable *list_;
}

- (id) initWithBook:(RVBook *)book database:(Database *)database;
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

- (int) numberOfRowsInTable:(UITable *)table {
    return files_ == nil ? 0 : [files_ count];
}

- (float) table:(UITable *)table heightForRow:(int)row {
    return 24;
}

- (UITableCell *) table:(UITable *)table cellForRow:(int)row column:(UITableColumn *)col reusing:(UITableCell *)reusing {
    if (reusing == nil) {
        reusing = [[[UIImageAndTextTableCell alloc] init] autorelease];
        UIFont *font = [UIFont systemFontOfSize:16];
        [[(UIImageAndTextTableCell *)reusing titleTextLabel] setFont:font];
    }
    [(UIImageAndTextTableCell *)reusing setTitle:[files_ objectAtIndex:row]];
    return reusing;
}

- (BOOL) table:(UITable *)table canSelectRow:(int)row {
    return NO;
}

- (id) initWithBook:(RVBook *)book database:(Database *)database {
    if ((self = [super initWithBook:book]) != nil) {
        database_ = database;

        files_ = [[NSMutableArray arrayWithCapacity:32] retain];

        list_ = [[UITable alloc] initWithFrame:[self bounds]];
        [self addSubview:list_];

        UITableColumn *column = [[[UITableColumn alloc]
            initWithTitle:CYLocalize("NAME")
            identifier:@"name"
            width:[self frame].size.width
        ] autorelease];

        [list_ setDataSource:self];
        [list_ setSeparatorStyle:1];
        [list_ addTableColumn:column];
        [list_ setDelegate:self];
        [list_ setReusesTableCells:YES];
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

- (void) resetViewAnimated:(BOOL)animated {
    [list_ resetViewAnimated:animated];
}

- (void) reloadData {
    [self setPackage:[database_ packageWithName:name_]];
    [self reloadButtons];
}

- (NSString *) title {
    return CYLocalize("INSTALLED_FILES");
}

- (NSString *) backButtonTitle {
    return CYLocalize("FILES");
}

@end
/* }}} */
/* Package View {{{ */
@interface PackageView : BrowserView {
    _transient Database *database_;
    Package *package_;
    NSString *name_;
    bool commercial_;
    NSMutableArray *buttons_;
}

- (id) initWithBook:(RVBook *)book database:(Database *)database;
- (void) setPackage:(Package *)package;

@end

@implementation PackageView

- (void) dealloc {
    if (package_ != nil)
        [package_ release];
    if (name_ != nil)
        [name_ release];
    [buttons_ release];
    [super dealloc];
}

- (void) release {
    if ([self retainCount] == 1)
        [delegate_ setPackageView:self];
    [super release];
}

/* XXX: this is not safe at all... localization of /fail/ */
- (void) _clickButtonWithName:(NSString *)name {
    if ([name isEqualToString:CYLocalize("CLEAR")])
        [delegate_ clearPackage:package_];
    else if ([name isEqualToString:CYLocalize("INSTALL")])
        [delegate_ installPackage:package_];
    else if ([name isEqualToString:CYLocalize("REINSTALL")])
        [delegate_ installPackage:package_];
    else if ([name isEqualToString:CYLocalize("REMOVE")])
        [delegate_ removePackage:package_];
    else if ([name isEqualToString:CYLocalize("UPGRADE")])
        [delegate_ installPackage:package_];
    else _assert(false);
}

- (void) alertSheet:(UIActionSheet *)sheet buttonClicked:(int)button {
    NSString *context([sheet context]);

    if ([context isEqualToString:@"modify"]) {
        int count = [buttons_ count];
        _assert(count != 0);
        _assert(button <= count + 1);

        if (count != button - 1)
            [self _clickButtonWithName:[buttons_ objectAtIndex:(button - 1)]];

        [sheet dismiss];
    } else
        [super alertSheet:sheet buttonClicked:button];
}

- (void) webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame {
    return [super webView:sender didFinishLoadForFrame:frame];
}

- (void) webView:(WebView *)sender didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame {
    [super webView:sender didClearWindowObject:window forFrame:frame];
    [window setValue:package_ forKey:@"package"];
}

- (bool) _allowJavaScriptPanel {
    return commercial_;
}

#if !AlwaysReload
- (void) __rightButtonClicked {
    int count = [buttons_ count];
    _assert(count != 0);

    if (count == 1)
        [self _clickButtonWithName:[buttons_ objectAtIndex:0]];
    else {
        NSMutableArray *buttons = [NSMutableArray arrayWithCapacity:(count + 1)];
        [buttons addObjectsFromArray:buttons_];
        [buttons addObject:CYLocalize("CANCEL")];

        [delegate_ slideUp:[[[UIActionSheet alloc]
            initWithTitle:nil
            buttons:buttons
            defaultButtonIndex:([buttons count] - 1)
            delegate:self
            context:@"modify"
        ] autorelease]];
    }
}

- (void) _rightButtonClicked {
    if (commercial_)
        [super _rightButtonClicked];
    else
        [self __rightButtonClicked];
}
#endif

- (id) _rightButtonTitle {
    int count = [buttons_ count];
    return count == 0 ? nil : count != 1 ? CYLocalize("MODIFY") : [buttons_ objectAtIndex:0];
}

- (NSString *) backButtonTitle {
    return @"Details";
}

- (id) initWithBook:(RVBook *)book database:(Database *)database {
    if ((self = [super initWithBook:book]) != nil) {
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
            [buttons_ addObject:CYLocalize("CLEAR")];
        if ([package_ source] == nil);
        else if ([package_ upgradableAndEssential:NO])
            [buttons_ addObject:CYLocalize("UPGRADE")];
        else if ([package_ installed] == nil)
            [buttons_ addObject:CYLocalize("INSTALL")];
        else
            [buttons_ addObject:CYLocalize("REINSTALL")];
        if ([package_ installed] != nil)
            [buttons_ addObject:CYLocalize("REMOVE")];

        if (special_ != NULL) {
            CGRect frame([webview_ frame]);
            frame.size.width = 320;
            frame.size.height = 0;
            [webview_ setFrame:frame];

            [scroller_ scrollPointVisibleAtTopLeft:CGPointZero];

            WebThreadLock();
            [[[webview_ webView] windowScriptObject] setValue:package_ forKey:@"package"];

            [self setButtonTitle:nil withStyle:nil toFunction:nil];

            [self setFinishHook:nil];
            [self setPopupHook:nil];
            WebThreadUnlock();

            //[self yieldToSelector:@selector(callFunction:) withObject:special_];
            [super callFunction:special_];
        }
    }

    [self reloadButtons];
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
@interface PackageTable : RVPage {
    _transient Database *database_;
    NSString *title_;
    NSMutableArray *packages_;
    NSMutableArray *sections_;
    UISectionList *list_;
}

- (id) initWithBook:(RVBook *)book database:(Database *)database title:(NSString *)title;

- (void) setDelegate:(id)delegate;

- (void) reloadData;
- (void) resetCursor;

- (UISectionList *) list;

- (void) setShouldHideHeaderInShortLists:(BOOL)hide;

@end

@implementation PackageTable

- (void) dealloc {
    [list_ setDataSource:nil];

    [title_ release];
    [packages_ release];
    [sections_ release];
    [list_ release];
    [super dealloc];
}

- (int) numberOfSectionsInSectionList:(UISectionList *)list {
    return [sections_ count];
}

- (NSString *) sectionList:(UISectionList *)list titleForSection:(int)section {
    return [[sections_ objectAtIndex:section] name];
}

- (int) sectionList:(UISectionList *)list rowForSection:(int)section {
    return [[sections_ objectAtIndex:section] row];
}

- (int) numberOfRowsInTable:(UITable *)table {
    return [packages_ count];
}

- (float) table:(UITable *)table heightForRow:(int)row {
    return [PackageCell heightForPackage:[packages_ objectAtIndex:row]];
}

- (UITableCell *) table:(UITable *)table cellForRow:(int)row column:(UITableColumn *)col reusing:(UITableCell *)reusing {
    if (reusing == nil)
        reusing = [[[PackageCell alloc] init] autorelease];
    [(PackageCell *)reusing setPackage:[packages_ objectAtIndex:row]];
    return reusing;
}

- (BOOL) table:(UITable *)table showDisclosureForRow:(int)row {
    return NO;
}

- (void) tableRowSelected:(NSNotification *)notification {
    int row = [[notification object] selectedRow];
    if (row == INT_MAX)
        return;

    Package *package = [packages_ objectAtIndex:row];
    package = [database_ packageWithName:[package id]];
    PackageView *view([delegate_ packageView]);
    [view setPackage:package];
    [view setDelegate:delegate_];
    [book_ pushPage:view];
}

- (id) initWithBook:(RVBook *)book database:(Database *)database title:(NSString *)title {
    if ((self = [super initWithBook:book]) != nil) {
        database_ = database;
        title_ = [title retain];

        packages_ = [[NSMutableArray arrayWithCapacity:16] retain];
        sections_ = [[NSMutableArray arrayWithCapacity:16] retain];

        list_ = [[UISectionList alloc] initWithFrame:[self bounds] showSectionIndex:YES];
        [list_ setDataSource:self];

        UITableColumn *column = [[[UITableColumn alloc]
            initWithTitle:CYLocalize("NAME")
            identifier:@"name"
            width:[self frame].size.width
        ] autorelease];

        UITable *table = [list_ table];
        [table setSeparatorStyle:1];
        [table addTableColumn:column];
        [table setDelegate:self];
        [table setReusesTableCells:YES];

        [self addSubview:list_];

        [self setAutoresizingMask:UIViewAutoresizingFlexibleHeight];
        [list_ setAutoresizingMask:UIViewAutoresizingFlexibleHeight];
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

- (NSString *) title {
    return title_;
}

- (void) resetViewAnimated:(BOOL)animated {
    [list_ resetViewAnimated:animated];
}

- (void) resetCursor {
    [[list_ table] scrollPointVisibleAtTopLeft:CGPointMake(0, 0) animated:NO];
}

- (UISectionList *) list {
    return list_;
}

- (void) setShouldHideHeaderInShortLists:(BOOL)hide {
    [list_ setShouldHideHeaderInShortLists:hide];
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

- (id) initWithBook:(RVBook *)book database:(Database *)database title:(NSString *)title filter:(SEL)filter with:(id)object;

@end

@implementation FilteredPackageTable

- (void) dealloc {
    if (object_ != nil)
        [object_ release];
    [super dealloc];
}

- (void) setObject:(id)object {
    if (object_ != nil)
        [object_ release];
    if (object == nil)
        object_ = nil;
    else
        object_ = [object retain];
}

- (bool) hasPackage:(Package *)package {
    _profile(FilteredPackageTable$hasPackage)
        return [package valid] && (*reinterpret_cast<bool (*)(id, SEL, id)>(imp_))(package, filter_, object_);
    _end
}

- (id) initWithBook:(RVBook *)book database:(Database *)database title:(NSString *)title filter:(SEL)filter with:(id)object {
    if ((self = [super initWithBook:book database:database title:title]) != nil) {
        filter_ = filter;
        object_ = object == nil ? nil : [object retain];

        /* XXX: this is an unsafe optimization of doomy hell */
        Method method = class_getInstanceMethod([Package class], filter);
        _assert(method != NULL);
        imp_ = method_getImplementation(method);
        _assert(imp_ != NULL);

        [self reloadData];
    } return self;
}

@end
/* }}} */

/* Add Source View {{{ */
@interface AddSourceView : RVPage {
    _transient Database *database_;
}

- (id) initWithBook:(RVBook *)book database:(Database *)database;

@end

@implementation AddSourceView

- (id) initWithBook:(RVBook *)book database:(Database *)database {
    if ((self = [super initWithBook:book]) != nil) {
        database_ = database;
    } return self;
}

@end
/* }}} */
/* Source Cell {{{ */
@interface SourceCell : UITableCell {
    UIImage *icon_;
    NSString *origin_;
    NSString *description_;
    NSString *label_;
}

- (void) dealloc;

- (SourceCell *) initWithSource:(Source *)source;

@end

@implementation SourceCell

- (void) dealloc {
    [icon_ release];
    [origin_ release];
    [description_ release];
    [label_ release];
    [super dealloc];
}

- (SourceCell *) initWithSource:(Source *)source {
    if ((self = [super init]) != nil) {
        if (icon_ == nil)
            icon_ = [UIImage applicationImageNamed:[NSString stringWithFormat:@"Sources/%@.png", [source host]]];
        if (icon_ == nil)
            icon_ = [UIImage applicationImageNamed:@"unknown.png"];
        icon_ = [icon_ retain];

        origin_ = [[source name] retain];
        label_ = [[source uri] retain];
        description_ = [[source description] retain];
    } return self;
}

- (void) drawContentInRect:(CGRect)rect selected:(BOOL)selected {
    if (icon_ != nil)
        [icon_ drawInRect:CGRectMake(10, 10, 30, 30)];

    if (selected)
        UISetColor(White_);

    if (!selected)
        UISetColor(Black_);
    [origin_ drawAtPoint:CGPointMake(48, 8) forWidth:240 withFont:Font18Bold_ ellipsis:2];

    if (!selected)
        UISetColor(Blue_);
    [label_ drawAtPoint:CGPointMake(58, 29) forWidth:225 withFont:Font12_ ellipsis:2];

    if (!selected)
        UISetColor(Gray_);
    [description_ drawAtPoint:CGPointMake(12, 46) forWidth:280 withFont:Font14_ ellipsis:2];

    [super drawContentInRect:rect selected:selected];
}

@end
/* }}} */
/* Source Table {{{ */
@interface SourceTable : RVPage {
    _transient Database *database_;
    UISectionList *list_;
    NSMutableArray *sources_;
    UIActionSheet *alert_;
    int offset_;

    NSString *href_;
    UIProgressHUD *hud_;
    NSError *error_;

    //NSURLConnection *installer_;
    NSURLConnection *trivial_bz2_;
    NSURLConnection *trivial_gz_;
    //NSURLConnection *automatic_;

    BOOL trivial_;
}

- (id) initWithBook:(RVBook *)book database:(Database *)database;

@end

@implementation SourceTable

- (void) _deallocConnection:(NSURLConnection *)connection {
    if (connection != nil) {
        [connection cancel];
        //[connection setDelegate:nil];
        [connection release];
    }
}

- (void) dealloc {
    [[list_ table] setDelegate:nil];
    [list_ setDataSource:nil];

    if (href_ != nil)
        [href_ release];
    if (hud_ != nil)
        [hud_ release];
    if (error_ != nil)
        [error_ release];

    //[self _deallocConnection:installer_];
    [self _deallocConnection:trivial_gz_];
    [self _deallocConnection:trivial_bz2_];
    //[self _deallocConnection:automatic_];

    [sources_ release];
    [list_ release];
    [super dealloc];
}

- (int) numberOfSectionsInSectionList:(UISectionList *)list {
    return offset_ == 0 ? 1 : 2;
}

- (NSString *) sectionList:(UISectionList *)list titleForSection:(int)section {
    switch (section + (offset_ == 0 ? 1 : 0)) {
        case 0: return CYLocalize("ENTERED_BY_USER");
        case 1: return CYLocalize("INSTALLED_BY_PACKAGE");

        default:
            _assert(false);
            return nil;
    }
}

- (int) sectionList:(UISectionList *)list rowForSection:(int)section {
    switch (section + (offset_ == 0 ? 1 : 0)) {
        case 0: return 0;
        case 1: return offset_;

        default:
            _assert(false);
            return -1;
    }
}

- (int) numberOfRowsInTable:(UITable *)table {
    return [sources_ count];
}

- (float) table:(UITable *)table heightForRow:(int)row {
    Source *source = [sources_ objectAtIndex:row];
    return [source description] == nil ? 56 : 73;
}

- (UITableCell *) table:(UITable *)table cellForRow:(int)row column:(UITableColumn *)col {
    Source *source = [sources_ objectAtIndex:row];
    // XXX: weird warning, stupid selectors ;P
    return [[[SourceCell alloc] initWithSource:(id)source] autorelease];
}

- (BOOL) table:(UITable *)table showDisclosureForRow:(int)row {
    return YES;
}

- (BOOL) table:(UITable *)table canSelectRow:(int)row {
    return YES;
}

- (void) tableRowSelected:(NSNotification*)notification {
    UITable *table([list_ table]);
    int row([table selectedRow]);
    if (row == INT_MAX)
        return;

    Source *source = [sources_ objectAtIndex:row];

    PackageTable *packages = [[[FilteredPackageTable alloc]
        initWithBook:book_
        database:database_
        title:[source label]
        filter:@selector(isVisibleInSource:)
        with:source
    ] autorelease];

    [packages setDelegate:delegate_];

    [book_ pushPage:packages];
}

- (BOOL) table:(UITable *)table canDeleteRow:(int)row {
    Source *source = [sources_ objectAtIndex:row];
    return [source record] != nil;
}

- (void) table:(UITable *)table willSwipeToDeleteRow:(int)row {
    [[list_ table] setDeleteConfirmationRow:row];
}

- (void) table:(UITable *)table deleteRow:(int)row {
    Source *source = [sources_ objectAtIndex:row];
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
    href = [@"http://cydia.saurik.com/api/repotag/" stringByAppendingString:href];
    href = [href stringByCachingURLWithCurrentCDN];

    NSURL *url([NSURL URLWithString:href]);

    NSStringEncoding encoding;
    NSError *error(nil);

    if (NSString *warning = [NSString stringWithContentsOfURL:url usedEncoding:&encoding error:&error])
        return [warning length] == 0 ? nil : warning;
    return nil;
}

- (void) _endConnection:(NSURLConnection *)connection {
    NSURLConnection **field = NULL;
    if (connection == trivial_bz2_)
        field = &trivial_bz2_;
    else if (connection == trivial_gz_)
        field = &trivial_gz_;
    _assert(field != NULL);
    [connection release];
    *field = nil;

    if (
        trivial_bz2_ == nil &&
        trivial_gz_ == nil
    ) {
        bool defer(false);

        if (trivial_) {
            if (NSString *warning = [self yieldToSelector:@selector(getWarning)]) {
                defer = true;

                UIActionSheet *sheet = [[[UIActionSheet alloc]
                    initWithTitle:CYLocalize("SOURCE_WARNING")
                    buttons:[NSArray arrayWithObjects:CYLocalize("ADD_ANYWAY"), CYLocalize("CANCEL"), nil]
                    defaultButtonIndex:0
                    delegate:self
                    context:@"warning"
                ] autorelease];

                [sheet setNumberOfRows:1];

                [sheet setBodyText:warning];
                [sheet popupAlertAnimated:YES];
            } else
                [self complete];
        } else if (error_ != nil) {
            UIActionSheet *sheet = [[[UIActionSheet alloc]
                initWithTitle:CYLocalize("VERIFICATION_ERROR")
                buttons:[NSArray arrayWithObjects:CYLocalize("OK"), nil]
                defaultButtonIndex:0
                delegate:self
                context:@"urlerror"
            ] autorelease];

            [sheet setBodyText:[error_ localizedDescription]];
            [sheet popupAlertAnimated:YES];
        } else {
            UIActionSheet *sheet = [[[UIActionSheet alloc]
                initWithTitle:CYLocalize("NOT_REPOSITORY")
                buttons:[NSArray arrayWithObjects:CYLocalize("OK"), nil]
                defaultButtonIndex:0
                delegate:self
                context:@"trivial"
            ] autorelease];

            [sheet setBodyText:CYLocalize("NOT_REPOSITORY_EX")];
            [sheet popupAlertAnimated:YES];
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
            trivial_ = YES;
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

- (NSURLConnection *) _requestHRef:(NSString *)href method:(NSString *)method {
    NSMutableURLRequest *request = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:href]
        cachePolicy:NSURLRequestUseProtocolCachePolicy
        timeoutInterval:20.0
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

- (void) alertSheet:(UIActionSheet *)sheet buttonClicked:(int)button {
    NSString *context([sheet context]);

    if ([context isEqualToString:@"source"]) {
        switch (button) {
            case 1: {
                NSString *href = [[sheet textField] text];

                //installer_ = [[self _requestHRef:href method:@"GET"] retain];

                if (![href hasSuffix:@"/"])
                    href_ = [href stringByAppendingString:@"/"];
                else
                    href_ = href;
                href_ = [href_ retain];

                trivial_bz2_ = [[self _requestHRef:[href_ stringByAppendingString:@"Packages.bz2"] method:@"HEAD"] retain];
                trivial_gz_ = [[self _requestHRef:[href_ stringByAppendingString:@"Packages.gz"] method:@"HEAD"] retain];
                //trivial_bz2_ = [[self _requestHRef:[href stringByAppendingString:@"dists/Release"] method:@"HEAD"] retain];

                trivial_ = false;

                hud_ = [[delegate_ addProgressHUD] retain];
                [hud_ setText:CYLocalize("VERIFYING_URL")];
            } break;

            case 2:
            break;

            default:
                _assert(false);
        }

        [sheet dismiss];
    } else if ([context isEqualToString:@"trivial"])
        [sheet dismiss];
    else if ([context isEqualToString:@"urlerror"])
        [sheet dismiss];
    else if ([context isEqualToString:@"warning"]) {
        switch (button) {
            case 1:
                [self complete];
            break;

            case 2:
            break;

            default:
                _assert(false);
        }

        [href_ release];
        href_ = nil;

        [sheet dismiss];
    }
}

- (id) initWithBook:(RVBook *)book database:(Database *)database {
    if ((self = [super initWithBook:book]) != nil) {
        database_ = database;
        sources_ = [[NSMutableArray arrayWithCapacity:16] retain];

        //list_ = [[UITable alloc] initWithFrame:[self bounds]];
        list_ = [[UISectionList alloc] initWithFrame:[self bounds] showSectionIndex:NO];
        [list_ setShouldHideHeaderInShortLists:NO];

        [self addSubview:list_];
        [list_ setDataSource:self];

        UITableColumn *column = [[UITableColumn alloc]
            initWithTitle:CYLocalize("NAME")
            identifier:@"name"
            width:[self frame].size.width
        ];

        UITable *table = [list_ table];
        [table setSeparatorStyle:1];
        [table addTableColumn:column];
        [table setDelegate:self];

        [self reloadData];

        [self setAutoresizingMask:UIViewAutoresizingFlexibleHeight];
        [list_ setAutoresizingMask:UIViewAutoresizingFlexibleHeight];
    } return self;
}

- (void) reloadData {
    pkgSourceList list;
    _assert(list.ReadMainList());

    [sources_ removeAllObjects];
    [sources_ addObjectsFromArray:[database_ sources]];
    _trace();
    [sources_ sortUsingSelector:@selector(compareByNameAndType:)];
    _trace();

    int count = [sources_ count];
    for (offset_ = 0; offset_ != count; ++offset_) {
        Source *source = [sources_ objectAtIndex:offset_];
        if ([source record] == nil)
            break;
    }

    [list_ reloadData];
}

- (void) resetViewAnimated:(BOOL)animated {
    [list_ resetViewAnimated:animated];
}

- (void) _leftButtonClicked {
    /*[book_ pushPage:[[[AddSourceView alloc]
        initWithBook:book_
        database:database_
    ] autorelease]];*/

    UIActionSheet *sheet = [[[UIActionSheet alloc]
        initWithTitle:CYLocalize("ENTER_APT_URL")
        buttons:[NSArray arrayWithObjects:CYLocalize("ADD_SOURCE"), CYLocalize("CANCEL"), nil]
        defaultButtonIndex:0
        delegate:self
        context:@"source"
    ] autorelease];

    [sheet setNumberOfRows:1];

    [sheet addTextFieldWithValue:@"http://" label:@""];

    UITextInputTraits *traits = [[sheet textField] textInputTraits];
    [traits setAutocapitalizationType:UITextAutocapitalizationTypeNone];
    [traits setAutocorrectionType:UITextAutocorrectionTypeNo];
    [traits setKeyboardType:UIKeyboardTypeURL];
    // XXX: UIReturnKeyDone
    [traits setReturnKeyType:UIReturnKeyNext];

    [sheet popupAlertAnimated:YES];
}

- (void) _rightButtonClicked {
    UITable *table = [list_ table];
    BOOL editing = [table isRowDeletionEnabled];
    [table enableRowDeletion:!editing animated:YES];
    [book_ reloadButtonsForPage:self];
}

- (NSString *) title {
    return CYLocalize("SOURCES");
}

- (NSString *) leftButtonTitle {
    return [[list_ table] isRowDeletionEnabled] ? CYLocalize("ADD") : nil;
}

- (id) rightButtonTitle {
    return [[list_ table] isRowDeletionEnabled] ? CYLocalize("DONE") : CYLocalize("EDIT");
}

- (UINavigationButtonStyle) rightButtonStyle {
    return [[list_ table] isRowDeletionEnabled] ? UINavigationButtonStyleHighlighted : UINavigationButtonStyleNormal;
}

@end
/* }}} */

/* Installed View {{{ */
@interface InstalledView : RVPage {
    _transient Database *database_;
    FilteredPackageTable *packages_;
    BOOL expert_;
}

- (id) initWithBook:(RVBook *)book database:(Database *)database;

@end

@implementation InstalledView

- (void) dealloc {
    [packages_ release];
    [super dealloc];
}

- (id) initWithBook:(RVBook *)book database:(Database *)database {
    if ((self = [super initWithBook:book]) != nil) {
        database_ = database;

        packages_ = [[FilteredPackageTable alloc]
            initWithBook:book
            database:database
            title:nil
            filter:@selector(isInstalledAndVisible:)
            with:[NSNumber numberWithBool:YES]
        ];

        [self addSubview:packages_];

        [self setAutoresizingMask:UIViewAutoresizingFlexibleHeight];
        [packages_ setAutoresizingMask:UIViewAutoresizingFlexibleHeight];
    } return self;
}

- (void) resetViewAnimated:(BOOL)animated {
    [packages_ resetViewAnimated:animated];
}

- (void) reloadData {
    [packages_ reloadData];
}

- (void) _rightButtonClicked {
    [packages_ setObject:[NSNumber numberWithBool:expert_]];
    [packages_ reloadData];
    expert_ = !expert_;
    [book_ reloadButtonsForPage:self];
}

- (NSString *) title {
    return CYLocalize("INSTALLED");
}

- (NSString *) backButtonTitle {
    return CYLocalize("PACKAGES");
}

- (id) rightButtonTitle {
    return Role_ != nil && [Role_ isEqualToString:@"Developer"] ? nil : expert_ ? CYLocalize("EXPERT") : CYLocalize("SIMPLE");
}

- (UINavigationButtonStyle) rightButtonStyle {
    return expert_ ? UINavigationButtonStyleHighlighted : UINavigationButtonStyleNormal;
}

- (void) setDelegate:(id)delegate {
    [super setDelegate:delegate];
    [packages_ setDelegate:delegate];
}

@end
/* }}} */

/* Home View {{{ */
@interface HomeView : BrowserView {
}

@end

@implementation HomeView

- (void) alertSheet:(UIActionSheet *)sheet buttonClicked:(int)button {
    NSString *context([sheet context]);

    if ([context isEqualToString:@"about"])
        [sheet dismiss];
    else
        [super alertSheet:sheet buttonClicked:button];
}

- (void) _leftButtonClicked {
    UIActionSheet *sheet = [[[UIActionSheet alloc]
        initWithTitle:CYLocalize("ABOUT_CYDIA")
        buttons:[NSArray arrayWithObjects:CYLocalize("CLOSE"), nil]
        defaultButtonIndex:0
        delegate:self
        context:@"about"
    ] autorelease];

    [sheet setBodyText:
        @"Copyright (C) 2008-2009\n"
        "Jay Freeman (saurik)\n"
        "saurik@saurik.com\n"
        "http://www.saurik.com/\n"
        "\n"
        "The Okori Group\n"
        "http://www.theokorigroup.com/\n"
        "\n"
        "College of Creative Studies,\n"
        "University of California,\n"
        "Santa Barbara\n"
        "http://www.ccs.ucsb.edu/"
    ];

    [sheet popupAlertAnimated:YES];
}

- (NSString *) leftButtonTitle {
    return CYLocalize("ABOUT");
}

@end
/* }}} */
/* Manage View {{{ */
@interface ManageView : BrowserView {
}

@end

@implementation ManageView

- (NSString *) title {
    return CYLocalize("MANAGE");
}

- (void) _leftButtonClicked {
    [delegate_ askForSettings];
}

- (NSString *) leftButtonTitle {
    return CYLocalize("SETTINGS");
}

#if !AlwaysReload
- (id) _rightButtonTitle {
    return Queuing_ ? CYLocalize("QUEUE") : nil;
}

- (UINavigationButtonStyle) rightButtonStyle {
    return Queuing_ ? UINavigationButtonStyleHighlighted : UINavigationButtonStyleNormal;
}

- (void) _rightButtonClicked {
    [delegate_ queue];
}
#endif

- (bool) isLoading {
    return false;
}

@end
/* }}} */

#include <BrowserView.m>

/* Cydia Book {{{ */
@interface CYBook : RVBook <
    ProgressDelegate
> {
    _transient Database *database_;
    UINavigationBar *overlay_;
    UINavigationBar *underlay_;
    UIProgressIndicator *indicator_;
    UITextLabel *prompt_;
    UIProgressBar *progress_;
    UINavigationButton *cancel_;
    bool updating_;
}

- (id) initWithFrame:(CGRect)frame database:(Database *)database;
- (void) update;
- (BOOL) updating;

@end

@implementation CYBook

- (void) dealloc {
    [overlay_ release];
    [indicator_ release];
    [prompt_ release];
    [progress_ release];
    [cancel_ release];
    [super dealloc];
}

- (NSString *) getTitleForPage:(RVPage *)page {
    return [super getTitleForPage:page];
}

- (BOOL) updating {
    return updating_;
}

- (void) update {
    [UIView beginAnimations:nil context:NULL];

    CGRect ovrframe = [overlay_ frame];
    ovrframe.origin.y = 0;
    [overlay_ setFrame:ovrframe];

    CGRect barframe = [navbar_ frame];
    barframe.origin.y += ovrframe.size.height;
    [navbar_ setFrame:barframe];

    CGRect trnframe = [transition_ frame];
    trnframe.origin.y += ovrframe.size.height;
    trnframe.size.height -= ovrframe.size.height;
    [transition_ setFrame:trnframe];

    [UIView endAnimations];

    [indicator_ startAnimation];
    [prompt_ setText:CYLocalize("UPDATING_DATABASE")];
    [progress_ setProgress:0];

    updating_ = true;
    [overlay_ addSubview:cancel_];

    [NSThread
        detachNewThreadSelector:@selector(_update)
        toTarget:self
        withObject:nil
    ];
}

- (void) _update_ {
    updating_ = false;

    [indicator_ stopAnimation];

    [UIView beginAnimations:nil context:NULL];

    CGRect ovrframe = [overlay_ frame];
    ovrframe.origin.y = -ovrframe.size.height;
    [overlay_ setFrame:ovrframe];

    CGRect barframe = [navbar_ frame];
    barframe.origin.y -= ovrframe.size.height;
    [navbar_ setFrame:barframe];

    CGRect trnframe = [transition_ frame];
    trnframe.origin.y -= ovrframe.size.height;
    trnframe.size.height += ovrframe.size.height;
    [transition_ setFrame:trnframe];

    [UIView commitAnimations];

    [delegate_ performSelector:@selector(reloadData) withObject:nil afterDelay:0];
}

- (id) initWithFrame:(CGRect)frame database:(Database *)database {
    if ((self = [super initWithFrame:frame]) != nil) {
        database_ = database;

        CGRect ovrrect = [navbar_ bounds];
        ovrrect.size.height = [UINavigationBar defaultSize].height;
        ovrrect.origin.y = -ovrrect.size.height;

        overlay_ = [[UINavigationBar alloc] initWithFrame:ovrrect];
        [self addSubview:overlay_];

        ovrrect.origin.y = frame.size.height;
        underlay_ = [[UINavigationBar alloc] initWithFrame:ovrrect];
        [underlay_ setTintColor:[UIColor colorWithRed:0.23 green:0.23 blue:0.23 alpha:1]];
        [self addSubview:underlay_];

        [overlay_ setBarStyle:1];
        [underlay_ setBarStyle:1];

        int barstyle = [overlay_ _barStyle:NO];
        bool ugly = barstyle == 0;

        UIProgressIndicatorStyle style = ugly ?
            UIProgressIndicatorStyleMediumBrown :
            UIProgressIndicatorStyleMediumWhite;

        CGSize indsize = [UIProgressIndicator defaultSizeForStyle:style];
        unsigned indoffset = (ovrrect.size.height - indsize.height) / 2;
        CGRect indrect = {{indoffset, indoffset}, indsize};

        indicator_ = [[UIProgressIndicator alloc] initWithFrame:indrect];
        [indicator_ setStyle:style];
        [overlay_ addSubview:indicator_];

        CGSize prmsize = {215, indsize.height + 4};

        CGRect prmrect = {{
            indoffset * 2 + indsize.width,
#ifdef __OBJC2__
            -1 +
#endif
            unsigned(ovrrect.size.height - prmsize.height) / 2
        }, prmsize};

        UIFont *font = [UIFont systemFontOfSize:15];

        prompt_ = [[UITextLabel alloc] initWithFrame:prmrect];

        [prompt_ setColor:[UIColor colorWithCGColor:(ugly ? Blueish_ : Off_)]];
        [prompt_ setBackgroundColor:[UIColor clearColor]];
        [prompt_ setFont:font];

        [overlay_ addSubview:prompt_];

        CGSize prgsize = {75, 100};

        CGRect prgrect = {{
            ovrrect.size.width - prgsize.width - 10,
            (ovrrect.size.height - prgsize.height) / 2
        } , prgsize};

        progress_ = [[UIProgressBar alloc] initWithFrame:prgrect];
        [progress_ setStyle:0];
        [overlay_ addSubview:progress_];

        cancel_ = [[UINavigationButton alloc] initWithTitle:CYLocalize("CANCEL") style:UINavigationButtonStyleHighlighted];
        [cancel_ addTarget:self action:@selector(_onCancel) forControlEvents:UIControlEventTouchUpInside];

        CGRect frame = [cancel_ frame];
        frame.origin.x = ovrrect.size.width - frame.size.width - 5;
        frame.origin.y = (ovrrect.size.height - frame.size.height) / 2;
        [cancel_ setFrame:frame];

        [cancel_ setBarStyle:barstyle];
    } return self;
}

- (void) _onCancel {
    updating_ = false;
    [cancel_ removeFromSuperview];
}

- (void) _update { _pooled
    Status status;
    status.setDelegate(self);

    [database_ updateWithStatus:status];

    [self
        performSelectorOnMainThread:@selector(_update_)
        withObject:nil
        waitUntilDone:NO
    ];
}

- (void) setProgressError:(NSString *)error forPackage:(NSString *)id {
    [prompt_ setText:[NSString stringWithFormat:CYLocalize("COLON_DELIMITED"), CYLocalize("ERROR"), error]];
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
    return !updating_;
}

- (void) alertSheet:(UIActionSheet *)sheet buttonClicked:(int)button {
    [sheet dismiss];
}

- (void) _setProgressTitle:(NSString *)title {
    [prompt_ setText:title];
}

- (void) _setProgressPercent:(NSNumber *)percent {
    [progress_ setProgress:[percent floatValue]];
}

- (void) _addProgressOutput:(NSString *)output {
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

/* Sections View {{{ */
@interface SectionsView : RVPage {
    _transient Database *database_;
    NSMutableArray *sections_;
    NSMutableArray *filtered_;
    UITransitionView *transition_;
    UITable *list_;
    UIView *accessory_;
    BOOL editing_;
}

- (id) initWithBook:(RVBook *)book database:(Database *)database;
- (void) reloadData;
- (void) resetView;

@end

@implementation SectionsView

- (void) dealloc {
    [list_ setDataSource:nil];
    [list_ setDelegate:nil];

    [sections_ release];
    [filtered_ release];
    [transition_ release];
    [list_ release];
    [accessory_ release];
    [super dealloc];
}

- (int) numberOfRowsInTable:(UITable *)table {
    return editing_ ? [sections_ count] : [filtered_ count] + 1;
}

- (float) table:(UITable *)table heightForRow:(int)row {
    return 45;
}

- (UITableCell *) table:(UITable *)table cellForRow:(int)row column:(UITableColumn *)col reusing:(UITableCell *)reusing {
    if (reusing == nil)
        reusing = [[[SectionCell alloc] init] autorelease];
    [(SectionCell *)reusing setSection:(editing_ ?
        [sections_ objectAtIndex:row] :
        (row == 0 ? nil : [filtered_ objectAtIndex:(row - 1)])
    ) editing:editing_];
    return reusing;
}

- (BOOL) table:(UITable *)table showDisclosureForRow:(int)row {
    return !editing_;
}

- (BOOL) table:(UITable *)table canSelectRow:(int)row {
    return !editing_;
}

- (void) tableRowSelected:(NSNotification *)notification {
    int row = [[notification object] selectedRow];
    if (row == INT_MAX)
        return;

    Section *section;
    NSString *name;
    NSString *title;

    if (row == 0) {
        section = nil;
        name = nil;
        title = CYLocalize("ALL_PACKAGES");
    } else {
        section = [filtered_ objectAtIndex:(row - 1)];
        name = [section name];

        if (name != nil)
            title = [[NSBundle mainBundle] localizedStringForKey:Simplify(name) value:nil table:@"Sections"];
        else {
            name = @"";
            title = CYLocalize("NO_SECTION");
        }
    }

    PackageTable *table = [[[FilteredPackageTable alloc]
        initWithBook:book_
        database:database_
        title:title
        filter:@selector(isVisiblyUninstalledInSection:)
        with:name
    ] autorelease];

    [table setDelegate:delegate_];

    [book_ pushPage:table];
}

- (id) initWithBook:(RVBook *)book database:(Database *)database {
    if ((self = [super initWithBook:book]) != nil) {
        database_ = database;

        sections_ = [[NSMutableArray arrayWithCapacity:16] retain];
        filtered_ = [[NSMutableArray arrayWithCapacity:16] retain];

        transition_ = [[UITransitionView alloc] initWithFrame:[self bounds]];
        [self addSubview:transition_];

        list_ = [[UITable alloc] initWithFrame:[transition_ bounds]];
        [transition_ transition:0 toView:list_];

        UITableColumn *column = [[[UITableColumn alloc]
            initWithTitle:CYLocalize("NAME")
            identifier:@"name"
            width:[self frame].size.width
        ] autorelease];

        [list_ setDataSource:self];
        [list_ setSeparatorStyle:1];
        [list_ addTableColumn:column];
        [list_ setDelegate:self];
        [list_ setReusesTableCells:YES];

        [self reloadData];

        [self setAutoresizingMask:UIViewAutoresizingFlexibleHeight];
        [list_ setAutoresizingMask:UIViewAutoresizingFlexibleHeight];
    } return self;
}

- (void) reloadData {
    NSArray *packages = [database_ packages];

    [sections_ removeAllObjects];
    [filtered_ removeAllObjects];

#if 0
    typedef __gnu_cxx::hash_map<NSString *, Section *, NSStringMapHash, NSStringMapEqual> SectionMap;
    SectionMap sections;
    sections.resize(64);
#else
    NSMutableDictionary *sections([NSMutableDictionary dictionaryWithCapacity:32]);
#endif

    _trace();
    for (Package *package in packages) {
        NSString *name([package section]);
        NSString *key(name == nil ? @"" : name);

#if 0
        Section **section;

        _profile(SectionsView$reloadData$Section)
            section = &sections[key];
            if (*section == nil) {
                _profile(SectionsView$reloadData$Section$Allocate)
                    *section = [[[Section alloc] initWithName:name localize:YES] autorelease];
                _end
            }
        _end

        [*section addToCount];

        _profile(SectionsView$reloadData$Filter)
            if (![package valid] || [package installed] != nil || ![package visible])
                continue;
        _end

        [*section addToRow];
#else
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
            if (![package valid] || [package installed] != nil || ![package visible])
                continue;
        _end

        [section addToRow];
#endif
    }
    _trace();

#if 0
    for (SectionMap::const_iterator i(sections.begin()), e(sections.end()); i != e; ++i)
        [sections_ addObject:i->second];
#else
    [sections_ addObjectsFromArray:[sections allValues]];
#endif

    [sections_ sortUsingSelector:@selector(compareByLocalized:)];

    for (Section *section in sections_) {
        size_t count([section row]);
        if (count == 0)
            continue;

        section = [[[Section alloc] initWithName:[section name] localized:[section localized]] autorelease];
        [section setCount:count];
        [filtered_ addObject:section];
    }

    [list_ reloadData];
    _trace();
}

- (void) resetView {
    if (editing_)
        [self _rightButtonClicked];
}

- (void) resetViewAnimated:(BOOL)animated {
    [list_ resetViewAnimated:animated];
}

- (void) _rightButtonClicked {
    if ((editing_ = !editing_))
        [list_ reloadData];
    else
        [delegate_ updateData];
    [book_ reloadTitleForPage:self];
    [book_ reloadButtonsForPage:self];
}

- (NSString *) title {
    return editing_ ? CYLocalize("SECTION_VISIBILITY") : CYLocalize("INSTALL_BY_SECTION");
}

- (NSString *) backButtonTitle {
    return CYLocalize("SECTIONS");
}

- (id) rightButtonTitle {
    return [sections_ count] == 0 ? nil : editing_ ? CYLocalize("DONE") : CYLocalize("EDIT");
}

- (UINavigationButtonStyle) rightButtonStyle {
    return editing_ ? UINavigationButtonStyleHighlighted : UINavigationButtonStyleNormal;
}

- (UIView *) accessoryView {
    return accessory_;
}

@end
/* }}} */
/* Changes View {{{ */
@interface ChangesView : RVPage {
    _transient Database *database_;
    NSMutableArray *packages_;
    NSMutableArray *sections_;
    UISectionList *list_;
    unsigned upgrades_;
}

- (id) initWithBook:(RVBook *)book database:(Database *)database;
- (void) reloadData;

@end

@implementation ChangesView

- (void) dealloc {
    [[list_ table] setDelegate:nil];
    [list_ setDataSource:nil];

    [packages_ release];
    [sections_ release];
    [list_ release];
    [super dealloc];
}

- (int) numberOfSectionsInSectionList:(UISectionList *)list {
    return [sections_ count];
}

- (NSString *) sectionList:(UISectionList *)list titleForSection:(int)section {
    return [[sections_ objectAtIndex:section] name];
}

- (int) sectionList:(UISectionList *)list rowForSection:(int)section {
    return [[sections_ objectAtIndex:section] row];
}

- (int) numberOfRowsInTable:(UITable *)table {
    return [packages_ count];
}

- (float) table:(UITable *)table heightForRow:(int)row {
    return [PackageCell heightForPackage:[packages_ objectAtIndex:row]];
}

- (UITableCell *) table:(UITable *)table cellForRow:(int)row column:(UITableColumn *)col reusing:(UITableCell *)reusing {
    if (reusing == nil)
        reusing = [[[PackageCell alloc] init] autorelease];
    [(PackageCell *)reusing setPackage:[packages_ objectAtIndex:row]];
    return reusing;
}

- (BOOL) table:(UITable *)table showDisclosureForRow:(int)row {
    return NO;
}

- (void) tableRowSelected:(NSNotification *)notification {
    int row = [[notification object] selectedRow];
    if (row == INT_MAX)
        return;
    Package *package = [packages_ objectAtIndex:row];
    PackageView *view([delegate_ packageView]);
    [view setDelegate:delegate_];
    [view setPackage:package];
    [book_ pushPage:view];
}

- (void) _leftButtonClicked {
    [(CYBook *)book_ update];
    [self reloadButtons];
}

- (void) _rightButtonClicked {
    [delegate_ distUpgrade];
}

- (id) initWithBook:(RVBook *)book database:(Database *)database {
    if ((self = [super initWithBook:book]) != nil) {
        database_ = database;

        packages_ = [[NSMutableArray arrayWithCapacity:16] retain];
        sections_ = [[NSMutableArray arrayWithCapacity:16] retain];

        list_ = [[UISectionList alloc] initWithFrame:[self bounds] showSectionIndex:NO];
        [self addSubview:list_];

        [list_ setShouldHideHeaderInShortLists:NO];
        [list_ setDataSource:self];
        //[list_ setSectionListStyle:1];

        UITableColumn *column = [[[UITableColumn alloc]
            initWithTitle:CYLocalize("NAME")
            identifier:@"name"
            width:[self frame].size.width
        ] autorelease];

        UITable *table = [list_ table];
        [table setSeparatorStyle:1];
        [table addTableColumn:column];
        [table setDelegate:self];
        [table setReusesTableCells:YES];

        [self reloadData];

        [self setAutoresizingMask:UIViewAutoresizingFlexibleHeight];
        [list_ setAutoresizingMask:UIViewAutoresizingFlexibleHeight];
    } return self;
}

- (void) reloadData {
    NSArray *packages = [database_ packages];

    [packages_ removeAllObjects];
    [sections_ removeAllObjects];

    _trace();
    for (Package *package in packages)
        if (
            [package installed] == nil && [package valid] && [package visible] ||
            [package upgradableAndEssential:YES]
        )
            [packages_ addObject:package];

    _trace();
    [packages_ radixSortUsingFunction:reinterpret_cast<SKRadixFunction>(&PackageChangesRadix) withContext:NULL];
    _trace();

    Section *upgradable = [[[Section alloc] initWithName:CYLocalize("AVAILABLE_UPGRADES") localize:NO] autorelease];
    Section *ignored = [[[Section alloc] initWithName:CYLocalize("IGNORED_UPGRADES") localize:NO] autorelease];
    Section *section = nil;
    NSDate *last = nil;

    upgrades_ = 0;
    bool unseens = false;

    CFDateFormatterRef formatter(CFDateFormatterCreate(NULL, Locale_, kCFDateFormatterMediumStyle, kCFDateFormatterMediumStyle));

    for (size_t offset = 0, count = [packages_ count]; offset != count; ++offset) {
        Package *package = [packages_ objectAtIndex:offset];

        BOOL uae = [package upgradableAndEssential:YES];

        if (!uae) {
            unseens = true;
            NSDate *seen;

            _profile(ChangesView$reloadData$Remember)
                seen = [package seen];
            _end

            if (section == nil || last != seen && (seen == nil || [seen compare:last] != NSOrderedSame)) {
                last = seen;

                NSString *name;
                if (seen == nil)
                    name = CYLocalize("UNKNOWN");
                else {
                    name = (NSString *) CFDateFormatterCreateStringWithDate(NULL, formatter, (CFDateRef) seen);
                    [name autorelease];
                }

                _profile(ChangesView$reloadData$Allocate)
                    name = [NSString stringWithFormat:CYLocalize("NEW_AT"), name];
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
        [packages_ removeObjectsInRange:NSMakeRange([packages_ count] - count, count)];
        [sections_ removeLastObject];
    }

    if ([ignored count] != 0)
        [sections_ insertObject:ignored atIndex:0];
    if (upgrades_ != 0)
        [sections_ insertObject:upgradable atIndex:0];

    [list_ reloadData];
    [self reloadButtons];
}

- (void) resetViewAnimated:(BOOL)animated {
    [list_ resetViewAnimated:animated];
}

- (NSString *) leftButtonTitle {
    return [(CYBook *)book_ updating] ? nil : CYLocalize("REFRESH");
}

- (id) rightButtonTitle {
    return upgrades_ == 0 ? nil : [NSString stringWithFormat:CYLocalize("PARENTHETICAL"), CYLocalize("UPGRADE"), [NSString stringWithFormat:@"%u", upgrades_]];
}

- (NSString *) title {
    return CYLocalize("CHANGES");
}

@end
/* }}} */
/* Search View {{{ */
@protocol SearchViewDelegate
- (void) showKeyboard:(BOOL)show;
@end

@interface SearchView : RVPage {
    UIView *accessory_;
    UISearchField *field_;
    UITransitionView *transition_;
    FilteredPackageTable *table_;
    UIPreferencesTable *advanced_;
    UIView *dimmed_;
    bool flipped_;
    bool reload_;
}

- (id) initWithBook:(RVBook *)book database:(Database *)database;
- (void) reloadData;

@end

@implementation SearchView

- (void) dealloc {
    [field_ setDelegate:nil];

    [accessory_ release];
    [field_ release];
    [transition_ release];
    [table_ release];
    [advanced_ release];
    [dimmed_ release];
    [super dealloc];
}

- (int) numberOfGroupsInPreferencesTable:(UIPreferencesTable *)table {
    return 1;
}

- (NSString *) preferencesTable:(UIPreferencesTable *)table titleForGroup:(int)group {
    switch (group) {
        case 0: return [NSString stringWithFormat:CYLocalize("PARENTHETICAL"), CYLocalize("ADVANCED_SEARCH"), CYLocalize("COMING_SOON")];

        default: _assert(false);
    }
}

- (int) preferencesTable:(UIPreferencesTable *)table numberOfRowsInGroup:(int)group {
    switch (group) {
        case 0: return 0;

        default: _assert(false);
    }
}

- (void) _showKeyboard:(BOOL)show {
    CGSize keysize = [UIKeyboard defaultSize];
    CGRect keydown = [book_ pageBounds];
    CGRect keyup = keydown;
    keyup.size.height -= keysize.height - ButtonBarHeight_;

    float delay = KeyboardTime_ * ButtonBarHeight_ / keysize.height;

    UIFrameAnimation *animation = [[[UIFrameAnimation alloc] initWithTarget:[table_ list]] autorelease];
    [animation setSignificantRectFields:8];

    if (show) {
        [animation setStartFrame:keydown];
        [animation setEndFrame:keyup];
    } else {
        [animation setStartFrame:keyup];
        [animation setEndFrame:keydown];
    }

    UIAnimator *animator = [UIAnimator sharedAnimator];

    [animator
        addAnimations:[NSArray arrayWithObjects:animation, nil]
        withDuration:(KeyboardTime_ - delay)
        start:!show
    ];

    if (show)
        [animator performSelector:@selector(startAnimation:) withObject:animation afterDelay:delay];

    [delegate_ showKeyboard:show];
}

- (void) textFieldDidBecomeFirstResponder:(UITextField *)field {
    [self _showKeyboard:YES];
}

- (void) textFieldDidResignFirstResponder:(UITextField *)field {
    [self _showKeyboard:NO];
}

- (void) keyboardInputChanged:(UIFieldEditor *)editor {
    if (reload_) {
        NSString *text([field_ text]);
        [field_ setClearButtonStyle:(text == nil || [text length] == 0 ? 0 : 2)];
        [self reloadData];
        reload_ = false;
    }
}

- (void) textFieldClearButtonPressed:(UITextField *)field {
    reload_ = true;
}

- (void) keyboardInputShouldDelete:(id)input {
    reload_ = true;
}

- (BOOL) keyboardInput:(id)input shouldInsertText:(NSString *)text isMarkedText:(int)marked {
    if ([text length] != 1 || [text characterAtIndex:0] != '\n') {
        reload_ = true;
        return YES;
    } else {
        [field_ resignFirstResponder];
        return NO;
    }
}

- (id) initWithBook:(RVBook *)book database:(Database *)database {
    if ((self = [super initWithBook:book]) != nil) {
        CGRect pageBounds = [book_ pageBounds];

        transition_ = [[UITransitionView alloc] initWithFrame:pageBounds];
        [self addSubview:transition_];

        advanced_ = [[UIPreferencesTable alloc] initWithFrame:pageBounds];

        [advanced_ setReusesTableCells:YES];
        [advanced_ setDataSource:self];
        [advanced_ reloadData];

        dimmed_ = [[UIView alloc] initWithFrame:pageBounds];
        CGColor dimmed(space_, 0, 0, 0, 0.5);
        [dimmed_ setBackgroundColor:[UIColor colorWithCGColor:dimmed]];

        table_ = [[FilteredPackageTable alloc]
            initWithBook:book
            database:database
            title:nil
            filter:@selector(isUnfilteredAndSearchedForBy:)
            with:nil
        ];

        [table_ setShouldHideHeaderInShortLists:NO];
        [transition_ transition:0 toView:table_];

        CGRect cnfrect = {{
#ifdef __OBJC2__
        6 +
#endif
        1, 38}, {17, 18}};

        CGRect area;
        area.origin.x = /*cnfrect.origin.x + cnfrect.size.width + 4 +*/ 10;
        area.origin.y = 1;

        area.size.width =
#ifdef __OBJC2__
            8 +
#endif
            [self bounds].size.width - area.origin.x - 18;

        area.size.height = [UISearchField defaultHeight];

        field_ = [[UISearchField alloc] initWithFrame:area];

        UIFont *font = [UIFont systemFontOfSize:16];
        [field_ setFont:font];

        [field_ setPlaceholder:CYLocalize("SEARCH_EX")];
        [field_ setDelegate:self];

        [field_ setPaddingTop:5];

        UITextInputTraits *traits([field_ textInputTraits]);
        [traits setAutocapitalizationType:UITextAutocapitalizationTypeNone];
        [traits setAutocorrectionType:UITextAutocorrectionTypeNo];
        [traits setReturnKeyType:UIReturnKeySearch];

        CGRect accrect = {{0, 6}, {6 + cnfrect.size.width + 6 + area.size.width + 6, area.size.height}};

        accessory_ = [[UIView alloc] initWithFrame:accrect];
        [accessory_ addSubview:field_];

        /*UIPushButton *configure = [[[UIPushButton alloc] initWithFrame:cnfrect] autorelease];
        [configure setShowPressFeedback:YES];
        [configure setImage:[UIImage applicationImageNamed:@"advanced.png"]];
        [configure addTarget:self action:@selector(configurePushed) forEvents:1];
        [accessory_ addSubview:configure];*/

        [self setAutoresizingMask:UIViewAutoresizingFlexibleHeight];
        [table_ setAutoresizingMask:UIViewAutoresizingFlexibleHeight];
    } return self;
}

- (void) flipPage {
#ifndef __OBJC2__
    LKAnimation *animation = [LKTransition animation];
    [animation setType:@"oglFlip"];
    [animation setTimingFunction:[LKTimingFunction functionWithName:@"easeInEaseOut"]];
    [animation setFillMode:@"extended"];
    [animation setTransitionFlags:3];
    [animation setDuration:10];
    [animation setSpeed:0.35];
    [animation setSubtype:(flipped_ ? @"fromLeft" : @"fromRight")];
    [[transition_ _layer] addAnimation:animation forKey:0];
    [transition_ transition:0 toView:(flipped_ ? (UIView *) table_ : (UIView *) advanced_)];
    flipped_ = !flipped_;
#endif
}

- (void) configurePushed {
    [field_ resignFirstResponder];
    [self flipPage];
}

- (void) resetViewAnimated:(BOOL)animated {
    if (flipped_)
        [self flipPage];
    [table_ resetViewAnimated:animated];
}

- (void) _reloadData {
}

- (void) reloadData {
    if (flipped_)
        [self flipPage];
    [table_ setObject:[field_ text]];
    _profile(SearchView$reloadData)
        [table_ reloadData];
    _end
    PrintTimes();
    [table_ resetCursor];
}

- (UIView *) accessoryView {
    return accessory_;
}

- (NSString *) title {
    return nil;
}

- (NSString *) backButtonTitle {
    return CYLocalize("SEARCH");
}

- (void) setDelegate:(id)delegate {
    [table_ setDelegate:delegate];
    [super setDelegate:delegate];
}

@end
/* }}} */

@interface SettingsView : RVPage {
    _transient Database *database_;
    NSString *name_;
    Package *package_;
    UIPreferencesTable *table_;
    _UISwitchSlider *subscribedSwitch_;
    _UISwitchSlider *ignoredSwitch_;
    UIPreferencesControlTableCell *subscribedCell_;
    UIPreferencesControlTableCell *ignoredCell_;
}

- (id) initWithBook:(RVBook *)book database:(Database *)database package:(NSString *)package;

@end

@implementation SettingsView

- (void) dealloc {
    [table_ setDataSource:nil];

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

- (int) numberOfGroupsInPreferencesTable:(UIPreferencesTable *)table {
    if (package_ == nil)
        return 0;

    return 2;
}

- (NSString *) preferencesTable:(UIPreferencesTable *)table titleForGroup:(int)group {
    if (package_ == nil)
        return nil;

    switch (group) {
        case 0: return nil;
        case 1: return nil;

        default: _assert(false);
    }

    return nil;
}

- (BOOL) preferencesTable:(UIPreferencesTable *)table isLabelGroup:(int)group {
    if (package_ == nil)
        return NO;

    switch (group) {
        case 0: return NO;
        case 1: return YES;

        default: _assert(false);
    }

    return NO;
}

- (int) preferencesTable:(UIPreferencesTable *)table numberOfRowsInGroup:(int)group {
    if (package_ == nil)
        return 0;

    switch (group) {
        case 0: return 1;
        case 1: return 1;

        default: _assert(false);
    }

    return 0;
}

- (void) onSomething:(UIPreferencesControlTableCell *)cell withKey:(NSString *)key {
    if (package_ == nil)
        return;

    _UISwitchSlider *slider([cell control]);
    BOOL value([slider value] != 0);
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

- (void) onSubscribed:(UIPreferencesControlTableCell *)cell {
    [self onSomething:cell withKey:@"IsSubscribed"];
}

- (void) onIgnored:(UIPreferencesControlTableCell *)cell {
    [self onSomething:cell withKey:@"IsIgnored"];
}

- (id) preferencesTable:(UIPreferencesTable *)table cellForRow:(int)row inGroup:(int)group {
    if (package_ == nil)
        return nil;

    switch (group) {
        case 0: switch (row) {
            case 0:
                return subscribedCell_;
            case 1:
                return ignoredCell_;
            default: _assert(false);
        } break;

        case 1: switch (row) {
            case 0: {
                UIPreferencesControlTableCell *cell([[[UIPreferencesControlTableCell alloc] init] autorelease]);
                [cell setShowSelection:NO];
                [cell setTitle:CYLocalize("SHOW_ALL_CHANGES_EX")];
                return cell;
            }

            default: _assert(false);
        } break;

        default: _assert(false);
    }

    return nil;
}

- (id) initWithBook:(RVBook *)book database:(Database *)database package:(NSString *)package {
    if ((self = [super initWithBook:book])) {
        database_ = database;
        name_ = [package retain];

        table_ = [[UIPreferencesTable alloc] initWithFrame:[self bounds]];
        [self addSubview:table_];

        subscribedSwitch_ = [[_UISwitchSlider alloc] initWithFrame:CGRectMake(200, 10, 50, 20)];
        [subscribedSwitch_ addTarget:self action:@selector(onSubscribed:) forEvents:kUIControlEventMouseUpInside];

        ignoredSwitch_ = [[_UISwitchSlider alloc] initWithFrame:CGRectMake(200, 10, 50, 20)];
        [ignoredSwitch_ addTarget:self action:@selector(onIgnored:) forEvents:kUIControlEventMouseUpInside];

        subscribedCell_ = [[UIPreferencesControlTableCell alloc] init];
        [subscribedCell_ setShowSelection:NO];
        [subscribedCell_ setTitle:CYLocalize("SHOW_ALL_CHANGES")];
        [subscribedCell_ setControl:subscribedSwitch_];

        ignoredCell_ = [[UIPreferencesControlTableCell alloc] init];
        [ignoredCell_ setShowSelection:NO];
        [ignoredCell_ setTitle:CYLocalize("IGNORE_UPGRADES")];
        [ignoredCell_ setControl:ignoredSwitch_];

        [table_ setDataSource:self];
        [self reloadData];
    } return self;
}

- (void) resetViewAnimated:(BOOL)animated {
    [table_ resetViewAnimated:animated];
}

- (void) reloadData {
    if (package_ != nil)
        [package_ autorelease];
    package_ = [database_ packageWithName:name_];
    if (package_ != nil) {
        [package_ retain];
        [subscribedSwitch_ setValue:([package_ subscribed] ? 1 : 0) animated:NO];
        [ignoredSwitch_ setValue:([package_ ignored] ? 1 : 0) animated:NO];
    }

    [table_ reloadData];
}

- (NSString *) title {
    return CYLocalize("SETTINGS");
}

@end

/* Signature View {{{ */
@interface SignatureView : BrowserView {
    _transient Database *database_;
    NSString *package_;
}

- (id) initWithBook:(RVBook *)book database:(Database *)database package:(NSString *)package;

@end

@implementation SignatureView

- (void) dealloc {
    [package_ release];
    [super dealloc];
}

- (void) webView:(WebView *)sender didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame {
    // XXX: dude!
    [super webView:sender didClearWindowObject:window forFrame:frame];
}

- (id) initWithBook:(RVBook *)book database:(Database *)database package:(NSString *)package {
    if ((self = [super initWithBook:book]) != nil) {
        database_ = database;
        package_ = [package retain];
        [self reloadData];
    } return self;
}

- (void) resetViewAnimated:(BOOL)animated {
}

- (void) reloadData {
    [self loadURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"signature" ofType:@"html"]]];
}

@end
/* }}} */

@interface Cydia : UIApplication <
    ConfirmationViewDelegate,
    ProgressViewDelegate,
    SearchViewDelegate,
    CydiaDelegate
> {
    UIWindow *window_;

    UIView *underlay_;
    UIView *overlay_;
    CYBook *book_;
    UIToolbar *buttonbar_;

    RVBook *confirm_;

    NSMutableArray *essential_;
    NSMutableArray *broken_;

    Database *database_;
    ProgressView *progress_;

    unsigned tag_;

    UIKeyboard *keyboard_;
    UIProgressHUD *hud_;

    SectionsView *sections_;
    ChangesView *changes_;
    ManageView *manage_;
    SearchView *search_;

    PackageView *package_;
}

@end

@implementation Cydia

- (void) _loaded {
    if ([broken_ count] != 0) {
        int count = [broken_ count];

        UIActionSheet *sheet = [[[UIActionSheet alloc]
            initWithTitle:(count == 1 ? CYLocalize("HALFINSTALLED_PACKAGE") : [NSString stringWithFormat:CYLocalize("HALFINSTALLED_PACKAGES"), count])
            buttons:[NSArray arrayWithObjects:
                CYLocalize("FORCIBLY_CLEAR"),
                CYLocalize("TEMPORARY_IGNORE"),
            nil]
            defaultButtonIndex:0
            delegate:self
            context:@"fixhalf"
        ] autorelease];

        [sheet setBodyText:CYLocalize("HALFINSTALLED_PACKAGE_EX")];
        [sheet popupAlertAnimated:YES];
    } else if (!Ignored_ && [essential_ count] != 0) {
        int count = [essential_ count];

        UIActionSheet *sheet = [[[UIActionSheet alloc]
            initWithTitle:(count == 1 ? CYLocalize("ESSENTIAL_UPGRADE") : [NSString stringWithFormat:CYLocalize("ESSENTIAL_UPGRADES"), count])
            buttons:[NSArray arrayWithObjects:
                CYLocalize("UPGRADE_ESSENTIAL"),
                CYLocalize("COMPLETE_UPGRADE"),
                CYLocalize("TEMPORARY_IGNORE"),
            nil]
            defaultButtonIndex:0
            delegate:self
            context:@"upgrade"
        ] autorelease];

        [sheet setBodyText:CYLocalize("ESSENTIAL_UPGRADE_EX")];
        [sheet popupAlertAnimated:YES];
    }
}

- (void) _reloadData {
    UIView *block();

    static bool loaded(false);
    UIProgressHUD *hud([self addProgressHUD]);
    [hud setText:(loaded ? CYLocalize("RELOADING_DATA") : CYLocalize("LOADING_DATA"))];
    loaded = true;

    [database_ yieldToSelector:@selector(reloadData) withObject:nil];
    _trace();

    [self removeProgressHUD:hud];

    size_t changes(0);

    [essential_ removeAllObjects];
    [broken_ removeAllObjects];

    NSArray *packages = [database_ packages];
    for (Package *package in packages) {
        if ([package half])
            [broken_ addObject:package];
        if ([package upgradableAndEssential:NO]) {
            if ([package essential])
                [essential_ addObject:package];
            ++changes;
        }
    }

    if (changes != 0) {
        NSString *badge([[NSNumber numberWithInt:changes] stringValue]);
        [buttonbar_ setBadgeValue:badge forButton:3];
        if ([buttonbar_ respondsToSelector:@selector(setBadgeAnimated:forButton:)])
            [buttonbar_ setBadgeAnimated:([essential_ count] != 0) forButton:3];
        if ([self respondsToSelector:@selector(setApplicationBadge:)])
            [self setApplicationBadge:badge];
        else
            [self setApplicationBadgeString:badge];
    } else {
        [buttonbar_ setBadgeValue:nil forButton:3];
        if ([buttonbar_ respondsToSelector:@selector(setBadgeAnimated:forButton:)])
            [buttonbar_ setBadgeAnimated:NO forButton:3];
        if ([self respondsToSelector:@selector(removeApplicationBadge)])
            [self removeApplicationBadge];
        else // XXX: maybe use setApplicationBadgeString also?
            [self setApplicationIconBadgeNumber:0];
    }

    Queuing_ = false;
    [buttonbar_ setBadgeValue:nil forButton:4];

    [self updateData];

    // XXX: what is this line of code for?
    if ([packages count] == 0);
    else if (Loaded_ || ManualRefresh) loaded:
        [self _loaded];
    else {
        Loaded_ = YES;

        if (NSDate *update = [Metadata_ objectForKey:@"LastUpdate"]) {
            NSTimeInterval interval([update timeIntervalSinceNow]);
            if (interval <= 0 && interval > -600)
                goto loaded;
        }

        [book_ update];
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

- (void) updateData {
    [self _saveConfig];

    /* XXX: this is just stupid */
    if (tag_ != 2 && sections_ != nil)
        [sections_ reloadData];
    if (tag_ != 3 && changes_ != nil)
        [changes_ reloadData];
    if (tag_ != 5 && search_ != nil)
        [search_ reloadData];

    [book_ reloadData];
}

- (void) update_ {
    [database_ update];
}

- (void) syncData {
    FILE *file = fopen("/etc/apt/sources.list.d/cydia.list", "w");
    _assert(file != NULL);

    NSArray *keys = [Sources_ allKeys];

    for (NSString *key in keys) {
        NSDictionary *source = [Sources_ objectForKey:key];

        fprintf(file, "%s %s %s\n",
            [[source objectForKey:@"Type"] UTF8String],
            [[source objectForKey:@"URI"] UTF8String],
            [[source objectForKey:@"Distribution"] UTF8String]
        );
    }

    fclose(file);

    [self _saveConfig];

    [progress_
        detachNewThreadSelector:@selector(update_)
        toTarget:self
        withObject:nil
        title:CYLocalize("UPDATING_SOURCES")
    ];
}

- (void) reloadData {
    @synchronized (self) {
        if (confirm_ == nil)
            [self _reloadData];
    }
}

- (void) resolve {
    pkgProblemResolver *resolver = [database_ resolver];

    resolver->InstallProtect();
    if (!resolver->Resolve(true))
        _error->Discard();
}

- (void) popUpBook:(RVBook *)book {
    [underlay_ popSubview:book];
}

- (CGRect) popUpBounds {
    return [underlay_ bounds];
}

- (void) perform {
    [database_ prepare];

    confirm_ = [[RVBook alloc] initWithFrame:[self popUpBounds]];
    [confirm_ setDelegate:self];

    ConfirmationView *page([[[ConfirmationView alloc] initWithBook:confirm_ database:database_] autorelease]);
    [page setDelegate:self];

    [confirm_ setPage:page];
    [self popUpBook:confirm_];
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
        [database_ upgrade];
        [self perform];
    }
}

- (void) cancel {
    [self slideUp:[[[UIActionSheet alloc]
        initWithTitle:nil
        buttons:[NSArray arrayWithObjects:CYLocalize("CONTINUE_QUEUING"), CYLocalize("CANCEL_CLEAR"), nil]
        defaultButtonIndex:1
        delegate:self
        context:@"cancel"
    ] autorelease]];
}

- (void) complete {
    @synchronized (self) {
        [self _reloadData];

        if (confirm_ != nil) {
            [confirm_ release];
            confirm_ = nil;
        }
    }
}

- (void) confirm {
    [overlay_ removeFromSuperview];
    reload_ = true;

    [progress_
        detachNewThreadSelector:@selector(perform)
        toTarget:database_
        withObject:nil
        title:CYLocalize("RUNNING")
    ];
}

- (void) bootstrap_ {
    [database_ update];
    [database_ upgrade];
    [database_ prepare];
    [database_ perform];
}

/* XXX: replace and localize */
- (void) bootstrap {
    [progress_
        detachNewThreadSelector:@selector(bootstrap_)
        toTarget:self
        withObject:nil
        title:@"Bootstrap Install"
    ];
}

- (void) progressViewIsComplete:(ProgressView *)progress {
    if (confirm_ != nil) {
        [underlay_ addSubview:overlay_];
        [confirm_ popFromSuperviewAnimated:NO];
    }

    [self complete];
}

- (void) setPage:(RVPage *)page {
    [page resetViewAnimated:NO];
    [page setDelegate:self];
    [book_ setPage:page];
}

- (RVPage *) _pageForURL:(NSURL *)url withClass:(Class)_class {
    BrowserView *browser = [[[_class alloc] initWithBook:book_] autorelease];
    [browser loadURL:url];
    return browser;
}

- (void) _setHomePage {
    [self setPage:[self _pageForURL:[NSURL URLWithString:@"http://cydia.saurik.com/"] withClass:[HomeView class]]];
}

- (SectionsView *) sectionsView {
    if (sections_ == nil)
        sections_ = [[SectionsView alloc] initWithBook:book_ database:database_];
    return sections_;
}

- (void) buttonBarItemTapped:(id)sender {
    unsigned tag = [sender tag];
    if (tag == tag_) {
        [book_ resetViewAnimated:YES];
        return;
    } else if (tag_ == 2 && tag != 2)
        [[self sectionsView] resetView];

    switch (tag) {
        case 1: [self _setHomePage]; break;

        case 2: [self setPage:[self sectionsView]]; break;
        case 3: [self setPage:changes_]; break;
        case 4: [self setPage:manage_]; break;
        case 5: [self setPage:search_]; break;

        default: _assert(false);
    }

    tag_ = tag;
}

- (void) applicationWillSuspend {
    [database_ clean];
    [super applicationWillSuspend];
}

- (void) askForSettings {
    NSString *parenthetical(CYLocalize("PARENTHETICAL"));

    UIActionSheet *role = [[[UIActionSheet alloc]
        initWithTitle:CYLocalize("WHO_ARE_YOU")
        buttons:[NSArray arrayWithObjects:
            [NSString stringWithFormat:parenthetical, CYLocalize("USER"), CYLocalize("USER_EX")],
            [NSString stringWithFormat:parenthetical, CYLocalize("HACKER"), CYLocalize("HACKER_EX")],
            [NSString stringWithFormat:parenthetical, CYLocalize("DEVELOPER"), CYLocalize("DEVELOPER_EX")],
        nil]
        defaultButtonIndex:-1
        delegate:self
        context:@"role"
    ] autorelease];

    [role setBodyText:CYLocalize("ROLE_EX")];
    [role popupAlertAnimated:YES];
}

- (void) setPackageView:(PackageView *)view {
    if (package_ == nil)
        package_ = [view retain];
}

- (PackageView *) packageView {
    PackageView *view;

    if (package_ == nil)
        view = [[[PackageView alloc] initWithBook:book_ database:database_] autorelease];
    else {
        return package_;
        view = [package_ autorelease];
        package_ = nil;
    }

    return view;
}

- (void) finish {
    if (hud_ != nil) {
        [self setStatusBarShowsProgress:NO];
        [self removeProgressHUD:hud_];

        [hud_ autorelease];
        hud_ = nil;

        pid_t pid = ExecFork();
        if (pid == 0) {
            execlp("launchctl", "launchctl", "stop", "com.apple.SpringBoard", NULL);
            perror("launchctl stop");
        }

        return;
    }

    if (Role_ == nil) {
        [self askForSettings];
        return;
    }

    _trace();
    overlay_ = [[UIView alloc] initWithFrame:[underlay_ bounds]];

    CGRect screenrect = [UIHardware fullScreenApplicationContentRect];
    book_ = [[CYBook alloc] initWithFrame:CGRectMake(
        0, 0, screenrect.size.width, screenrect.size.height - 48
    ) database:database_];

    [book_ setDelegate:self];

    [overlay_ addSubview:book_];

    NSArray *buttonitems = [NSArray arrayWithObjects:
        [NSDictionary dictionaryWithObjectsAndKeys:
            @"buttonBarItemTapped:", kUIButtonBarButtonAction,
            @"home-up.png", kUIButtonBarButtonInfo,
            @"home-dn.png", kUIButtonBarButtonSelectedInfo,
            [NSNumber numberWithInt:1], kUIButtonBarButtonTag,
            self, kUIButtonBarButtonTarget,
            @"Cydia", kUIButtonBarButtonTitle,
            @"0", kUIButtonBarButtonType,
        nil],

        [NSDictionary dictionaryWithObjectsAndKeys:
            @"buttonBarItemTapped:", kUIButtonBarButtonAction,
            @"install-up.png", kUIButtonBarButtonInfo,
            @"install-dn.png", kUIButtonBarButtonSelectedInfo,
            [NSNumber numberWithInt:2], kUIButtonBarButtonTag,
            self, kUIButtonBarButtonTarget,
            CYLocalize("SECTIONS"), kUIButtonBarButtonTitle,
            @"0", kUIButtonBarButtonType,
        nil],

        [NSDictionary dictionaryWithObjectsAndKeys:
            @"buttonBarItemTapped:", kUIButtonBarButtonAction,
            @"changes-up.png", kUIButtonBarButtonInfo,
            @"changes-dn.png", kUIButtonBarButtonSelectedInfo,
            [NSNumber numberWithInt:3], kUIButtonBarButtonTag,
            self, kUIButtonBarButtonTarget,
            CYLocalize("CHANGES"), kUIButtonBarButtonTitle,
            @"0", kUIButtonBarButtonType,
        nil],

        [NSDictionary dictionaryWithObjectsAndKeys:
            @"buttonBarItemTapped:", kUIButtonBarButtonAction,
            @"manage-up.png", kUIButtonBarButtonInfo,
            @"manage-dn.png", kUIButtonBarButtonSelectedInfo,
            [NSNumber numberWithInt:4], kUIButtonBarButtonTag,
            self, kUIButtonBarButtonTarget,
            CYLocalize("MANAGE"), kUIButtonBarButtonTitle,
            @"0", kUIButtonBarButtonType,
        nil],

        [NSDictionary dictionaryWithObjectsAndKeys:
            @"buttonBarItemTapped:", kUIButtonBarButtonAction,
            @"search-up.png", kUIButtonBarButtonInfo,
            @"search-dn.png", kUIButtonBarButtonSelectedInfo,
            [NSNumber numberWithInt:5], kUIButtonBarButtonTag,
            self, kUIButtonBarButtonTarget,
            CYLocalize("SEARCH"), kUIButtonBarButtonTitle,
            @"0", kUIButtonBarButtonType,
        nil],
    nil];

    buttonbar_ = [[UIToolbar alloc]
        initInView:overlay_
        withFrame:CGRectMake(
            0, screenrect.size.height - ButtonBarHeight_,
            screenrect.size.width, ButtonBarHeight_
        )
        withItemList:buttonitems
    ];

    [buttonbar_ setDelegate:self];
    [buttonbar_ setBarStyle:1];
    [buttonbar_ setButtonBarTrackingMode:2];

    int buttons[5] = {1, 2, 3, 4, 5};
    [buttonbar_ registerButtonGroup:0 withButtons:buttons withCount:5];
    [buttonbar_ showButtonGroup:0 withDuration:0];

    for (int i = 0; i != 5; ++i)
        [[buttonbar_ viewWithTag:(i + 1)] setFrame:CGRectMake(
            i * 64 + 2, 1, 60, ButtonBarHeight_
        )];

    [buttonbar_ showSelectionForButton:1];
    [overlay_ addSubview:buttonbar_];

    [UIKeyboard initImplementationNow];
    CGSize keysize = [UIKeyboard defaultSize];
    CGRect keyrect = {{0, [overlay_ bounds].size.height}, keysize};
    keyboard_ = [[UIKeyboard alloc] initWithFrame:keyrect];
    //[[UIKeyboardImpl sharedInstance] setSoundsEnabled:(Sounds_Keyboard_ ? YES : NO)];
    [overlay_ addSubview:keyboard_];

    if (!bootstrap_)
        [underlay_ addSubview:overlay_];

    [self reloadData];

    [self sectionsView];
    changes_ = [[ChangesView alloc] initWithBook:book_ database:database_];
    search_ = [[SearchView alloc] initWithBook:book_ database:database_];

    manage_ = (ManageView *) [[self
        _pageForURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"manage" ofType:@"html"]]
        withClass:[ManageView class]
    ] retain];

    [self setPackageView:[self packageView]];

    PrintTimes();

    if (bootstrap_)
        [self bootstrap];
    else
        [self _setHomePage];
}

- (void) alertSheet:(UIActionSheet *)sheet buttonClicked:(int)button {
    NSString *context([sheet context]);

    if ([context isEqualToString:@"missing"])
        [sheet dismiss];
    else if ([context isEqualToString:@"cancel"]) {
        bool clear;

        switch (button) {
            case 1:
                clear = false;
            break;

            case 2:
                clear = true;
            break;

            default:
                _assert(false);
        }

        [sheet dismiss];

        @synchronized (self) {
            if (clear)
                [self _reloadData];
            else {
                Queuing_ = true;
                [buttonbar_ setBadgeValue:CYLocalize("Q_D") forButton:4];
                [book_ reloadData];
            }

            if (confirm_ != nil) {
                [confirm_ release];
                confirm_ = nil;
            }
        }
    } else if ([context isEqualToString:@"fixhalf"]) {
        switch (button) {
            case 1:
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
            break;

            case 2:
                [broken_ removeAllObjects];
                [self _loaded];
            break;

            default:
                _assert(false);
        }

        [sheet dismiss];
    } else if ([context isEqualToString:@"role"]) {
        switch (button) {
            case 1: Role_ = @"User"; break;
            case 2: Role_ = @"Hacker"; break;
            case 3: Role_ = @"Developer"; break;

            default:
                Role_ = nil;
                _assert(false);
        }

        bool reset = Settings_ != nil;

        Settings_ = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            Role_, @"Role",
        nil];

        [Metadata_ setObject:Settings_ forKey:@"Settings"];

        Changed_ = true;

        if (reset)
            [self updateData];
        else
            [self finish];

        [sheet dismiss];
    } else if ([context isEqualToString:@"upgrade"]) {
        switch (button) {
            case 1:
                @synchronized (self) {
                    for (Package *essential in essential_)
                        [essential install];

                    [self resolve];
                    [self perform];
                }
            break;

            case 2:
                [self distUpgrade];
            break;

            case 3:
                Ignored_ = YES;
            break;

            default:
                _assert(false);
        }

        [sheet dismiss];
    }
}

- (void) reorganize { _pooled
    system("/usr/libexec/cydia/free.sh");
    [self performSelectorOnMainThread:@selector(finish) withObject:nil waitUntilDone:NO];
}

- (void) applicationSuspend:(__GSEvent *)event {
    if (hud_ == nil && ![progress_ isRunning])
        [super applicationSuspend:event];
}

- (void) _animateSuspension:(BOOL)arg0 duration:(double)arg1 startTime:(double)arg2 scale:(float)arg3 {
    if (hud_ == nil)
        [super _animateSuspension:arg0 duration:arg1 startTime:arg2 scale:arg3];
}

- (void) _setSuspended:(BOOL)value {
    if (hud_ == nil)
        [super _setSuspended:value];
}

- (UIProgressHUD *) addProgressHUD {
    UIProgressHUD *hud([[[UIProgressHUD alloc] initWithWindow:window_] autorelease]);
    [window_ setUserInteractionEnabled:NO];
    [hud show:YES];
    [progress_ addSubview:hud];
    return hud;
}

- (void) removeProgressHUD:(UIProgressHUD *)hud {
    [hud show:NO];
    [hud removeFromSuperview];
    [window_ setUserInteractionEnabled:YES];
}

- (void) openMailToURL:(NSURL *)url {
// XXX: this makes me sad
#if 0
    [[[MailToView alloc] initWithView:underlay_ delegate:self url:url] autorelease];
#else
    [UIApp openURL:url];// asPanel:YES];
#endif
}

- (void) clearFirstResponder {
    if (id responder = [window_ firstResponder])
        [responder resignFirstResponder];
}

- (RVPage *) pageForPackage:(NSString *)name {
    if (Package *package = [database_ packageWithName:name]) {
        PackageView *view([self packageView]);
        [view setPackage:package];
        return view;
    } else {
        UIActionSheet *sheet = [[[UIActionSheet alloc]
            initWithTitle:CYLocalize("CANNOT_LOCATE_PACKAGE")
            buttons:[NSArray arrayWithObjects:CYLocalize("CLOSE"), nil]
            defaultButtonIndex:0
            delegate:self
            context:@"missing"
        ] autorelease];

        [sheet setBodyText:[NSString stringWithFormat:CYLocalize("PACKAGE_CANNOT_BE_FOUND"), name]];

        [sheet popupAlertAnimated:YES];
        return nil;
    }
}

- (RVPage *) pageForURL:(NSURL *)url hasTag:(int *)tag {
    if (tag != NULL)
        tag = 0;

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
        return [[[AddSourceView alloc] initWithBook:book_ database:database_] autorelease];
    else if ([path isEqualToString:@"/storage"])
        return [self _pageForURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"storage" ofType:@"html"]] withClass:[BrowserView class]];
    else if ([path isEqualToString:@"/sources"])
        return [[[SourceTable alloc] initWithBook:book_ database:database_] autorelease];
    else if ([path isEqualToString:@"/packages"])
        return [[[InstalledView alloc] initWithBook:book_ database:database_] autorelease];
    else if ([path hasPrefix:@"/url/"])
        return [self _pageForURL:[NSURL URLWithString:[path substringFromIndex:5]] withClass:[BrowserView class]];
    else if ([path hasPrefix:@"/launch/"])
        [self launchApplicationWithIdentifier:[path substringFromIndex:8] suspended:NO];
    else if ([path hasPrefix:@"/package-settings/"])
        return [[[SettingsView alloc] initWithBook:book_ database:database_ package:[path substringFromIndex:18]] autorelease];
    else if ([path hasPrefix:@"/package-signature/"])
        return [[[SignatureView alloc] initWithBook:book_ database:database_ package:[path substringFromIndex:19]] autorelease];
    else if ([path hasPrefix:@"/package/"])
        return [self pageForPackage:[path substringFromIndex:9]];
    else if ([path hasPrefix:@"/files/"]) {
        NSString *name = [path substringFromIndex:7];

        if (Package *package = [database_ packageWithName:name]) {
            FileTable *files = [[[FileTable alloc] initWithBook:book_ database:database_] autorelease];
            [files setPackage:package];
            return files;
        }
    }

    return nil;
}

- (void) applicationOpenURL:(NSURL *)url {
    [super applicationOpenURL:url];
    int tag;
    if (RVPage *page = [self pageForURL:url hasTag:&tag]) {
        [self setPage:page];
        [buttonbar_ showSelectionForButton:tag];
        tag_ = tag;
    }
}

- (void) applicationDidFinishLaunching:(id)unused {
    _trace();
    Font12_ = [[UIFont systemFontOfSize:12] retain];
    Font12Bold_ = [[UIFont boldSystemFontOfSize:12] retain];
    Font14_ = [[UIFont systemFontOfSize:14] retain];
    Font18Bold_ = [[UIFont boldSystemFontOfSize:18] retain];
    Font22Bold_ = [[UIFont boldSystemFontOfSize:22] retain];

    tag_ = 1;

    essential_ = [[NSMutableArray alloc] initWithCapacity:4];
    broken_ = [[NSMutableArray alloc] initWithCapacity:4];

    [NSURLProtocol registerClass:[CydiaURLProtocol class]];

    CGRect screenrect = [UIHardware fullScreenApplicationContentRect];
    window_ = [[UIWindow alloc] initWithContentRect:screenrect];

    [window_ orderFront:self];
    [window_ makeKey:self];
    [window_ setHidden:NO];

    database_ = [Database sharedInstance];
    progress_ = [[ProgressView alloc] initWithFrame:[window_ bounds] database:database_ delegate:self];
    [database_ setDelegate:progress_];
    [window_ setContentView:progress_];

    underlay_ = [[UIView alloc] initWithFrame:[progress_ bounds]];
    [progress_ setContentView:underlay_];

    [progress_ resetView];

    if (
        readlink("/Applications", NULL, 0) == -1 && errno == EINVAL ||
        readlink("/Library/Ringtones", NULL, 0) == -1 && errno == EINVAL ||
        readlink("/Library/Wallpaper", NULL, 0) == -1 && errno == EINVAL ||
        readlink("/usr/include", NULL, 0) == -1 && errno == EINVAL ||
        readlink("/usr/libexec", NULL, 0) == -1 && errno == EINVAL ||
        readlink("/usr/share", NULL, 0) == -1 && errno == EINVAL /*||
        readlink("/var/lib", NULL, 0) == -1 && errno == EINVAL*/
    ) {
        [self setIdleTimerDisabled:YES];

        hud_ = [[self addProgressHUD] retain];
        [hud_ setText:@"Reorganizing\n\nWill Automatically\nClose When Done"];

        [self setStatusBarShowsProgress:YES];

        [NSThread
            detachNewThreadSelector:@selector(reorganize)
            toTarget:self
            withObject:nil
        ];
    } else
        [self finish];
}

- (void) showKeyboard:(BOOL)show {
    CGSize keysize = [UIKeyboard defaultSize];
    CGRect keydown = {{0, [overlay_ bounds].size.height}, keysize};
    CGRect keyup = keydown;
    keyup.origin.y -= keysize.height;

    UIFrameAnimation *animation = [[[UIFrameAnimation alloc] initWithTarget:keyboard_] autorelease];
    [animation setSignificantRectFields:2];

    if (show) {
        [animation setStartFrame:keydown];
        [animation setEndFrame:keyup];
        [keyboard_ activate];
    } else {
        [animation setStartFrame:keyup];
        [animation setEndFrame:keydown];
        [keyboard_ deactivate];
    }

    [[UIAnimator sharedAnimator]
        addAnimations:[NSArray arrayWithObjects:animation, nil]
        withDuration:KeyboardTime_
        start:YES
    ];
}

- (void) slideUp:(UIActionSheet *)alert {
    if (Advanced_)
        [alert presentSheetFromButtonBar:buttonbar_];
    else
        [alert presentSheetInView:overlay_];
}

@end

void AddPreferences(NSString *plist) { _pooled
    NSMutableDictionary *settings = [[[NSMutableDictionary alloc] initWithContentsOfFile:plist] autorelease];
    _assert(settings != NULL);
    NSMutableArray *items = [settings objectForKey:@"items"];

    bool cydia(false);

    for (NSMutableDictionary *item in items) {
        NSString *label = [item objectForKey:@"label"];
        if (label != nil && [label isEqualToString:@"Cydia"]) {
            cydia = true;
            break;
        }
    }

    if (!cydia) {
        for (size_t i(0); i != [items count]; ++i) {
            NSDictionary *item([items objectAtIndex:i]);
            NSString *label = [item objectForKey:@"label"];
            if (label != nil && [label isEqualToString:@"General"]) {
                [items insertObject:[NSDictionary dictionaryWithObjectsAndKeys:
                    @"CydiaSettings", @"bundle",
                    @"PSLinkCell", @"cell",
                    [NSNumber numberWithBool:YES], @"hasIcon",
                    [NSNumber numberWithBool:YES], @"isController",
                    @"Cydia", @"label",
                nil] atIndex:(i + 1)];

                break;
            }
        }

        _assert([settings writeToFile:plist atomically:YES] == YES);
    }
}

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

void (*_UIWebDocumentView$_setUIKitDelegate$)(UIWebDocumentView *, SEL, id);

void $UIWebDocumentView$_setUIKitDelegate$(UIWebDocumentView *self, SEL sel, id delegate) {
    if (delegate == nil && $WebDefaultUIKitDelegate != nil)
        delegate = [$WebDefaultUIKitDelegate sharedUIKitDelegate];
    return _UIWebDocumentView$_setUIKitDelegate$(self, sel, delegate);
}

int main(int argc, char *argv[]) { _pooled
    _trace();

    PackageName = reinterpret_cast<CYString &(*)(Package *, SEL)>(method_getImplementation(class_getInstanceMethod([Package class], @selector(cyname))));

    /* Library Hacks {{{ */
    class_addMethod(objc_getClass("DOMNodeList"), @selector(countByEnumeratingWithState:objects:count:), (IMP) &DOMNodeList$countByEnumeratingWithState$objects$count$, "I20@0:4^{NSFastEnumerationState}8^@12I16");

    $WebDefaultUIKitDelegate = objc_getClass("WebDefaultUIKitDelegate");
    Method UIWebDocumentView$_setUIKitDelegate$(class_getInstanceMethod([WebView class], @selector(_setUIKitDelegate:)));
    if (UIWebDocumentView$_setUIKitDelegate$ != NULL) {
        _UIWebDocumentView$_setUIKitDelegate$ = reinterpret_cast<void (*)(UIWebDocumentView *, SEL, id)>(method_getImplementation(UIWebDocumentView$_setUIKitDelegate$));
        method_setImplementation(UIWebDocumentView$_setUIKitDelegate$, reinterpret_cast<IMP>(&$UIWebDocumentView$_setUIKitDelegate$));
    }
    /* }}} */
    /* Set Locale {{{ */
    Locale_ = CFLocaleCopyCurrent();
    Languages_ = [NSLocale preferredLanguages];
    //CFStringRef locale(CFLocaleGetIdentifier(Locale_));
    //NSLog(@"%@", [Languages_ description]);
    const char *lang;
    if (Languages_ == nil || [Languages_ count] == 0)
        lang = NULL;
    else
        lang = [[Languages_ objectAtIndex:0] UTF8String];
    setenv("LANG", lang, true);
    //std::setlocale(LC_ALL, lang);
    NSLog(@"Setting Language: %s", lang);
    /* }}} */

    // XXX: apr_app_initialize?
    apr_initialize();

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
            if (strcmp(args[argi], "--bootstrap") == 0)
                bootstrap_ = true;
            else if (strcmp(args[argi], "--substrate") == 0)
                substrate = true;
            else
                fprintf(stderr, "unknown argument: %s\n", args[argi]);
    }
    /* }}} */

    {
        NSString *plist = [Home_ stringByAppendingString:@"/Library/Preferences/com.apple.preferences.sounds.plist"];
        if (NSDictionary *sounds = [NSDictionary dictionaryWithContentsOfFile:plist])
            if (NSNumber *keyboard = [sounds objectForKey:@"keyboard"])
                Sounds_Keyboard_ = [keyboard boolValue];
    }

    App_ = [[NSBundle mainBundle] bundlePath];
    Home_ = NSHomeDirectory();

    setuid(0);
    setgid(0);

    /*Method alloc = class_getClassMethod([NSObject class], @selector(alloc));
    alloc_ = alloc->method_imp;
    alloc->method_imp = (IMP) &Alloc_;*/

    /*Method dealloc = class_getClassMethod([NSObject class], @selector(dealloc));
    dealloc_ = dealloc->method_imp;
    dealloc->method_imp = (IMP) &Dealloc_;*/

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

    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char *machine = new char[size];
    if (sysctlbyname("hw.machine", machine, &size, NULL, 0) == -1)
        perror("sysctlbyname(\"hw.machine\", ?)");
    else
        Machine_ = machine;

    UniqueID_ = [[UIDevice currentDevice] uniqueIdentifier];

    if (NSDictionary *system = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"])
        Build_ = [system objectForKey:@"ProductBuildVersion"];
    if (NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:@"/Applications/MobileSafari.app/Info.plist"]) {
        Product_ = [info objectForKey:@"SafariProductVersion"];
        Safari_ = [info objectForKey:@"CFBundleVersion"];
    }

    /*AddPreferences(@"/Applications/Preferences.app/Settings-iPhone.plist");
    AddPreferences(@"/Applications/Preferences.app/Settings-iPod.plist");*/

    /* Load Database {{{ */
    _trace();
    Metadata_ = [[[NSMutableDictionary alloc] initWithContentsOfFile:@"/var/lib/cydia/metadata.plist"] autorelease];
    _trace();
    SectionMap_ = [[[NSDictionary alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Sections" ofType:@"plist"]] autorelease];
    _trace();

    if (Metadata_ == NULL)
        Metadata_ = [NSMutableDictionary dictionaryWithCapacity:2];
    else {
        Settings_ = [Metadata_ objectForKey:@"Settings"];

        Packages_ = [Metadata_ objectForKey:@"Packages"];
        Sections_ = [Metadata_ objectForKey:@"Sections"];
        Sources_ = [Metadata_ objectForKey:@"Sources"];
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

#if RecycleWebViews
    Documents_ = [[[NSMutableArray alloc] initWithCapacity:4] autorelease];
#endif

    if (substrate && access("/Applications/WinterBoard.app/WinterBoard.dylib", F_OK) == 0)
        dlopen("/Applications/WinterBoard.app/WinterBoard.dylib", RTLD_LAZY | RTLD_GLOBAL);
    /*if (substrate && access("/Library/MobileSubstrate/MobileSubstrate.dylib", F_OK) == 0)
        dlopen("/Library/MobileSubstrate/MobileSubstrate.dylib", RTLD_LAZY | RTLD_GLOBAL);*/

    if (access("/User", F_OK) != 0) {
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

    _assert(pkgInitConfig(*_config));
    _assert(pkgInitSystem(*_config, _system));

    if (lang != NULL)
        _config->Set("APT::Acquire::Translation", lang);
    _config->Set("Acquire::http::Timeout", 15);
    _config->Set("Acquire::http::MaxParallel", 4);

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
    /*Purple_.Set(space_, 1.0, 0.3, 0.0, 1.0);
    Purplish_.Set(space_, 1.0, 0.6, 0.4, 1.0); ORANGE */
    /*Purple_.Set(space_, 1.0, 0.5, 0.0, 1.0);
    Purplish_.Set(space_, 1.0, 0.7, 0.2, 1.0); ORANGISH */
    /*Purple_.Set(space_, 0.5, 0.0, 0.7, 1.0);
    Purplish_.Set(space_, 0.7, 0.4, 0.8, 1.0); PURPLE */

//.93
    InstallingColor_ = [UIColor colorWithRed:0.88f green:1.00f blue:0.88f alpha:1.00f];
    RemovingColor_ = [UIColor colorWithRed:1.00f green:0.88f blue:0.88f alpha:1.00f];
    /* }}}*/

    Finishes_ = [NSArray arrayWithObjects:@"return", @"reopen", @"restart", @"reload", @"reboot", nil];

    /* UIKit Configuration {{{ */
    void (*$GSFontSetUseLegacyFontMetrics)(BOOL)(reinterpret_cast<void (*)(BOOL)>(dlsym(RTLD_DEFAULT, "GSFontSetUseLegacyFontMetrics")));
    if ($GSFontSetUseLegacyFontMetrics != NULL)
        $GSFontSetUseLegacyFontMetrics(YES);

    UIKeyboardDisableAutomaticAppearance();
    /* }}} */

    _trace();
    int value = UIApplicationMain(argc, argv, @"Cydia", @"Cydia");

    CGColorSpaceRelease(space_);
    CFRelease(Locale_);

    return value;
}
