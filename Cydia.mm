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

/* #include Directives {{{ */
#include <CoreGraphics/CoreGraphics.h>
#include <GraphicsServices/GraphicsServices.h>
#include <Foundation/Foundation.h>
#include <UIKit/UIKit.h>
#include <WebCore/DOMHTML.h>

#include <WebKit/WebFrame.h>
#include <WebKit/WebView.h>

#include <objc/objc.h>
#include <objc/runtime.h>

#include <sstream>
#include <ext/stdio_filebuf.h>

#include <apt-pkg/acquire.h>
#include <apt-pkg/acquire-item.h>
#include <apt-pkg/algorithms.h>
#include <apt-pkg/cachefile.h>
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

#include <stdio.h>
#include <stdlib.h>

#include <errno.h>
#include <pcre.h>
#include <string.h>
/* }}} */
/* Extension Keywords {{{ */
#define _trace() fprintf(stderr, "_trace()@%s:%u[%s]\n", __FILE__, __LINE__, __FUNCTION__)

#define _assert(test) do \
    if (!(test)) { \
        fprintf(stderr, "_assert(%d:%s)@%s:%u[%s]\n", errno, #test, __FILE__, __LINE__, __FUNCTION__); \
        exit(-1); \
    } \
while (false)

#define _not(type) ((type) ~ (type) 0)

#define _transient
/* }}} */

/* Miscellaneous Messages {{{ */
@interface NSString (Cydia)
- (NSString *) stringByAddingPercentEscapes;
- (NSString *) stringByReplacingCharacter:(unsigned short)arg0 withCharacter:(unsigned short)arg1;
@end
/* }}} */
/* External Constants {{{ */
extern NSString *kUIButtonBarButtonAction;
extern NSString *kUIButtonBarButtonInfo;
extern NSString *kUIButtonBarButtonInfoOffset;
extern NSString *kUIButtonBarButtonSelectedInfo;
extern NSString *kUIButtonBarButtonStyle;
extern NSString *kUIButtonBarButtonTag;
extern NSString *kUIButtonBarButtonTarget;
extern NSString *kUIButtonBarButtonTitle;
extern NSString *kUIButtonBarButtonTitleVerticalHeight;
extern NSString *kUIButtonBarButtonTitleWidth;
extern NSString *kUIButtonBarButtonType;
/* }}} */

#if 1
#define $_
#define _$
#else
#define $_ fprintf(stderr, "+");_trace();
#define _$ fprintf(stderr, "-");_trace();
#endif

/* iPhoneOS 2.0 Compatibility {{{ */
#ifdef __OBJC2__
@interface UICGColor : NSObject {
}

- (id) initWithCGColor:(CGColorRef)color;
@end

@interface UIFont {
}

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

OBJC_EXPORT const char *class_getName(Class cls);

/* Reset View (UIView) {{{ */
@interface UIView (RVBook)
- (void) resetViewAnimated:(BOOL)animated;
- (void) clearView;
@end

@implementation UIView (RVBook)

- (void) resetViewAnimated:(BOOL)animated {
    fprintf(stderr, "%s\n", class_getName(self->isa));
    _assert(false);
}

- (void) clearView {
    fprintf(stderr, "%s\n", class_getName(self->isa));
    _assert(false);
}

@end
/* }}} */
/* Reset View (UITable) {{{ */
@interface UITable (RVBook)
- (void) resetViewAnimated:(BOOL)animated;
- (void) clearView;
@end

@implementation UITable (RVBook)

- (void) resetViewAnimated:(BOOL)animated {
    [self selectRow:-1 byExtendingSelection:NO withFade:animated];
}

- (void) clearView {
    [self clearAllData];
}

@end
/* }}} */
/* Reset View (UISectionList) {{{ */
@interface UISectionList (RVBook)
- (void) resetViewAnimated:(BOOL)animated;
- (void) clearView;
@end

@implementation UISectionList (RVBook)

- (void) resetViewAnimated:(BOOL)animated {
    [[self table] resetViewAnimated:animated];
}

- (void) clearView {
    [[self table] clearView];
}

@end
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
        return [NSString
            stringWithCString:(data_ + matches_[match * 2])
            length:(matches_[match * 2 + 1] - matches_[match * 2])
        ];
    }

    bool operator ()(const char *data, size_t size) {
        data_ = data;
        return pcre_exec(code_, study_, data, size, 0, 0, matches_, (capture_ + 1) * 3) >= 0;
    }
};
/* }}} */
/* Mime Addresses {{{ */
Pcre email_r("^\"?(.*)\"? <([^>]*)>$");

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

        if (email_r(data, size)) {
            name_ = [email_r[1] retain];
            email_ = [email_r[2] retain];
        } else {
            name_ = [[NSString stringWithCString:data length:size] retain];
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

/* Random Global Variables {{{ */
static const int PulseInterval_ = 50000;

static CGColor Black_;
static CGColor Clear_;
static CGColor Red_;
static CGColor White_;

static NSString *Home_;
static BOOL Sounds_Keyboard_;

const char *Firmware_ = NULL;
const char *Machine_ = NULL;
const char *SerialNumber_ = NULL;

unsigned Major_;
unsigned Minor_;
unsigned BugFix_;

CGColorSpaceRef space_;

#define FW_LEAST(major, minor, bugfix) \
    (major < Major_ || major == Major_ && \
        (minor < Minor_ || minor == Minor_ && \
            bugfix <= BugFix_))

bool bootstrap_;
bool restart_;

static NSMutableDictionary *Metadata_;
static NSMutableDictionary *Packages_;
static NSDate *now_;

NSString *GetLastUpdate() {
    NSDate *update = [Metadata_ objectForKey:@"LastUpdate"];

    if (update == nil)
        return @"Never or Unknown";

    CFLocaleRef locale = CFLocaleCopyCurrent();
    CFDateFormatterRef formatter = CFDateFormatterCreate(NULL, locale, kCFDateFormatterMediumStyle, kCFDateFormatterMediumStyle);
    CFStringRef formatted = CFDateFormatterCreateStringWithDate(NULL, formatter, (CFDateRef) update);

    CFRelease(formatter);
    CFRelease(locale);

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
/* }}} */

@class Package;
@class Source;

@protocol ProgressDelegate
- (void) setProgressError:(NSString *)error;
- (void) setProgressTitle:(NSString *)title;
- (void) setProgressPercent:(float)percent;
- (void) addProgressOutput:(NSString *)output;
@end

@protocol CydiaDelegate
- (void) installPackage:(Package *)package;
- (void) removePackage:(Package *)package;
- (void) slideUp:(UIAlertSheet *)alert;
- (void) distUpgrade;
@end

/* Status Delegation {{{ */
class Status :
    public pkgAcquireStatus
{
  private:
    _transient id<ProgressDelegate> delegate_;

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
        [delegate_ setProgressTitle:[NSString stringWithCString:("Downloading " + item.ShortDesc).c_str()]];
    }

    virtual void Done(pkgAcquire::ItemDesc &item) {
    }

    virtual void Fail(pkgAcquire::ItemDesc &item) {
        if (
            item.Owner->Status == pkgAcquire::Item::StatIdle ||
            item.Owner->Status == pkgAcquire::Item::StatDone
        )
            return;

        [delegate_ setProgressError:[NSString stringWithCString:item.Owner->ErrorText.c_str()]];
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
        [delegate_ setProgressTitle:[NSString stringWithCString:Op.c_str()]];
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
    pkgRecords *records_;
    pkgProblemResolver *resolver_;
    pkgAcquire *fetcher_;
    FileFd *lock_;
    SPtr<pkgPackageManager> manager_;
    pkgSourceList *list_;

    NSMutableDictionary *sources_;
    NSMutableArray *packages_;

    _transient id delegate_;
    Status status_;
    Progress progress_;
    int statusfd_;
}

- (void) _readStatus:(NSNumber *)fd;
- (void) _readOutput:(NSNumber *)fd;

- (Package *) packageWithName:(NSString *)name;

- (Database *) init;
- (pkgCacheFile &) cache;
- (pkgRecords *) records;
- (pkgProblemResolver *) resolver;
- (pkgAcquire &) fetcher;
- (NSArray *) packages;
- (void) reloadData;

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

    BOOL trusted_;
}

- (Source *) initWithMetaIndex:(metaIndex *)index;

- (BOOL) trusted;

- (NSString *) uri;
- (NSString *) distribution;
- (NSString *) type;

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

    [super dealloc];
}

