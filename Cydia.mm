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

#ifdef __OBJC2__
    #define UITextTraits UITextInputTraits
    #define textTraits textInputTraits
    #define setAutoCapsType setAutocapitalizationType
    #define setAutoCorrectionType setAutocorrectionType
    #define setPreferredKeyboardType setKeyboardType
#endif

/* #include Directives {{{ */
#include <objc/objc.h>
#include <objc/runtime.h>

#include <CoreGraphics/CoreGraphics.h>
#include <GraphicsServices/GraphicsServices.h>
#include <Foundation/Foundation.h>
#include <UIKit/UIKit.h>
#include <WebCore/DOMHTML.h>

#import "BrowserView.h"
#import "ResetView.h"
#import "UICaboodle.h"

#include <WebKit/WebFrame.h>
#include <WebKit/WebView.h>

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
#include <apt-pkg/pkgrecords.h>
#include <apt-pkg/sourcelist.h>
#include <apt-pkg/sptr.h>

#include <sys/sysctl.h>
#include <notify.h>

extern "C" {
#include <mach-o/nlist.h>
}

#include <cstdio>
#include <cstdlib>
#include <cstring>

#include <errno.h>
#include <pcre.h>
/* }}} */

/* iPhoneOS 2.0 Compatibility {{{ */
#ifdef __OBJC2__
@interface UICGColor : NSObject {
}

- (id) initWithCGColor:(CGColorRef)color;
@end

@interface UIFont {
}

+ (id)systemFontOfSize:(float)fp8;
+ (id)boldSystemFontOfSize:(float)fp8;
- (UIFont *) fontWithSize:(CGFloat)size;
@end

@interface NSObject (iPhoneOS)
- (CGColorRef) cgColor;
- (CGColorRef) CGColor;
- (void) set;
@end

@implementation NSObject (iPhoneOS)

- (CGColorRef) cgColor {
    return [self CGColor];
}

- (CGColorRef) CGColor {
    return (CGColorRef) self;
}

- (void) set {
    [[[[objc_getClass("UICGColor") alloc] initWithCGColor:[self CGColor]] autorelease] set];
}

@end

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

@interface UIApplication (IdleTimer)
- (void) setIdleTimerDisabled:(char)arg0;
@end

#ifdef __OBJC2__
typedef enum {
    kUIProgressIndicatorStyleMediumWhite = 1,
    kUIProgressIndicatorStyleSmallWhite = 0,
    kUIProgressIndicatorStyleSmallBlack = 4
} UIProgressIndicatorStyle;
#else
typedef enum {
    kUIProgressIndicatorStyleMediumWhite = 0,
    kUIProgressIndicatorStyleSmallWhite = 2,
    kUIProgressIndicatorStyleSmallBlack = 3
} UIProgressIndicatorStyle;
#endif

typedef enum {
    kUIControlEventMouseDown = 1 << 0,
    kUIControlEventMouseMovedInside = 1 << 2, // mouse moved inside control target
    kUIControlEventMouseMovedOutside = 1 << 3, // mouse moved outside control target
    kUIControlEventMouseUpInside = 1 << 6, // mouse up inside control target
    kUIControlEventMouseUpOutside = 1 << 7, // mouse up outside control target
    kUIControlAllEvents = (kUIControlEventMouseDown | kUIControlEventMouseMovedInside | kUIControlEventMouseMovedOutside | kUIControlEventMouseUpInside | kUIControlEventMouseUpOutside)
} UIControlEventMasks;

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
    char data[length + 1];
    memcpy(data, bytes, length);
    data[length] = '\0';
    return [NSString stringWithUTF8String:data];
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
            fprintf(stderr, "%d:%s\n", offset, error);
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
    NSString *email_;
}

- (NSString *) name;
- (NSString *) email;

+ (Address *) addressWithString:(NSString *)string;
- (Address *) initWithString:(NSString *)string;
@end

@implementation Address

- (void) dealloc {
    [name_ release];
    if (email_ != nil)
        [email_ release];
    [super dealloc];
}

- (NSString *) name {
    return name_;
}

- (NSString *) email {
    return email_;
}

+ (Address *) addressWithString:(NSString *)string {
    return [[[Address alloc] initWithString:string] autorelease];
}

