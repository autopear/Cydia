/* #include Directives {{{ */
#include <Foundation/NSURL.h>
#include <UIKit/UIKit.h>
#import <GraphicsServices/GraphicsServices.h>

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

extern "C" {
#include <mach-o/nlist.h>
}

#include <objc/objc-class.h>

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
/* }}} */
/* Miscellaneous Messages {{{ */
@interface WebView
- (void) setApplicationNameForUserAgent:(NSString *)applicationName;
- (id) frameLoadDelegate;
- (void) setFrameLoadDelegate:(id)delegate;
@end

@interface NSString (Cydia)
- (NSString *) stringByAddingPercentEscapes;
- (NSString *) stringByReplacingCharacter:(unsigned short)arg0 withCharacter:(unsigned short)arg1;
@end
/* }}} */

/* Reset View (UIView) {{{ */
@interface UIView (CYResetView)
- (void) resetViewAnimated:(BOOL)animated;
@end

@implementation UIView (CYResetView)

- (void) resetViewAnimated:(BOOL)animated {
    fprintf(stderr, "%s\n", self->isa->name);
    _assert(false);
}

@end
/* }}} */
/* Reset View (UITable) {{{ */
@interface UITable (CYResetView)
- (void) resetViewAnimated:(BOOL)animated;
@end

@implementation UITable (CYResetView)

- (void) resetViewAnimated:(BOOL)animated {
    [self selectRow:-1 byExtendingSelection:NO withFade:animated];
}

@end
/* }}} */
/* Reset View (UISectionList) {{{ */
@interface UISectionList (CYResetView)
- (void) resetViewAnimated:(BOOL)animated;
@end

@implementation UISectionList (CYResetView)

- (void) resetViewAnimated:(BOOL)animated {
    [[self table] resetViewAnimated:animated];
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
/* CoreGraphicsServices Primitives {{{ */
class CGColor {
  private:
    CGColorRef color_;

  public:
    CGColor(CGColorSpaceRef space, float red, float green, float blue, float alpha) {
        float color[] = {red, green, blue, alpha};
        color_ = CGColorCreate(space, color);
    }

    ~CGColor() {
        CGColorRelease(color_);
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
        /* XXX: no GSFontRelease()? */
        CFRelease(font_);
    }
};
/* }}} */

static const int PulseInterval_ = 50000;
const char *Machine_ = NULL;
const char *SerialNumber_ = NULL;

bool bootstrap_ = false;

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

@protocol ProgressDelegate
- (void) setError:(NSString *)error;
- (void) setTitle:(NSString *)title;
- (void) setPercent:(float)percent;
- (void) addOutput:(NSString *)output;
@end

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
    if (html)
        [text setHTML:value];
    else
        [text setText:value];
    [text setEnabled:NO];

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGColor clear(space, 0, 0, 0, 0);
    [text setBackgroundColor:clear];
    CGColorSpaceRelease(space);

    CGRect frame = [text frame];
    [text setFrame:frame];
    CGRect rect = [text visibleTextRect];
    frame.size.height = rect.size.height;
    [text setFrame:frame];

    return text;
}

/* Status Delegation {{{ */
class Status :
    public pkgAcquireStatus
{
  private:
    id delegate_;

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
        [delegate_ setTitle:[NSString stringWithCString:("Downloading " + item.ShortDesc).c_str()]];
    }

    virtual void Done(pkgAcquire::ItemDesc &item) {
    }

    virtual void Fail(pkgAcquire::ItemDesc &item) {
        if (
            item.Owner->Status == pkgAcquire::Item::StatIdle ||
            item.Owner->Status == pkgAcquire::Item::StatDone
        )
            return;

        [delegate_ setError:[NSString stringWithCString:item.Owner->ErrorText.c_str()]];
    }

    virtual bool Pulse(pkgAcquire *Owner) {
        bool value = pkgAcquireStatus::Pulse(Owner);

        float percent(
            double(CurrentBytes + CurrentItems) /
            double(TotalBytes + TotalItems)
        );

        [delegate_ setPercent:percent];
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
    id delegate_;

  protected:
    virtual void Update() {
        [delegate_ setTitle:[NSString stringWithCString:Op.c_str()]];
        [delegate_ setPercent:(Percent / 100)];
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
        [delegate_ setPercent:1];
    }
};
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
/* Mime Addresses {{{ */
Pcre email_r("^\"?(.*)\"? <([^>]*)>$");

@interface Address : NSObject {
    NSString *name_;
    NSString *email_;
}

- (void) dealloc;

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
/* Linear Algebra {{{ */
inline float interpolate(float begin, float end, float fraction) {
    return (end - begin) * fraction + begin;
}
/* }}} */

@class Package;

/* Database Interface {{{ */
@interface Database : NSObject {
    pkgCacheFile cache_;
    pkgRecords *records_;
    pkgProblemResolver *resolver_;
    pkgAcquire *fetcher_;
    FileFd *lock_;
    SPtr<pkgPackageManager> manager_;

    id delegate_;
    Status status_;
    Progress progress_;
    int statusfd_;
}

- (void) dealloc;

- (void) _readStatus:(NSNumber *)fd;
- (void) _readOutput:(NSNumber *)fd;

- (Package *) packageWithName:(NSString *)name;

- (Database *) init;
- (pkgCacheFile &) cache;
- (pkgRecords *) records;
- (pkgProblemResolver *) resolver;
- (pkgAcquire &) fetcher;
- (void) reloadData;

- (void) prepare;
- (void) perform;
- (void) update;
- (void) upgrade;

- (void) setDelegate:(id)delegate;
@end
/* }}} */

/* Reset View {{{ */
@interface ResetView : UIView {
    UIPushButton *configure_;
    UIPushButton *reload_;
    NSMutableArray *views_;
    UINavigationBar *navbar_;
    UITransitionView *transition_;
    bool resetting_;
    id delegate_;
}

- (void) dealloc;

- (void) navigationBar:(UINavigationBar *)navbar poppedItem:(UINavigationItem *)item;
- (void) alertSheet:(UIAlertSheet *)sheet buttonClicked:(int)button;

- (id) initWithFrame:(CGRect)frame;
- (void) setDelegate:(id)delegate;

- (void) configurePushed;
- (void) reloadPushed;

- (void) pushView:(UIView *)view withTitle:(NSString *)title backButtonTitle:(NSString *)back rightButton:(NSString *)right;
- (void) popViews:(unsigned)views;
- (void) resetView:(BOOL)clear;
- (void) _resetView;
- (void) setPrompt;
@end

@implementation ResetView

- (void) dealloc {
    [configure_ release];
    [reload_ release];
    [transition_ release];
    [navbar_ release];
    [views_ release];
    [super dealloc];
}

- (void) navigationBar:(UINavigationBar *)navbar poppedItem:(UINavigationItem *)item {
    [views_ removeLastObject];
    UIView *view([views_ lastObject]);
    [view resetViewAnimated:!resetting_];

    if (!resetting_) {
        [transition_ transition:2 toView:view];
        [self _resetView];
    }
}

- (void) alertSheet:(UIAlertSheet *)sheet buttonClicked:(int)button {
    [sheet dismiss];
}

- (id) initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame]) != nil) {
        views_ = [[NSMutableArray arrayWithCapacity:4] retain];

        struct CGRect bounds = [self bounds];
        CGSize navsize = [UINavigationBar defaultSizeWithPrompt];
        CGRect navrect = {{0, 0}, navsize};

        navbar_ = [[UINavigationBar alloc] initWithFrame:navrect];
        [self addSubview:navbar_];

        [navbar_ setBarStyle:1];
        [navbar_ setDelegate:self];

        transition_ = [[UITransitionView alloc] initWithFrame:CGRectMake(
            bounds.origin.x, bounds.origin.y + navsize.height, bounds.size.width, bounds.size.height - navsize.height
        )];

        //configure_ = [[UIPushButton alloc] initWithFrame:CGRectMake(15, 9, 17, 18)];
        configure_ = [[UIPushButton alloc] initWithFrame:CGRectMake(10, 9, 17, 18)];
        [configure_ setShowPressFeedback:YES];
        [configure_ setImage:[UIImage applicationImageNamed:@"configure.png"]];
        [configure_ addTarget:self action:@selector(configurePushed) forEvents:1];

        //reload_ = [[UIPushButton alloc] initWithFrame:CGRectMake(288, 5, 18, 22)];
        reload_ = [[UIPushButton alloc] initWithFrame:CGRectMake(293, 5, 18, 22)];
        [reload_ setShowPressFeedback:YES];
        [reload_ setImage:[UIImage applicationImageNamed:@"reload.png"]];
        [reload_ addTarget:self action:@selector(reloadPushed) forEvents:1];

        [navbar_ addSubview:configure_];
        [navbar_ addSubview:reload_];

        [self addSubview:transition_];
    } return self;
}