- (Source *) initWithMetaIndex:(metaIndex *)index {
    if ((self = [super init]) != nil) {
        trusted_ = index->IsTrusted();

        uri_ = [[NSString stringWithCString:index->GetURI().c_str()] retain];
        distribution_ = [[NSString stringWithCString:index->GetDist().c_str()] retain];
        type_ = [[NSString stringWithCString:index->GetType()] retain];

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
                    defaultIcon_ = [[NSString stringWithCString:value.c_str()] retain];
                else if (name == "Description")
                    description_ = [[NSString stringWithCString:value.c_str()] retain];
                else if (name == "Label")
                    label_ = [[NSString stringWithCString:value.c_str()] retain];
                else if (name == "Origin")
                    origin_ = [[NSString stringWithCString:value.c_str()] retain];
                else if (name == "Version")
                    version_ = [[NSString stringWithCString:value.c_str()] retain];
            }
        }
    } return self;
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

- (NSString *) description {
    return description_;
}

- (NSString *) label {
    return label_;
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
            return [NSString stringWithCString:value length:(line - value)];
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

    NSString *latest_;
    NSString *installed_;

    NSString *id_;
    NSString *name_;
    NSString *tagline_;
    NSString *icon_;
    NSString *website_;
}

- (Package *) initWithIterator:(pkgCache::PkgIterator)iterator database:(Database *)database version:(pkgCache::VerIterator)version file:(pkgCache::VerFileIterator)file;
+ (Package *) packageWithIterator:(pkgCache::PkgIterator)iterator database:(Database *)database;

- (NSString *) section;
- (Address *) maintainer;
- (size_t) size;
- (NSString *) description;
- (NSString *) index;

- (NSDate *) seen;

- (NSString *) latest;
- (NSString *) installed;
- (BOOL) upgradable;
- (BOOL) essential;
- (BOOL) broken;

- (NSString *) id;
- (NSString *) name;
- (NSString *) tagline;
- (NSString *) icon;
- (NSString *) website;

- (Source *) source;

- (BOOL) matches:(NSString *)text;

- (NSComparisonResult) compareByName:(Package *)package;
- (NSComparisonResult) compareBySection:(Package *)package;
- (NSComparisonResult) compareBySectionAndName:(Package *)package;
- (NSComparisonResult) compareForChanges:(Package *)package;

- (void) install;
- (void) remove;

- (NSNumber *) isSearchedForBy:(NSString *)search;
- (NSNumber *) isInstalledInSection:(NSString *)section;
- (NSNumber *) isUninstalledInSection:(NSString *)section;

@end

@implementation Package

- (void) dealloc {
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

    [source_ release];

    [super dealloc];
}

- (Package *) initWithIterator:(pkgCache::PkgIterator)iterator database:(Database *)database version:(pkgCache::VerIterator)version file:(pkgCache::VerFileIterator)file {
    if ((self = [super init]) != nil) {
        iterator_ = iterator;
        database_ = database;

        version_ = version;
        file_ = file;

        pkgRecords::Parser *parser = &[database_ records]->Lookup(file_);

        const char *begin, *end;
        parser->GetRec(begin, end);

        latest_ = [[NSString stringWithCString:version_.VerStr()] retain];
        installed_ = iterator_.CurrentVer().end() ? nil : [[NSString stringWithCString:iterator_.CurrentVer().VerStr()] retain];

        id_ = [[[NSString stringWithCString:iterator_.Name()] lowercaseString] retain];
        name_ = Scour("Name", begin, end);
        if (name_ != nil)
            name_ = [name_ retain];
        tagline_ = [[NSString stringWithCString:parser->ShortDesc().c_str()] retain];
        icon_ = Scour("Icon", begin, end);
        if (icon_ != nil)
            icon_ = [icon_ retain];
        website_ = Scour("Website", begin, end);
        if (website_ != nil)
            website_ = [website_ retain];

        source_ = [[database_ getSource:file_.File()] retain];

        NSMutableDictionary *metadata = [Packages_ objectForKey:id_];
        if (metadata == nil || [metadata count] == 0) {
            metadata = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                now_, @"FirstSeen",
            nil];

            [Packages_ setObject:metadata forKey:id_];
        }
    } return self;
}

+ (Package *) packageWithIterator:(pkgCache::PkgIterator)iterator database:(Database *)database {
    for (pkgCache::VerIterator version = iterator.VersionList(); !version.end(); ++version)
        for (pkgCache::VerFileIterator file = version.FileList(); !file.end(); ++file)
            return [[[Package alloc]
                initWithIterator:iterator 
                database:database
                version:version
                file:file]
            autorelease];
    return nil;
}

- (NSString *) section {
    const char *section = iterator_.Section();
    return section == NULL ? nil : [[NSString stringWithCString:section] stringByReplacingCharacter:'_' withCharacter:' '];
}

- (Address *) maintainer {
    pkgRecords::Parser *parser = &[database_ records]->Lookup(file_);
    return [Address addressWithString:[NSString stringWithCString:parser->Maintainer().c_str()]];
}

- (size_t) size {
    return version_->InstalledSize;
}

