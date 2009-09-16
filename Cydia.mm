/* Cydia - iPhone UIKit Front-End for Debian APT
 * Copyright (C) 2008-2009  Jay Freeman (saurik)
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
#import "UICaboodle/UCPlatform.h"
#import "UICaboodle/UCLocalize.h"

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
#include <apt-pkg/tagfile.h>

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

#import "UICaboodle/BrowserView.h"
#import "UICaboodle/ResetView.h"

#import "substrate.h"
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

@interface CYActionSheet : UIActionSheet {
    unsigned button_;
}

- (int) yieldToPopupAlertAnimated:(BOOL)animated;
@end

@implementation CYActionSheet

- (id) initWithTitle:(NSString *)title buttons:(NSArray *)buttons defaultButtonIndex:(int)index {
    if ((self = [super initWithTitle:title buttons:buttons defaultButtonIndex:index delegate:self context:nil]) != nil) {
    } return self;
}

- (void) alertSheet:(UIActionSheet *)sheet buttonClicked:(int)button {
    button_ = button;
}

- (int) yieldToPopupAlertAnimated:(BOOL)animated {
    button_ = 0;
    [self popupAlertAnimated:animated];
    NSRunLoop *loop([NSRunLoop currentRunLoop]);
    NSDate *future([NSDate distantFuture]);
    while (button_ == 0 && [loop runMode:NSDefaultRunLoopMode beforeDate:future]);
    return button_;
}

@end

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

#define ForRelease 1
#define TraceLogging (1 && !ForRelease)
#define HistogramInsertionSort (0 && !ForRelease)
#define ProfileTimes (0 && !ForRelease)
#define ForSaurik (1 && !ForRelease)
#define LogBrowser (0 && !ForRelease)
#define TrackResize (0 && !ForRelease)
#define ManualRefresh (1 && !ForRelease)
#define ShowInternals (0 && !ForRelease)
#define IgnoreInstall (0 && !ForRelease)
#define RecycleWebViews 0
#define RecyclePackageViews (1 && ForRelease)
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
@end

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
/* }}} */

/* C++ NSString Wrapper Cache {{{ */
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

/* Random Global Variables {{{ */
static const int PulseInterval_ = 50000;
static const int ButtonBarHeight_ = 48;
static const float KeyboardTime_ = 0.3f;

static int Finish_;
static NSArray *Finishes_;

#define SpringBoard_ "/System/Library/LaunchDaemons/com.apple.SpringBoard.plist"
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

static BOOL Advanced_;
static BOOL Ignored_;

static UIFont *Font12_;
static UIFont *Font12Bold_;
static UIFont *Font14_;
static UIFont *Font18Bold_;
static UIFont *Font22Bold_;

static const char *Machine_ = NULL;
static const NSString *System_ = NULL;
static const NSString *SerialNumber_ = nil;
static const NSString *ChipID_ = nil;
static const NSString *UniqueID_ = nil;
static const NSString *Build_ = nil;
static const NSString *Product_ = nil;
static const NSString *Safari_ = nil;

static CFLocaleRef Locale_;
static NSArray *Languages_;
static CGColorSpaceRef space_;

static bool reload_;

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

const char *StripVersion_(const char *version) {
    const char *colon(strchr(version, ':'));
    if (colon != NULL)
        version = colon + 1;
    return version;
}

CFStringRef StripVersion(const char *version) {
    const char *colon(strchr(version, ':'));
    if (colon != NULL)
        version = colon + 1;
    return CFStringCreateWithBytes(kCFAllocatorDefault, reinterpret_cast<const uint8_t *>(version), strlen(version), kCFStringEncodingUTF8, NO);
    // XXX: performance
    return CFCString(version);
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
- (RVPage *) pageForPackage:(NSString *)name;
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
- (bool) prepare;
- (void) perform;
- (bool) upgrade;
- (void) update;

- (void) setVisible;

- (void) updateWithStatus:(Status &)status;

- (void) setDelegate:(id)delegate;
- (Source *) getSource:(pkgCache::PkgFileIterator)file;
@end
/* }}} */
/* Delegate Helpers {{{ */
@implementation NSObject(ProgressDelegate)

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
    // XXX: holy typecast batman!
    [(id<ProgressDelegate>)self setProgressError:error withTitle:(package == nil ? id : [package name])];
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
    return depiction_.empty() ? nil : [depiction_ stringByReplacingOccurrencesOfString:@"*" withString:package];
}

- (NSString *) supportForPackage:(NSString *)package {
    return support_.empty() ? nil : [support_ stringByReplacingOccurrencesOfString:@"*" withString:package];
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
    bool cached_;
    bool parsed_;

    CYString section_;
    NSString *section$_;
    bool essential_;
    bool required_;
    bool visible_;

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

- (void) setVisible;

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

- (void) setVisible {
    visible_ = required_ && [self hasSupportingRole] && [self unfiltered];
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

        if (!file_.end()) {
            _profile(Package$initWithVersion$Source)
                source_ = [database_ getSource:file_.File()];
                if (source_ != nil)
                    [source_ retain];
                cached_ = true;
            _end
        }

        required_ = true;

        _profile(Package$initWithVersion$Tags)
            pkgCache::TagIterator tag(iterator_.TagList());
            if (!tag.end()) {
                tags_ = [[NSMutableArray alloc] initWithCapacity:8];
                do {
                    const char *name(tag.Name());
                    [tags_ addObject:(NSString *)CFCString(name)];
                    if (role_ == nil && strncmp(name, "role::", 6) == 0 /*&& strcmp(name, "role::leaper") != 0*/)
                        role_ = (NSString *) CFCString(name + 6);
                    if (required_ && strncmp(name, "require::", 9) == 0 && (
                        true
                    ))
                        required_ = false;
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
                } else {
                if (![version isEqualToString:latest_]) {
                    [metadata_ setObject:latest_ forKey:@"LastVersion"];
                    lastSeen_ = now_;
                    [metadata_ setObject:lastSeen_ forKey:@"LastSeen"];
                    changed = true;
                } }
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
        [self setVisible];
    } _end } return self;
}

+ (Package *) packageWithIterator:(pkgCache::PkgIterator)iterator withZone:(NSZone *)zone inPool:(apr_pool_t *)pool database:(Database *)database {
@synchronized ([Database class]) {
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
} }

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

- (NSArray *) relationships {
    return relationships_;
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
    return (![number boolValue] || [self visible]) && ![self uninstalled];
}

