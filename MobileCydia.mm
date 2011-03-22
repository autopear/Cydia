/* Cydia - iPhone UIKit Front-End for Debian APT
 * Copyright (C) 2008-2011  Jay Freeman (saurik)
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
#include "CyteKit/UCPlatform.h"
#include "CyteKit/Localize.h"

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

#include <QuartzCore/CALayer.h>

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
#include <sys/reboot.h>

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

#include <Cytore.hpp>
#include "Sources.h"

#include <CydiaSubstrate/CydiaSubstrate.h>
#include "Menes/Menes.h"

#include "CyteKit/IndirectDelegate.h"
#include "CyteKit/PerlCompatibleRegEx.hpp"
#include "CyteKit/TableViewCell.h"
#include "CyteKit/WebScriptObject-Cyte.h"
#include "CyteKit/WebViewController.h"
#include "CyteKit/WebViewTableViewCell.h"
#include "CyteKit/stringWithUTF8Bytes.h"

#include "Cydia/MIMEAddress.h"
#include "Cydia/LoadingViewController.h"
#include "Cydia/ProgressEvent.h"

#include "SDURLCache/SDURLCache.h"
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

extern NSString *Cydia_;

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
#define AlwaysReload (0 && !ForRelease)
#define TryIndexedCollation (0 && !ForRelease)

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

// Hash Functions/Structures {{{
extern "C" uint32_t hashlittle(const void *key, size_t length, uint32_t initval = 0);

union SplitHash {
    uint32_t u32;
    uint16_t u16[2];
};
// }}}

static bool ShowPromoted_;

static NSString *Colon_;
NSString *Elision_;
static NSString *Error_;
static NSString *Warning_;

static bool AprilFools_;

static const NSUInteger UIViewAutoresizingFlexibleBoth(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);

static _finline NSString *CydiaURL(NSString *path) {
    char page[26];
    page[0] = 'h'; page[1] = 't'; page[2] = 't'; page[3] = 'p'; page[4] = 's';
    page[5] = ':'; page[6] = '/'; page[7] = '/'; page[8] = 'c'; page[9] = 'y';
    page[10] = 'd'; page[11] = 'i'; page[12] = 'a'; page[13] = '.'; page[14] = 's';
    page[15] = 'a'; page[16] = 'u'; page[17] = 'r'; page[18] = 'i'; page[19] = 'k';
    page[20] = '.'; page[21] = 'c'; page[22] = 'o'; page[23] = 'm'; page[24] = '/';
    page[25] = '\0';
    return [[NSString stringWithUTF8String:page] stringByAppendingString:path];
}

static void ReapZombie(pid_t pid) {
    int status;
  wait:
    if (waitpid(pid, &status, 0) == -1)
        if (errno == EINTR)
            goto wait;
        else _assert(false);
}

static _finline void UpdateExternalStatus(uint64_t newStatus) {
    int notify_token;
    if (notify_register_check("com.saurik.Cydia.status", &notify_token) == NOTIFY_STATUS_OK) {
        notify_set_state(notify_token, newStatus);
        notify_cancel(notify_token);
    }
    notify_post("com.saurik.Cydia.status");
}

static CGFloat CYStatusBarHeight() {
    CGSize size([[UIApplication sharedApplication] statusBarFrame].size);
    return UIInterfaceOrientationIsPortrait([[UIApplication sharedApplication] statusBarOrientation]) ? size.height : size.width;
}

/* NSForcedOrderingSearch doesn't work on the iPhone */
static const NSStringCompareOptions MatchCompareOptions_ = NSLiteralSearch | NSCaseInsensitiveSearch;
static const NSStringCompareOptions LaxCompareOptions_ = NSNumericSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch | NSCaseInsensitiveSearch;
static const CFStringCompareFlags LaxCompareFlags_ = kCFCompareCaseInsensitive | kCFCompareNonliteral | kCFCompareLocalized | kCFCompareNumerically | kCFCompareWidthInsensitive | kCFCompareForcedOrdering;

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
- (NSComparisonResult) compareByPath:(NSString *)other;
- (NSString *) stringByAddingPercentEscapesIncludingReserved;
@end