- (void) setDelegate:(id)delegate {
    delegate_ = delegate;
}

- (void) configurePushed {
    UIAlertSheet *sheet = [[[UIAlertSheet alloc]
        initWithTitle:@"Sources Unimplemented"
        buttons:[NSArray arrayWithObjects:@"Okay", nil]
        defaultButtonIndex:0
        delegate:self
        context:self
    ] autorelease];

    [sheet setBodyText:@"This feature will be implemented soon. In the mean time, you may add sources by adding .list files to '/etc/apt/sources.list.d' or modifying '/etc/apt/sources.list'."];
    [sheet popupAlertAnimated:YES];
}

- (void) reloadPushed {
    [delegate_ update];
}

- (void) pushView:(UIView *)view withTitle:(NSString *)title backButtonTitle:(NSString *)back rightButton:(NSString *)right {
    UINavigationItem *navitem = [[[UINavigationItem alloc] initWithTitle:title] autorelease];
    [navbar_ pushNavigationItem:navitem];
    [navitem setBackButtonTitle:back];

    [navbar_ showButtonsWithLeftTitle:nil rightTitle:right];

    [transition_ transition:([views_ count] == 0 ? 0 : 1) toView:view];
    [views_ addObject:view];
}

- (void) popViews:(unsigned)views {
    resetting_ = true;
    for (unsigned i(0); i != views; ++i)
        [navbar_ popNavigationItem];
    resetting_ = false;

    [self _resetView];
    [transition_ transition:2 toView:[views_ lastObject]];
}

- (void) resetView:(BOOL)clear {
    resetting_ = true;

    if ([views_ count] > 1) {
        [navbar_ disableAnimation];
        while ([views_ count] != (clear ? 1 : 2))
            [navbar_ popNavigationItem];
        [navbar_ enableAnimation];
        if (!clear)
            [navbar_ popNavigationItem];
    }

    resetting_ = false;

    [self _resetView];
    [transition_ transition:(clear ? 0 : 2) toView:[views_ lastObject]];
}

- (void) _resetView {
    [navbar_ showButtonsWithLeftTitle:nil rightTitle:nil];
}

- (void) setPrompt {
    [navbar_ setPrompt:[NSString stringWithFormat:@"Last Updated: %@", GetLastUpdate()]];
}