- (NSString *) description {
    pkgRecords::Parser *parser = &[database_ records]->Lookup(file_);
    NSString *description([NSString stringWithCString:parser->LongDesc().c_str()]);

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

- (BOOL) upgradable {
    if (NSString *installed = [self installed])
        return [[self latest] compare:installed] != NSOrderedSame ? YES : NO;
    else
        return [self essential];
}

- (BOOL) essential {
    return (iterator_->Flags & pkgCache::Flag::Essential) == 0 ? NO : YES;
}

- (BOOL) broken {
    return (*[database_ cache])[iterator_].InstBroken();
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

- (Source *) source {
    return source_;
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
        NSComparisonResult result = [lhs compare:rhs];
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
    BOOL lhs = [self upgradable];
    BOOL rhs = [package upgradable];

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

- (NSNumber *) isSearchedForBy:(NSString *)search {
    return [NSNumber numberWithBool:[self matches:search]];
}

- (NSNumber *) isInstalledInSection:(NSString *)section {
    return [NSNumber numberWithBool:([self installed] != nil && (section == nil || [section isEqualToString:[self section]]))];
}

- (NSNumber *) isUninstalledInSection:(NSString *)section {
    return [NSNumber numberWithBool:([self installed] == nil && (section == nil || [section isEqualToString:[self section]]))];
}

@end
/* }}} */
/* Section Class {{{ */
@interface Section : NSObject {
    NSString *name_;
    size_t row_;
    size_t count_;
}

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

- (void) _readStatus:(NSNumber *)fd {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    __gnu_cxx::stdio_filebuf<char> ib([fd intValue], std::ios::in);
    std::istream is(&ib);
    std::string line;

    const char *error;
    int offset;
    pcre *code = pcre_compile("^([^:]*):([^:]*):([^:]*):(.*)$", 0, &error, &offset, NULL);

    pcre_extra *study = NULL;
    int capture;
    pcre_fullinfo(code, study, PCRE_INFO_CAPTURECOUNT, &capture);
    int matches[(capture + 1) * 3];

    while (std::getline(is, line)) {
        const char *data(line.c_str());

        _assert(pcre_exec(code, study, data, line.size(), 0, 0, matches, sizeof(matches) / sizeof(matches[0])) >= 0);

        std::istringstream buffer(line.substr(matches[6], matches[7] - matches[6]));
        float percent;
        buffer >> percent;
        [delegate_ setProgressPercent:(percent / 100)];

        NSString *string = [NSString stringWithCString:(data + matches[8]) length:(matches[9] - matches[8])];
        std::string type(line.substr(matches[2], matches[3] - matches[2]));

        if (type == "pmerror")
            [delegate_ setProgressError:string];
        else if (type == "pmstatus")
            [delegate_ setProgressTitle:string];
        else if (type == "pmconffile")
            ;
        else _assert(false);
    }

    [pool release];
    _assert(false);
}

- (void) _readOutput:(NSNumber *)fd {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    __gnu_cxx::stdio_filebuf<char> ib([fd intValue], std::ios::in);
    std::istream is(&ib);
    std::string line;

    while (std::getline(is, line))
        [delegate_ addProgressOutput:[NSString stringWithCString:line.c_str()]];

    [pool release];
    _assert(false);
}

- (Package *) packageWithName:(NSString *)name {
    pkgCache::PkgIterator iterator(cache_->FindPkg([name UTF8String]));
    return iterator.end() ? nil : [Package packageWithIterator:iterator database:self];
}

- (Database *) init {
    if ((self = [super init]) != nil) {
        records_ = NULL;
        resolver_ = NULL;
        fetcher_ = NULL;
        lock_ = NULL;

        sources_ = [[NSMutableDictionary dictionaryWithCapacity:16] retain];
        packages_ = [[NSMutableArray arrayWithCapacity:16] retain];

        int fds[2];

        _assert(pipe(fds) != -1);
        statusfd_ = fds[1];

        [NSThread
            detachNewThreadSelector:@selector(_readStatus:)
            toTarget:self
            withObject:[[NSNumber numberWithInt:fds[0]] retain]
        ];

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

- (void) reloadData {
    _error->Discard();
    delete list_;
    manager_ = NULL;
    delete lock_;
    delete fetcher_;
    delete resolver_;
    delete records_;
    cache_.Close();

    if (!cache_.Open(progress_, true)) {
        fprintf(stderr, "repairing corrupted database...\n");
        _error->Discard();
        [self updateWithStatus:status_];
        _assert(cache_.Open(progress_, true));
    }

    now_ = [[NSDate date] retain];

    records_ = new pkgRecords(cache_);
    resolver_ = new pkgProblemResolver(cache_);
    fetcher_ = new pkgAcquire(&status_);
    lock_ = NULL;

    list_ = new pkgSourceList();
    _assert(list_->ReadMainList());

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
            if ([package source] != nil || [package installed] != nil)
                [packages_ addObject:package];
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
    if (fetcher_->Run(PulseInterval_) != pkgAcquire::Continue)
        return;

    _system->UnLock();
    pkgPackageManager::OrderResult result = manager_->DoInstall(statusfd_);

    if (result == pkgPackageManager::Failed)
        return;
    if (_error->PendingError())
        return;
    if (result != pkgPackageManager::Completed)
        return;
}

- (void) upgrade {
    _assert(cache_->DelCount() == 0 && cache_->InstCount() == 0);
    _assert(pkgApplyStatus(cache_));

    if (cache_->BrokenCount() != 0) {
        _assert(pkgFixBroken(cache_));
        _assert(cache_->BrokenCount() == 0);
        _assert(pkgMinimizeUpgrade(cache_));
    }

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

/* RVPage Interface {{{ */
@class RVBook;

@interface RVPage : UIView {
    _transient RVBook *book_;
    _transient id delegate_;
}

- (NSString *) title;
- (NSString *) backButtonTitle;
- (NSString *) rightButtonTitle;
- (NSString *) leftButtonTitle;
- (UIView *) accessoryView;

- (void) _rightButtonClicked;
- (void) _leftButtonClicked;

- (void) setPageActive:(BOOL)active;
- (void) resetViewAnimated:(BOOL)animated;

- (void) setTitle:(NSString *)title;
- (void) setBackButtonTitle:(NSString *)title;

- (void) reloadButtons;
- (void) reloadData;

- (id) initWithBook:(RVBook *)book;

- (void) setDelegate:(id)delegate;

@end
/* }}} */
/* Reset View {{{ */
@protocol RVDelegate
- (void) setPageActive:(BOOL)active with:(id)object;
- (void) resetViewAnimated:(BOOL)animated with:(id)object;
- (void) reloadDataWith:(id)object;
@end

@interface RVBook : UIView {
    NSMutableArray *pages_;
    UINavigationBar *navbar_;
    UITransitionView *transition_;
    BOOL resetting_;
    _transient id delegate_;
}

- (id) initWithFrame:(CGRect)frame;
- (void) setDelegate:(id)delegate;

- (void) setPage:(RVPage *)page;

- (void) pushPage:(RVPage *)page;
- (void) popPages:(unsigned)pages;

- (void) setPrompt:(NSString *)prompt;

- (void) resetViewAnimated:(BOOL)animated;
- (void) resetViewAnimated:(BOOL)animated toPage:(RVPage *)page;

- (void) setTitle:(NSString *)title forPage:(RVPage *)page;
- (void) setBackButtonTitle:(NSString *)title forPage:(RVPage *)page;
- (void) reloadButtonsForPage:(RVPage *)page;

- (void) reloadData;

- (CGRect) pageBounds;

@end

@implementation RVBook

- (void) dealloc {
    [navbar_ setDelegate:nil];

    [pages_ release];
    [navbar_ release];
    [transition_ release];
    [super dealloc];
}

- (void) navigationBar:(UINavigationBar *)navbar buttonClicked:(int)button {
    _assert([pages_ count] != 0);
    RVPage *page = [pages_ lastObject];
    switch (button) {
        case 0: [page _rightButtonClicked]; break;
        case 1: [page _leftButtonClicked]; break;
    }
}

- (void) navigationBar:(UINavigationBar *)navbar poppedItem:(UINavigationItem *)item {
    _assert([pages_ count] != 0);
    if (!resetting_)
        [[pages_ lastObject] setPageActive:NO];
    [pages_ removeLastObject];
    if (!resetting_)
        [self resetViewAnimated:YES toPage:[pages_ lastObject]];
}

- (id) initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame]) != nil) {
        pages_ = [[NSMutableArray arrayWithCapacity:4] retain];

        struct CGRect bounds = [self bounds];
        CGSize navsize = [UINavigationBar defaultSizeWithPrompt];
        CGRect navrect = {{0, 0}, navsize};

        navbar_ = [[UINavigationBar alloc] initWithFrame:navrect];
        [self addSubview:navbar_];

        [navbar_ setBarStyle:1];
        [navbar_ setDelegate:self];

        [navbar_ setPrompt:@""];

        transition_ = [[UITransitionView alloc] initWithFrame:CGRectMake(
            bounds.origin.x, bounds.origin.y + navsize.height, bounds.size.width, bounds.size.height - navsize.height
        )];

        [self addSubview:transition_];
    } return self;
}

- (void) setDelegate:(id)delegate {
    delegate_ = delegate;
}

- (void) setPage:(RVPage *)page {
    if ([pages_ count] != 0)
        [[pages_ lastObject] setPageActive:NO];

    [navbar_ disableAnimation];
    resetting_ = true;
    for (unsigned i(0), pages([pages_ count]); i != pages; ++i)
        [navbar_ popNavigationItem];
    resetting_ = false;

    [self pushPage:page];
    [navbar_ enableAnimation];
}

- (void) pushPage:(RVPage *)page {
    if ([pages_ count] != 0)
        [[pages_ lastObject] setPageActive:NO];

    NSString *title = [page title]; {
        const char *data = [title UTF8String];
        size_t size = [title length];

        Pcre title_r("^(.*?)( \\(.*\\))?$");
        if (title_r(data, size))
            title = title_r[1];
    }

    NSString *backButtonTitle = [page backButtonTitle];
    if (backButtonTitle == nil)
        backButtonTitle = title;

    UINavigationItem *navitem = [[[UINavigationItem alloc] initWithTitle:title] autorelease];
    [navitem setBackButtonTitle:backButtonTitle];
    [navbar_ pushNavigationItem:navitem];

    BOOL animated = [pages_ count] == 0 ? NO : YES;
    [transition_ transition:(animated ? 1 : 0) toView:page];
    [page setPageActive:YES];

    [pages_ addObject:page];
    [self reloadButtonsForPage:page];

    [navbar_ setAccessoryView:[page accessoryView] animate:animated goingBack:NO];
}

- (void) popPages:(unsigned)pages {
    if (pages == 0)
        return;

    [[pages_ lastObject] setPageActive:NO];

    resetting_ = true;
    for (unsigned i(0); i != pages; ++i)
        [navbar_ popNavigationItem];
    resetting_ = false;

    [self resetViewAnimated:YES toPage:[pages_ lastObject]];
}

- (void) setPrompt:(NSString *)prompt {
    [navbar_ setPrompt:prompt];
}

- (void) resetViewAnimated:(BOOL)animated {
    resetting_ = true;

    if ([pages_ count] > 1) {
        [navbar_ disableAnimation];
        while ([pages_ count] != (animated ? 2 : 1))
            [navbar_ popNavigationItem];
        [navbar_ enableAnimation];
        if (animated)
            [navbar_ popNavigationItem];
    }

    resetting_ = false;

    [self resetViewAnimated:animated toPage:[pages_ lastObject]];
}

- (void) resetViewAnimated:(BOOL)animated toPage:(RVPage *)page {
    [page resetViewAnimated:animated];
    [transition_ transition:(animated ? 2 : 0) toView:page];
    [page setPageActive:YES];
    [self reloadButtonsForPage:page];
    [navbar_ setAccessoryView:[page accessoryView] animate:animated goingBack:YES];
}

- (void) setTitle:(NSString *)title forPage:(RVPage *)page {
    if ([pages_ count] == 0 || page != [pages_ lastObject])
        return;
    UINavigationItem *navitem = [navbar_ topItem];
    [navitem setTitle:title];
}

- (void) setBackButtonTitle:(NSString *)title forPage:(RVPage *)page {
    if ([pages_ count] == 0 || page != [pages_ lastObject])
        return;
    UINavigationItem *navitem = [navbar_ topItem];
    [navitem setBackButtonTitle:title];
}

- (void) reloadButtonsForPage:(RVPage *)page {
    if ([pages_ count] == 0 || page != [pages_ lastObject])
        return;
    NSString *leftButtonTitle([pages_ count] == 1 ? [page leftButtonTitle] : nil);
    [navbar_ showButtonsWithLeftTitle:leftButtonTitle rightTitle:[page rightButtonTitle]];
}

- (void) reloadData {
    for (int i(0), e([pages_ count]); i != e; ++i) {
        RVPage *page([pages_ objectAtIndex:(e - i - 1)]);
        [page reloadData];
    }
}

- (CGRect) pageBounds {
    return [transition_ bounds];
}

@end
/* }}} */
/* RVPage Implementation {{{ */
@implementation RVPage

- (NSString *) title {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (NSString *) backButtonTitle {
    return nil;
}

- (NSString *) leftButtonTitle {
    return nil;
}

- (NSString *) rightButtonTitle {
    return nil;
}

- (void) _rightButtonClicked {
    [self doesNotRecognizeSelector:_cmd];
}

- (void) _leftButtonClicked {
    [self doesNotRecognizeSelector:_cmd];
}

- (UIView *) accessoryView {
    return nil;
}

- (void) setPageActive:(BOOL)active {
}

- (void) resetViewAnimated:(BOOL)animated {
    [self doesNotRecognizeSelector:_cmd];
}

- (void) setTitle:(NSString *)title {
    [book_ setTitle:title forPage:self];
}

- (void) setBackButtonTitle:(NSString *)title {
    [book_ setBackButtonTitle:title forPage:self];
}

- (void) reloadButtons {
    [book_ reloadButtonsForPage:self];
}

- (void) reloadData {
}

- (id) initWithBook:(RVBook *)book {
    if ((self = [super initWithFrame:[book pageBounds]]) != nil) {
        book_ = book;
    } return self;
}

- (void) setDelegate:(id)delegate {
    delegate_ = delegate;
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
    [essential_ dismiss];
    [self cancel];
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
        for (pkgCache::PkgIterator iterator = cache->PkgBegin(); !iterator.end(); ++iterator) {
            Package *package([Package packageWithIterator:iterator database:database_]);
            NSString *name([package name]);
            bool essential((iterator->Flags & pkgCache::Flag::Essential) != 0);
            pkgDepCache::StateCache &state(cache[iterator]);

            if (state.NewInstall())
                [installing addObject:name];
            else if (!state.Delete() && (state.iFlags & pkgDepCache::ReInstall) == pkgDepCache::ReInstall)
                [reinstalling addObject:name];
            else if (state.Upgrade())
                [upgrading addObject:name];
            else if (state.Downgrade())
                [downgrading addObject:name];
            else if (state.Delete()) {
                if (essential)
                    remove = true;
                [removing addObject:name];
            }
        }

        if (!remove)
            essential_ = nil;
        else {
            essential_ = [[UIAlertSheet alloc]
                initWithTitle:@"Unable to Comply"
                buttons:[NSArray arrayWithObjects:@"Okay", nil]
                defaultButtonIndex:0
                delegate:self
                context:self
            ];

            [essential_ setBodyText:@"One or more of the packages you are about to remove are marked 'Essential' and cannot be removed by Cydia. Please use apt-get."];
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
    ProgressDelegate
> {
    UIView *view_;
    UIView *background_;
    UITransitionView *transition_;
    UIView *overlay_;
    UINavigationBar *navbar_;
    UIProgressBar *progress_;
    UITextView *output_;
    UITextLabel *status_;
    id delegate_;
}

- (void) transitionViewDidComplete:(UITransitionView*)view fromView:(UIView*)from toView:(UIView*)to;

- (ProgressView *) initWithFrame:(struct CGRect)frame delegate:(id)delegate;
- (void) setContentView:(UIView *)view;
- (void) resetView;

- (void) _retachThread;
- (void) _detachNewThreadData:(ProgressData *)data;
- (void) detachNewThreadSelector:(SEL)selector toTarget:(id)target withObject:(id)object title:(NSString *)title;

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
    [super dealloc];
}

- (void) transitionViewDidComplete:(UITransitionView*)view fromView:(UIView*)from toView:(UIView*)to {
    if (bootstrap_ && from == overlay_ && to == view_)
        exit(0);
}

- (ProgressView *) initWithFrame:(struct CGRect)frame delegate:(id)delegate {
    if ((self = [super initWithFrame:frame]) != nil) {
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
        [overlay_ addSubview:progress_];

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

        [overlay_ addSubview:output_];
        [overlay_ addSubview:status_];

        [progress_ setStyle:0];
    } return self;
}

- (void) setContentView:(UIView *)view {
    view_ = [view retain];
}

- (void) resetView {
    [transition_ transition:6 toView:view_];
}

- (void) alertSheet:(UIAlertSheet *)sheet buttonClicked:(int)button {
    [sheet dismiss];
}

- (void) _retachThread {
    [delegate_ progressViewIsComplete:self];
    [self resetView];
}

- (void) _detachNewThreadData:(ProgressData *)data {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    [[data target] performSelector:[data selector] withObject:[data object]];
    [data release];

    [self performSelectorOnMainThread:@selector(_retachThread) withObject:nil waitUntilDone:YES];

    [pool release];
}

- (void) detachNewThreadSelector:(SEL)selector toTarget:(id)target withObject:(id)object title:(NSString *)title {
    [navbar_ popNavigationItem];
    UINavigationItem *navitem = [[[UINavigationItem alloc] initWithTitle:title] autorelease];
    [navbar_ pushNavigationItem:navitem];

    [status_ setText:nil];
    [output_ setText:@""];
    [progress_ setProgress:0];

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

- (void) setProgressError:(NSString *)error {
    [self
        performSelectorOnMainThread:@selector(_setProgressError:)
        withObject:error
        waitUntilDone:YES
    ];
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

- (void) _setProgressError:(NSString *)error {
    UIAlertSheet *sheet = [[[UIAlertSheet alloc]
        initWithTitle:@"Package Error"
        buttons:[NSArray arrayWithObjects:@"Okay", nil]
        defaultButtonIndex:0
        delegate:self
        context:self
    ] autorelease];

    [sheet setBodyText:error];
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

@end
/* }}} */

/* Package Cell {{{ */
@interface PackageCell : UITableCell {
    UIImageView *icon_;
    UITextLabel *name_;
    UITextLabel *description_;
    UITextLabel *source_;
    UIImageView *trusted_;
}

- (PackageCell *) init;
- (void) setPackage:(Package *)package;

- (void) _setSelected:(float)fraction;
- (void) setSelected:(BOOL)selected;
- (void) setSelected:(BOOL)selected withFade:(BOOL)fade;
- (void) _setSelectionFadeFraction:(float)fraction;

@end

@implementation PackageCell

- (void) dealloc {
    [icon_ release];
    [name_ release];
    [description_ release];
    [source_ release];
    [trusted_ release];
    [super dealloc];
}

- (PackageCell *) init {
    if ((self = [super init]) != nil) {
        GSFontRef bold = GSFontCreateWithName("Helvetica", kGSFontTraitBold, 20);
        GSFontRef large = GSFontCreateWithName("Helvetica", kGSFontTraitNone, 12);
        GSFontRef small = GSFontCreateWithName("Helvetica", kGSFontTraitNone, 14);

        icon_ = [[UIImageView alloc] initWithFrame:CGRectMake(10, 10, 30, 30)];
        [icon_ zoomToScale:0.5f];

        name_ = [[UITextLabel alloc] initWithFrame:CGRectMake(48, 8, 240, 25)];
        [name_ setBackgroundColor:Clear_];
        [name_ setFont:bold];

        source_ = [[UITextLabel alloc] initWithFrame:CGRectMake(58, 28, 225, 20)];
        [source_ setBackgroundColor:Clear_];
        [source_ setFont:large];

        description_ = [[UITextLabel alloc] initWithFrame:CGRectMake(12, 46, 280, 20)];
        [description_ setBackgroundColor:Clear_];
        [description_ setFont:small];

        trusted_ = [[UIImageView alloc] initWithFrame:CGRectMake(30, 30, 16, 16)];
        [trusted_ setImage:[UIImage applicationImageNamed:@"trusted.png"]];

        [self addSubview:icon_];
        [self addSubview:name_];
        [self addSubview:description_];
        [self addSubview:source_];

        CFRelease(small);
        CFRelease(large);
        CFRelease(bold);
    } return self;
}

- (void) setPackage:(Package *)package {
    Source *source = [package source];

    UIImage *image = nil;
    if (NSString *icon = [package icon])
        image = [UIImage imageAtPath:[icon substringFromIndex:6]];
    if (image == nil) if (NSString *icon = [source defaultIcon])
        image = [UIImage imageAtPath:[icon substringFromIndex:6]];
    if (image == nil)
        image = [UIImage applicationImageNamed:@"unknown.png"];

    [icon_ setImage:image];
    [icon_ setFrame:CGRectMake(10, 10, 30, 30)];

    [name_ setText:[package name]];
    [description_ setText:[package tagline]];

    NSString *label;
    bool trusted;

    if (source != nil) {
        label = [source label];
        trusted = [source trusted];
    } else if ([[package id] isEqualToString:@"firmware"]) {
        label = @"Apple";
        trusted = false;
    } else {
        label = @"Unknown/Local";
        trusted = false;
    }

    [source_ setText:[NSString stringWithFormat:@"from %@", label]];

    if (trusted)
        [self addSubview:trusted_];
    else
        [trusted_ removeFromSuperview];
}

- (void) _setSelected:(float)fraction {
    CGColor black(space_,
        Interpolate(0.0, 1.0, fraction),
        Interpolate(0.0, 1.0, fraction),
        Interpolate(0.0, 1.0, fraction),
    1.0);

    CGColor gray(space_,
        Interpolate(0.4, 1.0, fraction),
        Interpolate(0.4, 1.0, fraction),
        Interpolate(0.4, 1.0, fraction),
    1.0);

    [name_ setColor:black];
    [description_ setColor:gray];
    [source_ setColor:black];
}

- (void) setSelected:(BOOL)selected {
    [self _setSelected:(selected ? 1.0 : 0.0)];
    [super setSelected:selected];
}

- (void) setSelected:(BOOL)selected withFade:(BOOL)fade {
    if (!fade)
        [self _setSelected:(selected ? 1.0 : 0.0)];
    [super setSelected:selected withFade:fade];
}

- (void) _setSelectionFadeFraction:(float)fraction {
    [self _setSelected:fraction];
    [super _setSelectionFadeFraction:fraction];
}

@end
/* }}} */
/* Section Cell {{{ */
@interface SectionCell : UITableCell {
    UITextLabel *name_;
    UITextLabel *count_;
}

- (id) init;
- (void) setSection:(Section *)section;

- (void) _setSelected:(float)fraction;
- (void) setSelected:(BOOL)selected;
- (void) setSelected:(BOOL)selected withFade:(BOOL)fade;
- (void) _setSelectionFadeFraction:(float)fraction;

@end

@implementation SectionCell

- (void) dealloc {
    [name_ release];
    [count_ release];
    [super dealloc];
}

- (id) init {
    if ((self = [super init]) != nil) {
        GSFontRef bold = GSFontCreateWithName("Helvetica", kGSFontTraitBold, 22);
        GSFontRef small = GSFontCreateWithName("Helvetica", kGSFontTraitBold, 12);

        name_ = [[UITextLabel alloc] initWithFrame:CGRectMake(48, 9, 250, 25)];
        [name_ setBackgroundColor:Clear_];
        [name_ setFont:bold];

        count_ = [[UITextLabel alloc] initWithFrame:CGRectMake(11, 7, 29, 32)];
        [count_ setCentersHorizontally:YES];
        [count_ setBackgroundColor:Clear_];
        [count_ setFont:small];
        [count_ setColor:White_];

        UIImageView *folder = [[[UIImageView alloc] initWithFrame:CGRectMake(8, 7, 32, 32)] autorelease];
        [folder setImage:[UIImage applicationImageNamed:@"folder.png"]];

        [self addSubview:folder];
        [self addSubview:name_];
        [self addSubview:count_];

        [self _setSelected:0];

        CFRelease(small);
        CFRelease(bold);
    } return self;
}

- (void) setSection:(Section *)section {
    if (section == nil) {
        [name_ setText:@"All Packages"];
        [count_ setText:nil];
    } else {
        NSString *name = [section name];
        [name_ setText:(name == nil ? @"(No Section)" : name)];
        [count_ setText:[NSString stringWithFormat:@"%d", [section count]]];
    }
}

- (void) _setSelected:(float)fraction {
    CGColor black(space_,
        Interpolate(0.0, 1.0, fraction),
        Interpolate(0.0, 1.0, fraction),
        Interpolate(0.0, 1.0, fraction),
    1.0);

    [name_ setColor:black];
}

- (void) setSelected:(BOOL)selected {
    [self _setSelected:(selected ? 1.0 : 0.0)];
    [super setSelected:selected];
}

- (void) setSelected:(BOOL)selected withFade:(BOOL)fade {
    if (!fade)
        [self _setSelected:(selected ? 1.0 : 0.0)];
    [super setSelected:selected withFade:fade];
}

- (void) _setSelectionFadeFraction:(float)fraction {
    [self _setSelected:fraction];
    [super _setSelectionFadeFraction:fraction];
}

@end
/* }}} */

/* Browser Interface {{{ */
@interface BrowserView : RVPage {
    _transient Database *database_;
    UIScroller *scroller_;
    UIWebView *webview_;
    NSMutableArray *urls_;
    UIProgressIndicator *indicator_;

    NSString *title_;
    bool loading_;
}

- (void) loadURL:(NSURL *)url cachePolicy:(NSURLRequestCachePolicy)policy;
- (void) loadURL:(NSURL *)url;

- (void) loadRequest:(NSURLRequest *)request;
- (void) reloadURL;

- (WebView *) webView;

- (id) initWithBook:(RVBook *)book database:(Database *)database;

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
    [super dealloc];
}

- (int) numberOfGroupsInPreferencesTable:(UIPreferencesTable *)table {
    return [package_ source] == nil ? 2 : 3;
}

- (NSString *) preferencesTable:(UIPreferencesTable *)table titleForGroup:(int)group {
    switch (group) {
        case 0: return nil;
        case 1: return @"Package Details";
        case 2: return @"Source Information";

        default: _assert(false);
    }
}

- (float) preferencesTable:(UIPreferencesTable *)table heightForRow:(int)row inGroup:(int)group withProposedHeight:(float)proposed {
    if (group != 0 || row != 1)
        return proposed;
    else
        return [description_ visibleTextRect].size.height + TextViewOffset_;
}

- (int) preferencesTable:(UIPreferencesTable *)table numberOfRowsInGroup:(int)group {
    switch (group) {
        case 0: return [package_ website] == nil ? 2 : 3;
        case 1: return 5;
        case 2: return 3;

        default: _assert(false);
    }
}

- (UIPreferencesTableCell *) preferencesTable:(UIPreferencesTable *)table cellForRow:(int)row inGroup:(int)group {
    UIPreferencesTableCell *cell = [[[UIPreferencesTableCell alloc] init] autorelease];
    [cell setShowSelection:NO];

    switch (group) {
        case 0: switch (row) {
            case 0:
                [cell setTitle:[package_ name]];
                [cell setValue:[package_ latest]];
            break;

            case 1:
                [cell addSubview:description_];
            break;

            case 2:
                [cell setTitle:@"More Information"];
                [cell setShowDisclosure:YES];
                [cell setShowSelection:YES];
            break;

            default: _assert(false);
        } break;

        case 1: switch (row) {
            case 0:
                [cell setTitle:@"Identifier"];
                [cell setValue:[package_ id]];
            break;

            case 1: {
                [cell setTitle:@"Installed Version"];
                NSString *installed([package_ installed]);
                [cell setValue:(installed == nil ? @"n/a" : installed)];
            } break;

            case 2: {
                [cell setTitle:@"Section"];
                NSString *section([package_ section]);
                [cell setValue:(section == nil ? @"n/a" : section)];
            } break;

            case 3:
                [cell setTitle:@"Expanded Size"];
                [cell setValue:SizeString([package_ size])];
            break;

            case 4:
                [cell setTitle:@"Maintainer"];
                [cell setValue:[[package_ maintainer] name]];
                [cell setShowDisclosure:YES];
                [cell setShowSelection:YES];
            break;

            default: _assert(false);
        } break;

        case 2: switch (row) {
            case 0:
                [cell setTitle:[[package_ source] label]];
                [cell setValue:[[package_ source] version]];
            break;

            case 1:
                [cell setValue:[[package_ source] description]];
            break;

            case 2:
                [cell setTitle:@"Origin"];
                [cell setValue:[[package_ source] origin]];
            break;

            default: _assert(false);
        } break;

        default: _assert(false);
    }

    return cell;
}

- (BOOL) canSelectRow:(int)row {
    return YES;
}

- (void) tableRowSelected:(NSNotification *)notification {
    int row = [table_ selectedRow];
    NSString *website = [package_ website];

    if (row == (website == nil ? 8 : 9))
        [delegate_ openURL:[NSURL URLWithString:[NSString stringWithFormat:@"mailto:%@?subject=%@",
            [[package_ maintainer] email],
            [[NSString stringWithFormat:@"regarding apt package \"%@\"", [package_ name]] stringByAddingPercentEscapes]
        ]]];
    else if (website != nil && row == 3) {
        NSURL *url = [NSURL URLWithString:website];
        BrowserView *browser = [[[BrowserView alloc] initWithBook:book_ database:database_] autorelease];
        [browser setDelegate:delegate_];
        [book_ pushPage:browser];
        [browser loadURL:url];
    }
}

- (void) alertSheet:(UIAlertSheet *)sheet buttonClicked:(int)button {
    switch (button) {
        case 1: [delegate_ installPackage:package_]; break;
        case 2: [delegate_ removePackage:package_]; break;
    }

    [sheet dismiss];
}

- (void) _rightButtonClicked {
    if ([package_ installed] == nil)
        [delegate_ installPackage:package_];
    else {
        NSMutableArray *buttons = [NSMutableArray arrayWithCapacity:6];

        if ([package_ upgradable])
            [buttons addObject:@"Upgrade"];
        else
            [buttons addObject:@"Reinstall"];

        [buttons addObject:@"Remove"];
        [buttons addObject:@"Cancel"];

        [delegate_ slideUp:[[[UIAlertSheet alloc]
            initWithTitle:@"Manage Package"
            buttons:buttons
            defaultButtonIndex:2
            delegate:self
            context:self
        ] autorelease]];
    }
}

- (NSString *) rightButtonTitle {
    _assert(package_ != nil);
    return [package_ installed] == nil ? @"Install" : @"Manage";
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

    if (package != nil) {
        package_ = [package retain];
        name_ = [[package id] retain];

        NSString *description([package description]);
        if (description == nil)
            description = [package tagline];
        description_ = [GetTextView(description, 12, true) retain];

        [description_ setTextColor:Black_];

        [table_ reloadData];
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
- (void) reloadData;

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
    return 73;
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

- (void) reloadData {
    NSArray *packages = [database_ packages];

    [packages_ removeAllObjects];
    [sections_ removeAllObjects];

    for (size_t i(0); i != [packages count]; ++i) {
        Package *package([packages objectAtIndex:i]);
        if ([[package performSelector:filter_ withObject:object_] boolValue])
            [packages_ addObject:package];
    }

    [packages_ sortUsingSelector:@selector(compareByName:)];

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

@end
/* }}} */

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
    NSMutableURLRequest *request = [NSMutableURLRequest
        requestWithURL:url
        cachePolicy:policy
        timeoutInterval:30.0
    ];

    [request addValue:[NSString stringWithCString:Firmware_] forHTTPHeaderField:@"X-Firmware"];
    [request addValue:[NSString stringWithCString:Machine_] forHTTPHeaderField:@"X-Machine"];
    [request addValue:[NSString stringWithCString:SerialNumber_] forHTTPHeaderField:@"X-Serial-Number"];

    [self loadRequest:request];
}


- (void) loadURL:(NSURL *)url {
    [self loadURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy];
}

// XXX: this needs to add the headers
- (NSURLRequest *) _addHeadersToRequest:(NSURLRequest *)request {
    return request;
}

- (void) loadRequest:(NSURLRequest *)request {
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

- (NSURLRequest *) webView:(WebView *)sender resource:(id)identifier willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse fromDataSource:(WebDataSource *)dataSource {
    return [self _addHeadersToRequest:request];
}

- (WebView *) webView:(WebView *)sender createWebViewWithRequest:(NSURLRequest *)request {
    [self setBackButtonTitle:title_];
    BrowserView *browser = [[[BrowserView alloc] initWithBook:book_ database:database_] autorelease];
    [browser setDelegate:delegate_];
    [book_ pushPage:browser];
    [browser loadRequest:[self _addHeadersToRequest:request]];
    return [browser webView];
}

- (void) webView:(WebView *)sender willClickElement:(id)element {
    if (![element respondsToSelector:@selector(href)])
        return;
    NSString *href = [element href];
    if (href == nil)
        return;
    if ([href hasPrefix:@"apptapp://package/"]) {
        NSString *name = [href substringFromIndex:18];
        Package *package = [database_ packageWithName:name];
        if (package == nil) {
            UIAlertSheet *sheet = [[[UIAlertSheet alloc]
                initWithTitle:@"Cannot Locate Package"
                buttons:[NSArray arrayWithObjects:@"Close", nil]
                defaultButtonIndex:0
                delegate:self
                context:self
            ] autorelease];

            [sheet setBodyText:[NSString stringWithFormat:
                @"The package %@ cannot be found in your current sources. I might recommend intalling more sources."
            , name]];

            [sheet popupAlertAnimated:YES];
        } else {
            [self setBackButtonTitle:title_];
            PackageView *view = [[[PackageView alloc] initWithBook:book_ database:database_] autorelease];
            [view setDelegate:delegate_];
            [view setPackage:package];
            [book_ pushPage:view];
        }
    }
}

- (void) webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame {
    title_ = [title retain];
    [self setTitle:title];
}

- (void) webView:(WebView *)sender didStartProvisionalLoadForFrame:(WebFrame *)frame {
    if ([frame parentFrame] != nil)
        return;

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
    loading_ = false;
    [indicator_ stopAnimation];
    [self reloadButtons];
}

- (void) webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame {
    if ([frame parentFrame] != nil)
        return;
    [self _finishLoading];
}

- (void) webView:(WebView *)sender didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame {
    if ([frame parentFrame] != nil)
        return;
    [self setTitle:[error localizedDescription]];
    [self _finishLoading];
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

        CGSize indsize = [UIProgressIndicator defaultSizeForStyle:0];
        indicator_ = [[UIProgressIndicator alloc] initWithFrame:CGRectMake(281, 43, indsize.width, indsize.height)];
        [indicator_ setStyle:0];

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

- (void) alertSheet:(UIAlertSheet *)sheet buttonClicked:(int)button {
    [sheet dismiss];
}

- (void) _leftButtonClicked {
    UIAlertSheet *sheet = [[[UIAlertSheet alloc]
        initWithTitle:@"About Cydia Packager"
        buttons:[NSArray arrayWithObjects:@"Close", nil]
        defaultButtonIndex:0
        delegate:self
        context:self
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

- (void) _rightButtonClicked {
    [self reloadURL];
}

- (NSString *) leftButtonTitle {
    return @"About";
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

@end
/* }}} */

/* Install View {{{ */
@interface InstallView : RVPage {
    _transient Database *database_;
    NSMutableArray *packages_;
    NSMutableArray *sections_;
    UITable *list_;
}

- (id) initWithBook:(RVBook *)book database:(Database *)database;
- (void) reloadData;

@end

@implementation InstallView

- (void) dealloc {
    [list_ setDataSource:nil];
    [list_ setDelegate:nil];

    [packages_ release];
    [sections_ release];
    [list_ release];
    [super dealloc];
}

- (int) numberOfRowsInTable:(UITable *)table {
    return [sections_ count] + 1;
}

- (float) table:(UITable *)table heightForRow:(int)row {
    return 45;
}

- (UITableCell *) table:(UITable *)table cellForRow:(int)row column:(UITableColumn *)col reusing:(UITableCell *)reusing {
    if (reusing == nil)
        reusing = [[[SectionCell alloc] init] autorelease];
    [(SectionCell *)reusing setSection:(row == 0 ? nil : [sections_ objectAtIndex:(row - 1)])];
    return reusing;
}

- (BOOL) table:(UITable *)table showDisclosureForRow:(int)row {
    return YES;
}

- (void) tableRowSelected:(NSNotification *)notification {
    int row = [[notification object] selectedRow];
    if (row == INT_MAX)
        return;

    Section *section;
    NSString *title;

    if (row == 0) {
        section = nil;
        title = @"All Packages";
    } else {
        section = [sections_ objectAtIndex:(row - 1)];
        title = [section name];
    }

    PackageTable *table = [[[PackageTable alloc]
        initWithBook:book_
        database:database_
        title:title
        filter:@selector(isUninstalledInSection:)
        with:(section == nil ? nil : [section name])
    ] autorelease];

    [table setDelegate:delegate_];

    [book_ pushPage:table];
}

- (id) initWithBook:(RVBook *)book database:(Database *)database {
    if ((self = [super initWithBook:book]) != nil) {
        database_ = database;

        packages_ = [[NSMutableArray arrayWithCapacity:16] retain];
        sections_ = [[NSMutableArray arrayWithCapacity:16] retain];

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

        [self reloadData];
    } return self;
}

- (void) reloadData {
    NSArray *packages = [database_ packages];

    [packages_ removeAllObjects];
    [sections_ removeAllObjects];

    for (size_t i(0); i != [packages count]; ++i) {
        Package *package([packages objectAtIndex:i]);
        if ([package installed] == nil)
            [packages_ addObject:package];
    }

    [packages_ sortUsingSelector:@selector(compareBySection:)];

    Section *section = nil;
    for (size_t offset = 0, count = [packages_ count]; offset != count; ++offset) {
        Package *package = [packages_ objectAtIndex:offset];
        NSString *name = [package section];

        if (section == nil || name != nil && ![[section name] isEqualToString:name]) {
            section = [[[Section alloc] initWithName:name row:offset] autorelease];
            [sections_ addObject:section];
        }

        [section addToCount];
    }

    [list_ reloadData];
}

- (void) resetViewAnimated:(BOOL)animated {
    [list_ resetViewAnimated:animated];
}

- (NSString *) title {
    return @"Install";
}

- (NSString *) backButtonTitle {
    return @"Sections";
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
    return 73;
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
        if ([package installed] == nil || [package upgradable])
            [packages_ addObject:package];
    }

    [packages_ sortUsingSelector:@selector(compareForChanges:)];

    Section *upgradable = [[[Section alloc] initWithName:@"Available Upgrades" row:0] autorelease];
    Section *section = nil;

    upgrades_ = 0;
    bool unseens = false;

    CFLocaleRef locale = CFLocaleCopyCurrent();
    CFDateFormatterRef formatter = CFDateFormatterCreate(NULL, locale, kCFDateFormatterMediumStyle, kCFDateFormatterMediumStyle);

    for (size_t offset = 0, count = [packages_ count]; offset != count; ++offset) {
        Package *package = [packages_ objectAtIndex:offset];

        if ([package upgradable]) {
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
    CFRelease(locale);

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

- (NSString *) rightButtonTitle {
    return upgrades_ == 0 ? nil : [NSString stringWithFormat:@"Upgrade All (%u)", upgrades_];
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

@interface SearchView : PackageTable {
    UIView *accessory_;
    UISearchField *field_;
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
    [super dealloc];
}

- (void) textFieldDidBecomeFirstResponder:(UITextField *)field {
    [delegate_ showKeyboard:YES];
    [list_ setEnabled:NO];

    /*CGColor dimmed(alpha, 0, 0, 0, 0.5);
    [editor_ setBackgroundColor:dimmed];*/
}

- (void) textFieldDidResignFirstResponder:(UITextField *)field {
    [list_ setEnabled:YES];
    [delegate_ showKeyboard:NO];
}

- (void) keyboardInputChanged:(UIFieldEditor *)editor {
    NSString *text([field_ text]);
    [field_ setClearButtonStyle:(text == nil || [text length] == 0 ? 0 : 2)];
}

- (BOOL) keyboardInput:(id)input shouldInsertText:(NSString *)text isMarkedText:(int)marked {
    if ([text length] != 1 || [text characterAtIndex:0] != '\n')
        return YES;

    [self reloadData];
    [field_ resignFirstResponder];
    return NO;
}

- (id) initWithBook:(RVBook *)book database:(Database *)database {
    if ((self = [super
        initWithBook:book
        database:database
        title:nil
        filter:@selector(isSearchedForBy:)
        with:nil
    ]) != nil) {
        CGRect cnfrect = {{0, 36}, {17, 18}};

        CGRect area;
        area.origin.x = cnfrect.size.width + 6;
        area.origin.y = 30;
        area.size.width = [self bounds].size.width - area.origin.x - 12;
        area.size.height = [UISearchField defaultHeight];

        field_ = [[UISearchField alloc] initWithFrame:area];

        GSFontRef font = GSFontCreateWithName("Helvetica", kGSFontTraitNone, 16);
        [field_ setFont:font];
        CFRelease(font);

        [field_ setPlaceholder:@"Package Names & Descriptions"];
        [field_ setPaddingTop:5];
        [field_ setDelegate:self];

#ifndef __OBJC2__
        UITextTraits *traits = [field_ textTraits];
        [traits setEditingDelegate:self];
        [traits setReturnKeyType:6];
        [traits setAutoCapsType:0];
        [traits setAutoCorrectionType:1];
#endif

        UIPushButton *configure = [[[UIPushButton alloc] initWithFrame:cnfrect] autorelease];
        [configure setShowPressFeedback:YES];
        [configure setImage:[UIImage applicationImageNamed:@"configure.png"]];
        [configure addTarget:self action:@selector(configurePushed) forEvents:1];

        accessory_ = [[UIView alloc] initWithFrame:CGRectMake(0, 6, cnfrect.size.width + area.size.width + 6 * 3, area.size.height + 30)];
        [accessory_ addSubview:field_];
        [accessory_ addSubview:configure];
    } return self;
}

- (void) configurePushed {
    // XXX: implement flippy advanced panel
}

- (void) reloadData {
    object_ = [[field_ text] retain];
    [super reloadData];
    [[list_ table] scrollPointVisibleAtTopLeft:CGPointMake(0, 0) animated:NO];
}

- (UIView *) accessoryView {
    return accessory_;
}

- (NSString *) backButtonTitle {
    return @"Search";
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
}

- (id) initWithFrame:(CGRect)frame database:(Database *)database;
- (void) update;

@end

@implementation CYBook

- (void) dealloc {
    [overlay_ release];
    [indicator_ release];
    [prompt_ release];
    [progress_ release];
    [super dealloc];
}

- (void) update {
    [navbar_ addSubview:overlay_];
    [indicator_ startAnimation];
    [prompt_ setText:@"Updating Database..."];
    [progress_ setProgress:0];

    [NSThread
        detachNewThreadSelector:@selector(_update)
        toTarget:self
        withObject:nil
    ];
}

- (void) _update_ {
    [overlay_ removeFromSuperview];
    [indicator_ stopAnimation];
    [delegate_ reloadData];

    [self setPrompt:[NSString stringWithFormat:@"Last Updated: %@", GetLastUpdate()]];
}

- (id) initWithFrame:(CGRect)frame database:(Database *)database {
    if ((self = [super initWithFrame:frame]) != nil) {
        database_ = database;

        CGRect ovrrect = [navbar_ bounds];
        ovrrect.size.height = [UINavigationBar defaultSizeWithPrompt].height - [UINavigationBar defaultSize].height;

        overlay_ = [[UIView alloc] initWithFrame:ovrrect];

        CGSize indsize = [UIProgressIndicator defaultSizeForStyle:2];
        unsigned indoffset = (ovrrect.size.height - indsize.height) / 2;
        CGRect indrect = {{indoffset, indoffset}, indsize};

        indicator_ = [[UIProgressIndicator alloc] initWithFrame:indrect];
        [indicator_ setStyle:2];
        [overlay_ addSubview:indicator_];

        CGSize prmsize = {200, indsize.width};

        CGRect prmrect = {{
            indoffset * 2 + indsize.width,
            (ovrrect.size.height - prmsize.height) / 2
        }, prmsize};

        GSFontRef font = GSFontCreateWithName("Helvetica", kGSFontTraitNone, 12);

        prompt_ = [[UITextLabel alloc] initWithFrame:prmrect];

        [prompt_ setColor:White_];
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

- (void) setProgressError:(NSString *)error {
    [self
        performSelectorOnMainThread:@selector(_setProgressError:)
        withObject:error
        waitUntilDone:YES
    ];
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

- (void) _setProgressError:(NSString *)error {
    [prompt_ setText:[NSString stringWithFormat:@"Error: %@", error]];
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

    Database *database_;
    ProgressView *progress_;

    unsigned tag_;

    UIKeyboard *keyboard_;
}

@end

@implementation Cydia

- (void) _reloadData {
    /*UIProgressHUD *hud = [[UIProgressHUD alloc] initWithWindow:window_];
    [hud setText:@"Reloading Data"];
    [overlay_ addSubview:hud];
    [hud show:YES];*/

    [database_ reloadData];

    size_t count = 16;

    if (Packages_ == nil) {
        Packages_ = [[NSMutableDictionary alloc] initWithCapacity:count];
        [Metadata_ setObject:Packages_ forKey:@"Packages"];
    }

    size_t changes(0);

    NSArray *packages = [database_ packages];
    for (int i(0), e([packages count]); i != e; ++i) {
        Package *package = [packages objectAtIndex:i];
        if ([package upgradable])
            ++changes;
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

    _assert([Metadata_ writeToFile:@"/var/lib/cydia/metadata.plist" atomically:YES] == YES);

    [book_ reloadData];
    /*[hud show:NO];
    [hud removeFromSuperview];*/
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
            context:self
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
    restart_ = true;

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

- (void) alertSheet:(UIAlertSheet *)sheet buttonClicked:(int)button {
    [sheet dismiss];
}

- (void) setPage:(RVPage *)page {
    [page setDelegate:self];
    [book_ setPage:page];
}

- (RVPage *) _setNewsPage {
    BrowserView *browser = [[[BrowserView alloc] initWithBook:book_ database:database_] autorelease];
    [self setPage:browser];
    [browser loadURL:[NSURL URLWithString:@"http://cydia.saurik.com/"]];
    return browser;
}

- (void) buttonBarItemTapped:(id)sender {
    unsigned tag = [sender tag];

    switch (tag) {
        case 1:
            [self _setNewsPage];
        break;

        case 2:
            [self setPage:[[[InstallView alloc] initWithBook:book_ database:database_] autorelease]];
        break;

        case 3:
            [self setPage:[[[ChangesView alloc] initWithBook:book_ database:database_] autorelease]];
        break;

        case 4:
            [self setPage:[[[PackageTable alloc]
                initWithBook:book_
                database:database_
                title:@"Manage"
                filter:@selector(isInstalledInSection:)
                with:nil
            ] autorelease]];
        break;

        case 5:
            [self setPage:[[[SearchView alloc] initWithBook:book_ database:database_] autorelease]];
        break;

        default:
            _assert(false);
    }

    tag_ = tag;
}

- (void) applicationWillSuspend {
    [super applicationWillSuspend];

    if (restart_)
        if (FW_LEAST(1,1,3))
            notify_post("com.apple.language.changed");
        else
            system("launchctl stop com.apple.SpringBoard");
}

- (void) applicationDidFinishLaunching:(id)unused {
    _assert(pkgInitConfig(*_config));
    _assert(pkgInitSystem(*_config, _system));

    confirm_ = nil;
    tag_ = 1;

    CGRect screenrect = [UIHardware fullScreenApplicationContentRect];
    window_ = [[UIWindow alloc] initWithContentRect:screenrect];

    [window_ orderFront: self];
    [window_ makeKey: self];
    [window_ _setHidden: NO];

    progress_ = [[ProgressView alloc] initWithFrame:[window_ bounds] delegate:self];
    [window_ setContentView:progress_];

    underlay_ = [[UIView alloc] initWithFrame:[progress_ bounds]];
    [progress_ setContentView:underlay_];

    overlay_ = [[UIView alloc] initWithFrame:[underlay_ bounds]];

    if (!bootstrap_)
        [underlay_ addSubview:overlay_];

    database_ = [[Database alloc] init];
    [database_ setDelegate:progress_];

    book_ = [[CYBook alloc] initWithFrame:CGRectMake(
        0, 0, screenrect.size.width, screenrect.size.height - 48
    ) database:database_];

    [book_ setDelegate:self];

    [overlay_ addSubview:book_];

    NSArray *buttonitems = [NSArray arrayWithObjects:
        [NSDictionary dictionaryWithObjectsAndKeys:
            @"buttonBarItemTapped:", kUIButtonBarButtonAction,
            @"news-up.png", kUIButtonBarButtonInfo,
            @"news-dn.png", kUIButtonBarButtonSelectedInfo,
            [NSNumber numberWithInt:1], kUIButtonBarButtonTag,
            self, kUIButtonBarButtonTarget,
            @"News", kUIButtonBarButtonTitle,
            @"0", kUIButtonBarButtonType,
        nil],

        [NSDictionary dictionaryWithObjectsAndKeys:
            @"buttonBarItemTapped:", kUIButtonBarButtonAction,
            @"install-up.png", kUIButtonBarButtonInfo,
            @"install-dn.png", kUIButtonBarButtonSelectedInfo,
            [NSNumber numberWithInt:2], kUIButtonBarButtonTag,
            self, kUIButtonBarButtonTarget,
            @"Install", kUIButtonBarButtonTitle,
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
            0, screenrect.size.height - 48,
            screenrect.size.width, 48
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
            i * 64 + 2, 1, 60, 48
        )];

    [buttonbar_ showSelectionForButton:1];
    [overlay_ addSubview:buttonbar_];

    [UIKeyboard initImplementationNow];
    CGSize keysize = [UIKeyboard defaultSize];
    CGRect keyrect = {{0, [overlay_ bounds].size.height - keysize.height}, keysize};
    keyboard_ = [[UIKeyboard alloc] initWithFrame:keyrect];
    [[UIKeyboardImpl sharedInstance] setSoundsEnabled:(Sounds_Keyboard_ ? YES : NO)];

    [self reloadData];
    [book_ update];

    [progress_ resetView];

    if (bootstrap_)
        [self bootstrap];
    else
        [self _setNewsPage];
}

- (void) showKeyboard:(BOOL)show {
    if (show)
        [overlay_ addSubview:keyboard_];
    else
        [keyboard_ removeFromSuperview];
}

- (void) slideUp:(UIAlertSheet *)alert {
    [alert presentSheetFromButtonBar:buttonbar_];
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
    else
        Packages_ = [Metadata_ objectForKey:@"Packages"];

    setenv("CYDIA", "", _not(int));
    if (access("/User", F_OK) != 0)
        system("/usr/libexec/cydia/firmware.sh");
    system("dpkg --configure -a");

    space_ = CGColorSpaceCreateDeviceRGB();

    Black_.Set(space_, 0.0, 0.0, 0.0, 1.0);
    Clear_.Set(space_, 0.0, 0.0, 0.0, 0.0);
    Red_.Set(space_, 1.0, 0.0, 0.0, 1.0);
    White_.Set(space_, 1.0, 1.0, 1.0, 1.0);

    int value = UIApplicationMain(argc, argv, [Cydia class]);

    CGColorSpaceRelease(space_);

    [pool release];
    return value;
}