@implementation NSString (Cydia)

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

    void copy(apr_pool_t *pool) {
        char *temp(reinterpret_cast<char *>(apr_palloc(pool, size_ + 1)));
        memcpy(temp, data_, size_);
        temp[size_] = '\0';
        data_ = temp;
    }

    void set(apr_pool_t *pool, const char *data, size_t size) {
        if (size == 0)
            clear();
        else {
            clear_();

            data_ = const_cast<char *>(data);
            size_ = size;

            if (pool != NULL)
                copy(pool);
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

    _finline operator const char *() {
        return reinterpret_cast<const char *>(data_);
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

static const NSString *UI_;

static int Finish_;
static bool RestartSubstrate_;
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

static BOOL Advanced_;
static BOOL Ignored_;

static _H<UIFont> Font12_;
static _H<UIFont> Font12Bold_;
static _H<UIFont> Font14_;
static _H<UIFont> Font18Bold_;
static _H<UIFont> Font22Bold_;

static const char *Machine_ = NULL;
static _H<NSString> System_;
static NSString *SerialNumber_ = nil;
static NSString *ChipID_ = nil;
static NSString *BBSNum_ = nil;
static _H<NSString> Token_;
static NSString *UniqueID_ = nil;
static _H<NSString> UserAgent_;
static _H<NSString> Product_;
static _H<NSString> Safari_;

static CFLocaleRef Locale_;
static NSArray *Languages_;
static CGColorSpaceRef space_;

static NSDictionary *SectionMap_;
static NSMutableDictionary *Metadata_;
static _transient NSMutableDictionary *Settings_;
static _transient NSString *Role_;
static _transient NSMutableDictionary *Packages_;
static _transient NSMutableDictionary *Values_;
static _transient NSMutableDictionary *Sections_;
_H<NSMutableDictionary> Sources_;
static _transient NSNumber *Version_;
bool Changed_;
static time_t now_;

bool IsWildcat_;
static CGFloat ScreenScale_;
static NSString *Idiom_;
static _H<NSString> Firmware_;
static NSString *Major_;

static _H<NSMutableDictionary> SessionData_;
static _H<NSObject> HostConfig_;
static _H<NSMutableSet> BridgedHosts_;
static _H<NSMutableSet> TokenHosts_;
static _H<NSMutableSet> InsecureHosts_;
static _H<NSMutableSet> PipelinedHosts_;
static _H<NSMutableSet> CachedURLs_;

static NSString *kCydiaProgressEventTypeError = @"Error";
static NSString *kCydiaProgressEventTypeInformation = @"Information";
static NSString *kCydiaProgressEventTypeStatus = @"Status";
static NSString *kCydiaProgressEventTypeWarning = @"Warning";
/* }}} */

/* Display Helpers {{{ */
inline float Interpolate(float begin, float end, float fraction) {
    return (end - begin) * fraction + begin;
}

static _finline const char *StripVersion_(const char *version) {
    const char *colon(strchr(version, ':'));
    return colon == NULL ? version : colon + 1;
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
    NSDictionary *metadata([Sections_ objectForKey:(section ?: @"")]);
    NSNumber *hidden(metadata == nil ? nil : [metadata objectForKey:@"Hidden"]);
    return hidden == nil || ![hidden boolValue];
}

static NSObject *CYIOGetValue(const char *path, NSString *property) {
    io_registry_entry_t entry(IORegistryEntryFromPath(kIOMasterPortDefault, path));
    if (entry == MACH_PORT_NULL)
        return nil;

    CFTypeRef value(IORegistryEntryCreateCFProperty(entry, (CFStringRef) property, kCFAllocatorDefault, 0));
    IOObjectRelease(entry);

    if (value == NULL)
        return nil;
    return [(id) value autorelease];
}

static NSString *CYHex(NSData *data, bool reverse = false) {
    if (data == nil)
        return nil;

    size_t length([data length]);
    uint8_t bytes[length];
    [data getBytes:bytes];

    char string[length * 2 + 1];
    for (size_t i(0); i != length; ++i)
        sprintf(string + i * 2, "%.2x", bytes[reverse ? length - i - 1 : i]);

    return [NSString stringWithUTF8String:string];
}

@class Cydia;

/* Delegate Prototypes {{{ */
@class Package;
@class Source;
@class CydiaProgressEvent;

@protocol DatabaseDelegate
- (void) repairWithSelector:(SEL)selector;
- (void) setConfigurationData:(NSString *)data;
- (void) addProgressEventOnMainThread:(CydiaProgressEvent *)event forTask:(NSString *)task;
@end

@class CYPackageController;

@protocol CydiaDelegate
- (void) returnToCydia;
- (void) saveState;
- (void) retainNetworkActivityIndicator;
- (void) releaseNetworkActivityIndicator;
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
- (void) addSource:(NSDictionary *)source;
- (void) addTrivialSource:(NSString *)href;
- (void) showSettings;
- (UIProgressHUD *) addProgressHUD;
- (void) removeProgressHUD:(UIProgressHUD *)hud;
- (CyteViewController *) pageForPackage:(NSString *)name;
- (void) showActionSheet:(UIActionSheet *)sheet fromItem:(UIBarButtonItem *)item;
- (void) reloadDataWithInvocation:(NSInvocation *)invocation;
@end
/* }}} */

/* Status Delegation {{{ */
class Status :
    public pkgAcquireStatus
{
  private:
    _transient NSObject<ProgressDelegate> *delegate_;
    bool cancelled_;

  public:
    Status() :
        delegate_(nil),
        cancelled_(false)
    {
    }

    void setDelegate(NSObject<ProgressDelegate> *delegate) {
        delegate_ = delegate;
    }

    NSObject<ProgressDelegate> *getDelegate() const {
        return delegate_;
    }

    virtual bool MediaChange(std::string media, std::string drive) {
        return false;
    }

    virtual void IMSHit(pkgAcquire::ItemDesc &item) {
        Done(item);
    }

    virtual void Fetch(pkgAcquire::ItemDesc &item) {
        NSString *name([NSString stringWithUTF8String:item.ShortDesc.c_str()]);
        CydiaProgressEvent *event([CydiaProgressEvent eventWithMessage:[NSString stringWithFormat:UCLocalize("DOWNLOADING_"), name] ofType:kCydiaProgressEventTypeStatus forItem:item]);
        [delegate_ performSelectorOnMainThread:@selector(addProgressEvent:) withObject:event waitUntilDone:YES];
    }

    virtual void Done(pkgAcquire::ItemDesc &item) {
        NSString *name([NSString stringWithUTF8String:item.ShortDesc.c_str()]);
        CydiaProgressEvent *event([CydiaProgressEvent eventWithMessage:[NSString stringWithFormat:Colon_, UCLocalize("DONE"), name] ofType:kCydiaProgressEventTypeStatus forItem:item]);
        [delegate_ performSelectorOnMainThread:@selector(addProgressEvent:) withObject:event waitUntilDone:YES];
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

        CydiaProgressEvent *event([CydiaProgressEvent eventWithMessage:[NSString stringWithUTF8String:error.c_str()] ofType:kCydiaProgressEventTypeError forItem:item]);
        [delegate_ performSelectorOnMainThread:@selector(addProgressEvent:) withObject:event waitUntilDone:YES];
    }

    virtual bool Pulse(pkgAcquire *Owner) {
        bool value = pkgAcquireStatus::Pulse(Owner);

        double percent(
            double(CurrentBytes + CurrentItems) /
            double(TotalBytes + TotalItems)
        );

        [delegate_ performSelectorOnMainThread:@selector(setProgressStatus:) withObject:[NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithDouble:percent], @"Percent",

            [NSNumber numberWithDouble:CurrentBytes], @"Current",
            [NSNumber numberWithDouble:TotalBytes], @"Total",
            [NSNumber numberWithDouble:CurrentCPS], @"Speed",
        nil] waitUntilDone:YES];

        if (value && ![delegate_ isProgressCancelled])
            return true;
        else {
            cancelled_ = true;
            return false;
        }
    }

    _finline bool WasCancelled() const {
        return cancelled_;
    }

    virtual void Start() {
        pkgAcquireStatus::Start();
        [delegate_ performSelectorOnMainThread:@selector(setProgressCancellable:) withObject:[NSNumber numberWithBool:YES] waitUntilDone:YES];
    }

    virtual void Stop() {
        pkgAcquireStatus::Stop();
        [delegate_ performSelectorOnMainThread:@selector(setProgressCancellable:) withObject:[NSNumber numberWithBool:NO] waitUntilDone:YES];
        [delegate_ performSelectorOnMainThread:@selector(setProgressStatus:) withObject:nil waitUntilDone:YES];
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

    SourceMap sourceMap_;
    _H<NSMutableArray> sourceList_;

    CFMutableArrayRef packages_;

    _transient NSObject<DatabaseDelegate> *delegate_;
    _transient NSObject<ProgressDelegate> *progress_;

    Status status_;

    int cydiafd_;
    int statusfd_;
    FILE *input_;

    std::map<const char *, _H<NSString> > sections_;
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
- (Source *) sourceWithKey:(NSString *)key;
- (void) reloadDataWithInvocation:(NSInvocation *)invocation;

- (void) configure;
- (bool) prepare;
- (void) perform;
- (bool) upgrade;
- (void) update;

- (void) updateWithStatus:(Status &)status;

- (void) setDelegate:(NSObject<DatabaseDelegate> *)delegate;

- (void) setProgressDelegate:(NSObject<ProgressDelegate> *)delegate;
- (NSObject<ProgressDelegate> *) progressDelegate;

- (Source *) getSource:(pkgCache::PkgFileIterator)file;

- (NSString *) mappedSectionForPointer:(const char *)pointer;

@end
/* }}} */
/* ProgressEvent Implementation {{{ */
@implementation CydiaProgressEvent

+ (CydiaProgressEvent *) eventWithMessage:(NSString *)message ofType:(NSString *)type {
    return [[[CydiaProgressEvent alloc] initWithMessage:message ofType:type] autorelease];
}

+ (CydiaProgressEvent *) eventWithMessage:(NSString *)message ofType:(NSString *)type forPackage:(NSString *)package {
    CydiaProgressEvent *event([self eventWithMessage:message ofType:type]);
    [event setPackage:package];
    return event;
}

+ (CydiaProgressEvent *) eventWithMessage:(NSString *)message ofType:(NSString *)type forItem:(pkgAcquire::ItemDesc &)item {
    CydiaProgressEvent *event([self eventWithMessage:message ofType:type]);

    NSString *description([NSString stringWithUTF8String:item.Description.c_str()]);
    NSArray *fields([description componentsSeparatedByString:@" "]);
    [event setItem:fields];

    if ([fields count] > 3) {
        [event setPackage:[fields objectAtIndex:2]];
        [event setVersion:[fields objectAtIndex:3]];
    }

    [event setURL:[NSString stringWithUTF8String:item.URI.c_str()]];

    return event;
}

+ (NSArray *) _attributeKeys {
    return [NSArray arrayWithObjects:
        @"item",
        @"message",
        @"package",
        @"type",
        @"url",
        @"version",
    nil];
}

- (NSArray *) attributeKeys {
    return [[self class] _attributeKeys];
}

+ (BOOL) isKeyExcludedFromWebScript:(const char *)name {
    return ![[self _attributeKeys] containsObject:[NSString stringWithUTF8String:name]] && [super isKeyExcludedFromWebScript:name];
}

- (id) initWithMessage:(NSString *)message ofType:(NSString *)type {
    if ((self = [super init]) != nil) {
        message_ = message;
        type_ = type;
    } return self;
}

- (NSString *) message {
    return message_;
}

- (NSString *) type {
    return type_;
}

- (NSArray *) item {
    return (id) item_ ?: [NSNull null];
}

- (void) setItem:(NSArray *)item {
    item_ = item;
}

- (NSString *) package {
    return (id) package_ ?: [NSNull null];
}

- (void) setPackage:(NSString *)package {
    package_ = package;
}

- (NSString *) url {
    return (id) url_ ?: [NSNull null];
}

- (void) setURL:(NSString *)url {
    url_ = url;
}

- (void) setVersion:(NSString *)version {
    version_ = version;
}

- (NSString *) version {
    return (id) version_ ?: [NSNull null];
}

- (NSString *) compound:(NSString *)value {
    if (value != nil) {
        NSString *mode(nil); {
            NSString *type([self type]);
            if ([type isEqualToString:kCydiaProgressEventTypeError])
                mode = UCLocalize("ERROR");
            else if ([type isEqualToString:kCydiaProgressEventTypeWarning])
                mode = UCLocalize("WARNING");
        }

        if (mode != nil)
            value = [NSString stringWithFormat:UCLocalize("COLON_DELIMITED"), mode, value];
    }

    return value;
}

- (NSString *) compoundMessage {
    return [self compound:[self message]];
}

- (NSString *) compoundTitle {
    NSString *title;

    if (package_ == nil)
        title = nil;
    else if (Package *package = [[Database sharedInstance] packageWithName:package_])
        title = [package name];
    else
        title = package_;

    return [self compound:title];
}

@end
/* }}} */

// Cytore Definitions {{{
struct PackageValue :
    Cytore::Block
{
    Cytore::Offset<PackageValue> next_;

    uint32_t index_ : 23;
    uint32_t subscribed_ : 1;
    uint32_t : 8;

    int32_t first_;
    int32_t last_;

    uint16_t vhash_;
    uint16_t nhash_;

    char version_[8];
    char name_[];
};

struct MetaValue :
    Cytore::Block
{
    uint32_t active_;
    Cytore::Offset<PackageValue> packages_[1 << 16];
};

static Cytore::File<MetaValue> MetaFile_;
// }}}
// Cytore Helper Functions {{{
static PackageValue *PackageFind(const char *name, size_t length, bool *fail = NULL) {
    SplitHash nhash = { hashlittle(name, length) };

    PackageValue *metadata;

    Cytore::Offset<PackageValue> *offset(&MetaFile_->packages_[nhash.u16[0]]);
    offset: if (offset->IsNull()) {
        *offset = MetaFile_.New<PackageValue>(length + 1);
        metadata = &MetaFile_.Get(*offset);

        if (metadata == NULL) {
            if (fail != NULL)
                *fail = true;

            metadata = new PackageValue();
            memset(metadata, 0, sizeof(*metadata));
        }

        memcpy(metadata->name_, name, length + 1);
        metadata->nhash_ = nhash.u16[1];
    } else {
        metadata = &MetaFile_.Get(*offset);

        if (metadata->nhash_ != nhash.u16[1] || strncmp(metadata->name_, name, length + 1) != 0) {
            offset = &metadata->next_;
            goto offset;
        }
    }

    return metadata;
}

static void PackageImport(const void *key, const void *value, void *context) {
    bool &fail(*reinterpret_cast<bool *>(context));

    char buffer[1024];
    if (!CFStringGetCString((CFStringRef) key, buffer, sizeof(buffer), kCFStringEncodingUTF8)) {
        NSLog(@"failed to import package %@", key);
        return;
    }

    PackageValue *metadata(PackageFind(buffer, strlen(buffer), &fail));
    NSDictionary *package((NSDictionary *) value);

    if (NSNumber *subscribed = [package objectForKey:@"IsSubscribed"])
        if ([subscribed boolValue] && !metadata->subscribed_)
            metadata->subscribed_ = true;

    if (NSDate *date = [package objectForKey:@"FirstSeen"]) {
        time_t time([date timeIntervalSince1970]);
        if (metadata->first_ > time || metadata->first_ == 0)
            metadata->first_ = time;
    }

    NSDate *date([package objectForKey:@"LastSeen"]);
    NSString *version([package objectForKey:@"LastVersion"]);

    if (date != nil && version != nil) {
        time_t time([date timeIntervalSince1970]);
        if (metadata->last_ < time || metadata->last_ == 0)
            if (CFStringGetCString((CFStringRef) version, buffer, sizeof(buffer), kCFStringEncodingUTF8)) {
                size_t length(strlen(buffer));
                uint16_t vhash(hashlittle(buffer, length));

                size_t capped(std::min<size_t>(8, length));
                char *latest(buffer + length - capped);

                strncpy(metadata->version_, latest, sizeof(metadata->version_));
                metadata->vhash_ = vhash;

                metadata->last_ = time;
            }
    }
}
// }}}

/* Source Class {{{ */
@interface Source : NSObject {
    unsigned era_;
    Database *database_;
    metaIndex *index_;

    CYString depiction_;
    CYString description_;
    CYString label_;
    CYString origin_;
    CYString support_;

    CYString uri_;
    CYString distribution_;
    CYString type_;
    CYString base_;
    CYString version_;

    _H<NSString> host_;
    _H<NSString> authority_;

    CYString defaultIcon_;

    _H<NSDictionary> record_;
    BOOL trusted_;
}

- (Source *) initWithMetaIndex:(metaIndex *)index forDatabase:(Database *)database inPool:(apr_pool_t *)pool;

- (NSComparisonResult) compareByName:(Source *)source;

- (NSString *) depictionForPackage:(NSString *)package;
- (NSString *) supportForPackage:(NSString *)package;

- (NSDictionary *) record;
- (BOOL) trusted;

- (NSString *) rooturi;
- (NSString *) distribution;
- (NSString *) type;

- (NSString *) key;
- (NSString *) host;

- (NSString *) name;
- (NSString *) shortDescription;
- (NSString *) label;
- (NSString *) origin;
- (NSString *) version;

- (NSString *) defaultIcon;
- (NSURL *) iconURL;

@end

@implementation Source

- (void) _clear {
    uri_.clear();
    distribution_.clear();
    type_.clear();

    base_.clear();

    description_.clear();
    label_.clear();
    origin_.clear();
    depiction_.clear();
    support_.clear();
    version_.clear();
    defaultIcon_.clear();

    record_ = nil;
    host_ = nil;
    authority_ = nil;
}

+ (NSString *) webScriptNameForSelector:(SEL)selector {
    if (false);
    else if (selector == @selector(addSection:))
        return @"addSection";
    else if (selector == @selector(getField:))
        return @"getField";
    else if (selector == @selector(removeSection:))
        return @"removeSection";
    else if (selector == @selector(remove))
        return @"remove";
    else
        return nil;
}

+ (BOOL) isSelectorExcludedFromWebScript:(SEL)selector {
    return [self webScriptNameForSelector:selector] == nil;
}

+ (NSArray *) _attributeKeys {
    return [NSArray arrayWithObjects:
        @"baseuri",
        @"distribution",
        @"host",
        @"key",
        @"iconuri",
        @"label",
        @"name",
        @"origin",
        @"rooturi",
        @"sections",
        @"shortDescription",
        @"trusted",
        @"type",
        @"version",
    nil];
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
        base_.set(pool, dindex->MetaIndexURI(""));

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

    NSURL *url([NSURL URLWithString:uri_]);

    host_ = [url host];
    if (host_ != nil)
        host_ = [host_ lowercaseString];

    if (host_ != nil)
        authority_ = host_;
    else
        authority_ = [url path];
}

- (Source *) initWithMetaIndex:(metaIndex *)index forDatabase:(Database *)database inPool:(apr_pool_t *)pool {
    if ((self = [super init]) != nil) {
        era_ = [database era];
        database_ = database;
        index_ = index;

        [self setMetaIndex:index inPool:pool];
    } return self;
}

- (NSString *) getField:(NSString *)name {
@synchronized (database_) {
    if ([database_ era] != era_ || index_ == NULL)
        return nil;

    debReleaseIndex *dindex(dynamic_cast<debReleaseIndex *>(index_));
    if (dindex == NULL)
        return nil;

    FileFd fd;
    if (!fd.Open(dindex->MetaIndexFile("Release"), FileFd::ReadOnly)) {
         _error->Discard();
         return nil;
    }

    pkgTagFile tags(&fd);

    pkgTagSection section;
    tags.Step(section);

    const char *start, *end;
    if (!section.Find([name UTF8String], start, end))
        return (NSString *) [NSNull null];

    return [NSString stringWithString:[(NSString *) CYStringCreate(start, end - start) autorelease]];
} }

- (NSComparisonResult) compareByName:(Source *)source {
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

- (NSArray *) sections {
    return record_ == nil ? (id) [NSNull null] : [record_ objectForKey:@"Sections"] ?: [NSArray array];
}

- (void) _addSection:(NSString *)section {
    if (record_ == nil)
        return;
    else if (NSMutableArray *sections = [record_ objectForKey:@"Sections"]) {
        if (![sections containsObject:section]) {
            [sections addObject:section];
            Changed_ = true;
        }
    } else {
        [record_ setObject:[NSMutableArray arrayWithObject:section] forKey:@"Sections"];
        Changed_ = true;
    }
}

- (bool) addSection:(NSString *)section {
    if (record_ == nil)
        return false;

    [self performSelectorOnMainThread:@selector(_addSection:) withObject:section waitUntilDone:NO];
    return true;
}

- (void) _removeSection:(NSString *)section {
    if (record_ == nil)
        return;

    if (NSMutableArray *sections = [record_ objectForKey:@"Sections"])
        if ([sections containsObject:section]) {
            [sections removeObject:section];
            Changed_ = true;
        }
}

- (bool) removeSection:(NSString *)section {
    if (record_ == nil)
        return false;

    [self performSelectorOnMainThread:@selector(_removeSection:) withObject:section waitUntilDone:NO];
    return true;
}

- (void) _remove {
    [Sources_ removeObjectForKey:[self key]];
    Changed_ = true;
}

- (bool) remove {
    bool value(record_ != nil);
    [self performSelectorOnMainThread:@selector(_remove) withObject:nil waitUntilDone:NO];
    return value;
}

- (NSDictionary *) record {
    return record_;
}

- (BOOL) trusted {
    return trusted_;
}

- (NSString *) rooturi {
    return uri_;
}

- (NSString *) distribution {
    return distribution_;
}

- (NSString *) type {
    return type_;
}

- (NSString *) baseuri {
    return base_.empty() ? nil : (id) base_;
}

- (NSString *) iconuri {
    if (NSString *base = [self baseuri])
        return [base stringByAppendingString:@"CydiaIcon.png"];

    return nil;
}

- (NSURL *) iconURL {
    if (NSString *uri = [self iconuri])
        return [NSURL URLWithString:uri];
    return nil;
}

- (NSString *) key {
    return [NSString stringWithFormat:@"%@:%@:%@", (NSString *) type_, (NSString *) uri_, (NSString *) distribution_];
}

- (NSString *) host {
    return host_;
}

- (NSString *) name {
    return origin_.empty() ? (id) authority_ : origin_;
}

- (NSString *) shortDescription {
    return description_;
}

- (NSString *) label {
    return label_.empty() ? (id) authority_ : label_;
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
/* CydiaOperation Class {{{ */
@interface CydiaOperation : NSObject {
    _H<NSString> operator_;
    _H<NSString> value_;
}

- (NSString *) operator;
- (NSString *) value;

@end

@implementation CydiaOperation

- (id) initWithOperator:(const char *)_operator value:(const char *)value {
    if ((self = [super init]) != nil) {
        operator_ = [NSString stringWithUTF8String:_operator];
        value_ = [NSString stringWithUTF8String:value];
    } return self;
}

+ (NSArray *) _attributeKeys {
    return [NSArray arrayWithObjects:
        @"operator",
        @"value",
    nil];
}

- (NSArray *) attributeKeys {
    return [[self class] _attributeKeys];
}

+ (BOOL) isKeyExcludedFromWebScript:(const char *)name {
    return ![[self _attributeKeys] containsObject:[NSString stringWithUTF8String:name]] && [super isKeyExcludedFromWebScript:name];
}

- (NSString *) operator {
    return operator_;
}

- (NSString *) value {
    return value_;
}

@end
/* }}} */
/* CydiaClause Class {{{ */
@interface CydiaClause : NSObject {
    _H<NSString> package_;
    _H<CydiaOperation> version_;
}

- (NSString *) package;
- (CydiaOperation *) version;

@end

@implementation CydiaClause

- (id) initWithIterator:(pkgCache::DepIterator &)dep {
    if ((self = [super init]) != nil) {
        package_ = [NSString stringWithUTF8String:dep.TargetPkg().Name()];

        if (const char *version = dep.TargetVer())
            version_ = [[[CydiaOperation alloc] initWithOperator:dep.CompType() value:version] autorelease];
        else
            version_ = (id) [NSNull null];
    } return self;
}

+ (NSArray *) _attributeKeys {
    return [NSArray arrayWithObjects:
        @"package",
        @"version",
    nil];
}

- (NSArray *) attributeKeys {
    return [[self class] _attributeKeys];
}

+ (BOOL) isKeyExcludedFromWebScript:(const char *)name {
    return ![[self _attributeKeys] containsObject:[NSString stringWithUTF8String:name]] && [super isKeyExcludedFromWebScript:name];
}

- (NSString *) package {
    return package_;
}

- (CydiaOperation *) version {
    return version_;
}

@end
/* }}} */
/* CydiaRelation Class {{{ */
@interface CydiaRelation : NSObject {
    _H<NSString> relationship_;
    _H<NSMutableArray> clauses_;
}

- (NSString *) relationship;
- (NSArray *) clauses;

@end

@implementation CydiaRelation

- (id) initWithIterator:(pkgCache::DepIterator &)dep {
    if ((self = [super init]) != nil) {
        relationship_ = [NSString stringWithUTF8String:dep.DepType()];
        clauses_ = [NSMutableArray arrayWithCapacity:8];

        pkgCache::DepIterator start;
        pkgCache::DepIterator end;
        dep.GlobOr(start, end); // ++dep

        _forever {
            [clauses_ addObject:[[[CydiaClause alloc] initWithIterator:start] autorelease]];

            // yes, seriously. (wtf?)
            if (start == end)
                break;
            ++start;
        }
    } return self;
}

+ (NSArray *) _attributeKeys {
    return [NSArray arrayWithObjects:
        @"clauses",
        @"relationship",
    nil];
}

- (NSArray *) attributeKeys {
    return [[self class] _attributeKeys];
}

+ (BOOL) isKeyExcludedFromWebScript:(const char *)name {
    return ![[self _attributeKeys] containsObject:[NSString stringWithUTF8String:name]] && [super isKeyExcludedFromWebScript:name];
}

- (NSString *) relationship {
    return relationship_;
}

- (NSArray *) clauses {
    return clauses_;
}

- (void) addClause:(CydiaClause *)clause {
    [clauses_ addObject:clause];
}

@end
/* }}} */
/* Package Class {{{ */
struct ParsedPackage {
    CYString md5sum_;
    CYString tagline_;

    CYString architecture_;
    CYString icon_;

    CYString depiction_;
    CYString homepage_;

    CYString sponsor_;
    CYString author_;

    CYString bugs_;
    CYString support_;
};

@interface Package : NSObject {
    uint32_t era_ : 25;
    uint32_t role_ : 3;
    uint32_t essential_ : 1;
    uint32_t obsolete_ : 1;
    uint32_t ignored_ : 1;
    uint32_t pooled_ : 1;

    apr_pool_t *pool_;

    uint32_t rank_;

    _transient Database *database_;

    pkgCache::VerIterator version_;
    pkgCache::PkgIterator iterator_;
    pkgCache::VerFileIterator file_;

    CYString id_;
    CYString name_;

    CYString latest_;
    CYString installed_;

    const char *section_;
    _transient NSString *section$_;

    _H<Source> source_;

    PackageValue *metadata_;
    ParsedPackage *parsed_;

    _H<NSMutableArray> tags_;
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

- (MIMEAddress *) maintainer;
- (size_t) size;
- (NSString *) longDescription;
- (NSString *) shortDescription;
- (unichar) index;

- (PackageValue *) metadata;
- (time_t) seen;

- (bool) subscribed;
- (bool) setSubscribed:(bool)subscribed;

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
- (MIMEAddress *) author;

- (NSString *) support;

- (NSArray *) files;
- (NSArray *) warnings;
- (NSArray *) applications;

- (Source *) source;

- (uint32_t) rank;
- (BOOL) matches:(NSArray *)query;

- (bool) hasSupportingRole;
- (BOOL) hasTag:(NSString *)tag;
- (NSString *) primaryPurpose;
- (NSArray *) purposes;
- (bool) isCommercial;

- (void) setIndex:(size_t)index;

- (CYString &) cyname;

- (uint32_t) compareBySection:(NSArray *)sections;

- (void) install;
- (void) remove;

- (bool) isUnfilteredAndSearchedForBy:(NSArray *)query;
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
        value.bits.timestamp = [self seen] >> 2;
        value.bits.ignored = 0;
        value.bits.upgradable = 0;
    }

    return _not(uint32_t) - value.key;
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
    if (!pooled_)
        apr_pool_destroy(pool_);
    if (parsed_ != NULL)
        delete parsed_;
    [super dealloc];
}

+ (NSString *) webScriptNameForSelector:(SEL)selector {
    if (false);
    else if (selector == @selector(clear))
        return @"clear";
    else if (selector == @selector(getField:))
        return @"getField";
    else if (selector == @selector(hasTag:))
        return @"hasTag";
    else if (selector == @selector(install))
        return @"install";
    else if (selector == @selector(remove))
        return @"remove";
    else
        return nil;
}

+ (BOOL) isSelectorExcludedFromWebScript:(SEL)selector {
    return [self webScriptNameForSelector:selector] == nil;
}

+ (NSArray *) _attributeKeys {
    return [NSArray arrayWithObjects:
        @"applications",
        @"architecture",
        @"author",
        @"depiction",
        @"essential",
        @"homepage",
        @"icon",
        @"id",
        @"installed",
        @"latest",
        @"longDescription",
        @"longSection",
        @"maintainer",
        @"md5sum",
        @"mode",
        @"name",
        @"purposes",
        @"relations",
        @"section",
        @"selection",
        @"shortDescription",
        @"shortSection",
        @"simpleSection",
        @"size",
        @"source",
        @"sponsor",
        @"state",
        @"support",
        @"tags",
        @"warnings",
    nil];
}

- (NSArray *) attributeKeys {
    return [[self class] _attributeKeys];
}

+ (BOOL) isKeyExcludedFromWebScript:(const char *)name {
    return ![[self _attributeKeys] containsObject:[NSString stringWithUTF8String:name]] && [super isKeyExcludedFromWebScript:name];
}

- (NSArray *) relations {
@synchronized (database_) {
    NSMutableArray *relations([NSMutableArray arrayWithCapacity:16]);
    for (pkgCache::DepIterator dep(version_.DependsList()); !dep.end(); ++dep)
        [relations addObject:[[[CydiaRelation alloc] initWithIterator:dep] autorelease]];
    return relations;
} }

- (NSString *) architecture {
    [self parse];
@synchronized (database_) {
    return parsed_->architecture_.empty() ? [NSNull null] : (id) parsed_->architecture_;
} }

- (NSString *) getField:(NSString *)name {
@synchronized (database_) {
    if ([database_ era] != era_ || file_.end())
        return nil;

    pkgRecords::Parser &parser([database_ records]->Lookup(file_));

    const char *start, *end;
    if (!parser.Find([name UTF8String], start, end))
        return (NSString *) [NSNull null];

    return [NSString stringWithString:[(NSString *) CYStringCreate(start, end - start) autorelease]];
} }

- (void) parse {
    if (parsed_ != NULL)
        return;
@synchronized (database_) {
    if ([database_ era] != era_ || file_.end())
        return;

    ParsedPackage *parsed(new ParsedPackage);
    parsed_ = parsed;

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
                {"architecture", &parsed->architecture_},
                {"icon", &parsed->icon_},
                {"depiction", &parsed->depiction_},
                {"homepage", &parsed->homepage_},
                {"website", &website},
                {"bugs", &parsed->bugs_},
                {"support", &parsed->support_},
                {"sponsor", &parsed->sponsor_},
                {"author", &parsed->author_},
                {"md5sum", &parsed->md5sum_},
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
                parsed->tagline_.set(pool_, start, stop - start);
            }
        _end

        _profile(Package$parse$Retain)
            if (parsed->homepage_.empty())
                parsed->homepage_ = website;
            if (parsed->homepage_ == parsed->depiction_)
                parsed->homepage_.clear();
        _end
    _end
} }

- (Package *) initWithVersion:(pkgCache::VerIterator)version withZone:(NSZone *)zone inPool:(apr_pool_t *)pool database:(Database *)database {
    if ((self = [super init]) != nil) {
    _profile(Package$initWithVersion)
        if (pool == NULL)
            apr_pool_create(&pool_, NULL);
        else {
            pool_ = pool;
            pooled_ = true;
        }

        database_ = database;
        era_ = [database era];

        version_ = version;

        pkgCache::PkgIterator iterator(version.ParentPkg());
        iterator_ = iterator;

        _profile(Package$initWithVersion$Version)
            if (!version_.end())
                file_ = version_.FileList();
            else {
                pkgCache &cache([database_ cache]);
                file_ = pkgCache::VerFileIterator(cache, cache.VerFileP);
            }
        _end

        _profile(Package$initWithVersion$Cache)
            name_.set(NULL, iterator.Display());

            latest_.set(NULL, StripVersion_(version_.VerStr()));

            pkgCache::VerIterator current(iterator.CurrentVer());
            if (!current.end())
                installed_.set(NULL, StripVersion_(current.VerStr()));
        _end

        _profile(Package$initWithVersion$Tags)
            pkgCache::TagIterator tag(iterator.TagList());
            if (!tag.end()) {
                tags_ = [NSMutableArray arrayWithCapacity:8];
                do {
                    const char *name(tag.Name());
                    [tags_ addObject:[(NSString *)CYStringCreate(name) autorelease]];

                    if (role_ == 0 && strncmp(name, "role::", 6) == 0 /*&& strcmp(name, "role::leaper") != 0*/) {
                        if (strcmp(name + 6, "enduser") == 0)
                            role_ = 1;
                        else if (strcmp(name + 6, "hacker") == 0)
                            role_ = 2;
                        else if (strcmp(name + 6, "developer") == 0)
                            role_ = 3;
                        else if (strcmp(name + 6, "cydia") == 0)
                            role_ = 7;
                        else
                            role_ = 4;
                    }

                    if (strncmp(name, "cydia::", 7) == 0) {
                        if (strcmp(name + 7, "essential") == 0)
                            essential_ = true;
                        else if (strcmp(name + 7, "obsolete") == 0)
                            obsolete_ = true;
                    }

                    ++tag;
                } while (!tag.end());
            }
        _end

        _profile(Package$initWithVersion$Metadata)
            const char *mixed(iterator.Name());
            size_t size(strlen(mixed));
            char lower[size + 1];

            for (size_t i(0); i != size; ++i)
                lower[i] = mixed[i] | 0x20;
            lower[size] = '\0';

            PackageValue *metadata(PackageFind(lower, size));
            metadata_ = metadata;

            id_.set(NULL, metadata->name_, size);

            const char *latest(version_.VerStr());
            size_t length(strlen(latest));

            uint16_t vhash(hashlittle(latest, length));

            size_t capped(std::min<size_t>(8, length));
            latest = latest + length - capped;

            if (metadata->first_ == 0)
                metadata->first_ = now_;

            if (metadata->vhash_ != vhash || strncmp(metadata->version_, latest, sizeof(metadata->version_)) != 0) {
                strncpy(metadata->version_, latest, sizeof(metadata->version_));
                metadata->vhash_ = vhash;
                metadata->last_ = now_;
            } else if (metadata->last_ == 0)
                metadata->last_ = metadata->first_;
        _end

        _profile(Package$initWithVersion$Section)
            section_ = iterator.Section();
        _end

        _profile(Package$initWithVersion$Flags)
            essential_ |= ((iterator->Flags & pkgCache::Flag::Essential) == 0 ? NO : YES);
            ignored_ = iterator->SelectedState == pkgCache::State::Hold;
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

    Package *package;

    _profile(Package$packageWithIterator$Allocate)
        package = [Package allocWithZone:zone];
    _end

    _profile(Package$packageWithIterator$Initialize)
        package = [package
            initWithVersion:version
            withZone:zone
            inPool:pool
            database:database
        ];
    _end

    _profile(Package$packageWithIterator$Autorelease)
        package = [package autorelease];
    _end

    return package;
}

- (pkgCache::PkgIterator) iterator {
    return iterator_;
}

- (NSString *) section {
    if (section$_ == nil) {
        if (section_ == NULL)
            return nil;

        _profile(Package$section$mappedSectionForPointer)
            section$_ = [database_ mappedSectionForPointer:section_];
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

- (MIMEAddress *) maintainer {
@synchronized (database_) {
    if ([database_ era] != era_ || file_.end())
        return nil;

    pkgRecords::Parser *parser = &[database_ records]->Lookup(file_);
    const std::string &maintainer(parser->Maintainer());
    return maintainer.empty() ? nil : [MIMEAddress addressWithString:[NSString stringWithUTF8String:maintainer.c_str()]];
} }

- (NSString *) md5sum {
    return parsed_ == NULL ? nil : (id) parsed_->md5sum_;
}

- (size_t) size {
@synchronized (database_) {
    if ([database_ era] != era_ || version_.end())
        return 0;

    return version_->InstalledSize;
} }

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
    if (parsed_ != NULL)
        return static_cast<NSString *>(parsed_->tagline_);

@synchronized (database_) {
    pkgRecords::Parser &parser([database_ records]->Lookup(file_));

    const char *start, *end;
    if (!parser.ShortDesc(start, end))
        return nil;

    if (end - start > 200)
        end = start + 200;

    /*
    if (const char *stop = reinterpret_cast<const char *>(memchr(start, '\n', end - start)))
        end = stop;

    while (end != start && end[-1] == '\r')
        --end;
    */

    return [(id) CYStringCreate(start, end - start) autorelease];
} }

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

- (PackageValue *) metadata {
    return metadata_;
}

- (time_t) seen {
    PackageValue *metadata([self metadata]);
    return metadata->subscribed_ ? metadata->last_ : metadata->first_;
}

- (bool) subscribed {
    return [self metadata]->subscribed_;
}

- (bool) setSubscribed:(bool)subscribed {
    PackageValue *metadata([self metadata]);
    if (metadata->subscribed_ == subscribed)
        return false;
    metadata->subscribed_ = subscribed;
    return true;
}

- (BOOL) ignored {
    return ignored_;
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
        if (_unlikely(obsolete_))
            return false;
    _end

    _profile(Package$unfiltered$hasSupportingRole)
        if (_unlikely(![self hasSupportingRole]))
            return false;
    _end

    return true;
}

- (BOOL) visible {
    if (![self unfiltered])
        return false;

    NSString *section;

    _profile(Package$visible$section)
        section = [self section];
    _end

    _profile(Package$visible$isSectionVisible)
        if (!isSectionVisible(section))
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
@synchronized (database_) {
    if ([database_ era] != era_ || iterator_.end())
        return nil;

    pkgDepCache::StateCache &state([database_ cache][iterator_]);
    return state.Mode != pkgDepCache::ModeKeep;
} }

- (NSString *) mode {
@synchronized (database_) {
    if ([database_ era] != era_ || iterator_.end())
        return nil;

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
} }

- (NSString *) id {
    return id_;
}

- (NSString *) name {
    return name_.empty() ? id_ : name_;
}

- (UIImage *) icon {
    NSString *section = [self simpleSection];

    UIImage *icon(nil);
    if (parsed_ != NULL)
        if (NSString *href = parsed_->icon_)
            if ([href hasPrefix:@"file:///"])
                icon = [UIImage imageAtPath:[[href substringFromIndex:7] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    if (icon == nil) if (section != nil)
        icon = [UIImage imageAtPath:[NSString stringWithFormat:@"%@/Sections/%@.png", App_, [section stringByReplacingOccurrencesOfString:@" " withString:@"_"]]];
    if (icon == nil) if (Source *source = [self source]) if (NSString *dicon = [source defaultIcon])
        if ([dicon hasPrefix:@"file:///"])
            icon = [UIImage imageAtPath:[[dicon substringFromIndex:7] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    if (icon == nil)
        icon = [UIImage applicationImageNamed:@"unknown.png"];
    return icon;
}

- (NSString *) homepage {
    return parsed_ == NULL ? nil : static_cast<NSString *>(parsed_->homepage_);
}

- (NSString *) depiction {
    return parsed_ != NULL && !parsed_->depiction_.empty() ? parsed_->depiction_ : [[self source] depictionForPackage:id_];
}

- (MIMEAddress *) sponsor {
    return parsed_ == NULL || parsed_->sponsor_.empty() ? nil : [MIMEAddress addressWithString:parsed_->sponsor_];
}

- (MIMEAddress *) author {
    return parsed_ == NULL || parsed_->author_.empty() ? nil : [MIMEAddress addressWithString:parsed_->author_];
}

- (NSString *) support {
    return parsed_ != NULL && !parsed_->bugs_.empty() ? parsed_->bugs_ : [[self source] supportForPackage:id_];
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

- (NSString *) state {
@synchronized (database_) {
    if ([database_ era] != era_ || file_.end())
        return nil;

    switch (iterator_->CurrentState) {
        case pkgCache::State::NotInstalled:
            return @"NotInstalled";
        case pkgCache::State::UnPacked:
            return @"UnPacked";
        case pkgCache::State::HalfConfigured:
            return @"HalfConfigured";
        case pkgCache::State::HalfInstalled:
            return @"HalfInstalled";
        case pkgCache::State::ConfigFiles:
            return @"ConfigFiles";
        case pkgCache::State::Installed:
            return @"Installed";
        case pkgCache::State::TriggersAwaited:
            return @"TriggersAwaited";
        case pkgCache::State::TriggersPending:
            return @"TriggersPending";
    }

    return (NSString *) [NSNull null];
} }

- (NSString *) selection {
@synchronized (database_) {
    if ([database_ era] != era_ || file_.end())
        return nil;

    switch (iterator_->SelectedState) {
        case pkgCache::State::Unknown:
            return @"Unknown";
        case pkgCache::State::Install:
            return @"Install";
        case pkgCache::State::Hold:
            return @"Hold";
        case pkgCache::State::DeInstall:
            return @"DeInstall";
        case pkgCache::State::Purge:
            return @"Purge";
    }

    return (NSString *) [NSNull null];
} }

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
                source_ = [database_ getSource:file_.File()] ?: (Source *) [NSNull null];
        }
    }

    return source_ == (Source *) [NSNull null] ? nil : source_;
}

- (uint32_t) rank {
    return rank_;
}

- (BOOL) matches:(NSArray *)query {
    if (query == nil || [query count] == 0)
        return NO;

    rank_ = 0;

    NSString *string;
    NSRange range;
    NSUInteger length;

    string = [self name];
    length = [string length];

    for (NSString *term in query) {
        range = [string rangeOfString:term options:MatchCompareOptions_];
        if (range.location != NSNotFound)
            rank_ -= 6 * 1000000 / length;
    }

    if (rank_ == 0) {
        string = [self id];
        length = [string length];

        for (NSString *term in query) {
            range = [string rangeOfString:term options:MatchCompareOptions_];
            if (range.location != NSNotFound)
                rank_ -= 6 * 1000000 / length;
        }
    }

    string = [self shortDescription];
    length = [string length];
    NSUInteger stop(std::min<NSUInteger>(length, 200));

    for (NSString *term in query) {
        range = [string rangeOfString:term options:MatchCompareOptions_ range:NSMakeRange(0, stop)];
        if (range.location != NSNotFound)
            rank_ -= 2 * 100000;
    }

    return rank_ != 0;
}

- (bool) hasSupportingRole {
    if (role_ == 0)
        return true;
    if (role_ == 1)
        return true;
    if ([Role_ isEqualToString:@"User"])
        return false;
    if (role_ == 2)
        return true;
    if ([Role_ isEqualToString:@"Hacker"])
        return false;
    if (role_ == 3)
        return true;
    if ([Role_ isEqualToString:@"Developer"])
        return false;
    _assert(false);
}

- (NSArray *) tags {
    return tags_;
}

- (BOOL) hasTag:(NSString *)tag {
    return tags_ == nil ? NO : [tags_ containsObject:tag];
}

- (NSString *) primaryPurpose {
    for (NSString *tag in (NSArray *) tags_)
        if ([tag hasPrefix:@"purpose::"])
            return [tag substringFromIndex:9];
    return nil;
}

- (NSArray *) purposes {
    NSMutableArray *purposes([NSMutableArray arrayWithCapacity:2]);
    for (NSString *tag in (NSArray *) tags_)
        if ([tag hasPrefix:@"purpose::"])
            [purposes addObject:[tag substringFromIndex:9]];
    return [purposes count] == 0 ? nil : purposes;
}

- (bool) isCommercial {
    return [self hasTag:@"cydia::commercial"];
}

- (void) setIndex:(size_t)index {
    if (metadata_->index_ != index)
        metadata_->index_ = index;
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

- (bool) isUnfilteredAndSearchedForBy:(NSArray *)query {
    _profile(Package$isUnfilteredAndSearchedForBy)
        bool value(true);

        _profile(Package$isUnfilteredAndSearchedForBy$Unfiltered)
            value &= [self unfiltered];
        _end

        _profile(Package$isUnfilteredAndSearchedForBy$Match)
            value &= [self matches:query];
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
    return ![self uninstalled] && (![number boolValue] && role_ != 7 || [self unfiltered]);
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
    _H<NSString> name_;
    unichar index_;
    size_t row_;
    size_t count_;
    _H<NSString> localized_;
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
            localized_ = localized;
    } return self;
}

- (Section *) initWithName:(NSString *)name localize:(BOOL)localize {
    return [self initWithName:name row:0 localize:localize];
}

- (Section *) initWithName:(NSString *)name row:(size_t)row localize:(BOOL)localize {
    if ((self = [super init]) != nil) {
        name_ = name;
        index_ = '\0';
        row_ = row;
        if (localize)
            localized_ = LocalizeSection(name_);
    } return self;
}

/* XXX: localize the index thingees */
- (Section *) initWithIndex:(unichar)index row:(size_t)row {
    if ((self = [super init]) != nil) {
        name_ = [NSString stringWithCharacters:&index length:1];
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

class CydiaLogCleaner :
    public pkgArchiveCleaner
{
  protected:
    virtual void Erase(const char *File, std::string Pkg, std::string Ver, struct stat &St) {
        unlink(File);
    }
};

/* Database Implementation {{{ */
@implementation Database

+ (Database *) sharedInstance {
    static _H<Database> instance;
    if (instance == nil)
        instance = [[[Database alloc] init] autorelease];
    return instance;
}

- (unsigned) era {
    return era_;
}

- (void) releasePackages {
    CFArrayApplyFunction(packages_, CFRangeMake(0, CFArrayGetCount(packages_)), reinterpret_cast<CFArrayApplierFunction>(&CFRelease), NULL);
    CFArrayRemoveAllValues(packages_);
}

- (void) dealloc {
    // XXX: actually implement this thing
    _assert(false);
    [self releasePackages];
    apr_pool_destroy(pool_);
    NSRecycleZone(zone_);
    [super dealloc];
}

- (void) _readCydia:(NSNumber *)fd {
    __gnu_cxx::stdio_filebuf<char> ib([fd intValue], std::ios::in);
    std::istream is(&ib);
    std::string line;

    static Pcre finish_r("^finish:([^:]*)$");

    while (std::getline(is, line)) {
        NSAutoreleasePool *pool([[NSAutoreleasePool alloc] init]);

        const char *data(line.c_str());
        size_t size = line.size();
        lprintf("C:%s\n", data);

        if (finish_r(data, size)) {
            NSString *finish = finish_r[1];
            int index = [Finishes_ indexOfObject:finish];
            if (index != INT_MAX && index > Finish_)
                Finish_ = index;
        }

        [pool release];
    }

    _assume(false);
}

- (void) _readStatus:(NSNumber *)fd {
    __gnu_cxx::stdio_filebuf<char> ib([fd intValue], std::ios::in);
    std::istream is(&ib);
    std::string line;

    static Pcre conffile_r("^status: [^ ]* : conffile-prompt : (.*?) *$");
    static Pcre pmstatus_r("^([^:]*):([^:]*):([^:]*):(.*)$");

    while (std::getline(is, line)) {
        NSAutoreleasePool *pool([[NSAutoreleasePool alloc] init]);

        const char *data(line.c_str());
        size_t size(line.size());
        lprintf("S:%s\n", data);

        if (conffile_r(data, size)) {
            // status: /fail : conffile-prompt : '/fail' '/fail.dpkg-new' 1 1
            [delegate_ performSelectorOnMainThread:@selector(setConfigurationData:) withObject:conffile_r[1] waitUntilDone:YES];
        } else if (strncmp(data, "status: ", 8) == 0) {
            // status: <package>: {unpacked,half-configured,installed}
            CydiaProgressEvent *event([CydiaProgressEvent eventWithMessage:[NSString stringWithUTF8String:(data + 8)] ofType:kCydiaProgressEventTypeStatus]);
            [progress_ performSelectorOnMainThread:@selector(addProgressEvent:) withObject:event waitUntilDone:YES];
        } else if (strncmp(data, "processing: ", 12) == 0) {
            // processing: configure: config-test
            CydiaProgressEvent *event([CydiaProgressEvent eventWithMessage:[NSString stringWithUTF8String:(data + 12)] ofType:kCydiaProgressEventTypeStatus]);
            [progress_ performSelectorOnMainThread:@selector(addProgressEvent:) withObject:event waitUntilDone:YES];
        } else if (pmstatus_r(data, size)) {
            std::string type([pmstatus_r[1] UTF8String]);

            NSString *package = pmstatus_r[2];
            if ([package isEqualToString:@"dpkg-exec"])
                package = nil;

            float percent([pmstatus_r[3] floatValue]);
            [progress_ performSelectorOnMainThread:@selector(setProgressPercent:) withObject:[NSNumber numberWithFloat:(percent / 100)] waitUntilDone:YES];

            NSString *string = pmstatus_r[4];

            if (type == "pmerror") {
                CydiaProgressEvent *event([CydiaProgressEvent eventWithMessage:string ofType:kCydiaProgressEventTypeError forPackage:package]);
                [progress_ performSelectorOnMainThread:@selector(addProgressEvent:) withObject:event waitUntilDone:YES];
            } else if (type == "pmstatus") {
                CydiaProgressEvent *event([CydiaProgressEvent eventWithMessage:string ofType:kCydiaProgressEventTypeStatus forPackage:package]);
                [progress_ performSelectorOnMainThread:@selector(addProgressEvent:) withObject:event waitUntilDone:YES];
            } else if (type == "pmconffile")
                [delegate_ performSelectorOnMainThread:@selector(setConfigurationData:) withObject:string waitUntilDone:YES];
            else
                lprintf("E:unknown pmstatus\n");
        } else
            lprintf("E:unknown status\n");

        [pool release];
    }

    _assume(false);
}

- (void) _readOutput:(NSNumber *)fd {
    __gnu_cxx::stdio_filebuf<char> ib([fd intValue], std::ios::in);
    std::istream is(&ib);
    std::string line;

    while (std::getline(is, line)) {
        NSAutoreleasePool *pool([[NSAutoreleasePool alloc] init]);

        lprintf("O:%s\n", line.c_str());

        CydiaProgressEvent *event([CydiaProgressEvent eventWithMessage:[NSString stringWithUTF8String:line.c_str()] ofType:kCydiaProgressEventTypeInformation]);
        [progress_ performSelectorOnMainThread:@selector(addProgressEvent:) withObject:event waitUntilDone:YES];

        [pool release];
    }

    _assume(false);
}

- (FILE *) input {
    return input_;
}

- (Package *) packageWithName:(NSString *)name {
    if (name == nil)
        return nil;
@synchronized (self) {
    if (static_cast<pkgDepCache *>(cache_) == NULL)
        return nil;
    pkgCache::PkgIterator iterator(cache_->FindPkg([name UTF8String]));
    return iterator.end() ? nil : [Package packageWithIterator:iterator withZone:NULL inPool:NULL database:self];
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

        size_t capacity(MetaFile_->active_);
        if (capacity == 0)
            capacity = 16384;
        else
            capacity += 1024;

        packages_ = CFArrayCreateMutable(kCFAllocatorDefault, capacity, NULL);
        sourceList_ = [NSMutableArray arrayWithCapacity:16];

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
    return sourceList_;
}

- (Source *) sourceWithKey:(NSString *)key {
    for (Source *source in [self sources]) {
        if ([[source key] isEqualToString:key])
            return source;
    } return nil;
}

- (bool) popErrorWithTitle:(NSString *)title {
    bool fatal(false);

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

        static Pcre no_pubkey("^GPG error:.* NO_PUBKEY .*$");
        if (warning && no_pubkey(error.c_str()))
            continue;

        [delegate_ addProgressEventOnMainThread:[CydiaProgressEvent eventWithMessage:[NSString stringWithUTF8String:error.c_str()] ofType:(warning ? kCydiaProgressEventTypeWarning : kCydiaProgressEventTypeError)] forTask:title];
    }

    return fatal;
}

- (bool) popErrorWithTitle:(NSString *)title forOperation:(bool)success {
    return [self popErrorWithTitle:title] || !success;
}

- (void) reloadDataWithInvocation:(NSInvocation *)invocation {
@synchronized (self) {
    ++era_;

    [self releasePackages];

    sourceMap_.clear();
    [sourceList_ removeAllObjects];

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

    cache_.Close();

    apr_pool_clear(pool_);

    NSRecycleZone(zone_);
    zone_ = NSCreateZone(1024 * 1024, 256 * 1024, NO);

    int chk(creat("/tmp/cydia.chk", 0644));
    if (chk != -1)
        close(chk);

    if (invocation != nil)
        [invocation invoke];

    NSString *title(UCLocalize("DATABASE"));

    _trace();
    OpProgress progress;
    while (!cache_.Open(progress, true)) { pop:
        std::string error;
        bool warning(!_error->PopMessage(error));
        lprintf("cache_.Open():[%s]\n", error.c_str());

        if (error == "dpkg was interrupted, you must manually run 'dpkg --configure -a' to correct the problem. ")
            [delegate_ repairWithSelector:@selector(configure)];
        else if (error == "The package lists or status file could not be parsed or opened.")
            [delegate_ repairWithSelector:@selector(update)];
        // else if (error == "Could not get lock /var/lib/dpkg/lock - open (35 Resource temporarily unavailable)")
        // else if (error == "Could not open lock file /var/lib/dpkg/lock - open (13 Permission denied)")
        // else if (error == "Malformed Status line")
        // else if (error == "The list of sources could not be read.")
        else {
            [delegate_ addProgressEventOnMainThread:[CydiaProgressEvent eventWithMessage:[NSString stringWithUTF8String:error.c_str()] ofType:(warning ? kCydiaProgressEventTypeWarning : kCydiaProgressEventTypeError)] forTask:title];
            return;
        }

        if (warning)
            goto pop;
        _error->Discard();
    }
    _trace();

    unlink("/tmp/cydia.chk");

    now_ = [[NSDate date] timeIntervalSince1970];

    policy_ = new pkgDepCache::Policy();
    records_ = new pkgRecords(cache_);
    resolver_ = new pkgProblemResolver(cache_);
    fetcher_ = new pkgAcquire(&status_);
    lock_ = NULL;

    list_ = new pkgSourceList();
    if ([self popErrorWithTitle:title forOperation:list_->ReadMainList()])
        return;

    if (cache_->DelCount() != 0 || cache_->InstCount() != 0) {
        [delegate_ addProgressEventOnMainThread:[CydiaProgressEvent eventWithMessage:UCLocalize("COUNTS_NONZERO_EX") ofType:kCydiaProgressEventTypeError] forTask:title];
        return;
    }

    if ([self popErrorWithTitle:title forOperation:pkgApplyStatus(cache_)])
        return;

    if (cache_->BrokenCount() != 0) {
        if ([self popErrorWithTitle:title forOperation:pkgFixBroken(cache_)])
            return;

        if (cache_->BrokenCount() != 0) {
            [delegate_ addProgressEventOnMainThread:[CydiaProgressEvent eventWithMessage:UCLocalize("STILL_BROKEN_EX") ofType:kCydiaProgressEventTypeError] forTask:title];
            return;
        }

        if ([self popErrorWithTitle:title forOperation:pkgMinimizeUpgrade(cache_)])
            return;
    }

    for (pkgSourceList::const_iterator source = list_->begin(); source != list_->end(); ++source) {
        Source *object([[[Source alloc] initWithMetaIndex:*source forDatabase:self inPool:pool_] autorelease]);
        [sourceList_ addObject:object];

        std::vector<pkgIndexFile *> *indices = (*source)->GetIndexFiles();
        for (std::vector<pkgIndexFile *>::const_iterator index = indices->begin(); index != indices->end(); ++index)
            // XXX: this could be more intelligent
            if (dynamic_cast<debPackagesIndex *>(*index) != NULL) {
                pkgCache::PkgFileIterator cached((*index)->FindInCache(cache_));
                if (!cached.end())
                    sourceMap_[cached->ID] = object;
            }
    }

    {
        /*std::vector<Package *> packages;
        packages.reserve(std::max(10000U, [packages_ count] + 1000));
        packages_ = nil;*/

        _trace();

        for (pkgCache::PkgIterator iterator = cache_->PkgBegin(); !iterator.end(); ++iterator)
            if (Package *package = [Package packageWithIterator:iterator withZone:zone_ inPool:pool_ database:self])
                //packages.push_back(package);
                CFArrayAppendValue(packages_, CFRetain(package));

        _trace();

        /*if (packages.empty())
            packages_ = [[NSArray alloc] init];
        else
            packages_ = [[NSArray alloc] initWithObjects:&packages.front() count:packages.size()];
        _trace();*/

        [(NSMutableArray *) packages_ radixSortUsingFunction:reinterpret_cast<MenesRadixSortFunction>(&PackagePrefixRadix) withContext:reinterpret_cast<void *>(16)];
        [(NSMutableArray *) packages_ radixSortUsingFunction:reinterpret_cast<MenesRadixSortFunction>(&PackagePrefixRadix) withContext:reinterpret_cast<void *>(4)];
        [(NSMutableArray *) packages_ radixSortUsingFunction:reinterpret_cast<MenesRadixSortFunction>(&PackagePrefixRadix) withContext:reinterpret_cast<void *>(0)];

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

        size_t count(CFArrayGetCount(packages_));
        MetaFile_->active_ = count;

        for (size_t index(0); index != count; ++index)
            [(Package *) CFArrayGetValueAtIndex(packages_, index) setIndex:index];

        _trace();
    }
} }

- (void) clear {
@synchronized (self) {
    delete resolver_;
    resolver_ = new pkgProblemResolver(cache_);

    for (pkgCache::PkgIterator iterator(cache_->PkgBegin()); !iterator.end(); ++iterator)
        if (!cache_[iterator].Keep())
            cache_->MarkKeep(iterator, false);
        else if ((cache_[iterator].iFlags & pkgDepCache::ReInstall) != 0)
            cache_->SetReInstall(iterator, false);
} }

- (void) configure {
    NSString *dpkg = [NSString stringWithFormat:@"dpkg --configure -a --status-fd %u", statusfd_];
    _trace();
    system([dpkg UTF8String]);
    _trace();
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

    CydiaLogCleaner cleaner;
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
    bool substrate(RestartSubstrate_);
    RestartSubstrate_ = false;

    NSString *title(UCLocalize("PERFORM_SELECTIONS"));

    NSMutableArray *before = [NSMutableArray arrayWithCapacity:16]; {
        pkgSourceList list;
        if ([self popErrorWithTitle:title forOperation:list.ReadMainList()])
            return;
        for (pkgSourceList::const_iterator source = list.begin(); source != list.end(); ++source)
            [before addObject:[NSString stringWithUTF8String:(*source)->GetURI().c_str()]];
    }

    [delegate_ performSelectorOnMainThread:@selector(retainNetworkActivityIndicator) withObject:nil waitUntilDone:YES];

    if (fetcher_->Run(PulseInterval_) != pkgAcquire::Continue) {
        _trace();
        [self popErrorWithTitle:title];
        return;
    }

    bool failed = false;
    for (pkgAcquire::ItemIterator item = fetcher_->ItemsBegin(); item != fetcher_->ItemsEnd(); item++) {
        if ((*item)->Status == pkgAcquire::Item::StatDone && (*item)->Complete)
            continue;
        if ((*item)->Status == pkgAcquire::Item::StatIdle)
            continue;

        failed = true;
    }

    [delegate_ performSelectorOnMainThread:@selector(releaseNetworkActivityIndicator) withObject:nil waitUntilDone:YES];

    if (failed) {
        _trace();
        return;
    }

    if (substrate)
        RestartSubstrate_ = true;

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
    NSString *title(UCLocalize("REFRESHING_DATA"));

    pkgSourceList list;
    if ([self popErrorWithTitle:title forOperation:list.ReadMainList()])
        return;

    FileFd lock;
    lock.Fd(GetLock(_config->FindDir("Dir::State::Lists") + "lock"));
    if ([self popErrorWithTitle:title])
        return;

    [delegate_ performSelectorOnMainThread:@selector(retainNetworkActivityIndicator) withObject:nil waitUntilDone:YES];

    bool success(ListUpdate(status, list, PulseInterval_));
    if (status.WasCancelled())
        _error->Discard();
    else {
        [self popErrorWithTitle:title forOperation:success];
        [Metadata_ setObject:[NSDate date] forKey:@"LastUpdate"];
        Changed_ = true;
    }

    [delegate_ performSelectorOnMainThread:@selector(releaseNetworkActivityIndicator) withObject:nil waitUntilDone:YES];
}

- (void) setDelegate:(NSObject<DatabaseDelegate> *)delegate {
    delegate_ = delegate;
}

- (void) setProgressDelegate:(NSObject<ProgressDelegate> *)delegate {
    progress_ = delegate;
    status_.setDelegate(delegate);
}

- (NSObject<ProgressDelegate> *) progressDelegate {
    return progress_;
}

- (Source *) getSource:(pkgCache::PkgFileIterator)file {
    SourceMap::const_iterator i(sourceMap_.find(file->ID));
    return i == sourceMap_.end() ? nil : i->second;
}

- (NSString *) mappedSectionForPointer:(const char *)section {
    _H<NSString> *mapped;

    _profile(Database$mappedSectionForPointer$Cache)
        mapped = &sections_[section];
    _end

    if (*mapped == NULL) {
        size_t length(strlen(section));
        char spaced[length + 1];

        _profile(Database$mappedSectionForPointer$Replace)
            for (size_t index(0); index != length; ++index)
                spaced[index] = section[index] == '_' ? ' ' : section[index];
            spaced[length] = '\0';
        _end

        NSString *string;

        _profile(Database$mappedSectionForPointer$stringWithUTF8String)
            string = [NSString stringWithUTF8String:spaced];
        _end

        _profile(Database$mappedSectionForPointer$Map)
            string = [SectionMap_ objectForKey:string] ?: string;
        _end

        *mapped = string;
    } return *mapped;
}

@end
/* }}} */

static _H<NSMutableSet> Diversions_;

@interface Diversion : NSObject {
    Pcre pattern_;
    _H<NSString> key_;
    _H<NSString> format_;
}

@end

@implementation Diversion

- (id) initWithFrom:(NSString *)from to:(NSString *)to {
    if ((self = [super init]) != nil) {
        pattern_ = [from UTF8String];
        key_ = from;
        format_ = to;
    } return self;
}

- (NSString *) divert:(NSString *)url {
    return !pattern_(url) ? nil : pattern_->*format_;
}

+ (NSURL *) divertURL:(NSURL *)url {
  divert:
    NSString *href([url absoluteString]);

    for (Diversion *diversion in (id) Diversions_)
        if (NSString *diverted = [diversion divert:href]) {
#if !ForRelease
            NSLog(@"div: %@", diverted);
#endif
            url = [NSURL URLWithString:diverted];
            goto divert;
        }

    return url;
}

- (NSString *) key {
    return key_;
}

- (NSUInteger) hash {
    return [key_ hash];
}

- (BOOL) isEqual:(Diversion *)object {
    return self == object || [self class] == [object class] && [key_ isEqual:[object key]];
}

@end

@interface CydiaObject : NSObject {
    _H<IndirectDelegate> indirect_;
    _transient id delegate_;
}

- (id) initWithDelegate:(IndirectDelegate *)indirect;

@end

@class CydiaObject;

@interface CydiaWebViewController : CyteWebViewController {
    _H<CydiaObject> cydia_;
}

+ (void) addDiversion:(Diversion *)diversion;
+ (NSURLRequest *) requestWithHeaders:(NSURLRequest *)request;
+ (void) didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame withCydia:(CydiaObject *)cydia;
- (void) setDelegate:(id)delegate;

@end

/* Web Scripting {{{ */
@implementation CydiaObject

- (id) initWithDelegate:(IndirectDelegate *)indirect {
    if ((self = [super init]) != nil) {
        indirect_ = indirect;
    } return self;
}

- (void) setDelegate:(id)delegate {
    delegate_ = delegate;
}

+ (NSArray *) _attributeKeys {
    return [NSArray arrayWithObjects:
        @"bbsnum",
        @"build",
        @"coreFoundationVersionNumber",
        @"device",
        @"ecid",
        @"firmware",
        @"hostname",
        @"idiom",
        @"mcc",
        @"mnc",
        @"model",
        @"operator",
        @"role",
        @"serial",
        @"token",
        @"version",
    nil];
}

- (NSArray *) attributeKeys {
    return [[self class] _attributeKeys];
}

+ (BOOL) isKeyExcludedFromWebScript:(const char *)name {
    return ![[self _attributeKeys] containsObject:[NSString stringWithUTF8String:name]] && [super isKeyExcludedFromWebScript:name];
}

- (NSString *) version {
    return Cydia_;
}

- (NSString *) build {
    return System_;
}

- (NSString *) coreFoundationVersionNumber {
    return [NSString stringWithFormat:@"%.2f", kCFCoreFoundationVersionNumber];
}

- (NSString *) device {
    return [[UIDevice currentDevice] uniqueIdentifier];
}

- (NSString *) firmware {
    return [[UIDevice currentDevice] systemVersion];
}

- (NSString *) hostname {
    return [[UIDevice currentDevice] name];
}

- (NSString *) idiom {
    return (id) Idiom_ ?: [NSNull null];
}

- (NSString *) mcc {
    if (CFStringRef (*$CTSIMSupportCopyMobileSubscriberCountryCode)(CFAllocatorRef) = reinterpret_cast<CFStringRef (*)(CFAllocatorRef)>(dlsym(RTLD_DEFAULT, "CTSIMSupportCopyMobileSubscriberCountryCode")))
        return [(NSString *) (*$CTSIMSupportCopyMobileSubscriberCountryCode)(kCFAllocatorDefault) autorelease];
    return nil;
}

- (NSString *) mnc {
    if (CFStringRef (*$CTSIMSupportCopyMobileSubscriberNetworkCode)(CFAllocatorRef) = reinterpret_cast<CFStringRef (*)(CFAllocatorRef)>(dlsym(RTLD_DEFAULT, "CTSIMSupportCopyMobileSubscriberNetworkCode")))
        return [(NSString *) (*$CTSIMSupportCopyMobileSubscriberNetworkCode)(kCFAllocatorDefault) autorelease];
    return nil;
}

- (NSString *) operator {
    if (CFStringRef (*$CTRegistrationCopyOperatorName)(CFAllocatorRef) = reinterpret_cast<CFStringRef (*)(CFAllocatorRef)>(dlsym(RTLD_DEFAULT, "CTRegistrationCopyOperatorName")))
        return [(NSString *) (*$CTRegistrationCopyOperatorName)(kCFAllocatorDefault) autorelease];
    return nil;
}

- (NSString *) bbsnum {
    return (id) BBSNum_ ?: [NSNull null];
}

- (NSString *) ecid {
    return (id) ChipID_ ?: [NSNull null];
}

- (NSString *) serial {
    return SerialNumber_;
}

- (NSString *) role {
    return (id) Role_ ?: [NSNull null];
}

- (NSString *) model {
    return [NSString stringWithUTF8String:Machine_];
}

- (NSString *) token {
    return (id) Token_ ?: [NSNull null];
}

+ (NSString *) webScriptNameForSelector:(SEL)selector {
    if (false);
    else if (selector == @selector(addBridgedHost:))
        return @"addBridgedHost";
    else if (selector == @selector(addInsecureHost:))
        return @"addInsecureHost";
    else if (selector == @selector(addInternalRedirect::))
        return @"addInternalRedirect";
    else if (selector == @selector(addPipelinedHost:scheme:))
        return @"addPipelinedHost";
    else if (selector == @selector(addSource:::))
        return @"addSource";
    else if (selector == @selector(addTokenHost:))
        return @"addTokenHost";
    else if (selector == @selector(addTrivialSource:))
        return @"addTrivialSource";
    else if (selector == @selector(close))
        return @"close";
    else if (selector == @selector(du:))
        return @"du";
    else if (selector == @selector(stringWithFormat:arguments:))
        return @"format";
    else if (selector == @selector(getAllSources))
        return @"getAllSourcs";
    else if (selector == @selector(getKernelNumber:))
        return @"getKernelNumber";
    else if (selector == @selector(getKernelString:))
        return @"getKernelString";
    else if (selector == @selector(getInstalledPackages))
        return @"getInstalledPackages";
    else if (selector == @selector(getIORegistryEntry::))
        return @"getIORegistryEntry";
    else if (selector == @selector(getLocaleIdentifier))
        return @"getLocaleIdentifier";
    else if (selector == @selector(getPreferredLanguages))
        return @"getPreferredLanguages";
    else if (selector == @selector(getPackageById:))
        return @"getPackageById";
    else if (selector == @selector(getMetadataKeys))
        return @"getMetadataKeys";
    else if (selector == @selector(getMetadataValue:))
        return @"getMetadataValue";
    else if (selector == @selector(getSessionValue:))
        return @"getSessionValue";
    else if (selector == @selector(installPackages:))
        return @"installPackages";
    else if (selector == @selector(localizedStringForKey:value:table:))
        return @"localize";
    else if (selector == @selector(popViewController:))
        return @"popViewController";
    else if (selector == @selector(refreshSources))
        return @"refreshSources";
    else if (selector == @selector(removeButton))
        return @"removeButton";
    else if (selector == @selector(saveConfig))
        return @"saveConfig";
    else if (selector == @selector(setMetadataValue::))
        return @"setMetadataValue";
    else if (selector == @selector(setSessionValue::))
        return @"setSessionValue";
    else if (selector == @selector(setShowPromoted:))
        return @"setShowPromoted";
    else if (selector == @selector(substitutePackageNames:))
        return @"substitutePackageNames";
    else if (selector == @selector(scrollToBottom:))
        return @"scrollToBottom";
    else if (selector == @selector(setAllowsNavigationAction:))
        return @"setAllowsNavigationAction";
    else if (selector == @selector(setBadgeValue:))
        return @"setBadgeValue";
    else if (selector == @selector(setButtonImage:withStyle:toFunction:))
        return @"setButtonImage";
    else if (selector == @selector(setButtonTitle:withStyle:toFunction:))
        return @"setButtonTitle";
    else if (selector == @selector(setHidesBackButton:))
        return @"setHidesBackButton";
    else if (selector == @selector(setHidesNavigationBar:))
        return @"setHidesNavigationBar";
    else if (selector == @selector(setNavigationBarStyle:))
        return @"setNavigationBarStyle";
    else if (selector == @selector(setNavigationBarTintRed:green:blue:alpha:))
        return @"setNavigationBarTintColor";
    else if (selector == @selector(setPasteboardString:))
        return @"setPasteboardString";
    else if (selector == @selector(setPasteboardURL:))
        return @"setPasteboardURL";
    else if (selector == @selector(setScrollAlwaysBounceVertical:))
        return @"setScrollAlwaysBounceVertical";
    else if (selector == @selector(setScrollIndicatorStyle:))
        return @"setScrollIndicatorStyle";
    else if (selector == @selector(setToken:))
        return @"setToken";
    else if (selector == @selector(setViewportWidth:))
        return @"setViewportWidth";
    else if (selector == @selector(statfs:))
        return @"statfs";
    else if (selector == @selector(supports:))
        return @"supports";
    else if (selector == @selector(unload))
        return @"unload";
    else
        return nil;
}

+ (BOOL) isSelectorExcludedFromWebScript:(SEL)selector {
    return [self webScriptNameForSelector:selector] == nil;
}

- (BOOL) supports:(NSString *)feature {
    return [feature isEqualToString:@"window.open"];
}

- (void) unload {
    [delegate_ performSelectorOnMainThread:@selector(unloadData) withObject:nil waitUntilDone:NO];
}

- (void) setScrollAlwaysBounceVertical:(NSNumber *)value {
    [indirect_ performSelectorOnMainThread:@selector(setScrollAlwaysBounceVerticalNumber:) withObject:value waitUntilDone:NO];
}

- (void) setScrollIndicatorStyle:(NSString *)style {
    [indirect_ performSelectorOnMainThread:@selector(setScrollIndicatorStyleWithName:) withObject:style waitUntilDone:NO];
}

- (void) addInternalRedirect:(NSString *)from :(NSString *)to {
    [CydiaWebViewController performSelectorOnMainThread:@selector(addDiversion:) withObject:[[[Diversion alloc] initWithFrom:from to:to] autorelease] waitUntilDone:NO];
}

- (NSNumber *) getKernelNumber:(NSString *)name {
    const char *string([name UTF8String]);

    size_t size;
    if (sysctlbyname(string, NULL, &size, NULL, 0) == -1)
        return (id) [NSNull null];

    if (size != sizeof(int))
        return (id) [NSNull null];

    int value;
    if (sysctlbyname(string, &value, &size, NULL, 0) == -1)
        return (id) [NSNull null];

    return [NSNumber numberWithInt:value];
}

- (NSString *) getKernelString:(NSString *)name {
    const char *string([name UTF8String]);

    size_t size;
    if (sysctlbyname(string, NULL, &size, NULL, 0) == -1)
        return (id) [NSNull null];

    char value[size + 1];
    if (sysctlbyname(string, value, &size, NULL, 0) == -1)
        return (id) [NSNull null];

    // XXX: just in case you request something ludicrous
    value[size] = '\0';

    return [NSString stringWithCString:value];
}

- (NSObject *) getIORegistryEntry:(NSString *)path :(NSString *)entry {
    NSObject *value(CYIOGetValue([path UTF8String], entry));

    if (value != nil)
        if ([value isKindOfClass:[NSData class]])
            value = CYHex((NSData *) value);

    return value;
}

- (NSArray *) getMetadataKeys {
@synchronized (Values_) {
    return [Values_ allKeys];
} }

- (void) _setShowPromoted:(NSNumber *)value {
    [Metadata_ setObject:value forKey:@"ShowPromoted"];
    Changed_ = true;
}

- (void) setShowPromoted:(NSNumber *)value {
    [self performSelectorOnMainThread:@selector(_setShowPromoted:) withObject:value waitUntilDone:NO];
}

- (id) getMetadataValue:(NSString *)key {
@synchronized (Values_) {
    return [Values_ objectForKey:key];
} }

- (void) setMetadataValue:(NSString *)key :(NSString *)value {
@synchronized (Values_) {
    if (value == nil || value == (id) [WebUndefined undefined] || value == (id) [NSNull null])
        [Values_ removeObjectForKey:key];
    else
        [Values_ setObject:value forKey:key];

    [delegate_ performSelectorOnMainThread:@selector(updateValues) withObject:nil waitUntilDone:YES];
} }

- (id) getSessionValue:(NSString *)key {
@synchronized (SessionData_) {
    return [SessionData_ objectForKey:key];
} }

- (void) setSessionValue:(NSString *)key :(NSString *)value {
@synchronized (SessionData_) {
    if (value == (id) [WebUndefined undefined])
        [SessionData_ removeObjectForKey:key];
    else
        [SessionData_ setObject:value forKey:key];
} }

- (void) addBridgedHost:(NSString *)host {
@synchronized (HostConfig_) {
    [BridgedHosts_ addObject:host];
} }

- (void) addInsecureHost:(NSString *)host {
@synchronized (HostConfig_) {
    [InsecureHosts_ addObject:host];
} }

- (void) addTokenHost:(NSString *)host {
@synchronized (HostConfig_) {
    [TokenHosts_ addObject:host];
} }

- (void) addPipelinedHost:(NSString *)host scheme:(NSString *)scheme {
@synchronized (HostConfig_) {
    if (scheme != (id) [WebUndefined undefined])
        host = [NSString stringWithFormat:@"%@:%@", [scheme lowercaseString], host];

    [PipelinedHosts_ addObject:host];
} }

- (void) popViewController:(NSNumber *)value {
    if (value == (id) [WebUndefined undefined])
        value = [NSNumber numberWithBool:YES];
    [indirect_ performSelectorOnMainThread:@selector(popViewControllerWithNumber:) withObject:value waitUntilDone:NO];
}

- (void) addSource:(NSString *)href :(NSString *)distribution :(WebScriptObject *)sections {
    NSMutableArray *array([NSMutableArray arrayWithCapacity:[sections count]]);

    for (NSString *section in sections)
        [array addObject:section];

    [delegate_ performSelectorOnMainThread:@selector(addSource:) withObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:
        @"deb", @"Type",
        href, @"URI",
        distribution, @"Distribution",
        array, @"Sections",
    nil] waitUntilDone:NO];
}

- (void) addTrivialSource:(NSString *)href {
    [delegate_ performSelectorOnMainThread:@selector(addTrivialSource:) withObject:href waitUntilDone:NO];
}

- (void) refreshSources {
    [delegate_ performSelectorOnMainThread:@selector(syncData) withObject:nil waitUntilDone:NO];
}

- (void) saveConfig {
    [delegate_ performSelectorOnMainThread:@selector(_saveConfig) withObject:nil waitUntilDone:NO];
}

- (NSArray *) getAllSources {
    return [[Database sharedInstance] sources];
}

- (NSArray *) getInstalledPackages {
    Database *database([Database sharedInstance]);
@synchronized (database) {
    NSArray *packages([database packages]);
    NSMutableArray *installed([NSMutableArray arrayWithCapacity:1024]);
    for (Package *package in packages)
        if (![package uninstalled])
            [installed addObject:package];
    return installed;
} }

- (Package *) getPackageById:(NSString *)id {
    if (Package *package = [[Database sharedInstance] packageWithName:id]) {
        [package parse];
        return package;
    } else
        return (Package *) [NSNull null];
}

- (NSString *) getLocaleIdentifier {
    return Locale_ == NULL ? (NSString *) [NSNull null] : (NSString *) CFLocaleGetIdentifier(Locale_);
}

- (NSArray *) getPreferredLanguages {
    return Languages_;
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

    ReapZombie(pid);

    return value;
}

- (void) close {
    [indirect_ performSelectorOnMainThread:@selector(close) withObject:nil waitUntilDone:NO];
}

- (void) installPackages:(NSArray *)packages {
    [delegate_ performSelectorOnMainThread:@selector(installPackages:) withObject:packages waitUntilDone:NO];
}

- (NSString *) substitutePackageNames:(NSString *)message {
    NSMutableArray *words([[message componentsSeparatedByString:@" "] mutableCopy]);
    for (size_t i(0), e([words count]); i != e; ++i) {
        NSString *word([words objectAtIndex:i]);
        if (Package *package = [[Database sharedInstance] packageWithName:word])
            [words replaceObjectAtIndex:i withObject:[package name]];
    }

    return [words componentsJoinedByString:@" "];
}

- (void) removeButton {
    [indirect_ removeButton];
}

- (void) setButtonImage:(NSString *)button withStyle:(NSString *)style toFunction:(id)function {
    [indirect_ setButtonImage:button withStyle:style toFunction:function];
}

- (void) setButtonTitle:(NSString *)button withStyle:(NSString *)style toFunction:(id)function {
    [indirect_ setButtonTitle:button withStyle:style toFunction:function];
}

- (void) setBadgeValue:(id)value {
    [indirect_ performSelectorOnMainThread:@selector(setBadgeValue:) withObject:value waitUntilDone:NO];
}

- (void) setAllowsNavigationAction:(NSString *)value {
    [indirect_ performSelectorOnMainThread:@selector(setAllowsNavigationActionByNumber:) withObject:value waitUntilDone:NO];
}

- (void) setHidesBackButton:(NSString *)value {
    [indirect_ performSelectorOnMainThread:@selector(setHidesBackButtonByNumber:) withObject:value waitUntilDone:NO];
}

- (void) setHidesNavigationBar:(NSString *)value {
    [indirect_ performSelectorOnMainThread:@selector(setHidesNavigationBarByNumber:) withObject:value waitUntilDone:NO];
}

- (void) setNavigationBarStyle:(NSString *)value {
    [indirect_ performSelectorOnMainThread:@selector(setNavigationBarStyle:) withObject:value waitUntilDone:NO];
}

- (void) setNavigationBarTintRed:(NSNumber *)red green:(NSNumber *)green blue:(NSNumber *)blue alpha:(NSNumber *)alpha {
    float opacity(alpha == (id) [WebUndefined undefined] ? 1 : [alpha floatValue]);
    UIColor *color([UIColor colorWithRed:[red floatValue] green:[green floatValue] blue:[blue floatValue] alpha:opacity]);
    [indirect_ performSelectorOnMainThread:@selector(setNavigationBarTintColor:) withObject:color waitUntilDone:NO];
}

- (void) setPasteboardString:(NSString *)value {
    [[objc_getClass("UIPasteboard") generalPasteboard] setString:value];
}

- (void) setPasteboardURL:(NSString *)value {
    [[objc_getClass("UIPasteboard") generalPasteboard] setURL:[NSURL URLWithString:value]];
}

- (void) _setToken:(NSString *)token {
    Token_ = token;

    if (token == nil)
        [Metadata_ removeObjectForKey:@"Token"];
    else
        [Metadata_ setObject:Token_ forKey:@"Token"];

    Changed_ = true;
}

- (void) setToken:(NSString *)token {
    [self performSelectorOnMainThread:@selector(_setToken:) withObject:token waitUntilDone:NO];
}

- (void) scrollToBottom:(NSNumber *)animated {
    [indirect_ performSelectorOnMainThread:@selector(scrollToBottomAnimated:) withObject:animated waitUntilDone:NO];
}

- (void) setViewportWidth:(float)width {
    [indirect_ setViewportWidthOnMainThread:width];
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

@interface NSURL (CydiaSecure)
@end

@implementation NSURL (CydiaSecure)

- (bool) isCydiaSecure {
    if ([[[self scheme] lowercaseString] isEqualToString:@"https"])
        return true;

    @synchronized (HostConfig_) {
        if ([InsecureHosts_ containsObject:[self host]])
            return true;
    }

    return false;
}

@end

/* Cydia Browser Controller {{{ */
@implementation CydiaWebViewController

- (NSURL *) navigationURL {
    return request_ == nil ? nil : [NSURL URLWithString:[NSString stringWithFormat:@"cydia://url/%@", [[request_ URL] absoluteString]]];
}

+ (void) _initialize {
    [super _initialize];

    Diversions_ = [NSMutableSet setWithCapacity:0];
}

+ (void) addDiversion:(Diversion *)diversion {
    [Diversions_ addObject:diversion];
}

- (void) webView:(WebView *)view didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame {
    [super webView:view didClearWindowObject:window forFrame:frame];
    [CydiaWebViewController didClearWindowObject:window forFrame:frame withCydia:cydia_];
}

+ (void) didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame withCydia:(CydiaObject *)cydia {
    WebDataSource *source([frame dataSource]);
    NSURLResponse *response([source response]);
    NSURL *url([response URL]);
    NSString *scheme([[url scheme] lowercaseString]);

    bool bridged(false);

    @synchronized (HostConfig_) {
        if ([scheme isEqualToString:@"file"])
            bridged = true;
        else if ([scheme isEqualToString:@"https"])
            if ([BridgedHosts_ containsObject:[url host]])
                bridged = true;
    }

    if (bridged)
        [window setValue:cydia forKey:@"cydia"];
}

- (void) _setupMail:(MFMailComposeViewController *)controller {
    [controller addAttachmentData:[NSData dataWithContentsOfFile:@"/tmp/cydia.log"] mimeType:@"text/plain" fileName:@"cydia.log"];

    system("/usr/bin/dpkg -l >/tmp/dpkgl.log");
    [controller addAttachmentData:[NSData dataWithContentsOfFile:@"/tmp/dpkgl.log"] mimeType:@"text/plain" fileName:@"dpkgl.log"];
}

- (NSURL *) URLWithURL:(NSURL *)url {
    return [Diversion divertURL:url];
}

- (NSURLRequest *) webView:(WebView *)view resource:(id)resource willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response fromDataSource:(WebDataSource *)source {
    return [CydiaWebViewController requestWithHeaders:[super webView:view resource:resource willSendRequest:request redirectResponse:response fromDataSource:source]];
}

+ (NSURLRequest *) requestWithHeaders:(NSURLRequest *)request {
    NSMutableURLRequest *copy([request mutableCopy]);

    NSURL *url([copy URL]);
    NSString *host([url host]);

    if ([copy valueForHTTPHeaderField:@"X-Cydia-Cf-Version"] == nil)
        [copy setValue:[NSString stringWithFormat:@"%.2f", kCFCoreFoundationVersionNumber] forHTTPHeaderField:@"X-Cydia-Cf-Version"];
    if (Machine_ != NULL && [copy valueForHTTPHeaderField:@"X-Machine"] == nil)
        [copy setValue:[NSString stringWithUTF8String:Machine_] forHTTPHeaderField:@"X-Machine"];

    bool bridged;
    bool token;

    @synchronized (HostConfig_) {
        bridged = [BridgedHosts_ containsObject:host];
        token = [TokenHosts_ containsObject:host];
    }

    if ([url isCydiaSecure]) {
        if (bridged) {
            if (UniqueID_ != nil && [copy valueForHTTPHeaderField:@"X-Cydia-Id"] == nil)
                [copy setValue:UniqueID_ forHTTPHeaderField:@"X-Cydia-Id"];
        } else if (token) {
            if (Token_ != nil && [copy valueForHTTPHeaderField:@"X-Cydia-Token"] == nil)
                [copy setValue:Token_ forHTTPHeaderField:@"X-Cydia-Token"];
        }
    }

    return copy;
}

- (void) setDelegate:(id)delegate {
    [super setDelegate:delegate];
    [cydia_ setDelegate:delegate];
}

- (NSString *) applicationNameForUserAgent {
    return UserAgent_;
}

- (id) init {
    if ((self = [super initWithWidth:0 ofClass:[CydiaWebViewController class]]) != nil) {
        cydia_ = [[[CydiaObject alloc] initWithDelegate:indirect_] autorelease];
    } return self;
}

@end

@interface AppCacheController : CydiaWebViewController {
}

@end

@implementation AppCacheController

- (void) didReceiveMemoryWarning {
    // XXX: this doesn't work
}

- (bool) retainsNetworkActivityIndicator {
    return false;
}

@end
/* }}} */

// CydiaScript {{{
@interface NSObject (CydiaScript)
- (id) Cydia$webScriptObjectInContext:(WebScriptObject *)context;
@end

@implementation NSObject (CydiaScript)

- (id) Cydia$webScriptObjectInContext:(WebScriptObject *)context {
    return self;
}

@end

@implementation NSArray (CydiaScript)

- (id) Cydia$webScriptObjectInContext:(WebScriptObject *)context {
    WebScriptObject *object([context evaluateWebScript:@"[]"]);
    for (size_t i(0), e([self count]); i != e; ++i)
        [object setWebScriptValueAtIndex:i value:[[self objectAtIndex:i] Cydia$webScriptObjectInContext:context]];
    return object;
}

@end

@implementation NSDictionary (CydiaScript)

- (id) Cydia$webScriptObjectInContext:(WebScriptObject *)context {
    WebScriptObject *object([context evaluateWebScript:@"({})"]);
    for (id i in self)
        [object setValue:[[self objectForKey:i] Cydia$webScriptObjectInContext:context] forKey:i];
    return object;
}

@end
// }}}

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

@protocol ConfirmationControllerDelegate
- (void) cancelAndClear:(bool)clear;
- (void) confirmWithNavigationController:(UINavigationController *)navigation;
- (void) queue;
@end

@interface ConfirmationController : CydiaWebViewController {
    _transient Database *database_;

    _H<UIAlertView> essential_;

    _H<NSDictionary> changes_;
    _H<NSMutableArray> issues_;
    _H<NSDictionary> sizes_;

    BOOL substrate_;
}

- (id) initWithDatabase:(Database *)database;

@end

@implementation ConfirmationController

- (void) complete {
    if (substrate_)
        RestartSubstrate_ = true;
    [delegate_ confirmWithNavigationController:[self navigationController]];
}

- (void) alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)button {
    NSString *context([alert context]);

    if ([context isEqualToString:@"remove"]) {
        if (button == [alert cancelButtonIndex])
            [self dismissModalViewControllerAnimated:YES];
        else if (button == [alert firstOtherButtonIndex]) {
            [self complete];
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
    [delegate_ cancelAndClear:NO];
    [self dismissModalViewControllerAnimated:YES];
}

- (id) invokeDefaultMethodWithArguments:(NSArray *)args {
    [self performSelectorOnMainThread:@selector(_doContinue) withObject:nil waitUntilDone:NO];
    return nil;
}

- (void) webView:(WebView *)view didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame {
    [super webView:view didClearWindowObject:window forFrame:frame];

    [window setValue:[[NSDictionary dictionaryWithObjectsAndKeys:
        (id) changes_, @"changes",
        (id) issues_, @"issues",
        (id) sizes_, @"sizes",
        self, @"queue",
    nil] Cydia$webScriptObjectInContext:window] forKey:@"cydiaConfirm"];
}

- (id) initWithDatabase:(Database *)database {
    if ((self = [super init]) != nil) {
        database_ = database;

        NSMutableArray *installs([NSMutableArray arrayWithCapacity:16]);
        NSMutableArray *reinstalls([NSMutableArray arrayWithCapacity:16]);
        NSMutableArray *upgrades([NSMutableArray arrayWithCapacity:16]);
        NSMutableArray *downgrades([NSMutableArray arrayWithCapacity:16]);
        NSMutableArray *removes([NSMutableArray arrayWithCapacity:16]);

        bool remove(false);

        pkgCacheFile &cache([database_ cache]);
        NSArray *packages([database_ packages]);
        pkgDepCache::Policy *policy([database_ policy]);

        issues_ = [NSMutableArray arrayWithCapacity:4];

        for (Package *package in packages) {
            pkgCache::PkgIterator iterator([package iterator]);
            NSString *name([package id]);

            if ([package broken]) {
                NSMutableArray *reasons([NSMutableArray arrayWithCapacity:4]);

                [issues_ addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                    name, @"package",
                    reasons, @"reasons",
                nil]];

                pkgCache::VerIterator ver(cache[iterator].InstVerIter(cache));
                if (ver.end())
                    continue;

                for (pkgCache::DepIterator dep(ver.DependsList()); !dep.end(); ) {
                    pkgCache::DepIterator start;
                    pkgCache::DepIterator end;
                    dep.GlobOr(start, end); // ++dep

                    if (!cache->IsImportantDep(end))
                        continue;
                    if ((cache[end] & pkgDepCache::DepGInstall) != 0)
                        continue;

                    NSMutableArray *clauses([NSMutableArray arrayWithCapacity:4]);

                    [reasons addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                        [NSString stringWithUTF8String:start.DepType()], @"relationship",
                        clauses, @"clauses",
                    nil]];

                    _forever {
                        NSString *reason, *installed((NSString *) [WebUndefined undefined]);

                        pkgCache::PkgIterator target(start.TargetPkg());
                        if (target->ProvidesList != 0)
                            reason = @"missing";
                        else {
                            pkgCache::VerIterator ver(cache[target].InstVerIter(cache));
                            if (!ver.end()) {
                                reason = @"installed";
                                installed = [NSString stringWithUTF8String:ver.VerStr()];
                            } else if (!cache[target].CandidateVerIter(cache).end())
                                reason = @"uninstalled";
                            else if (target->ProvidesList == 0)
                                reason = @"uninstallable";
                            else
                                reason = @"virtual";
                        }

                        NSDictionary *version(start.TargetVer() == 0 ? [NSNull null] : [NSDictionary dictionaryWithObjectsAndKeys:
                            [NSString stringWithUTF8String:start.CompType()], @"operator",
                            [NSString stringWithUTF8String:start.TargetVer()], @"value",
                        nil]);

                        [clauses addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                            [NSString stringWithUTF8String:start.TargetPkg().Name()], @"package",
                            version, @"version",
                            reason, @"reason",
                            installed, @"installed",
                        nil]];

                        // yes, seriously. (wtf?)
                        if (start == end)
                            break;
                        ++start;
                    }
                }
            }

            pkgDepCache::StateCache &state(cache[iterator]);

            static Pcre special_r("^(firmware$|gsc\\.|cy\\+)");

            if (state.NewInstall())
                [installs addObject:name];
            // XXX: else if (state.Install())
            else if (!state.Delete() && (state.iFlags & pkgDepCache::ReInstall) == pkgDepCache::ReInstall)
                [reinstalls addObject:name];
            // XXX: move before previous if
            else if (state.Upgrade())
                [upgrades addObject:name];
            else if (state.Downgrade())
                [downgrades addObject:name];
            else if (!state.Delete())
                // XXX: _assert(state.Keep());
                continue;
            else if (special_r(name))
                [issues_ addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                    [NSNull null], @"package",
                    [NSArray arrayWithObjects:
                        [NSDictionary dictionaryWithObjectsAndKeys:
                            @"Conflicts", @"relationship",
                            [NSArray arrayWithObjects:
                                [NSDictionary dictionaryWithObjectsAndKeys:
                                    name, @"package",
                                    [NSNull null], @"version",
                                    @"installed", @"reason",
                                nil],
                            nil], @"clauses",
                        nil],
                    nil], @"reasons",
                nil]];
            else {
                if ([package essential])
                    remove = true;
                [removes addObject:name];
            }

            substrate_ |= DepSubstrate(policy->GetCandidateVer(iterator));
            substrate_ |= DepSubstrate(iterator.CurrentVer());
        }

        if (!remove)
            essential_ = nil;
        else if (Advanced_) {
            NSString *parenthetical(UCLocalize("PARENTHETICAL"));

            essential_ = [[[UIAlertView alloc]
                initWithTitle:UCLocalize("REMOVING_ESSENTIALS")
                message:UCLocalize("REMOVING_ESSENTIALS_EX")
                delegate:self
                cancelButtonTitle:[NSString stringWithFormat:parenthetical, UCLocalize("CANCEL_OPERATION"), UCLocalize("SAFE")]
                otherButtonTitles:
                    [NSString stringWithFormat:parenthetical, UCLocalize("FORCE_REMOVAL"), UCLocalize("UNSAFE")],
                nil
            ] autorelease];

            [essential_ setContext:@"remove"];
        } else {
            essential_ = [[[UIAlertView alloc]
                initWithTitle:UCLocalize("UNABLE_TO_COMPLY")
                message:UCLocalize("UNABLE_TO_COMPLY_EX")
                delegate:self
                cancelButtonTitle:UCLocalize("OKAY")
                otherButtonTitles:nil
            ] autorelease];

            [essential_ setContext:@"unable"];
        }

        changes_ = [NSDictionary dictionaryWithObjectsAndKeys:
            installs, @"installs",
            reinstalls, @"reinstalls",
            upgrades, @"upgrades",
            downgrades, @"downgrades",
            removes, @"removes",
        nil];

        sizes_ = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInteger:[database_ fetcher].FetchNeeded()], @"downloading",
            [NSNumber numberWithInteger:[database_ fetcher].PartialPresent()], @"resuming",
        nil];

        [self setURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/#!/confirm/", UI_]]];
    } return self;
}

- (UIBarButtonItem *) leftButton {
    return [[[UIBarButtonItem alloc]
        initWithTitle:UCLocalize("CANCEL")
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(cancelButtonClicked)
    ] autorelease];
}

#if !AlwaysReload
- (void) applyRightButton {
    if ([issues_ count] == 0 && ![self isLoading])
        [[self navigationItem] setRightBarButtonItem:[[[UIBarButtonItem alloc]
            initWithTitle:UCLocalize("CONFIRM")
            style:UIBarButtonItemStyleDone
            target:self
            action:@selector(confirmButtonClicked)
        ] autorelease]];
    else
        [[self navigationItem] setRightBarButtonItem:nil];
}
#endif

- (void) cancelButtonClicked {
    [self dismissModalViewControllerAnimated:YES];
    [delegate_ cancelAndClear:YES];
}

#if !AlwaysReload
- (void) confirmButtonClicked {
    if (essential_ != nil)
        [essential_ show];
    else
        [self complete];
}
#endif

@end
/* }}} */

/* Progress Data {{{ */
@interface CydiaProgressData : NSObject {
    _transient id delegate_;

    bool running_;
    float percent_;

    float current_;
    float total_;
    float speed_;

    _H<NSMutableArray> events_;
    _H<NSString> title_;

    _H<NSString> status_;
    _H<NSString> finish_;
}

@end

@implementation CydiaProgressData

+ (NSArray *) _attributeKeys {
    return [NSArray arrayWithObjects:
        @"current",
        @"events",
        @"finish",
        @"percent",
        @"running",
        @"speed",
        @"title",
        @"total",
    nil];
}

- (NSArray *) attributeKeys {
    return [[self class] _attributeKeys];
}

+ (BOOL) isKeyExcludedFromWebScript:(const char *)name {
    return ![[self _attributeKeys] containsObject:[NSString stringWithUTF8String:name]] && [super isKeyExcludedFromWebScript:name];
}

- (id) init {
    if ((self = [super init]) != nil) {
        events_ = [NSMutableArray arrayWithCapacity:32];
    } return self;
}

- (void) setDelegate:(id)delegate {
    delegate_ = delegate;
}

- (void) setPercent:(float)value {
    percent_ = value;
}

- (NSNumber *) percent {
    return [NSNumber numberWithFloat:percent_];
}

- (void) setCurrent:(float)value {
    current_ = value;
}

- (NSNumber *) current {
    return [NSNumber numberWithFloat:current_];
}

- (void) setTotal:(float)value {
    total_ = value;
}

- (NSNumber *) total {
    return [NSNumber numberWithFloat:total_];
}

- (void) setSpeed:(float)value {
    speed_ = value;
}

- (NSNumber *) speed {
    return [NSNumber numberWithFloat:speed_];
}

- (NSArray *) events {
    return events_;
}

- (void) removeAllEvents {
    [events_ removeAllObjects];
}

- (void) addEvent:(CydiaProgressEvent *)event {
    [events_ addObject:event];
}

- (void) setTitle:(NSString *)text {
    title_ = text;
}

- (NSString *) title {
    return title_;
}

- (void) setFinish:(NSString *)text {
    finish_ = text;
}

- (NSString *) finish {
    return (id) finish_ ?: [NSNull null];
}

- (void) setRunning:(bool)running {
    running_ = running;
}

- (NSNumber *) running {
    return running_ ? (NSNumber *) kCFBooleanTrue : (NSNumber *) kCFBooleanFalse;
}

@end
/* }}} */
/* Progress Controller {{{ */
@interface ProgressController : CydiaWebViewController <
    ProgressDelegate
> {
    _transient Database *database_;
    _H<CydiaProgressData, 1> progress_;
    unsigned cancel_;
}

- (id) initWithDatabase:(Database *)database delegate:(id)delegate;

- (void) invoke:(NSInvocation *)invocation withTitle:(NSString *)title;

- (void) setTitle:(NSString *)title;
- (void) setCancellable:(bool)cancellable;

@end

@implementation ProgressController

- (void) dealloc {
    [database_ setProgressDelegate:nil];
    [super dealloc];
}

- (UIBarButtonItem *) leftButton {
    return cancel_ == 1 ? [[[UIBarButtonItem alloc]
        initWithTitle:UCLocalize("CANCEL")
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(cancel)
    ] autorelease] : nil;
}

- (void) updateCancel {
    [super applyLeftButton];
}

- (id) initWithDatabase:(Database *)database delegate:(id)delegate {
    if ((self = [super init]) != nil) {
        database_ = database;
        delegate_ = delegate;

        [database_ setProgressDelegate:self];

        progress_ = [[[CydiaProgressData alloc] init] autorelease];
        [progress_ setDelegate:self];

        [self setURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/#!/progress/", UI_]]];

        [scroller_ setBackgroundColor:[UIColor blackColor]];

        [[self navigationItem] setHidesBackButton:YES];

        [self updateCancel];
    } return self;
}

- (void) webView:(WebView *)view didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame {
    [super webView:view didClearWindowObject:window forFrame:frame];
    [window setValue:progress_ forKey:@"cydiaProgress"];
}

- (void) updateProgress {
    [self dispatchEvent:@"CydiaProgressUpdate"];
}

- (void) viewWillAppear:(BOOL)animated {
    [[[self navigationController] navigationBar] setBarStyle:UIBarStyleBlack];
    [super viewWillAppear:animated];
}

- (void) close {
    UpdateExternalStatus(0);

    if (Finish_ > 1)
        [delegate_ saveState];

    switch (Finish_) {
        case 0:
            [delegate_ returnToCydia];
        break;

        case 1:
            [delegate_ terminateWithSuccess];
            /*if ([delegate_ respondsToSelector:@selector(suspendWithAnimation:)])
                [delegate_ suspendWithAnimation:YES];
            else
                [delegate_ suspend];*/
        break;

        case 2:
            _trace();
            goto reload;

        case 3:
            _trace();
            goto reload;

        reload:
            system("/usr/bin/sbreload");
            _trace();
        break;

        case 4:
            _trace();
            if (void (*SBReboot)(mach_port_t) = reinterpret_cast<void (*)(mach_port_t)>(dlsym(RTLD_DEFAULT, "SBReboot")))
                SBReboot(SBSSpringBoardServerPort());
            else
                reboot2(RB_AUTOBOOT);
        break;
    }

    [super close];
}

- (void) setTitle:(NSString *)title {
    [progress_ setTitle:title];
    [self updateProgress];
}

- (UIBarButtonItem *) rightButton {
    return [[progress_ running] boolValue] ? [super rightButton] : [[[UIBarButtonItem alloc]
        initWithTitle:UCLocalize("CLOSE")
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(close)
    ] autorelease];
}

- (void) uicache {
    _trace();
    system("su -c /usr/bin/uicache mobile");
    _trace();
}

- (void) invoke:(NSInvocation *)invocation withTitle:(NSString *)title {
    UpdateExternalStatus(1);

    [progress_ setRunning:true];
    [self setTitle:title];
    // implicit updateProgress

    SHA1SumValue notifyconf; {
        FileFd file;
        if (!file.Open(NotifyConfig_, FileFd::ReadOnly))
            _error->Discard();
        else {
            MMap mmap(file, MMap::ReadOnly);
            SHA1Summation sha1;
            sha1.Add(reinterpret_cast<uint8_t *>(mmap.Data()), mmap.Size());
            notifyconf = sha1.Result();
        }
    }

    SHA1SumValue springlist; {
        FileFd file;
        if (!file.Open(SpringBoard_, FileFd::ReadOnly))
            _error->Discard();
        else {
            MMap mmap(file, MMap::ReadOnly);
            SHA1Summation sha1;
            sha1.Add(reinterpret_cast<uint8_t *>(mmap.Data()), mmap.Size());
            springlist = sha1.Result();
        }
    }

    if (invocation != nil) {
        [invocation yieldToSelector:@selector(invoke)];
        [self setTitle:@"COMPLETE"];
    }

    if (Finish_ < 4) {
        FileFd file;
        if (!file.Open(NotifyConfig_, FileFd::ReadOnly))
            _error->Discard();
        else {
            MMap mmap(file, MMap::ReadOnly);
            SHA1Summation sha1;
            sha1.Add(reinterpret_cast<uint8_t *>(mmap.Data()), mmap.Size());
            if (!(notifyconf == sha1.Result()))
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
            if (!(springlist == sha1.Result()))
                Finish_ = 3;
        }
    }

    if (Finish_ < 2) {
        if (RestartSubstrate_)
            Finish_ = 2;
    }

    RestartSubstrate_ = false;

    switch (Finish_) {
        case 0: [progress_ setFinish:UCLocalize("RETURN_TO_CYDIA")]; break; /* XXX: Maybe UCLocalize("DONE")? */
        case 1: [progress_ setFinish:UCLocalize("CLOSE_CYDIA")]; break;
        case 2: [progress_ setFinish:UCLocalize("RESTART_SPRINGBOARD")]; break;
        case 3: [progress_ setFinish:UCLocalize("RELOAD_SPRINGBOARD")]; break;
        case 4: [progress_ setFinish:UCLocalize("REBOOT_DEVICE")]; break;
    }

    UIProgressHUD *hud([delegate_ addProgressHUD]);
    [hud setText:UCLocalize("LOADING")];
    [self yieldToSelector:@selector(uicache)];
    [delegate_ removeProgressHUD:hud];

    UpdateExternalStatus(Finish_ == 0 ? 0 : 2);

    [progress_ setRunning:false];
    [self updateProgress];

    [self applyRightButton];
}

- (void) addProgressEvent:(CydiaProgressEvent *)event {
    [progress_ addEvent:event];
    [self updateProgress];
}

- (bool) isProgressCancelled {
    return cancel_ == 2;
}

- (void) cancel {
    cancel_ = 2;
    [self updateCancel];
}

- (void) setCancellable:(bool)cancellable {
    unsigned cancel(cancel_);

    if (!cancellable)
        cancel_ = 0;
    else if (cancel_ == 0)
        cancel_ = 1;

    if (cancel != cancel_)
        [self updateCancel];
}

- (void) setProgressCancellable:(NSNumber *)cancellable {
    [self setCancellable:[cancellable boolValue]];
}

- (void) setProgressPercent:(NSNumber *)percent {
    [progress_ setPercent:[percent floatValue]];
    [self updateProgress];
}

- (void) setProgressStatus:(NSDictionary *)status {
    if (status == nil) {
        [progress_ setCurrent:0];
        [progress_ setTotal:0];
        [progress_ setSpeed:0];
    } else {
        [progress_ setPercent:[[status objectForKey:@"Percent"] floatValue]];

        [progress_ setCurrent:[[status objectForKey:@"Current"] floatValue]];
        [progress_ setTotal:[[status objectForKey:@"Total"] floatValue]];
        [progress_ setSpeed:[[status objectForKey:@"Speed"] floatValue]];
    }

    [self updateProgress];
}

@end
/* }}} */

/* Package Cell {{{ */
@interface PackageCell : CyteTableViewCell <
    CyteTableViewCellDelegate
> {
    _H<UIImage> icon_;
    _H<NSString> name_;
    _H<NSString> description_;
    bool commercial_;
    _H<NSString> source_;
    _H<UIImage> badge_;
    _H<UIImage> placard_;
    bool summarized_;
}

- (PackageCell *) init;
- (void) setPackage:(Package *)package asSummary:(bool)summary;

- (void) drawContentRect:(CGRect)rect;

@end

@implementation PackageCell

- (PackageCell *) init {
    CGRect frame(CGRectMake(0, 0, 320, 74));
    if ((self = [super initWithFrame:frame reuseIdentifier:@"Package"]) != nil) {
        UIView *content([self contentView]);
        CGRect bounds([content bounds]);

        content_ = [[[CyteTableViewCellContentView alloc] initWithFrame:bounds] autorelease];
        [content_ setAutoresizingMask:UIViewAutoresizingFlexibleBoth];
        [content addSubview:content_];

        [content_ setDelegate:self];
        [content_ setOpaque:YES];
    } return self;
}

- (NSString *) accessibilityLabel {
    return [NSString stringWithFormat:UCLocalize("COLON_DELIMITED"), (id) name_, (id) description_];
}

- (void) setPackage:(Package *)package asSummary:(bool)summary {
    summarized_ = summary;

    icon_ = nil;
    name_ = nil;
    description_ = nil;
    source_ = nil;
    badge_ = nil;
    placard_ = nil;

    if (package == nil)
        [content_ setBackgroundColor:[UIColor whiteColor]];
    else {
        [package parse];

        Source *source = [package source];

        icon_ = [package icon];

        if (NSString *name = [package name])
            name_ = [NSString stringWithString:name];

        NSString *description(nil);

        if (description == nil && IsWildcat_)
            description = [package longDescription];
        if (description == nil)
            description = [package shortDescription];

        if (description != nil)
            description_ = [NSString stringWithString:description];

        commercial_ = [package isCommercial];

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

        source_ = [NSString stringWithFormat:UCLocalize("FROM"), from];

        if (NSString *purpose = [package primaryPurpose])
            badge_ = [UIImage imageAtPath:[NSString stringWithFormat:@"%@/Purposes/%@.png", App_, purpose]];

        UIColor *color;
        NSString *placard;

        if (NSString *mode = [package mode]) {
            if ([mode isEqualToString:@"REMOVE"] || [mode isEqualToString:@"PURGE"]) {
                color = RemovingColor_;
                //placard = @"removing";
            } else {
                color = InstallingColor_;
                //placard = @"installing";
            }

            // XXX: the removing/installing placards are not @2x
            placard = nil;
        } else {
            color = [UIColor whiteColor];

            if ([package installed] != nil)
                placard = @"installed";
            else
                placard = nil;
        }

        [content_ setBackgroundColor:color];

        if (placard != nil)
            placard_ = [UIImage imageAtPath:[NSString stringWithFormat:@"%@/%@.png", App_, placard]];
    }

    [self setNeedsDisplay];
    [content_ setNeedsDisplay];
}

- (void) drawSummaryContentRect:(CGRect)rect {
    bool highlighted(highlighted_);
    float width([self bounds].size.width);

    if (icon_ != nil) {
        CGRect rect;
        rect.size = [(UIImage *) icon_ size];

        while (rect.size.width > 16 || rect.size.height > 16) {
            rect.size.width /= 2;
            rect.size.height /= 2;
        }

        rect.origin.x = 18 - rect.size.width / 2;
        rect.origin.y = 18 - rect.size.height / 2;

        [icon_ drawInRect:rect];
    }

    if (badge_ != nil) {
        CGRect rect;
        rect.size = [(UIImage *) badge_ size];

        rect.size.width /= 4;
        rect.size.height /= 4;

        rect.origin.x = 23 - rect.size.width / 2;
        rect.origin.y = 23 - rect.size.height / 2;

        [badge_ drawInRect:rect];
    }

    if (highlighted)
        UISetColor(White_);

    if (!highlighted)
        UISetColor(commercial_ ? Purple_ : Black_);
    [name_ drawAtPoint:CGPointMake(36, 8) forWidth:(width - (placard_ == nil ? 68 : 94)) withFont:Font18Bold_ lineBreakMode:UILineBreakModeTailTruncation];

    if (placard_ != nil)
        [placard_ drawAtPoint:CGPointMake(width - 52, 9)];
}

- (void) drawNormalContentRect:(CGRect)rect {
    bool highlighted(highlighted_);
    float width([self bounds].size.width);

    if (icon_ != nil) {
        CGRect rect;
        rect.size = [(UIImage *) icon_ size];

        while (rect.size.width > 32 || rect.size.height > 32) {
            rect.size.width /= 2;
            rect.size.height /= 2;
        }

        rect.origin.x = 25 - rect.size.width / 2;
        rect.origin.y = 25 - rect.size.height / 2;

        [icon_ drawInRect:rect];
    }

    if (badge_ != nil) {
        CGRect rect;
        rect.size = [(UIImage *) badge_ size];

        rect.size.width /= 2;
        rect.size.height /= 2;

        rect.origin.x = 36 - rect.size.width / 2;
        rect.origin.y = 36 - rect.size.height / 2;

        [badge_ drawInRect:rect];
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

- (void) drawContentRect:(CGRect)rect {
    if (summarized_)
        [self drawSummaryContentRect:rect];
    else
        [self drawNormalContentRect:rect];
}

@end
/* }}} */
/* Section Cell {{{ */
@interface SectionCell : CyteTableViewCell <
    CyteTableViewCellDelegate
> {
    _H<NSString> basic_;
    _H<NSString> section_;
    _H<NSString> name_;
    _H<NSString> count_;
    _H<UIImage> icon_;
    _H<UISwitch> switch_;
    BOOL editing_;
}

- (void) setSection:(Section *)section editing:(BOOL)editing;

@end

@implementation SectionCell

- (id) initWithFrame:(CGRect)frame reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithFrame:frame reuseIdentifier:reuseIdentifier]) != nil) {
        icon_ = [UIImage applicationImageNamed:@"folder.png"];
        switch_ = [[[UISwitch alloc] initWithFrame:CGRectMake(218, 9, 60, 25)] autorelease];
        [switch_ addTarget:self action:@selector(onSwitch:) forEvents:UIControlEventValueChanged];

        UIView *content([self contentView]);
        CGRect bounds([content bounds]);

        content_ = [[[CyteTableViewCellContentView alloc] initWithFrame:bounds] autorelease];
        [content_ setAutoresizingMask:UIViewAutoresizingFlexibleBoth];
        [content addSubview:content_];
        [content_ setBackgroundColor:[UIColor whiteColor]];

        [content_ setDelegate:self];
    } return self;
}

- (void) onSwitch:(id)sender {
    NSMutableDictionary *metadata([Sections_ objectForKey:basic_]);
    if (metadata == nil) {
        metadata = [NSMutableDictionary dictionaryWithCapacity:2];
        [Sections_ setObject:metadata forKey:basic_];
    }

    [metadata setObject:[NSNumber numberWithBool:([switch_ isOn] == NO)] forKey:@"Hidden"];
    Changed_ = true;
}

- (void) setSection:(Section *)section editing:(BOOL)editing {
    if (editing != editing_) {
        if (editing_)
            [switch_ removeFromSuperview];
        else
            [self addSubview:switch_];
        editing_ = editing;
    }

    basic_ = nil;
    section_ = nil;
    name_ = nil;
    count_ = nil;

    if (section == nil) {
        name_ = UCLocalize("ALL_PACKAGES");
        count_ = nil;
    } else {
        basic_ = [section name];
        section_ = [section localized];

        name_  = section_ == nil || [section_ length] == 0 ? UCLocalize("NO_SECTION") : (NSString *) section_;
        count_ = [NSString stringWithFormat:@"%d", [section count]];

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

- (NSString *) accessibilityLabel {
    return name_;
}

- (void) drawContentRect:(CGRect)rect {
    bool highlighted(highlighted_ && !editing_);

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
@interface FileTable : CyteViewController <
    UITableViewDataSource,
    UITableViewDelegate
> {
    _transient Database *database_;
    _H<Package> package_;
    _H<NSString> name_;
    _H<NSMutableArray> files_;
    _H<UITableView, 2> list_;
}

- (id) initWithDatabase:(Database *)database;
- (void) setPackage:(Package *)package;

@end

@implementation FileTable

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

- (NSURL *) navigationURL {
    return [NSURL URLWithString:[NSString stringWithFormat:@"cydia://package/%@/files", [package_ id]]];
}

- (void) loadView {
    list_ = [[[UITableView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame]] autorelease];
    [list_ setAutoresizingMask:UIViewAutoresizingFlexibleBoth];
    [list_ setRowHeight:24.0f];
    [(UITableView *) list_ setDataSource:self];
    [list_ setDelegate:self];
    [self setView:list_];
}

- (void) viewDidLoad {
    [super viewDidLoad];

    [[self navigationItem] setTitle:UCLocalize("INSTALLED_FILES")];
}

- (void) releaseSubviews {
    list_ = nil;

    package_ = nil;
    files_ = nil;

    [super releaseSubviews];
}

- (id) initWithDatabase:(Database *)database {
    if ((self = [super init]) != nil) {
        database_ = database;
    } return self;
}

- (void) setPackage:(Package *)package {
    package_ = nil;
    name_ = nil;

    files_ = [NSMutableArray arrayWithCapacity:32];

    if (package != nil) {
        package_ = package;
        name_ = [package id];

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
    [super reloadData];

    [self setPackage:[database_ packageWithName:name_]];
}

@end
/* }}} */
/* Package Controller {{{ */
@interface CYPackageController : CydiaWebViewController <
    UIActionSheetDelegate
> {
    _transient Database *database_;
    _H<Package> package_;
    _H<NSString> name_;
    bool commercial_;
    _H<NSMutableArray> buttons_;
    _H<UIBarButtonItem> button_;
}

- (id) initWithDatabase:(Database *)database forPackage:(NSString *)name;

@end

@implementation CYPackageController

- (NSURL *) navigationURL {
    return [NSURL URLWithString:[NSString stringWithFormat:@"cydia://package/%@", (id) name_]];
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
    // Don't reload a commerical package by tapping the loading button,
    // but if it's not an Install button, we should forward it on.
    if (![package_ uninstalled])
        [self _customButtonClicked];
}

- (void) applyLoadingTitle {
    // Don't show "Loading" as the title. Ever.
}

- (UIBarButtonItem *) rightButton {
    return button_;
}
#endif

- (id) initWithDatabase:(Database *)database forPackage:(NSString *)name {
    if ((self = [super init]) != nil) {
        database_ = database;
        buttons_ = [NSMutableArray arrayWithCapacity:4];
        name_ = name == nil ? @"" : [NSString stringWithString:name];
        [self setURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/#!/package/%@", UI_, (id) name_]]];
    } return self;
}

- (void) reloadData {
    [super reloadData];

    package_ = [database_ packageWithName:name_];

    [buttons_ removeAllObjects];

    if (package_ != nil) {
        [(Package *) package_ parse];

        commercial_ = [package_ isCommercial];

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

    NSString *title;
    switch ([buttons_ count]) {
        case 0: title = nil; break;
        case 1: title = [buttons_ objectAtIndex:0]; break;
        default: title = UCLocalize("MODIFY"); break;
    }

    button_ = [[[UIBarButtonItem alloc]
        initWithTitle:title
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(customButtonClicked)
    ] autorelease];
}

- (bool) isLoading {
    return commercial_ ? [super isLoading] : false;
}

@end
/* }}} */

/* Package List Controller {{{ */
@interface PackageListController : CyteViewController <
    UITableViewDataSource,
    UITableViewDelegate
> {
    _transient Database *database_;
    unsigned era_;
    _H<NSArray> packages_;
    _H<NSMutableArray> sections_;
    _H<UITableView, 2> list_;
    _H<NSMutableArray> index_;
    _H<NSMutableDictionary> indices_;
    _H<NSString> title_;
    unsigned reloading_;
}

- (id) initWithDatabase:(Database *)database title:(NSString *)title;
- (void) setDelegate:(id)delegate;
- (void) resetCursor;
- (void) clearData;

@end

@implementation PackageListController

- (bool) isSummarized {
    return false;
}

- (bool) showsSections {
    return true;
}

- (void) deselectWithAnimation:(BOOL)animated {
    [list_ deselectRowAtIndexPath:[list_ indexPathForSelectedRow] animated:animated];
}

- (void) resizeForKeyboardBounds:(CGRect)bounds duration:(NSTimeInterval)duration curve:(UIViewAnimationCurve)curve {
    CGRect base = [[self view] bounds];
    base.size.height -= bounds.size.height;
    base.origin = [list_ frame].origin;

    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationBeginsFromCurrentState:YES];
    [UIView setAnimationCurve:curve];
    [UIView setAnimationDuration:duration];
    [list_ setFrame:base];
    [UIView commitAnimations];
}

- (void) resizeForKeyboardBounds:(CGRect)bounds duration:(NSTimeInterval)duration {
    [self resizeForKeyboardBounds:bounds duration:duration curve:UIViewAnimationCurveLinear];
}

- (void) resizeForKeyboardBounds:(CGRect)bounds {
    [self resizeForKeyboardBounds:bounds duration:0];
}

- (void) getKeyboardCurve:(UIViewAnimationCurve *)curve duration:(NSTimeInterval *)duration forNotification:(NSNotification *)notification {
    if (&UIKeyboardAnimationCurveUserInfoKey == NULL)
        *curve = UIViewAnimationCurveEaseInOut;
    else
        [[[notification userInfo] objectForKey:UIKeyboardAnimationCurveUserInfoKey] getValue:curve];

    if (&UIKeyboardAnimationDurationUserInfoKey == NULL)
        *duration = 0.3;
    else
        [[[notification userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] getValue:duration];
}

- (void) keyboardWillShow:(NSNotification *)notification {
    CGRect bounds;
    CGPoint center;
    [[[notification userInfo] objectForKey:UIKeyboardBoundsUserInfoKey] getValue:&bounds];
    [[[notification userInfo] objectForKey:UIKeyboardCenterEndUserInfoKey] getValue:&center];

    NSTimeInterval duration;
    UIViewAnimationCurve curve;
    [self getKeyboardCurve:&curve duration:&duration forNotification:notification];

    CGRect kbframe = CGRectMake(round(center.x - bounds.size.width / 2.0), round(center.y - bounds.size.height / 2.0), bounds.size.width, bounds.size.height);
    UIViewController *base = self;
    while ([base parentViewController] != nil)
        base = [base parentViewController];
    CGRect viewframe = [[base view] convertRect:[list_ frame] fromView:[list_ superview]];
    CGRect intersection = CGRectIntersection(viewframe, kbframe);

    if (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iPhoneOS_3_0) // XXX: _UIApplicationLinkedOnOrAfter(4)
        intersection.size.height += CYStatusBarHeight();

    [self resizeForKeyboardBounds:intersection duration:duration curve:curve];
}

- (void) keyboardWillHide:(NSNotification *)notification {
    NSTimeInterval duration;
    UIViewAnimationCurve curve;
    [self getKeyboardCurve:&curve duration:&duration forNotification:notification];

    [self resizeForKeyboardBounds:CGRectZero duration:duration curve:curve];
}

- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self resizeForKeyboardBounds:CGRectZero];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void) viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self resizeForKeyboardBounds:CGRectZero];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
}

- (void) viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self deselectWithAnimation:animated];
}

- (void) didSelectPackage:(Package *)package {
    CYPackageController *view([[[CYPackageController alloc] initWithDatabase:database_ forPackage:[package id]] autorelease]);
    [view setDelegate:delegate_];
    [[self navigationController] pushViewController:view animated:YES];
}

#if TryIndexedCollation
+ (BOOL) hasIndexedCollation {
    return NO; // XXX: objc_getClass("UILocalizedIndexedCollation") != nil;
}
#endif

- (NSInteger) numberOfSectionsInTableView:(UITableView *)list {
    NSInteger count([sections_ count]);
    return count == 0 ? 1 : count;
}

- (NSString *) tableView:(UITableView *)list titleForHeaderInSection:(NSInteger)section {
    if ([sections_ count] == 0 || [[sections_ objectAtIndex:section] count] == 0)
        return nil;
    return [[sections_ objectAtIndex:section] name];
}

- (NSInteger) tableView:(UITableView *)list numberOfRowsInSection:(NSInteger)section {
    if ([sections_ count] == 0)
        return 0;
    return [[sections_ objectAtIndex:section] count];
}

- (Package *) packageAtIndexPath:(NSIndexPath *)path {
@synchronized (database_) {
    if ([database_ era] != era_)
        return nil;

    Section *section([sections_ objectAtIndex:[path section]]);
    NSInteger row([path row]);
    Package *package([packages_ objectAtIndex:([section row] + row)]);
    return [[package retain] autorelease];
} }

- (UITableViewCell *) tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    PackageCell *cell((PackageCell *) [table dequeueReusableCellWithIdentifier:@"Package"]);
    if (cell == nil)
        cell = [[[PackageCell alloc] init] autorelease];

    Package *package([database_ packageWithName:[[self packageAtIndexPath:path] id]]);
    [cell setPackage:package asSummary:[self isSummarized]];
    return cell;
}

- (void) tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    Package *package([self packageAtIndexPath:path]);
    package = [database_ packageWithName:[package id]];
    [self didSelectPackage:package];
}

- (NSArray *) sectionIndexTitlesForTableView:(UITableView *)tableView {
    if (![self showsSections])
        return nil;

    return index_;
}

- (NSInteger) tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index {
#if TryIndexedCollation
    if ([[self class] hasIndexedCollation]) {
        return [[objc_getClass("UILocalizedIndexedCollation") currentCollation] sectionForSectionIndexTitleAtIndex:index];
    }
#endif

    return index;
}

- (void) updateHeight {
    [list_ setRowHeight:([self isSummarized] ? 38 : 73)];
}

- (id) initWithDatabase:(Database *)database title:(NSString *)title {
    if ((self = [super init]) != nil) {
        database_ = database;
        title_ = [title copy];
        [[self navigationItem] setTitle:title_];
    } return self;
}

- (void) loadView {
    UIView *view([[[UIView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame]] autorelease]);
    [view setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)];
    [self setView:view];

    list_ = [[[UITableView alloc] initWithFrame:[[self view] bounds] style:UITableViewStylePlain] autorelease];
    [list_ setAutoresizingMask:UIViewAutoresizingFlexibleBoth];
    [view addSubview:list_];

    // XXX: is 20 the most optimal number here?
    [list_ setSectionIndexMinimumDisplayRowCount:20];

    [(UITableView *) list_ setDataSource:self];
    [list_ setDelegate:self];

    [self updateHeight];
}

- (void) releaseSubviews {
    list_ = nil;

    packages_ = nil;
    sections_ = nil;
    index_ = nil;
    indices_ = nil;

    [super releaseSubviews];
}

- (void) setDelegate:(id)delegate {
    delegate_ = delegate;
}

- (bool) shouldYield {
    return false;
}

- (bool) shouldBlock {
    return false;
}

- (NSMutableArray *) _reloadPackages {
@synchronized (database_) {
    era_ = [database_ era];
    NSArray *packages([database_ packages]);

    return [NSMutableArray arrayWithArray:packages];
} }

- (void) _reloadData {
    if (reloading_ != 0) {
        reloading_ = 2;
        return;
    }

    NSArray *packages;

  reload:
    if ([self shouldYield]) {
        do {
            UIProgressHUD *hud;

            if (![self shouldBlock])
                hud = nil;
            else {
                hud = [delegate_ addProgressHUD];
                [hud setText:UCLocalize("LOADING")];
            }

            reloading_ = 1;
            packages = [self yieldToSelector:@selector(_reloadPackages)];

            if (hud != nil)
                [delegate_ removeProgressHUD:hud];
        } while (reloading_ == 2);
    } else {
        packages = [self _reloadPackages];
    }

@synchronized (database_) {
    if (era_ != [database_ era])
        goto reload;
    reloading_ = 0;

    packages_ = packages;

    indices_ = [NSMutableDictionary dictionaryWithCapacity:32];
    sections_ = [NSMutableArray arrayWithCapacity:16];

    Section *section = nil;

#if TryIndexedCollation
    if ([[self class] hasIndexedCollation]) {
        index_ = [[objc_getClass("UILocalizedIndexedCollation") currentCollation] sectionIndexTitles];

        id collation = [objc_getClass("UILocalizedIndexedCollation") currentCollation];
        NSArray *titles = [collation sectionIndexTitles];
        int secidx = -1;

        _profile(PackageTable$reloadData$Section)
            for (size_t offset(0), end([packages_ count]); offset != end; ++offset) {
                Package *package;
                int index;

                _profile(PackageTable$reloadData$Section$Package)
                    package = [packages_ objectAtIndex:offset];
                    index = [collation sectionForObject:package collationStringSelector:@selector(name)];
                _end

                while (secidx < index) {
                    secidx += 1;

                    _profile(PackageTable$reloadData$Section$Allocate)
                        section = [[[Section alloc] initWithName:[titles objectAtIndex:secidx] row:offset localize:NO] autorelease];
                    _end

                    _profile(PackageTable$reloadData$Section$Add)
                        [sections_ addObject:section];
                    _end
                }

                [section addToCount];
            }
        _end
    } else
#endif
    {
        index_ = [NSMutableArray arrayWithCapacity:32];

        bool sectioned([self showsSections]);
        if (!sectioned) {
            section = [[[Section alloc] initWithName:nil localize:false] autorelease];
            [sections_ addObject:section];
        }

        _profile(PackageTable$reloadData$Section)
            for (size_t offset(0), end([packages_ count]); offset != end; ++offset) {
                Package *package;
                unichar index;

                _profile(PackageTable$reloadData$Section$Package)
                    package = [packages_ objectAtIndex:offset];
                    index = [package index];
                _end

                if (sectioned && (section == nil || [section index] != index)) {
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
    }

    [self updateHeight];

    _profile(PackageTable$reloadData$List)
        [(UITableView *) list_ setDataSource:self];
        [list_ reloadData];
    _end
} }

- (void) reloadData {
    [super reloadData];

    if ([self shouldYield])
        [self performSelector:@selector(_reloadData) withObject:nil afterDelay:0];
    else
        [self _reloadData];
}

- (void) resetCursor {
    [list_ scrollRectToVisible:CGRectMake(0, 0, 1, 1) animated:NO];
}

- (void) clearData {
    [self updateHeight];

    [list_ setDataSource:nil];
    [list_ reloadData];

    [self resetCursor];
}

@end
/* }}} */
/* Filtered Package List Controller {{{ */
@interface FilteredPackageListController : PackageListController {
    SEL filter_;
    IMP imp_;
    _H<NSObject> object_;
}

- (void) setObject:(id)object;
- (void) setObject:(id)object forFilter:(SEL)filter;

- (SEL) filter;
- (void) setFilter:(SEL)filter;

- (id) initWithDatabase:(Database *)database title:(NSString *)title filter:(SEL)filter with:(id)object;

@end

@implementation FilteredPackageListController

- (SEL) filter {
    return filter_;
}

- (void) setFilter:(SEL)filter {
@synchronized (self) {
    filter_ = filter;

    /* XXX: this is an unsafe optimization of doomy hell */
    Method method(class_getInstanceMethod([Package class], filter));
    _assert(method != NULL);
    imp_ = method_getImplementation(method);
    _assert(imp_ != NULL);
} }

- (void) setObject:(id)object {
@synchronized (self) {
    object_ = object;
} }

- (void) setObject:(id)object forFilter:(SEL)filter {
@synchronized (self) {
    [self setFilter:filter];
    [self setObject:object];
} }

- (NSMutableArray *) _reloadPackages {
@synchronized (database_) {
    era_ = [database_ era];
    NSArray *packages([database_ packages]);

    NSMutableArray *filtered([NSMutableArray arrayWithCapacity:[packages count]]);

    IMP imp;
    SEL filter;
    _H<NSObject> object;

    @synchronized (self) {
        imp = imp_;
        filter = filter_;
        object = object_;
    }

    _profile(PackageTable$reloadData$Filter)
        for (Package *package in packages)
            if ([package valid] && (*reinterpret_cast<bool (*)(id, SEL, id)>(imp))(package, filter, object))
                [filtered addObject:package];
    _end

    return filtered;
} }

- (id) initWithDatabase:(Database *)database title:(NSString *)title filter:(SEL)filter with:(id)object {
    if ((self = [super initWithDatabase:database title:title]) != nil) {
        [self setFilter:filter];
        [self setObject:object];
    } return self;
}

@end
/* }}} */

/* Home Controller {{{ */
@interface HomeController : CydiaWebViewController {
}

@end

@implementation HomeController

- (id) init {
    if ((self = [super init]) != nil) {
        [self setURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/#!/home/", UI_]]];
        [self reloadData];
    } return self;
}

- (NSURL *) navigationURL {
    return [NSURL URLWithString:@"cydia://home"];
}

- (void) aboutButtonClicked {
    UIAlertView *alert([[[UIAlertView alloc] init] autorelease]);

    [alert setTitle:UCLocalize("ABOUT_CYDIA")];
    [alert addButtonWithTitle:UCLocalize("CLOSE")];
    [alert setCancelButtonIndex:0];

    [alert setMessage:
        @"Copyright \u00a9 2008-2011\n"
        "SaurikIT, LLC\n"
        "\n"
        "Jay Freeman (saurik)\n"
        "saurik@saurik.com\n"
        "http://www.saurik.com/"
    ];

    [alert show];
}

- (UIBarButtonItem *) leftButton {
    return [[[UIBarButtonItem alloc]
        initWithTitle:UCLocalize("ABOUT")
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(aboutButtonClicked)
    ] autorelease];
}

@end
/* }}} */
/* Manage Controller {{{ */
@interface ManageController : CydiaWebViewController {
}

- (void) queueStatusDidChange;

@end

@implementation ManageController

- (id) init {
    if ((self = [super init]) != nil) {
        [self setURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"manage" ofType:@"html"]]];
    } return self;
}

- (NSURL *) navigationURL {
    return [NSURL URLWithString:@"cydia://manage"];
}

- (UIBarButtonItem *) leftButton {
    return [[[UIBarButtonItem alloc]
        initWithTitle:UCLocalize("SETTINGS")
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(settingsButtonClicked)
    ] autorelease];
}

- (void) settingsButtonClicked {
    [delegate_ showSettings];
}

- (void) queueButtonClicked {
    [delegate_ queue];
}

- (UIBarButtonItem *) rightButton {
    return Queuing_ ? [[[UIBarButtonItem alloc]
        initWithTitle:UCLocalize("QUEUE")
        style:UIBarButtonItemStyleDone
        target:self
        action:@selector(queueButtonClicked)
    ] autorelease] : nil;
}

- (void) queueStatusDidChange {
    [self applyRightButton];
}

- (bool) isLoading {
    return !Queuing_ && [super isLoading];
}

@end
/* }}} */

/* Refresh Bar {{{ */
@interface RefreshBar : UINavigationBar {
    _H<UIProgressIndicator> indicator_;
    _H<UITextLabel> prompt_;
    _H<UIProgressBar> progress_;
    _H<UINavigationButton> cancel_;
}

@end

@implementation RefreshBar

- (void) positionViews {
    CGRect frame = [cancel_ frame];
    frame.size = [cancel_ sizeThatFits:frame.size];
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

- (void) setFrame:(CGRect)frame {
    [super setFrame:frame];
    [self positionViews];
}

- (id) initWithFrame:(CGRect)frame delegate:(id)delegate {
    if ((self = [super initWithFrame:frame]) != nil) {
        [self setAutoresizingMask:UIViewAutoresizingFlexibleWidth];

        [self setBarStyle:UIBarStyleBlack];

        UIBarStyle barstyle([self _barStyle:NO]);
        bool ugly(barstyle == UIBarStyleDefault);

        UIProgressIndicatorStyle style = ugly ?
            UIProgressIndicatorStyleMediumBrown :
            UIProgressIndicatorStyleMediumWhite;

        indicator_ = [[[UIProgressIndicator alloc] initWithFrame:CGRectZero] autorelease];
        [(UIProgressIndicator *) indicator_ setStyle:style];
        [indicator_ startAnimation];
        [self addSubview:indicator_];

        prompt_ = [[[UITextLabel alloc] initWithFrame:CGRectZero] autorelease];
        [prompt_ setColor:[UIColor colorWithCGColor:(ugly ? Blueish_ : Off_)]];
        [prompt_ setBackgroundColor:[UIColor clearColor]];
        [prompt_ setFont:[UIFont systemFontOfSize:15]];
        [self addSubview:prompt_];

        progress_ = [[[UIProgressBar alloc] initWithFrame:CGRectZero] autorelease];
        [progress_ setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin];
        [(UIProgressBar *) progress_ setStyle:0];
        [self addSubview:progress_];

        cancel_ = [[[UINavigationButton alloc] initWithTitle:UCLocalize("CANCEL") style:UINavigationButtonStyleHighlighted] autorelease];
        [cancel_ setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin];
        [cancel_ addTarget:delegate action:@selector(cancelPressed) forControlEvents:UIControlEventTouchUpInside];
        [cancel_ setBarStyle:barstyle];

        [self positionViews];
    } return self;
}

- (void) setCancellable:(bool)cancellable {
    if (cancellable)
        [self addSubview:cancel_];
    else
        [cancel_ removeFromSuperview];
}

- (void) start {
    [prompt_ setText:UCLocalize("UPDATING_DATABASE")];
    [progress_ setProgress:0];
}

- (void) stop {
    [self setCancellable:NO];
}

- (void) setPrompt:(NSString *)prompt {
    [prompt_ setText:prompt];
}

- (void) setProgress:(float)progress {
    [progress_ setProgress:progress];
}

@end
/* }}} */

/* Cydia Navigation Controller Interface {{{ */
@interface UINavigationController (Cydia)

- (NSArray *) navigationURLCollection;
- (void) unloadData;

@end
/* }}} */

/* Cydia Tab Bar Controller {{{ */
@interface CYTabBarController : UITabBarController <
    UITabBarControllerDelegate,
    ProgressDelegate
> {
    _transient Database *database_;
    _H<RefreshBar, 1> refreshbar_;

    bool dropped_;
    bool updating_;
    // XXX: ok, "updatedelegate_"?...
    _transient NSObject<CydiaDelegate> *updatedelegate_;

    _H<UIViewController> remembered_;
    _transient UIViewController *transient_;
}

- (NSArray *) navigationURLCollection;
- (void) dropBar:(BOOL)animated;
- (void) beginUpdate;
- (void) raiseBar:(BOOL)animated;
- (BOOL) updating;
- (void) unloadData;

@end

@implementation CYTabBarController

- (void) didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];

    // presenting a UINavigationController on 2.x does not update its transitionView
    // it thereby will not allow its topViewController to be unloaded by memory pressure
    if (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iPhoneOS_3_0) {
        UIViewController *selected([self selectedViewController]);
        for (UINavigationController *controller in [self viewControllers])
            if (controller != selected)
                if (UIViewController *top = [controller topViewController])
                    [top unloadView];
    }
}

- (void) setUnselectedViewController:(UIViewController *)transient {
    if (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iPhoneOS_3_0) {
        if (transient != nil) {
            [[[self viewControllers] objectAtIndex:0] pushViewController:transient animated:YES];
            [self setSelectedIndex:0];
        } return;
    }

    UINavigationController *navigation([[[UINavigationController alloc] init] autorelease]);
    [navigation setViewControllers:[NSArray arrayWithObject:transient]];
    transient = navigation;

    NSMutableArray *controllers = [[self viewControllers] mutableCopy];
    if (transient != nil) {
        if (transient_ == nil)
            remembered_ = [controllers objectAtIndex:0];
        transient_ = transient;
        [transient_ setTabBarItem:[remembered_ tabBarItem]];
        [controllers replaceObjectAtIndex:0 withObject:transient_];
        [self setSelectedIndex:0];
        [self setViewControllers:controllers];
        [self concealTabBarSelection];
    } else if (remembered_ != nil) {
        [remembered_ setTabBarItem:[transient_ tabBarItem]];
        transient_ = transient;
        [controllers replaceObjectAtIndex:0 withObject:remembered_];
        remembered_ = nil;
        [self setViewControllers:controllers];
        [self revealTabBarSelection];
    }
}

- (UIViewController *) unselectedViewController {
    return transient_;
}

- (void) tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController {
    if ([self unselectedViewController])
        [self setUnselectedViewController:nil];

    // presenting a UINavigationController on 2.x does not update its transitionView
    // if this view was unloaded, the tranitionView may currently be presenting nothing
    if (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iPhoneOS_3_0) {
        UINavigationController *navigation((UINavigationController *) viewController);
        [navigation pushViewController:[[[UIViewController alloc] init] autorelease] animated:NO];
        [navigation popViewControllerAnimated:NO];
    }
}

- (NSArray *) navigationURLCollection {
    NSMutableArray *items([NSMutableArray array]);

    // XXX: Should this deal with transient view controllers?
    for (id navigation in [self viewControllers]) {
        NSArray *stack = [navigation performSelector:@selector(navigationURLCollection)];
        if (stack != nil)
            [items addObject:stack];
    }

    return items;
}

- (void) dismissModalViewControllerAnimated:(BOOL)animated {
    if ([self modalViewController] == nil && [self unselectedViewController] != nil)
        [self setUnselectedViewController:nil];
    else
        [super dismissModalViewControllerAnimated:YES];
}

- (void) unloadData {
    [super unloadData];

    for (UINavigationController *controller in [self viewControllers])
        [controller unloadData];

    if (UIViewController *selected = [self selectedViewController])
        [selected reloadData];

    if (UIViewController *unselected = [self unselectedViewController]) {
        [unselected unloadData];
        [unselected reloadData];
    }
}

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [super dealloc];
}

- (id) initWithDatabase:(Database *)database {
    if ((self = [super init]) != nil) {
        database_ = database;
        [self setDelegate:self];

        [[self view] setAutoresizingMask:UIViewAutoresizingFlexibleBoth];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusBarFrameChanged:) name:UIApplicationDidChangeStatusBarFrameNotification object:nil];

        refreshbar_ = [[[RefreshBar alloc] initWithFrame:CGRectMake(0, 0, [[self view] frame].size.width, [UINavigationBar defaultSize].height) delegate:self] autorelease];
    } return self;
}

