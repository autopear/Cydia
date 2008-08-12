/* Source {{{ */
@interface Source : NSObject {
    NSString *description_;
    NSString *label_;
    NSString *origin_;

    NSString *uri_;
    NSString *distribution_;
    NSString *type_;

    BOOL trusted_;
}

- (void) dealloc;

- (Source *) initWithMetaIndex:(metaIndex *)index;

- (BOOL) trusted;

- (NSString *) uri;
- (NSString *) distribution;
- (NSString *) type;

- (NSString *) description;
- (NSString *) label;
- (NSString *) origin;
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

                if (name == "Description")
                    description_ = [[NSString stringWithCString:value.c_str()] retain];
                else if (name == "Label")
                    label_ = [[NSString stringWithCString:value.c_str()] retain];
                else if (name == "Origin")
                    origin_ = [[NSString stringWithCString:value.c_str()] retain];
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

@end
/* }}} */
/* Source Cell {{{ */
@interface SourceCell : UITableCell {
    UITextLabel *description_;
    UIRightTextLabel *label_;
    UITextLabel *origin_;
}

- (void) dealloc;

- (SourceCell *) initWithSource:(Source *)source;

- (void) _setSelected:(float)fraction;
- (void) setSelected:(BOOL)selected;
- (void) setSelected:(BOOL)selected withFade:(BOOL)fade;
- (void) _setSelectionFadeFraction:(float)fraction;

@end

@implementation SourceCell

- (void) dealloc {
    [description_ release];
    [label_ release];
    [origin_ release];
    [super dealloc];
}

- (SourceCell *) initWithSource:(Source *)source {
    if ((self = [super init]) != nil) {
        GSFontRef bold = GSFontCreateWithName("Helvetica", kGSFontTraitBold, 20);
        GSFontRef small = GSFontCreateWithName("Helvetica", kGSFontTraitNone, 14);

        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        float clear[] = {0, 0, 0, 0};

        NSString *description = [source description];
        if (description == nil)
            description = [source uri];

        description_ = [[UITextLabel alloc] initWithFrame:CGRectMake(12, 7, 270, 25)];
        [description_ setBackgroundColor:CGColorCreate(space, clear)];
        [description_ setFont:bold];
        [description_ setText:description];

        NSString *label = [source label];
        if (label == nil)
            label = [source type];

        label_ = [[UIRightTextLabel alloc] initWithFrame:CGRectMake(290, 32, 90, 25)];
        [label_ setBackgroundColor:CGColorCreate(space, clear)];
        [label_ setFont:small];
        [label_ setText:label];

        NSString *origin = [source origin];
        if (origin == nil)
            origin = [source distribution];

        origin_ = [[UITextLabel alloc] initWithFrame:CGRectMake(13, 35, 315, 20)];
        [origin_ setBackgroundColor:CGColorCreate(space, clear)];
        [origin_ setFont:small];
        [origin_ setText:origin];

        [self addSubview:description_];
        [self addSubview:label_];
        [self addSubview:origin_];

        CFRelease(small);
        CFRelease(bold);
    } return self;
}