- (Address *) initWithString:(NSString *)string {
    if ((self = [super init]) != nil) {
        const char *data = [string UTF8String];
        size_t size = [string length];

        static Pcre email_r("^\"?(.*)\"? <([^>]*)>$");

        if (email_r(data, size)) {
            name_ = [email_r[1] retain];
            email_ = [email_r[2] retain];
        } else {
            name_ = [[NSString alloc]
                initWithBytes:data
                length:size
                encoding:kCFStringEncodingUTF8
            ];

            email_ = nil;
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

class GSFont {
  private:
    GSFontRef font_;

  public:
    ~GSFont() {
        CFRelease(font_);
    }
};
/* }}} */
/* Right Alignment {{{ */
@interface UIRightTextLabel : UITextLabel {
    float       _savedRightEdgeX;
    BOOL        _sizedtofit_flag;
}

- (void) setFrame:(CGRect)frame;
- (void) setText:(NSString *)text;
- (void) realignText;
@end

@implementation UIRightTextLabel

- (void) setFrame:(CGRect)frame {
    [super setFrame:frame];
    if (_sizedtofit_flag == NO) {
        _savedRightEdgeX = frame.origin.x;
        [self realignText];
    }
}

- (void) setText:(NSString *)text {
    [super setText:text];
    [self realignText];
}

- (void) realignText {
    CGRect oldFrame = [self frame];

    _sizedtofit_flag = YES;
    [self sizeToFit]; // shrink down size so I can right align it

    CGRect newFrame = [self frame];

    oldFrame.origin.x = _savedRightEdgeX - newFrame.size.width;
    oldFrame.size.width = newFrame.size.width;
    [super setFrame:oldFrame];
    _sizedtofit_flag = NO;
}

@end
/* }}} */

extern "C" void UISetColor(CGColorRef color);

/* Random Global Variables {{{ */
static const int PulseInterval_ = 50000;
static const int ButtonBarHeight_ = 48;
static const float KeyboardTime_ = 0.3f;
static const char * const SpringBoard_ = "/System/Library/LaunchDaemons/com.apple.SpringBoard.plist";

#ifndef Cydia_
#define Cydia_ ""
#endif

static CGColor Blue_;
static CGColor Blueish_;
static CGColor Black_;
static CGColor Clear_;
static CGColor Red_;
static CGColor White_;
static CGColor Gray_;

static NSString *Home_;
static BOOL Sounds_Keyboard_;

static BOOL Advanced_;
//static BOOL Loaded_;
static BOOL Ignored_;

static UIFont *Font12_;
static UIFont *Font12Bold_;
static UIFont *Font14_;
static UIFont *Font18Bold_;
static UIFont *Font22Bold_;

const char *Firmware_ = NULL;
const char *Machine_ = NULL;
const char *SerialNumber_ = NULL;

unsigned Major_;
unsigned Minor_;
unsigned BugFix_;

CFLocaleRef Locale_;
CGColorSpaceRef space_;

#define FW_LEAST(major, minor, bugfix) \
    (major < Major_ || major == Major_ && \
        (minor < Minor_ || minor == Minor_ && \
            bugfix <= BugFix_))

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
    unsigned power = 0;
    while (size > 1024) {
        size /= 1024;
        ++power;
    }

    static const char *powers_[] = {"B", "kB", "MB", "GB"};

    return [NSString stringWithFormat:@"%.1f%s", size, powers_[power]];
}

NSString *StripVersion(NSString *version) {
    NSRange colon = [version rangeOfString:@":"];
    if (colon.location != NSNotFound)
        version = [version substringFromIndex:(colon.location + 1)];
    return version;
}

static const float TextViewOffset_ = 22;

UITextView *GetTextView(NSString *value, float left, bool html) {
    UITextView *text([[[UITextView alloc] initWithFrame:CGRectMake(left, 3, 310 - left, 1000)] autorelease]);
    [text setEditable:NO];
    [text setTextSize:16];
    /*if (html)
        [text setHTML:value];
    else*/
        [text setText:value];
    [text setEnabled:NO];

    [text setBackgroundColor:Clear_];

    CGRect frame = [text frame];
    [text setFrame:frame];
    CGRect rect = [text visibleTextRect];
    frame.size.height = rect.size.height;
    [text setFrame:frame];

    return text;
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
- (void) addProgressOutput:(NSString *)output;
@end

@protocol ConfigurationDelegate
- (void) repairWithSelector:(SEL)selector;
- (void) setConfigurationData:(NSString *)data;
@end

@protocol CydiaDelegate
- (void) installPackage:(Package *)package;
- (void) removePackage:(Package *)package;
- (void) slideUp:(UIAlertSheet *)alert;
- (void) distUpgrade;
- (void) updateData;
- (void) syncData;
- (void) askForSettings;
- (UIProgressHUD *) addProgressHUD;
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

        [delegate_ performSelectorOnMainThread:@selector(_setProgressError:)
            withObject:[NSArray arrayWithObjects:[NSString stringWithUTF8String:item.Owner->ErrorText.c_str()], nil]
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
        return value;
    }

    virtual void Start() {
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

- (void) _readCydia:(NSNumber *)fd;
- (void) _readStatus:(NSNumber *)fd;
- (void) _readOutput:(NSNumber *)fd;

- (FILE *) input;

- (Package *) packageWithName:(NSString *)name;

- (Database *) init;
- (pkgCacheFile &) cache;
- (pkgDepCache::Policy *) policy;
- (pkgRecords *) records;
- (pkgProblemResolver *) resolver;
- (pkgAcquire &) fetcher;
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

- (void) dealloc {
    [uri_ release];
    [distribution_ release];
    [type_ release];

    if (description_ != nil)
        [description_ release];
    if (label_ != nil)
        [label_ release];
    if (origin_ != nil)
        [origin_ release];
    if (version_ != nil)
        [version_ release];
    if (defaultIcon_ != nil)
        [defaultIcon_ release];
    if (record_ != nil)
        [record_ release];

    [super dealloc];
}

- (Source *) initWithMetaIndex:(metaIndex *)index {
    if ((self = [super init]) != nil) {
        trusted_ = index->IsTrusted();

        uri_ = [[NSString stringWithUTF8String:index->GetURI().c_str()] retain];
        distribution_ = [[NSString stringWithUTF8String:index->GetDist().c_str()] retain];
        type_ = [[NSString stringWithUTF8String:index->GetType()] retain];

        description_ = nil;
        label_ = nil;
        origin_ = nil;
        version_ = nil;
        defaultIcon_ = nil;

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

    return [lhs caseInsensitiveCompare:rhs];
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
NSString *Scour(const char *field, const char *begin, const char *end) {
    size_t i(0), l(strlen(field));

    for (;;) {
        const char *name = begin + i;
        const char *colon = name + l;
        const char *value = colon + 1;

        if (
            value < end &&
            *colon == ':' &&
            memcmp(name, field, l) == 0
        ) {
            while (value != end && value[0] == ' ')
                ++value;
            const char *line = std::find(value, end, '\n');
            while (line != value && line[-1] == ' ')
                --line;

            return [NSString stringWithUTF8Bytes:value length:(line - value)];
        } else {
            begin = std::find(begin, end, '\n');
            if (begin == end)
                return nil;
            ++begin;
        }
    }
}

@interface Package : NSObject {
    pkgCache::PkgIterator iterator_;
    _transient Database *database_;
    pkgCache::VerIterator version_;
    pkgCache::VerFileIterator file_;

    Source *source_;
    bool cached_;

    NSString *latest_;
    NSString *installed_;

    NSString *id_;
    NSString *name_;
    NSString *tagline_;
    NSString *icon_;
    NSString *website_;
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
- (Address *) maintainer;
- (size_t) size;
- (NSString *) description;
- (NSString *) index;

- (NSDate *) seen;

- (NSString *) latest;
- (NSString *) installed;

- (BOOL) valid;
- (BOOL) upgradableAndEssential:(BOOL)essential;
- (BOOL) essential;
- (BOOL) broken;
- (BOOL) visible;

- (BOOL) half;
- (BOOL) halfConfigured;
- (BOOL) halfInstalled;
- (BOOL) hasMode;
- (NSString *) mode;

- (NSString *) id;
- (NSString *) name;
- (NSString *) tagline;
- (NSString *) icon;
- (NSString *) website;
- (Address *) author;

- (NSArray *) relationships;

- (Source *) source;
- (NSString *) role;

- (BOOL) matches:(NSString *)text;

- (bool) hasSupportingRole;
- (BOOL) hasTag:(NSString *)tag;

- (NSComparisonResult) compareByName:(Package *)package;
- (NSComparisonResult) compareBySection:(Package *)package;
- (NSComparisonResult) compareBySectionAndName:(Package *)package;
- (NSComparisonResult) compareForChanges:(Package *)package;

- (void) install;
- (void) remove;

- (NSNumber *) isVisiblySearchedForBy:(NSString *)search;
- (NSNumber *) isInstalledAndVisible:(NSNumber *)number;
- (NSNumber *) isVisiblyUninstalledInSection:(NSString *)section;
- (NSNumber *) isVisibleInSource:(Source *)source;

@end

@implementation Package

- (void) dealloc {
    if (source_ != nil)
        [source_ release];

    [latest_ release];
    if (installed_ != nil)
        [installed_ release];

    [id_ release];
    if (name_ != nil)
        [name_ release];
    [tagline_ release];
    if (icon_ != nil)
        [icon_ release];
    if (website_ != nil)
        [website_ release];
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

- (Package *) initWithIterator:(pkgCache::PkgIterator)iterator database:(Database *)database {
    if ((self = [super init]) != nil) {
        iterator_ = iterator;
        database_ = database;

        version_ = [database_ policy]->GetCandidateVer(iterator_);
        latest_ = version_.end() ? nil : [StripVersion([NSString stringWithUTF8String:version_.VerStr()]) retain];

        if (!version_.end())
            file_ = version_.FileList();
        else {
            pkgCache &cache([database_ cache]);
            file_ = pkgCache::VerFileIterator(cache, cache.VerFileP);
        }

        pkgCache::VerIterator current = iterator_.CurrentVer();
        installed_ = current.end() ? nil : [StripVersion([NSString stringWithUTF8String:current.VerStr()]) retain];

        id_ = [[[NSString stringWithUTF8String:iterator_.Name()] lowercaseString] retain];

        if (!file_.end()) {
            pkgRecords::Parser *parser = &[database_ records]->Lookup(file_);

            const char *begin, *end;
            parser->GetRec(begin, end);

            name_ = Scour("Name", begin, end);
            if (name_ != nil)
                name_ = [name_ retain];
            tagline_ = [[NSString stringWithUTF8String:parser->ShortDesc().c_str()] retain];
            icon_ = Scour("Icon", begin, end);
            if (icon_ != nil)
                icon_ = [icon_ retain];
            website_ = Scour("Homepage", begin, end);
            if (website_ == nil)
                website_ = Scour("Website", begin, end);
            if (website_ != nil)
                website_ = [website_ retain];
            NSString *sponsor = Scour("Sponsor", begin, end);
            if (sponsor != nil)
                sponsor_ = [[Address addressWithString:sponsor] retain];
            NSString *author = Scour("Author", begin, end);
            if (author != nil)
                author_ = [[Address addressWithString:author] retain];
            NSString *tags = Scour("Tag", begin, end);
            if (tags != nil)
                tags_ = [[tags componentsSeparatedByString:@", "] retain];
        }

        if (tags_ != nil)
            for (int i(0), e([tags_ count]); i != e; ++i) {
                NSString *tag = [tags_ objectAtIndex:i];
                if ([tag hasPrefix:@"role::"]) {
                    role_ = [[tag substringFromIndex:6] retain];
                    break;
                }
            }

        NSMutableDictionary *metadata = [Packages_ objectForKey:id_];
        if (metadata == nil || [metadata count] == 0) {
            metadata = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                now_, @"FirstSeen",
            nil];

            [Packages_ setObject:metadata forKey:id_];
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

    return [name stringByReplacingCharacter:'_' withCharacter:' '];
}

- (Address *) maintainer {
    if (file_.end())
        return nil;
    pkgRecords::Parser *parser = &[database_ records]->Lookup(file_);
    return [Address addressWithString:[NSString stringWithUTF8String:parser->Maintainer().c_str()]];
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

- (NSDate *) seen {
    return [[Packages_ objectForKey:id_] objectForKey:@"FirstSeen"];
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

    if (current.end())
        return essential && [self essential];
    else {
        pkgCache::VerIterator candidate = [database_ policy]->GetCandidateVer(iterator_);
        return !candidate.end() && candidate != current;
    }
}

- (BOOL) essential {
    return (iterator_->Flags & pkgCache::Flag::Essential) == 0 ? NO : YES;
}

- (BOOL) broken {
    return [database_ cache][iterator_].InstBroken();
}

- (BOOL) visible {
    NSString *section = [self section];
    return [self hasSupportingRole] && (section == nil || isSectionVisible(section));
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
            _assert(false);
        case pkgDepCache::ModeKeep:
            if ((state.iFlags & pkgDepCache::AutoKept) != 0)
                return nil;
            else
                return nil;
            _assert(false);
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

- (NSString *) icon {
    return icon_;
}

- (NSString *) website {
    return website_;
}

- (Address *) sponsor {
    return sponsor_;
}

- (Address *) author {
    return author_;
}

- (NSArray *) relationships {
    return relationships_;
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

    return [lhs caseInsensitiveCompare:rhs];
}

- (NSComparisonResult) compareBySection:(Package *)package {
    NSString *lhs = [self section];
    NSString *rhs = [package section];

    if (lhs == NULL && rhs != NULL)
        return NSOrderedAscending;
    else if (lhs != NULL && rhs == NULL)
        return NSOrderedDescending;
    else if (lhs != NULL && rhs != NULL) {
        NSComparisonResult result = [lhs caseInsensitiveCompare:rhs];
        if (result != NSOrderedSame)
            return result;
    }

    return NSOrderedSame;
}

- (NSComparisonResult) compareBySectionAndName:(Package *)package {
    NSString *lhs = [self section];
    NSString *rhs = [package section];

    if (lhs == NULL && rhs != NULL)
        return NSOrderedAscending;
    else if (lhs != NULL && rhs == NULL)
        return NSOrderedDescending;
    else if (lhs != NULL && rhs != NULL) {
        NSComparisonResult result = [lhs compare:rhs];
        if (result != NSOrderedSame)
            return result;
    }

    return [self compareByName:package];
}

- (NSComparisonResult) compareForChanges:(Package *)package {
    BOOL lhs = [self upgradableAndEssential:YES];
    BOOL rhs = [package upgradableAndEssential:YES];

    if (lhs != rhs)
        return lhs ? NSOrderedAscending : NSOrderedDescending;
    else if (!lhs) {
        switch ([[self seen] compare:[package seen]]) {
            case NSOrderedAscending:
                return NSOrderedDescending;
            case NSOrderedSame:
                break;
            case NSOrderedDescending:
                return NSOrderedAscending;
            default:
                _assert(false);
        }
    }

    return [self compareByName:package];
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

- (NSNumber *) isVisiblySearchedForBy:(NSString *)search {
    return [NSNumber numberWithBool:(
        [self valid] && [self visible] && [self matches:search]
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
        [self valid] && [self visible] &&
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

    return [lhs caseInsensitiveCompare:rhs];
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

/* Database Implementation {{{ */
@implementation Database

- (void) dealloc {
    _assert(false);
    [super dealloc];
}

- (void) _readCydia:(NSNumber *)fd {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    __gnu_cxx::stdio_filebuf<char> ib([fd intValue], std::ios::in);
    std::istream is(&ib);
    std::string line;

    while (std::getline(is, line)) {
        const char *data(line.c_str());
        //size_t size = line.size();
        fprintf(stderr, "C:%s\n", data);
    }

    [pool release];
    _assert(false);
}

- (void) _readStatus:(NSNumber *)fd {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    __gnu_cxx::stdio_filebuf<char> ib([fd intValue], std::ios::in);
    std::istream is(&ib);
    std::string line;

    static Pcre conffile_r("^status: [^ ]* : conffile-prompt : (.*?) *$");
    static Pcre pmstatus_r("^([^:]*):([^:]*):([^:]*):(.*)$");

    while (std::getline(is, line)) {
        const char *data(line.c_str());
        size_t size = line.size();
        fprintf(stderr, "S:%s\n", data);

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
            else if (type == "pmstatus")
                [delegate_ setProgressTitle:string];
            else if (type == "pmconffile")
                [delegate_ setConfigurationData:string];
            else _assert(false);
        } else _assert(false);
    }

    [pool release];
    _assert(false);
}

- (void) _readOutput:(NSNumber *)fd {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    __gnu_cxx::stdio_filebuf<char> ib([fd intValue], std::ios::in);
    std::istream is(&ib);
    std::string line;

    while (std::getline(is, line)) {
        fprintf(stderr, "O:%s\n", line.c_str());
        [delegate_ addProgressOutput:[NSString stringWithUTF8String:line.c_str()]];
    }

    [pool release];
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
        setenv("CYDIA", [[[[NSNumber numberWithInt:cydiafd_] stringValue] stringByAppendingString:@" 0"] UTF8String], _not(int));

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

- (NSArray *) packages {
    return packages_;
}

- (NSArray *) sources {
    return [sources_ allValues];
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

    if (!cache_.Open(progress_, true)) {
        std::string error;
        if (!_error->PopMessage(error))
            _assert(false);
        _error->Discard();
        fprintf(stderr, "cache_.Open():[%s]\n", error.c_str());

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
    for (pkgCache::PkgIterator iterator = cache_->PkgBegin(); !iterator.end(); ++iterator)
        if (Package *package = [Package packageWithIterator:iterator database:self])
            [packages_ addObject:package];

    [packages_ sortUsingSelector:@selector(compareByName:)];
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
            fprintf(stderr, "ArchiveCleaner: %s\n", error.c_str());
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

        fprintf(stderr, "pAf:%s:%s\n", uri.c_str(), error.c_str());
        failed = true;

        [delegate_ performSelectorOnMainThread:@selector(_setProgressError:)
            withObject:[NSArray arrayWithObjects:[NSString stringWithUTF8String:error.c_str()], nil]
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

/* Confirmation View {{{ */
void AddTextView(NSMutableDictionary *fields, NSMutableArray *packages, NSString *key) {
    if ([packages count] == 0)
        return;

    UITextView *text = GetTextView([packages count] == 0 ? @"n/a" : [packages componentsJoinedByString:@", "], 120, false);
    [fields setObject:text forKey:key];

    CGColor blue(space_, 0, 0, 0.4, 1);
    [text setTextColor:blue];
}

@protocol ConfirmationViewDelegate
- (void) cancel;
- (void) confirm;
@end

@interface ConfirmationView : UIView {
    Database *database_;
    id delegate_;
    UITransitionView *transition_;
    UIView *overlay_;
    UINavigationBar *navbar_;
    UIPreferencesTable *table_;
    NSMutableDictionary *fields_;
    UIAlertSheet *essential_;
}

- (void) cancel;

- (id) initWithView:(UIView *)view database:(Database *)database delegate:(id)delegate;

@end

@implementation ConfirmationView

- (void) dealloc {
    [navbar_ setDelegate:nil];
    [transition_ setDelegate:nil];
    [table_ setDataSource:nil];

    [transition_ release];
    [overlay_ release];
    [navbar_ release];
    [table_ release];
    [fields_ release];
    if (essential_ != nil)
        [essential_ release];
    [super dealloc];
}

- (void) cancel {
    [transition_ transition:7 toView:nil];
    [delegate_ cancel];
}

- (void) transitionViewDidComplete:(UITransitionView*)view fromView:(UIView*)from toView:(UIView*)to {
    if (from != nil && to == nil)
        [self removeFromSuperview];
}

- (void) navigationBar:(UINavigationBar *)navbar buttonClicked:(int)button {
    switch (button) {
        case 0:
            if (essential_ != nil)
                [essential_ popupAlertAnimated:YES];
            else
                [delegate_ confirm];
        break;

        case 1:
            [self cancel];
        break;
    }
}

- (void) alertSheet:(UIAlertSheet *)sheet buttonClicked:(int)button {
    NSString *context = [sheet context];

    if ([context isEqualToString:@"remove"])
        switch (button) {
            case 1:
                [self cancel];
                break;
            case 2:
                [delegate_ confirm];
                break;
            default:
                _assert(false);
        }
    else if ([context isEqualToString:@"unable"])
        [self cancel];

    [sheet dismiss];
}

- (int) numberOfGroupsInPreferencesTable:(UIPreferencesTable *)table {
    return 2;
}

- (NSString *) preferencesTable:(UIPreferencesTable *)table titleForGroup:(int)group {
    switch (group) {
        case 0: return @"Statistics";
        case 1: return @"Modifications";

        default: _assert(false);
    }
}

- (int) preferencesTable:(UIPreferencesTable *)table numberOfRowsInGroup:(int)group {
    switch (group) {
        case 0: return 3;
        case 1: return [fields_ count];

        default: _assert(false);
    }
}

- (float) preferencesTable:(UIPreferencesTable *)table heightForRow:(int)row inGroup:(int)group withProposedHeight:(float)proposed {
    if (group != 1 || row == -1)
        return proposed;
    else {
        _assert(size_t(row) < [fields_ count]);
        return [[[fields_ allValues] objectAtIndex:row] visibleTextRect].size.height + TextViewOffset_;
    }
}

- (UIPreferencesTableCell *) preferencesTable:(UIPreferencesTable *)table cellForRow:(int)row inGroup:(int)group {
    UIPreferencesTableCell *cell = [[[UIPreferencesTableCell alloc] init] autorelease];
    [cell setShowSelection:NO];

    switch (group) {
        case 0: switch (row) {
            case 0: {
                [cell setTitle:@"Downloading"];
                [cell setValue:SizeString([database_ fetcher].FetchNeeded())];
            } break;

            case 1: {
                [cell setTitle:@"Resuming At"];
                [cell setValue:SizeString([database_ fetcher].PartialPresent())];
            } break;

            case 2: {
                double size([database_ cache]->UsrSize());

                if (size < 0) {
                    [cell setTitle:@"Disk Freeing"];
                    [cell setValue:SizeString(-size)];
                } else {
                    [cell setTitle:@"Disk Using"];
                    [cell setValue:SizeString(size)];
                }
            } break;

            default: _assert(false);
        } break;

        case 1:
            _assert(size_t(row) < [fields_ count]);
            [cell setTitle:[[fields_ allKeys] objectAtIndex:row]];
            [cell addSubview:[[fields_ allValues] objectAtIndex:row]];
        break;

        default: _assert(false);
    }

    return cell;
}

- (id) initWithView:(UIView *)view database:(Database *)database delegate:(id)delegate {
    if ((self = [super initWithFrame:[view bounds]]) != nil) {
        database_ = database;
        delegate_ = delegate;

        transition_ = [[UITransitionView alloc] initWithFrame:[self bounds]];
        [self addSubview:transition_];

        overlay_ = [[UIView alloc] initWithFrame:[transition_ bounds]];

        CGSize navsize = [UINavigationBar defaultSize];
        CGRect navrect = {{0, 0}, navsize};
        CGRect bounds = [overlay_ bounds];

        navbar_ = [[UINavigationBar alloc] initWithFrame:navrect];
        if (Advanced_)
            [navbar_ setBarStyle:1];
        [navbar_ setDelegate:self];

        UINavigationItem *navitem = [[[UINavigationItem alloc] initWithTitle:@"Confirm"] autorelease];
        [navbar_ pushNavigationItem:navitem];
        [navbar_ showButtonsWithLeftTitle:@"Cancel" rightTitle:@"Confirm"];

        fields_ = [[NSMutableDictionary dictionaryWithCapacity:16] retain];

        NSMutableArray *installing = [NSMutableArray arrayWithCapacity:16];
        NSMutableArray *reinstalling = [NSMutableArray arrayWithCapacity:16];
        NSMutableArray *upgrading = [NSMutableArray arrayWithCapacity:16];
        NSMutableArray *downgrading = [NSMutableArray arrayWithCapacity:16];
        NSMutableArray *removing = [NSMutableArray arrayWithCapacity:16];

        bool remove(false);

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
            }
        }

        if (!remove)
            essential_ = nil;
        else if (Advanced_ || true) {
            essential_ = [[UIAlertSheet alloc]
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
            essential_ = [[UIAlertSheet alloc]
                initWithTitle:@"Unable to Comply"
                buttons:[NSArray arrayWithObjects:@"Okay", nil]
                defaultButtonIndex:0
                delegate:self
                context:@"unable"
            ];

            [essential_ setBodyText:@"This operation requires the removal of one or more packages that are required for the continued operation of either Cydia or iPhoneOS. In order to continue and force this operation you will need to be activate the Advanced mode under to continue and force this operation you will need to be activate the Advanced mode under Settings."];
        }

        AddTextView(fields_, installing, @"Installing");
        AddTextView(fields_, reinstalling, @"Reinstalling");
        AddTextView(fields_, upgrading, @"Upgrading");
        AddTextView(fields_, downgrading, @"Downgrading");
        AddTextView(fields_, removing, @"Removing");

        table_ = [[UIPreferencesTable alloc] initWithFrame:CGRectMake(
            0, navsize.height, bounds.size.width, bounds.size.height - navsize.height
        )];

        [table_ setReusesTableCells:YES];
        [table_ setDataSource:self];
        [table_ reloadData];

        [overlay_ addSubview:navbar_];
        [overlay_ addSubview:table_];

        [view addSubview:self];

        [transition_ setDelegate:self];

        UIView *blank = [[[UIView alloc] initWithFrame:[transition_ bounds]] autorelease];
        [transition_ transition:0 toView:blank];
        [transition_ transition:3 toView:overlay_];
    } return self;
}

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
            [overlay_ setBackgroundColor:Black_];
        else {
            background_ = [[UIView alloc] initWithFrame:[self bounds]];
            [background_ setBackgroundColor:Black_];
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

        [status_ setColor:White_];
        [status_ setBackgroundColor:Clear_];

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

        [output_ setTextColor:White_];
        [output_ setBackgroundColor:Clear_];

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
        [close_ setTitle:@"Return to Cydia"];
        [close_ setEnabled:YES];

        GSFontRef bold = GSFontCreateWithName("Helvetica", kGSFontTraitBold, 22);
        [close_ setTitleFont:bold];
        CFRelease(bold);

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

- (void) alertSheet:(UIAlertSheet *)sheet buttonClicked:(int)button {
    NSString *context = [sheet context];
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
            default:
                _assert(false);
        }
    }

    [sheet dismiss];
}

- (void) closeButtonPushed {
    [delegate_ progressViewIsComplete:self];
    [self resetView];
}

- (void) _retachThread {
    UINavigationItem *item = [navbar_ topItem];
    [item setTitle:@"Complete"];

    [overlay_ addSubview:close_];
    [progress_ removeFromSuperview];
    [status_ removeFromSuperview];

#ifdef __OBJC2__
    notify_post("com.apple.mobile.application_installed");
#endif

    [delegate_ setStatusBarShowsProgress:NO];

    running_ = NO;
}

- (void) _detachNewThreadData:(ProgressData *)data {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    [[data target] performSelector:[data selector] withObject:[data object]];
    [data release];

    [self performSelectorOnMainThread:@selector(_retachThread) withObject:nil waitUntilDone:YES];

    [pool release];
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
        title:@"Repairing..."
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

    UIAlertSheet *sheet = [[[UIAlertSheet alloc]
        initWithTitle:(package == nil ? @"Source Error" : [package name])
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

- (void) addProgressOutput:(NSString *)output {
    [self
        performSelectorOnMainThread:@selector(_addProgressOutput:)
        withObject:output
        waitUntilDone:YES
    ];
}

- (void) _setConfigurationData:(NSString *)data {
    static Pcre conffile_r("^'(.*)' '(.*)' ([01]) ([01])$");

    _assert(conffile_r(data));

    NSString *ofile = conffile_r[1];
    //NSString *nfile = conffile_r[2];

    UIAlertSheet *sheet = [[[UIAlertSheet alloc]
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
    [status_ setText:[title stringByAppendingString:@"..."]];
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
    //UIImageView *trusted_;
#ifdef USE_BADGES
    UIImageView *badge_;
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
}

- (void) dealloc {
    [self clearPackage];
#ifdef USE_BADGES
    [badge_ release];
    [status_ release];
#endif
    //[trusted_ release];
    [super dealloc];
}

- (PackageCell *) init {
    if ((self = [super init]) != nil) {
#ifdef USE_BADGES
        badge_ = [[UIImageView alloc] initWithFrame:CGRectMake(17, 70, 16, 16)];

        status_ = [[UITextLabel alloc] initWithFrame:CGRectMake(48, 68, 280, 20)];
        [status_ setBackgroundColor:Clear_];
        [status_ setFont:small];
#endif
    } return self;
}

- (void) setPackage:(Package *)package {
    [self clearPackage];

    Source *source = [package source];

    icon_ = nil;
    if (NSString *icon = [package icon])
        icon_ = [UIImage imageAtPath:[icon substringFromIndex:6]];
    if (icon_ == nil) if (NSString *section = [package section])
        icon_ = [UIImage applicationImageNamed:[NSString stringWithFormat:@"Sections/%@.png", Simplify(section)]];
    /*if (icon_ == nil) if (NSString *icon = [source defaultIcon])
        icon_ = [UIImage imageAtPath:[icon substringFromIndex:6]];*/
    if (icon_ == nil)
        icon_ = [UIImage applicationImageNamed:@"unknown.png"];

    icon_ = [icon_ retain];

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

    NSString *section = Simplify([package section]);
    if (section != nil && ![section isEqualToString:label])
        from = [from stringByAppendingString:[NSString stringWithFormat:@" (%@)", section]];

    source_ = [from retain];

#ifdef USE_BADGES
    [badge_ removeFromSuperview];
    [status_ removeFromSuperview];

    if (NSString *mode = [package mode]) {
        [badge_ setImage:[UIImage applicationImageNamed:
            [mode isEqualToString:@"Remove"] || [mode isEqualToString:@"Purge"] ? @"removing.png" : @"installing.png"
        ]];

        [status_ setText:[NSString stringWithFormat:@"Queued for %@", mode]];
        [status_ setColor:Blueish_];
    } else if ([package half]) {
        [badge_ setImage:[UIImage applicationImageNamed:@"damaged.png"]];
        [status_ setText:@"Package Damaged"];
        [status_ setColor:Red_];
    } else {
        [badge_ setImage:nil];
        [status_ setText:nil];
        goto done;
    }

    [self addSubview:badge_];
    [self addSubview:status_];
  done:;
#endif
}

- (void) drawContentInRect:(CGRect)rect selected:(BOOL)selected {
    if (icon_ != nil)
        [icon_ drawInRect:CGRectMake(10, 10, 30, 30)];

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
    UISwitchControl *switch_;
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

        switch_ = [[UISwitchControl alloc] initWithFrame:CGRectMake(218, 9, 60, 25)];
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
            [switch_ setValue:isSectionVisible(section_) animated:NO];
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
        [count_ drawAtPoint:CGPointMake(12 + (29 - size.width) / 2, 15) withFont:Font12Bold_];

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
        GSFontRef font = GSFontCreateWithName("Helvetica", kGSFontTraitNone, 16);
        [[(UIImageAndTextTableCell *)reusing titleTextLabel] setFont:font];
        CFRelease(font);
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

        NSString *path = [NSString stringWithFormat:@"/var/lib/dpkg/info/%@.list", name_];

        {
            std::ifstream fin([path UTF8String]);
            std::string line;
            while (std::getline(fin, line))
                [files_ addObject:[NSString stringWithUTF8String:line.c_str()]];
        }

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
@protocol PackageViewDelegate
- (void) performPackage:(Package *)package;
@end

@interface PackageView : RVPage {
    _transient Database *database_;
    UIPreferencesTable *table_;
    Package *package_;
    NSString *name_;
    UITextView *description_;
    NSMutableArray *buttons_;
}

- (id) initWithBook:(RVBook *)book database:(Database *)database;
- (void) setPackage:(Package *)package;

@end

@implementation PackageView

- (void) dealloc {
    [table_ setDataSource:nil];
    [table_ setDelegate:nil];

    if (package_ != nil)
        [package_ release];
    if (name_ != nil)
        [name_ release];
    if (description_ != nil)
        [description_ release];
    [table_ release];
    [buttons_ release];
    [super dealloc];
}

- (int) numberOfGroupsInPreferencesTable:(UIPreferencesTable *)table {
    int number = 2;
    if ([package_ installed] != nil)
        ++number;
    if ([package_ source] != nil)
        ++number;
    return number;
}

- (NSString *) preferencesTable:(UIPreferencesTable *)table titleForGroup:(int)group {
    if (group-- == 0)
        return nil;
    else if ([package_ installed] != nil && group-- == 0)
        return @"Installed Package";
    else if (group-- == 0)
        return @"Package Details";
    else if ([package_ source] != nil && group-- == 0)
        return @"Source Information";
    else _assert(false);
}

- (float) preferencesTable:(UIPreferencesTable *)table heightForRow:(int)row inGroup:(int)group withProposedHeight:(float)proposed {
    if (description_ == nil || group != 0 || row != ([package_ author] == nil ? 1 : 2))
        return proposed;
    else
        return [description_ visibleTextRect].size.height + TextViewOffset_;
}

- (int) preferencesTable:(UIPreferencesTable *)table numberOfRowsInGroup:(int)group {
    if (group-- == 0) {
        int number = 1;
        if ([package_ author] != nil)
            ++number;
        if (description_ != nil)
            ++number;
        if ([package_ website] != nil)
            ++number;
        return number;
    } else if ([package_ installed] != nil && group-- == 0)
        return 2;
    else if (group-- == 0) {
        int number = 2;
        if ([package_ size] != 0)
            ++number;
        if ([package_ maintainer] != nil)
            ++number;
        if ([package_ sponsor] != nil)
            ++number;
        if ([package_ relationships] != nil)
            ++number;
        if ([[package_ source] trusted])
            ++number;
        return number;
    } else if ([package_ source] != nil && group-- == 0) {
        Source *source = [package_ source];
        NSString *description = [source description];
        int number = 1;
        if (description != nil && ![description isEqualToString:[source label]])
            ++number;
        if ([source origin] != nil)
            ++number;
        return number;
    } else _assert(false);
}

- (UIPreferencesTableCell *) preferencesTable:(UIPreferencesTable *)table cellForRow:(int)row inGroup:(int)group {
    UIPreferencesTableCell *cell = [[[UIPreferencesTableCell alloc] init] autorelease];
    [cell setShowSelection:NO];

    if (group-- == 0) {
        if (false) {
        } else if (row-- == 0) {
            [cell setTitle:[package_ name]];
            [cell setValue:[package_ latest]];
        } else if ([package_ author] != nil && row-- == 0) {
            [cell setTitle:@"Author"];
            [cell setValue:[[package_ author] name]];
            [cell setShowDisclosure:YES];
            [cell setShowSelection:YES];
        } else if (description_ != nil && row-- == 0) {
            [cell addSubview:description_];
        } else if ([package_ website] != nil && row-- == 0) {
            [cell setTitle:@"More Information"];
            [cell setShowDisclosure:YES];
            [cell setShowSelection:YES];
        } else _assert(false);
    } else if ([package_ installed] != nil && group-- == 0) {
        if (false) {
        } else if (row-- == 0) {
            [cell setTitle:@"Version"];
            NSString *installed([package_ installed]);
            [cell setValue:(installed == nil ? @"n/a" : installed)];
        } else if (row-- == 0) {
            [cell setTitle:@"Filesystem Content"];
            [cell setShowDisclosure:YES];
            [cell setShowSelection:YES];
        } else _assert(false);
    } else if (group-- == 0) {
        if (false) {
        } else if (row-- == 0) {
            [cell setTitle:@"Identifier"];
            [cell setValue:[package_ id]];
        } else if (row-- == 0) {
            [cell setTitle:@"Section"];
            NSString *section([package_ section]);
            [cell setValue:(section == nil ? @"n/a" : section)];
        } else if ([package_ size] != 0 && row-- == 0) {
            [cell setTitle:@"Expanded Size"];
            [cell setValue:SizeString([package_ size])];
        } else if ([package_ maintainer] != nil && row-- == 0) {
            [cell setTitle:@"Maintainer"];
            [cell setValue:[[package_ maintainer] name]];
            [cell setShowDisclosure:YES];
            [cell setShowSelection:YES];
        } else if ([package_ sponsor] != nil && row-- == 0) {
            [cell setTitle:@"Sponsor"];
            [cell setValue:[[package_ sponsor] name]];
            [cell setShowDisclosure:YES];
            [cell setShowSelection:YES];
        } else if ([package_ relationships] != nil && row-- == 0) {
            [cell setTitle:@"Package Relationships"];
            [cell setShowDisclosure:YES];
            [cell setShowSelection:YES];
        } else if ([[package_ source] trusted] && row-- == 0) {
            [cell setIcon:[UIImage applicationImageNamed:@"trusted.png"]];
            [cell setValue:@"This package has been signed."];
        } else _assert(false);
    } else if ([package_ source] != nil && group-- == 0) {
        Source *source = [package_ source];
        NSString *description = [source description];

        if (false) {
        } else if (row-- == 0) {
            NSString *label = [source label];
            if (label == nil)
                label = [source uri];
            [cell setTitle:label];
            [cell setValue:[source version]];
        } else if (description != nil && ![description isEqualToString:[source label]] && row-- == 0) {
            [cell setValue:description];
        } else if ([source origin] != nil && row-- == 0) {
            [cell setTitle:@"Origin"];
            [cell setValue:[source origin]];
        } else _assert(false);
    } else _assert(false);

    return cell;
}

- (BOOL) canSelectRow:(int)row {
    return YES;
}

- (void) tableRowSelected:(NSNotification *)notification {
    int row = [table_ selectedRow];
    if (row == INT_MAX)
        return;

    #define _else else goto _label; return; } _label:

    if (true) {
        if (row-- == 0) {
        } else if (row-- == 0) {
        } else if ([package_ author] != nil && row-- == 0) {
            [delegate_ openURL:[NSURL URLWithString:[NSString stringWithFormat:@"mailto:%@?subject=%@",
                [[package_ author] email],
                [[NSString stringWithFormat:@"regarding apt package \"%@\"",
                    [package_ name]
                ] stringByAddingPercentEscapes]
            ]]];
        } else if (description_ != nil && row-- == 0) {
        } else if ([package_ website] != nil && row-- == 0) {
            NSURL *url = [NSURL URLWithString:[package_ website]];
            BrowserView *browser = [[[BrowserView alloc] initWithBook:book_ database:database_] autorelease];
            [browser setDelegate:delegate_];
            [book_ pushPage:browser];
            [browser loadURL:url];
    } _else if ([package_ installed] != nil) {
        if (row-- == 0) {
        } else if (row-- == 0) {
        } else if (row-- == 0) {
            FileTable *files = [[[FileTable alloc] initWithBook:book_ database:database_] autorelease];
            [files setDelegate:delegate_];
            [files setPackage:package_];
            [book_ pushPage:files];
    } _else if (true) {
        if (row-- == 0) {
        } else if (row-- == 0) {
        } else if (row-- == 0) {
        } else if ([package_ size] != 0 && row-- == 0) {
        } else if ([package_ maintainer] != nil && row-- == 0) {
            [delegate_ openURL:[NSURL URLWithString:[NSString stringWithFormat:@"mailto:%@?subject=%@",
                [[package_ maintainer] email],
                [[NSString stringWithFormat:@"regarding apt package \"%@\"",
                    [package_ name]
                ] stringByAddingPercentEscapes]
            ]]];
        } else if ([package_ sponsor] != nil && row-- == 0) {
            NSURL *url = [NSURL URLWithString:[[package_ sponsor] email]];
            BrowserView *browser = [[[BrowserView alloc] initWithBook:book_ database:database_] autorelease];
            [browser setDelegate:delegate_];
            [book_ pushPage:browser];
            [browser loadURL:url];
        } else if ([package_ relationships] != nil && row-- == 0) {
        } else if ([[package_ source] trusted] && row-- == 0) {
    } _else if ([package_ source] != nil) {
        Source *source = [package_ source];
        NSString *description = [source description];

        if (row-- == 0) {
        } else if (row-- == 0) {
        } else if (description != nil && ![description isEqualToString:[source label]] && row-- == 0) {
        } else if ([source origin] != nil && row-- == 0) {
    } _else _assert(false);

    #undef _else
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

- (void) alertSheet:(UIAlertSheet *)sheet buttonClicked:(int)button {
    int count = [buttons_ count];
    _assert(count != 0);
    _assert(button <= count + 1);

    if (count != button - 1)
        [self _clickButtonWithName:[buttons_ objectAtIndex:(button - 1)]];

    [sheet dismiss];
}

- (void) _rightButtonClicked {
    int count = [buttons_ count];
    _assert(count != 0);

    if (count == 1)
        [self _clickButtonWithName:[buttons_ objectAtIndex:0]];
    else {
        NSMutableArray *buttons = [NSMutableArray arrayWithCapacity:(count + 1)];
        [buttons addObjectsFromArray:buttons_];
        [buttons addObject:@"Cancel"];

        [delegate_ slideUp:[[[UIAlertSheet alloc]
            initWithTitle:nil
            buttons:buttons
            defaultButtonIndex:2
            delegate:self
            context:@"manage"
        ] autorelease]];
    }
}

- (NSString *) rightButtonTitle {
    int count = [buttons_ count];
    return count == 0 ? nil : count != 1 ? @"Modify" : [buttons_ objectAtIndex:0];
}

- (NSString *) title {
    return @"Details";
}

- (id) initWithBook:(RVBook *)book database:(Database *)database {
    if ((self = [super initWithBook:book]) != nil) {
        database_ = database;

        table_ = [[UIPreferencesTable alloc] initWithFrame:[self bounds]];
        [self addSubview:table_];

        [table_ setDataSource:self];
        [table_ setDelegate:self];

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

    if (description_ != nil) {
        [description_ release];
        description_ = nil;
    }

    [buttons_ removeAllObjects];

    if (package != nil) {
        package_ = [package retain];
        name_ = [[package id] retain];

        NSString *description([package description]);
        if (description == nil)
            description = [package tagline];
        if (description != nil) {
            description_ = [GetTextView(description, 12, true) retain];
            [description_ setTextColor:Black_];
        }

        [table_ reloadData];

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

- (void) resetViewAnimated:(BOOL)animated {
    [table_ resetViewAnimated:animated];
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
    SEL filter_;
    id object_;
    NSMutableArray *packages_;
    NSMutableArray *sections_;
    UISectionList *list_;
}

- (id) initWithBook:(RVBook *)book database:(Database *)database title:(NSString *)title filter:(SEL)filter with:(id)object;

- (void) setDelegate:(id)delegate;
- (void) setObject:(id)object;

- (void) reloadData;
- (void) resetCursor;

- (UISectionList *) list;

- (void) setShouldHideHeaderInShortLists:(BOOL)hide;

@end

@implementation PackageTable

- (void) dealloc {
    [list_ setDataSource:nil];

    [title_ release];
    if (object_ != nil)
        [object_ release];
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

- (id) initWithBook:(RVBook *)book database:(Database *)database title:(NSString *)title filter:(SEL)filter with:(id)object {
    if ((self = [super initWithBook:book]) != nil) {
        database_ = database;
        title_ = [title retain];
        filter_ = filter;
        object_ = object == nil ? nil : [object retain];

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
        [self reloadData];
    } return self;
}

- (void) setDelegate:(id)delegate {
    delegate_ = delegate;
}

- (void) setObject:(id)object {
    if (object_ != nil)
        [object_ release];
    if (object == nil)
        object_ = nil;
    else
        object_ = [object retain];
}

- (void) reloadData {
    NSArray *packages = [database_ packages];

    [packages_ removeAllObjects];
    [sections_ removeAllObjects];

    for (size_t i(0); i != [packages count]; ++i) {
        Package *package([packages objectAtIndex:i]);
        if ([[package performSelector:filter_ withObject:object_] boolValue])
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
    UIAlertSheet *alert_;
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

    PackageTable *packages = [[[PackageTable alloc]
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
            UIAlertSheet *sheet = [[[UIAlertSheet alloc]
                initWithTitle:@"Verification Error"
                buttons:[NSArray arrayWithObjects:@"OK", nil]
                defaultButtonIndex:0
                delegate:self
                context:@"urlerror"
            ] autorelease];

            [sheet setBodyText:[error_ localizedDescription]];
            [sheet popupAlertAnimated:YES];
        } else {
            UIAlertSheet *sheet = [[[UIAlertSheet alloc]
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
    fprintf(stderr, "connection:\"%s\" didFailWithError:\"%s\"", [href_ UTF8String], [[error localizedDescription] UTF8String]);
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

- (void) alertSheet:(UIAlertSheet *)sheet buttonClicked:(int)button {
    NSString *context = [sheet context];
    if ([context isEqualToString:@"source"])
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
    } return self;
}

- (void) reloadData {
    pkgSourceList list;
    _assert(list.ReadMainList());

    [sources_ removeAllObjects];
    [sources_ addObjectsFromArray:[database_ sources]];
    [sources_ sortUsingSelector:@selector(compareByNameAndType:)];

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

    UIAlertSheet *sheet = [[[UIAlertSheet alloc]
        initWithTitle:@"Enter Cydia/APT URL"
        buttons:[NSArray arrayWithObjects:@"Add Source", @"Cancel", nil]
        defaultButtonIndex:0
        delegate:self
        context:@"source"
    ] autorelease];

    [sheet addTextFieldWithValue:@"http://" label:@""];

    UITextTraits *traits = [[sheet textField] textTraits];
    [traits setAutoCapsType:0];
    [traits setPreferredKeyboardType:3];
    [traits setAutoCorrectionType:1];

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

- (NSString *) backButtonTitle {
    return @"Sources";
}

- (NSString *) leftButtonTitle {
    return [[list_ table] isRowDeletionEnabled] ? @"Add" : nil;
}

- (NSString *) rightButtonTitle {
    return [[list_ table] isRowDeletionEnabled] ? @"Done" : @"Edit";
}

- (RVUINavBarButtonStyle) rightButtonStyle {
    return [[list_ table] isRowDeletionEnabled] ? RVUINavBarButtonStyleHighlighted : RVUINavBarButtonStyleNormal;
}

@end
/* }}} */

/* Installed View {{{ */
@interface InstalledView : RVPage {
    _transient Database *database_;
    PackageTable *packages_;
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

        packages_ = [[PackageTable alloc]
            initWithBook:book
            database:database
            title:nil
            filter:@selector(isInstalledAndVisible:)
            with:[NSNumber numberWithBool:YES]
        ];

        [self addSubview:packages_];
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

- (NSString *) rightButtonTitle {
    return Role_ != nil && [Role_ isEqualToString:@"Developer"] ? nil : expert_ ? @"Expert" : @"Simple";
}

- (RVUINavBarButtonStyle) rightButtonStyle {
    return expert_ ? RVUINavBarButtonStyleHighlighted : RVUINavBarButtonStyleNormal;
}

- (void) setDelegate:(id)delegate {
    [super setDelegate:delegate];
    [packages_ setDelegate:delegate];
}

@end
/* }}} */

@interface HomeView : BrowserView {
}

@end

@implementation HomeView

- (void) alertSheet:(UIAlertSheet *)sheet buttonClicked:(int)button {
    [sheet dismiss];
}

- (void) _leftButtonClicked {
    UIAlertSheet *sheet = [[[UIAlertSheet alloc]
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

- (NSString *) rightButtonTitle {
    return nil;
}

@end

/* Browser Implementation {{{ */
@implementation BrowserView

- (void) dealloc {
    WebView *webview = [webview_ webView];
    [webview setFrameLoadDelegate:nil];
    [webview setResourceLoadDelegate:nil];
    [webview setUIDelegate:nil];

    [scroller_ setDelegate:nil];
    [webview_ setDelegate:nil];

    [scroller_ release];
    [webview_ release];
    [urls_ release];
    [indicator_ release];
    if (title_ != nil)
        [title_ release];
    [super dealloc];
}

- (void) loadURL:(NSURL *)url cachePolicy:(NSURLRequestCachePolicy)policy {
    [self loadRequest:[NSURLRequest
        requestWithURL:url
        cachePolicy:policy
        timeoutInterval:30.0
    ]];
}

- (void) loadURL:(NSURL *)url {
    [self loadURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy];
}

- (NSURLRequest *) _addHeadersToRequest:(NSURLRequest *)request {
    NSMutableURLRequest *copy = [request mutableCopy];

    [copy addValue:[NSString stringWithUTF8String:Firmware_] forHTTPHeaderField:@"X-Firmware"];
    [copy addValue:[NSString stringWithUTF8String:Machine_] forHTTPHeaderField:@"X-Machine"];
    [copy addValue:[NSString stringWithUTF8String:SerialNumber_] forHTTPHeaderField:@"X-Serial-Number"];

    if (Role_ != nil)
        [copy addValue:Role_ forHTTPHeaderField:@"X-Role"];

    return copy;
}

- (void) loadRequest:(NSURLRequest *)request {
    pushed_ = true;
    [webview_ loadRequest:request];
}

- (void) reloadURL {
    NSURL *url = [[[urls_ lastObject] retain] autorelease];
    [urls_ removeLastObject];
    [self loadURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData];
}

- (WebView *) webView {
    return [webview_ webView];
}

- (void) view:(UIView *)sender didSetFrame:(CGRect)frame {
    [scroller_ setContentSize:frame.size];
}

- (void) view:(UIView *)sender didSetFrame:(CGRect)frame oldFrame:(CGRect)old {
    [self view:sender didSetFrame:frame];
}

- (void) pushPage:(RVPage *)page {
    [self setBackButtonTitle:title_];
    [page setDelegate:delegate_];
    [book_ pushPage:page];
}

- (void) getSpecial:(NSString *)href {
    RVPage *page = nil;

    if ([href hasPrefix:@"mailto:"])
        [delegate_ openURL:[NSURL URLWithString:href]];
    else if ([href isEqualToString:@"cydia://add-source"])
        page = [[[AddSourceView alloc] initWithBook:book_ database:database_] autorelease];
    else if ([href isEqualToString:@"cydia://sources"])
        page = [[[SourceTable alloc] initWithBook:book_ database:database_] autorelease];
    else if ([href isEqualToString:@"cydia://packages"])
        page = [[[InstalledView alloc] initWithBook:book_ database:database_] autorelease];
    else if ([href hasPrefix:@"apptapp://package/"]) {
        NSString *name = [href substringFromIndex:18];

        if (Package *package = [database_ packageWithName:name]) {
            PackageView *view = [[[PackageView alloc] initWithBook:book_ database:database_] autorelease];
            [view setPackage:package];
            page = view;
        } else {
            UIAlertSheet *sheet = [[[UIAlertSheet alloc]
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
        }
    }

    if (page != nil)
        [self pushPage:page];
}

- (void) webView:(WebView *)sender willClickElement:(id)element {
    if ([[element localName] isEqualToString:@"img"])
        do if ((element = [element parentNode]) == nil)
            return;
        while (![[element localName] isEqualToString:@"a"]);
    if (![element respondsToSelector:@selector(href)])
        return;
    NSString *href = [element href];
    if (href == nil)
        return;
    [self getSpecial:href];
}

- (BOOL) isSpecialScheme:(NSString *)scheme {
    return
        [scheme isEqualToString:@"apptapp"] ||
        [scheme isEqualToString:@"cydia"] ||
        [scheme isEqualToString:@"mailto"];
}

- (NSURLRequest *) webView:(WebView *)sender resource:(id)identifier willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse fromDataSource:(WebDataSource *)dataSource {
    NSURL *url = [request URL];
    if ([self isSpecialScheme:[url scheme]]) {
        [self getSpecial:[url absoluteString]];
        return nil;
    }

    if (!pushed_) {
        pushed_ = true;
        [book_ pushPage:self];
    }

    return [self _addHeadersToRequest:request];
}

- (WebView *) webView:(WebView *)sender createWebViewWithRequest:(NSURLRequest *)request {
    if (request != nil) {
        NSString *scheme = [[request URL] scheme];
        if ([self isSpecialScheme:scheme])
            return nil;
    }

    [self setBackButtonTitle:title_];

    BrowserView *browser = [[[BrowserView alloc] initWithBook:book_ database:database_] autorelease];
    [browser setDelegate:delegate_];

    if (request != nil) {
        [browser loadRequest:[self _addHeadersToRequest:request]];
        [book_ pushPage:browser];
    }

    return [browser webView];
}

- (void) webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame {
    title_ = [title retain];
    [self setTitle:title];
}

- (void) webView:(WebView *)sender didStartProvisionalLoadForFrame:(WebFrame *)frame {
    if ([frame parentFrame] != nil)
        return;

    reloading_ = false;
    loading_ = true;
    [indicator_ startAnimation];
    [self reloadButtons];

    if (title_ != nil) {
        [title_ release];
        title_ = nil;
    }

    [self setTitle:@"Loading..."];

    WebView *webview = [webview_ webView];
    NSString *href = [webview mainFrameURL];
    [urls_ addObject:[NSURL URLWithString:href]];

    CGRect webrect = [scroller_ frame];
    webrect.size.height = 0;
    [webview_ setFrame:webrect];
}

- (void) _finishLoading {
    if (!reloading_) {
        loading_ = false;
        [indicator_ stopAnimation];
        [self reloadButtons];
    }
}

- (void) webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame {
    if ([frame parentFrame] != nil)
        return;
    [self _finishLoading];
}

- (void) webView:(WebView *)sender didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame {
    if ([frame parentFrame] != nil)
        return;
    [self _finishLoading];

    [self loadURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@?%@",
        [[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"error" ofType:@"html"]] absoluteString],
        [[error localizedDescription] stringByAddingPercentEscapes]
    ]]];
}

- (id) initWithBook:(RVBook *)book database:(Database *)database {
    if ((self = [super initWithBook:book]) != nil) {
        database_ = database;
        loading_ = false;

        struct CGRect bounds = [self bounds];

        UIImageView *pinstripe = [[[UIImageView alloc] initWithFrame:bounds] autorelease];
        [pinstripe setImage:[UIImage applicationImageNamed:@"pinstripe.png"]];
        [self addSubview:pinstripe];

        scroller_ = [[UIScroller alloc] initWithFrame:bounds];
        [self addSubview:scroller_];

        [scroller_ setScrollingEnabled:YES];
        [scroller_ setAdjustForContentSizeChange:YES];
        [scroller_ setClipsSubviews:YES];
        [scroller_ setAllowsRubberBanding:YES];
        [scroller_ setScrollDecelerationFactor:0.99];
        [scroller_ setDelegate:self];

        CGRect webrect = [scroller_ bounds];
        webrect.size.height = 0;

        webview_ = [[UIWebView alloc] initWithFrame:webrect];
        [scroller_ addSubview:webview_];

        [webview_ setTilingEnabled:YES];
        [webview_ setTileSize:CGSizeMake(webrect.size.width, 500)];
        [webview_ setAutoresizes:YES];
        [webview_ setDelegate:self];
        //[webview_ setEnabledGestures:2];

        CGSize indsize = [UIProgressIndicator defaultSizeForStyle:kUIProgressIndicatorStyleMediumWhite];
        indicator_ = [[UIProgressIndicator alloc] initWithFrame:CGRectMake(281, 42, indsize.width, indsize.height)];
        [indicator_ setStyle:kUIProgressIndicatorStyleMediumWhite];

        Package *package([database_ packageWithName:@"cydia"]);
        NSString *application = package == nil ? @"Cydia" : [NSString
            stringWithFormat:@"Cydia/%@",
            [package installed]
        ];

        WebView *webview = [webview_ webView];
        [webview setApplicationNameForUserAgent:application];
        [webview setFrameLoadDelegate:self];
        [webview setResourceLoadDelegate:self];
        [webview setUIDelegate:self];

        urls_ = [[NSMutableArray alloc] initWithCapacity:16];
    } return self;
}

- (void) _rightButtonClicked {
    reloading_ = true;
    [self reloadURL];
}

- (NSString *) rightButtonTitle {
    return loading_ ? @"" : @"Reload";
}

- (NSString *) title {
    return nil;
}

- (NSString *) backButtonTitle {
    return @"Browser";
}

- (void) setPageActive:(BOOL)active {
    if (active)
        [book_ addSubview:indicator_];
    else
        [indicator_ removeFromSuperview];
}

- (void) resetViewAnimated:(BOOL)animated {
}

- (void) setPushed:(bool)pushed {
    pushed_ = pushed;
}

@end
/* }}} */

@interface CYBook : RVBook <
    ProgressDelegate
> {
    _transient Database *database_;
    UIView *overlay_;
    UIProgressIndicator *indicator_;
    UITextLabel *prompt_;
    UIProgressBar *progress_;
    bool updating_;
}

- (id) initWithFrame:(CGRect)frame database:(Database *)database;
- (void) update;
- (BOOL) updating;

@end

/* Install View {{{ */
@interface InstallView : RVPage {
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

@implementation InstallView

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

    PackageTable *table = [[[PackageTable alloc]
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
    } return self;
}

- (void) reloadData {
    NSArray *packages = [database_ packages];

    [sections_ removeAllObjects];
    [filtered_ removeAllObjects];

    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:[packages count]];
    NSMutableDictionary *sections = [NSMutableDictionary dictionaryWithCapacity:32];

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

    [sections_ addObjectsFromArray:[sections allValues]];
    [sections_ sortUsingSelector:@selector(compareByName:)];

    [filtered sortUsingSelector:@selector(compareBySection:)];

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

    [list_ reloadData];
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
    else {
        [delegate_ updateData];
    }

    [book_ setTitle:[self title] forPage:self];
    [book_ reloadButtonsForPage:self];
}

- (NSString *) title {
    return editing_ ? @"Section Visibility" : @"Install by Section";
}

- (NSString *) backButtonTitle {
    return @"Sections";
}

- (NSString *) rightButtonTitle {
    return [sections_ count] == 0 ? nil : editing_ ? @"Done" : @"Edit";
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
    } return self;
}

- (void) reloadData {
    NSArray *packages = [database_ packages];

    [packages_ removeAllObjects];
    [sections_ removeAllObjects];

    for (size_t i(0); i != [packages count]; ++i) {
        Package *package([packages objectAtIndex:i]);

        if (
            [package installed] == nil && [package valid] && [package visible] ||
            [package upgradableAndEssential:NO]
        )
            [packages_ addObject:package];
    }

    [packages_ sortUsingSelector:@selector(compareForChanges:)];

    Section *upgradable = [[[Section alloc] initWithName:@"Available Upgrades"] autorelease];
    Section *section = nil;

    upgrades_ = 0;
    bool unseens = false;

    CFDateFormatterRef formatter = CFDateFormatterCreate(NULL, Locale_, kCFDateFormatterMediumStyle, kCFDateFormatterMediumStyle);

    for (size_t offset = 0, count = [packages_ count]; offset != count; ++offset) {
        Package *package = [packages_ objectAtIndex:offset];

        if ([package upgradableAndEssential:YES]) {
            ++upgrades_;
            [upgradable addToCount];
        } else {
            unseens = true;
            NSDate *seen = [package seen];

            NSString *name;

            if (seen == nil)
                name = [@"n/a ?" retain];
            else {
                name = (NSString *) CFDateFormatterCreateStringWithDate(NULL, formatter, (CFDateRef) seen);
            }

            if (section == nil || ![[section name] isEqualToString:name]) {
                section = [[[Section alloc] initWithName:name row:offset] autorelease];
                [sections_ addObject:section];
            }

            [name release];
            [section addToCount];
        }
    }

    CFRelease(formatter);

    if (unseens) {
        Section *last = [sections_ lastObject];
        size_t count = [last count];
        [packages_ removeObjectsInRange:NSMakeRange([packages_ count] - count, count)];
        [sections_ removeLastObject];
    }

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

- (NSString *) rightButtonTitle {
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
    PackageTable *table_;
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
#ifndef __OBJC2__
    [[field_ textTraits] setEditingDelegate:nil];
#endif
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

#ifndef __OBJC2__
    [delegate_ showKeyboard:show];
#endif
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

        /*UIImageView *pinstripe = [[[UIImageView alloc] initWithFrame:pageBounds] autorelease];
        [pinstripe setImage:[UIImage applicationImageNamed:@"pinstripe.png"]];
        [self addSubview:pinstripe];*/

        transition_ = [[UITransitionView alloc] initWithFrame:pageBounds];
        [self addSubview:transition_];

        advanced_ = [[UIPreferencesTable alloc] initWithFrame:pageBounds];

        [advanced_ setReusesTableCells:YES];
        [advanced_ setDataSource:self];
        [advanced_ reloadData];

        dimmed_ = [[UIView alloc] initWithFrame:pageBounds];
        CGColor dimmed(space_, 0, 0, 0, 0.5);
        [dimmed_ setBackgroundColor:dimmed];

        table_ = [[PackageTable alloc]
            initWithBook:book
            database:database
            title:nil
            filter:@selector(isVisiblySearchedForBy:)
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
        area.origin.y = 30;

        area.size.width =
#ifdef __OBJC2__
            8 +
#endif
            [self bounds].size.width - area.origin.x - 18;

        area.size.height = [UISearchField defaultHeight];

        field_ = [[UISearchField alloc] initWithFrame:area];

        GSFontRef font = GSFontCreateWithName("Helvetica", kGSFontTraitNone, 16);
        [field_ setFont:font];
        CFRelease(font);

        [field_ setPlaceholder:@"Package Names & Descriptions"];
        [field_ setDelegate:self];

#ifdef __OBJC2__
        [field_ setPaddingTop:3];
#else
        [field_ setPaddingTop:5];
#endif

        UITextTraits *traits = [field_ textTraits];
        [traits setAutoCapsType:0];
        [traits setAutoCorrectionType:1];
        [traits setReturnKeyType:6];

#ifndef __OBJC2__
        [traits setEditingDelegate:self];
#endif

        CGRect accrect = {{0, 6}, {6 + cnfrect.size.width + 6 + area.size.width + 6, area.size.height + 30}};

        accessory_ = [[UIView alloc] initWithFrame:accrect];
        [accessory_ addSubview:field_];

        /*UIPushButton *configure = [[[UIPushButton alloc] initWithFrame:cnfrect] autorelease];
        [configure setShowPressFeedback:YES];
        [configure setImage:[UIImage applicationImageNamed:@"advanced.png"]];
        [configure addTarget:self action:@selector(configurePushed) forEvents:1];
        [accessory_ addSubview:configure];*/
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

@implementation CYBook

- (void) dealloc {
    [overlay_ release];
    [indicator_ release];
    [prompt_ release];
    [progress_ release];
    [super dealloc];
}

- (NSString *) getTitleForPage:(RVPage *)page {
    return Simplify([super getTitleForPage:page]);
}

- (BOOL) updating {
    return updating_;
}

- (void) update {
    [navbar_ setPrompt:@""];
    [navbar_ addSubview:overlay_];
    [indicator_ startAnimation];
    [prompt_ setText:@"Updating Database..."];
    [progress_ setProgress:0];

    updating_ = true;

    [NSThread
        detachNewThreadSelector:@selector(_update)
        toTarget:self
        withObject:nil
    ];
}

- (void) _update_ {
    updating_ = false;

    [overlay_ removeFromSuperview];
    [indicator_ stopAnimation];
    [delegate_ reloadData];

    [self setPrompt:[NSString stringWithFormat:@"Last Updated: %@", GetLastUpdate()]];
}

- (id) initWithFrame:(CGRect)frame database:(Database *)database {
    if ((self = [super initWithFrame:frame]) != nil) {
        database_ = database;

        if (Advanced_)
            [navbar_ setBarStyle:1];

        CGRect ovrrect = [navbar_ bounds];
        ovrrect.size.height = ([UINavigationBar defaultSizeWithPrompt].height - [UINavigationBar defaultSize].height);

        overlay_ = [[UIView alloc] initWithFrame:ovrrect];

        UIProgressIndicatorStyle style = Advanced_ ?
            kUIProgressIndicatorStyleSmallWhite :
            kUIProgressIndicatorStyleSmallBlack;

        CGSize indsize = [UIProgressIndicator defaultSizeForStyle:style];
        unsigned indoffset = (ovrrect.size.height - indsize.height) / 2;
        CGRect indrect = {{indoffset, indoffset}, indsize};

        indicator_ = [[UIProgressIndicator alloc] initWithFrame:indrect];
        [indicator_ setStyle:style];
        [overlay_ addSubview:indicator_];

        CGSize prmsize = {200, indsize.width + 4};

        CGRect prmrect = {{
            indoffset * 2 + indsize.width,
#ifdef __OBJC2__
            -1 +
#endif
            (ovrrect.size.height - prmsize.height) / 2
        }, prmsize};

        GSFontRef font = GSFontCreateWithName("Helvetica", kGSFontTraitNone, 12);

        prompt_ = [[UITextLabel alloc] initWithFrame:prmrect];

        [prompt_ setColor:(Advanced_ ? White_ : Blueish_)];
        [prompt_ setBackgroundColor:Clear_];
        [prompt_ setFont:font];

        CFRelease(font);

        [overlay_ addSubview:prompt_];

        CGSize prgsize = {75, 100};

        CGRect prgrect = {{
            ovrrect.size.width - prgsize.width - 10,
            (ovrrect.size.height - prgsize.height) / 2
        } , prgsize};

        progress_ = [[UIProgressBar alloc] initWithFrame:prgrect];
        [progress_ setStyle:0];
        [overlay_ addSubview:progress_];
    } return self;
}

- (void) _update {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    Status status;
    status.setDelegate(self);

    [database_ updateWithStatus:status];

    [self
        performSelectorOnMainThread:@selector(_update_)
        withObject:nil
        waitUntilDone:NO
    ];

    [pool release];
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
}

- (void) addProgressOutput:(NSString *)output {
    [self
        performSelectorOnMainThread:@selector(_addProgressOutput:)
        withObject:output
        waitUntilDone:YES
    ];
}

- (void) alertSheet:(UIAlertSheet *)sheet buttonClicked:(int)button {
    [sheet dismiss];
}

- (void) _setProgressTitle:(NSString *)title {
    [prompt_ setText:[title stringByAppendingString:@"..."]];
}

- (void) _addProgressOutput:(NSString *)output {
}

@end

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
    UIButtonBar *buttonbar_;

    ConfirmationView *confirm_;

    NSMutableArray *essential_;
    NSMutableArray *broken_;

    Database *database_;
    ProgressView *progress_;

    unsigned tag_;

    UIKeyboard *keyboard_;
    UIProgressHUD *hud_;

    InstallView *install_;
    ChangesView *changes_;
    ManageView *manage_;
    SearchView *search_;
}

@end

@implementation Cydia

- (void) _loaded {
    if ([broken_ count] != 0) {
        int count = [broken_ count];

        UIAlertSheet *sheet = [[[UIAlertSheet alloc]
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

        UIAlertSheet *sheet = [[[UIAlertSheet alloc]
            initWithTitle:[NSString stringWithFormat:@"%d Essential Upgrade%@", count, (count == 1 ? @"" : @"s")]
            buttons:[NSArray arrayWithObjects:@"Upgrade Essential", @"Ignore (Temporary)", nil]
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
    for (int i(0), e([packages count]); i != e; ++i) {
        Package *package = [packages objectAtIndex:i];
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

    /*if ([packages count] == 0);
    else if (Loaded_)*/
        [self _loaded];
    /*else {
        Loaded_ = YES;
        [book_ update];
    }*/

    /*[hud show:NO];
    [hud removeFromSuperview];*/
}

- (void) _saveConfig {
    if (Changed_) {
        _assert([Metadata_ writeToFile:@"/var/lib/cydia/metadata.plist" atomically:YES] == YES);
        Changed_ = false;
    }
}

- (void) updateData {
    [self _saveConfig];

    /* XXX: this is just stupid */
    if (tag_ != 2)
        [install_ reloadData];
    if (tag_ != 3)
        [changes_ reloadData];
    if (tag_ != 5)
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
        title:@"Updating Sources..."
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

- (void) perform {
    [database_ prepare];

    if ([database_ cache]->BrokenCount() == 0)
        confirm_ = [[ConfirmationView alloc] initWithView:underlay_ database:database_ delegate:self];
    else {
        NSMutableArray *broken = [NSMutableArray arrayWithCapacity:16];
        NSArray *packages = [database_ packages];

        for (size_t i(0); i != [packages count]; ++i) {
            Package *package = [packages objectAtIndex:i];
            if ([package broken])
                [broken addObject:[package name]];
        }

        UIAlertSheet *sheet = [[[UIAlertSheet alloc]
            initWithTitle:[NSString stringWithFormat:@"%d Broken Packages", [database_ cache]->BrokenCount()]
            buttons:[NSArray arrayWithObjects:@"Okay", nil]
            defaultButtonIndex:0
            delegate:self
            context:@"broken"
        ] autorelease];

        [sheet setBodyText:[NSString stringWithFormat:@"The following packages have unmet dependencies:\n\n%@", [broken componentsJoinedByString:@"\n"]]];
        [sheet popupAlertAnimated:YES];

        [self _reloadData];
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
    @synchronized (self) {
        [confirm_ release];
        confirm_ = nil;
        [self _reloadData];
    }
}

- (void) confirm {
    [overlay_ removeFromSuperview];
    reload_ = true;

    [progress_
        detachNewThreadSelector:@selector(perform)
        toTarget:database_
        withObject:nil
        title:@"Running..."
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
        title:@"Bootstrap Install..."
    ];
}

- (void) progressViewIsComplete:(ProgressView *)progress {
    @synchronized (self) {
        [self _reloadData];

        if (confirm_ != nil) {
            [underlay_ addSubview:overlay_];
            [confirm_ removeFromSuperview];
            [confirm_ release];
            confirm_ = nil;
        }
    }
}

- (void) setPage:(RVPage *)page {
    [page resetViewAnimated:NO];
    [page setDelegate:self];
    [book_ setPage:page];
}

- (RVPage *) _pageForURL:(NSURL *)url withClass:(Class)_class {
    BrowserView *browser = [[[_class alloc] initWithBook:book_ database:database_] autorelease];
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
        [install_ resetView];

    switch (tag) {
        case 1: [self _setHomePage]; break;

        case 2: [self setPage:install_]; break;
        case 3: [self setPage:changes_]; break;
        case 4: [self setPage:manage_]; break;
        case 5: [self setPage:search_]; break;

        default: _assert(false);
    }

    tag_ = tag;
}

- (void) fixSpringBoard {
    pid_t pid = ExecFork();
    if (pid == 0) {
        sleep(1);

        if (pid_t child = fork()) {
            waitpid(child, NULL, 0);
        } else {
            execlp("launchctl", "launchctl", "unload", SpringBoard_, NULL);
            perror("launchctl unload");
            exit(0);
        }

        execlp("launchctl", "launchctl", "load", SpringBoard_, NULL);
        perror("launchctl load");
        exit(0);
    }
}

- (void) applicationWillSuspend {
    [database_ clean];

    if (reload_) {
#ifndef __OBJC2__
        [self fixSpringBoard];
#endif
}

    [super applicationWillSuspend];
}

- (void) askForSettings {
    UIAlertSheet *role = [[[UIAlertSheet alloc]
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

    buttonbar_ = [[UIButtonBar alloc]
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
    [[UIKeyboardImpl sharedInstance] setSoundsEnabled:(Sounds_Keyboard_ ? YES : NO)];
    [overlay_ addSubview:keyboard_];

    install_ = [[InstallView alloc] initWithBook:book_ database:database_];
    changes_ = [[ChangesView alloc] initWithBook:book_ database:database_];
    search_ = [[SearchView alloc] initWithBook:book_ database:database_];

    manage_ = (ManageView *) [[self
        _pageForURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"manage" ofType:@"html"]]
        withClass:[ManageView class]
    ] retain];

    if (!bootstrap_)
        [underlay_ addSubview:overlay_];

    [self reloadData];

    if (bootstrap_)
        [self bootstrap];
    else
        [self _setHomePage];
}

- (void) alertSheet:(UIAlertSheet *)sheet buttonClicked:(int)button {
    NSString *context = [sheet context];
    if ([context isEqualToString:@"fixhalf"])
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
    else if ([context isEqualToString:@"role"]) {
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
    } else if ([context isEqualToString:@"upgrade"])
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
                Ignored_ = YES;
            break;

            default:
                _assert(false);
        }

    [sheet dismiss];
}

- (void) reorganize {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    system("/usr/libexec/cydia/free.sh");
    [self performSelectorOnMainThread:@selector(finish) withObject:nil waitUntilDone:NO];
    [pool release];
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

- (void) applicationDidFinishLaunching:(id)unused {
    Font12_ = [[UIFont systemFontOfSize:12] retain];
    Font12Bold_ = [[UIFont boldSystemFontOfSize:12] retain];
    Font14_ = [[UIFont systemFontOfSize:14] retain];
    Font18Bold_ = [[UIFont boldSystemFontOfSize:18] retain];
    Font22Bold_ = [[UIFont boldSystemFontOfSize:22] retain];

    _assert(pkgInitConfig(*_config));
    _assert(pkgInitSystem(*_config, _system));

    confirm_ = nil;
    tag_ = 1;

    essential_ = [[NSMutableArray alloc] initWithCapacity:4];
    broken_ = [[NSMutableArray alloc] initWithCapacity:4];

    CGRect screenrect = [UIHardware fullScreenApplicationContentRect];
    window_ = [[UIWindow alloc] initWithContentRect:screenrect];

    [window_ orderFront:self];
    [window_ makeKey:self];
    [window_ _setHidden:NO];

    database_ = [[Database alloc] init];
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
        readlink("/usr/share", NULL, 0) == -1 && errno == EINVAL
    ) {
        [self setIdleTimerDisabled:YES];

        hud_ = [self addProgressHUD];
        [hud_ setText:@"Reorganizing\n\nWill Automatically\nRestart When Done"];

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

- (void) slideUp:(UIAlertSheet *)alert {
    if (Advanced_)
        [alert presentSheetFromButtonBar:buttonbar_];
    else
        [alert presentSheetInView:overlay_];
}

@end

void AddPreferences(NSString *plist) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

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

    [pool release];
}

/*IMP alloc_;
id Alloc_(id self, SEL selector) {
    id object = alloc_(self, selector);
    fprintf(stderr, "[%s]A-%p\n", self->isa->name, object);
    return object;
}*/

/*IMP dealloc_;
id Dealloc_(id self, SEL selector) {
    id object = dealloc_(self, selector);
    fprintf(stderr, "[%s]D-%p\n", self->isa->name, object);
    return object;
}*/

int main(int argc, char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    bootstrap_ = argc > 1 && strcmp(argv[1], "--bootstrap") == 0;

    Home_ = NSHomeDirectory();

    {
        NSString *plist = [Home_ stringByAppendingString:@"/Library/Preferences/com.apple.preferences.sounds.plist"];
        if (NSDictionary *sounds = [NSDictionary dictionaryWithContentsOfFile:plist])
            if (NSNumber *keyboard = [sounds objectForKey:@"keyboard"])
                Sounds_Keyboard_ = [keyboard boolValue];
    }

    setuid(0);
    setgid(0);

    if (unlink("/var/cache/apt/pkgcache.bin") == -1)
        _assert(errno == ENOENT);
    if (unlink("/var/cache/apt/srcpkgcache.bin") == -1)
        _assert(errno == ENOENT);

    /*Method alloc = class_getClassMethod([NSObject class], @selector(alloc));
    alloc_ = alloc->method_imp;
    alloc->method_imp = (IMP) &Alloc_;*/

    /*Method dealloc = class_getClassMethod([NSObject class], @selector(dealloc));
    dealloc_ = dealloc->method_imp;
    dealloc->method_imp = (IMP) &Dealloc_;*/

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

    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char *machine = new char[size];
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    Machine_ = machine;

    if (CFMutableDictionaryRef dict = IOServiceMatching("IOPlatformExpertDevice"))
        if (io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault, dict)) {
            if (CFTypeRef serial = IORegistryEntryCreateCFProperty(service, CFSTR(kIOPlatformSerialNumberKey), kCFAllocatorDefault, 0)) {
                SerialNumber_ = strdup(CFStringGetCStringPtr((CFStringRef) serial, CFStringGetSystemEncoding()));
                CFRelease(serial);
            }

            IOObjectRelease(service);
        }

    /*AddPreferences(@"/Applications/Preferences.app/Settings-iPhone.plist");
    AddPreferences(@"/Applications/Preferences.app/Settings-iPod.plist");*/

    if ((Metadata_ = [[NSMutableDictionary alloc] initWithContentsOfFile:@"/var/lib/cydia/metadata.plist"]) == NULL)
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

    if (access("/User", F_OK) != 0)
        system("/usr/libexec/cydia/firmware.sh");

    Locale_ = CFLocaleCopyCurrent();
    space_ = CGColorSpaceCreateDeviceRGB();

    Blue_.Set(space_, 0.2, 0.2, 1.0, 1.0);
    Blueish_.Set(space_, 0x19/255.f, 0x32/255.f, 0x50/255.f, 1.0);
    Black_.Set(space_, 0.0, 0.0, 0.0, 1.0);
    Clear_.Set(space_, 0.0, 0.0, 0.0, 0.0);
    Red_.Set(space_, 1.0, 0.0, 0.0, 1.0);
    White_.Set(space_, 1.0, 1.0, 1.0, 1.0);
    Gray_.Set(space_, 0.4, 0.4, 0.4, 1.0);

    SectionMap_ = [[[NSDictionary alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Sections" ofType:@"plist"]] autorelease];

    int value = UIApplicationMain(argc, argv, [Cydia class]);

    CGColorSpaceRelease(space_);
    CFRelease(Locale_);

    [pool release];
    return value;
}