- (void) setUpdate:(NSDate *)date {
    [self beginUpdate];
}

- (void) beginUpdate {
    [(RefreshBar *) refreshbar_ start];
    [self dropBar:YES];

    [updatedelegate_ retainNetworkActivityIndicator];
    updating_ = true;

    [NSThread
        detachNewThreadSelector:@selector(performUpdate)
        toTarget:self
        withObject:nil
    ];
}

- (void) performUpdate {
    NSAutoreleasePool *pool([[NSAutoreleasePool alloc] init]);

    Status status;
    status.setDelegate(self);
    [database_ updateWithStatus:status];

    [self
        performSelectorOnMainThread:@selector(completeUpdate)
        withObject:nil
        waitUntilDone:NO
    ];

    [pool release];
}

- (void) stopUpdateWithSelector:(SEL)selector {
    updating_ = false;
    [updatedelegate_ releaseNetworkActivityIndicator];

    [self raiseBar:YES];
    [refreshbar_ stop];

    [updatedelegate_ performSelector:selector withObject:nil afterDelay:0];
}

- (void) completeUpdate {
    if (!updating_)
        return;
    [self stopUpdateWithSelector:@selector(reloadData)];
}

- (void) cancelUpdate {
    [self stopUpdateWithSelector:@selector(updateData)];
}