@end
/* }}} */
/* Confirmation View {{{ */
void AddTextView(NSMutableDictionary *fields, NSMutableArray *packages, NSString *key) {
    if ([packages count] == 0)
        return;

    UITextView *text = GetTextView([packages count] == 0 ? @"n/a" : [packages componentsJoinedByString:@", "], 110, false);
    [fields setObject:text forKey:key];

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGColor blue(space, 0, 0, 0.4, 1);
    [text setTextColor:blue];
    CGColorSpaceRelease(space);
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

- (void) dealloc;
- (void) cancel;

- (void) transitionViewDidComplete:(UITransitionView*)view fromView:(UIView*)from toView:(UIView*)to;
- (void) navigationBar:(UINavigationBar *)navbar buttonClicked:(int)button;
- (void) alertSheet:(UIAlertSheet *)sheet buttonClicked:(int)button;

- (int) numberOfGroupsInPreferencesTable:(UIPreferencesTable *)table;
- (NSString *) preferencesTable:(UIPreferencesTable *)table titleForGroup:(int)group;
- (float) preferencesTable:(UIPreferencesTable *)table heightForRow:(int)row inGroup:(int)group withProposedHeight:(float)proposed;
- (int) preferencesTable:(UIPreferencesTable *)table numberOfRowsInGroup:(int)group;
- (UIPreferencesTableCell *) preferencesTable:(UIPreferencesTable *)table cellForRow:(int)row inGroup:(int)group;

- (id) initWithView:(UIView *)view database:(Database *)database delegate:(id)delegate;

@end

@implementation ConfirmationView
#include "internals.h"

- (void) dealloc {
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
        NSMutableArray *upgrading = [NSMutableArray arrayWithCapacity:16];
        NSMutableArray *removing = [NSMutableArray arrayWithCapacity:16];

        bool essential(false);

        pkgCacheFile &cache([database_ cache]);
        for (pkgCache::PkgIterator iterator = cache->PkgBegin(); !iterator.end(); ++iterator) {
            NSString *name([NSString stringWithCString:iterator.Name()]);
            if (cache[iterator].NewInstall())
                [installing addObject:name];
            else if (cache[iterator].Upgrade())
                [upgrading addObject:name];
            else if (cache[iterator].Delete()) {
                [removing addObject:name];
                if ((iterator->Flags & pkgCache::Flag::Essential) != 0)
                    essential = true;
            }
        }

        if (!essential)
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
        AddTextView(fields_, upgrading, @"Upgrading");
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
    Database *database_;
    pkgCache::VerIterator version_;
    pkgCache::VerFileIterator file_;

    NSString *latest_;
    NSString *installed_;

    NSString *id_;
    NSString *name_;
    NSString *tagline_;
    NSString *icon_;
    NSString *bundle_;
    NSString *website_;
}

- (void) dealloc;

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

- (NSString *) id;
- (NSString *) name;
- (NSString *) tagline;
- (NSString *) icon;
- (NSString *) bundle;
- (NSString *) website;

- (BOOL) matches:(NSString *)text;

- (NSComparisonResult) compareByName:(Package *)package;
- (NSComparisonResult) compareBySectionAndName:(Package *)package;
- (NSComparisonResult) compareForChanges:(Package *)package;

- (void) install;
- (void) remove;
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
    if (bundle_ != nil)
        [bundle_ release];
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
        bundle_ = Scour("Bundle", begin, end);
        if (bundle_ != nil)
            bundle_ = [bundle_ retain];
        website_ = Scour("Website", begin, end);
        if (website_ != nil)
            website_ = [website_ retain];

        NSMutableDictionary *metadata = [Packages_ objectForKey:id_];
        if (metadata == nil) {
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
    return [[NSString stringWithCString:iterator_.Section()] stringByReplacingCharacter:'_' withCharacter:' '];
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
    return [[[self name] substringToIndex:1] uppercaseString];
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
    NSString *installed = [self installed];
    return installed != nil && [[self latest] compare:installed] != NSOrderedSame ? YES : NO;
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

- (NSString *) bundle {
    return bundle_;
}

- (NSString *) website {
    return website_;
}

- (BOOL) matches:(NSString *)text {
    if (text == nil)
        return NO;

    NSRange range;

    range = [[self name] rangeOfString:text options:NSCaseInsensitiveSearch];
    if (range.location != NSNotFound)
        return YES;

    range = [[self tagline] rangeOfString:text options:NSCaseInsensitiveSearch];
    if (range.location != NSNotFound)
        return YES;

    return NO;
}

- (NSComparisonResult) compareByName:(Package *)package {
    return [[self name] caseInsensitiveCompare:[package name]];
}

- (NSComparisonResult) compareBySectionAndName:(Package *)package {
    NSComparisonResult result = [[self section] compare:[package section]];
    if (result != NSOrderedSame)
        return result;
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
    [database_ cache]->MarkInstall(iterator_, false);
}

- (void) remove {
    pkgProblemResolver *resolver = [database_ resolver];
    resolver->Clear(iterator_);
    resolver->Protect(iterator_);
    resolver->Remove(iterator_);
    [database_ cache]->MarkDelete(iterator_, true);
}

@end
/* }}} */
/* Section Class {{{ */
@interface Section : NSObject {
    NSString *name_;
    size_t row_;
    NSMutableArray *packages_;
}

- (void) dealloc;

- (Section *) initWithName:(NSString *)name row:(size_t)row;
- (NSString *) name;
- (size_t) row;
- (NSArray *) packages;
- (size_t) count;
- (void) addPackage:(Package *)package;
@end

@implementation Section

- (void) dealloc {
    [name_ release];
    [packages_ release];
    [super dealloc];
}

- (Section *) initWithName:(NSString *)name row:(size_t)row {
    if ((self = [super init]) != nil) {
        name_ = [name retain];
        row_ = row;
        packages_ = [[NSMutableArray arrayWithCapacity:16] retain];
    } return self;
}

- (NSString *) name {
    return name_;
}

- (size_t) row {
    return row_;
}

- (NSArray *) packages {
    return packages_;
}

- (size_t) count {
    return [packages_ count];
}

- (void) addPackage:(Package *)package {
    [packages_ addObject:package];
}

@end
/* }}} */

/* Package View {{{ */
@protocol PackageViewDelegate
- (void) performPackage:(Package *)package;
@end

@interface PackageView : UIView {
    UIPreferencesTable *table_;
    Package *package_;
    UITextView *description_;
    id delegate_;
}

- (void) dealloc;

- (int) numberOfGroupsInPreferencesTable:(UIPreferencesTable *)table;
- (NSString *) preferencesTable:(UIPreferencesTable *)table titleForGroup:(int)group;
- (float) preferencesTable:(UIPreferencesTable *)table heightForRow:(int)row inGroup:(int)group withProposedHeight:(float)proposed;
- (int) preferencesTable:(UIPreferencesTable *)table numberOfRowsInGroup:(int)group;
- (UIPreferencesTableCell *) preferencesTable:(UIPreferencesTable *)table cellForRow:(int)row inGroup:(int)group;

- (BOOL) canSelectRow:(int)row;
- (void) tableRowSelected:(NSNotification *)notification;

- (Package *) package;

- (id) initWithFrame:(struct CGRect)frame;
- (void) setPackage:(Package *)package;
- (void) setDelegate:(id)delegate;
@end

@implementation PackageView

- (void) dealloc {
    if (package_ != nil)
        [package_ release];
    if (description_ != nil)
        [description_ release];
    [table_ release];
    [super dealloc];
}

- (int) numberOfGroupsInPreferencesTable:(UIPreferencesTable *)table {
    return 2;
}

- (NSString *) preferencesTable:(UIPreferencesTable *)table titleForGroup:(int)group {
    switch (group) {
        case 0: return nil;
        case 1: return @"Details";
        case 2: return @"Source";

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
        case 2: return 0;

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

            case 2:
                [cell setTitle:@"Section"];
                [cell setValue:[package_ section]];
            break;

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
        } break;

        default: _assert(false);
    }

    return cell;
}

- (BOOL) canSelectRow:(int)row {
    return YES;
}

- (void) tableRowSelected:(NSNotification *)notification {
    switch ([table_ selectedRow]) {
        case 8:
            [delegate_ openURL:[NSURL URLWithString:[NSString stringWithFormat:@"mailto:%@?subject=%@",
                [[package_ maintainer] email],
                [[NSString stringWithFormat:@"regarding apt package \"%@\"", [package_ name]] stringByAddingPercentEscapes]
            ]]];
        break;
    }
}

- (Package *) package {
    return package_;
}

- (id) initWithFrame:(struct CGRect)frame {
    if ((self = [super initWithFrame:frame]) != nil) {
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

    if (description_ != nil) {
        [description_ release];
        description_ = nil;
    }

    if (package != nil) {
        package_ = [package retain];

        NSString *description([package description]);
        if (description == nil)
            description = [package tagline];
        description_ = [GetTextView(description, 12, true) retain];

        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGColor black(space, 0, 0, 0, 1);
        [description_ setTextColor:black];
        CGColorSpaceRelease(space);

        [table_ reloadData];
    }
}

- (void) setDelegate:(id)delegate {
    delegate_ = delegate;
}

@end
/* }}} */
/* Package Cell {{{ */
@interface PackageCell : UITableCell {
    UITextLabel *name_;
    UITextLabel *version_;
    UITextLabel *description_;
    SEL versioner_;
}

- (void) dealloc;

- (PackageCell *) initWithVersioner:(SEL)versioner;
- (void) setPackage:(Package *)package;

- (void) _setSelected:(float)fraction;
- (void) setSelected:(BOOL)selected;
- (void) setSelected:(BOOL)selected withFade:(BOOL)fade;
- (void) _setSelectionFadeFraction:(float)fraction;

@end

@implementation PackageCell

- (void) dealloc {
    [name_ release];
    [version_ release];
    [description_ release];
    [super dealloc];
}

- (PackageCell *) initWithVersioner:(SEL)versioner {
    if ((self = [super init]) != nil) {
        versioner_ = versioner;

        GSFontRef bold = GSFontCreateWithName("Helvetica", kGSFontTraitBold, 22);
        GSFontRef large = GSFontCreateWithName("Helvetica", kGSFontTraitNone, 16);
        GSFontRef small = GSFontCreateWithName("Helvetica", kGSFontTraitNone, 14);

        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();

        CGColor clear(space, 0, 0, 0, 0);

        name_ = [[UITextLabel alloc] initWithFrame:CGRectMake(12, 7, 250, 25)];
        [name_ setBackgroundColor:clear];
        [name_ setFont:bold];

        version_ = [[UIRightTextLabel alloc] initWithFrame:CGRectMake(286, 7, 70, 25)];
        [version_ setBackgroundColor:clear];
        [version_ setFont:large];

        description_ = [[UITextLabel alloc] initWithFrame:CGRectMake(13, 35, 315, 20)];
        [description_ setBackgroundColor:clear];
        [description_ setFont:small];

        [self addSubview:name_];
        [self addSubview:version_];
        [self addSubview:description_];

        CGColorSpaceRelease(space);

        CFRelease(small);
        CFRelease(large);
        CFRelease(bold);
    } return self;
}

- (void) setPackage:(Package *)package {
    [name_ setText:[package name]];
    [version_ setText:[package latest]];
    [description_ setText:[package tagline]];
}

- (void) _setSelected:(float)fraction {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();

    CGColor black(space,
        interpolate(0.0, 1.0, fraction),
        interpolate(0.0, 1.0, fraction),
        interpolate(0.0, 1.0, fraction),
    1.0);

    CGColor blue(space,
        interpolate(0.2, 1.0, fraction),
        interpolate(0.2, 1.0, fraction),
        interpolate(1.0, 1.0, fraction),
    1.0);

    CGColor gray(space,
        interpolate(0.4, 1.0, fraction),
        interpolate(0.4, 1.0, fraction),
        interpolate(0.4, 1.0, fraction),
    1.0);

    [name_ setColor:black];
    [version_ setColor:blue];
    [description_ setColor:gray];

    CGColorSpaceRelease(space);
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
        [delegate_ setPercent:(percent / 100)];

        NSString *string = [NSString stringWithCString:(data + matches[8]) length:(matches[9] - matches[8])];
        std::string type(line.substr(matches[2], matches[3] - matches[2]));

        if (type == "pmerror")
            [delegate_ setError:string];
        else if (type == "pmstatus")
            [delegate_ setTitle:string];
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
        [delegate_ addOutput:[NSString stringWithCString:line.c_str()]];

    [pool release];
    _assert(false);
}

- (Package *) packageWithName:(NSString *)name {
    pkgCache::PkgIterator iterator(cache_->FindPkg([name cString]));
    return iterator.end() ? nil : [Package packageWithIterator:iterator database:self];
}

- (Database *) init {
    if ((self = [super init]) != nil) {
        records_ = NULL;
        resolver_ = NULL;
        fetcher_ = NULL;
        lock_ = NULL;

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

- (void) reloadData {
    _error->Discard();
    manager_ = NULL;
    delete lock_;
    delete fetcher_;
    delete resolver_;
    delete records_;
    cache_.Close();
    _assert(cache_.Open(progress_, true));
    records_ = new pkgRecords(cache_);
    resolver_ = new pkgProblemResolver(cache_);
    fetcher_ = new pkgAcquire(&status_);
    lock_ = NULL;
}

- (void) prepare {
    pkgRecords records(cache_);

    lock_ = new FileFd();
    lock_->Fd(GetLock(_config->FindDir("Dir::Cache::Archives") + "lock"));
    _assert(!_error->PendingError());

    pkgSourceList list;
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

- (void) update {
    pkgSourceList list;
    _assert(list.ReadMainList());

    FileFd lock;
    lock.Fd(GetLock(_config->FindDir("Dir::State::Lists") + "lock"));
    _assert(!_error->PendingError());

    pkgAcquire fetcher(&status_);
    _assert(list.GetIndexes(&fetcher));
    _assert(fetcher.Run(PulseInterval_) != pkgAcquire::Failed);

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

- (void) setDelegate:(id)delegate {
    delegate_ = delegate;
    status_.setDelegate(delegate);
    progress_.setDelegate(delegate);
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

- (void) dealloc;

- (void) transitionViewDidComplete:(UITransitionView*)view fromView:(UIView*)from toView:(UIView*)to;

- (ProgressView *) initWithFrame:(struct CGRect)frame delegate:(id)delegate;
- (void) setContentView:(UIView *)view;
- (void) resetView;

- (void) alertSheet:(UIAlertSheet *)sheet buttonClicked:(int)button;

- (void) _retachThread;
- (void) _detachNewThreadData:(ProgressData *)data;
- (void) detachNewThreadSelector:(SEL)selector toTarget:(id)target withObject:(id)object title:(NSString *)title;

- (void) setError:(NSString *)error;
- (void) _setError:(NSString *)error;

- (void) setTitle:(NSString *)title;
- (void) _setTitle:(NSString *)title;

- (void) setPercent:(float)percent;
- (void) _setPercent:(NSNumber *)percent;

- (void) addOutput:(NSString *)output;
- (void) _addOutput:(NSString *)output;
@end

@protocol ProgressViewDelegate
- (void) progressViewIsComplete:(ProgressView *)sender;
@end

@implementation ProgressView

- (void) dealloc {
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

        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();

        CGColor black(space, 0.0, 0.0, 0.0, 1.0);
        CGColor white(space, 1.0, 1.0, 1.0, 1.0);
        CGColor clear(space, 0.0, 0.0, 0.0, 0.0);

        transition_ = [[UITransitionView alloc] initWithFrame:[self bounds]];
        [transition_ setDelegate:self];

        overlay_ = [[UIView alloc] initWithFrame:[transition_ bounds]];

        if (bootstrap_)
            [overlay_ setBackgroundColor:black];
        else {
            background_ = [[UIView alloc] initWithFrame:[self bounds]];
            [background_ setBackgroundColor:black];
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

        [status_ setColor:white];
        [status_ setBackgroundColor:clear];

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

        [output_ setTextColor:white];
        [output_ setBackgroundColor:clear];

        [output_ setMarginTop:0];
        [output_ setAllowsRubberBanding:YES];

        [overlay_ addSubview:output_];
        [overlay_ addSubview:status_];

        [progress_ setStyle:0];

        CGColorSpaceRelease(space);
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

- (void) setError:(NSString *)error {
    [self
        performSelectorOnMainThread:@selector(_setError:)
        withObject:error
        waitUntilDone:YES
    ];
}

- (void) _setError:(NSString *)error {
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

- (void) setTitle:(NSString *)title {
    [self
        performSelectorOnMainThread:@selector(_setTitle:)
        withObject:title
        waitUntilDone:YES
    ];
}

- (void) _setTitle:(NSString *)title {
    [status_ setText:[title stringByAppendingString:@"..."]];
}

- (void) setPercent:(float)percent {
    [self
        performSelectorOnMainThread:@selector(_setPercent:)
        withObject:[NSNumber numberWithFloat:percent]
        waitUntilDone:YES
    ];
}

- (void) _setPercent:(NSNumber *)percent {
    [progress_ setProgress:[percent floatValue]];
}

- (void) addOutput:(NSString *)output {
    [self
        performSelectorOnMainThread:@selector(_addOutput:)
        withObject:output
        waitUntilDone:YES
    ];
}

- (void) _addOutput:(NSString *)output {
    [output_ setText:[NSString stringWithFormat:@"%@\n%@", [output_ text], output]];
    CGSize size = [output_ contentSize];
    CGRect rect = {{0, size.height}, {size.width, 0}};
    [output_ scrollRectToVisible:rect animated:YES];
}

@end
/* }}} */

/* Package Table {{{ */
@protocol PackageTableDelegate
- (void) packageTable:(id)table packageSelected:(Package *)package;
@end

@interface PackageTable : UIView {
    SEL versioner_;
    UISectionList *list_;

    id delegate_;
    NSArray *packages_;
    NSMutableArray *sections_;
}

- (void) dealloc;

- (int) numberOfSectionsInSectionList:(UISectionList *)list;
- (NSString *) sectionList:(UISectionList *)list titleForSection:(int)section;
- (int) sectionList:(UISectionList *)list rowForSection:(int)section;

- (int) numberOfRowsInTable:(UITable *)table;
- (float) table:(UITable *)table heightForRow:(int)row;
- (UITableCell *) table:(UITable *)table cellForRow:(int)row column:(UITableColumn *)col reusing:(UITableCell *)reusing;
- (BOOL) table:(UITable *)table showDisclosureForRow:(int)row;
- (void) tableRowSelected:(NSNotification *)notification;

- (id) initWithFrame:(CGRect)frame versioner:(SEL)versioner;

- (void) setDelegate:(id)delegate;
- (void) setPackages:(NSArray *)packages;

- (void) resetViewAnimated:(BOOL)animated;
- (UITable *) table;
@end

@implementation PackageTable

- (void) dealloc {
    [list_ release];
    [sections_ release];
    if (packages_ != nil)
        [packages_ release];
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
    return 64;
}

- (UITableCell *) table:(UITable *)table cellForRow:(int)row column:(UITableColumn *)col reusing:(UITableCell *)reusing {
    if (reusing == nil)
        reusing = [[[PackageCell alloc] initWithVersioner:versioner_] autorelease];
    [(PackageCell *)reusing setPackage:[packages_ objectAtIndex:row]];
    return reusing;
}

- (BOOL) table:(UITable *)table showDisclosureForRow:(int)row {
    return NO;
}

- (void) tableRowSelected:(NSNotification *)notification {
    int row = [[notification object] selectedRow];
    [delegate_ packageTable:self packageSelected:(row == INT_MAX ? nil : [packages_ objectAtIndex:row])];
}

- (id) initWithFrame:(CGRect)frame versioner:(SEL)versioner {
    if ((self = [super initWithFrame:frame]) != nil) {
        versioner_ = versioner;
        sections_ = [[NSMutableArray arrayWithCapacity:16] retain];

        list_ = [[UISectionList alloc] initWithFrame:[self bounds] showSectionIndex:YES];
        [list_ setDataSource:self];

        UITableColumn *column = [[[UITableColumn alloc]
            initWithTitle:@"Name"
            identifier:@"name"
            width:frame.size.width
        ] autorelease];

        UITable *table = [list_ table];
        [table setSeparatorStyle:1];
        [table addTableColumn:column];
        [table setDelegate:self];
        [table setReusesTableCells:YES];

        [self addSubview:list_];
    } return self;
}

- (void) setDelegate:(id)delegate {
    delegate_ = delegate;
}

- (void) setPackages:(NSArray *)packages {
    if (packages_ != nil)
        [packages_ autorelease];
    _assert(packages != nil);
    packages_ = [packages retain];

    [sections_ removeAllObjects];

    Section *section = nil;

    for (size_t offset(0); offset != [packages_ count]; ++offset) {
        Package *package = [packages_ objectAtIndex:offset];
        NSString *name = [package index];

        if (section == nil || ![[section name] isEqual:name]) {
            section = [[[Section alloc] initWithName:name row:offset] autorelease];
            [sections_ addObject:section];
        }

        [section addPackage:package];
    }

    [list_ reloadData];
}

- (void) resetViewAnimated:(BOOL)animated {
    [[list_ table] selectRow:-1 byExtendingSelection:NO withFade:animated];
}

- (UITable *) table {
    return [list_ table];
}

@end
/* }}} */

/* Section Cell {{{ */
@interface SectionCell : UITableCell {
    UITextLabel *name_;
    UITextLabel *count_;
}

- (void) dealloc;

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

        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGColor clear(space, 0, 0, 0, 0);
        CGColor white(space, 1, 1, 1, 1);

        name_ = [[UITextLabel alloc] initWithFrame:CGRectMake(47, 9, 250, 25)];
        [name_ setBackgroundColor:clear];
        [name_ setFont:bold];

        count_ = [[UITextLabel alloc] initWithFrame:CGRectMake(11, 7, 29, 32)];
        [count_ setCentersHorizontally:YES];
        [count_ setBackgroundColor:clear];
        [count_ setFont:small];
        [count_ setColor:white];

        UIImageView *folder = [[[UIImageView alloc] initWithFrame:CGRectMake(8, 7, 32, 32)] autorelease];
        [folder setImage:[UIImage applicationImageNamed:@"folder.png"]];

        [self addSubview:folder];
        [self addSubview:name_];
        [self addSubview:count_];

        [self _setSelected:0];

        CGColorSpaceRelease(space);

        CFRelease(small);
        CFRelease(bold);
    } return self;
}

- (void) setSection:(Section *)section {
    if (section == nil) {
        [name_ setText:@"All Packages"];
        [count_ setText:nil];
    } else {
        [name_ setText:[section name]];
        [count_ setText:[NSString stringWithFormat:@"%d", [section count]]];
    }
}

- (void) _setSelected:(float)fraction {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();

    CGColor black(space,
        interpolate(0.0, 1.0, fraction),
        interpolate(0.0, 1.0, fraction),
        interpolate(0.0, 1.0, fraction),
    1.0);

    [name_ setColor:black];

    CGColorSpaceRelease(space);
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
/* Install View {{{ */
@interface InstallView : ResetView <
    PackageTableDelegate
> {
    NSArray *sections_;
    UITable *list_;
    PackageTable *table_;
    PackageView *view_;
    NSString *section_;
    NSString *package_;
    NSMutableArray *packages_;
}

- (void) dealloc;

- (void) navigationBar:(UINavigationBar *)navbar buttonClicked:(int)button;

- (int) numberOfRowsInTable:(UITable *)table;
- (float) table:(UITable *)table heightForRow:(int)row;
- (UITableCell *) table:(UITable *)table cellForRow:(int)row column:(UITableColumn *)col reusing:(UITableCell *)reusing;
- (BOOL) table:(UITable *)table showDisclosureForRow:(int)row;
- (void) tableRowSelected:(NSNotification *)notification;

- (void) packageTable:(id)table packageSelected:(Package *)package;

- (id) initWithFrame:(CGRect)frame;
- (void) setPackages:(NSArray *)packages;
- (void) setDelegate:(id)delegate;
@end

@implementation InstallView

- (void) dealloc {
    [packages_ release];
    if (sections_ != nil)
        [sections_ release];
    if (list_ != nil)
        [list_ release];
    if (table_ != nil)
        [table_ release];
    if (view_ != nil)
        [view_ release];
    if (section_ != nil)
        [section_ release];
    if (package_ != nil)
        [package_ release];
    [super dealloc];
}

- (void) navigationBar:(UINavigationBar *)navbar buttonClicked:(int)button {
    if (button == 0) {
        [[view_ package] install];
        [delegate_ resolve];
        [delegate_ perform];
    }
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
    if (row == 0)
        [(SectionCell *)reusing setSection:nil];
    else
        [(SectionCell *)reusing setSection:[sections_ objectAtIndex:(row - 1)]];
    return reusing;
}

- (BOOL) table:(UITable *)table showDisclosureForRow:(int)row {
    return YES;
}

- (void) tableRowSelected:(NSNotification *)notification {
    int row = [[notification object] selectedRow];

    if (row == INT_MAX) {
        [section_ release];
        section_ = nil;

        [table_ release];
        table_ = nil;
    } else {
        _assert(section_ == nil);
        _assert(table_ == nil);

        Section *section;
        NSString *name;

        if (row == 0) {
            section = nil;
            section_ = nil;
            name = @"All Packages";
        } else {
            section = [sections_ objectAtIndex:(row - 1)];
            name = [section name];
            section_ = [name retain];
        }

        table_ = [[PackageTable alloc] initWithFrame:[transition_ bounds] versioner:@selector(latest)];
        [table_ setDelegate:self];
        [table_ setPackages:(section == nil ? packages_ : [section packages])];

        [self pushView:table_ withTitle:name backButtonTitle:@"Packages" rightButton:nil];
    }
}

- (void) packageTable:(id)table packageSelected:(Package *)package {
    if (package == nil) {
        [package_ release];
        package_ = nil;

        [view_ release];
        view_ = nil;
    } else {
        _assert(package_ == nil);
        _assert(view_ == nil);

        package_ = [[package name] retain];

        view_ = [[PackageView alloc] initWithFrame:[transition_ bounds]];
        [view_ setDelegate:delegate_];

        [view_ setPackage:package];

        [self pushView:view_ withTitle:[package name] backButtonTitle:nil rightButton:@"Install"];
    }
}

- (id) initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame]) != nil) {
        packages_ = [[NSMutableArray arrayWithCapacity:16] retain];

        list_ = [[UITable alloc] initWithFrame:[transition_ bounds]];
        [self pushView:list_ withTitle:@"Install" backButtonTitle:@"Sections" rightButton:nil];

        UITableColumn *column = [[[UITableColumn alloc]
            initWithTitle:@"Name"
            identifier:@"name"
            width:frame.size.width
        ] autorelease];

        [list_ setDataSource:self];
        [list_ setSeparatorStyle:1];
        [list_ addTableColumn:column];
        [list_ setDelegate:self];
        [list_ setReusesTableCells:YES];

        [transition_ transition:0 toView:list_];
    } return self;
}

- (void) setPackages:(NSArray *)packages {
    [packages_ removeAllObjects];

    for (size_t i(0); i != [packages count]; ++i) {
        Package *package([packages objectAtIndex:i]);
        if ([package installed] == nil)
            [packages_ addObject:package];
    }

    [packages_ sortUsingSelector:@selector(compareBySectionAndName:)];
    NSMutableArray *sections = [NSMutableArray arrayWithCapacity:16];

    Section *nsection = nil;
    Package *npackage = nil;

    Section *section = nil;
    for (size_t offset = 0, count = [packages_ count]; offset != count; ++offset) {
        Package *package = [packages_ objectAtIndex:offset];
        NSString *name = [package section];

        if (section == nil || ![[section name] isEqual:name]) {
            section = [[[Section alloc] initWithName:name row:offset] autorelease];

            if ([name isEqualToString:section_])
                nsection = section;
            [sections addObject:section];
        }

        if ([[package name] isEqualToString:package_])
            npackage = package;
        [section addPackage:package];
    }

    if (sections_ != nil)
        [sections_ release];
    sections_ = [sections retain];

    [packages_ sortUsingSelector:@selector(compareByName:)];

    [list_ reloadData];

    unsigned views(0);

    if (npackage != nil)
        [view_ setPackage:npackage];
    else if (package_ != nil)
        ++views;

    if (nsection != nil)
        [table_ setPackages:[nsection packages]];
    else if (section_ != nil)
        ++views;

    [self popViews:views];
    [self setPrompt];
}

- (void) setDelegate:(id)delegate {
    if (view_ != nil)
        [view_ setDelegate:delegate];
    [super setDelegate:delegate];
}

@end
/* }}} */
/* Changes View {{{ */
@interface ChangesView : ResetView <
    PackageTableDelegate
> {
    UISectionList *list_;
    NSMutableArray *packages_;
    NSMutableArray *sections_;
    PackageView *view_;
    NSString *package_;
    size_t count_;
}

- (void) dealloc;

- (void) navigationBar:(UINavigationBar *)navbar buttonClicked:(int)button;

- (int) numberOfSectionsInSectionList:(UISectionList *)list;
- (NSString *) sectionList:(UISectionList *)list titleForSection:(int)section;
- (int) sectionList:(UISectionList *)list rowForSection:(int)section;

- (int) numberOfRowsInTable:(UITable *)table;
- (float) table:(UITable *)table heightForRow:(int)row;
- (UITableCell *) table:(UITable *)table cellForRow:(int)row column:(UITableColumn *)col reusing:(UITableCell *)reusing;
- (BOOL) table:(UITable *)table showDisclosureForRow:(int)row;
- (void) tableRowSelected:(NSNotification *)notification;

- (id) initWithFrame:(CGRect)frame;
- (void) setPackages:(NSArray *)packages;
- (void) _resetView;
- (size_t) count;

- (void) setDelegate:(id)delegate;
@end

@implementation ChangesView

- (void) dealloc {
    [list_ release];
    [packages_ release];
    [sections_ release];
    if (view_ != nil)
        [view_ release];
    if (package_ != nil)
        [package_ release];
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
    return 64;
}

- (UITableCell *) table:(UITable *)table cellForRow:(int)row column:(UITableColumn *)col reusing:(UITableCell *)reusing {
    if (reusing == nil)
        reusing = [[[PackageCell alloc] initWithVersioner:NULL] autorelease];
    [(PackageCell *)reusing setPackage:[packages_ objectAtIndex:row]];
    return reusing;
}

- (BOOL) table:(UITable *)table showDisclosureForRow:(int)row {
    return NO;
}

- (void) tableRowSelected:(NSNotification *)notification {
    int row = [[notification object] selectedRow];
    [self packageTable:self packageSelected:(row == INT_MAX ? nil : [packages_ objectAtIndex:row])];
}

- (void) navigationBar:(UINavigationBar *)navbar buttonClicked:(int)button {
    switch (button) {
        case 0:
            [[view_ package] install];
            [delegate_ resolve];
            [delegate_ perform];
        break;

        case 1:
            [delegate_ upgrade];
        break;
    }
}

- (void) packageTable:(id)table packageSelected:(Package *)package {
    if (package == nil) {
        [package_ release];
        package_ = nil;

        [view_ release];
        view_ = nil;
    } else {
        _assert(package_ == nil);
        _assert(view_ == nil);

        package_ = [[package name] retain];

        view_ = [[PackageView alloc] initWithFrame:[transition_ bounds]];
        [view_ setDelegate:delegate_];

        [view_ setPackage:package];

        [self pushView:view_ withTitle:[package name] backButtonTitle:nil rightButton:(
            [package upgradable] ? @"Upgrade" : @"Install"
        )];
    }
}

- (id) initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame]) != nil) {
        packages_ = [[NSMutableArray arrayWithCapacity:16] retain];
        sections_ = [[NSMutableArray arrayWithCapacity:16] retain];

        list_ = [[UISectionList alloc] initWithFrame:[transition_ bounds] showSectionIndex:NO];
        [list_ setShouldHideHeaderInShortLists:NO];
        [list_ setDataSource:self];
        //[list_ setSectionListStyle:1];

        UITableColumn *column = [[[UITableColumn alloc]
            initWithTitle:@"Name"
            identifier:@"name"
            width:frame.size.width
        ] autorelease];

        UITable *table = [list_ table];
        [table setSeparatorStyle:1];
        [table addTableColumn:column];
        [table setDelegate:self];
        [table setReusesTableCells:YES];

        [self pushView:list_ withTitle:@"Changes" backButtonTitle:nil rightButton:nil];
    } return self;
}

- (void) setPackages:(NSArray *)packages {
    [packages_ removeAllObjects];
    for (size_t i(0); i != [packages count]; ++i) {
        Package *package([packages objectAtIndex:i]);
        if ([package installed] == nil || [package upgradable])
            [packages_ addObject:package];
    }

    [packages_ sortUsingSelector:@selector(compareForChanges:)];

    [sections_ removeAllObjects];

    Section *upgradable = [[[Section alloc] initWithName:@"Available Upgrades" row:0] autorelease];
    Section *section = nil;

    count_ = 0;
    Package *npackage = nil;
    for (size_t offset = 0, count = [packages_ count]; offset != count; ++offset) {
        Package *package = [packages_ objectAtIndex:offset];
        if ([[package name] isEqualToString:package_])
            npackage = package;

        if ([package upgradable])
            [upgradable addPackage:package];
        else {
            NSDate *seen = [package seen];

            CFLocaleRef locale = CFLocaleCopyCurrent();
            CFDateFormatterRef formatter = CFDateFormatterCreate(NULL, locale, kCFDateFormatterMediumStyle, kCFDateFormatterMediumStyle);
            CFStringRef formatted = CFDateFormatterCreateStringWithDate(NULL, formatter, (CFDateRef) seen);

            NSString *name = (NSString *) formatted;

            if (section == nil || ![[section name] isEqual:name]) {
                section = [[[Section alloc] initWithName:name row:offset] autorelease];
                [sections_ addObject:section];
            }

            [section addPackage:package];

            CFRelease(formatter);
            CFRelease(formatted);
            CFRelease(locale);
        }
    }

    count_ = [[upgradable packages] count];
    if (count_ != 0)
        [sections_ insertObject:upgradable atIndex:0];

    [list_ reloadData];

    if (npackage != nil)
        [view_ setPackage:npackage];
    else if (package_ != nil)
        [self popViews:1];

    [self _resetView];
    [self setPrompt];
}

- (void) _resetView {
    if ([views_ count] == 1)
        [navbar_ showButtonsWithLeftTitle:(count_ == 0 ? nil : @"Upgrade All") rightTitle:nil];
}

- (size_t) count {
    return count_;
}

- (void) setDelegate:(id)delegate {
    if (view_ != nil)
        [view_ setDelegate:delegate];
    [super setDelegate:delegate];
}

@end
/* }}} */
/* Manage View {{{ */
@interface ManageView : ResetView <
    PackageTableDelegate
> {
    PackageTable *table_;
    PackageView *view_;
    NSString *package_;
}

- (void) dealloc;

- (void) navigationBar:(UINavigationBar *)navbar buttonClicked:(int)button;

- (void) packageTable:(id)table packageSelected:(Package *)package;

- (id) initWithFrame:(CGRect)frame;
- (void) setPackages:(NSArray *)packages;

- (void) setDelegate:(id)delegate;
@end

@implementation ManageView

- (void) dealloc {
    [table_ release];
    if (view_ != nil)
        [view_ release];
    if (package_ != nil)
        [package_ release];
    [super dealloc];
}

- (void) navigationBar:(UINavigationBar *)navbar buttonClicked:(int)button {
    if (button == 0) {
        [[view_ package] remove];
        [delegate_ resolve];
        [delegate_ perform];
    }
}

- (void) packageTable:(id)table packageSelected:(Package *)package {
    if (package == nil) {
        [package_ release];
        package_ = nil;

        [view_ release];
        view_ = nil;
    } else {
        _assert(package_ == nil);
        _assert(view_ == nil);

        package_ = [[package name] retain];

        view_ = [[PackageView alloc] initWithFrame:[transition_ bounds]];
        [view_ setDelegate:delegate_];

        [view_ setPackage:package];

        [self pushView:view_ withTitle:[package name] backButtonTitle:nil rightButton:@"Uninstall"];
    }
}

- (id) initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame]) != nil) {
        table_ = [[PackageTable alloc] initWithFrame:[transition_ bounds] versioner:@selector(latest)];
        [table_ setDelegate:self];

        [self pushView:table_ withTitle:@"Uninstall" backButtonTitle:@"Packages" rightButton:nil];
    } return self;
}