- (void) _setSelected:(float)fraction {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();

    float black[] = {
        interpolate(0.0, 1.0, fraction),
        interpolate(0.0, 1.0, fraction),
        interpolate(0.0, 1.0, fraction),
    1.0};

    float blue[] = {
        interpolate(0.2, 1.0, fraction),
        interpolate(0.2, 1.0, fraction),
        interpolate(1.0, 1.0, fraction),
    1.0};

    float gray[] = {
        interpolate(0.4, 1.0, fraction),
        interpolate(0.4, 1.0, fraction),
        interpolate(0.4, 1.0, fraction),
    1.0};

    [description_ setColor:CGColorCreate(space, black)];
    [label_ setColor:CGColorCreate(space, blue)];
    [origin_ setColor:CGColorCreate(space, gray)];
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

/* Sources View {{{ */
@interface SourcesView : UIView {
    UISectionList *list_;
    Database *database_;
    id delegate_;
    NSMutableArray *sources_;
    UIActionSheet *alert_;
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

- (void) dealloc;
- (id) initWithFrame:(CGRect)frame database:(Database *)database;
- (void) setDelegate:(id)delegate;
- (void) reloadData;
- (NSString *) leftTitle;
- (NSString *) rightTitle;
@end

@implementation SourcesView

- (int) numberOfSectionsInSectionList:(UISectionList *)list {
    return 1;
}

- (NSString *) sectionList:(UISectionList *)list titleForSection:(int)section {
    return @"sources";
}

- (int) sectionList:(UISectionList *)list rowForSection:(int)section {
    return 0;
}

- (int) numberOfRowsInTable:(UITable *)table {
    return [sources_ count];
}

- (float) table:(UITable *)table heightForRow:(int)row {
    return 64;
}

- (UITableCell *) table:(UITable *)table cellForRow:(int)row column:(UITableColumn *)col {
    return [[[SourceCell alloc] initWithSource:[sources_ objectAtIndex:row]] autorelease];
}

- (BOOL) table:(UITable *)table showDisclosureForRow:(int)row {
    return NO;
}

- (void) tableRowSelected:(NSNotification*)notification {
    UITable *table([list_ table]);
    int row([table selectedRow]);
    if (row == INT_MAX)
        return;

    [table selectRow:-1 byExtendingSelection:NO withFade:YES];
}

- (void) alertSheet:(UIActionSheet *)sheet buttonClicked:(int)button {
    [alert_ dismiss];
    [alert_ release];
    alert_ = nil;
}

- (void) navigationBar:(UINavigationBar *)navbar buttonClicked:(int)button {
    switch (button) {
        case 0:
            alert_ = [[UIActionSheet alloc]
                initWithTitle:@"Unimplemented"
                buttons:[NSArray arrayWithObjects:@"Okay", nil]
                defaultButtonIndex:0
                delegate:self
                context:self
            ];

            [alert_ setBodyText:@"This feature will be implemented soon. In the mean time, you may add sources by adding .list files to '/etc/apt/sources.list.d'. If you'd like to be in the default list, please contact the author of Packager."];
            [alert_ popupAlertAnimated:YES];
        break;

        case 1:
            [delegate_ update];
        break;
    }
}

- (void) dealloc {
    if (sources_ != nil)
        [sources_ release];
    [list_ release];
    [super dealloc];
}

- (id) initWithFrame:(CGRect)frame database:(Database *)database {
    if ((self = [super initWithFrame:frame]) != nil) {
        database_ = database;
        sources_ = nil;

        CGSize navsize = [UINavigationBar defaultSize];
        CGRect navrect = {{0, 0}, navsize};
        CGRect bounds = [self bounds];

        navbar_ = [[UINavigationBar alloc] initWithFrame:navrect];
        [self addSubview:navbar_];

        [navbar_ setBarStyle:1];
        [navbar_ setDelegate:self];

        UINavigationItem *navitem = [[[UINavigationItem alloc] initWithTitle:@"Sources"] autorelease];
        [navbar_ pushNavigationItem:navitem];

        list_ = [[UISectionList alloc] initWithFrame:CGRectMake(
            0, navsize.height, bounds.size.width, bounds.size.height - navsize.height
        )];

        [self addSubview:list_];

        [list_ setDataSource:self];
        [list_ setShouldHideHeaderInShortLists:NO];

        UITableColumn *column = [[UITableColumn alloc]
            initWithTitle:@"Name"
            identifier:@"name"
            width:frame.size.width
        ];

        UITable *table = [list_ table];
        [table setSeparatorStyle:1];
        [table addTableColumn:column];
        [table setDelegate:self];
    } return self;
}

- (void) setDelegate:(id)delegate {
    delegate_ = delegate;
}

- (void) reloadData {
    pkgSourceList list;
    _assert(list.ReadMainList());

    if (sources_ != nil)
        [sources_ release];

    sources_ = [[NSMutableArray arrayWithCapacity:16] retain];
    for (pkgSourceList::const_iterator source = list.begin(); source != list.end(); ++source)
        [sources_ addObject:[[[Source alloc] initWithMetaIndex:*source] autorelease]];

    [list_ reloadData];
}

- (NSString *) leftTitle {
    return @"Refresh All";
}

- (NSString *) rightTitle {
    return @"Edit";
}

@end
/* }}} */
/* Settings View {{{ */
@interface SettingsView : ResetView {
}

- (void) dealloc;
- (void) reloadData;
@end

@implementation SettingsView

- (void) dealloc {
    [super dealloc];
}

- (id) initWithFrame:(CGRect)frame database:(Database *)database {
    if ((self = [super initWithFrame:frame]) != nil) {
        database_ = database;
        sources_ = nil;

        CGSize navsize = [UINavigationBar defaultSize];
        CGRect navrect = {{0, 0}, navsize};
        CGRect bounds = [self bounds];

        navbar_ = [[UINavigationBar alloc] initWithFrame:navrect];
        [self addSubview:navbar_];

        [navbar_ setBarStyle:1];
        [navbar_ setDelegate:self];

        UINavigationItem *navitem = [[[UINavigationItem alloc] initWithTitle:@"Settings"] autorelease];
        [navbar_ pushNavigationItem:navitem];
    } return self;
}

- (void) reloadData {
    [self resetView];
}

@end
/* }}} */