- (void) cancelPressed {
    [self cancelUpdate];
}

- (BOOL) updating {
    return updating_;
}

- (void) addProgressEvent:(CydiaProgressEvent *)event {
    [refreshbar_ setPrompt:[event compoundMessage]];
}

- (bool) isProgressCancelled {
    return !updating_;
}

- (void) setProgressCancellable:(NSNumber *)cancellable {
    [refreshbar_ setCancellable:(updating_ && [cancellable boolValue])];
}

- (void) setProgressPercent:(NSNumber *)percent {
    [refreshbar_ setProgress:[percent floatValue]];
}

- (void) setProgressStatus:(NSDictionary *)status {
    if (status != nil)
        [self setProgressPercent:[status objectForKey:@"Percent"]];
}

- (void) setUpdateDelegate:(id)delegate {
    updatedelegate_ = delegate;
}

- (UIView *) transitionView {
    if ([self respondsToSelector:@selector(_transitionView)])
        return [self _transitionView];
    else
        return MSHookIvar<id>(self, "_viewControllerTransitionView");
}

- (void) dropBar:(BOOL)animated {
    if (dropped_)
        return;
    dropped_ = true;

    UIView *transition([self transitionView]);
    [[self view] addSubview:refreshbar_];

    CGRect barframe([refreshbar_ frame]);

    if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iPhoneOS_3_0) // XXX: _UIApplicationLinkedOnOrAfter(4)
        barframe.origin.y = CYStatusBarHeight();
    else
        barframe.origin.y = 0;

    [refreshbar_ setFrame:barframe];

    if (animated)
        [UIView beginAnimations:nil context:NULL];

    CGRect viewframe = [transition frame];
    viewframe.origin.y += barframe.size.height;
    viewframe.size.height -= barframe.size.height;
    [transition setFrame:viewframe];

    if (animated)
        [UIView commitAnimations];

    // Ensure bar has the proper width for our view, it might have changed
    barframe.size.width = viewframe.size.width;
    [refreshbar_ setFrame:barframe];
}