- (void) setPackages:(NSArray *)packages {
    NSMutableArray *local = [NSMutableArray arrayWithCapacity:16];
    for (size_t i(0); i != [packages count]; ++i) {
        Package *package([packages objectAtIndex:i]);
        if ([package installed] != nil)
            [local addObject:package];
    }

    [local sortUsingSelector:@selector(compareByName:)];

    Package *npackage = nil;
    for (size_t offset = 0, count = [local count]; offset != count; ++offset) {
        Package *package = [local objectAtIndex:offset];
        if ([[package name] isEqualToString:package_])
            npackage = package;
    }

    [table_ setPackages:local];

    if (npackage != nil)
        [view_ setPackage:npackage];
    else if (package_ != nil)
        [self popViews:1];

    [self setPrompt];
}

- (void) setDelegate:(id)delegate {
    if (view_ != nil)
        [view_ setDelegate:delegate];
    [super setDelegate:delegate];
}

@end
/* }}} */
/* Search View {{{ */
@protocol SearchViewDelegate
- (void) showKeyboard:(BOOL)show;
@end

@interface SearchView : ResetView <
    PackageTableDelegate
> {
    NSMutableArray *packages_;
    UIView *accessory_;
    UISearchField *field_;
    PackageTable *table_;
    PackageView *view_;
    NSString *package_;
}

