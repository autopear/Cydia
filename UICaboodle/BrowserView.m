#include <BrowserView.h>

/* Indirect Delegate {{{ */
@interface IndirectDelegate : NSProxy {
    _transient volatile id delegate_;
}

- (void) setDelegate:(id)delegate;
- (id) initWithDelegate:(id)delegate;
@end

@implementation IndirectDelegate

- (void) setDelegate:(id)delegate {
    delegate_ = delegate;
}

- (id) initWithDelegate:(id)delegate {
    delegate_ = delegate;
    return self;
}

- (BOOL) respondsToSelector:(SEL)sel {
    return delegate_ == nil ? FALSE : [delegate_ respondsToSelector:sel];
}

- (NSMethodSignature *) methodSignatureForSelector:(SEL)sel {
    if (delegate_ != nil)
        if (NSMethodSignature *sig = [delegate_ methodSignatureForSelector:sel])
            return sig;
    // XXX: I fucking hate Apple so very very bad
    return [NSMethodSignature signatureWithObjCTypes:"v@:"];
}

- (void) forwardInvocation:(NSInvocation *)inv {
    SEL sel = [inv selector];
    if (delegate_ != nil && [delegate_ respondsToSelector:sel])
        [inv invokeWithTarget:delegate_];
}

@end
/* }}} */

@interface WebView (Cydia)
- (void) setScriptDebugDelegate:(id)delegate;
- (void) _setFormDelegate:(id)delegate;
- (void) _setUIKitDelegate:(id)delegate;
- (void) setWebMailDelegate:(id)delegate;
- (void) _setLayoutInterval:(float)interval;
@end

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