- (void) raiseBar:(BOOL)animated {
    if (!dropped_)
        return;
    dropped_ = false;

    UIView *transition([self transitionView]);
    [refreshbar_ removeFromSuperview];

    CGRect barframe([refreshbar_ frame]);

    if (animated)
        [UIView beginAnimations:nil context:NULL];

    CGRect viewframe = [transition frame];
    viewframe.origin.y -= barframe.size.height;
    viewframe.size.height += barframe.size.height;
    [transition setFrame:viewframe];

    if (animated)
        [UIView commitAnimations];
}

- (void) didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    bool dropped(dropped_);

    if (dropped)
        [self raiseBar:NO];

    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];

    if (dropped)
        [self dropBar:NO];
}

- (void) statusBarFrameChanged:(NSNotification *)notification {
    if (dropped_) {
        [self raiseBar:NO];
        [self dropBar:NO];
    }
}

@end
/* }}} */

/* Cydia Navigation Controller Implementation {{{ */
@implementation UINavigationController (Cydia)

- (NSArray *) navigationURLCollection {
    NSMutableArray *stack([NSMutableArray array]);

    for (CyteViewController *controller in [self viewControllers]) {
        NSString *url = [[controller navigationURL] absoluteString];
        if (url != nil)
            [stack addObject:url];
    }

    return stack;
}

- (void) reloadData {
    [super reloadData];

    UIViewController *visible([self visibleViewController]);
    if (visible != nil)
        [visible reloadData];

    // on the iPad, this view controller is ALSO visible. :(
    if (IsWildcat_)
        if (UIViewController *top = [self topViewController])
            if (top != visible)
                [top reloadData];
}

- (void) unloadData {
    for (CyteViewController *page in [self viewControllers])
        [page unloadData];

    [super unloadData];
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
    if (scheme != nil && [scheme isEqualToString:@"cydia"])
        return YES;
    if ([[url absoluteString] hasPrefix:@"about:cydia-"])
        return YES;

    return NO;
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
    NSString *scheme([[url scheme] lowercaseString]);

    NSString *path;

    if ([scheme isEqualToString:@"cydia"])
        path = [href substringFromIndex:8];
    else if ([scheme isEqualToString:@"about"])
        path = [href substringFromIndex:12];
    else _assert(false);

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
        [package parse];
        UIImage *icon([package icon]);
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
        UIImage *icon([UIImage imageAtPath:[NSString stringWithFormat:@"%@/Sections/%@.png", App_, [path stringByReplacingOccurrencesOfString:@" " withString:@"_"]]]);
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

/* Section Controller {{{ */
@interface SectionController : FilteredPackageListController {
    _H<IndirectDelegate, 1> indirect_;
    _H<CydiaObject> cydia_;
    _H<NSString> section_;
    std::vector< _H<CyteWebViewTableViewCell, 1> > promoted_;
}

- (id) initWithDatabase:(Database *)database section:(NSString *)section;

@end

@implementation SectionController

- (NSURL *) navigationURL {
    NSString *name = section_;
    if (name == nil)
        name = @"all";

    return [NSURL URLWithString:[NSString stringWithFormat:@"cydia://sections/%@", [name stringByAddingPercentEscapesIncludingReserved]]];
}

- (id) initWithDatabase:(Database *)database section:(NSString *)name {
    NSString *title;
    if (name == nil)
        title = UCLocalize("ALL_PACKAGES");
    else if (![name isEqual:@""])
        title = [[NSBundle mainBundle] localizedStringForKey:Simplify(name) value:nil table:@"Sections"];
    else
        title = UCLocalize("NO_SECTION");

    if ((self = [super initWithDatabase:database title:title filter:@selector(isVisibleInSection:) with:name]) != nil) {
        indirect_ = [[[IndirectDelegate alloc] initWithDelegate:self] autorelease];
        cydia_ = [[[CydiaObject alloc] initWithDelegate:indirect_] autorelease];
        section_ = name;
    } return self;
}

- (NSInteger) numberOfSectionsInTableView:(UITableView *)list {
    return [super numberOfSectionsInTableView:list] + 1;
}

- (NSString *) tableView:(UITableView *)list titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? nil : [super tableView:list titleForHeaderInSection:(section - 1)];
}