- (void) dealloc;

- (void) navigationBar:(UINavigationBar *)navbar buttonClicked:(int)button;
- (void) packageTable:(id)table packageSelected:(Package *)package;

- (void) textFieldDidBecomeFirstResponder:(UITextField *)field;
- (void) textFieldDidResignFirstResponder:(UITextField *)field;

- (void) keyboardInputChanged:(UIFieldEditor *)editor;
- (BOOL) keyboardInput:(id)input shouldInsertText:(NSString *)text isMarkedText:(int)marked;

- (id) initWithFrame:(CGRect)frame;
- (void) setPackages:(NSArray *)packages;

- (void) setDelegate:(id)delegate;
- (void) resetPackage:(Package *)package;
- (void) searchPackages;

@end

@implementation SearchView

- (void) dealloc {
    [packages_ release];
    [accessory_ release];
    [field_ release];
    [table_ release];
    if (view_ != nil)
        [view_ release];
    if (package_ != nil)
        [package_ release];
    [super dealloc];
}

- (void) navigationBar:(UINavigationBar *)navbar buttonClicked:(int)button {
    if (button == 0) {
        Package *package = [view_ package];
        if ([package installed] == nil)
            [package install];
        else
            [package remove];
        [delegate_ resolve];
        [delegate_ perform];
    }
}

