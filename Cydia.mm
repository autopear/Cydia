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

#include <objc/objc.h>
#include <objc/runtime.h>

#include <CoreGraphics/CoreGraphics.h>
#include <GraphicsServices/GraphicsServices.h>
#include <Foundation/Foundation.h>

#import <QuartzCore/CALayer.h>

#import <UIKit/UIKit.h>

// XXX: remove
#import <MessageUI/MailComposeController.h>

#include <sstream>
#include <string>

#include <ext/stdio_filebuf.h>

#include <apt-pkg/acquire.h>
#include <apt-pkg/acquire-item.h>
#include <apt-pkg/algorithms.h>
#include <apt-pkg/cachefile.h>
#include <apt-pkg/clean.h>
#include <apt-pkg/configuration.h>
#include <apt-pkg/debmetaindex.h>
#include <apt-pkg/error.h>
#include <apt-pkg/init.h>
#include <apt-pkg/mmap.h>
#include <apt-pkg/pkgrecords.h>
#include <apt-pkg/sha1.h>
#include <apt-pkg/sourcelist.h>
#include <apt-pkg/sptr.h>
#include <apt-pkg/strutl.h>

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

static uint64_t profile_;

#define _timestamp ({ \
    struct timeval tv; \
    gettimeofday(&tv, NULL); \
    tv.tv_sec * 1000000 + tv.tv_usec; \
})

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

    _finline This_ &operator =(Type_ *value) {
        if (value_ != value) {
            Clear_();
            value_ = value;
            Retain_();
        } return this;
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

/* NSForcedOrderingSearch doesn't work on the iPhone */
static const NSStringCompareOptions BaseCompareOptions_ = NSNumericSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch;
static const NSStringCompareOptions ForcedCompareOptions_ = BaseCompareOptions_;
static const NSStringCompareOptions LaxCompareOptions_ = BaseCompareOptions_ | NSCaseInsensitiveSearch;

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
#define ForSaurik (1 && !ForRelease)
#define IgnoreInstall (0 && !ForRelease)
#define RecycleWebViews 0
#define AlwaysReload (1 && !ForRelease)

#if ForRelease
#undef _trace
#define _trace(args...)
#endif

/* Radix Sort {{{ */
@interface NSMutableArray (Radix)
- (void) radixSortUsingSelector:(SEL)selector withObject:(id)object;
@end

@implementation NSMutableArray (Radix)

- (void) radixSortUsingSelector:(SEL)selector withObject:(id)object {
    NSInvocation *invocation([NSInvocation invocationWithMethodSignature:[NSMethodSignature signatureWithObjCTypes:"L12@0:4@8"]]);
    [invocation setSelector:selector];
    [invocation setArgument:&object atIndex:2];

    size_t count([self count]);

    struct RadixItem {
        size_t index;
        uint32_t key;
    } *swap(new RadixItem[count * 2]), *lhs(swap), *rhs(swap + count);

    for (size_t i(0); i != count; ++i) {
        RadixItem &item(lhs[i]);
        item.index = i;

        id object([self objectAtIndex:i]);
        [invocation setTarget:object];

        [invocation invoke];
        [invocation getReturnValue:&item.key];
    }

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

        RadixItem *tmp(lhs);
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

@end
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
+ (NSString *) stringWithUTF8Bytes:(const char *)bytes length:(int)length;
- (NSComparisonResult) compareByPath:(NSString *)other;
@end

@implementation NSString (Cydia)

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

@end

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

static CGColor Blue_;
static CGColor Blueish_;
static CGColor Black_;
static CGColor Off_;
static CGColor White_;
static CGColor Gray_;

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

CFLocaleRef Locale_;
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
        return @"Never or Unknown";

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

NSString *StripVersion(NSString *version) {
    NSRange colon = [version rangeOfString:@":"];
    if (colon.location != NSNotFound)
        version = [version substringFromIndex:(colon.location + 1)];
    return version;
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

    static Pcre title_r("^(.*?) \\(.*\\)$");
    if (title_r(data, size))
        return Simplify(title_r[1]);

    return title;
}
/* }}} */

bool isSectionVisible(NSString *section) {
    NSDictionary *metadata = [Sections_ objectForKey:section];
    NSNumber *hidden = metadata == nil ? nil : [metadata objectForKey:@"Hidden"];
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

@protocol CydiaDelegate
- (void) installPackage:(Package *)package;
- (void) removePackage:(Package *)package;
- (void) slideUp:(UIActionSheet *)alert;
- (void) distUpgrade;
- (void) updateData;
- (void) syncData;
- (void) askForSettings;
- (UIProgressHUD *) addProgressHUD;
- (RVPage *) pageForURL:(NSURL *)url hasTag:(int *)tag;
- (RVPage *) pageForPackage:(NSString *)name;
- (void) openMailToURL:(NSURL *)url;
- (void) clearFirstResponder;
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
        [delegate_ setProgressTitle:[NSString stringWithUTF8String:Op.c_str()]];
        [delegate_ setProgressPercent:(Percent / 100)];
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
        [delegate_ setProgressPercent:1];
    }
};
/* }}} */

/* Database Interface {{{ */
@interface Database : NSObject {
    pkgCacheFile cache_;
    pkgDepCache::Policy *policy_;
    pkgRecords *records_;
    pkgProblemResolver *resolver_;
    pkgAcquire *fetcher_;
    FileFd *lock_;
    SPtr<pkgPackageManager> manager_;
    pkgSourceList *list_;

    NSMutableDictionary *sources_;
    NSMutableArray *packages_;

    _transient NSObject<ConfigurationDelegate, ProgressDelegate> *delegate_;
    Status status_;
    Progress progress_;

    int cydiafd_;
    int statusfd_;
    FILE *input_;
}

+ (Database *) sharedInstance;

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
- (Source *) getSource:(const pkgCache::PkgFileIterator &)file;
@end
/* }}} */

/* Source Class {{{ */
@interface Source : NSObject {
    NSString *description_;
    NSString *label_;
    NSString *origin_;

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
    pkgCache::PkgIterator iterator_;
    _transient Database *database_;
    pkgCache::VerIterator version_;
    pkgCache::VerFileIterator file_;

    Source *source_;
    bool cached_;

    NSString *section_;

    NSString *latest_;
    NSString *installed_;

    NSString *id_;
    NSString *name_;
    NSString *tagline_;
    NSString *icon_;
    NSString *depiction_;
    NSString *homepage_;
    Address *sponsor_;
    Address *author_;
    NSArray *tags_;
    NSString *role_;

    NSArray *relationships_;
}

- (Package *) initWithIterator:(pkgCache::PkgIterator)iterator database:(Database *)database;
+ (Package *) packageWithIterator:(pkgCache::PkgIterator)iterator database:(Database *)database;

- (pkgCache::PkgIterator) iterator;

- (NSString *) section;
- (NSString *) simpleSection;

- (NSString *) uri;

- (Address *) maintainer;
- (size_t) size;
- (NSString *) description;
- (NSString *) index;

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
- (NSString *) tagline;
- (UIImage *) icon;
- (NSString *) homepage;
- (NSString *) depiction;
- (Address *) author;

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

- (NSComparisonResult) compareByName:(Package *)package;
- (NSComparisonResult) compareBySection:(Package *)package;

- (uint32_t) compareForChanges;

- (void) install;
- (void) remove;

- (NSNumber *) isUnfilteredAndSearchedForBy:(NSString *)search;
- (NSNumber *) isInstalledAndVisible:(NSNumber *)number;
- (NSNumber *) isVisiblyUninstalledInSection:(NSString *)section;
- (NSNumber *) isVisibleInSource:(Source *)source;

@end

@implementation Package

- (void) dealloc {
    if (source_ != nil)
        [source_ release];

    if (section_ != nil)
        [section_ release];

    [latest_ release];
    if (installed_ != nil)
        [installed_ release];

    [id_ release];
    if (name_ != nil)
        [name_ release];
    [tagline_ release];
    if (icon_ != nil)
        [icon_ release];
    if (depiction_ != nil)
        [depiction_ release];
    if (homepage_ != nil)
        [homepage_ release];
    if (sponsor_ != nil)
        [sponsor_ release];
    if (author_ != nil)
        [author_ release];
    if (tags_ != nil)
        [tags_ release];
    if (role_ != nil)
        [role_ release];

    if (relationships_ != nil)
        [relationships_ release];

    [super dealloc];
}

+ (NSArray *) _attributeKeys {
    return [NSArray arrayWithObjects:@"applications", @"author", @"depiction", @"description", @"essential", @"homepage", @"icon", @"id", @"installed", @"latest", @"maintainer", @"name", @"purposes", @"section", @"size", @"source", @"sponsor", @"tagline", @"warnings", nil];
}

- (NSArray *) attributeKeys {
    return [[self class] _attributeKeys];
}

+ (BOOL) isKeyExcludedFromWebScript:(const char *)name {
    return ![[self _attributeKeys] containsObject:[NSString stringWithUTF8String:name]] && [super isKeyExcludedFromWebScript:name];
}

- (Package *) initWithIterator:(pkgCache::PkgIterator)iterator database:(Database *)database {
    if ((self = [super init]) != nil) {
        iterator_ = iterator;
        database_ = database;

        version_ = [database_ policy]->GetCandidateVer(iterator_);
        NSString *latest = version_.end() ? nil : [NSString stringWithUTF8String:version_.VerStr()];
        latest_ = latest == nil ? nil : [StripVersion(latest) retain];

        pkgCache::VerIterator current = iterator_.CurrentVer();
        NSString *installed = current.end() ? nil : [NSString stringWithUTF8String:current.VerStr()];
        installed_ = [StripVersion(installed) retain];

        if (!version_.end())
            file_ = version_.FileList();
        else {
            pkgCache &cache([database_ cache]);
            file_ = pkgCache::VerFileIterator(cache, cache.VerFileP);
        }

        id_ = [[NSString stringWithUTF8String:iterator_.Name()] retain];

        if (!file_.end()) {
            pkgRecords::Parser *parser = &[database_ records]->Lookup(file_);

            const char *begin, *end;
            parser->GetRec(begin, end);

            NSString *website(nil);
            NSString *sponsor(nil);
            NSString *author(nil);
            NSString *tag(nil);

            struct {
                const char *name_;
                NSString **value_;
            } names[] = {
                {"name", &name_},
                {"icon", &icon_},
                {"depiction", &depiction_},
                {"homepage", &homepage_},
                {"website", &website},
                {"sponsor", &sponsor},
                {"author", &author},
                {"tag", &tag},
            };

            while (begin != end)
                if (*begin == '\n') {
                    ++begin;
                    continue;
                } else if (isblank(*begin)) next: {
                    begin = static_cast<char *>(memchr(begin + 1, '\n', end - begin - 1));
                    if (begin == NULL)
                        break;
                } else if (const char *colon = static_cast<char *>(memchr(begin, ':', end - begin))) {
                    const char *name(begin);
                    size_t size(colon - begin);

                    begin = static_cast<char *>(memchr(begin, '\n', end - begin));

                    {
                        const char *stop(begin == NULL ? end : begin);
                        while (stop[-1] == '\r')
                            --stop;
                        while (++colon != stop && isblank(*colon));

                        for (size_t i(0); i != sizeof(names) / sizeof(names[0]); ++i)
                            if (strncasecmp(names[i].name_, name, size) == 0) {
                                NSString *value([NSString stringWithUTF8Bytes:colon length:(stop - colon)]);
                                *names[i].value_ = value;
                                break;
                            }
                    }

                    if (begin == NULL)
                        break;
                    ++begin;
                } else goto next;

            if (name_ != nil)
                name_ = [name_ retain];
            tagline_ = [[NSString stringWithUTF8String:parser->ShortDesc().c_str()] retain];
            if (icon_ != nil)
                icon_ = [icon_ retain];
            if (depiction_ != nil)
                depiction_ = [depiction_ retain];
            if (homepage_ == nil)
                homepage_ = website;
            if ([homepage_ isEqualToString:depiction_])
                homepage_ = nil;
            if (homepage_ != nil)
                homepage_ = [homepage_ retain];
            if (sponsor != nil)
                sponsor_ = [[Address addressWithString:sponsor] retain];
            if (author != nil)
                author_ = [[Address addressWithString:author] retain];
            if (tag != nil)
                tags_ = [[tag componentsSeparatedByString:@", "] retain];
        }

        if (tags_ != nil)
            for (int i(0), e([tags_ count]); i != e; ++i) {
                NSString *tag = [tags_ objectAtIndex:i];
                if ([tag hasPrefix:@"role::"]) {
                    role_ = [[tag substringFromIndex:6] retain];
                    break;
                }
            }

        NSString *solid(latest == nil ? installed : latest);
        bool changed(false);

        NSString *key([id_ lowercaseString]);

        NSMutableDictionary *metadata = [Packages_ objectForKey:key];
        if (metadata == nil) {
            metadata = [[NSMutableDictionary dictionaryWithObjectsAndKeys:
                now_, @"FirstSeen",
            nil] mutableCopy];

            if (solid != nil)
                [metadata setObject:solid forKey:@"LastVersion"];
            changed = true;
        } else {
            NSDate *first([metadata objectForKey:@"FirstSeen"]);
            NSDate *last([metadata objectForKey:@"LastSeen"]);
            NSString *version([metadata objectForKey:@"LastVersion"]);

            if (first == nil) {
                first = last == nil ? now_ : last;
                [metadata setObject:first forKey:@"FirstSeen"];
                changed = true;
            }

            if (solid != nil)
                if (version == nil) {
                    [metadata setObject:solid forKey:@"LastVersion"];
                    changed = true;
                } else if (![version isEqualToString:solid]) {
                    [metadata setObject:solid forKey:@"LastVersion"];
                    last = now_;
                    [metadata setObject:last forKey:@"LastSeen"];
                    changed = true;
                }
        }

        if (changed) {
            [Packages_ setObject:metadata forKey:key];
            Changed_ = true;
        }
    } return self;
}

+ (Package *) packageWithIterator:(pkgCache::PkgIterator)iterator database:(Database *)database {
    return [[[Package alloc]
        initWithIterator:iterator 
        database:database
    ] autorelease];
}

- (pkgCache::PkgIterator) iterator {
    return iterator_;
}

- (NSString *) section {
    if (section_ != nil)
        return section_;

    const char *section = iterator_.Section();
    if (section == NULL)
        return nil;

    NSString *name = [[NSString stringWithUTF8String:section] stringByReplacingCharacter:' ' withCharacter:'_'];

  lookup:
    if (NSDictionary *value = [SectionMap_ objectForKey:name])
        if (NSString *rename = [value objectForKey:@"Rename"]) {
            name = rename;
            goto lookup;
        }

    section_ = [[name stringByReplacingCharacter:'_' withCharacter:' '] retain];
    return section_;
}

- (NSString *) simpleSection {
    if (NSString *section = [self section])
        return Simplify(section);
    else
        return nil;
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

- (NSString *) description {
    if (file_.end())
        return nil;
    pkgRecords::Parser *parser = &[database_ records]->Lookup(file_);
    NSString *description([NSString stringWithUTF8String:parser->LongDesc().c_str()]);

    NSArray *lines = [description componentsSeparatedByString:@"\n"];
    NSMutableArray *trimmed = [NSMutableArray arrayWithCapacity:([lines count] - 1)];
    if ([lines count] < 2)
        return nil;

    NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];
    for (size_t i(1); i != [lines count]; ++i) {
        NSString *trim = [[lines objectAtIndex:i] stringByTrimmingCharactersInSet:whitespace];
        [trimmed addObject:trim];
    }

    return [trimmed componentsJoinedByString:@"\n"];
}

- (NSString *) index {
    NSString *index = [[[self name] substringToIndex:1] uppercaseString];
    return [index length] != 0 && isalpha([index characterAtIndex:0]) ? index : @"123";
}

- (NSMutableDictionary *) metadata {
    return [Packages_ objectForKey:[id_ lowercaseString]];
}

- (NSDate *) seen {
    NSDictionary *metadata([self metadata]);
    if ([self subscribed])
        if (NSDate *last = [metadata objectForKey:@"LastSeen"])
            return last;
    return [metadata objectForKey:@"FirstSeen"];
}

- (BOOL) subscribed {
    NSDictionary *metadata([self metadata]);
    if (NSNumber *subscribed = [metadata objectForKey:@"IsSubscribed"])
        return [subscribed boolValue];
    else
        return false;
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
    pkgCache::VerIterator current = iterator_.CurrentVer();

    bool value;
    if (current.end())
        value = essential && [self essential];
    else
        value = !version_.end() && version_ != current;// && (!essential || ![database_ cache][iterator_].Keep());
    return value;
}

- (BOOL) essential {
    return (iterator_->Flags & pkgCache::Flag::Essential) == 0 ? NO : YES;
}

- (BOOL) broken {
    return [database_ cache][iterator_].InstBroken();
}

- (BOOL) unfiltered {
    NSString *section = [self section];
    return section == nil || isSectionVisible(section);
}

- (BOOL) visible {
    return [self hasSupportingRole] && [self unfiltered];
}

- (BOOL) half {
    unsigned char current = iterator_->CurrentState;
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
                return @"Purge";
            else
                return @"Remove";
        case pkgDepCache::ModeKeep:
            if ((state.iFlags & pkgDepCache::AutoKept) != 0)
                return nil;
            else
                return nil;
        case pkgDepCache::ModeInstall:
            if ((state.iFlags & pkgDepCache::ReInstall) != 0)
                return @"Reinstall";
            else switch (state.Status) {
                case -1:
                    return @"Downgrade";
                case 0:
                    return @"Install";
                case 1:
                    return @"Upgrade";
                case 2:
                    return @"New Install";
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
    return name_ == nil ? id_ : name_;
}

- (NSString *) tagline {
    return tagline_;
}

- (UIImage *) icon {
    NSString *section = [self simpleSection];

    UIImage *icon(nil);
    if (icon_ != nil)
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
    return sponsor_;
}

- (Address *) author {
    return author_;
}

- (NSArray *) files {
    NSString *path = [NSString stringWithFormat:@"/var/lib/dpkg/info/%@.list", id_];
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
        [warnings addObject:@"illegal package identifier"];
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
            [warnings addObject:@"files installed into Cydia.app"];
        if (_private)
            [warnings addObject:@"files installed with /private/*"];
        if (stash)
            [warnings addObject:@"files installed to /var/stash"];
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
        source_ = file_.end() ? nil : [[database_ getSource:file_.File()] retain];
        cached_ = true;
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

    range = [[self id] rangeOfString:text options:NSCaseInsensitiveSearch];
    if (range.location != NSNotFound)
        return YES;

    range = [[self name] rangeOfString:text options:NSCaseInsensitiveSearch];
    if (range.location != NSNotFound)
        return YES;

    range = [[self tagline] rangeOfString:text options:NSCaseInsensitiveSearch];
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

- (NSComparisonResult) compareByName:(Package *)package {
    NSString *lhs = [self name];
    NSString *rhs = [package name];

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

- (NSComparisonResult) compareBySection:(Package *)package {
    NSString *lhs = [self section];
    NSString *rhs = [package section];

    if (lhs == NULL && rhs != NULL)
        return NSOrderedAscending;
    else if (lhs != NULL && rhs == NULL)
        return NSOrderedDescending;
    else if (lhs != NULL && rhs != NULL) {
        NSComparisonResult result([lhs compare:rhs options:LaxCompareOptions_]);
        return result != NSOrderedSame ? result : [lhs compare:rhs options:ForcedCompareOptions_];
    }

    return NSOrderedSame;
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

- (NSNumber *) isUnfilteredAndSearchedForBy:(NSString *)search {
    return [NSNumber numberWithBool:(
        [self unfiltered] && [self matches:search]
    )];
}

- (NSNumber *) isInstalledAndVisible:(NSNumber *)number {
    return [NSNumber numberWithBool:(
        (![number boolValue] || [self visible]) && [self installed] != nil
    )];
}

- (NSNumber *) isVisiblyUninstalledInSection:(NSString *)name {
    NSString *section = [self section];

    return [NSNumber numberWithBool:(
        [self visible] &&
        [self installed] == nil && (
            name == nil ||
            section == nil && [name length] == 0 ||
            [name isEqualToString:section]
        )
    )];
}

- (NSNumber *) isVisibleInSource:(Source *)source {
    return [NSNumber numberWithBool:([self source] == source && [self visible])];
}

@end
/* }}} */
/* Section Class {{{ */
@interface Section : NSObject {
    NSString *name_;
    size_t row_;
    size_t count_;
}

- (NSComparisonResult) compareByName:(Section *)section;
- (Section *) initWithName:(NSString *)name;
- (Section *) initWithName:(NSString *)name row:(size_t)row;
- (NSString *) name;
- (size_t) row;
- (size_t) count;
- (void) addToCount;

@end

@implementation Section

- (void) dealloc {
    [name_ release];
    [super dealloc];
}

- (NSComparisonResult) compareByName:(Section *)section {
    NSString *lhs = [self name];
    NSString *rhs = [section name];

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

- (Section *) initWithName:(NSString *)name {
    return [self initWithName:name row:0];
}

- (Section *) initWithName:(NSString *)name row:(size_t)row {
    if ((self = [super init]) != nil) {
        name_ = [name retain];
        row_ = row;
    } return self;
}

- (NSString *) name {
    return name_;
}

- (size_t) row {
    return row_;
}

- (size_t) count {
    return count_;
}

- (void) addToCount {
    ++count_;
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

- (void) dealloc {
    _assert(false);
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
    return iterator.end() ? nil : [Package packageWithIterator:iterator database:self];
}

- (Database *) init {
    if ((self = [super init]) != nil) {
        policy_ = NULL;
        records_ = NULL;
        resolver_ = NULL;
        fetcher_ = NULL;
        lock_ = NULL;

        sources_ = [[NSMutableDictionary dictionaryWithCapacity:16] retain];
        packages_ = [[NSMutableArray arrayWithCapacity:16] retain];

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
    return [sources_ allValues];
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

- (void) reloadData {
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

    [sources_ removeAllObjects];
    for (pkgSourceList::const_iterator source = list_->begin(); source != list_->end(); ++source) {
        std::vector<pkgIndexFile *> *indices = (*source)->GetIndexFiles();
        for (std::vector<pkgIndexFile *>::const_iterator index = indices->begin(); index != indices->end(); ++index)
            [sources_
                setObject:[[[Source alloc] initWithMetaIndex:*source] autorelease]
                forKey:[NSNumber numberWithLong:reinterpret_cast<uintptr_t>(*index)]
            ];
    }

    [packages_ removeAllObjects];
    _trace();
    profile_ = 0;
    for (pkgCache::PkgIterator iterator = cache_->PkgBegin(); !iterator.end(); ++iterator)
        if (Package *package = [Package packageWithIterator:iterator database:self])
            [packages_ addObject:package];
    _trace();
    [packages_ sortUsingSelector:@selector(compareByName:)];
    _trace();
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

- (Source *) getSource:(const pkgCache::PkgFileIterator &)file {
    pkgIndexFile *index(NULL);
    list_->FindIndex(file, index);
    return [sources_ objectForKey:[NSNumber numberWithLong:reinterpret_cast<uintptr_t>(index)]];
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
NSArray *buttons = [NSArray arrayWithObjects:@"OK", nil];
UIActionSheet *mailAlertSheet = [[UIActionSheet alloc] initWithTitle:@"Error" buttons:buttons defaultButtonIndex:0 delegate:self context:self];
[mailAlertSheet setBodyText:[controller error]];
[mailAlertSheet popupAlertAnimated:YES];
}
}

- (void) showError {
    NSLog(@"%@", [controller_ error]);
    NSArray *buttons = [NSArray arrayWithObjects:@"OK", nil];
    UIActionSheet *mailAlertSheet = [[UIActionSheet alloc] initWithTitle:@"Error" buttons:buttons defaultButtonIndex:0 delegate:self context:self];
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
    [window setValue:changes_ forKey:@"changes"];
    [window setValue:issues_ forKey:@"issues"];
    [window setValue:sizes_ forKey:@"sizes"];
    [super webView:sender didClearWindowObject:window forFrame:frame];
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
        for (size_t i(0), e = [packages count]; i != e; ++i) {
            Package *package = [packages objectAtIndex:i];
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
            essential_ = [[UIActionSheet alloc]
                initWithTitle:@"Removing Essentials"
                buttons:[NSArray arrayWithObjects:
                    @"Cancel Operation (Safe)",
                    @"Force Removal (Unsafe)",
                nil]
                defaultButtonIndex:0
                delegate:self
                context:@"remove"
            ];

#ifndef __OBJC2__
            [essential_ setDestructiveButton:[[essential_ buttons] objectAtIndex:0]];
#endif
            [essential_ setBodyText:@"This operation involves the removal of one or more packages that are required for the continued operation of either Cydia or iPhoneOS. If you continue, you may not be able to use Cydia to repair any damage."];
        } else {
            essential_ = [[UIActionSheet alloc]
                initWithTitle:@"Unable to Comply"
                buttons:[NSArray arrayWithObjects:@"Okay", nil]
                defaultButtonIndex:0
                delegate:self
                context:@"unable"
            ];

            [essential_ setBodyText:@"This operation requires the removal of one or more packages that are required for the continued operation of either Cydia or iPhoneOS. In order to continue and force this operation you will need to be activate the Advanced mode under to continue and force this operation you will need to be activate the Advanced mode under Settings."];
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
    return @"Confirm";
}

- (NSString *) leftButtonTitle {
    return @"Cancel";
}

- (id) _rightButtonTitle {
#if AlwaysReload || IgnoreInstall
    return @"Reload";
#else
    return issues_ == nil ? @"Confirm" : nil;
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
    size_t received_;
    NSTimeInterval last_;
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

        output_ = [[UITextView alloc] initWithFrame:CGRectMake(
            10,
            navrect.size.height + 20,
            bounds.size.width - 20,
            bounds.size.height - navsize.height - 62 - navrect.size.height
        )];

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
    [item setTitle:@"Complete"];

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
        case 0: [close_ setTitle:@"Return to Cydia"]; break;
        case 1: [close_ setTitle:@"Close Cydia (Restart)"]; break;
        case 2: [close_ setTitle:@"Restart SpringBoard"]; break;
        case 3: [close_ setTitle:@"Reload SpringBoard"]; break;
        case 4: [close_ setTitle:@"Reboot Device"]; break;
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

    received_ = 0;
    last_ = 0;//[NSDate timeIntervalSinceReferenceDate];

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
        title:@"Repairing"
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
        buttons:[NSArray arrayWithObjects:@"Okay", nil]
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
    last_ = [NSDate timeIntervalSinceReferenceDate];
}

- (void) addProgressOutput:(NSString *)output {
    [self
        performSelectorOnMainThread:@selector(_addProgressOutput:)
        withObject:output
        waitUntilDone:YES
    ];
}

- (bool) isCancelling:(size_t)received {
    if (last_ != 0) {
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (received_ != received) {
            received_ = received;
            last_ = now;
        } else if (now - last_ > 30)
            return true;
    }

    return false;
}

- (void) _setConfigurationData:(NSString *)data {
    static Pcre conffile_r("^'(.*)' '(.*)' ([01]) ([01])$");

    _assert(conffile_r(data));

    NSString *ofile = conffile_r[1];
    //NSString *nfile = conffile_r[2];

    UIActionSheet *sheet = [[[UIActionSheet alloc]
        initWithTitle:@"Configuration Upgrade"
        buttons:[NSArray arrayWithObjects:
            @"Keep My Old Copy",
            @"Accept The New Copy",
            // XXX: @"See What Changed",
        nil]
        defaultButtonIndex:0
        delegate:self
        context:@"conffile"
    ] autorelease];

    [sheet setBodyText:[NSString stringWithFormat:
        @"The following file has been changed by both the package maintainer and by you (or for you by a script).\n\n%@"
    , ofile]];

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
@interface PackageCell : UISimpleTableCell {
    UIImage *icon_;
    NSString *name_;
    NSString *description_;
    NSString *source_;
    UIImage *badge_;
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

    Source *source = [package source];
    NSString *section = [package simpleSection];

    icon_ = [[package icon] retain];

    name_ = [[package name] retain];
    description_ = [[package tagline] retain];

    NSString *label = nil;
    bool trusted = false;

    if (source != nil) {
        label = [source label];
        trusted = [source trusted];
    } else if ([[package id] isEqualToString:@"firmware"])
        label = @"Apple";
    else
        label = @"Unknown/Local";

    NSString *from = [NSString stringWithFormat:@"from %@", label];

    if (section != nil && ![section isEqualToString:label])
        from = [from stringByAppendingString:[NSString stringWithFormat:@" (%@)", section]];

    source_ = [from retain];

    if (NSString *purpose = [package primaryPurpose])
        if ((badge_ = [UIImage imageAtPath:[NSString stringWithFormat:@"%@/Purposes/%@.png", App_, purpose]]) != nil)
            badge_ = [badge_ retain];

#ifdef USE_BADGES
    if (NSString *mode = [package mode]) {
        [badge_ setImage:[UIImage applicationImageNamed:
            [mode isEqualToString:@"Remove"] || [mode isEqualToString:@"Purge"] ? @"removing.png" : @"installing.png"
        ]];

        [status_ setText:[NSString stringWithFormat:@"Queued for %@", mode]];
        [status_ setColor:[UIColor colorWithCGColor:Blueish_]];
    } else if ([package half]) {
        [badge_ setImage:[UIImage applicationImageNamed:@"damaged.png"]];
        [status_ setText:@"Package Damaged"];
        [status_ setColor:[UIColor redColor]];
    } else {
        [badge_ setImage:nil];
        [status_ setText:nil];
    }
#endif
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
        UISetColor(Black_);
    [name_ drawAtPoint:CGPointMake(48, 8) forWidth:240 withFont:Font18Bold_ ellipsis:2];
    [source_ drawAtPoint:CGPointMake(58, 29) forWidth:225 withFont:Font12_ ellipsis:2];

    if (!selected)
        UISetColor(Gray_);
    [description_ drawAtPoint:CGPointMake(12, 46) forWidth:280 withFont:Font14_ ellipsis:2];

    [super drawContentInRect:rect selected:selected];
}

+ (int) heightForPackage:(Package *)package {
    NSString *tagline([package tagline]);
    int height = tagline == nil || [tagline length] == 0 ? -17 : 0;
#ifdef USE_BADGES
    if ([package hasMode] || [package half])
        return height + 96;
    else
#endif
        return height + 73;
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
        name_ = [@"All Packages" retain];
        count_ = nil;
    } else {
        section_ = [section name];
        if (section_ != nil)
            section_ = [section_ retain];
        name_  = [(section_ == nil ? @"(No Section)" : section_) retain];
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
            initWithTitle:@"Name"
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
    return @"Installed Files";
}

- (NSString *) backButtonTitle {
    return @"Files";
}

@end
/* }}} */
/* Package View {{{ */
@interface PackageView : BrowserView {
    _transient Database *database_;
    Package *package_;
    NSString *name_;
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

- (void) _clickButtonWithName:(NSString *)name {
    if ([name isEqualToString:@"Install"])
        [delegate_ installPackage:package_];
    else if ([name isEqualToString:@"Reinstall"])
        [delegate_ installPackage:package_];
    else if ([name isEqualToString:@"Remove"])
        [delegate_ removePackage:package_];
    else if ([name isEqualToString:@"Upgrade"])
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
    [window setValue:package_ forKey:@"package"];
    [super webView:sender didClearWindowObject:window forFrame:frame];
}

#if !AlwaysReload
- (void) _rightButtonClicked {
    /*[super _rightButtonClicked];
    return;*/

    int count = [buttons_ count];
    _assert(count != 0);

    if (count == 1)
        [self _clickButtonWithName:[buttons_ objectAtIndex:0]];
    else {
        NSMutableArray *buttons = [NSMutableArray arrayWithCapacity:(count + 1)];
        [buttons addObjectsFromArray:buttons_];
        [buttons addObject:@"Cancel"];

        [delegate_ slideUp:[[[UIActionSheet alloc]
            initWithTitle:nil
            buttons:buttons
            defaultButtonIndex:2
            delegate:self
            context:@"modify"
        ] autorelease]];
    }
}
#endif

- (id) _rightButtonTitle {
    int count = [buttons_ count];
    return count == 0 ? nil : count != 1 ? @"Modify" : [buttons_ objectAtIndex:0];
}

- (NSString *) backButtonTitle {
    return @"Details";
}

- (id) initWithBook:(RVBook *)book database:(Database *)database {
    if ((self = [super initWithBook:book]) != nil) {
        database_ = database;
        buttons_ = [[NSMutableArray alloc] initWithCapacity:4];
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
        package_ = [package retain];
        name_ = [[package id] retain];

        [self loadURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"package" ofType:@"html"]]];

        if ([package_ source] == nil);
        else if ([package_ upgradableAndEssential:NO])
            [buttons_ addObject:@"Upgrade"];
        else if ([package_ installed] == nil)
            [buttons_ addObject:@"Install"];
        else
            [buttons_ addObject:@"Reinstall"];
        if ([package_ installed] != nil)
            [buttons_ addObject:@"Remove"];
    }
}

- (bool) _loading {
    return false;
}

- (void) reloadData {
    [self setPackage:[database_ packageWithName:name_]];
    [self reloadButtons];
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
    PackageView *view = [[[PackageView alloc] initWithBook:book_ database:database_] autorelease];
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
            initWithTitle:@"Name"
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

    for (size_t i(0); i != [packages count]; ++i) {
        Package *package([packages objectAtIndex:i]);
        if ([self hasPackage:package])
            [packages_ addObject:package];
    }

    Section *section = nil;

    for (size_t offset(0); offset != [packages_ count]; ++offset) {
        Package *package = [packages_ objectAtIndex:offset];
        NSString *name = [package index];

        if (section == nil || ![[section name] isEqualToString:name]) {
            section = [[[Section alloc] initWithName:name row:offset] autorelease];
            [sections_ addObject:section];
        }

        [section addToCount];
    }

    [list_ reloadData];
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
    return [package valid] && [[package performSelector:filter_ withObject:object_] boolValue];
}

- (id) initWithBook:(RVBook *)book database:(Database *)database title:(NSString *)title filter:(SEL)filter with:(id)object {
    if ((self = [super initWithBook:book database:database title:title]) != nil) {
        filter_ = filter;
        object_ = object == nil ? nil : [object retain];

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
        case 0: return @"Entered by User";
        case 1: return @"Installed by Packages";

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
        [delegate_ setStatusBarShowsProgress:NO];

        [hud_ show:NO];
        [hud_ removeFromSuperview];
        [hud_ autorelease];
        hud_ = nil;

        if (trivial_) {
            [Sources_ setObject:[NSDictionary dictionaryWithObjectsAndKeys:
                @"deb", @"Type",
                href_, @"URI",
                @"./", @"Distribution",
            nil] forKey:[NSString stringWithFormat:@"deb:%@:./", href_]];

            [delegate_ syncData];
        } else if (error_ != nil) {
            UIActionSheet *sheet = [[[UIActionSheet alloc]
                initWithTitle:@"Verification Error"
                buttons:[NSArray arrayWithObjects:@"OK", nil]
                defaultButtonIndex:0
                delegate:self
                context:@"urlerror"
            ] autorelease];

            [sheet setBodyText:[error_ localizedDescription]];
            [sheet popupAlertAnimated:YES];
        } else {
            UIActionSheet *sheet = [[[UIActionSheet alloc]
                initWithTitle:@"Did not Find Repository"
                buttons:[NSArray arrayWithObjects:@"OK", nil]
                defaultButtonIndex:0
                delegate:self
                context:@"trivial"
            ] autorelease];

            [sheet setBodyText:@"The indicated repository could not be found. This could be because you are trying to add a legacy Installer repository (these are not supported). Also, this interface is only capable of working with exact repository URLs. If you host a repository and are having issues please contact the author of Cydia with any questions you have."];
            [sheet popupAlertAnimated:YES];
        }

        [href_ release];
        href_ = nil;

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

                hud_ = [delegate_ addProgressHUD];
                [hud_ setText:@"Verifying URL"];
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
            initWithTitle:@"Name"
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
        initWithTitle:@"Enter Cydia/APT URL"
        buttons:[NSArray arrayWithObjects:@"Add Source", @"Cancel", nil]
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
    return @"Sources";
}

- (NSString *) leftButtonTitle {
    return [[list_ table] isRowDeletionEnabled] ? @"Add" : nil;
}

- (id) rightButtonTitle {
    return [[list_ table] isRowDeletionEnabled] ? @"Done" : @"Edit";
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
    return @"Installed";
}

- (NSString *) backButtonTitle {
    return @"Packages";
}

- (id) rightButtonTitle {
    return Role_ != nil && [Role_ isEqualToString:@"Developer"] ? nil : expert_ ? @"Expert" : @"Simple";
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
        initWithTitle:@"About Cydia Installer"
        buttons:[NSArray arrayWithObjects:@"Close", nil]
        defaultButtonIndex:0
        delegate:self
        context:@"about"
    ] autorelease];

    [sheet setBodyText:
        @"Copyright (C) 2008\n"
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
    return @"About";
}

@end
/* }}} */
/* Manage View {{{ */
@interface ManageView : BrowserView {
}

@end

@implementation ManageView

- (NSString *) title {
    return @"Manage";
}

- (void) _leftButtonClicked {
    [delegate_ askForSettings];
}

- (NSString *) leftButtonTitle {
    return @"Settings";
}

#if !AlwaysReload
- (id) _rightButtonTitle {
    return nil;
}
#endif

- (bool) _loading {
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
    size_t received_;
    NSTimeInterval last_;
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
    return Simplify([super getTitleForPage:page]);
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
    [prompt_ setText:@"Updating Database"];
    [progress_ setProgress:0];

    received_ = 0;
    last_ = [NSDate timeIntervalSinceReferenceDate];
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

        cancel_ = [[UINavigationButton alloc] initWithTitle:@"Cancel" style:UINavigationButtonStyleHighlighted];
        [cancel_ addTarget:self action:@selector(_onCancel) forControlEvents:UIControlEventTouchUpInside];

        CGRect frame = [cancel_ frame];
        frame.size.width = 65;
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
    [prompt_ setText:[NSString stringWithFormat:@"Error: %@", error]];
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
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (received_ != received) {
        received_ = received;
        last_ = now;
    } else if (now - last_ > 15)
        return true;
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
        title = @"All Packages";
    } else {
        section = [filtered_ objectAtIndex:(row - 1)];
        name = [section name];

        if (name != nil)
            title = name;
        else {
            name = @"";
            title = @"(No Section)";
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
            initWithTitle:@"Name"
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

    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:[packages count]];
    NSMutableDictionary *sections = [NSMutableDictionary dictionaryWithCapacity:32];

    _trace();
    for (size_t i(0); i != [packages count]; ++i) {
        Package *package([packages objectAtIndex:i]);
        NSString *name([package section]);

        if (name != nil) {
            Section *section([sections objectForKey:name]);
            if (section == nil) {
                section = [[[Section alloc] initWithName:name] autorelease];
                [sections setObject:section forKey:name];
            }
        }

        if ([package valid] && [package installed] == nil && [package visible])
            [filtered addObject:package];
    }
    _trace();

    [sections_ addObjectsFromArray:[sections allValues]];
    [sections_ sortUsingSelector:@selector(compareByName:)];

    _trace();
    [filtered sortUsingSelector:@selector(compareBySection:)];
    _trace();

    Section *section = nil;
    for (size_t offset = 0, count = [filtered count]; offset != count; ++offset) {
        Package *package = [filtered objectAtIndex:offset];
        NSString *name = [package section];

        if (section == nil || name != nil && ![[section name] isEqualToString:name]) {
            section = name == nil ?
                [[[Section alloc] initWithName:nil] autorelease] :
                [sections objectForKey:name];
            [filtered_ addObject:section];
        }

        [section addToCount];
    }
    _trace();

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
    return editing_ ? @"Section Visibility" : @"Install by Section";
}

- (NSString *) backButtonTitle {
    return @"Sections";
}

- (id) rightButtonTitle {
    return [sections_ count] == 0 ? nil : editing_ ? @"Done" : @"Edit";
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
    PackageView *view = [[[PackageView alloc] initWithBook:book_ database:database_] autorelease];
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
            initWithTitle:@"Name"
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
    for (size_t i(0); i != [packages count]; ++i) {
        Package *package([packages objectAtIndex:i]);

        if (
            [package installed] == nil && [package valid] && [package visible] ||
            [package upgradableAndEssential:YES]
        )
            [packages_ addObject:package];
    }

    _trace();
    [packages_ radixSortUsingSelector:@selector(compareForChanges) withObject:nil];
    _trace();

    Section *upgradable = [[[Section alloc] initWithName:@"Available Upgrades"] autorelease];
    Section *ignored = [[[Section alloc] initWithName:@"Ignored Upgrades"] autorelease];
    Section *section = nil;
    NSDate *last = nil;

    upgrades_ = 0;
    bool unseens = false;

    CFDateFormatterRef formatter = CFDateFormatterCreate(NULL, Locale_, kCFDateFormatterMediumStyle, kCFDateFormatterMediumStyle);

    _trace();
    for (size_t offset = 0, count = [packages_ count]; offset != count; ++offset) {
        Package *package = [packages_ objectAtIndex:offset];

        if (![package upgradableAndEssential:YES]) {
            unseens = true;
            NSDate *seen = [package seen];

            if (section == nil || last != seen && (seen == nil || [seen compare:last] != NSOrderedSame)) {
                last = seen;

                NSString *name(seen == nil ? [@"n/a ?" retain] : (NSString *) CFDateFormatterCreateStringWithDate(NULL, formatter, (CFDateRef) seen));
                section = [[[Section alloc] initWithName:name row:offset] autorelease];
                [sections_ addObject:section];
                [name release];
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
    return [(CYBook *)book_ updating] ? nil : @"Refresh";
}

- (id) rightButtonTitle {
    return upgrades_ == 0 ? nil : [NSString stringWithFormat:@"Upgrade (%u)", upgrades_];
}

- (NSString *) title {
    return @"Changes";
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
        case 0: return @"Advanced Search (Coming Soon!)";

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

        [field_ setPlaceholder:@"Package Names & Descriptions"];
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
    [table_ reloadData];
    [table_ resetCursor];
}

- (UIView *) accessoryView {
    return accessory_;
}

- (NSString *) title {
    return nil;
}

- (NSString *) backButtonTitle {
    return @"Search";
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
                [cell setTitle:@"Changes only shows upgrades to installed packages so as to minimize spam from packagers. Activate this to see upgrades to this package even when it is not installed."];
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
        [subscribedCell_ setTitle:@"Show All Changes"];
        [subscribedCell_ setControl:subscribedSwitch_];

        ignoredCell_ = [[UIPreferencesControlTableCell alloc] init];
        [ignoredCell_ setShowSelection:NO];
        [ignoredCell_ setTitle:@"Ignore Upgrades"];
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
    return @"Settings";
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
}

@end

@implementation Cydia

- (void) _loaded {
    if ([broken_ count] != 0) {
        int count = [broken_ count];

        UIActionSheet *sheet = [[[UIActionSheet alloc]
            initWithTitle:[NSString stringWithFormat:@"%d Half-Installed Package%@", count, (count == 1 ? @"" : @"s")]
            buttons:[NSArray arrayWithObjects:
                @"Forcibly Clear",
                @"Ignore (Temporary)",
            nil]
            defaultButtonIndex:0
            delegate:self
            context:@"fixhalf"
        ] autorelease];

        [sheet setBodyText:@"When the shell scripts associated with packages fail, they are left in a bad state known as either half-configured or half-installed. These errors don't go away and instead continue to cause issues. These scripts can be deleted and the packages forcibly removed."];
        [sheet popupAlertAnimated:YES];
    } else if (!Ignored_ && [essential_ count] != 0) {
        int count = [essential_ count];

        UIActionSheet *sheet = [[[UIActionSheet alloc]
            initWithTitle:[NSString stringWithFormat:@"%d Essential Upgrade%@", count, (count == 1 ? @"" : @"s")]
            buttons:[NSArray arrayWithObjects:
                @"Upgrade Essential",
                @"Complete Upgrade",
                @"Ignore (Temporary)",
            nil]
            defaultButtonIndex:0
            delegate:self
            context:@"upgrade"
        ] autorelease];

        [sheet setBodyText:@"One or more essential packages are currently out of date. If these upgrades are not performed you are likely to encounter errors."];
        [sheet popupAlertAnimated:YES];
    }
}

- (void) _reloadData {
    /*UIProgressHUD *hud = [[UIProgressHUD alloc] initWithWindow:window_];
    [hud setText:@"Reloading Data"];
    [overlay_ addSubview:hud];
    [hud show:YES];*/

    [database_ reloadData];

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
            [buttonbar_ setBadgeAnimated:YES forButton:3];
        [self setApplicationBadge:badge];
    } else {
        [buttonbar_ setBadgeValue:nil forButton:3];
        if ([buttonbar_ respondsToSelector:@selector(setBadgeAnimated:forButton:)])
            [buttonbar_ setBadgeAnimated:NO forButton:3];
        [self removeApplicationBadge];
    }

    [self updateData];

    // XXX: what is this line of code for?
    if ([packages count] == 0);
    else if (Loaded_) loaded:
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

    /*[hud show:NO];
    [hud removeFromSuperview];*/
}

- (void) _saveConfig {
    if (Changed_) {
        _trace();
        _assert([Metadata_ writeToFile:@"/var/lib/cydia/metadata.plist" atomically:YES] == YES);
        _trace();
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

    for (int i(0), e([keys count]); i != e; ++i) {
        NSString *key = [keys objectAtIndex:i];
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
        title:@"Updating Sources"
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
        title:@"Running"
    ];
}

- (void) bootstrap_ {
    [database_ update];
    [database_ upgrade];
    [database_ prepare];
    [database_ perform];
}

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

    [self cancel];
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

- (void) buttonBarItemTapped:(id)sender {
    unsigned tag = [sender tag];
    if (tag == tag_) {
        [book_ resetViewAnimated:YES];
        return;
    } else if (tag_ == 2 && tag != 2)
        [sections_ resetView];

    switch (tag) {
        case 1: [self _setHomePage]; break;

        case 2: [self setPage:sections_]; break;
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
    UIActionSheet *role = [[[UIActionSheet alloc]
        initWithTitle:@"Who Are You?"
        buttons:[NSArray arrayWithObjects:
            @"User (Graphical Only)",
            @"Hacker (+ Command Line)",
            @"Developer (No Filters)",
        nil]
        defaultButtonIndex:-1
        delegate:self
        context:@"role"
    ] autorelease];

    [role setBodyText:@"Not all of the packages available via Cydia are designed to be used by all users. Please categorize yourself so that Cydia can apply helpful filters.\n\nThis choice can be changed from \"Settings\" under the \"Manage\" tab."];
    [role popupAlertAnimated:YES];
}

- (void) finish {
    if (hud_ != nil) {
        [self setStatusBarShowsProgress:NO];

        [hud_ show:NO];
        [hud_ removeFromSuperview];
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
            @"Home", kUIButtonBarButtonTitle,
            @"0", kUIButtonBarButtonType,
        nil],

        [NSDictionary dictionaryWithObjectsAndKeys:
            @"buttonBarItemTapped:", kUIButtonBarButtonAction,
            @"install-up.png", kUIButtonBarButtonInfo,
            @"install-dn.png", kUIButtonBarButtonSelectedInfo,
            [NSNumber numberWithInt:2], kUIButtonBarButtonTag,
            self, kUIButtonBarButtonTarget,
            @"Sections", kUIButtonBarButtonTitle,
            @"0", kUIButtonBarButtonType,
        nil],

        [NSDictionary dictionaryWithObjectsAndKeys:
            @"buttonBarItemTapped:", kUIButtonBarButtonAction,
            @"changes-up.png", kUIButtonBarButtonInfo,
            @"changes-dn.png", kUIButtonBarButtonSelectedInfo,
            [NSNumber numberWithInt:3], kUIButtonBarButtonTag,
            self, kUIButtonBarButtonTarget,
            @"Changes", kUIButtonBarButtonTitle,
            @"0", kUIButtonBarButtonType,
        nil],

        [NSDictionary dictionaryWithObjectsAndKeys:
            @"buttonBarItemTapped:", kUIButtonBarButtonAction,
            @"manage-up.png", kUIButtonBarButtonInfo,
            @"manage-dn.png", kUIButtonBarButtonSelectedInfo,
            [NSNumber numberWithInt:4], kUIButtonBarButtonTag,
            self, kUIButtonBarButtonTarget,
            @"Manage", kUIButtonBarButtonTitle,
            @"0", kUIButtonBarButtonType,
        nil],

        [NSDictionary dictionaryWithObjectsAndKeys:
            @"buttonBarItemTapped:", kUIButtonBarButtonAction,
            @"search-up.png", kUIButtonBarButtonInfo,
            @"search-dn.png", kUIButtonBarButtonSelectedInfo,
            [NSNumber numberWithInt:5], kUIButtonBarButtonTag,
            self, kUIButtonBarButtonTarget,
            @"Search", kUIButtonBarButtonTitle,
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

    sections_ = [[SectionsView alloc] initWithBook:book_ database:database_];
    changes_ = [[ChangesView alloc] initWithBook:book_ database:database_];
    search_ = [[SearchView alloc] initWithBook:book_ database:database_];

    manage_ = (ManageView *) [[self
        _pageForURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"manage" ofType:@"html"]]
        withClass:[ManageView class]
    ] retain];

    if (bootstrap_)
        [self bootstrap];
    else
        [self _setHomePage];
}

- (void) alertSheet:(UIActionSheet *)sheet buttonClicked:(int)button {
    NSString *context([sheet context]);

    if ([context isEqualToString:@"missing"])
        [sheet dismiss];
    else if ([context isEqualToString:@"fixhalf"]) {
        switch (button) {
            case 1:
                @synchronized (self) {
                    for (int i = 0, e = [broken_ count]; i != e; ++i) {
                        Package *broken = [broken_ objectAtIndex:i];
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
                    for (int i = 0, e = [essential_ count]; i != e; ++i) {
                        Package *essential = [essential_ objectAtIndex:i];
                        [essential install];
                    }

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
    UIProgressHUD *hud = [[UIProgressHUD alloc] initWithWindow:window_];
    [hud show:YES];
    [underlay_ addSubview:hud];
    return hud;
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
        PackageView *view = [[[PackageView alloc] initWithBook:book_ database:database_] autorelease];
        [view setPackage:package];
        return view;
    } else {
        UIActionSheet *sheet = [[[UIActionSheet alloc]
            initWithTitle:@"Cannot Locate Package"
            buttons:[NSArray arrayWithObjects:@"Close", nil]
            defaultButtonIndex:0
            delegate:self
            context:@"missing"
        ] autorelease];

        [sheet setBodyText:[NSString stringWithFormat:
            @"The package %@ cannot be found in your current sources. I might recommend installing more sources."
        , name]];

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
    Font12_ = [[UIFont systemFontOfSize:12] retain];
    Font12Bold_ = [[UIFont boldSystemFontOfSize:12] retain];
    Font14_ = [[UIFont systemFontOfSize:14] retain];
    Font18Bold_ = [[UIFont boldSystemFontOfSize:18] retain];
    Font22Bold_ = [[UIFont boldSystemFontOfSize:22] retain];

    _assert(pkgInitConfig(*_config));
    _assert(pkgInitSystem(*_config, _system));

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

        hud_ = [self addProgressHUD];
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

    for (size_t i(0); i != [items count]; ++i) {
        NSMutableDictionary *item([items objectAtIndex:i]);
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

int main(int argc, char *argv[]) { _pooled
    _trace();
    class_addMethod(objc_getClass("DOMNodeList"), @selector(countByEnumeratingWithState:objects:count:), (IMP) &DOMNodeList$countByEnumeratingWithState$objects$count$, "I20@0:4^{NSFastEnumerationState}8^@12I16");

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

    App_ = [[NSBundle mainBundle] bundlePath];
    Home_ = NSHomeDirectory();
    Locale_ = CFLocaleCopyCurrent();

    {
        NSString *plist = [Home_ stringByAppendingString:@"/Library/Preferences/com.apple.preferences.sounds.plist"];
        if (NSDictionary *sounds = [NSDictionary dictionaryWithContentsOfFile:plist])
            if (NSNumber *keyboard = [sounds objectForKey:@"keyboard"])
                Sounds_Keyboard_ = [keyboard boolValue];
    }

    setuid(0);
    setgid(0);

#if 1 /* XXX: this costs 1.4s of startup performance */
    if (unlink("/var/cache/apt/pkgcache.bin") == -1)
        _assert(errno == ENOENT);
    if (unlink("/var/cache/apt/srcpkgcache.bin") == -1)
        _assert(errno == ENOENT);
#endif

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

    /*AddPreferences(@"/Applications/Preferences.app/Settings-iPhone.plist");
    AddPreferences(@"/Applications/Preferences.app/Settings-iPod.plist");*/

    _trace();
    Metadata_ = [[NSMutableDictionary alloc] initWithContentsOfFile:@"/var/lib/cydia/metadata.plist"];
    _trace();

    if (Metadata_ == NULL)
        Metadata_ = [[NSMutableDictionary alloc] initWithCapacity:2];
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

    space_ = CGColorSpaceCreateDeviceRGB();

    Blue_.Set(space_, 0.2, 0.2, 1.0, 1.0);
    Blueish_.Set(space_, 0x19/255.f, 0x32/255.f, 0x50/255.f, 1.0);
    Black_.Set(space_, 0.0, 0.0, 0.0, 1.0);
    Off_.Set(space_, 0.9, 0.9, 0.9, 1.0);
    White_.Set(space_, 1.0, 1.0, 1.0, 1.0);
    Gray_.Set(space_, 0.4, 0.4, 0.4, 1.0);

    Finishes_ = [NSArray arrayWithObjects:@"return", @"reopen", @"restart", @"reload", @"reboot", nil];

    SectionMap_ = [[[NSDictionary alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Sections" ofType:@"plist"]] autorelease];

    UIApplicationUseLegacyEvents(YES);
    UIKeyboardDisableAutomaticAppearance();

    _trace();
    int value = UIApplicationMain(argc, argv, @"Cydia", @"Cydia");

    CGColorSpaceRelease(space_);
    CFRelease(Locale_);

    return value;
}