- (NSInteger) tableView:(UITableView *)list numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? promoted_.size() : [super tableView:list numberOfRowsInSection:(section - 1)];
}

+ (NSIndexPath *) adjustedIndexPath:(NSIndexPath *)path {
    return [NSIndexPath indexPathForRow:[path row] inSection:([path section] - 1)];
}

- (UITableViewCell *) tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    if ([path section] != 0)
        return [super tableView:table cellForRowAtIndexPath:[SectionController adjustedIndexPath:path]];

    return promoted_[[path row]];
}

- (void) tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    if ([path section] != 0)
        return [super tableView:table didSelectRowAtIndexPath:[SectionController adjustedIndexPath:path]];
}

- (NSInteger) tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index {
    NSInteger section([super tableView:tableView sectionForSectionIndexTitle:title atIndex:index]);
    return section == 0 ? 0 : section + 1;
}

- (void) webView:(WebView *)view decidePolicyForNewWindowAction:(NSDictionary *)action request:(NSURLRequest *)request newFrameName:(NSString *)frame decisionListener:(id<WebPolicyDecisionListener>)listener {
    NSURL *url([request URL]);
    if (url == nil)
        return;

    if ([frame isEqualToString:@"_open"])
        [delegate_ openURL:url];
    else {
        CyteViewController *controller([delegate_ pageForURL:url forExternal:NO] ?: [[[CydiaWebViewController alloc] initWithRequest:request] autorelease]);
        [controller setDelegate:delegate_];
        [[self navigationController] pushViewController:controller animated:YES];
    }

    [listener ignore];
}

- (NSURLRequest *) webView:(WebView *)view resource:(id)resource willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response fromDataSource:(WebDataSource *)source {
    return [CydiaWebViewController requestWithHeaders:request];
}

- (void) webView:(WebView *)view didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame {
    [CydiaWebViewController didClearWindowObject:window forFrame:frame withCydia:cydia_];
}

- (void) loadView {
    [super loadView];

    // XXX: this code is horrible. I mean, wtf Jay?
    if (ShowPromoted_ && [[Metadata_ objectForKey:@"ShowPromoted"] boolValue]) {
        promoted_.resize(1);

        for (unsigned i(0); i != promoted_.size(); ++i) {
            CyteWebViewTableViewCell *promoted([CyteWebViewTableViewCell cellWithRequest:[NSURLRequest
                requestWithURL:[Diversion divertURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/#!/sectionhead/%u/%@",
                    UI_, i, section_ == nil ? @"" : [section_ stringByAddingPercentEscapesIncludingReserved]]
                ]]

                cachePolicy:NSURLRequestUseProtocolCachePolicy
                timeoutInterval:120
            ]]);

            [promoted setDelegate:self];
            promoted_[i] = promoted;
        }
    }
}

- (void) setDelegate:(id)delegate {
    [super setDelegate:delegate];
    [cydia_ setDelegate:delegate];
}

- (void) releaseSubviews {
    promoted_.clear();
    [super releaseSubviews];
}

@end
/* }}} */
/* Sections Controller {{{ */
@interface SectionsController : CyteViewController <
    UITableViewDataSource,
    UITableViewDelegate
> {
    _transient Database *database_;
    _H<NSMutableArray> sections_;
    _H<NSMutableArray> filtered_;
    _H<UITableView, 2> list_;
}

- (id) initWithDatabase:(Database *)database;
- (void) editButtonClicked;

@end

@implementation SectionsController

- (NSURL *) navigationURL {
    return [NSURL URLWithString:@"cydia://sections"];
}

- (void) updateNavigationItem {
    [[self navigationItem] setTitle:[self isEditing] ? UCLocalize("SECTION_VISIBILITY") : UCLocalize("SECTIONS")];
    if ([sections_ count] == 0) {
        [[self navigationItem] setRightBarButtonItem:nil];
    } else {
        [[self navigationItem] setRightBarButtonItem:[[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:([self isEditing] ? UIBarButtonSystemItemDone : UIBarButtonSystemItemEdit)
            target:self
            action:@selector(editButtonClicked)
        ] animated:([[self navigationItem] rightBarButtonItem] != nil)];
    }
}

- (void) setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];

    if (editing)
        [list_ reloadData];
    else
        [delegate_ updateData];

    [self updateNavigationItem];
}

- (void) viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [list_ deselectRowAtIndexPath:[list_ indexPathForSelectedRow] animated:animated];
}

- (void) viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self setEditing:NO];
}

- (Section *) sectionAtIndexPath:(NSIndexPath *)indexPath {
    Section *section = nil;
    int index = [indexPath row];
    if (![self isEditing]) {
        index -= 1; 
        if (index >= 0)
            section = [filtered_ objectAtIndex:index];
    } else {
        section = [sections_ objectAtIndex:index];
    }
    return section;
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self isEditing])
        return [sections_ count];
    else
        return [filtered_ count] + 1;
}

/*- (CGFloat) tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 45.0f;
}*/

- (UITableViewCell *) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuseIdentifier = @"SectionCell";

    SectionCell *cell = (SectionCell *)[tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (cell == nil)
        cell = [[[SectionCell alloc] initWithFrame:CGRectZero reuseIdentifier:reuseIdentifier] autorelease];

    [cell setSection:[self sectionAtIndexPath:indexPath] editing:[self isEditing]];

    return cell;
}

- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isEditing])
        return;

    Section *section = [self sectionAtIndexPath:indexPath];

    SectionController *controller = [[[SectionController alloc]
        initWithDatabase:database_
        section:[section name]
    ] autorelease];
    [controller setDelegate:delegate_];

    [[self navigationController] pushViewController:controller animated:YES];
}

- (void) loadView {
    list_ = [[[UITableView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame]] autorelease];
    [list_ setAutoresizingMask:UIViewAutoresizingFlexibleBoth];
    [list_ setRowHeight:45.0f];
    [(UITableView *) list_ setDataSource:self];
    [list_ setDelegate:self];
    [self setView:list_];
}

- (void) viewDidLoad {
    [super viewDidLoad];

    [[self navigationItem] setTitle:UCLocalize("SECTIONS")];
}

- (void) releaseSubviews {
    list_ = nil;

    sections_ = nil;
    filtered_ = nil;

    [super releaseSubviews];
}

- (id) initWithDatabase:(Database *)database {
    if ((self = [super init]) != nil) {
        database_ = database;
    } return self;
}

- (void) reloadData {
    [super reloadData];

    NSArray *packages = [database_ packages];

    sections_ = [NSMutableArray arrayWithCapacity:16];
    filtered_ = [NSMutableArray arrayWithCapacity:16];

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
                    section = [[[Section alloc] initWithName:key localize:YES] autorelease];
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

    for (Section *section in (id) sections_) {
        size_t count([section row]);
        if (count == 0)
            continue;

        section = [[[Section alloc] initWithName:[section name] localized:[section localized]] autorelease];
        [section setCount:count];
        [filtered_ addObject:section];
    }

    [self updateNavigationItem];
    [list_ reloadData];
    _trace();
}

- (void) editButtonClicked {
    [self setEditing:![self isEditing] animated:YES];
}

@end
/* }}} */

/* Changes Controller {{{ */
@interface ChangesController : CyteViewController <
    UITableViewDataSource,
    UITableViewDelegate
> {
    _transient Database *database_;
    unsigned era_;
    _H<NSArray> packages_;
    _H<NSMutableArray> sections_;
    _H<UITableView, 2> list_;
    _H<CyteWebView, 1> dickbar_;
    unsigned upgrades_;
    _H<IndirectDelegate, 1> indirect_;
    _H<CydiaObject> cydia_;
}

- (id) initWithDatabase:(Database *)database;

@end

@implementation ChangesController

- (NSURL *) navigationURL {
    return [NSURL URLWithString:@"cydia://changes"];
}

- (void) viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [list_ deselectRowAtIndexPath:[list_ indexPathForSelectedRow] animated:animated];
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
@synchronized (database_) {
    if ([database_ era] != era_)
        return nil;

    NSUInteger sectionIndex([path section]);
    if (sectionIndex >= [sections_ count])
        return nil;
    Section *section([sections_ objectAtIndex:sectionIndex]);
    NSInteger row([path row]);
    return [[[packages_ objectAtIndex:([section row] + row)] retain] autorelease];
} }

- (UITableViewCell *) tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    PackageCell *cell((PackageCell *) [table dequeueReusableCellWithIdentifier:@"Package"]);
    if (cell == nil)
        cell = [[[PackageCell alloc] init] autorelease];

    Package *package([database_ packageWithName:[[self packageAtIndexPath:path] id]]);
    [cell setPackage:package asSummary:false];
    return cell;
}

- (NSIndexPath *) tableView:(UITableView *)table willSelectRowAtIndexPath:(NSIndexPath *)path {
    Package *package([self packageAtIndexPath:path]);
    CYPackageController *view([[[CYPackageController alloc] initWithDatabase:database_ forPackage:[package id]] autorelease]);
    [view setDelegate:delegate_];
    [[self navigationController] pushViewController:view animated:YES];
    return path;
}

- (void) refreshButtonClicked {
    [delegate_ beginUpdate];
    [[self navigationItem] setLeftBarButtonItem:nil animated:YES];
}

- (void) upgradeButtonClicked {
    [delegate_ distUpgrade];
    [[self navigationItem] setRightBarButtonItem:nil animated:YES];
}

- (void) loadView {
    UIView *view([[[UIView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame]] autorelease]);
    [view setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)];
    [self setView:view];

    list_ = [[[UITableView alloc] initWithFrame:[view bounds] style:UITableViewStylePlain] autorelease];
    [list_ setAutoresizingMask:UIViewAutoresizingFlexibleBoth];
    [list_ setRowHeight:73];
    [(UITableView *) list_ setDataSource:self];
    [list_ setDelegate:self];
    [view addSubview:list_];

    if (AprilFools_ && kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iPhoneOS_3_0) {
        CGRect dickframe([view bounds]);
        dickframe.size.height = 44;

        dickbar_ = [[[CyteWebView alloc] initWithFrame:dickframe] autorelease];
        [dickbar_ setDelegate:self];
        [view addSubview:dickbar_];

        [dickbar_ setBackgroundColor:[UIColor clearColor]];
        [dickbar_ setScalesPageToFit:YES];

        UIWebDocumentView *document([dickbar_ _documentView]);
        [document setBackgroundColor:[UIColor clearColor]];
        [document setDrawsBackground:NO];

        WebView *webview([document webView]);
        [webview setShouldUpdateWhileOffscreen:NO];

        UIScrollView *scroller([dickbar_ scrollView]);
        [scroller setScrollingEnabled:NO];
        [scroller setFixedBackgroundPattern:YES];
        [scroller setBackgroundColor:[UIColor clearColor]];

        WebPreferences *preferences([webview preferences]);
        [preferences setCacheModel:WebCacheModelDocumentBrowser];
        [preferences setJavaScriptCanOpenWindowsAutomatically:YES];
        [preferences setOfflineWebApplicationCacheEnabled:YES];

        [dickbar_ loadRequest:[NSURLRequest
            requestWithURL:[Diversion divertURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/#!/dickbar/", UI_]]]
            cachePolicy:NSURLRequestUseProtocolCachePolicy
            timeoutInterval:120
        ]];

        UIEdgeInsets inset = {44, 0, 0, 0};
        [list_ setContentInset:inset];

        [dickbar_ setAutoresizingMask:UIViewAutoresizingFlexibleWidth];
    }
}

- (void) webView:(WebView *)view decidePolicyForNewWindowAction:(NSDictionary *)action request:(NSURLRequest *)request newFrameName:(NSString *)frame decisionListener:(id<WebPolicyDecisionListener>)listener {
    NSURL *url([request URL]);
    if (url == nil)
        return;

    if ([frame isEqualToString:@"_open"])
        [delegate_ openURL:url];
    else {
        CyteViewController *controller([delegate_ pageForURL:url forExternal:NO] ?: [[[CydiaWebViewController alloc] initWithRequest:request] autorelease]);
        [controller setDelegate:delegate_];
        [[self navigationController] pushViewController:controller animated:YES];
    }

    [listener ignore];
}

- (NSURLRequest *) webView:(WebView *)view resource:(id)resource willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response fromDataSource:(WebDataSource *)source {
    return [CydiaWebViewController requestWithHeaders:request];
}

- (void) webView:(WebView *)view didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame {
    [CydiaWebViewController didClearWindowObject:window forFrame:frame withCydia:cydia_];
}

- (void) setDelegate:(id)delegate {
    [super setDelegate:delegate];
    [cydia_ setDelegate:delegate];
}

- (void) viewDidLoad {
    [super viewDidLoad];

    [[self navigationItem] setTitle:(AprilFools_ ? @"Timeline" : UCLocalize("CHANGES"))];
}

- (void) releaseSubviews {
    list_ = nil;

    packages_ = nil;
    sections_ = nil;
    dickbar_ = nil;

    [super releaseSubviews];
}

- (id) initWithDatabase:(Database *)database {
    if ((self = [super init]) != nil) {
        indirect_ = [[[IndirectDelegate alloc] initWithDelegate:self] autorelease];
        cydia_ = [[[CydiaObject alloc] initWithDelegate:indirect_] autorelease];
        database_ = database;
    } return self;
}

- (NSMutableArray *) _reloadPackages {
@synchronized (database_) {
    era_ = [database_ era];
    NSArray *packages([database_ packages]);

    NSMutableArray *filtered([NSMutableArray arrayWithCapacity:[packages count]]);

    _trace();
    _profile(ChangesController$_reloadPackages$Filter)
        for (Package *package in packages)
            if ([package upgradableAndEssential:YES] || [package visible])
                CFArrayAppendValue((CFMutableArrayRef) filtered, package);
    _end
    _trace();
    _profile(ChangesController$_reloadPackages$radixSort)
        [filtered radixSortUsingFunction:reinterpret_cast<MenesRadixSortFunction>(&PackageChangesRadix) withContext:NULL];
    _end
    _trace();

    return filtered;
} }

- (void) _reloadData {
    NSArray *packages;

  reload:
    if (true) {
        UIProgressHUD *hud([delegate_ addProgressHUD]);
        [hud setText:UCLocalize("LOADING")];
        //NSLog(@"HUD:%@::%@", delegate_, hud);
        packages = [self yieldToSelector:@selector(_reloadPackages)];
        [delegate_ removeProgressHUD:hud];
    } else {
        packages = [self _reloadPackages];
    }

@synchronized (database_) {
    if (era_ != [database_ era])
        goto reload;

    packages_ = packages;
    sections_ = [NSMutableArray arrayWithCapacity:16];

    Section *upgradable = [[[Section alloc] initWithName:UCLocalize("AVAILABLE_UPGRADES") localize:NO] autorelease];
    Section *ignored = nil;
    Section *section = nil;
    time_t last = 0;

    upgrades_ = 0;
    bool unseens = false;

    CFDateFormatterRef formatter(CFDateFormatterCreate(NULL, Locale_, kCFDateFormatterMediumStyle, kCFDateFormatterMediumStyle));

    for (size_t offset = 0, count = [packages_ count]; offset != count; ++offset) {
        Package *package = [packages_ objectAtIndex:offset];

        BOOL uae = [package upgradableAndEssential:YES];

        if (!uae) {
            unseens = true;
            time_t seen([package seen]);

            if (section == nil || last != seen) {
                last = seen;

                NSString *name;
                name = (NSString *) CFDateFormatterCreateStringWithDate(NULL, formatter, (CFDateRef) [NSDate dateWithTimeIntervalSince1970:seen]);
                [name autorelease];

                _profile(ChangesController$reloadData$Allocate)
                    name = [NSString stringWithFormat:UCLocalize("NEW_AT"), name];
                    section = [[[Section alloc] initWithName:name row:offset localize:NO] autorelease];
                    [sections_ addObject:section];
                _end
            }

            [section addToCount];
        } else if ([package ignored]) {
            if (ignored == nil) {
                ignored = [[[Section alloc] initWithName:UCLocalize("IGNORED_UPGRADES") row:offset localize:NO] autorelease];
            }
            [ignored addToCount];
        } else {
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

    [[self navigationItem] setRightBarButtonItem:(upgrades_ == 0 ? nil : [[[UIBarButtonItem alloc]
        initWithTitle:[NSString stringWithFormat:UCLocalize("PARENTHETICAL"), UCLocalize("UPGRADE"), [NSString stringWithFormat:@"%u", upgrades_]]
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(upgradeButtonClicked)
    ] autorelease]) animated:YES];

    [[self navigationItem] setLeftBarButtonItem:([delegate_ updating] ? nil : [[[UIBarButtonItem alloc]
        initWithTitle:UCLocalize("REFRESH")
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(refreshButtonClicked)
    ] autorelease]) animated:YES];

    PrintTimes();
} }

- (void) reloadData {
    [super reloadData];
    [self performSelector:@selector(_reloadData) withObject:nil afterDelay:0];
}

@end
/* }}} */
/* Search Controller {{{ */
@interface SearchController : FilteredPackageListController <
    UISearchBarDelegate
> {
    _H<UISearchBar, 1> search_;
    BOOL searchloaded_;
}

- (id) initWithDatabase:(Database *)database query:(NSString *)query;
- (void) reloadData;

@end

@implementation SearchController

- (NSURL *) navigationURL {
    if ([search_ text] == nil || [[search_ text] isEqualToString:@""])
        return [NSURL URLWithString:@"cydia://search"];
    else
        return [NSURL URLWithString:[NSString stringWithFormat:@"cydia://search/%@", [[search_ text] stringByAddingPercentEscapesIncludingReserved]]];
}

- (void) useSearch {
    [self setObject:[[search_ text] componentsSeparatedByString:@" "] forFilter:@selector(isUnfilteredAndSearchedForBy:)];
    [self clearData];
    [self reloadData];
}

- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if ([self filter] == @selector(isUnfilteredAndSelectedForBy:))
        [self useSearch];
}

- (void) searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    [self setObject:[search_ text] forFilter:@selector(isUnfilteredAndSelectedForBy:)];
    [self clearData];
    [self reloadData];
}

- (void) searchBarButtonClicked:(UISearchBar *)searchBar {
    [search_ resignFirstResponder];
    [self useSearch];
}

- (void) searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    [search_ setText:@""];
    [self searchBarButtonClicked:searchBar];
}

- (void) searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [self searchBarButtonClicked:searchBar];
}

- (void) searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
    [self setObject:text forFilter:@selector(isUnfilteredAndSelectedForBy:)];
    [self reloadData];
}

- (bool) shouldYield {
    return YES;
}

- (bool) shouldBlock {
    return [self filter] == @selector(isUnfilteredAndSearchedForBy:);
}

- (bool) isSummarized {
    return [self filter] == @selector(isUnfilteredAndSelectedForBy:);
}

- (bool) showsSections {
    return false;
}

- (NSMutableArray *) _reloadPackages {
    NSMutableArray *packages([super _reloadPackages]);
    if ([self filter] == @selector(isUnfilteredAndSearchedForBy:))
        [packages radixSortUsingSelector:@selector(rank)];
    return packages;
}

- (id) initWithDatabase:(Database *)database query:(NSString *)query {
    if ((self = [super initWithDatabase:database title:UCLocalize("SEARCH") filter:@selector(isUnfilteredAndSearchedForBy:) with:[query componentsSeparatedByString:@" "]])) {
        search_ = [[[UISearchBar alloc] init] autorelease];
        [search_ setDelegate:self];

        if (query != nil)
            [search_ setText:query];
    } return self;
}

- (void) viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    if (!searchloaded_) {
        searchloaded_ = YES;
        [search_ setFrame:CGRectMake(0, 0, [[self view] bounds].size.width, 44.0f)];
        [search_ layoutSubviews];
        [search_ setPlaceholder:UCLocalize("SEARCH_EX")];

        UITextField *textField;
        if ([search_ respondsToSelector:@selector(searchField)])
            textField = [search_ searchField];
        else
            textField = MSHookIvar<UITextField *>(search_, "_searchField");

        [textField setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin];
        [textField setEnablesReturnKeyAutomatically:NO];
        [[self navigationItem] setTitleView:textField];
    }
}

- (void) reloadData {
    id object([search_ text]);
    if ([self filter] == @selector(isUnfilteredAndSearchedForBy:))
        object = [object componentsSeparatedByString:@" "];

    [self setObject:object];
    [self resetCursor];

    [super reloadData];
}

- (void) didSelectPackage:(Package *)package {
    [search_ resignFirstResponder];
    [super didSelectPackage:package];
}

@end
/* }}} */
/* Package Settings Controller {{{ */
@interface PackageSettingsController : CyteViewController <
    UITableViewDataSource,
    UITableViewDelegate
> {
    _transient Database *database_;
    _H<NSString> name_;
    _H<Package> package_;
    _H<UITableView, 2> table_;
    _H<UISwitch> subscribedSwitch_;
    _H<UISwitch> ignoredSwitch_;
    _H<UITableViewCell> subscribedCell_;
    _H<UITableViewCell> ignoredCell_;
}

- (id) initWithDatabase:(Database *)database package:(NSString *)package;

@end

@implementation PackageSettingsController

- (NSURL *) navigationURL {
    return [NSURL URLWithString:[NSString stringWithFormat:@"cydia://package/%@/settings", (id) name_]];
}

- (NSInteger) numberOfSectionsInTableView:(UITableView *)tableView {
    if (package_ == nil)
        return 0;

    if ([package_ installed] == nil)
        return 1;
    else
        return 2;
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (package_ == nil)
        return 0;

    // both sections contain just one item right now.
    return 1;
}

- (NSString *) tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return nil;
}

- (NSString *) tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0)
        return UCLocalize("SHOW_ALL_CHANGES_EX");
    else
        return UCLocalize("IGNORE_UPGRADES_EX");
}

- (void) onSubscribed:(id)control {
    bool value([control isOn]);
    if (package_ == nil)
        return;
    if ([package_ setSubscribed:value])
        [delegate_ updateData];
}

- (void) _updateIgnored {
    const char *package([name_ UTF8String]);
    bool on([ignoredSwitch_ isOn]);

    pid_t pid(ExecFork());
    if (pid == 0) {
        FILE *dpkg(popen("dpkg --set-selections", "w"));
        fwrite(package, strlen(package), 1, dpkg);

        if (on)
            fwrite(" hold\n", 6, 1, dpkg);
        else
            fwrite(" install\n", 9, 1, dpkg);

        pclose(dpkg);

        exit(0);
        _assert(false);
    }

    ReapZombie(pid);
}

- (void) onIgnored:(id)control {
    NSInvocation *invocation([NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(_updateIgnored)]]);
    [invocation setTarget:self];
    [invocation setSelector:@selector(_updateIgnored)];

    [delegate_ reloadDataWithInvocation:invocation];
}

- (UITableViewCell *) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (package_ == nil)
        return nil;

    switch ([indexPath section]) {
        case 0: return subscribedCell_;
        case 1: return ignoredCell_;

        _nodefault
    }

    return nil;
}

- (void) loadView {
    UIView *view([[[UIView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame]] autorelease]);
    [view setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)];
    [self setView:view];

    table_ = [[[UITableView alloc] initWithFrame:[[self view] bounds] style:UITableViewStyleGrouped] autorelease];
    [table_ setAutoresizingMask:UIViewAutoresizingFlexibleBoth];
    [(UITableView *) table_ setDataSource:self];
    [table_ setDelegate:self];
    [view addSubview:table_];

    subscribedSwitch_ = [[[UISwitch alloc] initWithFrame:CGRectMake(0, 0, 50, 20)] autorelease];
    [subscribedSwitch_ setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin];
    [subscribedSwitch_ addTarget:self action:@selector(onSubscribed:) forEvents:UIControlEventValueChanged];

    ignoredSwitch_ = [[[UISwitch alloc] initWithFrame:CGRectMake(0, 0, 50, 20)] autorelease];
    [ignoredSwitch_ setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin];
    [ignoredSwitch_ addTarget:self action:@selector(onIgnored:) forEvents:UIControlEventValueChanged];

    subscribedCell_ = [[[UITableViewCell alloc] init] autorelease];
    [subscribedCell_ setText:UCLocalize("SHOW_ALL_CHANGES")];
    [subscribedCell_ setAccessoryView:subscribedSwitch_];
    [subscribedCell_ setSelectionStyle:UITableViewCellSelectionStyleNone];

    ignoredCell_ = [[[UITableViewCell alloc] init] autorelease];
    [ignoredCell_ setText:UCLocalize("IGNORE_UPGRADES")];
    [ignoredCell_ setAccessoryView:ignoredSwitch_];
    [ignoredCell_ setSelectionStyle:UITableViewCellSelectionStyleNone];
}

- (void) viewDidLoad {
    [super viewDidLoad];

    [[self navigationItem] setTitle:UCLocalize("SETTINGS")];
}

- (void) releaseSubviews {
    ignoredCell_ = nil;
    subscribedCell_ = nil;
    table_ = nil;
    ignoredSwitch_ = nil;
    subscribedSwitch_ = nil;

    [super releaseSubviews];
}

- (id) initWithDatabase:(Database *)database package:(NSString *)package {
    if ((self = [super init]) != nil) {
        database_ = database;
        name_ = package;
    } return self;
}

- (void) reloadData {
    [super reloadData];

    package_ = [database_ packageWithName:name_];

    if (package_ != nil) {
        [subscribedSwitch_ setOn:([package_ subscribed] ? 1 : 0) animated:NO];
        [ignoredSwitch_ setOn:([package_ ignored] ? 1 : 0) animated:NO];
    } // XXX: what now, G?

    [table_ reloadData];
}

@end
/* }}} */

/* Installed Controller {{{ */
@interface InstalledController : FilteredPackageListController {
    BOOL expert_;
}

- (id) initWithDatabase:(Database *)database;

- (void) updateRoleButton;
- (void) queueStatusDidChange;

@end

@implementation InstalledController

- (NSURL *) navigationURL {
    return [NSURL URLWithString:@"cydia://installed"];
}

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
    [self setObject:[NSNumber numberWithBool:expert_]];
    [self reloadData];
    expert_ = !expert_;

    [self updateRoleButton];
}

@end
/* }}} */

/* Source Cell {{{ */
@interface SourceCell : CyteTableViewCell <
    CyteTableViewCellDelegate
> {
    _H<NSURL> url_;
    _H<UIImage> icon_;
    _H<NSString> origin_;
    _H<NSString> label_;
}

- (void) setSource:(Source *)source;

@end

@implementation SourceCell

- (void) _setImage:(NSArray *)data {
    if ([url_ isEqual:[data objectAtIndex:0]]) {
        icon_ = [data objectAtIndex:1];
        [content_ setNeedsDisplay];
    }
}

- (void) _setSource:(NSURL *) url {
    NSAutoreleasePool *pool([[NSAutoreleasePool alloc] init]);

    if (NSData *data = [NSURLConnection
        sendSynchronousRequest:[NSURLRequest
            requestWithURL:url
            //cachePolicy:NSURLRequestUseProtocolCachePolicy
            //timeoutInterval:5
        ]

        returningResponse:NULL
        error:NULL
    ])
        if (UIImage *image = [UIImage imageWithData:data])
            [self performSelectorOnMainThread:@selector(_setImage:) withObject:[NSArray arrayWithObjects:url, image, nil] waitUntilDone:NO];

    [pool release];
}

- (void) setSource:(Source *)source {
    icon_ = [UIImage applicationImageNamed:@"unknown.png"];

    origin_ = [source name];
    label_ = [source rooturi];

    [content_ setNeedsDisplay];

    url_ = [source iconURL];
    [NSThread detachNewThreadSelector:@selector(_setSource:) toTarget:self withObject:url_];
}

- (SourceCell *) initWithFrame:(CGRect)frame reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithFrame:frame reuseIdentifier:reuseIdentifier]) != nil) {
        UIView *content([self contentView]);
        CGRect bounds([content bounds]);

        content_ = [[[CyteTableViewCellContentView alloc] initWithFrame:bounds] autorelease];
        [content_ setAutoresizingMask:UIViewAutoresizingFlexibleBoth];
        [content_ setBackgroundColor:[UIColor whiteColor]];
        [content addSubview:content_];

        [content_ setDelegate:self];
        [content_ setOpaque:YES];

        [[content_ layer] setContentsGravity:kCAGravityTopLeft];
    } return self;
}

- (NSString *) accessibilityLabel {
    return label_;
}

- (void) drawContentRect:(CGRect)rect {
    bool highlighted(highlighted_);
    float width(rect.size.width);

    if (icon_ != nil) {
        CGRect rect;
        rect.size = [(UIImage *) icon_ size];

        while (rect.size.width > 32 || rect.size.height > 32) {
            rect.size.width /= 2;
            rect.size.height /= 2;
        }

        rect.origin.x = 25 - rect.size.width / 2;
        rect.origin.y = 25 - rect.size.height / 2;

        [icon_ drawInRect:rect];
    }

    if (highlighted)
        UISetColor(White_);

    if (!highlighted)
        UISetColor(Black_);
    [origin_ drawAtPoint:CGPointMake(48, 8) forWidth:(width - 65) withFont:Font18Bold_ lineBreakMode:UILineBreakModeTailTruncation];

    if (!highlighted)
        UISetColor(Gray_);
    [label_ drawAtPoint:CGPointMake(48, 29) forWidth:(width - 65) withFont:Font12_ lineBreakMode:UILineBreakModeTailTruncation];
}

@end
/* }}} */
/* Source Controller {{{ */
@interface SourceController : FilteredPackageListController {
    _transient Source *source_;
    _H<NSString> key_;
}

- (id) initWithDatabase:(Database *)database source:(Source *)source;