- (void) packageTable:(id)table packageSelected:(Package *)package {
    if (package == nil) {
        [navbar_ setAccessoryView:accessory_ animate:(resetting_ ? NO : YES) goingBack:YES];

        [package_ release];
        package_ = nil;

        [view_ release];
        view_ = nil;
    } else {
        [navbar_ setAccessoryView:nil animate:YES goingBack:NO];

        _assert(package_ == nil);
        _assert(view_ == nil);

        package_ = [[package name] retain];

        view_ = [[PackageView alloc] initWithFrame:[transition_ bounds]];
        [view_ setDelegate:delegate_];

        [self pushView:view_ withTitle:[package name] backButtonTitle:nil rightButton:nil];
        [self resetPackage:package];
    }
}

- (void) textFieldDidBecomeFirstResponder:(UITextField *)field {
    [delegate_ showKeyboard:YES];
    [table_ setEnabled:NO];

    /*CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGColor dimmed(alpha, 0, 0, 0, 0.5);
    [editor_ setBackgroundColor:dimmed];
    CGColorSpaceRelease(space);*/
}

- (void) textFieldDidResignFirstResponder:(UITextField *)field {
    [table_ setEnabled:YES];
    [delegate_ showKeyboard:NO];
}

- (void) keyboardInputChanged:(UIFieldEditor *)editor {
    NSString *text([field_ text]);
    [field_ setClearButtonStyle:(text == nil || [text length] == 0 ? 0 : 2)];
}

