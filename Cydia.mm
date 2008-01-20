/* #include Directives {{{ */
#include <UIKit/UIKit.h>
#import <GraphicsServices/GraphicsServices.h>

#include <apt-pkg/acquire.h>
#include <apt-pkg/acquire-item.h>
#include <apt-pkg/algorithms.h>
#include <apt-pkg/cachefile.h>
#include <apt-pkg/configuration.h>
#include <apt-pkg/error.h>
#include <apt-pkg/init.h>
#include <apt-pkg/pkgrecords.h>
#include <apt-pkg/sourcelist.h>

#include <pcre.h>
#include <string.h>
/* }}} */
/* Extension Keywords {{{ */
#define _trace() printf("_trace()@%s:%u[%s]\n", __FILE__, __LINE__, __FUNCTION__)

#define _assert(test) do \
    if (!(test)) { \
        printf("_assert(%s)@%s:%u[%s]\n", #test, __FILE__, __LINE__, __FUNCTION__); \
        exit(-1); \
    } \
while (false)
/* }}} */

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
        [delegate_ performSelectorOnMainThread:@selector(setStatusIMSHit) withObject:nil waitUntilDone:YES];
    }

    virtual void Fetch(pkgAcquire::ItemDesc &item) {
        [delegate_ performSelectorOnMainThread:@selector(setStatusFetch) withObject:nil waitUntilDone:YES];
    }

    virtual void Done(pkgAcquire::ItemDesc &item) {
        [delegate_ performSelectorOnMainThread:@selector(setStatusDone) withObject:nil waitUntilDone:YES];
    }

    virtual void Fail(pkgAcquire::ItemDesc &item) {
        [delegate_ performSelectorOnMainThread:@selector(setStatusFail) withObject:nil waitUntilDone:YES];
    }

    virtual bool Pulse(pkgAcquire *Owner) {
        [delegate_ performSelectorOnMainThread:@selector(setStatusPulse) withObject:nil waitUntilDone:YES];
        return true;
    }

    virtual void Start() {
        [delegate_ performSelectorOnMainThread:@selector(setStatusStart) withObject:nil waitUntilDone:YES];
    }

    virtual void Stop() {
        [delegate_ performSelectorOnMainThread:@selector(setStatusStop) withObject:nil waitUntilDone:YES];
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
        printf("Update(): %f (%s)\n", Percent, Op.c_str());
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
        printf("Done()\n");
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

- (NSString *) name {
    return name_;
}

- (NSString *) email {
    return email_;
}

+ (Address *) addressWithString:(NSString *)string {
    return [[[Address alloc] initWithString:string] retain];
}

- (Address *) initWithString:(NSString *)string {
    if ((self = [super init]) != nil) {
        const char *error;
        int offset;

        pcre *code = pcre_compile("^\"?(.*)\"? <([^>]*)>$", 0, &error, &offset, NULL);

        if (code == NULL) {
            printf("%d:%s\n", offset, error);
            _assert(false);
        }

        pcre_extra *study = NULL;
        int capture;
        pcre_fullinfo(code, study, PCRE_INFO_CAPTURECOUNT, &capture);

        size_t size = [string length];
        const char *data = [string UTF8String];

        int matches[(capture + 1) * 3];
        pcre_exec(code, study, data, size, 0, 0, matches, sizeof(matches) / sizeof(matches[0]));

        name_ = [[NSString stringWithCString:(data + matches[2]) length:(matches[3] - matches[2])] retain];
        email_ = [[NSString stringWithCString:(data + matches[4]) length:(matches[5] - matches[4])] retain];
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

@interface Database : NSObject {
    pkgCacheFile cache_;
    pkgRecords *records_;
    pkgProblemResolver *resolver_;

    Status status_;
    Progress progress_;
}

- (Database *) init;
- (pkgCacheFile &) cache;
- (pkgRecords *) records;
- (pkgProblemResolver *) resolver;
- (void) reloadData;
- (void) update;
- (void) upgrade;
- (void) setDelegate:(id)delegate;
@end

/* Package Class {{{ */
@interface Package : NSObject {
    pkgCache::PkgIterator iterator_;
    Database *database_;
    UITableCell *cell_;
    pkgRecords::Parser *parser_;
    pkgCache::VerIterator version_;
    pkgCache::VerFileIterator file_;
}

- (Package *) initWithIterator:(pkgCache::PkgIterator)iterator database:(Database *)database version:(pkgCache::VerIterator)version file:(pkgCache::VerFileIterator)file;
+ (Package *) packageWithIterator:(pkgCache::PkgIterator)iterator database:(Database *)database;

- (NSString *) name;
- (NSString *) section;
- (BOOL) installed;
- (NSString *) version;
- (Address *) maintainer;
- (size_t) size;
- (NSString *) tagline;
- (NSString *) description;
- (UITableCell *) cell;
- (void) setCell:(UITableCell *)cell;
- (NSComparisonResult) compareBySectionAndName:(Package *)package;

- (void) install;
- (void) remove;
@end

@implementation Package

- (Package *) initWithIterator:(pkgCache::PkgIterator)iterator database:(Database *)database version:(pkgCache::VerIterator)version file:(pkgCache::VerFileIterator)file {
    if ((self = [super init]) != nil) {
        iterator_ = iterator;
        database_ = database;
        cell_ = nil;

        version_ = version;
        file_ = file;
        parser_ = &[database_ records]->Lookup(file);
    } return self;
}

+ (Package *) packageWithIterator:(pkgCache::PkgIterator)iterator database:(Database *)database {
    for (pkgCache::VerIterator version = iterator.VersionList(); !version.end(); ++version)
        for (pkgCache::VerFileIterator file = version.FileList(); !file.end(); ++file)
            return [[Package alloc] initWithIterator:iterator database:database version:version file:file];
    return nil;
}

- (NSString *) name {
    return [NSString stringWithCString:iterator_.Name()];
}

- (NSString *) section {
    return [NSString stringWithCString:iterator_.Section()];
}

- (BOOL) installed {
    return iterator_->CurrentState != pkgCache::State::NotInstalled;
}

- (NSString *) version {
    return [NSString stringWithCString:version_.VerStr()];
}

- (Address *) maintainer {
    return [Address addressWithString:[NSString stringWithCString:parser_->Maintainer().c_str()]];
}

- (size_t) size {
    return version_->InstalledSize;
}

- (NSString *) tagline {
    return [NSString stringWithCString:parser_->ShortDesc().c_str()];
}

- (NSString *) description {
    return [NSString stringWithCString:parser_->LongDesc().c_str()];
}

- (UITableCell *) cell {
    return cell_;
}

- (void) setCell:(UITableCell *)cell {
    cell_ = cell;
}

- (NSComparisonResult) compareBySectionAndName:(Package *)package {
    NSComparisonResult result = [[self section] compare:[package section]];
    if (result != NSOrderedSame)
        return result;
    return [[self name] compare:[package name]];
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
    [database_ cache]->MarkDelete(iterator_, false);
}

@end
/* }}} */
/* Section Class {{{ */
@interface Section : NSObject {
    NSString *name_;
    size_t row_;
    NSMutableArray *packages_;
}

- (Section *) initWithName:(NSString *)name row:(size_t)row;
- (NSString *) name;
- (size_t) row;
- (void) addPackage:(Package *)package;
@end

@implementation Section

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

- (void) addPackage:(Package *)package {
    [packages_ addObject:package];
}

@end
/* }}} */

/* Confirmation View {{{ */
@interface ConfirmationView : UIView {
}

@end

@implementation ConfirmationView
@end
/* }}} */
/* Package View {{{ */
@interface PackageView : UIPreferencesTable {
    Package *package_;
    Database *database_;
    NSMutableArray *cells_;
}

- (int) numberOfGroupsInPreferencesTable:(UIPreferencesTable *)table;
- (int) preferencesTable:(UIPreferencesTable *)table numberOfRowsInGroup:(int)group;
- (UIPreferencesTableCell *) preferencesTable:(UIPreferencesTable *)table cellForRow:(int)row inGroup:(int)group;

- (PackageView *) initWithFrame:(struct CGRect)frame database:(Database *)database;
- (void) setPackage:(Package *)package;
@end

@implementation PackageView

- (int) numberOfGroupsInPreferencesTable:(UIPreferencesTable *)table {
    return 2;
}

- (NSString *) preferencesTable:(UIPreferencesTable *)table titleForGroup:(int)group {
    switch (group) {
        case 0:
            return @"Specifics";
        break;

        case 1:
            return @"Description";
        break;

        default: _assert(false);
    }
}

- (int) preferencesTable:(UIPreferencesTable *)table numberOfRowsInGroup:(int)group {
    switch (group) {
        case 0:
            return 5;
        break;

        case 1:
            return 1;
        break;

        default: _assert(false);
    }
}

- (UIPreferencesTableCell *) preferencesTable:(UIPreferencesTable *)table cellForRow:(int)row inGroup:(int)group {
    UIPreferencesTableCell *cell;

    switch (group) {
        case 0: switch (row) {
            case 0:
                cell = [cells_ objectAtIndex:0];
                [cell setTitle:@"Name"];
                [cell setValue:[package_ name]];
            break;

            case 1:
                cell = [cells_ objectAtIndex:1];
                [cell setTitle:@"Version"];
                [cell setValue:[package_ version]];
            break;

            case 2:
                cell = [cells_ objectAtIndex:2];
                [cell setTitle:@"Section"];
                [cell setValue:[package_ section]];
            break;

            case 3: {
                double size = [package_ size];
                unsigned power = 0;
                while (size > 1024) {
                    size /= 1024;
                    ++power;
                }

                cell = [cells_ objectAtIndex:3];
                [cell setTitle:@"Size"];
                [cell setValue:[NSString stringWithFormat:@"%.1f%c", size, "bkMG"[power]]];
            } break;

            case 4:
                cell = [cells_ objectAtIndex:4];
                [cell setTitle:@"Maintainer"];
                [cell setValue:[[package_ maintainer] name]];
                [cell setShowDisclosure:YES];
                [cell setShowSelection:YES];
            break;

            default: _assert(false);
        } break;

        case 1: switch (row) {
            case 0:
                cell = [cells_ objectAtIndex:5];
                [cell setTitle:@"Tagline"];
                [cell setValue:[package_ tagline]];
            break;

            case 1:
                cell = [cells_ objectAtIndex:6];
                [cell setTitle:@"Description"];
                [cell setValue:[package_ description]];
            break;
        } break;

        default: _assert(false);
    }

    return cell;
}

- (PackageView *) initWithFrame:(struct CGRect)frame database:(Database *)database {
    if ((self = [super initWithFrame:frame]) != nil) {
        database_ = database;
        [self setDataSource:self];

        cells_ = [[NSMutableArray arrayWithCapacity:16] retain];

        for (unsigned i = 0; i != 6; ++i) {
            struct CGRect frame = [self frameOfPreferencesCellAtRow:0 inGroup:0];
            UIPreferencesTableCell *cell = [[UIPreferencesTableCell alloc] init];
            [cell setShowSelection:NO];
            [cells_ addObject:cell];
        }
    } return self;
}

- (void) setPackage:(Package *)package {
    package_ = package;
    [self reloadData];
}

@end
/* }}} */

@implementation Database

- (Database *) init {
    if ((self = [super init]) != nil) {
        records_ = NULL;
        resolver_ = NULL;
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

- (void) reloadData {
    delete resolver_;
    delete records_;
    cache_.Close();
    cache_.Open(progress_, true);
    records_ = new pkgRecords(cache_);
    resolver_ = new pkgProblemResolver(cache_);
}

- (void) update {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    pkgSourceList list;
    _assert(list.ReadMainList());

    FileFd lock;
    lock.Fd(GetLock(_config->FindDir("Dir::State::Lists") + "lock"));
    _assert(!_error->PendingError());

    pkgAcquire fetcher(&status_);
    _assert(list.GetIndexes(&fetcher));
    _assert(fetcher.Run() != pkgAcquire::Failed);

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

    [pool release];
}

- (void) upgrade {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    _assert(cache_->DelCount() == 0 && cache_->InstCount() == 0);
    _assert(pkgApplyStatus(cache_));

    if (cache_->BrokenCount() != 0) {
        _assert(pkgFixBroken(cache_));
        _assert(cache_->BrokenCount() == 0);
        _assert(pkgMinimizeUpgrade(cache_));
    }

    _assert(pkgDistUpgrade(cache_));

    //InstallPackages(cache_, true);

    [pool release];
}

- (void) setDelegate:(id)delegate {
    status_.setDelegate(delegate);
    progress_.setDelegate(delegate);
}

@end

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

@interface ProgressView : UIView {
    UIView *view_;
    UITransitionView *transition_;
    UIView *progress_;
    UINavigationBar *navbar_;
}

- (ProgressView *) initWithFrame:(struct CGRect)frame;
- (void) setContentView:(UIView *)view;
- (void) resetView;

- (void) _detachNewThreadData:(ProgressData *)data;
- (void) detachNewThreadSelector:(SEL)selector toTarget:(id)target withObject:(id)object;

- (void) setStatusIMSHit;
- (void) setStatusFetch;
- (void) setStatusDone;
- (void) setStatusFail;
- (void) setStatusPulse;

- (void) setStatusStart;
- (void) setStatusStop;
@end

@implementation ProgressView

- (ProgressView *) initWithFrame:(struct CGRect)frame {
    if ((self = [super initWithFrame:frame]) != nil) {
        transition_ = [[UITransitionView alloc] initWithFrame:[self bounds]];
        [self addSubview:transition_];

        progress_ = [[UIView alloc] initWithFrame:[transition_ bounds]];

        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        float black[] = {0.0, 0.0, 0.0, 1.0};
        [progress_ setBackgroundColor:CGColorCreate(space, black)];

        CGSize navsize = [UINavigationBar defaultSize];
        CGRect navrect = {{0, 0}, navsize};

        navbar_ = [[UINavigationBar alloc] initWithFrame:navrect];
        [progress_ addSubview:navbar_];

        [navbar_ setBarStyle:1];
        [navbar_ setDelegate:self];

        UINavigationItem *navitem = [[UINavigationItem alloc] initWithTitle:nil];
        [navbar_ pushNavigationItem:navitem];
    } return self;
}

- (void) setContentView:(UIView *)view {
    view_ = view;
}

- (void) resetView {
    [transition_ transition:6 toView:view_];
}

- (void) _detachNewThreadData:(ProgressData *)data {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    [[data target] performSelector:[data selector] withObject:[data object]];
    [self performSelectorOnMainThread:@selector(resetView) withObject:nil waitUntilDone:YES];

    [pool release];
}

- (void) detachNewThreadSelector:(SEL)selector toTarget:(id)target withObject:(id)object {
    [transition_ transition:6 toView:progress_];

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

- (void) setStatusIMSHit {
    _trace();
}

- (void) setStatusFetch {
    _trace();
}

- (void) setStatusDone {
    _trace();
}

- (void) setStatusFail {
    _trace();
}

- (void) setStatusPulse {
    _trace();
}

- (void) setStatusStart {
    _trace();
}

- (void) setStatusStop {
    _trace();
}

@end

@protocol PackagesDelegate

- (void) viewPackage:(Package *)package;

@end

@interface Packages : UIView {
    NSString *title_;
    Database *database_;
    bool (*filter_)(Package *package);
    NSMutableArray *packages_;
    NSMutableArray *sections_;
    id delegate_;
    UISectionList *list_;
    UINavigationBar *navbar_;
    UITransitionView *transition_;
    Package *package_;
    PackageView *pkgview_;
    SEL selector_;
}

- (int) numberOfSectionsInSectionList:(UISectionList *)list;
- (NSString *) sectionList:(UISectionList *)list titleForSection:(int)section;
- (int) sectionList:(UISectionList *)list rowForSection:(int)section;

- (int) numberOfRowsInTable:(UITable *)table;
- (float) table:(UITable *)table heightForRow:(int)row;
- (UITableCell *) table:(UITable *)table cellForRow:(int)row column:(UITableColumn *)col;
- (BOOL) table:(UITable *)table showDisclosureForRow:(int)row;
- (void) tableRowSelected:(NSNotification*)notification;

- (void) navigationBar:(UINavigationBar *)navbar buttonClicked:(int)button;
- (void) navigationBar:(UINavigationBar *)navbar poppedItem:(UINavigationItem *)item;

- (Packages *) initWithFrame:(struct CGRect)frame title:(NSString *)title database:(Database *)database filter:(bool (*)(Package *))filter selector:(SEL)selector;
- (void) setDelegate:(id)delegate;
- (void) addPackage:(Package *)package;
- (NSMutableArray *) packages;
- (void) reloadData;
@end

@implementation Packages

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

- (UITableCell *) table:(UITable *)table cellForRow:(int)row column:(UITableColumn *)col {
    Package *package = [packages_ objectAtIndex:row]; {
        UITableCell *cell = [package cell];
        if (cell != nil)
            return cell;
    }

#if 0
    UIImageAndTextTableCell *cell_ = [[UIImageAndTextTableCell alloc] init];
    [package setCell:cell_];

    [cell_ setTitle:[package name]];
    return cell_;
#endif

    UITableCell *cell = [[UITableCell alloc] init];
    [package setCell:cell];

    GSFontRef bold = GSFontCreateWithName("Helvetica", kGSFontTraitBold, 22);
    GSFontRef large = GSFontCreateWithName("Helvetica", kGSFontTraitNone, 16);
    GSFontRef small = GSFontCreateWithName("Helvetica", kGSFontTraitNone, 14);

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    float blue[] = {0.2, 0.2, 1.0, 1.0};
    float gray[] = {0.4, 0.4, 0.4, 1.0};
    float clear[] = {0, 0, 0, 0};

    UITextLabel *name = [[UITextLabel alloc] initWithFrame:CGRectMake(12, 7, 250, 25)];
    [name setText:[package name]];
    [name setBackgroundColor:CGColorCreate(space, clear)];
    [name setFont:bold];

    UIRightTextLabel *version = [[UIRightTextLabel alloc] initWithFrame:CGRectMake(290, 7, 70, 25)];
    [version setText:[package version]];
    [version setColor:CGColorCreate(space, blue)];
    [version setBackgroundColor:CGColorCreate(space, clear)];
    [version setFont:large];

    UITextLabel *description = [[UITextLabel alloc] initWithFrame:CGRectMake(13, 35, 315, 20)];
    [description setText:[package tagline]];
    [description setColor:CGColorCreate(space, gray)];
    [description setBackgroundColor:CGColorCreate(space, clear)];
    [description setFont:small];

    [cell addSubview:name];
    [cell addSubview:version];
    [cell addSubview:description];

    CFRelease(small);
    CFRelease(large);
    CFRelease(bold);

    return cell;
}

- (BOOL) table:(UITable *)table showDisclosureForRow:(int)row {
    return YES;
}

- (void) tableRowSelected:(NSNotification*)notification {
    int row = [[list_ table] selectedRow];
    if (row == INT_MAX)
        return;

    package_ = [packages_ objectAtIndex:row];

    UINavigationItem *navitem = [[UINavigationItem alloc] initWithTitle:[package_ name]];
    [navbar_ pushNavigationItem:navitem];

    [navbar_ showButtonsWithLeftTitle:nil rightTitle:title_];

    [pkgview_ setPackage:package_];
    [transition_ transition:1 toView:pkgview_];

}

- (void) navigationBar:(UINavigationBar *)navbar buttonClicked:(int)button {
    if (button == 0) {
        printf("bef:%ld\n", [database_ cache]->InstCount());
        [package_ performSelector:selector_];

        pkgProblemResolver *resolver = [database_ resolver];

        resolver->InstallProtect();
        if (!resolver->Resolve(true))
            _error->Discard();

        printf("aft:%ld\n", [database_ cache]->InstCount());
        _assert(false);
    }
}

- (void) navigationBar:(UINavigationBar *)navbar poppedItem:(UINavigationItem *)item {
    [transition_ transition:2 toView:list_];
    [navbar_ showButtonsWithLeftTitle:nil rightTitle:nil];
    UITable *table = [list_ table];
    [table selectRow:-1 byExtendingSelection:NO withFade:YES];
    //UITableCell *cell = [table cellAtRow:[table selectedRow] column:0];
    //[table selectCell:nil inRow:-1 column:-1 withFade:YES];
    //[table highlightRow:-1];
    //[cell setSelected:NO withFade:YES];
    package_ = nil;
}

- (Packages *) initWithFrame:(struct CGRect)frame title:(NSString *)title database:(Database *)database filter:(bool (*)(Package *))filter selector:(SEL)selector {
    if ((self = [super initWithFrame:frame]) != nil) {
        title_ = title;
        database_ = database;
        filter_ = filter;
        selector_ = selector;

        packages_ = [[NSMutableArray arrayWithCapacity:16] retain];

        struct CGRect bounds = [self bounds];
        CGSize navsize = [UINavigationBar defaultSize];
        CGRect navrect = {{0, 0}, navsize};

        navbar_ = [[UINavigationBar alloc] initWithFrame:navrect];
        [self addSubview:navbar_];

        [navbar_ setBarStyle:1];
        [navbar_ setDelegate:self];

        UINavigationItem *navitem = [[UINavigationItem alloc] initWithTitle:title];
        [navbar_ pushNavigationItem:navitem];
        [navitem setBackButtonTitle:@"Packages"];

        transition_ = [[UITransitionView alloc] initWithFrame:CGRectMake(
            bounds.origin.x, bounds.origin.y + navsize.height, bounds.size.width, bounds.size.height - navsize.height
        )];

        [self addSubview:transition_];

        list_ = [[UISectionList alloc] initWithFrame:[transition_ bounds] showSectionIndex:NO];
        [list_ setDataSource:self];

        [transition_ transition:0 toView:list_];

        UITableColumn *column = [[UITableColumn alloc]
            initWithTitle:@"Name"
            identifier:@"name"
            width:frame.size.width
        ];

        UITable *table = [list_ table];
        [table setSeparatorStyle:1];
        [table addTableColumn:column];
        [table setDelegate:self];

        pkgview_ = [[PackageView alloc] initWithFrame:[transition_ bounds] database:database_];
    } return self;
}

- (void) setDelegate:(id)delegate {
    delegate_ = delegate;
}

- (void) addPackage:(Package *)package {
    _assert(sections_ == nil);
    [packages_ addObject:package];
}

- (NSMutableArray *) packages {
    return packages_;
}

- (void) reloadData {
    for (pkgCache::PkgIterator iterator = [database_ cache]->PkgBegin(); !iterator.end(); ++iterator) {
        Package *package = [Package packageWithIterator:iterator database:database_];
        if (package == nil)
            continue;
        if (filter_(package))
            [self addPackage:package];
    }

    [packages_ sortUsingSelector:@selector(compareBySectionAndName:)];
    sections_ = [[NSMutableArray arrayWithCapacity:16] retain];

    Section *section = nil;
    for (size_t offset = 0, count = [packages_ count]; offset != count; ++offset) {
        Package *package = [packages_ objectAtIndex:offset];
        NSString *name = [package section];

        if (section == nil || ![[section name] isEqual:name]) {
            section = [[Section alloc] initWithName:name row:offset];
            [sections_ addObject:section];
        }

        [section addPackage:package];
    }

    [list_ reloadData];
}

@end

bool IsInstalled(Package *package) {
    return [package installed];
}

bool IsNotInstalled(Package *package) {
    return ![package installed];
}

@interface Cydia : UIApplication <PackagesDelegate> {
    UIWindow *window_;
    UITransitionView *transition_;

    Database *database_;
    ProgressView *progress_;

    UIView *featured_;
    UINavigationBar *navbar_;
    UIScroller *scroller_;
    UIWebView *webview_;
    NSURL *url_;

    Packages *install_;
    Packages *uninstall_;
}

- (void) loadNews;
- (void) reloadData;

- (void) navigationBar:(UINavigationBar *)navbar buttonClicked:(int)button;
- (void) buttonBarItemTapped:(id)sender;

- (void) view:(UIView *)sender didSetFrame:(CGRect)frame;
- (void) view:(UIView *)view didDrawInRect:(CGRect)rect duration:(float)duration;

- (void) viewPackage:(Package *)package;

- (void) applicationDidFinishLaunching:(id)unused;
@end

@implementation Cydia

- (void) loadNews {
    [webview_ loadRequest:[NSURLRequest
        requestWithURL:url_
        cachePolicy:NSURLRequestReloadIgnoringCacheData
        timeoutInterval:30.0
    ]];
}

- (void) reloadData {
    [database_ reloadData];
    [install_ reloadData];
    [uninstall_ reloadData];
}

- (void) navigationBar:(UINavigationBar *)navbar buttonClicked:(int)button {
    switch (button) {
        case 0:
            [self loadNews];
        break;

        case 1:
        break;
    }
}

- (void) buttonBarItemTapped:(id)sender {
    UIView *view;

    switch ([sender tag]) {
        case 1: view = featured_; break;
        case 2: view = install_; break;
        case 4: view = uninstall_; break;

        default:
            _assert(false);
    }

    [transition_ transition:0 toView:view];
}

- (void) view:(UIView *)view didSetFrame:(CGRect)frame {
    [scroller_ setContentSize:frame.size];
}

- (void) view:(UIView *)view didDrawInRect:(CGRect)rect duration:(float)duration {
    [scroller_ setContentSize:[webview_ bounds].size];
}

- (void) viewPackage:(Package *)package {
    _assert(false);
}

- (void) applicationDidFinishLaunching:(id)unused {
    _assert(pkgInitConfig(*_config));
    _assert(pkgInitSystem(*_config, _system));

    CGRect screenrect = [UIHardware fullScreenApplicationContentRect];
    window_ = [[UIWindow alloc] initWithContentRect:screenrect];

    [window_ orderFront: self];
    [window_ makeKey: self];
    [window_ _setHidden: NO];

    progress_ = [[ProgressView alloc] initWithFrame:[window_ bounds]];
    [database_ setDelegate:progress_];
    [window_ setContentView:progress_];

    UIView *view = [[UIView alloc] initWithFrame:[progress_ bounds]];
    [progress_ setContentView:view];

    transition_ = [[UITransitionView alloc] initWithFrame:CGRectMake(
        0, 0, screenrect.size.width, screenrect.size.height - 48
    )];

    [view addSubview:transition_];

    featured_ = [[UIView alloc] initWithFrame:[transition_ bounds]];

    CGSize navsize = [UINavigationBar defaultSize];
    CGRect navrect = {{0, 0}, navsize};

    navbar_ = [[UINavigationBar alloc] initWithFrame:navrect];
    [featured_ addSubview:navbar_];

    [navbar_ setBarStyle:1];
    [navbar_ setDelegate:self];

    [navbar_ showButtonsWithLeftTitle:@"About" rightTitle:@"Reload"];

    UINavigationItem *navitem = [[UINavigationItem alloc] initWithTitle:@"Featured"];
    [navbar_ pushNavigationItem:navitem];

    struct CGRect subbounds = [featured_ bounds];
    subbounds.origin.y += navsize.height;
    subbounds.size.height -= navsize.height;

    UIImageView *pinstripe = [[UIImageView alloc] initWithFrame:subbounds];
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

    webview_ = [[UIWebView alloc] initWithFrame:[scroller_ bounds]];
    [scroller_ addSubview:webview_];

    [webview_ setTilingEnabled:YES];
    [webview_ setTileSize:CGSizeMake(screenrect.size.width, 500)];
    [webview_ setAutoresizes:YES];
    [webview_ setDelegate:self];

    url_ = [NSURL URLWithString:@"http://cydia.saurik.com/"];
    [self loadNews];

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
            @"upgrade-up.png", kUIButtonBarButtonInfo,
            @"upgrade-dn.png", kUIButtonBarButtonSelectedInfo,
            [NSNumber numberWithInt:3], kUIButtonBarButtonTag,
            self, kUIButtonBarButtonTarget,
            @"Upgrade", kUIButtonBarButtonTitle,
            @"0", kUIButtonBarButtonType,
        nil],

        [NSDictionary dictionaryWithObjectsAndKeys:
            @"buttonBarItemTapped:", kUIButtonBarButtonAction,
            @"uninstall-up.png", kUIButtonBarButtonInfo,
            @"uninstall-dn.png", kUIButtonBarButtonSelectedInfo,
            [NSNumber numberWithInt:4], kUIButtonBarButtonTag,
            self, kUIButtonBarButtonTarget,
            @"Uninstall", kUIButtonBarButtonTitle,
            @"0", kUIButtonBarButtonType,
        nil],

        [NSDictionary dictionaryWithObjectsAndKeys:
            @"buttonBarItemTapped:", kUIButtonBarButtonAction,
            @"sources-up.png", kUIButtonBarButtonInfo,
            @"sources-dn.png", kUIButtonBarButtonSelectedInfo,
            [NSNumber numberWithInt:5], kUIButtonBarButtonTag,
            self, kUIButtonBarButtonTarget,
            @"Sources", kUIButtonBarButtonTitle,
            @"0", kUIButtonBarButtonType,
        nil],
    nil];

    UIButtonBar *buttonbar = [[UIButtonBar alloc]
        initInView:view
        withFrame:CGRectMake(
            0, screenrect.size.height - 48,
            screenrect.size.width, 48
        )
        withItemList:buttonitems
    ];

    [buttonbar setDelegate:self];
    [buttonbar setBarStyle:1];
    [buttonbar setButtonBarTrackingMode:2];

    int buttons[5] = {1, 2, 3, 4, 5};
    [buttonbar registerButtonGroup:0 withButtons:buttons withCount:5];
    [buttonbar showButtonGroup:0 withDuration:0];

    for (int i = 0; i != 5; ++i)
        [[buttonbar viewWithTag:(i + 1)] setFrame:CGRectMake(
            i * 64 + 2, 1, 60, 48
        )];

    [buttonbar showSelectionForButton:1];
    [transition_ transition:0 toView:featured_];

    [view addSubview:buttonbar];

    database_ = [[Database alloc] init];

    install_ = [[Packages alloc] initWithFrame:[transition_ bounds] title:@"Install" database:database_ filter:&IsNotInstalled selector:@selector(install)];
    [install_ setDelegate:self];

    uninstall_ = [[Packages alloc] initWithFrame:[transition_ bounds] title:@"Uninstall" database:database_ filter:&IsInstalled selector:@selector(remove)];
    [uninstall_ setDelegate:self];

#if 0
    UIAlertSheet *alert = [[UIAlertSheet alloc]
        initWithTitle:@"Alert Title"
        buttons:[NSArray arrayWithObjects:@"Yes", nil]
        defaultButtonIndex:0
        delegate:self
        context:self
    ];

    NSLog(@"%p\n", [alert table]);
    [[alert table] setDelegate:self];
    [[alert table] reloadData];

    [alert addTextFieldWithValue:@"Title" label:@"Label"];
    [alert setShowsOverSpringBoardAlerts:YES];
    [alert setBodyText:@"This is an alert."];
    [alert presentSheetFromButtonBar:buttonbar];
    //[alert popupAlertAnimated:YES];
#endif

    [self reloadData];
    [progress_ resetView];
    //[progress_ detachNewThreadSelector:@selector(reloadData) toTarget:self withObject:nil];
}

@end

int main(int argc, char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    UIApplicationMain(argc, argv, [Cydia class]);
    [pool release];
}