- (bool) isVisibleInSection:(NSString *)name {
    NSString *section = [self section];

    return
        [self visible] && (
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
@synchronized ([Database class]) {
    if (static_cast<pkgDepCache *>(cache_) == NULL)
        return nil;
    pkgCache::PkgIterator iterator(cache_->FindPkg([name UTF8String]));
    return iterator.end() ? nil : [Package packageWithIterator:iterator withZone:NULL inPool:pool_ database:self];
} }

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

- (void) reloadData { _pooled
@synchronized ([Database class]) {
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

    _trace();

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

- (void) setVisible {
    for (Package *package in packages_)
        [package setVisible];
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
        /* XXX: ignore this because users suck and don't understand why refreshing is important: return */;

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

/* Web Scripting {{{ */
@interface CydiaObject : NSObject {
    id indirect_;
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
    else if (selector == @selector(setAutoPopup:))
        return @"setAutoPopup";
    else if (selector == @selector(setButtonImage:withStyle:toFunction:))
        return @"setButtonImage";
    else if (selector == @selector(setButtonTitle:withStyle:toFunction:))
        return @"setButtonTitle";
    else if (selector == @selector(setFinishHook:))
        return @"setFinishHook";
    else if (selector == @selector(setPopupHook:))
        return @"setPopupHook";
    else if (selector == @selector(setSpecial:))
        return @"setSpecial";
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
    for (Package *package in installed)
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

- (void) setAutoPopup:(BOOL)popup {
    [indirect_ setAutoPopup:popup];
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

- (void) setFinishHook:(id)function {
    [indirect_ setFinishHook:function];
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
    return [[[NSString alloc] initWithFormat:format arguments:reinterpret_cast<va_list>(values)] autorelease];
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

@interface CydiaBrowserView : BrowserView {
    CydiaObject *cydia_;
}

@end

@implementation CydiaBrowserView

- (void) dealloc {
    [cydia_ release];
    [super dealloc];
}

- (void) webView:(WebView *)sender didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame {
    [super webView:sender didClearWindowObject:window forFrame:frame];
    [window setValue:cydia_ forKey:@"cydia"];
}

- (void) _setMoreHeaders:(NSMutableURLRequest *)request {
    if (System_ != NULL)
        [request setValue:System_ forHTTPHeaderField:@"X-System"];
    if (Machine_ != NULL)
        [request setValue:[NSString stringWithUTF8String:Machine_] forHTTPHeaderField:@"X-Machine"];
    if (UniqueID_ != nil)
        [request setValue:UniqueID_ forHTTPHeaderField:@"X-Unique-ID"];
    if (Role_ != nil)
        [request setValue:Role_ forHTTPHeaderField:@"X-Role"];
}

- (NSURLRequest *) webView:(WebView *)sender resource:(id)identifier willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse fromDataSource:(WebDataSource *)source {
    NSMutableURLRequest *copy = [request mutableCopy];
    [self _setMoreHeaders:copy];
    return copy;
}

- (id) initWithBook:(RVBook *)book forWidth:(float)width {
    if ((self = [super initWithBook:book forWidth:width ofClass:[CydiaBrowserView class]]) != nil) {
        cydia_ = [[CydiaObject alloc] initWithDelegate:indirect_];

        WebView *webview([webview_ webView]);

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

@protocol ConfirmationViewDelegate
- (void) cancel;
- (void) confirm;
- (void) queue;
@end

@interface ConfirmationView : CydiaBrowserView {
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
            _nodefault
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
        else if (Advanced_) {
            NSString *parenthetical(UCLocalize("PARENTHETICAL"));

            essential_ = [[UIActionSheet alloc]
                initWithTitle:UCLocalize("REMOVING_ESSENTIALS")
                buttons:[NSArray arrayWithObjects:
                    [NSString stringWithFormat:parenthetical, UCLocalize("CANCEL_OPERATION"), UCLocalize("SAFE")],
                    [NSString stringWithFormat:parenthetical, UCLocalize("FORCE_REMOVAL"), UCLocalize("UNSAFE")],
                nil]
                defaultButtonIndex:0
                delegate:self
                context:@"remove"
            ];

            [essential_ setDestructiveButtonIndex:1];
            [essential_ setBodyText:UCLocalize("REMOVING_ESSENTIALS_EX")];
        } else {
            essential_ = [[UIActionSheet alloc]
                initWithTitle:UCLocalize("UNABLE_TO_COMPLY")
                buttons:[NSArray arrayWithObjects:UCLocalize("OKAY"), nil]
                defaultButtonIndex:0
                delegate:self
                context:@"unable"
            ];

            [essential_ setBodyText:UCLocalize("UNABLE_TO_COMPLY_EX")];
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
    return UCLocalize("CONFIRM");
}

- (NSString *) leftButtonTitle {
    return [NSString stringWithFormat:UCLocalize("SLASH_DELIMITED"), UCLocalize("CANCEL"), UCLocalize("QUEUE")];
}

- (id) rightButtonTitle {
    return issues_ != nil ? nil : [super rightButtonTitle];
}

- (id) _rightButtonTitle {
#if AlwaysReload || IgnoreInstall
    return [super _rightButtonTitle];
#else
    return UCLocalize("CONFIRM");
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
    NSString *title_;
}

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
    if (title_ != nil)
        [title_ release];
    [super dealloc];
}

- (id) initWithFrame:(struct CGRect)frame database:(Database *)database delegate:(id)delegate {
    if ((self = [super initWithFrame:frame]) != nil) {
        database_ = database;
        delegate_ = delegate;

        transition_ = [[UITransitionView alloc] initWithFrame:[self bounds]];
        [transition_ setDelegate:self];

        overlay_ = [[UIView alloc] initWithFrame:[transition_ bounds]];

        background_ = [[UIView alloc] initWithFrame:[self bounds]];
        [background_ setBackgroundColor:[UIColor blackColor]];
        [self addSubview:background_];

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

        output_ = [[UITextView alloc] initWithFrame:CGRectMake(
            10,
            navrect.size.height + 20,
            bounds.size.width - 20,
            bounds.size.height - navsize.height - 62 - navrect.size.height
        )];

        //[output_ setTextFont:@"Courier New"];
        [output_ setFont:[[output_ font] fontWithSize:12]];

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

        [close_ addTarget:self action:@selector(closeButtonPushed) forEvents:UIControlEventTouchUpInside];
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

    if ([context isEqualToString:@"conffile"]) {
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
            _nodefault
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
    UINavigationItem *item([navbar_ topItem]);
    [item setTitle:UCLocalize("COMPLETE")];

    [overlay_ addSubview:close_];
    [progress_ removeFromSuperview];
    [status_ removeFromSuperview];

    [database_ popErrorWithTitle:title_];
    [delegate_ progressViewIsComplete:self];

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
        case 0: [close_ setTitle:UCLocalize("RETURN_TO_CYDIA")]; break;
        case 1: [close_ setTitle:UCLocalize("CLOSE_CYDIA")]; break;
        case 2: [close_ setTitle:UCLocalize("RESTART_SPRINGBOARD")]; break;
        case 3: [close_ setTitle:UCLocalize("RELOAD_SPRINGBOARD")]; break;
        case 4: [close_ setTitle:UCLocalize("REBOOT_DEVICE")]; break;
    }

#define ListCache_ "/User/Library/Caches/com.apple.mobile.installation.plist"
#define IconCache_ "/User/Library/Caches/com.apple.springboard-imagecache-icons.plist"

    unlink(IconCache_);

    if (NSMutableDictionary *cache = [[NSMutableDictionary alloc] initWithContentsOfFile:@ListCache_]) {
        [cache autorelease];

        NSFileManager *manager([NSFileManager defaultManager]);
        NSError *error(nil);

        id system([cache objectForKey:@"System"]);
        if (system == nil)
            goto error;

        struct stat info;
        if (stat(ListCache_, &info) == -1)
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

        [cache writeToFile:@ListCache_ atomically:YES];

        if (chown(ListCache_, info.st_uid, info.st_gid) == -1)
            goto error;
        if (chmod(ListCache_, info.st_mode) == -1)
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
    if (title_ != nil)
        [title_ release];
    if (title == nil)
        title_ = nil;
    else
        title_ = [title retain];

    UINavigationItem *item([navbar_ topItem]);
    [item setTitle:title_];

    [status_ setText:nil];
    [output_ setText:@""];
    [progress_ setProgress:0];

    [close_ removeFromSuperview];
    [overlay_ addSubview:progress_];
    [overlay_ addSubview:status_];

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

    [sheet setBodyText:error];
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

    UIActionSheet *sheet = [[[UIActionSheet alloc]
        initWithTitle:UCLocalize("CONFIGURATION_UPGRADE")
        buttons:[NSArray arrayWithObjects:
            UCLocalize("KEEP_OLD_COPY"),
            UCLocalize("ACCEPT_NEW_COPY"),
            // XXX: UCLocalize("SEE_WHAT_CHANGED"),
        nil]
        defaultButtonIndex:0
        delegate:self
        context:@"conffile"
    ] autorelease];

    [sheet setBodyText:[NSString stringWithFormat:@"%@\n\n%@", UCLocalize("CONFIGURATION_UPGRADE_EX"), ofile]];
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
@interface ContentView : UIView {
    _transient id delegate_;
}

@end

@interface PackageCell : UITableViewCell {
    UIImage *icon_;
    NSString *name_;
    NSString *description_;
    bool commercial_;
    NSString *source_;
    UIImage *badge_;
    Package *package_;
    UIColor *color_;
    ContentView *content_;
    BOOL faded_;
    float fade_;
    UIImage *placard_;
}

- (PackageCell *) init;
- (void) setPackage:(Package *)package;

+ (int) heightForPackage:(Package *)package;
- (void) drawContentRect:(CGRect)rect;

@end

@implementation ContentView

- (id) initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame]) != nil) {
    } return self;
}

- (void) setDelegate:(id)delegate {
    delegate_ = delegate;
}

- (void) drawRect:(CGRect)rect {
    [super drawRect:rect];
    [delegate_ drawContentRect:rect];
}

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
    [content_ release];
    [color_ release];
    [super dealloc];
}

- (float) fade {
    return faded_ ? [self selectionPercent] : fade_;
}

- (PackageCell *) init {
    CGRect frame(CGRectMake(0, 0, 320, 74));
    if ((self = [super initWithFrame:frame reuseIdentifier:@"Package"]) != nil) {
        UIView *content([self contentView]);
        CGRect bounds([content bounds]);
        content_ = [[ContentView alloc] initWithFrame:bounds];
        [content_ setDelegate:self];
        [content_ setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)];
        [content_ setOpaque:YES];
        [content addSubview:content_];
        if ([self respondsToSelector:@selector(selectionPercent)])
            faded_ = YES;
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
    description_ = [[package shortDescription] retain];
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
    bool selected([self isSelected]);

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

    if (selected)
        UISetColor(White_);

    if (!selected)
        UISetColor(commercial_ ? Purple_ : Black_);
    [name_ drawAtPoint:CGPointMake(48, 8) forWidth:(placard_ == nil ? 240 : 214) withFont:Font18Bold_ ellipsis:2];
    [source_ drawAtPoint:CGPointMake(58, 29) forWidth:225 withFont:Font12_ ellipsis:2];

    if (!selected)
        UISetColor(commercial_ ? Purplish_ : Gray_);
    [description_ drawAtPoint:CGPointMake(12, 46) forWidth:274 withFont:Font14_ ellipsis:2];

    if (placard_ != nil)
        [placard_ drawAtPoint:CGPointMake(268, 9)];
}

- (void) setSelected:(BOOL)selected animated:(BOOL)fade {
    //[self _setBackgroundColor];
    [super setSelected:selected animated:fade];
    [content_ setNeedsDisplay];
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
        [switch_ addTarget:self action:@selector(onSwitch:) forEvents:UIControlEventTouchUpInside];
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
        name_ = [UCLocalize("ALL_PACKAGES") retain];
        count_ = nil;
    } else {
        section_ = [section localized];
        if (section_ != nil)
            section_ = [section_ retain];
        name_  = [(section_ == nil || [section_ length] == 0 ? UCLocalize("NO_SECTION") : section_) retain];
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
            initWithTitle:UCLocalize("NAME")
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
    return UCLocalize("INSTALLED_FILES");
}

- (NSString *) backButtonTitle {
    return UCLocalize("FILES");
}

@end
/* }}} */
/* Package View {{{ */
@interface PackageView : CydiaBrowserView {
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
    int count([buttons_ count]);
    if (count == 0)
        return;

    if (count == 1)
        [self _clickButtonWithName:[buttons_ objectAtIndex:0]];
    else {
        NSMutableArray *buttons = [NSMutableArray arrayWithCapacity:(count + 1)];
        [buttons addObjectsFromArray:buttons_];
        [buttons addObject:UCLocalize("CANCEL")];

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
    return count == 0 ? nil : count != 1 ? UCLocalize("MODIFY") : [buttons_ objectAtIndex:0];
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
    UITableView *list_;
    NSMutableArray *index_;
    NSMutableDictionary *indices_;
}

- (id) initWithBook:(RVBook *)book database:(Database *)database title:(NSString *)title;

- (void) setDelegate:(id)delegate;

- (void) reloadData;
- (void) resetCursor;

- (UITableView *) list;

- (void) setShouldHideHeaderInShortLists:(BOOL)hide;

@end

@implementation PackageTable

- (void) dealloc {
    [list_ setDataSource:nil];

    [title_ release];
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
    PackageCell *cell([table dequeueReusableCellWithIdentifier:@"Package"]);
    if (cell == nil)
        cell = [[[PackageCell alloc] init] autorelease];
    [cell setPackage:[self packageAtIndexPath:path]];
    return cell;
}

- (CGFloat) tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    return 73;
    return [PackageCell heightForPackage:[self packageAtIndexPath:path]];
}

- (NSIndexPath *) tableView:(UITableView *)table willSelectRowAtIndexPath:(NSIndexPath *)path {
    Package *package([self packageAtIndexPath:path]);
    package = [database_ packageWithName:[package id]];
    PackageView *view([delegate_ packageView]);
    [view setPackage:package];
    [view setDelegate:delegate_];
    [book_ pushPage:view];
    return path;
}

- (NSArray *) sectionIndexTitlesForTableView:(UITableView *)tableView {
    return [packages_ count] > 20 ? index_ : nil;
}

- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index {
    return index;
}

- (id) initWithBook:(RVBook *)book database:(Database *)database title:(NSString *)title {
    if ((self = [super initWithBook:book]) != nil) {
        database_ = database;
        title_ = [title retain];

        index_ = [[NSMutableArray alloc] initWithCapacity:32];
        indices_ = [[NSMutableDictionary alloc] initWithCapacity:32];

        packages_ = [[NSMutableArray arrayWithCapacity:16] retain];
        sections_ = [[NSMutableArray arrayWithCapacity:16] retain];

        list_ = [[UITableView alloc] initWithFrame:[self bounds] style:UITableViewStylePlain];
        [list_ setDataSource:self];
        [list_ setDelegate:self];

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

- (NSString *) title {
    return title_;
}

- (void) resetViewAnimated:(BOOL)animated {
    [list_ resetViewAnimated:animated];
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
        Method method(class_getInstanceMethod([Package class], filter));
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
    NSURLConnection *trivial_;
    NSURLConnection *trivial_bz2_;
    NSURLConnection *trivial_gz_;
    //NSURLConnection *automatic_;

    BOOL cydia_;
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
    [self _deallocConnection:trivial_];
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
        case 0: return UCLocalize("ENTERED_BY_USER");
        case 1: return UCLocalize("INSTALLED_BY_PACKAGE");

        _nodefault
    }
}

- (int) sectionList:(UISectionList *)list rowForSection:(int)section {
    switch (section + (offset_ == 0 ? 1 : 0)) {
        case 0: return 0;
        case 1: return offset_;

        _nodefault
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

                UIActionSheet *sheet = [[[UIActionSheet alloc]
                    initWithTitle:UCLocalize("SOURCE_WARNING")
                    buttons:[NSArray arrayWithObjects:UCLocalize("ADD_ANYWAY"), UCLocalize("CANCEL"), nil]
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
                initWithTitle:UCLocalize("VERIFICATION_ERROR")
                buttons:[NSArray arrayWithObjects:UCLocalize("OK"), nil]
                defaultButtonIndex:0
                delegate:self
                context:@"urlerror"
            ] autorelease];

            [sheet setBodyText:[error_ localizedDescription]];
            [sheet popupAlertAnimated:YES];
        } else {
            UIActionSheet *sheet = [[[UIActionSheet alloc]
                initWithTitle:UCLocalize("NOT_REPOSITORY")
                buttons:[NSArray arrayWithObjects:UCLocalize("OK"), nil]
                defaultButtonIndex:0
                delegate:self
                context:@"trivial"
            ] autorelease];

            [sheet setBodyText:UCLocalize("NOT_REPOSITORY_EX")];
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

                trivial_ = [[self _requestHRef:[href_ stringByAppendingString:@"Packages"] method:@"HEAD"] retain];
                trivial_bz2_ = [[self _requestHRef:[href_ stringByAppendingString:@"Packages.bz2"] method:@"HEAD"] retain];
                trivial_gz_ = [[self _requestHRef:[href_ stringByAppendingString:@"Packages.gz"] method:@"HEAD"] retain];
                //trivial_bz2_ = [[self _requestHRef:[href stringByAppendingString:@"dists/Release"] method:@"HEAD"] retain];

                cydia_ = false;

                hud_ = [[delegate_ addProgressHUD] retain];
                [hud_ setText:UCLocalize("VERIFYING_URL")];
            } break;

            case 2:
            break;

            _nodefault
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

            _nodefault
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
            initWithTitle:UCLocalize("NAME")
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
    if (!list.ReadMainList())
        return;

    [sources_ removeAllObjects];
    [sources_ addObjectsFromArray:[database_ sources]];
    _trace();
    [sources_ sortUsingSelector:@selector(compareByNameAndType:)];
    _trace();

    int count([sources_ count]);
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
        initWithTitle:UCLocalize("ENTER_APT_URL")
        buttons:[NSArray arrayWithObjects:UCLocalize("ADD_SOURCE"), UCLocalize("CANCEL"), nil]
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
    return UCLocalize("SOURCES");
}

- (NSString *) leftButtonTitle {
    return [[list_ table] isRowDeletionEnabled] ? UCLocalize("ADD") : nil;
}

- (id) rightButtonTitle {
    return [[list_ table] isRowDeletionEnabled] ? UCLocalize("DONE") : UCLocalize("EDIT");
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
    return UCLocalize("INSTALLED");
}

- (NSString *) backButtonTitle {
    return UCLocalize("PACKAGES");
}

- (id) rightButtonTitle {
    return Role_ != nil && [Role_ isEqualToString:@"Developer"] ? nil : expert_ ? UCLocalize("EXPERT") : UCLocalize("SIMPLE");
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
@interface HomeView : CydiaBrowserView {
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

- (void) _setMoreHeaders:(NSMutableURLRequest *)request {
    [super _setMoreHeaders:request];
    if (ChipID_ != nil)
        [request setValue:ChipID_ forHTTPHeaderField:@"X-Chip-ID"];
}

- (void) _leftButtonClicked {
    UIActionSheet *sheet = [[[UIActionSheet alloc]
        initWithTitle:UCLocalize("ABOUT_CYDIA")
        buttons:[NSArray arrayWithObjects:UCLocalize("CLOSE"), nil]
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
    return UCLocalize("ABOUT");
}

@end
/* }}} */
/* Manage View {{{ */
@interface ManageView : CydiaBrowserView {
}

@end

@implementation ManageView

- (NSString *) title {
    return UCLocalize("MANAGE");
}

- (void) _leftButtonClicked {
    [delegate_ askForSettings];
    [delegate_ updateData];
}

- (NSString *) leftButtonTitle {
    return UCLocalize("SETTINGS");
}

#if !AlwaysReload
- (id) _rightButtonTitle {
    return Queuing_ ? UCLocalize("QUEUE") : nil;
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
    [prompt_ setText:UCLocalize("UPDATING_DATABASE")];
    [progress_ setProgress:0];

    updating_ = true;
    [overlay_ addSubview:cancel_];

    [NSThread
        detachNewThreadSelector:@selector(_update)
        toTarget:self
        withObject:nil
    ];
}

- (void) alertSheet:(UIActionSheet *)sheet buttonClicked:(int)button {
    NSString *context([sheet context]);

    if ([context isEqualToString:@"refresh"])
        [sheet dismiss];
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

        CGRect ovrrect([navbar_ bounds]);
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

        int barstyle([overlay_ _barStyle:NO]);
        bool ugly(barstyle == 0);

        UIProgressIndicatorStyle style = ugly ?
            UIProgressIndicatorStyleMediumBrown :
            UIProgressIndicatorStyleMediumWhite;

        CGSize indsize([UIProgressIndicator defaultSizeForStyle:style]);
        unsigned indoffset = (ovrrect.size.height - indsize.height) / 2;
        CGRect indrect = {{indoffset, indoffset}, indsize};

        indicator_ = [[UIProgressIndicator alloc] initWithFrame:indrect];
        [indicator_ setStyle:style];
        [overlay_ addSubview:indicator_];

        CGSize prmsize = {215, indsize.height + 4};

        CGRect prmrect = {{
            indoffset * 2 + indsize.width,
            unsigned(ovrrect.size.height - prmsize.height) / 2 - 1
        }, prmsize};

        UIFont *font([UIFont systemFontOfSize:15]);

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

        cancel_ = [[UINavigationButton alloc] initWithTitle:UCLocalize("CANCEL") style:UINavigationButtonStyleHighlighted];
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

- (void) setProgressError:(NSString *)error withTitle:(NSString *)title {
    [prompt_ setText:[NSString stringWithFormat:UCLocalize("COLON_DELIMITED"), UCLocalize("ERROR"), error]];
}

/*
    UIActionSheet *sheet = [[[UIActionSheet alloc]
        initWithTitle:[NSString stringWithFormat:UCLocalize("COLON_DELIMITED"), UCLocalize("ERROR"), UCLocalize("REFRESH")]
        buttons:[NSArray arrayWithObjects:
            UCLocalize("OK"),
        nil]
        defaultButtonIndex:0
        delegate:self
        context:@"refresh"
    ] autorelease];

    [sheet setBodyText:error];
    [sheet popupAlertAnimated:YES];

    [self reloadButtons];
*/

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
        title = UCLocalize("ALL_PACKAGES");
    } else {
        section = [filtered_ objectAtIndex:(row - 1)];
        name = [section name];

        if (name != nil) {
            name = [NSString stringWithString:name];
            title = [[NSBundle mainBundle] localizedStringForKey:Simplify(name) value:nil table:@"Sections"];
        } else {
            name = @"";
            title = UCLocalize("NO_SECTION");
        }
    }

    PackageTable *table = [[[FilteredPackageTable alloc]
        initWithBook:book_
        database:database_
        title:title
        filter:@selector(isVisibleInSection:)
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
            initWithTitle:UCLocalize("NAME")
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
            if (![package valid] || ![package visible])
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
            if (![package valid] || ![package visible])
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
    return editing_ ? UCLocalize("SECTION_VISIBILITY") : UCLocalize("SECTIONS");
}

- (NSString *) backButtonTitle {
    return UCLocalize("SECTIONS");
}

- (id) rightButtonTitle {
    return [sections_ count] == 0 ? nil : editing_ ? UCLocalize("DONE") : UCLocalize("EDIT");
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
    UITableView *list_;
    unsigned upgrades_;
}

- (id) initWithBook:(RVBook *)book database:(Database *)database;
- (void) reloadData;

@end

@implementation ChangesView

- (void) dealloc {
    [list_ setDelegate:nil];
    [list_ setDataSource:nil];

    [packages_ release];
    [sections_ release];
    [list_ release];
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
    return [packages_ objectAtIndex:([section row] + row)];
}

- (UITableViewCell *) tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    PackageCell *cell([table dequeueReusableCellWithIdentifier:@"Package"]);
    if (cell == nil)
        cell = [[[PackageCell alloc] init] autorelease];
    [cell setPackage:[self packageAtIndexPath:path]];
    return cell;
}

- (CGFloat) tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    return 73;
    return [PackageCell heightForPackage:[self packageAtIndexPath:path]];
}

- (NSIndexPath *) tableView:(UITableView *)table willSelectRowAtIndexPath:(NSIndexPath *)path {
    Package *package([self packageAtIndexPath:path]);
    PackageView *view([delegate_ packageView]);
    [view setDelegate:delegate_];
    [view setPackage:package];
    [book_ pushPage:view];
    return path;
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

        list_ = [[UITableView alloc] initWithFrame:[self bounds] style:UITableViewStylePlain];
        [self addSubview:list_];

        //XXX:[list_ setShouldHideHeaderInShortLists:NO];
        [list_ setDataSource:self];
        [list_ setDelegate:self];
        //[list_ setSectionListStyle:1];

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
            [package uninstalled] && [package valid] && [package visible] ||
            [package upgradableAndEssential:YES]
        )
            [packages_ addObject:package];

    _trace();
    [packages_ radixSortUsingFunction:reinterpret_cast<SKRadixFunction>(&PackageChangesRadix) withContext:NULL];
    _trace();

    Section *upgradable = [[[Section alloc] initWithName:UCLocalize("AVAILABLE_UPGRADES") localize:NO] autorelease];
    Section *ignored = [[[Section alloc] initWithName:UCLocalize("IGNORED_UPGRADES") localize:NO] autorelease];
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
                    name = UCLocalize("UNKNOWN");
                else {
                    name = (NSString *) CFDateFormatterCreateStringWithDate(NULL, formatter, (CFDateRef) seen);
                    [name autorelease];
                }

                _profile(ChangesView$reloadData$Allocate)
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
    return [(CYBook *)book_ updating] ? nil : UCLocalize("REFRESH");
}

- (id) rightButtonTitle {
    return upgrades_ == 0 ? nil : [NSString stringWithFormat:UCLocalize("PARENTHETICAL"), UCLocalize("UPGRADE"), [NSString stringWithFormat:@"%u", upgrades_]];
}

- (NSString *) title {
    return UCLocalize("CHANGES");
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
    FilteredPackageTable *table_;
    UIView *dimmed_;
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
    [table_ release];
    [dimmed_ release];
    [super dealloc];
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
        [self addSubview:table_];

        CGRect cnfrect = {{7, 38}, {17, 18}};

        CGRect area;

        area.origin.x = 10;
        area.origin.y = 1;

        area.size.width = [self bounds].size.width - area.origin.x * 2;
        area.size.height = [UISearchField defaultHeight];

        field_ = [[UISearchField alloc] initWithFrame:area];

        UIFont *font = [UIFont systemFontOfSize:16];
        [field_ setFont:font];

        [field_ setPlaceholder:UCLocalize("SEARCH_EX")];
        [field_ setDelegate:self];

        [field_ setPaddingTop:5];

        UITextInputTraits *traits([field_ textInputTraits]);
        [traits setAutocapitalizationType:UITextAutocapitalizationTypeNone];
        [traits setAutocorrectionType:UITextAutocorrectionTypeNo];
        [traits setReturnKeyType:UIReturnKeySearch];

        CGRect accrect = {{0, 6}, {6 + cnfrect.size.width + 6 + area.size.width + 6, area.size.height}};

        accessory_ = [[UIView alloc] initWithFrame:accrect];
        [accessory_ addSubview:field_];

        [self setAutoresizingMask:UIViewAutoresizingFlexibleHeight];
        [table_ setAutoresizingMask:UIViewAutoresizingFlexibleHeight];
    } return self;
}

- (void) resetViewAnimated:(BOOL)animated {
    [table_ resetViewAnimated:animated];
}

- (void) _reloadData {
}

- (void) reloadData {
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
    return UCLocalize("SEARCH");
}

- (void) setDelegate:(id)delegate {
    [table_ setDelegate:delegate];
    [super setDelegate:delegate];
}

@end
/* }}} */
/* Settings View {{{ */
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

        _nodefault
    }

    return nil;
}

- (BOOL) preferencesTable:(UIPreferencesTable *)table isLabelGroup:(int)group {
    if (package_ == nil)
        return NO;

    switch (group) {
        case 0: return NO;
        case 1: return YES;

        _nodefault
    }

    return NO;
}

- (int) preferencesTable:(UIPreferencesTable *)table numberOfRowsInGroup:(int)group {
    if (package_ == nil)
        return 0;

    switch (group) {
        case 0: return 1;
        case 1: return 1;

        _nodefault
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
            _nodefault
        } break;

        case 1: switch (row) {
            case 0: {
                UIPreferencesControlTableCell *cell([[[UIPreferencesControlTableCell alloc] init] autorelease]);
                [cell setShowSelection:NO];
                [cell setTitle:UCLocalize("SHOW_ALL_CHANGES_EX")];
                return cell;
            }

            _nodefault
        } break;

        _nodefault
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
        [subscribedSwitch_ addTarget:self action:@selector(onSubscribed:) forEvents:UIControlEventTouchUpInside];

        ignoredSwitch_ = [[_UISwitchSlider alloc] initWithFrame:CGRectMake(200, 10, 50, 20)];
        [ignoredSwitch_ addTarget:self action:@selector(onIgnored:) forEvents:UIControlEventTouchUpInside];

        subscribedCell_ = [[UIPreferencesControlTableCell alloc] init];
        [subscribedCell_ setShowSelection:NO];
        [subscribedCell_ setTitle:UCLocalize("SHOW_ALL_CHANGES")];
        [subscribedCell_ setControl:subscribedSwitch_];

        ignoredCell_ = [[UIPreferencesControlTableCell alloc] init];
        [ignoredCell_ setShowSelection:NO];
        [ignoredCell_ setTitle:UCLocalize("IGNORE_UPGRADES")];
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
    return UCLocalize("SETTINGS");
}

@end
/* }}} */

/* Signature View {{{ */
@interface SignatureView : CydiaBrowserView {
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
    UIToolbar *toolbar_;

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

#if RecyclePackageViews
    NSMutableArray *details_;
#endif
}

- (RVPage *) _pageForURL:(NSURL *)url withClass:(Class)_class;
- (void) setPage:(RVPage *)page;

@end

static _finline void _setHomePage(Cydia *self) {
    [self setPage:[self _pageForURL:[NSURL URLWithString:CydiaURL(@"")] withClass:[HomeView class]]];
}

@implementation Cydia

- (void) _loaded {
    if ([broken_ count] != 0) {
        int count = [broken_ count];

        UIActionSheet *sheet = [[[UIActionSheet alloc]
            initWithTitle:(count == 1 ? UCLocalize("HALFINSTALLED_PACKAGE") : [NSString stringWithFormat:UCLocalize("HALFINSTALLED_PACKAGES"), count])
            buttons:[NSArray arrayWithObjects:
                UCLocalize("FORCIBLY_CLEAR"),
                UCLocalize("TEMPORARY_IGNORE"),
            nil]
            defaultButtonIndex:0
            delegate:self
            context:@"fixhalf"
        ] autorelease];

        [sheet setBodyText:UCLocalize("HALFINSTALLED_PACKAGE_EX")];
        [sheet popupAlertAnimated:YES];
    } else if (!Ignored_ && [essential_ count] != 0) {
        int count = [essential_ count];

        UIActionSheet *sheet = [[[UIActionSheet alloc]
            initWithTitle:(count == 1 ? UCLocalize("ESSENTIAL_UPGRADE") : [NSString stringWithFormat:UCLocalize("ESSENTIAL_UPGRADES"), count])
            buttons:[NSArray arrayWithObjects:
                UCLocalize("UPGRADE_ESSENTIAL"),
                UCLocalize("COMPLETE_UPGRADE"),
                UCLocalize("TEMPORARY_IGNORE"),
            nil]
            defaultButtonIndex:0
            delegate:self
            context:@"upgrade"
        ] autorelease];

        [sheet setBodyText:UCLocalize("ESSENTIAL_UPGRADE_EX")];
        [sheet popupAlertAnimated:YES];
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
    if (tag_ != 2 && sections_ != nil)
        [sections_ reloadData];
    if (tag_ != 3 && changes_ != nil)
        [changes_ reloadData];
    if (tag_ != 5 && search_ != nil)
        [search_ reloadData];

    [book_ reloadData];
}

- (void) _reloadData {
    UIView *block();

    static bool loaded(false);
    UIProgressHUD *hud([self addProgressHUD]);
    [hud setText:(loaded ? UCLocalize("RELOADING_DATA") : UCLocalize("LOADING_DATA"))];

    [database_ yieldToSelector:@selector(reloadData) withObject:nil];
    _trace();

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

    if (changes != 0) {
        NSString *badge([[NSNumber numberWithInt:changes] stringValue]);
        [toolbar_ setBadgeValue:badge forButton:3];
        if ([toolbar_ respondsToSelector:@selector(setBadgeAnimated:forButton:)])
            [toolbar_ setBadgeAnimated:([essential_ count] != 0) forButton:3];
        if ([self respondsToSelector:@selector(setApplicationBadge:)])
            [self setApplicationBadge:badge];
        else
            [self setApplicationBadgeString:badge];
    } else {
        [toolbar_ setBadgeValue:nil forButton:3];
        if ([toolbar_ respondsToSelector:@selector(setBadgeAnimated:forButton:)])
            [toolbar_ setBadgeAnimated:NO forButton:3];
        if ([self respondsToSelector:@selector(removeApplicationBadge)])
            [self removeApplicationBadge];
        else // XXX: maybe use setApplicationBadgeString also?
            [self setApplicationIconBadgeNumber:0];
    }

    Queuing_ = false;
    [toolbar_ setBadgeValue:nil forButton:4];

    [self _updateData];

    if (loaded || ManualRefresh) loaded:
        [self _loaded];
    else {
        loaded = true;

        if (NSDate *update = [Metadata_ objectForKey:@"LastUpdate"]) {
            NSTimeInterval interval([update timeIntervalSinceNow]);
            if (interval <= 0 && interval > -(15*60))
                goto loaded;
        }

        [book_ update];
    }
}

- (void) updateData {
    [database_ setVisible];
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

    [progress_
        detachNewThreadSelector:@selector(update_)
        toTarget:self
        withObject:nil
        title:UCLocalize("UPDATING_SOURCES")
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

- (bool) perform {
    if (![database_ prepare])
        return false;

    confirm_ = [[RVBook alloc] initWithFrame:[self popUpBounds]];
    [confirm_ setDelegate:self];

    ConfirmationView *page([[[ConfirmationView alloc] initWithBook:confirm_ database:database_] autorelease]);
    [page setDelegate:self];

    [confirm_ setPage:page];
    [self popUpBook:confirm_];

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

- (void) cancel {
    [self slideUp:[[[UIActionSheet alloc]
        initWithTitle:nil
        buttons:[NSArray arrayWithObjects:UCLocalize("CONTINUE_QUEUING"), UCLocalize("CANCEL_CLEAR"), nil]
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
        title:UCLocalize("RUNNING")
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
    CydiaBrowserView *browser = [[[_class alloc] initWithBook:book_] autorelease];
    [browser loadURL:url];
    return browser;
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
    } else if (tag_ == 2)
        [[self sectionsView] resetView];

    switch (tag) {
        case 1: _setHomePage(self); break;

        case 2: [self setPage:[self sectionsView]]; break;
        case 3: [self setPage:changes_]; break;
        case 4: [self setPage:manage_]; break;
        case 5: [self setPage:search_]; break;

        _nodefault
    }

    tag_ = tag;
}

- (void) askForSettings {
    NSString *parenthetical(UCLocalize("PARENTHETICAL"));

    CYActionSheet *role([[[CYActionSheet alloc]
        initWithTitle:UCLocalize("WHO_ARE_YOU")
        buttons:[NSArray arrayWithObjects:
            [NSString stringWithFormat:parenthetical, UCLocalize("USER"), UCLocalize("USER_EX")],
            [NSString stringWithFormat:parenthetical, UCLocalize("HACKER"), UCLocalize("HACKER_EX")],
            [NSString stringWithFormat:parenthetical, UCLocalize("DEVELOPER"), UCLocalize("DEVELOPER_EX")],
        nil]
        defaultButtonIndex:-1
    ] autorelease]);

    [role setBodyText:UCLocalize("ROLE_EX")];

    int button([role yieldToPopupAlertAnimated:YES]);

    switch (button) {
        case 1: Role_ = @"User"; break;
        case 2: Role_ = @"Hacker"; break;
        case 3: Role_ = @"Developer"; break;

        _nodefault
    }

    Settings_ = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        Role_, @"Role",
    nil];

    [Metadata_ setObject:Settings_ forKey:@"Settings"];

    Changed_ = true;

    [role dismiss];
}

- (void) setPackageView:(PackageView *)view {
    WebThreadLock();
    [view setPackage:nil];
#if RecyclePackageViews
    if ([details_ count] < 3)
        [details_ addObject:view];
#endif
    WebThreadUnlock();
}

- (PackageView *) _packageView {
    return [[[PackageView alloc] initWithBook:book_ database:database_] autorelease];
}

- (PackageView *) packageView {
#if RecyclePackageViews
    PackageView *view;
    size_t count([details_ count]);

    if (count == 0) {
        view = [self _packageView];
      renew:
        [details_ addObject:[self _packageView]];
    } else {
        view = [[[details_ lastObject] retain] autorelease];
        [details_ removeLastObject];
        if (count == 1)
            goto renew;
    }

    return view;
#else
    return [self _packageView];
#endif
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

            _nodefault
        }

        [sheet dismiss];

        @synchronized (self) {
            if (clear)
                [self _reloadData];
            else {
                Queuing_ = true;
                [toolbar_ setBadgeValue:UCLocalize("Q_D") forButton:4];
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

            _nodefault
        }

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

            _nodefault
        }

        [sheet dismiss];
    }
}

- (void) system:(NSString *)command { _pooled
    system([command UTF8String]);
}

- (void) applicationWillSuspend {
    [database_ clean];
    [super applicationWillSuspend];
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

- (RVPage *) pageForPackage:(NSString *)name {
    if (Package *package = [database_ packageWithName:name]) {
        PackageView *view([self packageView]);
        [view setPackage:package];
        return view;
    } else {
        NSURL *url([NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"unknown" ofType:@"html"]]);
        url = [NSURL URLWithString:[[url absoluteString] stringByAppendingString:[NSString stringWithFormat:@"?%@", name]]];
        return [self _pageForURL:url withClass:[CydiaBrowserView class]];
    }
}

- (RVPage *) pageForURL:(NSURL *)url hasTag:(int *)tag {
    if (tag != NULL)
        tag = 0;

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
        return [[[AddSourceView alloc] initWithBook:book_ database:database_] autorelease];
    else if ([path isEqualToString:@"/storage"])
        return [self _pageForURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"storage" ofType:@"html"]] withClass:[CydiaBrowserView class]];
    else if ([path isEqualToString:@"/sources"])
        return [[[SourceTable alloc] initWithBook:book_ database:database_] autorelease];
    else if ([path isEqualToString:@"/packages"])
        return [[[InstalledView alloc] initWithBook:book_ database:database_] autorelease];
    else if ([path hasPrefix:@"/url/"])
        return [self _pageForURL:[NSURL URLWithString:[path substringFromIndex:5]] withClass:[CydiaBrowserView class]];
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
        [toolbar_ showSelectionForButton:tag];
        tag_ = tag;
    }
}

- (void) applicationDidFinishLaunching:(id)unused {
    [BrowserView _initialize];

    [NSURLProtocol registerClass:[CydiaURLProtocol class]];

    Font12_ = [[UIFont systemFontOfSize:12] retain];
    Font12Bold_ = [[UIFont boldSystemFontOfSize:12] retain];
    Font14_ = [[UIFont systemFontOfSize:14] retain];
    Font18Bold_ = [[UIFont boldSystemFontOfSize:18] retain];
    Font22Bold_ = [[UIFont boldSystemFontOfSize:22] retain];

    tag_ = 1;

    essential_ = [[NSMutableArray alloc] initWithCapacity:4];
    broken_ = [[NSMutableArray alloc] initWithCapacity:4];

    window_ = [[UIWindow alloc] initWithContentRect:[UIHardware fullScreenApplicationContentRect]];
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
        //readlink("/usr/bin", NULL, 0) == -1 && errno == EINVAL ||
        readlink("/usr/include", NULL, 0) == -1 && errno == EINVAL ||
        readlink("/usr/lib/pam", NULL, 0) == -1 && errno == EINVAL ||
        readlink("/usr/libexec", NULL, 0) == -1 && errno == EINVAL ||
        readlink("/usr/share", NULL, 0) == -1 && errno == EINVAL ||
        //readlink("/var/lib", NULL, 0) == -1 && errno == EINVAL ||
        false
    ) {
        [self setIdleTimerDisabled:YES];

        hud_ = [self addProgressHUD];
        [hud_ setText:@"Reorganizing\n\nWill Automatically\nClose When Done"];
        [self setStatusBarShowsProgress:YES];

        [self yieldToSelector:@selector(system:) withObject:@"/usr/libexec/cydia/free.sh"];

        [self setStatusBarShowsProgress:NO];
        [self removeProgressHUD:hud_];
        hud_ = nil;

        if (ExecFork() == 0) {
            execlp("launchctl", "launchctl", "stop", "com.apple.SpringBoard", NULL);
            perror("launchctl stop");
        }

        return;
    }

    if (Role_ == nil)
        [self askForSettings];

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
            UCLocalize("SECTIONS"), kUIButtonBarButtonTitle,
            @"0", kUIButtonBarButtonType,
        nil],

        [NSDictionary dictionaryWithObjectsAndKeys:
            @"buttonBarItemTapped:", kUIButtonBarButtonAction,
            @"changes-up.png", kUIButtonBarButtonInfo,
            @"changes-dn.png", kUIButtonBarButtonSelectedInfo,
            [NSNumber numberWithInt:3], kUIButtonBarButtonTag,
            self, kUIButtonBarButtonTarget,
            UCLocalize("CHANGES"), kUIButtonBarButtonTitle,
            @"0", kUIButtonBarButtonType,
        nil],

        [NSDictionary dictionaryWithObjectsAndKeys:
            @"buttonBarItemTapped:", kUIButtonBarButtonAction,
            @"manage-up.png", kUIButtonBarButtonInfo,
            @"manage-dn.png", kUIButtonBarButtonSelectedInfo,
            [NSNumber numberWithInt:4], kUIButtonBarButtonTag,
            self, kUIButtonBarButtonTarget,
            UCLocalize("MANAGE"), kUIButtonBarButtonTitle,
            @"0", kUIButtonBarButtonType,
        nil],

        [NSDictionary dictionaryWithObjectsAndKeys:
            @"buttonBarItemTapped:", kUIButtonBarButtonAction,
            @"search-up.png", kUIButtonBarButtonInfo,
            @"search-dn.png", kUIButtonBarButtonSelectedInfo,
            [NSNumber numberWithInt:5], kUIButtonBarButtonTag,
            self, kUIButtonBarButtonTarget,
            UCLocalize("SEARCH"), kUIButtonBarButtonTitle,
            @"0", kUIButtonBarButtonType,
        nil],
    nil];

    toolbar_ = [[UIToolbar alloc]
        initInView:overlay_
        withFrame:CGRectMake(
            0, screenrect.size.height - ButtonBarHeight_,
            screenrect.size.width, ButtonBarHeight_
        )
        withItemList:buttonitems
    ];

    [toolbar_ setDelegate:self];
    [toolbar_ setBarStyle:1];
    [toolbar_ setButtonBarTrackingMode:2];

    int buttons[5] = {1, 2, 3, 4, 5};
    [toolbar_ registerButtonGroup:0 withButtons:buttons withCount:5];
    [toolbar_ showButtonGroup:0 withDuration:0];

    for (int i = 0; i != 5; ++i)
        [[toolbar_ viewWithTag:(i + 1)] setFrame:CGRectMake(
            i * 64 + 2, 1, 60, ButtonBarHeight_
        )];

    [toolbar_ showSelectionForButton:1];
    [overlay_ addSubview:toolbar_];

    [UIKeyboard initImplementationNow];
    CGSize keysize = [UIKeyboard defaultSize];
    CGRect keyrect = {{0, [overlay_ bounds].size.height}, keysize};
    keyboard_ = [[UIKeyboard alloc] initWithFrame:keyrect];
    [overlay_ addSubview:keyboard_];

    [underlay_ addSubview:overlay_];

    [self reloadData];

    [self sectionsView];
    changes_ = [[ChangesView alloc] initWithBook:book_ database:database_];
    search_ = [[SearchView alloc] initWithBook:book_ database:database_];

    manage_ = (ManageView *) [[self
        _pageForURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"manage" ofType:@"html"]]
        withClass:[ManageView class]
    ] retain];

#if RecyclePackageViews
    details_ = [[NSMutableArray alloc] initWithCapacity:4];
    [details_ addObject:[self _packageView]];
    [details_ addObject:[self _packageView]];
#endif

    PrintTimes();

    _setHomePage(self);
}

- (void) showKeyboard:(BOOL)show {
    CGSize keysize([UIKeyboard defaultSize]);
    CGRect keydown = {{0, [overlay_ bounds].size.height}, keysize};
    CGRect keyup(keydown);
    keyup.origin.y -= keysize.height;

    UIFrameAnimation *animation([[[UIFrameAnimation alloc] initWithTarget:keyboard_] autorelease]);
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
    [alert presentSheetInView:overlay_];
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

    Finishes_ = [NSArray arrayWithObjects:@"return", @"reopen", @"restart", @"reload", @"reboot", nil];

    if (substrate && access("/Applications/WinterBoard.app/WinterBoard.dylib", F_OK) == 0)
        dlopen("/Applications/WinterBoard.app/WinterBoard.dylib", RTLD_LAZY | RTLD_GLOBAL);
    /*if (substrate && access("/Library/MobileSubstrate/MobileSubstrate.dylib", F_OK) == 0)
        dlopen("/Library/MobileSubstrate/MobileSubstrate.dylib", RTLD_LAZY | RTLD_GLOBAL);*/

    if (access("/tmp/.cydia.fw", F_OK) == 0) {
        unlink("/tmp/.cydia.fw");
        goto firmware;
    } else if (access("/User", F_OK) != 0) {
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
    _config->Set("Acquire::http::Timeout", 15);
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

    UIKeyboardDisableAutomaticAppearance();
    /* }}} */

    Colon_ = UCLocalize("COLON_DELIMITED");
    Error_ = UCLocalize("ERROR");
    Warning_ = UCLocalize("WARNING");

    _trace();
    int value = UIApplicationMain(argc, argv, @"Cydia", @"Cydia");

    CGColorSpaceRelease(space_);
    CFRelease(Locale_);

    return value;
}