- (BOOL) keyboardInput:(id)input shouldInsertText:(NSString *)text isMarkedText:(int)marked {
    if ([text length] != 1 || [text characterAtIndex:0] != '\n')
        return YES;

    [self searchPackages];
    [field_ resignFirstResponder];
    return NO;
}

- (id) initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame]) != nil) {
        packages_ = [[NSMutableArray arrayWithCapacity:16] retain];

        table_ = [[PackageTable alloc] initWithFrame:[transition_ bounds] versioner:@selector(latest)];
        [table_ setDelegate:self];

        CGRect area = [self bounds];
        area.origin.y = 30;
        area.origin.x = 0;
        area.size.width -= 12;
        area.size.height = [UISearchField defaultHeight];

        field_ = [[UISearchField alloc] initWithFrame:area];

        GSFontRef font = GSFontCreateWithName("Helvetica", kGSFontTraitNone, 16);
        [field_ setFont:font];
        CFRelease(font);

        [field_ setPlaceholder:@"Package Names & Descriptions"];
        [field_ setPaddingTop:5];
        [field_ setDelegate:self];

        UITextTraits *traits = [field_ textTraits];
        [traits setEditingDelegate:self];
        [traits setReturnKeyType:6];

        accessory_ = [[UIView alloc] initWithFrame:CGRectMake(6, 6, area.size.width, area.size.height + 30)];
        [accessory_ addSubview:field_];

        [navbar_ setAccessoryView:accessory_];
        [self pushView:table_ withTitle:nil backButtonTitle:@"Search" rightButton:nil];

        /* XXX: for the love of god just fix this */
        [navbar_ removeFromSuperview];
        [reload_ removeFromSuperview];
        [configure_ removeFromSuperview];
        [self addSubview:navbar_];
        [self addSubview:reload_];
        [self addSubview:configure_];
    } return self;
}

- (void) setPackages:(NSArray *)packages {
    [packages_ removeAllObjects];
    [packages_ addObjectsFromArray:packages];
    [packages_ sortUsingSelector:@selector(compareByName:)];

    Package *npackage = nil;
    for (size_t offset = 0, count = [packages_ count]; offset != count; ++offset) {
        Package *package = [packages_ objectAtIndex:offset];
        if ([[package name] isEqualToString:package_])
            npackage = package;
    }

    [self searchPackages];

    if (npackage != nil)
        [self resetPackage:npackage];
    else if (package_ != nil)
        [self popViews:1];

    [self setPrompt];
}

- (void) setDelegate:(id)delegate {
    if (view_ != nil)
        [view_ setDelegate:delegate];
    [super setDelegate:delegate];
}

- (void) resetPackage:(Package *)package {
    [view_ setPackage:package];
    NSString *right = [package installed] == nil ? @"Install" : @"Uninstall";
    [navbar_ showButtonsWithLeftTitle:nil rightTitle:right];
}

- (void) searchPackages {
    NSString *text([field_ text]);

    NSMutableArray *packages([NSMutableArray arrayWithCapacity:16]);

    for (size_t offset(0), count([packages_ count]); offset != count; ++offset) {
        Package *package = [packages_ objectAtIndex:offset];
        if ([package matches:text])
            [packages addObject:package];
    }

    [table_ setPackages:packages];
    [[table_ table] scrollPointVisibleAtTopLeft:CGPointMake(0, 0) animated:NO];
}

@end
/* }}} */

@interface Cydia : UIApplication <
    ConfirmationViewDelegate,
    ProgressViewDelegate,
    SearchViewDelegate
> {
    UIWindow *window_;
    UIView *underlay_;
    UIView *overlay_;
    UITransitionView *transition_;
    UIButtonBar *buttonbar_;

    ConfirmationView *confirm_;

    Database *database_;
    ProgressView *progress_;

    UIView *featured_;
    UINavigationBar *navbar_;
    UIScroller *scroller_;
    UIWebView *webview_;
    NSURL *url_;
    UIProgressIndicator *indicator_;

    InstallView *install_;
    ChangesView *changes_;
    ManageView *manage_;
    SearchView *search_;

    bool restart_;
    unsigned tag_;

    UIKeyboard *keyboard_;
}

- (void) loadNews;
- (void) reloadData:(BOOL)reset;
- (void) setPrompt;

- (void) resolve;
- (void) perform;
- (void) upgrade;
- (void) update;

- (void) cancel;
- (void) confirm;

- (void) progressViewIsComplete:(ProgressView *)progress;

- (void) navigationBar:(UINavigationBar *)navbar buttonClicked:(int)button;
- (void) alertSheet:(UIAlertSheet *)sheet buttonClicked:(int)button;
- (void) buttonBarItemTapped:(id)sender;

- (void) view:(UIView *)sender didSetFrame:(CGRect)frame oldFrame:(CGRect)old;

- (void) webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame;

- (void) applicationWillSuspend;
- (void) applicationDidFinishLaunching:(id)unused;
@end

@implementation Cydia
#include "internals.h"

- (void) loadNews {
    NSMutableURLRequest *request = [NSMutableURLRequest
        requestWithURL:url_
        cachePolicy:NSURLRequestReloadIgnoringCacheData
        timeoutInterval:30.0
    ];

    [request addValue:[NSString stringWithCString:Machine_] forHTTPHeaderField:@"X-Machine"];
    [request addValue:[NSString stringWithCString:SerialNumber_] forHTTPHeaderField:@"X-Serial-Number"];

    [webview_ loadRequest:request];
}