@end

@implementation SourceController

- (NSURL *) navigationURL {
    return [NSURL URLWithString:[NSString stringWithFormat:@"cydia://sources/%@", [key_ stringByAddingPercentEscapesIncludingReserved]]];
}

- (id) initWithDatabase:(Database *)database source:(Source *)source {
    if ((self = [super initWithDatabase:database title:[source label] filter:@selector(isVisibleInSource:) with:source]) != nil) {
        source_ = source;
        key_ = [source key];
    } return self;
}

- (void) reloadData {
    source_ = [database_ sourceWithKey:key_];
    key_ = [source_ key];
    [self setObject:source_];

    [[self navigationItem] setTitle:[source_ label]];

    [super reloadData];
}

@end
/* }}} */
/* Sources Controller {{{ */
@interface SourcesController : CyteViewController <
    UITableViewDataSource,
    UITableViewDelegate
> {
    _transient Database *database_;
    unsigned era_;

    _H<UITableView, 2> list_;
    _H<NSMutableArray> sources_;
    int offset_;

    _H<NSString> href_;
    _H<UIProgressHUD> hud_;
    _H<NSError> error_;

    //NSURLConnection *installer_;
    NSURLConnection *trivial_;
    NSURLConnection *trivial_bz2_;
    NSURLConnection *trivial_gz_;
    //NSURLConnection *automatic_;

    BOOL cydia_;
}

- (id) initWithDatabase:(Database *)database;
- (void) updateButtonsForEditingStatusAnimated:(BOOL)animated;

@end

@implementation SourcesController

- (void) _releaseConnection:(NSURLConnection *)connection {
    if (connection != nil) {
        [connection cancel];
        //[connection setDelegate:nil];
        [connection release];
    }
}

- (void) dealloc {
    //[self _releaseConnection:installer_];
    [self _releaseConnection:trivial_];
    [self _releaseConnection:trivial_gz_];
    [self _releaseConnection:trivial_bz2_];
    //[self _releaseConnection:automatic_];

    [super dealloc];
}

- (NSURL *) navigationURL {
    return [NSURL URLWithString:@"cydia://sources"];
}

- (void) viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [list_ deselectRowAtIndexPath:[list_ indexPathForSelectedRow] animated:animated];
}

- (NSInteger) numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSString *) tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return nil;
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [sources_ count];
}

- (Source *) sourceAtIndexPath:(NSIndexPath *)indexPath {
@synchronized (database_) {
    if ([database_ era] != era_)
        return nil;

    return [sources_ objectAtIndex:[indexPath row]];
} }

- (UITableViewCell *) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"SourceCell";

    SourceCell *cell = (SourceCell *) [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if(cell == nil) cell = [[[SourceCell alloc] initWithFrame:CGRectZero reuseIdentifier:cellIdentifier] autorelease];
    [cell setSource:[self sourceAtIndexPath:indexPath]];
    [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];

    return cell;
}

- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    Source *source = [self sourceAtIndexPath:indexPath];

    SourceController *controller = [[[SourceController alloc]
        initWithDatabase:database_
        source:source
    ] autorelease];

    [controller setDelegate:delegate_];

    [[self navigationController] pushViewController:controller animated:YES];
}

- (BOOL) tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    Source *source = [self sourceAtIndexPath:indexPath];
    return [source record] != nil;
}

- (void) tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle ==  UITableViewCellEditingStyleDelete) {
        Source *source = [self sourceAtIndexPath:indexPath];
        [Sources_ removeObjectForKey:[source key]];
        [delegate_ syncData];
    }
}

- (void) complete {
    [delegate_ addTrivialSource:href_];
    href_ = nil;

    [delegate_ syncData];
}

- (NSString *) getWarning {
    NSString *href(href_);
    NSRange colon([href rangeOfString:@"://"]);
    if (colon.location != NSNotFound)
        href = [href substringFromIndex:(colon.location + 3)];
    href = [href stringByAddingPercentEscapes];
    href = [CydiaURL(@"api/repotag/") stringByAppendingString:href];

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
        NSString *warning(cydia_ ? [self yieldToSelector:@selector(getWarning)] : nil);

        [delegate_ releaseNetworkActivityIndicator];

        [delegate_ removeProgressHUD:hud_];
        hud_ = nil;

        if (cydia_) {
            if (warning != nil) {
                UIAlertView *alert = [[[UIAlertView alloc]
                    initWithTitle:UCLocalize("SOURCE_WARNING")
                    message:warning
                    delegate:self
                    cancelButtonTitle:UCLocalize("CANCEL")
                    otherButtonTitles:
                        UCLocalize("ADD_ANYWAY"),
                    nil
                ] autorelease];

                [alert setContext:@"warning"];
                [alert setNumberOfRows:1];
                [alert show];

                // XXX: there used to be this great mechanism called yieldToPopup... who deleted it?
                error_ = nil;
                return;
            }

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

            href_ = nil;
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

            href_ = nil;
        }

        error_ = nil;
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
    error_ = error;
    [self _endConnection:connection];
}

- (void) connectionDidFinishLoading:(NSURLConnection *)connection {
    [self _endConnection:connection];
}

- (NSURLConnection *) _requestHRef:(NSString *)href method:(NSString *)method {
    NSURL *url([NSURL URLWithString:href]);

    NSMutableURLRequest *request = [NSMutableURLRequest
        requestWithURL:url
        cachePolicy:NSURLRequestUseProtocolCachePolicy
        timeoutInterval:120.0
    ];

    [request setHTTPMethod:method];

    if (Machine_ != NULL)
        [request setValue:[NSString stringWithUTF8String:Machine_] forHTTPHeaderField:@"X-Machine"];

    if ([url isCydiaSecure]) {
        if (UniqueID_ != nil) {
            [request setValue:UniqueID_ forHTTPHeaderField:@"X-Unique-ID"];
            [request setValue:UniqueID_ forHTTPHeaderField:@"X-Cydia-Id"];
        }
    }

    return [[[NSURLConnection alloc] initWithRequest:request delegate:self] autorelease];
}

- (void) alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)button {
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

                trivial_ = [[self _requestHRef:[href_ stringByAppendingString:@"Packages"] method:@"HEAD"] retain];
                trivial_bz2_ = [[self _requestHRef:[href_ stringByAppendingString:@"Packages.bz2"] method:@"HEAD"] retain];
                trivial_gz_ = [[self _requestHRef:[href_ stringByAppendingString:@"Packages.gz"] method:@"HEAD"] retain];
                //trivial_bz2_ = [[self _requestHRef:[href stringByAppendingString:@"dists/Release"] method:@"HEAD"] retain];

                cydia_ = false;

                // XXX: this is stupid
                hud_ = [delegate_ addProgressHUD];
                [hud_ setText:UCLocalize("VERIFYING_URL")];
                [delegate_ retainNetworkActivityIndicator];
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
                [self performSelector:@selector(complete) withObject:nil afterDelay:0];
            break;

            case 0:
            break;

            _nodefault
        }

        [alert dismissWithClickedButtonIndex:-1 animated:YES];
    }
}

- (void) loadView {
    list_ = [[[UITableView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame] style:UITableViewStylePlain] autorelease];
    [list_ setAutoresizingMask:UIViewAutoresizingFlexibleBoth];
    [list_ setRowHeight:53];
    [(UITableView *) list_ setDataSource:self];
    [list_ setDelegate:self];
    [self setView:list_];
}

- (void) viewDidLoad {
    [super viewDidLoad];

    [[self navigationItem] setTitle:UCLocalize("SOURCES")];
    [self updateButtonsForEditingStatusAnimated:NO];
}

- (void) viewWillDisappear:(BOOL)animated {
    [super viewWillAppear:animated];

    [list_ setEditing:NO];
    [self updateButtonsForEditingStatusAnimated:NO];
}

- (void) releaseSubviews {
    list_ = nil;

    sources_ = nil;

    [super releaseSubviews];
}

- (id) initWithDatabase:(Database *)database {
    if ((self = [super init]) != nil) {
        database_ = database;
    } return self;
}

- (void) reloadData {
    [super reloadData];

@synchronized (database_) {
    era_ = [database_ era];

    pkgSourceList list;
    if ([database_ popErrorWithTitle:UCLocalize("SOURCES") forOperation:list.ReadMainList()])
        return;

    sources_ = [NSMutableArray arrayWithCapacity:16];
    [sources_ addObjectsFromArray:[database_ sources]];
    _trace();
    [sources_ sortUsingSelector:@selector(compareByName:)];
    _trace();

    int count([sources_ count]);
    offset_ = 0;
    for (int i = 0; i != count; i++) {
        if ([[sources_ objectAtIndex:i] record] == nil)
            break;
        offset_++;
    }

    [list_ reloadData];
} }

- (void) showAddSourcePrompt {
    UIAlertView *alert = [[[UIAlertView alloc]
        initWithTitle:UCLocalize("ENTER_APT_URL")
        message:nil
        delegate:self
        cancelButtonTitle:UCLocalize("CANCEL")
        otherButtonTitles:
            UCLocalize("ADD_SOURCE"),
        nil
    ] autorelease];

    [alert setContext:@"source"];

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

- (void) addButtonClicked {
    [self showAddSourcePrompt];
}

- (void) updateButtonsForEditingStatusAnimated:(BOOL)animated { 
    BOOL editing([list_ isEditing]);

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
    [self updateButtonsForEditingStatusAnimated:YES];
}

@end
/* }}} */

/* Settings Controller {{{ */
@interface SettingsController : CyteViewController <
    UITableViewDataSource,
    UITableViewDelegate
> {
    _transient Database *database_;
    // XXX: ok, "roledelegate_"?...
    _transient id roledelegate_;
    _H<UITableView, 2> table_;
    _H<UISegmentedControl> segment_;
    _H<UIView> container_;
}

- (void) showDoneButton;
- (void) resizeSegmentedControl;

@end

@implementation SettingsController

- (void) loadView {
    table_ = [[[UITableView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame] style:UITableViewStyleGrouped] autorelease];
    [table_ setAutoresizingMask:UIViewAutoresizingFlexibleBoth];
    [table_ setDelegate:self];
    [(UITableView *) table_ setDataSource:self];
    [self setView:table_];

    NSArray *items = [NSArray arrayWithObjects:
        UCLocalize("USER"),
        UCLocalize("HACKER"),
        UCLocalize("DEVELOPER"),
    nil];
    segment_ = [[[UISegmentedControl alloc] initWithItems:items] autorelease];
    [segment_ setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin)];
    container_ = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, [[self view] frame].size.width, 44.0f)] autorelease];
    [container_ addSubview:segment_];
}

- (void) viewDidLoad {
    [super viewDidLoad];

    [[self navigationItem] setTitle:UCLocalize("WHO_ARE_YOU")];

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
}

- (void) releaseSubviews {
    table_ = nil;
    segment_ = nil;
    container_ = nil;

    [super releaseSubviews];
}

- (id) initWithDatabase:(Database *)database delegate:(id)delegate {
    if ((self = [super init]) != nil) {
        database_ = database;
        roledelegate_ = delegate;
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

- (UITableViewCell *) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
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

- (void) reloadData {
    [super reloadData];

    [table_ reloadData];
}

@end
/* }}} */
/* Stash Controller {{{ */
@interface StashController : CyteViewController {
    _H<UIActivityIndicatorView> spinner_;
    _H<UILabel> status_;
    _H<UILabel> caption_;
}

@end

@implementation StashController

- (void) loadView {
    UIView *view([[[UIView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame]] autorelease]);
    [view setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)];
    [self setView:view];

    [view setBackgroundColor:[UIColor viewFlipsideBackgroundColor]];

    spinner_ = [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge] autorelease];
    CGRect spinrect = [spinner_ frame];
    spinrect.origin.x = ([[self view] frame].size.width / 2) - (spinrect.size.width / 2);
    spinrect.origin.y = [[self view] frame].size.height - 80.0f;
    [spinner_ setFrame:spinrect];
    [spinner_ setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin];
    [view addSubview:spinner_];
    [spinner_ startAnimating];

    CGRect captrect;
    captrect.size.width = [[self view] frame].size.width;
    captrect.size.height = 40.0f;
    captrect.origin.x = 0;
    captrect.origin.y = ([[self view] frame].size.height / 2) - (captrect.size.height * 2);
    caption_ = [[[UILabel alloc] initWithFrame:captrect] autorelease];
    [caption_ setText:UCLocalize("PREPARING_FILESYSTEM")];
    [caption_ setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin];
    [caption_ setFont:[UIFont boldSystemFontOfSize:28.0f]];
    [caption_ setTextColor:[UIColor whiteColor]];
    [caption_ setBackgroundColor:[UIColor clearColor]];
    [caption_ setShadowColor:[UIColor blackColor]];
    [caption_ setTextAlignment:UITextAlignmentCenter];
    [view addSubview:caption_];

    CGRect statusrect;
    statusrect.size.width = [[self view] frame].size.width;
    statusrect.size.height = 30.0f;
    statusrect.origin.x = 0;
    statusrect.origin.y = ([[self view] frame].size.height / 2) - statusrect.size.height;
    status_ = [[[UILabel alloc] initWithFrame:statusrect] autorelease];
    [status_ setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin];
    [status_ setText:UCLocalize("EXIT_WHEN_COMPLETE")];
    [status_ setFont:[UIFont systemFontOfSize:16.0f]];
    [status_ setTextColor:[UIColor whiteColor]];
    [status_ setBackgroundColor:[UIColor clearColor]];
    [status_ setShadowColor:[UIColor blackColor]];
    [status_ setTextAlignment:UITextAlignmentCenter];
    [view addSubview:status_];
}

- (void) releaseSubviews {
    spinner_ = nil;
    status_ = nil;
    caption_ = nil;

    [super releaseSubviews];
}

@end
/* }}} */

@interface CYURLCache : SDURLCache {
}

@end

@implementation CYURLCache

- (void) logEvent:(NSString *)event forRequest:(NSURLRequest *)request {
#if !ForRelease
    if (false);
    else if ([event isEqualToString:@"no-cache"])
        event = @"!!!";
    else if ([event isEqualToString:@"store"])
        event = @">>>";
    else if ([event isEqualToString:@"invalid"])
        event = @"???";
    else if ([event isEqualToString:@"memory"])
        event = @"mem";
    else if ([event isEqualToString:@"disk"])
        event = @"ssd";
    else if ([event isEqualToString:@"miss"])
        event = @"---";

    NSLog(@"%@: %@", event, [[request URL] absoluteString]);
#endif
}

- (void) storeCachedResponse:(NSCachedURLResponse *)cached forRequest:(NSURLRequest *)request {
    if (NSURLResponse *response = [cached response])
        if (NSString *mime = [response MIMEType])
            if ([mime isEqualToString:@"text/cache-manifest"]) {
                NSURL *url([response URL]);

#if !ForRelease
                NSLog(@"###: %@", [url absoluteString]);
#endif

                @synchronized (HostConfig_) {
                    [CachedURLs_ addObject:url];
                }
            }

    [super storeCachedResponse:cached forRequest:request];
}

@end

@interface Cydia : UIApplication <
    ConfirmationControllerDelegate,
    DatabaseDelegate,
    CydiaDelegate,
    UINavigationControllerDelegate,
    UITabBarControllerDelegate
> {
    _H<UIWindow> window_;
    _H<CYTabBarController> tabbar_;
    _H<CydiaLoadingViewController> emulated_;

    _H<NSMutableArray> essential_;
    _H<NSMutableArray> broken_;

    Database *database_;

    _H<NSURL> starturl_;

    unsigned locked_;
    unsigned activity_;

    _H<StashController> stash_;

    bool loaded_;
}

- (void) loadData;

@end

@implementation Cydia

- (void) beginUpdate {
    [tabbar_ beginUpdate];
}

- (BOOL) updating {
    return [tabbar_ updating];
}

- (void) _loaded {
    if ([broken_ count] != 0) {
        int count = [broken_ count];

        UIAlertView *alert = [[[UIAlertView alloc]
            initWithTitle:(count == 1 ? UCLocalize("HALFINSTALLED_PACKAGE") : [NSString stringWithFormat:UCLocalize("HALFINSTALLED_PACKAGES"), count])
            message:UCLocalize("HALFINSTALLED_PACKAGE_EX")
            delegate:self
            cancelButtonTitle:UCLocalize("FORCIBLY_CLEAR")
            otherButtonTitles:
                UCLocalize("TEMPORARY_IGNORE"),
            nil
        ] autorelease];

        [alert setContext:@"fixhalf"];
        [alert setNumberOfRows:2];
        [alert show];
    } else if (!Ignored_ && [essential_ count] != 0) {
        int count = [essential_ count];

        UIAlertView *alert = [[[UIAlertView alloc]
            initWithTitle:(count == 1 ? UCLocalize("ESSENTIAL_UPGRADE") : [NSString stringWithFormat:UCLocalize("ESSENTIAL_UPGRADES"), count])
            message:UCLocalize("ESSENTIAL_UPGRADE_EX")
            delegate:self
            cancelButtonTitle:UCLocalize("TEMPORARY_IGNORE")
            otherButtonTitles:
                UCLocalize("UPGRADE_ESSENTIAL"),
                UCLocalize("COMPLETE_UPGRADE"),
            nil
        ] autorelease];

        [alert setContext:@"upgrade"];
        [alert show];
    }
}

- (void) returnToCydia {
    [self _loaded];
}

- (void) _saveConfig {
    @synchronized (database_) {
        _trace();
        MetaFile_.Sync();
        _trace();
    }

    if (Changed_) {
        NSString *error(nil);

        if (NSData *data = [NSPropertyListSerialization dataFromPropertyList:Metadata_ format:NSPropertyListBinaryFormat_v1_0 errorDescription:&error]) {
            _trace();
            NSError *error(nil);
            if (![data writeToFile:@"/var/lib/cydia/metadata.plist" options:NSAtomicWrite error:&error])
                NSLog(@"failure to save metadata data: %@", error);
            _trace();

            Changed_ = false;
        } else {
            NSLog(@"failure to serialize metadata: %@", error);
        }
    }

    CydiaWriteSources();
}

// Navigation controller for the queuing badge.
- (UINavigationController *) queueNavigationController {
    NSArray *controllers = [tabbar_ viewControllers];
    return [controllers objectAtIndex:3];
}

- (void) unloadData {
    [tabbar_ unloadData];
}

- (void) _updateData {
    [self _saveConfig];
    [self unloadData];

    UINavigationController *navigation = [self queueNavigationController];

    id queuedelegate = nil;
    if ([[navigation viewControllers] count] > 0)
        queuedelegate = [[navigation viewControllers] objectAtIndex:0];

    [queuedelegate queueStatusDidChange];
    [[navigation tabBarItem] setBadgeValue:(Queuing_ ? UCLocalize("Q_D") : nil)];
}

- (void) _refreshIfPossible:(NSDate *)update {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    bool recently = false;
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
        // If we are cancelling, we need to make sure it knows it's already loaded.
        loaded_ = true;

        [self performSelectorOnMainThread:@selector(_loaded) withObject:nil waitUntilDone:NO];
    } else {
        // We are going to load, so remember that.
        loaded_ = true;

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
            [tabbar_ performSelectorOnMainThread:@selector(setUpdate:) withObject:update waitUntilDone:NO];
    }

    [pool release];
}

- (void) refreshIfPossible {
    [NSThread detachNewThreadSelector:@selector(_refreshIfPossible:) toTarget:self withObject:[Metadata_ objectForKey:@"LastUpdate"]];
}

- (void) reloadDataWithInvocation:(NSInvocation *)invocation {
@synchronized (self) {
    UIProgressHUD *hud(loaded_ ? [self addProgressHUD] : nil);
    [hud setText:UCLocalize("RELOADING_DATA")];

    [database_ yieldToSelector:@selector(reloadDataWithInvocation:) withObject:invocation];

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

    UITabBarItem *changesItem = [[[tabbar_ viewControllers] objectAtIndex:2] tabBarItem];
    if (changes != 0) {
        _trace();
        NSString *badge([[NSNumber numberWithInt:changes] stringValue]);
        [changesItem setBadgeValue:badge];
        [changesItem setAnimatedBadge:([essential_ count] > 0)];
        [self setApplicationIconBadgeNumber:changes];
    } else {
        _trace();
        [changesItem setBadgeValue:nil];
        [changesItem setAnimatedBadge:NO];
        [self setApplicationIconBadgeNumber:0];
    }

    [self _updateData];

    if (hud != nil)
        [self removeProgressHUD:hud];
} }

- (void) updateData {
    [self _updateData];
}

- (void) update_ {
    [database_ update];
    [self performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:YES];
}

- (void) disemulate {
    if (emulated_ == nil)
        return;

    [window_ addSubview:[tabbar_ view]];
    [[emulated_ view] removeFromSuperview];
    emulated_ = nil;
    [window_ setUserInteractionEnabled:YES];
}

- (void) presentModalViewController:(UIViewController *)controller force:(BOOL)force {
    UINavigationController *navigation([[[UINavigationController alloc] initWithRootViewController:controller] autorelease]);
    if (IsWildcat_)
        [navigation setModalPresentationStyle:UIModalPresentationFormSheet];

    UIViewController *parent;
    if (emulated_ == nil)
        parent = tabbar_;
    else if (!force)
        parent = emulated_;
    else {
        [self disemulate];
        parent = tabbar_;
    }

    [parent presentModalViewController:navigation animated:YES];
}

- (ProgressController *) invokeNewProgress:(NSInvocation *)invocation forController:(UINavigationController *)navigation withTitle:(NSString *)title {
    ProgressController *progress([[[ProgressController alloc] initWithDatabase:database_ delegate:self] autorelease]);

    if (navigation != nil)
        [navigation pushViewController:progress animated:YES];
    else
        [self presentModalViewController:progress force:YES];

    [progress invoke:invocation withTitle:title];
    return progress;
}

- (void) detachNewProgressSelector:(SEL)selector toTarget:(id)target forController:(UINavigationController *)navigation title:(NSString *)title {
    [self invokeNewProgress:[NSInvocation invocationWithSelector:selector forTarget:target] forController:navigation withTitle:title];
}

- (void) repairWithInvocation:(NSInvocation *)invocation {
    _trace();
    [self invokeNewProgress:invocation forController:nil withTitle:@"REPAIRING"];
    _trace();
}

- (void) repairWithSelector:(SEL)selector {
    [self performSelectorOnMainThread:@selector(repairWithInvocation:) withObject:[NSInvocation invocationWithSelector:selector forTarget:database_] waitUntilDone:YES];
}

- (void) reloadData {
    [self reloadDataWithInvocation:nil];
    if ([database_ progressDelegate] == nil)
        [self _loaded];
}

- (void) syncData {
    [self _saveConfig];
    [self detachNewProgressSelector:@selector(update_) toTarget:self forController:nil title:@"UPDATING_SOURCES"];
}

- (void) addSource:(NSDictionary *) source {
    CydiaAddSource(source);
}

- (void) addSource:(NSString *)href withDistribution:(NSString *)distribution andSections:(NSArray *)sections {
    CydiaAddSource(href, distribution, sections);
}

- (void) addTrivialSource:(NSString *)href {
    CydiaAddSource(href, @"./");
}

- (void) updateValues {
    Changed_ = true;
}

- (void) resolve {
    pkgProblemResolver *resolver = [database_ resolver];

    resolver->InstallProtect();
    if (!resolver->Resolve(true))
        _error->Discard();
}

