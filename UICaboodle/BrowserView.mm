#include <UICaboodle/BrowserView.h>
#include <UICaboodle/UCLocalize.h>

#import <QuartzCore/CALayer.h>
// XXX: fix the minimum requirement
extern NSString * const kCAFilterNearest;

#include <WebCore/WebCoreThread.h>
#include <WebKit/WebPreferences-WebPrivate.h>

#include "substrate.h"

#define ForSaurik 1

static bool Wildcat_;

static CFArrayRef (*$GSSystemCopyCapability)(CFStringRef);
static CFArrayRef (*$GSSystemGetCapability)(CFStringRef);
static Class $UIFormAssistant;
static Class $UIWebBrowserView;

@interface NSString (UIKit)
- (NSString *) stringByAddingPercentEscapes;
@end

/* Indirect Delegate {{{ */
@interface IndirectDelegate : NSObject {
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

- (void) webView:(WebView *)sender didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame {
    if (delegate_ != nil)
        return [delegate_ webView:sender didClearWindowObject:window forFrame:frame];
}

- (void) webView:(WebView *)sender didCommitLoadForFrame:(WebFrame *)frame {
    if (delegate_ != nil)
        return [delegate_ webView:sender didCommitLoadForFrame:frame];
}

- (void) webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame {
    if (delegate_ != nil)
        return [delegate_ webView:sender didFailLoadWithError:error forFrame:frame];
}

- (void) webView:(WebView *)sender didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame {
    if (delegate_ != nil)
        return [delegate_ webView:sender didFailProvisionalLoadWithError:error forFrame:frame];
}

- (void) webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame {
    if (delegate_ != nil)
        return [delegate_ webView:sender didFinishLoadForFrame:frame];
}

- (void) webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame {
    if (delegate_ != nil)
        return [delegate_ webView:sender didReceiveTitle:title forFrame:frame];
}

- (void) webView:(WebView *)sender didStartProvisionalLoadForFrame:(WebFrame *)frame {
    if (delegate_ != nil)
        return [delegate_ webView:sender didStartProvisionalLoadForFrame:frame];
}

- (void) webView:(WebView *)sender resource:(id)identifier didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge fromDataSource:(WebDataSource *)source {
    if (delegate_ != nil)
        return [delegate_ webView:sender resource:identifier didReceiveAuthenticationChallenge:challenge fromDataSource:source];
}

- (NSURLRequest *) webView:(WebView *)sender resource:(id)identifier willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse fromDataSource:(WebDataSource *)source {
    if (delegate_ != nil)
        return [delegate_ webView:sender resource:identifier willSendRequest:request redirectResponse:redirectResponse fromDataSource:source];
    return nil;
}

- (IMP) methodForSelector:(SEL)sel {
    if (IMP method = [super methodForSelector:sel])
        return method;
    fprintf(stderr, "methodForSelector:[%s] == NULL\n", sel_getName(sel));
    return NULL;
}

- (BOOL) respondsToSelector:(SEL)sel {
    if ([super respondsToSelector:sel])
        return YES;
    // XXX: WebThreadCreateNSInvocation returns nil
    //fprintf(stderr, "[%s]R?%s\n", class_getName(self->isa), sel_getName(sel));
    return delegate_ == nil ? NO : [delegate_ respondsToSelector:sel];
}

- (NSMethodSignature *) methodSignatureForSelector:(SEL)sel {
    if (NSMethodSignature *method = [super methodSignatureForSelector:sel])
        return method;
    //fprintf(stderr, "[%s]S?%s\n", class_getName(self->isa), sel_getName(sel));
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

@interface WebView (UICaboodle)
- (void) setScriptDebugDelegate:(id)delegate;
- (void) _setFormDelegate:(id)delegate;
- (void) _setUIKitDelegate:(id)delegate;
- (void) setWebMailDelegate:(id)delegate;
- (void) _setLayoutInterval:(float)interval;
@end

@implementation WebScriptObject (UICaboodle)

- (unsigned) count {
    id length([self valueForKey:@"length"]);
    if ([length respondsToSelector:@selector(intValue)])
        return [length intValue];
    else
        return 0;
}

- (id) objectAtIndex:(unsigned)index {
    return [self webScriptValueAtIndex:index];
}

@end

#define ShowInternals 1
#define LogBrowser 0

#define lprintf(args...) fprintf(stderr, args)

@implementation BrowserView

#if ShowInternals
#include "UICaboodle/UCInternal.h"
#endif

+ (void) _initialize {
    [WebView enableWebThread];

    WebPreferences *preferences([WebPreferences standardPreferences]);
    [preferences setCacheModel:WebCacheModelDocumentBrowser];
    [preferences setOfflineWebApplicationCacheEnabled:YES];

    [WebPreferences _setInitialDefaultTextEncodingToSystemEncoding];

    $GSSystemCopyCapability = reinterpret_cast<CFArrayRef (*)(CFStringRef)>(dlsym(RTLD_DEFAULT, "GSSystemCopyCapability"));
    $GSSystemGetCapability = reinterpret_cast<CFArrayRef (*)(CFStringRef)>(dlsym(RTLD_DEFAULT, "GSSystemGetCapability"));
    $UIFormAssistant = objc_getClass("UIFormAssistant");

    $UIWebBrowserView = objc_getClass("UIWebBrowserView");
    if ($UIWebBrowserView == nil) {
        Wildcat_ = false;
        $UIWebBrowserView = objc_getClass("UIWebDocumentView");
    } else {
        Wildcat_ = true;
    }
}

- (void) dealloc {
#if LogBrowser
    NSLog(@"[BrowserView dealloc]");
#endif

    if (challenge_ != nil)
        [challenge_ release];

    WebThreadLock();

    WebView *webview = [webview_ webView];
    [webview setFrameLoadDelegate:nil];
    [webview setResourceLoadDelegate:nil];
    [webview setUIDelegate:nil];
    [webview setScriptDebugDelegate:nil];
    [webview setPolicyDelegate:nil];

    /* XXX: these are set by UIWebDocumentView
    [webview setDownloadDelegate:nil];
    [webview _setFormDelegate:nil];
    [webview _setUIKitDelegate:nil];
    [webview setEditingDelegate:nil];*/

    /* XXX: no one sets this, ever
    [webview setWebMailDelegate:nil];*/

    [webview_ setDelegate:nil];
    [webview_ setGestureDelegate:nil];

    if ([webview_ respondsToSelector:@selector(setFormEditingDelegate:)])
        [webview_ setFormEditingDelegate:nil];

    [webview_ setInteractionDelegate:nil];

    [indirect_ setDelegate:nil];

    //NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    [webview close];

#if RecycleWebViews
    [webview_ removeFromSuperview];
    [Documents_ addObject:[webview_ autorelease]];
#else
    [webview_ release];
#endif

    [indirect_ release];

    WebThreadUnlock();

    [scroller_ setDelegate:nil];

    if (button_ != nil)
        [button_ release];
    if (style_ != nil)
        [style_ release];
    if (function_ != nil)
        [function_ release];
    if (finish_ != nil)
        [finish_ release];
    if (closer_ != nil)
        [closer_ release];
    if (special_ != nil)
        [special_ release];

    [scroller_ release];
    [indicator_ release];
    if (confirm_ != nil)
        [confirm_ release];
    if (sensitive_ != nil)
        [sensitive_ release];
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

- (void) loadRequest:(NSURLRequest *)request {
    pushed_ = true;
    error_ = false;

    WebThreadLock();
    [webview_ loadRequest:request];
    WebThreadUnlock();
}

- (void) reloadURL {
    if (request_ == nil)
        return;

    if ([request_ HTTPBody] == nil && [request_ HTTPBodyStream] == nil)
        [self loadRequest:request_];
    else {
        UIActionSheet *sheet = [[[UIActionSheet alloc]
            initWithTitle:UCLocalize("RESUBMIT_FORM")
            buttons:[NSArray arrayWithObjects:UCLocalize("CANCEL"), UCLocalize("SUBMIT"), nil]
            defaultButtonIndex:0
            delegate:self
            context:@"submit"
        ] autorelease];

        [sheet setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)];

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

/* XXX: WebThreadLock? */
- (void) _fixScroller:(CGRect)bounds {
    float extra;

    if (!editing_ || $UIFormAssistant == nil)
        extra = 0;
    else {
        UIFormAssistant *assistant([$UIFormAssistant sharedFormAssistant]);
        CGRect peripheral([assistant peripheralFrame]);
#if LogBrowser
        NSLog(@"per:%f", peripheral.size.height);
#endif
        extra = peripheral.size.height;
    }

    CGRect subrect([scroller_ frame]);
    subrect.size.height -= extra;

    if ([scroller_ respondsToSelector:@selector(setScrollerIndicatorSubrect:)])
        [scroller_ setScrollerIndicatorSubrect:subrect];

    [webview_ setValue:[NSValue valueWithSize:NSMakeSize(subrect.size.width, subrect.size.height)] forGestureAttribute:UIGestureAttributeVisibleSize];

    CGSize size(size_);
    size.height += extra;
    [scroller_ setContentSize:size];

    if ([scroller_ respondsToSelector:@selector(releaseRubberBandIfNecessary)])
        [scroller_ releaseRubberBandIfNecessary];
}

- (void) fixScroller {
    CGRect bounds([webview_ documentBounds]);
#if TrackResize
    NSLog(@"_fs:(%f,%f+%f,%f)", bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height);
#endif
    [self _fixScroller:bounds];
}

- (void) view:(UIView *)sender didSetFrame:(CGRect)frame {
    size_ = frame.size;
#if TrackResize
    NSLog(@"dsf:(%f,%f+%f,%f)", frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
#endif
    [self _fixScroller:frame];
}

- (void) view:(UIView *)sender didSetFrame:(CGRect)frame oldFrame:(CGRect)old {
    [self view:sender didSetFrame:frame];
}

- (void) pushPage:(RVPage *)page {
    [page setDelegate:delegate_];
    [self setBackButtonTitle:title_];
    [book_ pushPage:page];
}

- (void) _pushPage {
    if (pushed_)
        return;
    // WTR: [self autorelease];
    pushed_ = true;
    [book_ pushPage:self];
}

- (void) swapPage:(RVPage *)page {
    [page setDelegate:delegate_];
    if (pushed_)
        [book_ swapPage:page];
    else
        [book_ pushPage:page];
}

- (BOOL) getSpecial:(NSURL *)url swap:(BOOL)swap {
#if LogBrowser
    NSLog(@"getSpecial:%@", url);
#endif

    if (RVPage *page = [delegate_ pageForURL:url hasTag:NULL]) {
        if (swap)
            [self swapPage:page];
        else
            [self pushPage:page];

        return true;
    } else
        return false;
}

- (void) formAssistant:(id)sender didBeginEditingFormNode:(id)node {
}

- (void) formAssistant:(id)sender didEndEditingFormNode:(id)node {
    [self fixScroller];
}

- (void) webViewShow:(WebView *)sender {
    /* XXX: this is where I cry myself to sleep */
}

- (bool) _allowJavaScriptPanel {
    return true;
}

- (bool) allowSensitiveRequests {
    return [self _allowJavaScriptPanel];
}

- (void) _promptForSensitive:(NSMutableArray *)array {
    NSString *name([array objectAtIndex:0]);

    UIActionSheet *sheet = [[[UIActionSheet alloc]
        initWithTitle:nil
        buttons:[NSArray arrayWithObjects:UCLocalize("YES"), UCLocalize("NO"), nil]
        defaultButtonIndex:0
        delegate:indirect_
        context:@"sensitive"
    ] autorelease];

    [sheet setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)];

    NSString *host(@"XXX");

    [sheet setNumberOfRows:1];
    [sheet setBodyText:[NSString stringWithFormat:@"The website at %@ is requesting your phone's %@. This is almost certainly for product licensing purposes. Will you allow this?", host, name]];
    [sheet popupAlertAnimated:YES];

    NSRunLoop *loop([NSRunLoop currentRunLoop]);
    NSDate *future([NSDate distantFuture]);

    while (sensitive_ == nil && [loop runMode:NSDefaultRunLoopMode beforeDate:future]);

    NSNumber *sensitive([sensitive_ autorelease]);
    sensitive_ = nil;

    [self autorelease];
    [array replaceObjectAtIndex:0 withObject:sensitive];
}

- (bool) promptForSensitive:(NSString *)name {
    if (![self allowSensitiveRequests])
        return false;

    NSMutableArray *array([NSMutableArray arrayWithCapacity:1]);
    [array addObject:name];

    [self performSelectorOnMainThread:@selector(_promptForSensitive:) withObject:array waitUntilDone:YES];
    return [[array lastObject] boolValue];
}

- (void) webView:(WebView *)sender runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame {
    if (![self _allowJavaScriptPanel])
        return;
    [self retain];

    UIActionSheet *sheet = [[[UIActionSheet alloc]
        initWithTitle:nil
        buttons:[NSArray arrayWithObjects:UCLocalize("OK"), nil]
        defaultButtonIndex:0
        delegate:self
        context:@"alert"
    ] autorelease];

    [sheet setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)];

    [sheet setBodyText:message];
    [sheet popupAlertAnimated:YES];
}

- (BOOL) webView:(WebView *)sender runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame {
    if (![self _allowJavaScriptPanel])
        return NO;
    [self retain];

    UIActionSheet *sheet = [[[UIActionSheet alloc]
        initWithTitle:nil
        buttons:[NSArray arrayWithObjects:UCLocalize("OK"), UCLocalize("CANCEL"), nil]
        defaultButtonIndex:0
        delegate:indirect_
        context:@"confirm"
    ] autorelease];

    [sheet setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)];

    [sheet setNumberOfRows:1];
    [sheet setBodyText:message];
    [sheet popupAlertAnimated:YES];

    NSRunLoop *loop([NSRunLoop currentRunLoop]);
    NSDate *future([NSDate distantFuture]);

    while (confirm_ == nil && [loop runMode:NSDefaultRunLoopMode beforeDate:future]);

    NSNumber *confirm([confirm_ autorelease]);
    confirm_ = nil;

    [self autorelease];
    return [confirm boolValue];
}

- (void) setAutoPopup:(BOOL)popup {
    popup_ = popup;
}

- (void) setSpecial:(id)function {
    if (special_ != nil)
        [special_ autorelease];
    special_ = function == nil ? nil : [function retain];
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

    [self reloadButtons];
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

    [self reloadButtons];
}

- (void) setFinishHook:(id)function {
    if (finish_ != nil)
        [finish_ autorelease];
    finish_ = function == nil ? nil : [function retain];
}

- (void) setPopupHook:(id)function {
    if (closer_ != nil)
        [closer_ autorelease];
    closer_ = function == nil ? nil : [function retain];
}

- (void) _openMailToURL:(NSURL *)url {
    [UIApp openURL:url];// asPanel:YES];
}

- (void) webView:(WebView *)sender willBeginEditingFormElement:(id)element {
    editing_ = true;
}

- (void) webView:(WebView *)sender didBeginEditingFormElement:(id)element {
    [self fixScroller];
}

- (void) webViewDidEndEditingFormElements:(WebView *)sender {
    editing_ = false;
    [self fixScroller];
}

- (void) webViewClose:(WebView *)sender {
    [book_ close];
}

- (void) close {
    [book_ close];
}

- (void) webView:(WebView *)sender didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame {
}

- (void) webView:(WebView *)sender unableToImplementPolicyWithError:(NSError *)error frame:(WebFrame *)frame {
    NSLog(@"err:%@", error);
}

- (void) webView:(WebView *)sender decidePolicyForNewWindowAction:(NSDictionary *)action request:(NSURLRequest *)request newFrameName:(NSString *)name decisionListener:(id<WebPolicyDecisionListener>)listener {
#if LogBrowser
    NSLog(@"nwa:%@", name);
#endif

    if (NSURL *url = [request URL]) {
        if (name == nil) unknown: {
            if (![self getSpecial:url swap:NO]) {
                NSString *scheme([[url scheme] lowercaseString]);
                if ([scheme isEqualToString:@"mailto"])
                    [self _openMailToURL:url];
                else goto use;
            }
        } else if ([name isEqualToString:@"_open"])
            [delegate_ openURL:url];
        else if ([name isEqualToString:@"_popup"]) {
            NSString *scheme([[url scheme] lowercaseString]);
            if ([scheme isEqualToString:@"mailto"])
                [self _openMailToURL:url];
            else {
                RVBook *book([[[RVPopUpBook alloc] initWithFrame:[delegate_ popUpBounds]] autorelease]);
                [book setHook:indirect_];

                RVPage *page([delegate_ pageForURL:url hasTag:NULL]);
                if (page == nil) {
                    /* XXX: call createWebViewWithRequest instead? */

                    [self setBackButtonTitle:title_];

                    BrowserView *browser([[[class_ alloc] initWithBook:book] autorelease]);
                    [browser loadURL:url];
                    page = browser;
                }

                [book setDelegate:delegate_];
                [page setDelegate:delegate_];

                [book setPage:page];
                [book_ pushBook:book];
            }
        } else goto unknown;

        [listener ignore];
    } else use:
        [listener use];
}

- (void) webView:(WebView *)sender decidePolicyForMIMEType:(NSString *)type request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener {
    if ([WebView canShowMIMEType:type])
        [listener use];
    else {
        // XXX: handle more mime types!
        [listener ignore];

        WebView *webview([webview_ webView]);
        if (frame == [webview mainFrame])
            [UIApp openURL:[request URL]];
    }
}

- (void) webView:(WebView *)sender decidePolicyForNavigationAction:(NSDictionary *)action request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener {
    if (request == nil) ignore: {
        [listener ignore];
        return;
    }

    NSURL *url([request URL]);
    NSString *host([url host]);

    if (url == nil) use: {
        if (!error_ && [frame parentFrame] == nil) {
            if (request_ != nil)
                [request_ autorelease];
            request_ = [request retain];
#if LogBrowser
            NSLog(@"dpn:%@", request_);
#endif
        }

        [listener use];

        WebView *webview([webview_ webView]);
        if (frame == [webview mainFrame])
            [self _pushPage];
        return;
    }
#if LogBrowser
    else NSLog(@"nav:%@:%@", url, [action description]);
#endif

    const NSArray *capability;

    if ($GSSystemCopyCapability != NULL) {
        capability = reinterpret_cast<const NSArray *>((*$GSSystemCopyCapability)(kGSDisplayIdentifiersCapability));
        capability = [capability autorelease];
    } else if ($GSSystemGetCapability != NULL) {
        capability = reinterpret_cast<const NSArray *>((*$GSSystemGetCapability)(kGSDisplayIdentifiersCapability));
    } else
        capability = nil;

    NSURL *open(nil);

    if (capability != nil && (
        [url isGoogleMapsURL] && [capability containsObject:@"com.apple.Maps"] && (open = [url mapsURL]) != nil||
        [host hasSuffix:@"youtube.com"] && [capability containsObject:@"com.apple.youtube"] && (open = [url youTubeURL]) != nil ||
        [url respondsToSelector:@selector(phobosURL)] && (open = [url phobosURL]) != nil
    )) {
        url = open;
      open:
        [UIApp openURL:url];
        goto ignore;
    }

    int store(_not(int));
    if (NSURL *itms = [url itmsURL:&store]) {
#if LogBrowser
        NSLog(@"itms#%@#%u#%@", url, store, itms);
#endif

        if (capability != nil && (
            store == 1 && [capability containsObject:@"com.apple.MobileStore"] ||
            store == 2 && [capability containsObject:@"com.apple.AppStore"]
        )) {
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
        [self _openMailToURL:url];
        goto ignore;
    }

    if ([self getSpecial:url swap:YES])
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

- (void) alertSheet:(UIActionSheet *)sheet buttonClicked:(int)button {
    NSString *context([sheet context]);

    if ([context isEqualToString:@"alert"]) {
        [self autorelease];
        [sheet dismiss];
    } else if ([context isEqualToString:@"confirm"]) {
        switch (button) {
            case 1:
                confirm_ = [NSNumber numberWithBool:YES];
            break;

            case 2:
                confirm_ = [NSNumber numberWithBool:NO];
            break;
        }

        [sheet dismiss];
    } else if ([context isEqualToString:@"sensitive"]) {
        switch (button) {
            case 1:
                sensitive_ = [NSNumber numberWithBool:YES];
            break;

            case 2:
                sensitive_ = [NSNumber numberWithBool:NO];
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

            _nodefault
        }

        [challenge_ release];
        challenge_ = nil;

        [sheet dismiss];
    } else if ([context isEqualToString:@"submit"]) {
        switch (button) {
            case 1:
            break;

            case 2:
                if (request_ != nil) {
                    WebThreadLock();
                    [webview_ loadRequest:request_];
                    WebThreadUnlock();
                }
            break;

            _nodefault
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
        buttons:[NSArray arrayWithObjects:UCLocalize("LOGIN"), UCLocalize("CANCEL"), nil]
        defaultButtonIndex:0
        delegate:self
        context:@"challenge"
    ] autorelease];

    [sheet setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)];

    [sheet setNumberOfRows:1];

    [sheet addTextFieldWithValue:@"" label:UCLocalize("USERNAME")];
    [sheet addTextFieldWithValue:@"" label:UCLocalize("PASSWORD")];

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
    return request;
}

- (WebView *) webView:(WebView *)sender createWebViewWithRequest:(NSURLRequest *)request windowFeatures:(NSDictionary *)features {
//- (WebView *) webView:(WebView *)sender createWebViewWithRequest:(NSURLRequest *)request userGesture:(BOOL)gesture {
#if LogBrowser
    NSLog(@"cwv:%@ (%@): %@", request, title_, features == nil ? @"{}" : [features description]);
    //NSLog(@"cwv:%@ (%@): %@", request, title_, gesture ? @"Yes" : @"No");
#endif

    NSNumber *value([features objectForKey:@"width"]);
    float width(value == nil ? 0 : [value floatValue]);

    RVBook *book(!popup_ ? book_ : [[[RVPopUpBook alloc] initWithFrame:[delegate_ popUpBounds]] autorelease]);

    /* XXX: deal with cydia:// pages */
    BrowserView *browser([[[class_ alloc] initWithBook:book forWidth:width] autorelease]);

    if (features != nil && popup_) {
        [book setDelegate:delegate_];
        [book setHook:indirect_];
        [browser setDelegate:delegate_];

        [browser loadRequest:request];

        [book setPage:browser];
        [book_ pushBook:book];
    } else if (request == nil) {
        [self setBackButtonTitle:title_];
        [browser setDelegate:delegate_];
        [browser retain];
    } else {
        [self pushPage:browser];
        [browser loadRequest:request];
    }

    return [browser webView];
}

- (WebView *) webView:(WebView *)sender createWebViewWithRequest:(NSURLRequest *)request {
    return [self webView:sender createWebViewWithRequest:request windowFeatures:nil];
    //return [self webView:sender createWebViewWithRequest:request userGesture:YES];
}

- (void) webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame {
    if ([frame parentFrame] != nil)
        return;

    title_ = [title retain];
    [book_ reloadTitleForPage:self];
}

- (void) webView:(WebView *)sender didStartProvisionalLoadForFrame:(WebFrame *)frame {
    /*if ([loading_ count] == 0)
        [self retain];*/
    [loading_ addObject:[NSValue valueWithNonretainedObject:frame]];

    if ([frame parentFrame] == nil) {
        [webview_ resignFirstResponder];

        reloading_ = false;

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

        if (finish_ != nil) {
            [finish_ release];
            finish_ = nil;
        }

        if (closer_ != nil) {
            [closer_ release];
            closer_ = nil;
        }

        if (special_ != nil) {
            [special_ release];
            special_ = nil;
        }

        [book_ reloadTitleForPage:self];

        CGRect webrect = [scroller_ bounds];
        webrect.size.height = 1;
        [webview_ setFrame:webrect];

        if ([scroller_ respondsToSelector:@selector(scrollPointVisibleAtTopLeft:)])
            [scroller_ scrollPointVisibleAtTopLeft:CGPointZero];
        else
            [scroller_ scrollRectToVisible:CGRectZero animated:NO];

        if ([scroller_ respondsToSelector:@selector(setZoomScale:duration:)])
            [scroller_ setZoomScale:1 duration:0];
        else if ([scroller_ respondsToSelector:@selector(_setZoomScale:duration:)])
            [scroller_ _setZoomScale:1 duration:0];
        /*else if ([scroller_ respondsToSelector:@selector(setZoomScale:animated:)])
            [scroller_ setZoomScale:1 animated:NO];*/
    }

    [self reloadButtons];
}

- (void) _finishLoading {
    size_t count([loading_ count]);
    /*if (count == 0)
        [self autorelease];*/
    if (reloading_ || count != 0)
        return;
    if (finish_ != nil)
        [self callFunction:finish_];
    [self reloadButtons];
}

- (bool) isLoading {
    return [loading_ count] != 0;
}

- (void) reloadButtons {
    if ([self isLoading])
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
    [self _pushPage];
    return [webview_ webView:sender didCommitLoadForFrame:frame];
}

- (void) webView:(WebView *)sender didReceiveDocTypeForFrame:(WebFrame *)frame {
    return [webview_ webView:sender didReceiveDocTypeForFrame:frame];
}

- (void) webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame {
    [loading_ removeObject:[NSValue valueWithNonretainedObject:frame]];
    [self _finishLoading];

    if ([frame parentFrame] == nil) {
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

- (void) _didFailWithError:(NSError *)error forFrame:(WebFrame *)frame {
    _trace();
    /*if ([frame parentFrame] == nil)
        [self autorelease];*/

    [loading_ removeObject:[NSValue valueWithNonretainedObject:frame]];
    [self _finishLoading];

    if (reloading_)
        return;

    if ([frame parentFrame] == nil) {
        [self loadURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@?%@",
            [[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"error" ofType:@"html"]] absoluteString],
            [[error localizedDescription] stringByAddingPercentEscapes]
        ]]];

        error_ = true;
    }
}

- (void) webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame {
    [self _didFailWithError:error forFrame:frame];
    if ([webview_ respondsToSelector:@selector(webView:didFailLoadWithError:forFrame:)])
        [webview_ webView:sender didFailLoadWithError:error forFrame:frame];
}

- (void) webView:(WebView *)sender didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame {
    [self _didFailWithError:error forFrame:frame];
}

- (void) webView:(WebView *)sender addMessageToConsole:(NSDictionary *)dictionary {
#if LogBrowser || ForSaurik
    lprintf("Console:%s\n", [[dictionary description] UTF8String]);
#endif
}

- (void) webView:(WebView *)sender didReceiveMessage:(NSDictionary *)dictionary {
#if LogBrowser || ForSaurik
    lprintf("Console:%s\n", [[dictionary description] UTF8String]);
#endif
    if ([webview_ respondsToSelector:@selector(webView:didReceiveMessage:)])
        [webview_ webView:sender didReceiveMessage:dictionary];
}

- (void) webView:(id)sender willCloseFrame:(id)frame {
    if ([webview_ respondsToSelector:@selector(webView:willCloseFrame:)])
        [webview_ webView:sender willCloseFrame:frame];
}

- (void) webView:(id)sender didFinishDocumentLoadForFrame:(id)frame {
    if ([webview_ respondsToSelector:@selector(webView:didFinishDocumentLoadForFrame:)])
        [webview_ webView:sender didFinishDocumentLoadForFrame:frame];
}

- (void) webView:(id)sender didFirstLayoutInFrame:(id)frame {
    if ([webview_ respondsToSelector:@selector(webView:didFirstLayoutInFrame:)])
        [webview_ webView:sender didFirstLayoutInFrame:frame];
}

- (void) webViewFormEditedStatusHasChanged:(id)changed {
    if ([webview_ respondsToSelector:@selector(webViewFormEditedStatusHasChanged:)])
        [webview_ webViewFormEditedStatusHasChanged:changed];
}

- (void) webView:(id)sender formStateDidFocusNode:(id)formState {
    if ([webview_ respondsToSelector:@selector(webView:formStateDidFocusNode:)])
        [webview_ webView:sender formStateDidFocusNode:formState];
}

- (void) webView:(id)sender formStateDidBlurNode:(id)formState {
    if ([webview_ respondsToSelector:@selector(webView:formStateDidBlurNode:)])
        [webview_ webView:sender formStateDidBlurNode:formState];
}

/* XXX: fix this stupid include file
- (void) webView:(WebView *)sender frame:(WebFrame *)frame exceededDatabaseQuotaForSecurityOrigin:(WebSecurityOrigin *)origin database:(NSString *)database {
    [origin setQuota:0x500000];
}*/

- (void) webViewDidLayout:(id)sender {
    [webview_ webViewDidLayout:sender];
}

- (void) webView:(id)sender didFirstVisuallyNonEmptyLayoutInFrame:(id)frame {
    [webview_ webView:sender didFirstVisuallyNonEmptyLayoutInFrame:frame];
}

- (void) webView:(id)sender saveStateToHistoryItem:(id)item forFrame:(id)frame {
    [webview_ webView:sender saveStateToHistoryItem:item forFrame:frame];
}

- (void) webView:(id)sender restoreStateFromHistoryItem:(id)item forFrame:(id)frame force:(BOOL)force {
    [webview_ webView:sender restoreStateFromHistoryItem:item forFrame:frame force:force];
}

- (void) webView:(id)sender attachRootLayer:(id)layer {
    [webview_ webView:sender attachRootLayer:layer];
}

- (id) webView:(id)sender plugInViewWithArguments:(id)arguments fromPlugInPackage:(id)package {
    return [webview_ webView:sender plugInViewWithArguments:arguments fromPlugInPackage:package];
}

- (void) webView:(id)sender willShowFullScreenForPlugInView:(id)view {
    [webview_ webView:sender willShowFullScreenForPlugInView:view];
}

- (void) webView:(id)sender didHideFullScreenForPlugInView:(id)view {
    [webview_ webView:sender didHideFullScreenForPlugInView:view];
}

- (void) webView:(id)sender willAddPlugInView:(id)view {
    [webview_ webView:sender willAddPlugInView:view];
}

- (void) webView:(id)sender didObserveDeferredContentChange:(int)change forFrame:(id)frame {
    [webview_ webView:sender didObserveDeferredContentChange:change forFrame:frame];
}

- (void) webViewDidPreventDefaultForEvent:(id)sender {
    [webview_ webViewDidPreventDefaultForEvent:sender];
}

- (void) _setTileDrawingEnabled:(BOOL)enabled {
    //[webview_ setTileDrawingEnabled:enabled];
}

- (void) setViewportWidth:(float)width {
    width_ = width != 0 ? width : [[self class] defaultWidth];
    [webview_ setViewportSize:CGSizeMake(width_, UIWebViewGrowsAndShrinksToFitHeight) forDocumentTypes:0x10];
}

- (void) willStartGesturesInView:(UIView *)view forEvent:(GSEventRef)event {
    [self _setTileDrawingEnabled:NO];
}

- (void) didFinishGesturesInView:(UIView *)view forEvent:(GSEventRef)event {
    [self _setTileDrawingEnabled:YES];
    [webview_ redrawScaledDocument];
}

- (void) scrollerWillStartDragging:(UIScroller *)scroller {
    [self _setTileDrawingEnabled:NO];
}

- (void) scrollerDidEndDragging:(UIScroller *)scroller willSmoothScroll:(BOOL)smooth {
    [self _setTileDrawingEnabled:YES];
}

- (void) scrollerDidEndDragging:(UIScroller *)scroller {
    [self _setTileDrawingEnabled:YES];
}

- (id) initWithBook:(RVBook *)book forWidth:(float)width ofClass:(Class)_class {
    if ((self = [super initWithBook:book]) != nil) {
        class_ = _class;
        loading_ = [[NSMutableSet alloc] initWithCapacity:3];
        popup_ = false;

        struct CGRect bounds = [self bounds];

        scroller_ = [[objc_getClass(Wildcat_ ? "UIScrollView" : "UIScroller") alloc] initWithFrame:bounds];
        [self addSubview:scroller_];

        [scroller_ setFixedBackgroundPattern:YES];
        [scroller_ setBackgroundColor:[UIColor pinStripeColor]];

        [scroller_ setScrollingEnabled:YES];
        [scroller_ setClipsSubviews:YES];

        if (!Wildcat_)
            [scroller_ setAllowsRubberBanding:YES];

        [scroller_ setDelegate:self];
        [scroller_ setBounces:YES];

        if (!Wildcat_) {
            [scroller_ setScrollHysteresis:8];
            [scroller_ setThumbDetectionEnabled:NO];
            [scroller_ setDirectionalScrolling:YES];
            //[scroller_ setScrollDecelerationFactor:0.99]; /* 0.989324 */
            [scroller_ setEventMode:YES];
        }

        if (Wildcat_) {
            UIScrollView *scroller((UIScrollView *)scroller_);
            //[scroller setDirectionalLockEnabled:NO];
            [scroller setDelaysContentTouches:NO];
            //[scroller setScrollsToTop:NO];
            //[scroller setCanCancelContentTouches:NO];
        }

        [scroller_ setShowBackgroundShadow:NO]; /* YES */
        //[scroller_ setAllowsRubberBanding:YES]; /* Vertical */

        if (!Wildcat_)
            [scroller_ setAdjustForContentSizeChange:YES]; /* NO */

        CGRect webrect = [scroller_ bounds];
        webrect.size.height = 0;

        WebView *webview;

        WebThreadLock();

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
            webview_ = [[$UIWebBrowserView alloc] initWithFrame:webrect];
            webview = [webview_ webView];

            // XXX: this is terribly (too?) expensive
            //[webview_ setDrawsBackground:NO];
            [webview setPreferencesIdentifier:@"Cydia"];

            [webview_ setTileSize:CGSizeMake(webrect.size.width, 500)];

            if ([webview_ respondsToSelector:@selector(enableReachability)])
                [webview_ enableReachability];
            if ([webview_ respondsToSelector:@selector(setAllowsMessaging:)])
                [webview_ setAllowsMessaging:YES];
            if ([webview_ respondsToSelector:@selector(useSelectionAssistantWithMode:)])
                [webview_ useSelectionAssistantWithMode:0];

            [webview_ setTilingEnabled:YES];
            [webview_ setDrawsGrid:NO];
            [webview_ setLogsTilingChanges:NO];
            [webview_ setTileMinificationFilter:kCAFilterNearest];

            if ([webview_ respondsToSelector:@selector(setDataDetectorTypes:)])
                /* XXX: abstractify */
                [webview_ setDataDetectorTypes:0x80000000];
            else
                [webview_ setDetectsPhoneNumbers:NO];

            [webview_ setAutoresizes:YES];

            [webview_ setMinimumScale:0.25f forDocumentTypes:0x10];
            [webview_ setMaximumScale:5.00f forDocumentTypes:0x10];
            [webview_ setInitialScale:UIWebViewScalesToFitScale forDocumentTypes:0x10];
            //[webview_ setViewportSize:CGSizeMake(980, UIWebViewGrowsAndShrinksToFitHeight) forDocumentTypes:0x10];

            [webview_ setViewportSize:CGSizeMake(320, UIWebViewGrowsAndShrinksToFitHeight) forDocumentTypes:0x2];

            [webview_ setMinimumScale:1.00f forDocumentTypes:0x8];
            [webview_ setInitialScale:UIWebViewScalesToFitScale forDocumentTypes:0x8];
            [webview_ setViewportSize:CGSizeMake(320, UIWebViewGrowsAndShrinksToFitHeight) forDocumentTypes:0x8];

            [webview_ _setDocumentType:0x4];

            if ([webview_ respondsToSelector:@selector(setZoomsFocusedFormControl:)])
                [webview_ setZoomsFocusedFormControl:YES];
            [webview_ setContentsPosition:7];
            [webview_ setEnabledGestures:0xa];
            [webview_ setValue:[NSNumber numberWithBool:YES] forGestureAttribute:UIGestureAttributeIsZoomRubberBandEnabled];
            [webview_ setValue:[NSNumber numberWithBool:YES] forGestureAttribute:UIGestureAttributeUpdatesScroller];

            [webview_ setSmoothsFonts:YES];
            [webview_ setAllowsImageSheet:YES];
            [webview _setUsesLoaderCache:YES];

            [webview setGroupName:@"CydiaGroup"];

            WebPreferences *preferences([webview preferences]);

            if ([webview respondsToSelector:@selector(_setLayoutInterval:)])
                [webview _setLayoutInterval:0];
            else
                [preferences _setLayoutInterval:0];
        }

        [self setViewportWidth:width];

        [webview_ setDelegate:self];
        [webview_ setGestureDelegate:self];

        if ([webview_ respondsToSelector:@selector(setFormEditingDelegate:)])
            [webview_ setFormEditingDelegate:self];

        [webview_ setInteractionDelegate:self];

        [scroller_ addSubview:webview_];

        //NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

        indirect_ = [[IndirectDelegate alloc] initWithDelegate:self];

        [webview setFrameLoadDelegate:indirect_];
        [webview setPolicyDelegate:indirect_];
        [webview setResourceLoadDelegate:indirect_];
        [webview setUIDelegate:indirect_];

        /* XXX: do not turn this on under penalty of extreme pain */
        [webview setScriptDebugDelegate:nil];

        WebThreadUnlock();

        CGSize indsize = [UIProgressIndicator defaultSizeForStyle:UIProgressIndicatorStyleMediumWhite];
        indicator_ = [[UIProgressIndicator alloc] initWithFrame:CGRectMake(bounds.size.width - 39, 12, indsize.width, indsize.height)];
        [indicator_ setStyle:UIProgressIndicatorStyleMediumWhite];

        [self setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)];
        [scroller_ setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)];
        [indicator_ setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin];
        [webview_ setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)];

        /*UIWebView *test([[[UIWebView alloc] initWithFrame:[self bounds]] autorelease]);
        [test loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"http://www.saurik.com/"]]];
        [self addSubview:test];*/
    } return self;
}