+ (NSString *) webScriptNameForSelector:(SEL)selector {
    if (selector == @selector(getPackageById:))
        return @"getPackageById";
    else if (selector == @selector(setButtonImage:withStyle:toFunction:))
        return @"setButtonImage";
    else if (selector == @selector(setButtonTitle:withStyle:toFunction:))
        return @"setButtonTitle";
    else if (selector == @selector(supports:))
        return @"supports";
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

- (Package *) getPackageById:(NSString *)id {
    return [[Database sharedInstance] packageWithName:id];
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
        execlp("du", "du", "-s", [path UTF8String], NULL);
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

- (void) setButtonImage:(NSString *)button withStyle:(NSString *)style toFunction:(id)function {
    [indirect_ setButtonImage:button withStyle:style toFunction:function];
}

- (void) setButtonTitle:(NSString *)button withStyle:(NSString *)style toFunction:(id)function {
    [indirect_ setButtonTitle:button withStyle:style toFunction:function];
}

@end
/* }}} */

@implementation BrowserView

#if ShowInternals
#include "Internals.h"
#endif

- (void) dealloc {
    NSLog(@"deallocating WebView");

    if (challenge_ != nil)
        [challenge_ release];

    WebView *webview = [webview_ webView];
    [webview setFrameLoadDelegate:nil];
    [webview setResourceLoadDelegate:nil];
    [webview setUIDelegate:nil];
    [webview setScriptDebugDelegate:nil];
    [webview setPolicyDelegate:nil];

    [webview setDownloadDelegate:nil];

    [webview _setFormDelegate:nil];
    [webview _setUIKitDelegate:nil];
    [webview setWebMailDelegate:nil];
    [webview setEditingDelegate:nil];

    [webview_ setDelegate:nil];
    [webview_ setGestureDelegate:nil];

    //NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    [webview close];

#if RecycleWebViews
    [webview_ removeFromSuperview];
    [Documents_ addObject:[webview_ autorelease]];
#else
    [webview_ release];
#endif

    [indirect_ setDelegate:nil];
    [indirect_ release];

    [cydia_ release];

    [scroller_ setDelegate:nil];

    if (button_ != nil)
        [button_ release];
    if (style_ != nil)
        [style_ release];
    if (function_ != nil)
        [function_ release];

    [scroller_ release];
    [indicator_ release];
    if (confirm_ != nil)
        [confirm_ release];
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

- (NSMutableURLRequest *) _addHeadersToRequest:(NSURLRequest *)request {
    NSMutableURLRequest *copy = [request mutableCopy];

    if (Machine_ != NULL)
        [copy setValue:[NSString stringWithUTF8String:Machine_] forHTTPHeaderField:@"X-Machine"];
    if (UniqueID_ != nil)
        [copy setValue:UniqueID_ forHTTPHeaderField:@"X-Unique-ID"];

    if (Role_ != nil)
        [copy setValue:Role_ forHTTPHeaderField:@"X-Role"];

    return copy;
}

- (void) loadRequest:(NSURLRequest *)request {
    pushed_ = true;
    error_ = false;
    [webview_ loadRequest:request];
}

- (void) reloadURL {
    if (request_ == nil)
        return;

    if ([request_ HTTPBody] == nil && [request_ HTTPBodyStream] == nil)
        [self loadRequest:request_];
    else {
        UIActionSheet *sheet = [[[UIActionSheet alloc]
            initWithTitle:@"Are you sure you want to submit this form again?"
            buttons:[NSArray arrayWithObjects:@"Cancel", @"Submit", nil]
            defaultButtonIndex:0
            delegate:self
            context:@"submit"
        ] autorelease];

        [sheet setNumberOfRows:1];
        [sheet popupAlertAnimated:YES];
    }
}

- (WebView *) webView {
    return [webview_ webView];
}

- (UIWebDocumentView *) documentView {
    return webview_;
}

- (void) view:(UIView *)sender didSetFrame:(CGRect)frame {
    [scroller_ setContentSize:frame.size];
}

- (void) view:(UIView *)sender didSetFrame:(CGRect)frame oldFrame:(CGRect)old {
    [self view:sender didSetFrame:frame];
}

- (void) pushPage:(RVPage *)page {
    [page setDelegate:delegate_];
    [self setBackButtonTitle:title_];
    [book_ pushPage:page];
}

- (BOOL) getSpecial:(NSURL *)url {
    NSString *href([url absoluteString]);
    NSString *scheme([[url scheme] lowercaseString]);

    RVPage *page = nil;

    if ([href hasPrefix:@"apptapp://package/"])
        page = [delegate_ pageForPackage:[href substringFromIndex:18]];
    else if ([scheme isEqualToString:@"cydia"]) {
        page = [delegate_ pageForURL:url hasTag:NULL];
        if (page == nil)
            return false;
    } else if (![scheme isEqualToString:@"apptapp"])
        return false;

    if (page != nil)
        [self pushPage:page];
    return true;
}

- (void) webViewShow:(WebView *)sender {
}

- (void) webView:(WebView *)sender runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame {
    UIActionSheet *sheet = [[[UIActionSheet alloc]
        initWithTitle:nil
        buttons:[NSArray arrayWithObjects:@"OK", nil]
        defaultButtonIndex:0
        delegate:self
        context:@"alert"
    ] autorelease];

    [sheet setBodyText:message];
    [sheet popupAlertAnimated:YES];
}

- (BOOL) webView:(WebView *)sender runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame {
    UIActionSheet *sheet = [[[UIActionSheet alloc]
        initWithTitle:nil
        buttons:[NSArray arrayWithObjects:@"OK", @"Cancel", nil]
        defaultButtonIndex:0
        delegate:self
        context:@"confirm"
    ] autorelease];

    [sheet setNumberOfRows:1];
    [sheet setBodyText:message];
    [sheet popupAlertAnimated:YES];

    NSRunLoop *loop([NSRunLoop currentRunLoop]);
    NSDate *future([NSDate distantFuture]);

    while (confirm_ == nil && [loop runMode:NSDefaultRunLoopMode beforeDate:future]);

    NSNumber *confirm([confirm_ autorelease]);
    confirm_ = nil;
    return [confirm boolValue];
}

- (void) setButtonImage:(NSString *)button withStyle:(NSString *)style toFunction:(id)function {
    if (button_ != nil)
        [button_ autorelease];
    button_ = button == nil ? nil : [[UIImage imageWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:button]]] retain];

    if (style_ != nil)
        [style_ autorelease];
    style_ = style == nil ? nil : [style retain];

    if (function_ != nil)
        [function_ autorelease];
    function_ = function == nil ? nil : [function retain];
}

- (void) setButtonTitle:(NSString *)button withStyle:(NSString *)style toFunction:(id)function {
    if (button_ != nil)
        [button_ autorelease];
    button_ = button == nil ? nil : [button retain];

    if (style_ != nil)
        [style_ autorelease];
    style_ = style == nil ? nil : [style retain];

    if (function_ != nil)
        [function_ autorelease];
    function_ = function == nil ? nil : [function retain];
}

- (void) webViewClose:(WebView *)sender {
    [book_ close];
}

- (void) webView:(WebView *)sender didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame {
    [window setValue:cydia_ forKey:@"cydia"];
}

- (void) webView:(WebView *)sender unableToImplementPolicyWithError:(NSError *)error frame:(WebFrame *)frame {
    NSLog(@"err:%@", error);
}

- (void) webView:(WebView *)sender decidePolicyForNewWindowAction:(NSDictionary *)action request:(NSURLRequest *)request newFrameName:(NSString *)name decisionListener:(id<WebPolicyDecisionListener>)listener {
    NSLog(@"nwa:%@", name);

    if (NSURL *url = [request URL]) {
        if (name == nil) unknown: {
            if (![self getSpecial:url]) {
                NSString *scheme([[url scheme] lowercaseString]);
                if ([scheme isEqualToString:@"mailto"])
                    [delegate_ openMailToURL:url];
                else goto use;
            }
        } else if ([name isEqualToString:@"_open"])
            [delegate_ openURL:url];
        else if ([name isEqualToString:@"_popup"]) {
            RVBook *book([[[RVPopUpBook alloc] initWithFrame:[delegate_ popUpBounds]] autorelease]);

            RVPage *page([delegate_ pageForURL:url hasTag:NULL]);
            if (page == nil) {
                /* XXX: call createWebViewWithRequest instead */

                [self setBackButtonTitle:title_];

                BrowserView *browser([[[BrowserView alloc] initWithBook:book] autorelease]);
                [browser loadURL:url];
                page = browser;
            }

            [book setDelegate:delegate_];
            [page setDelegate:delegate_];

            [book setPage:page];
            [book_ pushBook:book];
        } else goto unknown;

        [listener ignore];
    } else use:
        [listener use];
}

- (void) webView:(WebView *)webView decidePolicyForMIMEType:(NSString *)type request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener {
    if ([WebView canShowMIMEType:type])
        [listener use];
    else {
        // XXX: handle more mime types!
        [listener ignore];
        if (frame == [webView mainFrame])
            [UIApp openURL:[request URL]];
    }
}

- (void) webView:(WebView *)sender decidePolicyForNavigationAction:(NSDictionary *)action request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener {
    if (request == nil) ignore: {
        [listener ignore];
        return;
    }

    NSURL *url([request URL]);

    if (url == nil) use: {
        if (!error_ && [frame parentFrame] == nil) {
            if (request_ != nil)
                [request_ autorelease];
            request_ = [request retain];
#if ForSaurik
            NSLog(@"dpn:%@", request_);
#endif
        }

        [listener use];
        return;
    }
#if ForSaurik
    else NSLog(@"nav:%@:%@", url, [action description]);
#endif

    const NSArray *capability(reinterpret_cast<const NSArray *>(GSSystemGetCapability(kGSDisplayIdentifiersCapability)));

    if (
        [capability containsObject:@"com.apple.Maps"] && [url mapsURL] ||
        [capability containsObject:@"com.apple.youtube"] && [url youTubeURL]
    ) {
      open:
        [UIApp openURL:url];
        goto ignore;
    }

    int store(_not(int));
    if (NSURL *itms = [url itmsURL:&store]) {
        NSLog(@"itms#%@#%u#%@", url, store, itms);
        if (
            store == 1 && [capability containsObject:@"com.apple.MobileStore"] ||
            store == 2 && [capability containsObject:@"com.apple.AppStore"]
        ) {
            url = itms;
            goto open;
        }
    }

    NSString *scheme([[url scheme] lowercaseString]);

    if ([scheme isEqualToString:@"tel"]) {
        // XXX: intelligence
        goto open;
    }

    if ([scheme isEqualToString:@"mailto"]) {
        [delegate_ openMailToURL:url];
        goto ignore;
    }

    if ([self getSpecial:url])
        goto ignore;
    else if ([WebView _canHandleRequest:request])
        goto use;
    else if ([url isSpringboardHandledURL])
        goto open;
    else
        goto use;
}

- (void) webView:(WebView *)sender setStatusText:(NSString *)text {
    //lprintf("Status:%s\n", [text UTF8String]);
}

- (void) _pushPage {
    if (pushed_)
        return;
    pushed_ = true;
    [book_ pushPage:self];
}

- (void) alertSheet:(UIActionSheet *)sheet buttonClicked:(int)button {
    NSString *context([sheet context]);

    if ([context isEqualToString:@"alert"])
        [sheet dismiss];
    else if ([context isEqualToString:@"confirm"]) {
        switch (button) {
            case 1:
                confirm_ = [NSNumber numberWithBool:YES];
            break;

            case 2:
                confirm_ = [NSNumber numberWithBool:NO];
            break;
        }

        [sheet dismiss];
    } else if ([context isEqualToString:@"challenge"]) {
        id<NSURLAuthenticationChallengeSender> sender([challenge_ sender]);

        switch (button) {
            case 1: {
                NSString *username([[sheet textFieldAtIndex:0] text]);
                NSString *password([[sheet textFieldAtIndex:1] text]);

                NSURLCredential *credential([NSURLCredential credentialWithUser:username password:password persistence:NSURLCredentialPersistenceForSession]);

                [sender useCredential:credential forAuthenticationChallenge:challenge_];
            } break;

            case 2:
                [sender cancelAuthenticationChallenge:challenge_];
            break;

            default:
                _assert(false);
        }

        [challenge_ release];
        challenge_ = nil;

        [sheet dismiss];
    } else if ([context isEqualToString:@"submit"]) {
        switch (button) {
            case 1:
            break;

            case 2:
                if (request_ != nil)
                    [webview_ loadRequest:request_];
            break;

            default:
                _assert(false);
        }

        [sheet dismiss];
    }
}

- (void) webView:(WebView *)sender resource:(id)identifier didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge fromDataSource:(WebDataSource *)source {
    challenge_ = [challenge retain];

    NSURLProtectionSpace *space([challenge protectionSpace]);
    NSString *realm([space realm]);
    if (realm == nil)
        realm = @"";

    UIActionSheet *sheet = [[[UIActionSheet alloc]
        initWithTitle:realm
        buttons:[NSArray arrayWithObjects:@"Login", @"Cancel", nil]
        defaultButtonIndex:0
        delegate:self
        context:@"challenge"
    ] autorelease];

    [sheet setNumberOfRows:1];

    [sheet addTextFieldWithValue:@"" label:@"username"];
    [sheet addTextFieldWithValue:@"" label:@"password"];

    UITextField *username([sheet textFieldAtIndex:0]); {
        UITextInputTraits *traits([username textInputTraits]);
        [traits setAutocapitalizationType:UITextAutocapitalizationTypeNone];
        [traits setAutocorrectionType:UITextAutocorrectionTypeNo];
        [traits setKeyboardType:UIKeyboardTypeASCIICapable];
        [traits setReturnKeyType:UIReturnKeyNext];
    }

    UITextField *password([sheet textFieldAtIndex:1]); {
        UITextInputTraits *traits([password textInputTraits]);
        [traits setAutocapitalizationType:UITextAutocapitalizationTypeNone];
        [traits setAutocorrectionType:UITextAutocorrectionTypeNo];
        [traits setKeyboardType:UIKeyboardTypeASCIICapable];
        // XXX: UIReturnKeyDone
        [traits setReturnKeyType:UIReturnKeyNext];
        [traits setSecureTextEntry:YES];
    }

    [sheet popupAlertAnimated:YES];
}

- (NSURLRequest *) webView:(WebView *)sender resource:(id)identifier willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse fromDataSource:(WebDataSource *)source {
    NSURL *url = [request URL];
    if ([self getSpecial:url])
        return nil;
    [self _pushPage];
    return [self _addHeadersToRequest:request];
}

- (WebView *) webView:(WebView *)sender createWebViewWithRequest:(NSURLRequest *)request windowFeatures:(NSDictionary *)features {
#if ForSaurik
    NSLog(@"cwv:%@ (%@)", request, title_);
#endif

    BrowserView *browser = [[[BrowserView alloc] initWithBook:book_] autorelease];
    [self pushPage:browser];
    [browser loadRequest:request];
    return [browser webView];
}

- (WebView *) webView:(WebView *)sender createWebViewWithRequest:(NSURLRequest *)request {
    return [self webView:sender createWebViewWithRequest:request windowFeatures:nil];
}

- (void) webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame {
    if ([frame parentFrame] != nil)
        return;

    title_ = [title retain];
    [book_ reloadTitleForPage:self];
}

- (void) webView:(WebView *)sender didStartProvisionalLoadForFrame:(WebFrame *)frame {
    if ([frame parentFrame] != nil)
        return;

    reloading_ = false;
    loading_ = true;
    [self reloadButtons];

    if (title_ != nil) {
        [title_ release];
        title_ = nil;
    }

    if (button_ != nil) {
        [button_ release];
        button_ = nil;
    }

    if (style_ != nil) {
        [style_ release];
        style_ = nil;
    }

    if (function_ != nil) {
        [function_ release];
        function_ = nil;
    }

    [book_ reloadTitleForPage:self];

    [scroller_ scrollPointVisibleAtTopLeft:CGPointZero];

    CGRect webrect = [scroller_ bounds];
    webrect.size.height = 0;
    [webview_ setFrame:webrect];
}

- (void) _finishLoading {
    if (!reloading_) {
        loading_ = false;
        [self reloadButtons];
    }
}

- (bool) _loading {
    return loading_;
}

- (void) reloadButtons {
    if ([self _loading])
        [indicator_ startAnimation];
    else
        [indicator_ stopAnimation];
    [super reloadButtons];
}

- (BOOL) webView:(WebView *)sender shouldScrollToPoint:(struct CGPoint)point forFrame:(WebFrame *)frame {
    return [webview_ webView:sender shouldScrollToPoint:point forFrame:frame];
}

- (void) webView:(WebView *)sender didReceiveViewportArguments:(id)arguments forFrame:(WebFrame *)frame {
    return [webview_ webView:sender didReceiveViewportArguments:arguments forFrame:frame];
}

- (void) webView:(WebView *)sender needsScrollNotifications:(id)notifications forFrame:(WebFrame *)frame {
    return [webview_ webView:sender needsScrollNotifications:notifications forFrame:frame];
}

- (void) webView:(WebView *)sender didCommitLoadForFrame:(WebFrame *)frame {
    return [webview_ webView:sender didCommitLoadForFrame:frame];
}

- (void) webView:(WebView *)sender didReceiveDocTypeForFrame:(WebFrame *)frame {
    return [webview_ webView:sender didReceiveDocTypeForFrame:frame];
}

- (void) webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame {
    if ([frame parentFrame] == nil) {
        [self _finishLoading];

        if (DOMDocument *document = [frame DOMDocument])
            if (DOMNodeList<NSFastEnumeration> *bodies = [document getElementsByTagName:@"body"])
                for (DOMHTMLBodyElement *body in bodies) {
                    DOMCSSStyleDeclaration *style([document getComputedStyle:body pseudoElement:nil]);

                    bool colored(false);

                    if (DOMCSSPrimitiveValue *color = static_cast<DOMCSSPrimitiveValue *>([style getPropertyCSSValue:@"background-color"])) {
                        if ([color primitiveType] == DOM_CSS_RGBCOLOR) {
                            DOMRGBColor *rgb([color getRGBColorValue]);

                            float red([[rgb red] getFloatValue:DOM_CSS_NUMBER]);
                            float green([[rgb green] getFloatValue:DOM_CSS_NUMBER]);
                            float blue([[rgb blue] getFloatValue:DOM_CSS_NUMBER]);
                            float alpha([[rgb alpha] getFloatValue:DOM_CSS_NUMBER]);

                            UIColor *uic(nil);

                            if (red == 0xc7 && green == 0xce && blue == 0xd5)
                                uic = [UIColor pinStripeColor];
                            else if (alpha != 0)
                                uic = [UIColor
                                    colorWithRed:(red / 255)
                                    green:(green / 255)
                                    blue:(blue / 255)
                                    alpha:alpha
                                ];

                            if (uic != nil) {
                                colored = true;
                                [scroller_ setBackgroundColor:uic];
                            }
                        }
                    }

                    if (!colored)
                        [scroller_ setBackgroundColor:[UIColor pinStripeColor]];
                    break;
                }
    }

    return [webview_ webView:sender didFinishLoadForFrame:frame];
}

- (void) webView:(WebView *)sender didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame {
    if ([frame parentFrame] != nil)
        return;
    if (reloading_)
        return;
    [self _finishLoading];

    [self loadURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@?%@",
        [[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"error" ofType:@"html"]] absoluteString],
        [[error localizedDescription] stringByAddingPercentEscapes]
    ]]];

    error_ = true;
}