- (bool) perform {
    // XXX: this is a really crappy way of doing this.
    // like, seriously: this state machine is still broken, and cancelling this here doesn't really /fix/ that.
    // for one, the user can still /start/ a reloading data event while they have a queue, which is stupid
    // for two, this just means there is a race condition between the refresh completing and the confirmation controller appearing.
    if ([tabbar_ updating])
        [tabbar_ cancelUpdate];

    if (![database_ prepare])
        return false;

    ConfirmationController *page([[[ConfirmationController alloc] initWithDatabase:database_] autorelease]);
    [page setDelegate:self];
    UINavigationController *confirm_([[[UINavigationController alloc] initWithRootViewController:page] autorelease]);

    if (IsWildcat_)
        [confirm_ setModalPresentationStyle:UIModalPresentationFormSheet];
    [tabbar_ presentModalViewController:confirm_ animated:YES];

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

- (void) perform_ {
    [database_ perform];
    [self performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:YES];
}

- (void) confirmWithNavigationController:(UINavigationController *)navigation {
    Queuing_ = false;
    ++locked_;
    [self detachNewProgressSelector:@selector(perform_) toTarget:self forController:navigation title:@"RUNNING"];
    --locked_;
    [self refreshIfPossible];
}

- (void) showSettings {
    [self presentModalViewController:[[[SettingsController alloc] initWithDatabase:database_ delegate:self] autorelease] force:NO];
}

- (void) retainNetworkActivityIndicator {
    if (activity_++ == 0)
        [self setNetworkActivityIndicatorVisible:YES];

#if TraceLogging
    NSLog(@"retainNetworkActivityIndicator->%d", activity_);
#endif
}

- (void) releaseNetworkActivityIndicator {
    if (--activity_ == 0)
        [self setNetworkActivityIndicatorVisible:NO];

#if TraceLogging
    NSLog(@"releaseNetworkActivityIndicator->%d", activity_);
#endif

}

- (void) cancelAndClear:(bool)clear {
    @synchronized (self) {
        if (clear) {
            [database_ clear];
            Queuing_ = false;
        } else {
            Queuing_ = true;
        }

        [self _updateData];
    }
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

        [alert dismissWithClickedButtonIndex:-1 animated:YES];
    } else if ([context isEqualToString:@"fixhalf"]) {
        if (button == [alert cancelButtonIndex]) {
            @synchronized (self) {
                for (Package *broken in (id) broken_) {
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
        } else if (button == [alert firstOtherButtonIndex]) {
            [broken_ removeAllObjects];
            [self _loaded];
        }

        [alert dismissWithClickedButtonIndex:-1 animated:YES];
    } else if ([context isEqualToString:@"upgrade"]) {
        if (button == [alert firstOtherButtonIndex]) {
            @synchronized (self) {
                for (Package *essential in (id) essential_)
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

- (void) system:(NSString *)command {
    NSAutoreleasePool *pool([[NSAutoreleasePool alloc] init]);

    _trace();
    system([command UTF8String]);
    _trace();

    [pool release];
}

- (void) applicationWillSuspend {
    [database_ clean];
    [super applicationWillSuspend];
}

- (BOOL) isSafeToSuspend {
    if (locked_ != 0) {
#if !ForRelease
        NSLog(@"isSafeToSuspend: locked_ != 0");
#endif
        return false;
    }

    // Use external process status API internally.
    // This is probably a really bad idea.
    // XXX: what is the point of this? does this solve anything at all?
    uint64_t status = 0;
    int notify_token;
    if (notify_register_check("com.saurik.Cydia.status", &notify_token) == NOTIFY_STATUS_OK) {
        notify_get_state(notify_token, &status);
        notify_cancel(notify_token);
    }

    if (status != 0) {
#if !ForRelease
        NSLog(@"isSafeToSuspend: status != 0");
#endif
        return false;
    }

#if !ForRelease
    NSLog(@"isSafeToSuspend: -> true");
#endif
    return true;
}

- (void) applicationSuspend:(__GSEvent *)event {
    if ([self isSafeToSuspend])
        [super applicationSuspend:event];
}

- (void) _animateSuspension:(BOOL)arg0 duration:(double)arg1 startTime:(double)arg2 scale:(float)arg3 {
    if ([self isSafeToSuspend])
        [super _animateSuspension:arg0 duration:arg1 startTime:arg2 scale:arg3];
}

- (void) _setSuspended:(BOOL)value {
    if ([self isSafeToSuspend])
        [super _setSuspended:value];
}

- (UIProgressHUD *) addProgressHUD {
    UIProgressHUD *hud([[[UIProgressHUD alloc] init] autorelease]);
    [hud setAutoresizingMask:UIViewAutoresizingFlexibleBoth];

    [window_ setUserInteractionEnabled:NO];

    UIViewController *target(tabbar_);
    if (UIViewController *modal = [target modalViewController])
        target = modal;

    [hud showInView:[target view]];

    ++locked_;
    return hud;
}

- (void) removeProgressHUD:(UIProgressHUD *)hud {
    --locked_;
    [hud hide];
    [hud removeFromSuperview];
    [window_ setUserInteractionEnabled:YES];
}

- (CyteViewController *) pageForPackage:(NSString *)name {
    return [[[CYPackageController alloc] initWithDatabase:database_ forPackage:name] autorelease];
}

- (CyteViewController *) pageForURL:(NSURL *)url forExternal:(BOOL)external {
    NSString *scheme([[url scheme] lowercaseString]);
    if ([[url absoluteString] length] <= [scheme length] + 3)
        return nil;
    NSString *path([[url absoluteString] substringFromIndex:[scheme length] + 3]);
    NSArray *components([path componentsSeparatedByString:@"/"]);

    if ([scheme isEqualToString:@"apptapp"] && [components count] > 0 && [[components objectAtIndex:0] isEqualToString:@"package"]) {
        CyteViewController *controller([self pageForPackage:[components objectAtIndex:1]]);
        if (controller != nil)
            [controller setDelegate:self];
        return controller;
    }

    if ([components count] < 1 || ![scheme isEqualToString:@"cydia"])
        return nil;

    NSString *base([components objectAtIndex:0]);

    CyteViewController *controller = nil;

    if ([base isEqualToString:@"url"]) {
        // This kind of URL can contain slashes in the argument, so we can't parse them below.
        NSString *destination = [[url absoluteString] substringFromIndex:([scheme length] + [@"://" length] + [base length] + [@"/" length])];
        controller = [[[CydiaWebViewController alloc] initWithURL:[NSURL URLWithString:destination]] autorelease];
    } else if (!external && [components count] == 1) {
        if ([base isEqualToString:@"manage"]) {
            controller = [[[ManageController alloc] init] autorelease];
        }

        if ([base isEqualToString:@"storage"]) {
            controller = [[[CydiaWebViewController alloc] initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/storage/", UI_]]] autorelease];
        }

        if ([base isEqualToString:@"sources"]) {
            controller = [[[SourcesController alloc] initWithDatabase:database_] autorelease];
        }

        if ([base isEqualToString:@"home"]) {
            controller = [[[HomeController alloc] init] autorelease];
        }

        if ([base isEqualToString:@"sections"]) {
            controller = [[[SectionsController alloc] initWithDatabase:database_] autorelease];
        }

        if ([base isEqualToString:@"search"]) {
            controller = [[[SearchController alloc] initWithDatabase:database_ query:nil] autorelease];
        }

        if ([base isEqualToString:@"changes"]) {
            controller = [[[ChangesController alloc] initWithDatabase:database_] autorelease];
        }

        if ([base isEqualToString:@"installed"]) {
            controller = [[[InstalledController alloc] initWithDatabase:database_] autorelease];
        }
    } else if ([components count] == 2) {
        NSString *argument = [components objectAtIndex:1];

        if ([base isEqualToString:@"package"]) {
            controller = [self pageForPackage:argument];
        }

        if (!external && [base isEqualToString:@"search"]) {
            controller = [[[SearchController alloc] initWithDatabase:database_ query:[argument stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] autorelease];
        }

        if (!external && [base isEqualToString:@"sections"]) {
            if ([argument isEqualToString:@"all"])
                argument = nil;
            controller = [[[SectionController alloc] initWithDatabase:database_ section:[argument stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] autorelease];
        }

        if (!external && [base isEqualToString:@"sources"]) {
            if ([argument isEqualToString:@"add"]) {
                controller = [[[SourcesController alloc] initWithDatabase:database_] autorelease];
                [(SourcesController *)controller showAddSourcePrompt];
            } else {
                Source *source = [database_ sourceWithKey:[argument stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
                controller = [[[SourceController alloc] initWithDatabase:database_ source:source] autorelease];
            }
        }

        if (!external && [base isEqualToString:@"launch"]) {
            [self launchApplicationWithIdentifier:argument suspended:NO];
            return nil;
        }
    } else if (!external && [components count] == 3) {
        NSString *arg1 = [components objectAtIndex:1];
        NSString *arg2 = [components objectAtIndex:2];

        if ([base isEqualToString:@"package"]) {
            if ([arg2 isEqualToString:@"settings"]) {
                controller = [[[PackageSettingsController alloc] initWithDatabase:database_ package:arg1] autorelease];
            } else if ([arg2 isEqualToString:@"files"]) {
                if (Package *package = [database_ packageWithName:arg1]) {
                    controller = [[[FileTable alloc] initWithDatabase:database_] autorelease];
                    [(FileTable *)controller setPackage:package];
                }
            }
        }
    }

    [controller setDelegate:self];
    return controller;
}

- (BOOL) openCydiaURL:(NSURL *)url forExternal:(BOOL)external {
    CyteViewController *page([self pageForURL:url forExternal:external]);

    if (page != nil)
        [tabbar_ setUnselectedViewController:page];

    return page != nil;
}

- (void) applicationOpenURL:(NSURL *)url {
    [super applicationOpenURL:url];

    if (!loaded_)
        starturl_ = url;
    else
        [self openCydiaURL:url forExternal:YES];
}

- (void) applicationWillResignActive:(UIApplication *)application {
    // Stop refreshing if you get a phone call or lock the device.
    if ([tabbar_ updating])
        [tabbar_ cancelUpdate];

    if ([[self superclass] instancesRespondToSelector:@selector(applicationWillResignActive:)])
        [super applicationWillResignActive:application];
}

- (void) saveState {
    [Metadata_ setObject:[tabbar_ navigationURLCollection] forKey:@"InterfaceState"];
    [Metadata_ setObject:[NSDate date] forKey:@"LastClosed"];
    [Metadata_ setObject:[NSNumber numberWithInt:[tabbar_ selectedIndex]] forKey:@"InterfaceIndex"];
    Changed_ = true;

    [self _saveConfig];
}

- (void) applicationWillTerminate:(UIApplication *)application {
    [self saveState];
}

- (void) setConfigurationData:(NSString *)data {
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
        otherButtonTitles:
            UCLocalize("ACCEPT_NEW_COPY"),
            // XXX: UCLocalize("SEE_WHAT_CHANGED"),
        nil
    ] autorelease];

    [alert setContext:@"conffile"];
    [alert setNumberOfRows:2];
    [alert show];
}

- (void) addStashController {
    ++locked_;
    stash_ = [[[StashController alloc] init] autorelease];
    [window_ addSubview:[stash_ view]];
}

- (void) removeStashController {
    [[stash_ view] removeFromSuperview];
    stash_ = nil;
    --locked_;
}

- (void) stash {
    [self setIdleTimerDisabled:YES];

    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackOpaque];
    UpdateExternalStatus(1);
    [self yieldToSelector:@selector(system:) withObject:@"/usr/libexec/cydia/free.sh"];
    UpdateExternalStatus(0);

    [self removeStashController];

    pid_t pid(ExecFork());
    if (pid == 0) {
        execlp("launchctl", "launchctl", "stop", "com.apple.SpringBoard", NULL);
        perror("launchctl stop");
        exit(0);
    }

    ReapZombie(pid);
}

- (void) setupViewControllers {
    tabbar_ = [[[CYTabBarController alloc] initWithDatabase:database_] autorelease];

    NSMutableArray *items([NSMutableArray arrayWithObjects:
        [[[UITabBarItem alloc] initWithTitle:@"Cydia" image:[UIImage applicationImageNamed:@"home.png"] tag:0] autorelease],
        [[[UITabBarItem alloc] initWithTitle:UCLocalize("SECTIONS") image:[UIImage applicationImageNamed:@"install.png"] tag:0] autorelease],
        [[[UITabBarItem alloc] initWithTitle:(AprilFools_ ? @"Timeline" : UCLocalize("CHANGES")) image:[UIImage applicationImageNamed:@"changes.png"] tag:0] autorelease],
        [[[UITabBarItem alloc] initWithTitle:UCLocalize("SEARCH") image:[UIImage applicationImageNamed:@"search.png"] tag:0] autorelease],
    nil]);

    if (IsWildcat_) {
        [items insertObject:[[[UITabBarItem alloc] initWithTitle:UCLocalize("SOURCES") image:[UIImage applicationImageNamed:@"source.png"] tag:0] autorelease] atIndex:3];
        [items insertObject:[[[UITabBarItem alloc] initWithTitle:UCLocalize("INSTALLED") image:[UIImage applicationImageNamed:@"manage.png"] tag:0] autorelease] atIndex:3];
    } else {
        [items insertObject:[[[UITabBarItem alloc] initWithTitle:UCLocalize("MANAGE") image:[UIImage applicationImageNamed:@"manage.png"] tag:0] autorelease] atIndex:3];
    }

    NSMutableArray *controllers([NSMutableArray array]);
    for (UITabBarItem *item in items) {
        UINavigationController *controller([[[UINavigationController alloc] init] autorelease]);
        [controller setTabBarItem:item];
        [controllers addObject:controller];
    }
    [tabbar_ setViewControllers:controllers];

    [tabbar_ setUpdateDelegate:self];
}

- (void) _sendMemoryWarningNotification {
    if (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iPhoneOS_3_0) // XXX: maybe 4_0?
        [[NSNotificationCenter defaultCenter] postNotificationName:@"UIApplicationMemoryWarningNotification" object:[UIApplication sharedApplication]];
    else
        [[NSNotificationCenter defaultCenter] postNotificationName:@"UIApplicationDidReceiveMemoryWarningNotification" object:[UIApplication sharedApplication]];
}

- (void) _sendMemoryWarningNotifications {
    while (true) {
        [self performSelectorOnMainThread:@selector(_sendMemoryWarningNotification) withObject:nil waitUntilDone:NO];
        sleep(2);
        //usleep(2000000);
    }
}

- (void) applicationDidReceiveMemoryWarning:(UIApplication *)application {
    NSLog(@"--");
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
}

- (void) applicationDidFinishLaunching:(id)unused {
    //[NSThread detachNewThreadSelector:@selector(_sendMemoryWarningNotifications) toTarget:self withObject:nil];

_trace();
    if ([self respondsToSelector:@selector(setApplicationSupportsShakeToEdit:)])
        [self setApplicationSupportsShakeToEdit:NO];

    @synchronized (HostConfig_) {
        [BridgedHosts_ addObject:[[NSURL URLWithString:CydiaURL(@"")] host]];
    }

    [NSURLCache setSharedURLCache:[[[CYURLCache alloc]
        initWithMemoryCapacity:524288
        diskCapacity:10485760
        diskPath:[NSString stringWithFormat:@"%@/Library/Caches/com.saurik.Cydia/SDURLCache", @"/var/root"]
    ] autorelease]];

    [CydiaWebViewController _initialize];

    [NSURLProtocol registerClass:[CydiaURLProtocol class]];

    // this would disallow http{,s} URLs from accessing this data
    //[WebView registerURLSchemeAsLocal:@"cydia"];

    Font12_ = [UIFont systemFontOfSize:12];
    Font12Bold_ = [UIFont boldSystemFontOfSize:12];
    Font14_ = [UIFont systemFontOfSize:14];
    Font18Bold_ = [UIFont boldSystemFontOfSize:18];
    Font22Bold_ = [UIFont boldSystemFontOfSize:22];

    essential_ = [NSMutableArray arrayWithCapacity:4];
    broken_ = [NSMutableArray arrayWithCapacity:4];

    // XXX: I really need this thing... like, seriously... I'm sorry
    [[[AppCacheController alloc] initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/appcache/", UI_]]] reloadData];

    window_ = [[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
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
    [database_ setDelegate:self];

    [window_ setUserInteractionEnabled:NO];
    [self setupViewControllers];

    emulated_ = [[[CydiaLoadingViewController alloc] init] autorelease];
    [window_ addSubview:[emulated_ view]];

    [self performSelector:@selector(loadData) withObject:nil afterDelay:0];
_trace();
}

- (NSArray *) defaultStartPages {
    NSMutableArray *standard = [NSMutableArray array];
    [standard addObject:[NSArray arrayWithObject:@"cydia://home"]];
    [standard addObject:[NSArray arrayWithObject:@"cydia://sections"]];
    [standard addObject:[NSArray arrayWithObject:@"cydia://changes"]];
    if (!IsWildcat_) {
        [standard addObject:[NSArray arrayWithObject:@"cydia://manage"]];
    } else {
        [standard addObject:[NSArray arrayWithObject:@"cydia://installed"]];
        [standard addObject:[NSArray arrayWithObject:@"cydia://sources"]];
    }
    [standard addObject:[NSArray arrayWithObject:@"cydia://search"]];
    return standard;
}

- (void) loadData {
_trace();
    if (Role_ == nil) {
        [window_ setUserInteractionEnabled:YES];
        [self showSettings];
        return;
    } else {
        if ([emulated_ modalViewController] != nil)
            [emulated_ dismissModalViewControllerAnimated:YES];
        [window_ setUserInteractionEnabled:NO];
    }

    [self reloadDataWithInvocation:nil];
    [self refreshIfPossible];
    PrintTimes();

    [self disemulate];

    int savedIndex = [[Metadata_ objectForKey:@"InterfaceIndex"] intValue];
    NSArray *saved = [[Metadata_ objectForKey:@"InterfaceState"] mutableCopy];
    int standardIndex = 0;
    NSArray *standard = [self defaultStartPages];

    BOOL valid = YES;

    if (saved == nil)
        valid = NO;

    NSDate *closed = [Metadata_ objectForKey:@"LastClosed"];
    if (valid && closed != nil) {
        NSTimeInterval interval([closed timeIntervalSinceNow]);
        // XXX: Is 30 minutes the optimal time here?
        if (interval <= -(30*60))
            valid = NO;
    }

    if (valid && [saved count] != [standard count])
        valid = NO;

    if (valid) {
        for (unsigned int i = 0; i < [standard count]; i++) {
            NSArray *std = [standard objectAtIndex:i], *sav = [saved objectAtIndex:i];
            // XXX: The "hasPrefix" sanity check here could be, in theory, fooled,
            //      but it's good enough for now.
            if ([sav count] == 0 || ![[sav objectAtIndex:0] hasPrefix:[std objectAtIndex:0]]) {
                valid = NO;
                break;
            }
        }
    }

    NSArray *items = nil;
    if (valid) {
        [tabbar_ setSelectedIndex:savedIndex];
        items = saved;
    } else {
        [tabbar_ setSelectedIndex:standardIndex];
        items = standard;
    }

    for (unsigned int tab = 0; tab < [[tabbar_ viewControllers] count]; tab++) {
        NSArray *stack = [items objectAtIndex:tab];
        UINavigationController *navigation = [[tabbar_ viewControllers] objectAtIndex:tab];
        NSMutableArray *current = [NSMutableArray array];

        for (unsigned int nav = 0; nav < [stack count]; nav++) {
            NSString *addr = [stack objectAtIndex:nav];
            NSURL *url = [NSURL URLWithString:addr];
            CyteViewController *page = [self pageForURL:url forExternal:NO];
            if (page != nil)
                [current addObject:page];
        }

        [navigation setViewControllers:current];
    }

    // (Try to) show the startup URL.
    if (starturl_ != nil) {
        [self openCydiaURL:starturl_ forExternal:NO];
        starturl_ = nil;
    }
}

- (void) showActionSheet:(UIActionSheet *)sheet fromItem:(UIBarButtonItem *)item {
    if (item != nil && IsWildcat_) {
        [sheet showFromBarButtonItem:item animated:YES];
    } else {
        [sheet showInView:window_];
    }
}

- (void) addProgressEvent:(CydiaProgressEvent *)event forTask:(NSString *)task {
    id<ProgressDelegate> progress([database_ progressDelegate] ?: [self invokeNewProgress:nil forController:nil withTitle:task]);
    [progress setTitle:task];
    [progress addProgressEvent:event];
}

- (void) addProgressEventForTask:(NSArray *)data {
    CydiaProgressEvent *event([data objectAtIndex:0]);
    NSString *task([data count] < 2 ? nil : [data objectAtIndex:1]);
    [self addProgressEvent:event forTask:task];
}

- (void) addProgressEventOnMainThread:(CydiaProgressEvent *)event forTask:(NSString *)task {
    [self performSelectorOnMainThread:@selector(addProgressEventForTask:) withObject:[NSArray arrayWithObjects:event, task, nil] waitUntilDone:YES];
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

static NSSet *MobilizedFiles_;

static NSURL *MobilizeURL(NSURL *url) {
    NSString *path([url path]);
    if ([path hasPrefix:@"/var/root/"]) {
        NSString *file([path substringFromIndex:10]);
        if ([MobilizedFiles_ containsObject:file])
            url = [NSURL fileURLWithPath:[@"/var/mobile/" stringByAppendingString:file] isDirectory:NO];
    }

    return url;
}

Class $CFXPreferencesPropertyListSource;
@class CFXPreferencesPropertyListSource;

MSHook(BOOL, CFXPreferencesPropertyListSource$_backingPlistChangedSinceLastSync, CFXPreferencesPropertyListSource *self, SEL _cmd) {
    NSURL *&url(MSHookIvar<NSURL *>(self, "_url")), *old(url);
    NSAutoreleasePool *pool([[NSAutoreleasePool alloc] init]);
    url = MobilizeURL(url);
    BOOL value(_CFXPreferencesPropertyListSource$_backingPlistChangedSinceLastSync(self, _cmd));
    //NSLog(@"%@ %s", [url absoluteString], value ? "YES" : "NO");
    url = old;
    [pool release];
    return value;
}

MSHook(void *, CFXPreferencesPropertyListSource$createPlistFromDisk, CFXPreferencesPropertyListSource *self, SEL _cmd) {
    NSURL *&url(MSHookIvar<NSURL *>(self, "_url")), *old(url);
    NSAutoreleasePool *pool([[NSAutoreleasePool alloc] init]);
    url = MobilizeURL(url);
    void *value(_CFXPreferencesPropertyListSource$createPlistFromDisk(self, _cmd));
    //NSLog(@"%@ %@", [url absoluteString], value);
    url = old;
    [pool release];
    return value;
}

Class $NSURLConnection;

MSHook(id, NSURLConnection$init$, NSURLConnection *self, SEL _cmd, NSURLRequest *request, id delegate, BOOL usesCache, int64_t maxContentLength, BOOL startImmediately, NSDictionary *connectionProperties) {
    NSMutableURLRequest *copy([request mutableCopy]);

    NSURL *url([copy URL]);

    NSString *host([url host]);
    NSString *scheme([[url scheme] lowercaseString]);

    NSString *compound([NSString stringWithFormat:@"%@:%@", scheme, host]);

    @synchronized (HostConfig_) {
        if ([copy respondsToSelector:@selector(setHTTPShouldUsePipelining:)])
            if ([PipelinedHosts_ containsObject:host] || [PipelinedHosts_ containsObject:compound])
                [copy setHTTPShouldUsePipelining:YES];

        if (NSString *control = [copy valueForHTTPHeaderField:@"Cache-Control"])
            if ([control isEqualToString:@"max-age=0"])
                if ([CachedURLs_ containsObject:url]) {
#if !ForRelease
                    NSLog(@"~~~: %@", url);
#endif

                    [copy setCachePolicy:NSURLRequestReturnCacheDataDontLoad];

                    [copy setValue:nil forHTTPHeaderField:@"Cache-Control"];
                    [copy setValue:nil forHTTPHeaderField:@"If-Modified-Since"];
                    [copy setValue:nil forHTTPHeaderField:@"If-None-Match"];
                }
    }

    if ((self = _NSURLConnection$init$(self, _cmd, copy, delegate, usesCache, maxContentLength, startImmediately, connectionProperties)) != nil) {
    } return self;
}

int main(int argc, char *argv[]) {
    NSAutoreleasePool *pool([[NSAutoreleasePool alloc] init]);

    _trace();

    UpdateExternalStatus(0);

    if (Class $UIDevice = objc_getClass("UIDevice")) {
        UIDevice *device([$UIDevice currentDevice]);
        IsWildcat_ = [device respondsToSelector:@selector(isWildcat)] && [device isWildcat];
    } else
        IsWildcat_ = false;

    UIScreen *screen([UIScreen mainScreen]);
    if ([screen respondsToSelector:@selector(scale)])
        ScreenScale_ = [screen scale];
    else
        ScreenScale_ = 1;

    UIDevice *device([UIDevice currentDevice]);
    if (![device respondsToSelector:@selector(userInterfaceIdiom)])
        Idiom_ = @"iphone";
    else {
        UIUserInterfaceIdiom idiom([device userInterfaceIdiom]);
        if (idiom == UIUserInterfaceIdiomPhone)
            Idiom_ = @"iphone";
        else if (idiom == UIUserInterfaceIdiomPad)
            Idiom_ = @"ipad";
        else
            NSLog(@"unknown UIUserInterfaceIdiom!");
    }

    Pcre pattern("^([0-9]+\\.[0-9]+)");

    if (pattern([device systemVersion]))
        Firmware_ = pattern[1];
    if (pattern(Cydia_))
        Major_ = pattern[1];

    SessionData_ = [NSMutableDictionary dictionaryWithCapacity:4];

    HostConfig_ = [[[NSObject alloc] init] autorelease];
    @synchronized (HostConfig_) {
        BridgedHosts_ = [NSMutableSet setWithCapacity:4];
        TokenHosts_ = [NSMutableSet setWithCapacity:4];
        InsecureHosts_ = [NSMutableSet setWithCapacity:4];
        PipelinedHosts_ = [NSMutableSet setWithCapacity:4];
        CachedURLs_ = [NSMutableSet setWithCapacity:32];
    }

    NSString *ui(@"ui/ios");
    if (Idiom_ != nil)
        ui = [ui stringByAppendingString:[NSString stringWithFormat:@"~%@", Idiom_]];
    ui = [ui stringByAppendingString:[NSString stringWithFormat:@"/%@", Major_]];
    UI_ = CydiaURL(ui);

    PackageName = reinterpret_cast<CYString &(*)(Package *, SEL)>(method_getImplementation(class_getInstanceMethod([Package class], @selector(cyname))));

    MobilizedFiles_ = [NSMutableSet setWithObjects:
        @"Library/Preferences/com.apple.Accessibility.plist",
        @"Library/Preferences/com.apple.preferences.sounds.plist",
    nil];

    /* Library Hacks {{{ */
    class_addMethod(objc_getClass("DOMNodeList"), @selector(countByEnumeratingWithState:objects:count:), (IMP) &DOMNodeList$countByEnumeratingWithState$objects$count$, "I20@0:4^{NSFastEnumerationState}8^@12I16");

    $CFXPreferencesPropertyListSource = objc_getClass("CFXPreferencesPropertyListSource");

    Method CFXPreferencesPropertyListSource$_backingPlistChangedSinceLastSync(class_getInstanceMethod($CFXPreferencesPropertyListSource, @selector(_backingPlistChangedSinceLastSync)));
    if (CFXPreferencesPropertyListSource$_backingPlistChangedSinceLastSync != NULL) {
        _CFXPreferencesPropertyListSource$_backingPlistChangedSinceLastSync = reinterpret_cast<BOOL (*)(CFXPreferencesPropertyListSource *, SEL)>(method_getImplementation(CFXPreferencesPropertyListSource$_backingPlistChangedSinceLastSync));
        method_setImplementation(CFXPreferencesPropertyListSource$_backingPlistChangedSinceLastSync, reinterpret_cast<IMP>(&$CFXPreferencesPropertyListSource$_backingPlistChangedSinceLastSync));
    }

    Method CFXPreferencesPropertyListSource$createPlistFromDisk(class_getInstanceMethod($CFXPreferencesPropertyListSource, @selector(createPlistFromDisk)));
    if (CFXPreferencesPropertyListSource$createPlistFromDisk != NULL) {
        _CFXPreferencesPropertyListSource$createPlistFromDisk = reinterpret_cast<void *(*)(CFXPreferencesPropertyListSource *, SEL)>(method_getImplementation(CFXPreferencesPropertyListSource$createPlistFromDisk));
        method_setImplementation(CFXPreferencesPropertyListSource$createPlistFromDisk, reinterpret_cast<IMP>(&$CFXPreferencesPropertyListSource$createPlistFromDisk));
    }

    $WebDefaultUIKitDelegate = objc_getClass("WebDefaultUIKitDelegate");
    Method UIWebDocumentView$_setUIKitDelegate$(class_getInstanceMethod([WebView class], @selector(_setUIKitDelegate:)));
    if (UIWebDocumentView$_setUIKitDelegate$ != NULL) {
        _UIWebDocumentView$_setUIKitDelegate$ = reinterpret_cast<void (*)(UIWebDocumentView *, SEL, id)>(method_getImplementation(UIWebDocumentView$_setUIKitDelegate$));
        method_setImplementation(UIWebDocumentView$_setUIKitDelegate$, reinterpret_cast<IMP>(&$UIWebDocumentView$_setUIKitDelegate$));
    }

    $NSURLConnection = objc_getClass("NSURLConnection");
    Method NSURLConnection$init$(class_getInstanceMethod($NSURLConnection, @selector(_initWithRequest:delegate:usesCache:maxContentLength:startImmediately:connectionProperties:)));
    if (NSURLConnection$init$ != NULL) {
        _NSURLConnection$init$ = reinterpret_cast<id (*)(NSURLConnection *, SEL, NSURLRequest *, id, BOOL, int64_t, BOOL, NSDictionary *)>(method_getImplementation(NSURLConnection$init$));
        method_setImplementation(NSURLConnection$init$, reinterpret_cast<IMP>(&$NSURLConnection$init$));
    }
    /* }}} */
    /* Set Locale {{{ */
    Locale_ = CFLocaleCopyCurrent();
    Languages_ = [NSLocale preferredLanguages];

    //CFStringRef locale(CFLocaleGetIdentifier(Locale_));
    //NSLog(@"%@", [Languages_ description]);

    const char *lang;
    if (Locale_ != NULL)
        lang = [(NSString *) CFLocaleGetIdentifier(Locale_) UTF8String];
    else if (Languages_ != nil && [Languages_ count] != 0)
        lang = [[Languages_ objectAtIndex:0] UTF8String];
    else
        // XXX: consider just setting to C and then falling through?
        lang = NULL;

    if (lang != NULL) {
        Pcre pattern("^([a-z][a-z])(?:-[A-Za-z]*)?(_[A-Z][A-Z])?$");
        lang = !pattern(lang) ? NULL : [pattern->*@"%1$@%2$@" UTF8String];
    }

    NSLog(@"Setting Language: %s", lang);

    if (lang != NULL) {
        setenv("LANG", lang, true);
        std::setlocale(LC_ALL, lang);
    }
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

    SerialNumber_ = (NSString *) CYIOGetValue("IOService:/", @"IOPlatformSerialNumber");
    ChipID_ = [CYHex((NSData *) CYIOGetValue("IODeviceTree:/chosen", @"unique-chip-id"), true) uppercaseString];
    BBSNum_ = CYHex((NSData *) CYIOGetValue("IOService:/AppleARMPE/baseband", @"snum"), false);

    UniqueID_ = [device uniqueIdentifier];

    if (NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:@"/Applications/MobileSafari.app/Info.plist"]) {
        Product_ = [info objectForKey:@"SafariProductVersion"];
        Safari_ = [info objectForKey:@"CFBundleVersion"];
    }

    NSString *agent([NSString stringWithFormat:@"Cydia/%@ CF/%.2f", Cydia_, kCFCoreFoundationVersionNumber]);

    if (Pcre match = Pcre("^[0-9]+(\\.[0-9]+)+", Safari_))
        agent = [NSString stringWithFormat:@"Safari/%@ %@", match[0], agent];
    if (Pcre match = Pcre("^[0-9]+[A-Z][0-9]+[a-z]?", System_))
        agent = [NSString stringWithFormat:@"Mobile/%@ %@", match[0], agent];
    if (Pcre match = Pcre("^[0-9]+(\\.[0-9]+)+", Product_))
        agent = [NSString stringWithFormat:@"Version/%@ %@", match[0], agent];

    UserAgent_ = agent;
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

        Values_ = [Metadata_ objectForKey:@"Values"];
        Sections_ = [Metadata_ objectForKey:@"Sections"];
        Sources_ = [Metadata_ objectForKey:@"Sources"];

        Token_ = [Metadata_ objectForKey:@"Token"];

        Version_ = [Metadata_ objectForKey:@"Version"];
    }

    if (Settings_ != nil)
        Role_ = [Settings_ objectForKey:@"Role"];

    if (Values_ == nil) {
        Values_ = [[[NSMutableDictionary alloc] initWithCapacity:4] autorelease];
        [Metadata_ setObject:Values_ forKey:@"Values"];
    }

    if (Sections_ == nil) {
        Sections_ = [[[NSMutableDictionary alloc] initWithCapacity:32] autorelease];
        [Metadata_ setObject:Sections_ forKey:@"Sections"];
    }

    if (Sources_ == nil) {
        Sources_ = [[[NSMutableDictionary alloc] initWithCapacity:0] autorelease];
        [Metadata_ setObject:Sources_ forKey:@"Sources"];
    }

    if (Version_ == nil) {
        Version_ = [NSNumber numberWithUnsignedInt:0];
        [Metadata_ setObject:Version_ forKey:@"Version"];
    }

    if ([Version_ unsignedIntValue] == 0) {
        CydiaAddSource(@"http://apt.thebigboss.org/repofiles/cydia/", @"stable", [NSMutableArray arrayWithObject:@"main"]);
        CydiaAddSource(@"http://apt.modmyi.com/", @"stable", [NSMutableArray arrayWithObject:@"main"]);
        CydiaAddSource(@"http://cydia.zodttd.com/repo/cydia/", @"stable", [NSMutableArray arrayWithObject:@"main"]);
        CydiaAddSource(@"http://repo666.ultrasn0w.com/", @"./");

        Version_ = [NSNumber numberWithUnsignedInt:1];
        [Metadata_ setObject:Version_ forKey:@"Version"];

        [Metadata_ removeObjectForKey:@"LastUpdate"];

        Changed_ = true;
    }
    /* }}} */

    CydiaWriteSources();

    _trace();
    MetaFile_.Open("/var/lib/cydia/metadata.cb0");
    _trace();

    if (Packages_ != nil) {
        bool fail(false);
        CFDictionaryApplyFunction((CFDictionaryRef) Packages_, &PackageImport, &fail);
        _trace();

        if (!fail) {
            [Metadata_ removeObjectForKey:@"Packages"];
            Packages_ = nil;
            Changed_ = true;
        }
    }

    Finishes_ = [NSArray arrayWithObjects:@"return", @"reopen", @"restart", @"reload", @"reboot", nil];

#define MobileSubstrate_(name) \
    if (substrate && access("/Library/MobileSubstrate/DynamicLibraries/" #name ".dylib", F_OK) == 0) { \
        void *handle(dlopen("/Library/MobileSubstrate/DynamicLibraries/" #name ".dylib", RTLD_LAZY | RTLD_GLOBAL)); \
        if (handle == NULL) \
            NSLog(@"%s", dlerror()); \
    }

    MobileSubstrate_(Activator)
    MobileSubstrate_(libstatusbar)
    MobileSubstrate_(SimulatedKeyEvents)
    MobileSubstrate_(WinterBoard)

    /*if (substrate && access("/Library/MobileSubstrate/MobileSubstrate.dylib", F_OK) == 0)
        dlopen("/Library/MobileSubstrate/MobileSubstrate.dylib", RTLD_LAZY | RTLD_GLOBAL);*/

    int version([[NSString stringWithContentsOfFile:@"/var/lib/cydia/firmware.ver"] intValue]);

    if (access("/User", F_OK) != 0 || version != 5) {
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

    BOOL (*GSSystemHasCapability)(CFStringRef) = reinterpret_cast<BOOL (*)(CFStringRef)>(dlsym(RTLD_DEFAULT, "GSSystemHasCapability"));
    ShowPromoted_ = GSSystemHasCapability != NULL && GSSystemHasCapability(CFSTR("armv7"));

    Colon_ = UCLocalize("COLON_DELIMITED");
    Elision_ = UCLocalize("ELISION");
    Error_ = UCLocalize("ERROR");
    Warning_ = UCLocalize("WARNING");

#if !ForRelease
    AprilFools_ = true;
#else
    CFGregorianDate date(CFAbsoluteTimeGetGregorianDate(CFAbsoluteTimeGetCurrent(), CFTimeZoneCopySystem()));
    AprilFools_ = date.month == 4 && date.day == 1;
#endif

    _trace();
    int value(UIApplicationMain(argc, argv, @"Cydia", @"Cydia"));

    CGColorSpaceRelease(space_);
    CFRelease(Locale_);

    [pool release];
    return value;
}