- (id) initWithBook:(RVBook *)book forWidth:(float)width {
    return [self initWithBook:book forWidth:width ofClass:[self class]];
}

- (id) initWithBook:(RVBook *)book {
    return [self initWithBook:book forWidth:0];
}

- (NSString *) stringByEvaluatingJavaScriptFromString:(NSString *)script {
    WebThreadLock();
    WebView *webview([webview_ webView]);
    NSString *string([webview stringByEvaluatingJavaScriptFromString:script]);
    WebThreadUnlock();
    return string;
}

- (void) callFunction:(WebScriptObject *)function {
    WebThreadLock();

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

    if (UIWindow *window = [self window])
        if (UIResponder *responder = [window firstResponder])
            [responder resignFirstResponder];

    JSObjectRef object([function JSObject]);
    JSGlobalContextRef context([frame globalContext]);
    JSObjectCallAsFunction(context, object, NULL, 0, NULL, NULL);

    if (settings != NULL)
        settings->setJavaScriptCanOpenWindowsAutomatically(no);

    WebThreadUnlock();
}

- (void) didCloseBook:(RVBook *)book {
    if (closer_ != nil)
        [self callFunction:closer_];
}

- (void) __rightButtonClicked {
    reloading_ = true;
    [self reloadURL];
}

- (void) _rightButtonClicked {
#if !AlwaysReload
    if (function_ != nil)
        [self callFunction:function_];
    else
#endif
        [self __rightButtonClicked];
}

- (id) _rightButtonTitle {
    return UCLocalize("RELOAD");
}

- (id) rightButtonTitle {
    return [self isLoading] ? @"" : button_ != nil ? button_ : [self _rightButtonTitle];
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
    return title_ == nil ? UCLocalize("LOADING") : title_;
}

- (NSString *) backButtonTitle {
    return UCLocalize("BROWSER");
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

+ (float) defaultWidth {
    return 980;
}

@end