- (void) webView:(WebView *)sender addMessageToConsole:(NSDictionary *)dictionary {
#if ForSaurik
    lprintf("Console:%s\n", [[dictionary description] UTF8String]);
#endif
}

- (id) initWithBook:(RVBook *)book {
    if ((self = [super initWithBook:book]) != nil) {
        loading_ = false;

        struct CGRect bounds = [self bounds];

        scroller_ = [[UIScroller alloc] initWithFrame:bounds];
        [self addSubview:scroller_];

        [scroller_ setShowBackgroundShadow:NO];
        [scroller_ setFixedBackgroundPattern:YES];
        [scroller_ setBackgroundColor:[UIColor pinStripeColor]];

        [scroller_ setScrollingEnabled:YES];
        [scroller_ setAdjustForContentSizeChange:YES];
        [scroller_ setClipsSubviews:YES];
        [scroller_ setAllowsRubberBanding:YES];
        [scroller_ setScrollDecelerationFactor:0.99];
        [scroller_ setDelegate:self];

        CGRect webrect = [scroller_ bounds];
        webrect.size.height = 0;

        WebView *webview;

#if RecycleWebViews
        webview_ = [Documents_ lastObject];
        if (webview_ != nil) {
            webview_ = [webview_ retain];
            webview = [webview_ webView];
            [Documents_ removeLastObject];
            [webview_ setFrame:webrect];
        } else {
#else
        if (true) {
#endif
            webview_ = [[UIWebDocumentView alloc] initWithFrame:webrect];
            webview = [webview_ webView];

            // XXX: this is terribly (too?) expensive
            //[webview_ setDrawsBackground:NO];
            [webview setPreferencesIdentifier:@"Cydia"];

            [webview_ setTileSize:CGSizeMake(webrect.size.width, 500)];

            [webview_ setAllowsMessaging:YES];

            [webview_ setTilingEnabled:YES];
            [webview_ setDrawsGrid:NO];
            [webview_ setLogsTilingChanges:NO];
            [webview_ setTileMinificationFilter:kCAFilterNearest];
            [webview_ setDetectsPhoneNumbers:NO];
            [webview_ setAutoresizes:YES];

            [webview_ setMinimumScale:0.25f forDocumentTypes:0x10];
            [webview_ setInitialScale:UIWebViewScalesToFitScale forDocumentTypes:0x10];
            [webview_ setViewportSize:CGSizeMake(980, UIWebViewGrowsAndShrinksToFitHeight) forDocumentTypes:0x10];

            [webview_ setViewportSize:CGSizeMake(320, UIWebViewGrowsAndShrinksToFitHeight) forDocumentTypes:0x2];

            [webview_ setMinimumScale:1.0f forDocumentTypes:0x8];
            [webview_ setInitialScale:UIWebViewScalesToFitScale forDocumentTypes:0x8];
            [webview_ setViewportSize:CGSizeMake(320, UIWebViewGrowsAndShrinksToFitHeight) forDocumentTypes:0x8];

            [webview_ _setDocumentType:0x4];

            [webview_ setZoomsFocusedFormControl:YES];
            [webview_ setContentsPosition:7];
            [webview_ setEnabledGestures:0xa];
            [webview_ setValue:[NSNumber numberWithBool:YES] forGestureAttribute:UIGestureAttributeIsZoomRubberBandEnabled];
            [webview_ setValue:[NSNumber numberWithBool:YES] forGestureAttribute:UIGestureAttributeUpdatesScroller];

            [webview_ setSmoothsFonts:YES];

            [webview _setUsesLoaderCache:YES];
            [webview setGroupName:@"Cydia"];
            [webview _setLayoutInterval:0];
        }

        [webview_ setDelegate:self];
        [webview_ setGestureDelegate:self];
        [scroller_ addSubview:webview_];

        //NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

        CGSize indsize = [UIProgressIndicator defaultSizeForStyle:UIProgressIndicatorStyleMediumWhite];
        indicator_ = [[UIProgressIndicator alloc] initWithFrame:CGRectMake(281, 12, indsize.width, indsize.height)];
        [indicator_ setStyle:UIProgressIndicatorStyleMediumWhite];

        Package *package([[Database sharedInstance] packageWithName:@"cydia"]);
        NSString *application = package == nil ? @"Cydia" : [NSString
            stringWithFormat:@"Cydia/%@",
            [package installed]
        ];

        if (Build_ != nil)
            application = [NSString stringWithFormat:@"Mobile/%@ %@", Build_, application];

        /* XXX: lookup application directory? */
        /*if (NSDictionary *safari = [NSDictionary dictionaryWithContentsOfFile:@"/Applications/MobileSafari.app/Info.plist"])
            if (NSString *version = [safari objectForKey:@"SafariProductVersion"])
                application = [NSString stringWithFormat:@"Version/%@ %@", version, application];*/

        [webview setApplicationNameForUserAgent:application];

        indirect_ = [[IndirectDelegate alloc] initWithDelegate:self];
        cydia_ = [[CydiaObject alloc] initWithDelegate:indirect_];

        [webview setFrameLoadDelegate:self];
        [webview setResourceLoadDelegate:indirect_];
        [webview setUIDelegate:self];
        [webview setScriptDebugDelegate:self];
        [webview setPolicyDelegate:self];

        [self setAutoresizingMask:UIViewAutoresizingFlexibleHeight];
        [scroller_ setAutoresizingMask:UIViewAutoresizingFlexibleHeight];
    } return self;
}

- (void) didFinishGesturesInView:(UIView *)view forEvent:(id)event {
    [webview_ redrawScaledDocument];
}

- (void) _rightButtonClicked {
    if (function_ == nil) {
        reloading_ = true;
        [self reloadURL];
    } else {
        WebView *webview([webview_ webView]);
        WebFrame *frame([webview mainFrame]);

        id _private(MSHookIvar<id>(webview, "_private"));
        WebCore::Page *page(_private == nil ? NULL : MSHookIvar<WebCore::Page *>(_private, "page"));
        WebCore::Settings *settings(page == NULL ? NULL : page->settings());

        bool no;
        if (settings == NULL)
            no = 0;
        else {
            no = settings->JavaScriptCanOpenWindowsAutomatically();
            settings->setJavaScriptCanOpenWindowsAutomatically(true);
        }

        [delegate_ clearFirstResponder];
        JSObjectRef function([function_ JSObject]);
        JSGlobalContextRef context([frame globalContext]);
        JSObjectCallAsFunction(context, function, NULL, 0, NULL, NULL);

        if (settings != NULL)
            settings->setJavaScriptCanOpenWindowsAutomatically(no);
    }
}

- (id) _rightButtonTitle {
    return button_ != nil ? button_ : @"Reload";
}

- (id) rightButtonTitle {
    return [self _loading] ? @"" : [self _rightButtonTitle];
}

- (UINavigationButtonStyle) rightButtonStyle {
    if (style_ == nil) normal:
        return UINavigationButtonStyleNormal;
    else if ([style_ isEqualToString:@"Normal"])
        return UINavigationButtonStyleNormal;
    else if ([style_ isEqualToString:@"Back"])
        return UINavigationButtonStyleBack;
    else if ([style_ isEqualToString:@"Highlighted"])
        return UINavigationButtonStyleHighlighted;
    else if ([style_ isEqualToString:@"Destructive"])
        return UINavigationButtonStyleDestructive;
    else goto normal;
}

- (NSString *) title {
    return title_ == nil ? @"Loading" : title_;
}

- (NSString *) backButtonTitle {
    return @"Browser";
}

- (void) setPageActive:(BOOL)active {
    if (!active)
        [indicator_ removeFromSuperview];
    else
        [[book_ navigationBar] addSubview:indicator_];
}

- (void) resetViewAnimated:(BOOL)animated {
}

- (void) setPushed:(bool)pushed {
    pushed_ = pushed;
}

@end