- (void) reloadData:(BOOL)reset {
    [database_ reloadData];

    size_t count = 16;

    if (Packages_ == nil) {
        Packages_ = [[NSMutableDictionary alloc] initWithCapacity:count];
        [Metadata_ setObject:Packages_ forKey:@"Packages"];
    }

    now_ = [NSDate date];

    NSMutableArray *packages = [NSMutableArray arrayWithCapacity:count];
    for (pkgCache::PkgIterator iterator = [database_ cache]->PkgBegin(); !iterator.end(); ++iterator)
        if (Package *package = [Package packageWithIterator:iterator database:database_])
            [packages addObject:package];

    [install_ setPackages:packages];
    [changes_ setPackages:packages];
    [manage_ setPackages:packages];
    [search_ setPackages:packages];

    if (size_t count = [changes_ count]) {
        NSString *badge([[NSNumber numberWithInt:count] stringValue]);
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
}

- (void) setPrompt {
    [navbar_ setPrompt:[NSString stringWithFormat:@"Last Updated: %@", GetLastUpdate()]];
}

- (void) resolve {
    pkgProblemResolver *resolver = [database_ resolver];

    resolver->InstallProtect();
    if (!resolver->Resolve(true))
        _error->Discard();
}

- (void) perform {
    [database_ prepare];
    confirm_ = [[ConfirmationView alloc] initWithView:underlay_ database:database_ delegate:self];
}

- (void) upgrade {
    [database_ upgrade];
    [self perform];
}

- (void) cancel {
    [self reloadData:NO];
    [confirm_ release];
    confirm_ = nil;
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

- (void) update {
    [progress_
        detachNewThreadSelector:@selector(update)
        toTarget:database_
        withObject:nil
        title:@"Refreshing Sources..."
    ];
}

- (void) progressViewIsComplete:(ProgressView *)progress {
    [self reloadData:YES];

    if (confirm_ != nil) {
        [underlay_ addSubview:overlay_];
        [confirm_ removeFromSuperview];
        [confirm_ release];
        confirm_ = nil;
    }
}

- (void) navigationBar:(UINavigationBar *)navbar buttonClicked:(int)button {
    switch (button) {
        case 0:
            [self loadNews];
        break;

        case 1:
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
                "http://www.ccs.ucsb.edu/\n"
                "\n"
                "Special Thanks:\n"
                "bad_, BHSPitMonkey, cash, Cobra,\n"
                "core, Corona, crashx, cromas,\n"
                "Darken, dtzWill, Erica, francis,\n"
                "Godores, jerry, Kingstone, lounger,\n"
                "mbranes, rockabilly, tman, Wbiggs"
            ];

            [sheet presentSheetFromButtonBar:buttonbar_];
        break;
    }
}

- (void) alertSheet:(UIAlertSheet *)sheet buttonClicked:(int)button {
    [sheet dismiss];
}

- (void) buttonBarItemTapped:(id)sender {
    UIView *view;
    unsigned tag = [sender tag];

    switch (tag) {
        case 1: view = featured_; break;
        case 2: view = install_; break;
        case 3: view = changes_; break;
        case 4: view = manage_; break;
        case 5: view = search_; break;

        default:
            _assert(false);
    }

    if ([view respondsToSelector:@selector(resetView:)])
        [(id) view resetView:(tag == tag_ ? NO : YES)];
    tag_ = tag;
    [transition_ transition:0 toView:view];
}

- (void) view:(UIView *)sender didSetFrame:(CGRect)frame oldFrame:(CGRect)old {
    [scroller_ setContentSize:frame.size];
    [indicator_ stopAnimation];
}

- (void) webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame {
    [navbar_ setPrompt:title];
}

- (void) webView:(WebView *)sender didStartProvisionalLoadForFrame:(WebFrame *)frame {
    [navbar_ setPrompt:@"Loading..."];
    [indicator_ startAnimation];
}

- (void) applicationWillSuspend {
    if (restart_)
        system("launchctl stop com.apple.SpringBoard");
    [super applicationWillSuspend];
}

- (void) applicationDidFinishLaunching:(id)unused {
    _assert(pkgInitConfig(*_config));
    _assert(pkgInitSystem(*_config, _system));

    confirm_ = nil;
    restart_ = false;
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

    transition_ = [[UITransitionView alloc] initWithFrame:CGRectMake(
        0, 0, screenrect.size.width, screenrect.size.height - 48
    )];

    [overlay_ addSubview:transition_];

    featured_ = [[UIView alloc] initWithFrame:[transition_ bounds]];

    CGSize navsize = [UINavigationBar defaultSizeWithPrompt];
    CGRect navrect = {{0, 0}, navsize};

    navbar_ = [[UINavigationBar alloc] initWithFrame:navrect];
    [featured_ addSubview:navbar_];

    [navbar_ setBarStyle:1];
    [navbar_ setDelegate:self];

    [navbar_ showButtonsWithLeftTitle:@"About" rightTitle:@"Reload"];

    UINavigationItem *navitem = [[[UINavigationItem alloc] initWithTitle:@"Featured"] autorelease];
    [navbar_ pushNavigationItem:navitem];

    struct CGRect subbounds = [featured_ bounds];
    subbounds.origin.y += navsize.height;
    subbounds.size.height -= navsize.height;

    UIImageView *pinstripe = [[[UIImageView alloc] initWithFrame:subbounds] autorelease];
    [pinstripe setImage:[UIImage applicationImageNamed:@"pinstripe.png"]];
    [featured_ addSubview:pinstripe];

    scroller_ = [[UIScroller alloc] initWithFrame:subbounds];
    [featured_ addSubview:scroller_];

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
    [webview_ setTileSize:CGSizeMake(screenrect.size.width, 500)];
    [webview_ setAutoresizes:YES];
    [webview_ setDelegate:self];

    CGSize indsize = [UIProgressIndicator defaultSizeForStyle:2];
    indicator_ = [[UIProgressIndicator alloc] initWithFrame:CGRectMake(87, 45, indsize.width, indsize.height)];
    [indicator_ setStyle:2];
    [featured_ addSubview:indicator_];

    NSArray *buttonitems = [NSArray arrayWithObjects:
        [NSDictionary dictionaryWithObjectsAndKeys:
            @"buttonBarItemTapped:", kUIButtonBarButtonAction,
            @"featured-up.png", kUIButtonBarButtonInfo,
            @"featured-dn.png", kUIButtonBarButtonSelectedInfo,
            [NSNumber numberWithInt:1], kUIButtonBarButtonTag,
            self, kUIButtonBarButtonTarget,
            @"Featured", kUIButtonBarButtonTitle,
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
            @"Uninstall", kUIButtonBarButtonTitle,
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
    [transition_ transition:0 toView:featured_];

    [overlay_ addSubview:buttonbar_];

    [UIKeyboard initImplementationNow];

    CGRect edtrect = [overlay_ bounds];
    edtrect.origin.y += navsize.height;
    edtrect.size.height -= navsize.height;

    CGSize keysize = [UIKeyboard defaultSize];
    CGRect keyrect = {{0, [overlay_ bounds].size.height - keysize.height}, keysize};
    keyboard_ = [[UIKeyboard alloc] initWithFrame:keyrect];

    database_ = [[Database alloc] init];
    [database_ setDelegate:progress_];

    install_ = [[InstallView alloc] initWithFrame:[transition_ bounds]];
    [install_ setDelegate:self];

    changes_ = [[ChangesView alloc] initWithFrame:[transition_ bounds]];
    [changes_ setDelegate:self];

    manage_ = [[ManageView alloc] initWithFrame:[transition_ bounds]];
    [manage_ setDelegate:self];

    search_ = [[SearchView alloc] initWithFrame:[transition_ bounds]];
    [search_ setDelegate:self];

    [self reloadData:NO];

    Package *package([database_ packageWithName:@"cydia"]);
    NSString *application = package == nil ? @"Cydia" : [NSString stringWithFormat:@"Cydia/%@", [package installed]];

    WebView *webview = [webview_ webView];
    [webview setApplicationNameForUserAgent:application];
    [webview setFrameLoadDelegate:self];

    url_ = [NSURL URLWithString:@"http://cydia.saurik.com/"];
    [self loadNews];

    [progress_ resetView];

    if (bootstrap_)
        [self bootstrap];
}

- (void) showKeyboard:(BOOL)show {
    if (show)
        [overlay_ addSubview:keyboard_];
    else
        [keyboard_ removeFromSuperview];
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

int main(int argc, char *argv[]) {
    struct nlist nl[2];
    memset(nl, 0, sizeof(nl));
    nl[0].n_un.n_name = "_useMDNSResponder";
    nlist("/usr/lib/libc.dylib", nl);
    if (nl[0].n_type != N_UNDF)
        *(int *) nl[0].n_value = 0;

    bootstrap_ = argc > 1 && strcmp(argv[1], "--bootstrap") == 0;

    setuid(0);
    setgid(0);

    /*Method alloc = class_getClassMethod([NSObject class], @selector(alloc));
    alloc_ = alloc->method_imp;
    alloc->method_imp = (IMP) &Alloc_;*/

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

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

    AddPreferences(@"/Applications/Preferences.app/Settings-iPhone.plist");
    AddPreferences(@"/Applications/Preferences.app/Settings-iPod.plist");

    if ((Metadata_ = [[NSMutableDictionary alloc] initWithContentsOfFile:@"/var/lib/cydia/metadata.plist"]) == NULL)
        Metadata_ = [[NSMutableDictionary alloc] initWithCapacity:2];
    else
        Packages_ = [Metadata_ objectForKey:@"Packages"];

    system("dpkg --configure -a");

    UIApplicationMain(argc, argv, [Cydia class]);
    [pool release];
    return 0;
}
