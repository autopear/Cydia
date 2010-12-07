#include <UIKit/UIKit.h>
#include "iPhonePrivate.h"

#include "UCPlatform.h"

#include <UICaboodle/BrowserView.h>
#include <UICaboodle/UCLocalize.h>

//#include <QuartzCore/CALayer.h>
// XXX: fix the minimum requirement
extern NSString * const kCAFilterNearest;

#include <WebCore/WebCoreThread.h>

#include <WebKit/WebPolicyDelegate.h>
#include <WebKit/WebPreferences.h>

#include <WebKit/DOMCSSPrimitiveValue.h>
#include <WebKit/DOMCSSStyleDeclaration.h>
#include <WebKit/DOMDocument.h>
#include <WebKit/DOMHTMLBodyElement.h>
#include <WebKit/DOMRGBColor.h>

//#include <WebCore/Page.h>
//#include <WebCore/Settings.h>

#include "substrate.h"

#define ForSaurik 0

template <typename Type_>
static inline void CYRelease(Type_ &value) {
    if (value != nil) {
        [value release];
        value = nil;
    }
}

float CYScrollViewDecelerationRateNormal;

@interface WebView (Apple)
- (void) _setLayoutInterval:(float)interval;
@end

@interface WebPreferences (Apple)
+ (void) _setInitialDefaultTextEncodingToSystemEncoding;
- (void) _setLayoutInterval:(NSInteger)interval;
- (void) setOfflineWebApplicationCacheEnabled:(BOOL)enabled;
@end

/* Indirect Delegate {{{ */
@interface IndirectDelegate : NSObject <
    HookProtocol
> {
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

- (void) didDismissModalViewController {
    if (delegate_ != nil)
        return [delegate_ didDismissModalViewController];
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

@implementation WebScriptObject (UICaboodle)

- (NSUInteger) count {
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

// CYWebPolicyDecision* {{{
enum CYWebPolicyDecision {
    CYWebPolicyDecisionUnknown,
    CYWebPolicyDecisionDownload,
    CYWebPolicyDecisionIgnore,
    CYWebPolicyDecisionUse,
};

@interface CYWebPolicyDecisionMediator : NSObject <
    WebPolicyDecisionListener
> {
    id<WebPolicyDecisionListener> listener_;
    CYWebPolicyDecision decision_;
}

- (id) initWithListener:(id<WebPolicyDecisionListener>)listener;

- (CYWebPolicyDecision) decision;
- (bool) decided;
- (bool) decide;

@end

@implementation CYWebPolicyDecisionMediator

- (id) initWithListener:(id<WebPolicyDecisionListener>)listener {
    if ((self = [super init]) != nil) {
        listener_ = listener;
    } return self;
}

- (CYWebPolicyDecision) decision {
    return decision_;
}

- (bool) decided {
    return decision_ != CYWebPolicyDecisionUnknown;
}

- (bool) decide {
    switch (decision_) {
        case CYWebPolicyDecisionUnknown:
        default:
            NSLog(@"CYWebPolicyDecisionUnknown");
            return false;

        case CYWebPolicyDecisionDownload: [listener_ download]; break;
        case CYWebPolicyDecisionIgnore: [listener_ ignore]; break;
        case CYWebPolicyDecisionUse: [listener_ use]; break;
    }

    return true;
}

- (void) download {
    decision_ = CYWebPolicyDecisionDownload;
}

- (void) ignore {
    decision_ = CYWebPolicyDecisionIgnore;
}

- (void) use {
    decision_ = CYWebPolicyDecisionUse;
}

@end
// }}}

@implementation CYWebView : UIWebView

- (id) initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame]) != nil) {
    } return self;
}

- (void) dealloc {
    [super dealloc];
}

- (id<CYWebViewDelegate>) delegate {
    return (id<CYWebViewDelegate>) [super delegate];
}

/*- (WebView *) webView:(WebView *)view createWebViewWithRequest:(NSURLRequest *)request {
    id<CYWebViewDelegate> delegate([self delegate]);
    WebView *created(nil);
    if (created == nil && [delegate respondsToSelector:@selector(webView:createWebViewWithRequest:)])
        created = [delegate webView:view createWebViewWithRequest:request];
    if (created == nil && [UIWebView instancesRespondToSelector:@selector(webView:createWebViewWithRequest:)])
        created = [super webView:view createWebViewWithRequest:request];
    return created;
}*/

// webView:decidePolicyForNavigationAction:request:frame:decisionListener: (2.0+) {{{
- (void) webView:(WebView *)view decidePolicyForNavigationAction:(NSDictionary *)action request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener {
    id<CYWebViewDelegate> delegate([self delegate]);
    CYWebPolicyDecisionMediator *mediator([[[CYWebPolicyDecisionMediator alloc] initWithListener:listener] autorelease]);
    if (![mediator decided] && [delegate respondsToSelector:@selector(webView:decidePolicyForNavigationAction:request:frame:decisionListener:)])
        [delegate webView:view decidePolicyForNavigationAction:action request:request frame:frame decisionListener:mediator];
    if (![mediator decided] && [UIWebView instancesRespondToSelector:@selector(webView:decidePolicyForNavigationAction:request:frame:decisionListener:)])
        [super webView:view decidePolicyForNavigationAction:action request:request frame:frame decisionListener:mediator];
    [mediator decide];
}
// }}}
// webView:decidePolicyForNewWindowAction:request:newFrameName:decisionListener: (3.0+) {{{
static void $UIWebViewWebViewDelegate$webView$decidePolicyForNewWindowAction$request$newFrameName$decisionListener$(UIWebViewWebViewDelegate *self, SEL sel, WebView *view, NSDictionary *action, NSURLRequest *request, NSString *frame, id<WebPolicyDecisionListener> listener) {
    UIWebView *uiWebView(MSHookIvar<UIWebView *>(self, "uiWebView"));
    if ([uiWebView respondsToSelector:@selector(webView:decidePolicyForNewWindowAction:request:newFrameName:decisionListener:)])
        [uiWebView webView:view decidePolicyForNewWindowAction:action request:request newFrameName:frame decisionListener:listener];
}

- (void) webView:(WebView *)view decidePolicyForNewWindowAction:(NSDictionary *)action request:(NSURLRequest *)request newFrameName:(NSString *)frame decisionListener:(id<WebPolicyDecisionListener>)listener {
    id<CYWebViewDelegate> delegate([self delegate]);
    CYWebPolicyDecisionMediator *mediator([[[CYWebPolicyDecisionMediator alloc] initWithListener:listener] autorelease]);
    if (![mediator decided] && [delegate respondsToSelector:@selector(webView:decidePolicyForNewWindowAction:request:newFrameName:decisionListener:)])
        [delegate webView:view decidePolicyForNewWindowAction:action request:request newFrameName:frame decisionListener:mediator];
    if (![mediator decided] && [UIWebView instancesRespondToSelector:@selector(webView:decidePolicyForNewWindowAction:request:newFrameName:decisionListener:)])
        [super webView:view decidePolicyForNewWindowAction:action request:request newFrameName:frame decisionListener:mediator];
    [mediator decide];
}
// }}}
// webView:didClearWindowObject:forFrame: (3.2+) {{{
static void $UIWebViewWebViewDelegate$webView$didClearWindowObject$forFrame$(UIWebViewWebViewDelegate *self, SEL sel, WebView *view, WebScriptObject *window, WebFrame *frame) {
    UIWebView *uiWebView(MSHookIvar<UIWebView *>(self, "uiWebView"));
    if ([uiWebView respondsToSelector:@selector(webView:didClearWindowObject:forFrame:)])
        [uiWebView webView:view didClearWindowObject:window forFrame:frame];
}

- (void) webView:(WebView *)view didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame {
    id<CYWebViewDelegate> delegate([self delegate]);
    if ([delegate respondsToSelector:@selector(webView:didClearWindowObject:forFrame:)])
        [delegate webView:view didClearWindowObject:window forFrame:frame];
    if ([UIWebView instancesRespondToSelector:@selector(webView:didClearWindowObject:forFrame:)])
        [super webView:view didClearWindowObject:window forFrame:frame];
}
// }}}
// webView:didFailLoadWithError:forFrame: (2.0+) {{{
- (void) webView:(WebView *)view didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame {
    id<CYWebViewDelegate> delegate([self delegate]);
    if ([delegate respondsToSelector:@selector(webView:didFailLoadWithError:forFrame:)])
        [delegate webView:view didFailLoadWithError:error forFrame:frame];
    if ([UIWebView instancesRespondToSelector:@selector(webView:didFailLoadWithError:forFrame:)])
        [super webView:view didFailLoadWithError:error forFrame:frame];
}
// }}}
// webView:didFailProvisionalLoadWithError:forFrame: (2.0+) {{{
- (void) webView:(WebView *)view didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame {
    id<CYWebViewDelegate> delegate([self delegate]);
    if ([delegate respondsToSelector:@selector(webView:didFailProvisionalLoadWithError:forFrame:)])
        [delegate webView:view didFailProvisionalLoadWithError:error forFrame:frame];
    if ([UIWebView instancesRespondToSelector:@selector(webView:didFailProvisionalLoadWithError:forFrame:)])
        [super webView:view didFailProvisionalLoadWithError:error forFrame:frame];
}
// }}}
// webView:didFinishLoadForFrame: (2.0+) {{{
- (void) webView:(WebView *)view didFinishLoadForFrame:(WebFrame *)frame {
    id<CYWebViewDelegate> delegate([self delegate]);
    if ([delegate respondsToSelector:@selector(webView:didFinishLoadForFrame:)])
        [delegate webView:view didFinishLoadForFrame:frame];
    if ([UIWebView instancesRespondToSelector:@selector(webView:didFinishLoadForFrame:)])
        [super webView:view didFinishLoadForFrame:frame];
}
// }}}
// webView:didReceiveTitle:forFrame: (3.2+) {{{
static void $UIWebViewWebViewDelegate$webView$didReceiveTitle$forFrame$(UIWebViewWebViewDelegate *self, SEL sel, WebView *view, NSString *title, WebFrame *frame) {
    UIWebView *uiWebView(MSHookIvar<UIWebView *>(self, "uiWebView"));
    if ([uiWebView respondsToSelector:@selector(webView:didReceiveTitle:forFrame:)])
        [uiWebView webView:view didReceiveTitle:title forFrame:frame];
}

- (void) webView:(WebView *)view didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame {
    id<CYWebViewDelegate> delegate([self delegate]);
    if ([delegate respondsToSelector:@selector(webView:didReceiveTitle:forFrame:)])
        [delegate webView:view didReceiveTitle:title forFrame:frame];
    if ([UIWebView instancesRespondToSelector:@selector(webView:didReceiveTitle:forFrame:)])
        [super webView:view didReceiveTitle:title forFrame:frame];
}
// }}}
// webView:didStartProvisionalLoadForFrame: (2.0+) {{{
- (void) webView:(WebView *)view didStartProvisionalLoadForFrame:(WebFrame *)frame {
    id<CYWebViewDelegate> delegate([self delegate]);
    if ([delegate respondsToSelector:@selector(webView:didStartProvisionalLoadForFrame:)])
        [delegate webView:view didStartProvisionalLoadForFrame:frame];
    if ([UIWebView instancesRespondToSelector:@selector(webView:didStartProvisionalLoadForFrame:)])
        [super webView:view didStartProvisionalLoadForFrame:frame];
}
// }}}
// webView:resource:willSendRequest:redirectResponse:fromDataSource: (3.2+) {{{
static NSURLRequest *$UIWebViewWebViewDelegate$webView$resource$willSendRequest$redirectResponse$fromDataSource$(UIWebViewWebViewDelegate *self, SEL sel, WebView *view, id identifier, NSURLRequest *request, NSURLResponse *response, WebDataSource *source) {
    UIWebView *uiWebView(MSHookIvar<UIWebView *>(self, "uiWebView"));
    if ([uiWebView respondsToSelector:@selector(webView:resource:willSendRequest:redirectResponse:fromDataSource:)])
        request = [uiWebView webView:view resource:identifier willSendRequest:request redirectResponse:response fromDataSource:source];
    return request;
}

- (NSURLRequest *) webView:(WebView *)view resource:(id)identifier willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response fromDataSource:(WebDataSource *)source {
    id<CYWebViewDelegate> delegate([self delegate]);
    if ([UIWebView instancesRespondToSelector:@selector(webView:resource:willSendRequest:redirectResponse:fromDataSource:)])
        request = [super webView:view resource:identifier willSendRequest:request redirectResponse:response fromDataSource:source];
    if ([delegate respondsToSelector:@selector(webView:resource:willSendRequest:redirectResponse:fromDataSource:)])
        request = [delegate webView:view resource:identifier willSendRequest:request redirectResponse:response fromDataSource:source];
    return request;
}
// }}}
// webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame: (2.1+) {{{
- (void) webView:(WebView *)view runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame {
    id<CYWebViewDelegate> delegate([self delegate]);
    if ([UIWebView instancesRespondToSelector:@selector(webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:)])
        if (
            ![delegate respondsToSelector:@selector(webView:shouldRunJavaScriptAlertPanelWithMessage:initiatedByFrame:)] ||
            [delegate webView:view shouldRunJavaScriptAlertPanelWithMessage:message initiatedByFrame:frame]
        )
            [super webView:view runJavaScriptAlertPanelWithMessage:message initiatedByFrame:frame];
}
// }}}
// webView:runJavaScriptConfirmPanelWithMessage:initiatedByFrame: (2.1+) {{{
- (BOOL) webView:(WebView *)view runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame {
    id<CYWebViewDelegate> delegate([self delegate]);
    if ([UIWebView instancesRespondToSelector:@selector(webView:runJavaScriptConfirmPanelWithMessage:initiatedByFrame:)])
        if (
            ![delegate respondsToSelector:@selector(webView:shouldRunJavaScriptConfirmPanelWithMessage:initiatedByFrame:)] ||
            [delegate webView:view shouldRunJavaScriptConfirmPanelWithMessage:message initiatedByFrame:frame]
        )
            return [super webView:view runJavaScriptConfirmPanelWithMessage:message initiatedByFrame:frame];
    return NO;
}
// }}}
// webView:runJavaScriptTextInputPanelWithPrompt:defaultText:initiatedByFrame: (2.1+) {{{
- (NSString *) webView:(WebView *)view runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt defaultText:(NSString *)text initiatedByFrame:(WebFrame *)frame {
    id<CYWebViewDelegate> delegate([self delegate]);
    if ([UIWebView instancesRespondToSelector:@selector(webView:runJavaScriptTextInputPanelWithPrompt:defaultText:initiatedByFrame:)])
        if (
            ![delegate respondsToSelector:@selector(webView:shouldRunJavaScriptTextInputPanelWithPrompt:defaultText:initiatedByFrame:)] ||
            [delegate webView:view shouldRunJavaScriptTextInputPanelWithPrompt:prompt defaultText:text initiatedByFrame:frame]
        )
            return [super webView:view runJavaScriptTextInputPanelWithPrompt:prompt defaultText:text initiatedByFrame:frame];
    return nil;
}
// }}}
// webViewClose: (3.2+) {{{
static void $UIWebViewWebViewDelegate$webViewClose$(UIWebViewWebViewDelegate *self, SEL sel, WebView *view) {
    UIWebView *uiWebView(MSHookIvar<UIWebView *>(self, "uiWebView"));
    if ([uiWebView respondsToSelector:@selector(webViewClose:)])
        [uiWebView webViewClose:view];
}

- (void) webViewClose:(WebView *)view {
    id<CYWebViewDelegate> delegate([self delegate]);
    if ([delegate respondsToSelector:@selector(webViewClose:)])
        [delegate webViewClose:view];
    if ([UIWebView instancesRespondToSelector:@selector(webViewClose:)])
        [super webViewClose:view];
}
// }}}

- (void) _updateViewSettings {
    [super _updateViewSettings];

    id<CYWebViewDelegate> delegate([self delegate]);
    if ([delegate respondsToSelector:@selector(webViewUpdateViewSettings:)])
        [delegate webViewUpdateViewSettings:self];
}

+ (void) initialize {
    if (Class $UIWebViewWebViewDelegate = objc_getClass("UIWebViewWebViewDelegate")) {
        class_addMethod($UIWebViewWebViewDelegate, @selector(webView:decidePolicyForNewWindowAction:request:newFrameName:decisionListener:), (IMP) &$UIWebViewWebViewDelegate$webView$decidePolicyForNewWindowAction$request$newFrameName$decisionListener$, "v28@0:4@8@12@16@20@24");
        class_addMethod($UIWebViewWebViewDelegate, @selector(webView:didClearWindowObject:forFrame:), (IMP) &$UIWebViewWebViewDelegate$webView$didClearWindowObject$forFrame$, "v20@0:4@8@12@16");
        class_addMethod($UIWebViewWebViewDelegate, @selector(webView:didReceiveTitle:forFrame:), (IMP) &$UIWebViewWebViewDelegate$webView$didReceiveTitle$forFrame$, "v20@0:4@8@12@16");
        class_addMethod($UIWebViewWebViewDelegate, @selector(webView:resource:willSendRequest:redirectResponse:fromDataSource:), (IMP) &$UIWebViewWebViewDelegate$webView$resource$willSendRequest$redirectResponse$fromDataSource$, "@28@0:4@8@12@16@20@24");
        class_addMethod($UIWebViewWebViewDelegate, @selector(webViewClose:), (IMP) &$UIWebViewWebViewDelegate$webViewClose$, "v12@0:4@8");
    }
}

@end

#define ShowInternals 0
#define LogBrowser 0

#define lprintf(args...) fprintf(stderr, args)

@implementation BrowserController

#if ShowInternals
#include "UICaboodle/UCInternal.h"
#endif

+ (void) _initialize {
    [WebPreferences _setInitialDefaultTextEncodingToSystemEncoding];

    if (float *_UIScrollViewDecelerationRateNormal = reinterpret_cast<float *>(dlsym(RTLD_DEFAULT, "UIScrollViewDecelerationRateNormal")))
        CYScrollViewDecelerationRateNormal = *_UIScrollViewDecelerationRateNormal;
    else // XXX: this actually might be fast on some older systems: we should look into this
        CYScrollViewDecelerationRateNormal = 0.998;
}

- (void) dealloc {
#if LogBrowser
    NSLog(@"[BrowserController dealloc]");
#endif

    [webview_ setDelegate:nil];

    [indirect_ setDelegate:nil];
    [indirect_ release];

    if (challenge_ != nil)
        [challenge_ release];

    if (request_ != nil)
        [request_ release];

    if (custom_ != nil)
        [custom_ release];
    if (style_ != nil)
        [style_ release];

    if (function_ != nil)
        [function_ release];
    if (closer_ != nil)
        [closer_ release];

    if (title_ != nil)
        [title_ release];

    if ([loading_ count] != 0)
        [delegate_ releaseNetworkActivityIndicator];
    [loading_ release];

    [reloaditem_ release];
    [loadingitem_ release];

    [indicator_ release];

    [super dealloc];
}

- (void) loadURL:(NSURL *)url cachePolicy:(NSURLRequestCachePolicy)policy {
    [self loadRequest:[NSURLRequest
        requestWithURL:url
        cachePolicy:policy
        timeoutInterval:120.0
    ]];
}

- (void) loadURL:(NSURL *)url {
    [self loadURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy];
}

- (void) loadRequest:(NSURLRequest *)request {
#if LogBrowser
    NSLog(@"loadRequest:%@", request);
#endif

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
        UIAlertView *alert = [[[UIAlertView alloc]
            initWithTitle:UCLocalize("RESUBMIT_FORM")
            message:nil
            delegate:self
            cancelButtonTitle:UCLocalize("CANCEL")
            otherButtonTitles:UCLocalize("SUBMIT"), nil
        ] autorelease];

        [alert setContext:@"submit"];
        [alert show];
    }
}

- (void) setButtonImage:(NSString *)button withStyle:(NSString *)style toFunction:(id)function {
    if (custom_ != nil)
        [custom_ autorelease];
    if (button == nil)
        custom_ = nil;
    else
        custom_ = [[UIImage imageWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:button]]] retain];

    if (style_ != nil)
        [style_ autorelease];
    if (style == nil)
        style_ = nil;
    else
        style_ = [style retain];

    if (function_ != nil)
        [function_ autorelease];
    if (function == nil)
        function_ = nil;
    else
        function_ = [function retain];

    [self applyRightButton];
}

- (void) setButtonTitle:(NSString *)button withStyle:(NSString *)style toFunction:(id)function {
    if (custom_ != nil)
        [custom_ autorelease];
    if (button == nil)
        custom_ = nil;
    else
        custom_ = [button retain];

    if (style_ != nil)
        [style_ autorelease];
    if (style == nil)
        style_ = nil;
    else
        style_ = [style retain];

    if (function_ != nil)
        [function_ autorelease];
    if (function == nil)
        function_ = nil;
    else
        function_ = [function retain];

    [self applyRightButton];
}

- (void) setPopupHook:(id)function {
    if (closer_ != nil)
        [closer_ autorelease];
    if (function == nil)
        closer_ = nil;
    else
        closer_ = [function retain];
}

- (void) _setViewportWidth {
    [[webview_ _documentView] setViewportSize:CGSizeMake(width_, UIWebViewGrowsAndShrinksToFitHeight) forDocumentTypes:0x10];
}

- (void) setViewportWidth:(float)width {
    width_ = width != 0 ? width : [[self class] defaultWidth];
    [self _setViewportWidth];
}

- (void) webViewUpdateViewSettings:(UIWebView *)view {
    [self _setViewportWidth];
}

- (void) _openMailToURL:(NSURL *)url {
    [[UIApplication sharedApplication] openURL:url];// asPanel:YES];
}

- (bool) _allowJavaScriptPanel {
    return true;
}

- (void) _didFailWithError:(NSError *)error forFrame:(WebFrame *)frame {
    [loading_ removeObject:[NSValue valueWithNonretainedObject:frame]];
    [self _didFinishLoading];

    if ([error code] == NSURLErrorCancelled)
        return;

    if ([frame parentFrame] == nil) {
        [self loadURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@?%@",
            [[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"error" ofType:@"html"]] absoluteString],
            [[error localizedDescription] stringByAddingPercentEscapes]
        ]]];

        error_ = true;
    }
}

// CYWebViewDelegate {{{
- (void) webView:(WebView *)view decidePolicyForNavigationAction:(NSDictionary *)action request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener {
#if LogBrowser
    NSLog(@"decidePolicyForNavigationAction:%@ request:%@ frame:%@", action, request, frame);
#endif

    if ([frame parentFrame] == nil) {
        if (!error_) {
            if (request_ != nil)
                [request_ autorelease];
            if (request == nil)
                request_ = nil;
            else
                request_ = [request retain];
        }
    }
}

- (void) webView:(WebView *)view decidePolicyForNewWindowAction:(NSDictionary *)action request:(NSURLRequest *)request newFrameName:(NSString *)frame decisionListener:(id<WebPolicyDecisionListener>)listener {
#if LogBrowser
    NSLog(@"decidePolicyForNewWindowAction:%@ request:%@ newFrameName:%@", action, request, frame);
#endif

    NSURL *url([request URL]);
    if (url == nil)
        return;

    if ([frame isEqualToString:@"_open"])
        [delegate_ openURL:url];

    NSString *scheme([[url scheme] lowercaseString]);
    if ([scheme isEqualToString:@"mailto"])
        [self _openMailToURL:url];

    CYViewController *page([delegate_ pageForURL:url hasTag:NULL]);

    if (page == nil) {
        BrowserController *browser([[[class_ alloc] init] autorelease]);
        [browser loadRequest:request];
        page = browser;
    }

    [page setDelegate:delegate_];

    if (![frame isEqualToString:@"_popup"]) {
        [[self navigationItem] setTitle:title_];

        [[self navigationController] pushViewController:page animated:YES];
    } else {
        UCNavigationController *navigation([[[UCNavigationController alloc] init] autorelease]);

        [navigation setHook:indirect_];
        [navigation setDelegate:delegate_];

        [navigation setViewControllers:[NSArray arrayWithObject:page]];

        [[page navigationItem] setLeftBarButtonItem:[[[UIBarButtonItem alloc]
            initWithTitle:UCLocalize("CLOSE")
            style:UIBarButtonItemStylePlain
            target:page
            action:@selector(close)
        ] autorelease]];

        [[self navigationController] presentModalViewController:navigation animated:YES];
    }

    [listener ignore];
}

- (void) webView:(WebView *)view didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame {
}

- (void) webView:(WebView *)view didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame {
#if LogBrowser
    NSLog(@"didFailLoadWithError:%@ forFrame:%@", error, frame);
#endif

    [self _didFailWithError:error forFrame:frame];
}

- (void) webView:(WebView *)view didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame {
#if LogBrowser
    NSLog(@"didFailProvisionalLoadWithError:%@ forFrame:%@", error, frame);
#endif

    [self _didFailWithError:error forFrame:frame];
}

- (void) webView:(WebView *)view didFinishLoadForFrame:(WebFrame *)frame {
    [loading_ removeObject:[NSValue valueWithNonretainedObject:frame]];

    if ([frame parentFrame] == nil) {
        if (DOMDocument *document = [frame DOMDocument])
            if (DOMNodeList<NSFastEnumeration> *bodies = [document getElementsByTagName:@"body"])
                for (DOMHTMLBodyElement *body in (id) bodies) {
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
                                uic = [UIColor groupTableViewBackgroundColor];
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
                        [scroller_ setBackgroundColor:[UIColor groupTableViewBackgroundColor]];
                    break;
                }
    }

    [self _didFinishLoading];
}

- (void) webView:(WebView *)view didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame {
    if ([frame parentFrame] != nil)
        return;

    if (title_ != nil)
        [title_ autorelease];
    title_ = [title retain];

    [[self navigationItem] setTitle:title_];
}

- (void) webView:(WebView *)view didStartProvisionalLoadForFrame:(WebFrame *)frame {
    [loading_ addObject:[NSValue valueWithNonretainedObject:frame]];

    if ([frame parentFrame] == nil) {
        CYRelease(title_);
        CYRelease(custom_);
        CYRelease(style_);
        CYRelease(function_);
        CYRelease(closer_);

        // XXX: do we still need to do this?
        [[self navigationItem] setTitle:nil];
    }

    [self _didStartLoading];
}

- (NSURLRequest *) webView:(WebView *)view resource:(id)identifier willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response fromDataSource:(WebDataSource *)source {
#if LogBrowser
    NSLog(@"resource:%@ willSendRequest:%@ redirectResponse:%@ fromDataSource:%@", identifier, request, response, source);
#endif

    return request;
}

- (bool) webView:(WebView *)view shouldRunJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame {
    return [self _allowJavaScriptPanel];
}

- (bool) webView:(WebView *)view shouldRunJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame {
    return [self _allowJavaScriptPanel];
}

- (bool) webView:(WebView *)view shouldRunJavaScriptTextInputPanelWithPrompt:(NSString *)prompt defaultText:(NSString *)text initiatedByFrame:(WebFrame *)frame {
    return [self _allowJavaScriptPanel];
}

- (void) webViewClose:(WebView *)view {
    [self close];
}
// }}}

- (void) close {
    [[self navigationController] dismissModalViewControllerAnimated:YES];
}

- (void) alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)button {
    NSString *context([alert context]);

    if ([context isEqualToString:@"sensitive"]) {
        switch (button) {
            case 1:
                sensitive_ = [NSNumber numberWithBool:YES];
            break;

            case 2:
                sensitive_ = [NSNumber numberWithBool:NO];
            break;
        }

        [alert dismissWithClickedButtonIndex:-1 animated:YES];
    } else if ([context isEqualToString:@"challenge"]) {
        id<NSURLAuthenticationChallengeSender> sender([challenge_ sender]);

        switch (button) {
            case 1: {
                NSString *username([[alert textFieldAtIndex:0] text]);
                NSString *password([[alert textFieldAtIndex:1] text]);

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

        [alert dismissWithClickedButtonIndex:-1 animated:YES];
    } else if ([context isEqualToString:@"submit"]) {
        if (button == [alert cancelButtonIndex]) {
        } else if (button == [alert firstOtherButtonIndex]) {
            if (request_ != nil) {
                WebThreadLock();
                [webview_ loadRequest:request_];
                WebThreadUnlock();
            }
        }

        [alert dismissWithClickedButtonIndex:-1 animated:YES];
    }
}

- (UIBarButtonItemStyle) rightButtonStyle {
    if (style_ == nil) normal:
        return UIBarButtonItemStylePlain;
    else if ([style_ isEqualToString:@"Normal"])
        return UIBarButtonItemStylePlain;
    else if ([style_ isEqualToString:@"Highlighted"])
        return UIBarButtonItemStyleDone;
    else goto normal;
}

- (UIBarButtonItem *) customButton {
    return [[[UIBarButtonItem alloc]
        initWithTitle:custom_
        style:[self rightButtonStyle]
        target:self
        action:@selector(customButtonClicked)
    ] autorelease];
}

- (UIBarButtonItem *) rightButton {
    return reloaditem_;
}

- (void) applyLoadingTitle {
    [[self navigationItem] setTitle:UCLocalize("LOADING")];
}

- (void) layoutRightButton {
    [[loadingitem_ view] addSubview:indicator_];
    [[loadingitem_ view] bringSubviewToFront:indicator_];
}

- (void) applyRightButton {
    if ([self isLoading]) {
        [[self navigationItem] setRightBarButtonItem:loadingitem_ animated:YES];
        [self performSelector:@selector(layoutRightButton) withObject:nil afterDelay:0];

        [indicator_ startAnimating];
        [self applyLoadingTitle];
    } else {
        [indicator_ stopAnimating];

        [[self navigationItem] setRightBarButtonItem:(
            custom_ != nil ? [self customButton] : [self rightButton]
        ) animated:YES];
    }
}

- (void) didStartLoading {
    // Overridden in subclasses.
}

- (void) _didStartLoading {
    [self applyRightButton];

    if ([loading_ count] != 1)
        return;

    [delegate_ retainNetworkActivityIndicator];
    [self didStartLoading];
}

- (void) didFinishLoading {
    // Overridden in subclasses.
}

- (void) _didFinishLoading {
    if ([loading_ count] != 0)
        return;

    [self applyRightButton];
    [[self navigationItem] setTitle:title_];

    [delegate_ releaseNetworkActivityIndicator];
    [self didFinishLoading];
}

- (bool) isLoading {
    return [loading_ count] != 0;
}

- (id) initWithWidth:(float)width ofClass:(Class)_class {
    if ((self = [super init]) != nil) {
        class_ = _class;
        loading_ = [[NSMutableSet alloc] initWithCapacity:5];

        indirect_ = [[IndirectDelegate alloc] initWithDelegate:self];

        webview_ = [[[CYWebView alloc] initWithFrame:[[self view] bounds]] autorelease];
        [webview_ setDelegate:self];
        [self setView:webview_];

        if ([webview_ respondsToSelector:@selector(setDataDetectorTypes:)])
            [webview_ setDataDetectorTypes:UIDataDetectorTypeAutomatic];
        else
            [webview_ setDetectsPhoneNumbers:NO];

        [webview_ setScalesPageToFit:YES];

        UIWebDocumentView *document([webview_ _documentView]);

        // XXX: I think this improves scrolling; the hardcoded-ness sucks
        [document setTileSize:CGSizeMake(320, 500)];

        [document setBackgroundColor:[UIColor clearColor]];

        // XXX: this is terribly (too?) expensive
        [document setDrawsBackground:NO];

        WebView *webview([document webView]);
        WebPreferences *preferences([webview preferences]);

        // XXX: I have no clue if I actually /want/ this modification
        if ([webview respondsToSelector:@selector(_setLayoutInterval:)])
            [webview _setLayoutInterval:0];
        else if ([preferences respondsToSelector:@selector(_setLayoutInterval:)])
            [preferences _setLayoutInterval:0];

        [preferences setCacheModel:WebCacheModelDocumentBrowser];
        [preferences setOfflineWebApplicationCacheEnabled:YES];

        if ([webview_ respondsToSelector:@selector(_scrollView)]) {
            scroller_ = [webview_ _scrollView];

            [scroller_ setDirectionalLockEnabled:YES];
            [scroller_ setDecelerationRate:CYScrollViewDecelerationRateNormal];
            [scroller_ setDelaysContentTouches:NO];

            [scroller_ setCanCancelContentTouches:YES];
        } else if ([webview_ respondsToSelector:@selector(_scroller)]) {
            UIScroller *scroller([webview_ _scroller]);
            scroller_ = (UIScrollView *) scroller;

            [scroller setDirectionalScrolling:YES];
            // XXX: we might be better off /not/ setting this on older systems
            [scroller setScrollDecelerationFactor:CYScrollViewDecelerationRateNormal]; /* 0.989324 */
            [scroller setScrollHysteresis:0]; /* 8 */

            [scroller setThumbDetectionEnabled:NO];

            // use NO with UIApplicationUseLegacyEvents(YES)
            [scroller setEventMode:YES];

            // XXX: this is handled by setBounces, right?
            //[scroller setAllowsRubberBanding:YES];
        }

        [scroller_ setFixedBackgroundPattern:YES];
        [scroller_ setBackgroundColor:[UIColor groupTableViewBackgroundColor]];
        [scroller_ setClipsSubviews:YES];

        [scroller_ setBounces:YES];
        [scroller_ setScrollingEnabled:YES];
        [scroller_ setShowBackgroundShadow:NO];

        [self setViewportWidth:width];

        reloaditem_ = [[UIBarButtonItem alloc]
            initWithTitle:UCLocalize("RELOAD")
            style:[self rightButtonStyle]
            target:self
            action:@selector(reloadButtonClicked)
        ];

        loadingitem_ = [[UIBarButtonItem alloc]
            initWithTitle:@" "
            style:UIBarButtonItemStylePlain
            target:self
            action:@selector(reloadButtonClicked)
        ];

        indicator_ = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite]; 
        [indicator_ setFrame:CGRectMake(15, 5, [indicator_ frame].size.width, [indicator_ frame].size.height)];

        [webview_ setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)];
        [indicator_ setAutoresizingMask:UIViewAutoresizingFlexibleLeftMargin];
    } return self;
}

- (id) initWithWidth:(float)width {
    return [self initWithWidth:width ofClass:[self class]];
}

- (id) init {
    return [self initWithWidth:0];
}

- (void) didDismissModalViewController {
    if (closer_ != nil)
        [self callFunction:closer_];
}

- (void) callFunction:(WebScriptObject *)function {
    WebThreadLock();

    WebView *webview([[webview_ _documentView] webView]);
    WebFrame *frame([webview mainFrame]);
    WebPreferences *preferences([webview preferences]);

    bool maybe([preferences javaScriptCanOpenWindowsAutomatically]);
    [preferences setJavaScriptCanOpenWindowsAutomatically:NO];

    /*id _private(MSHookIvar<id>(webview, "_private"));
    WebCore::Page *page(_private == nil ? NULL : MSHookIvar<WebCore::Page *>(_private, "page"));
    WebCore::Settings *settings(page == NULL ? NULL : page->settings());

    bool no;
    if (settings == NULL)
        no = 0;
    else {
        no = settings->JavaScriptCanOpenWindowsAutomatically();
        settings->setJavaScriptCanOpenWindowsAutomatically(true);
    }*/

    if (UIWindow *window = [[self view] window])
        if (UIResponder *responder = [window firstResponder])
            [responder resignFirstResponder];

    JSObjectRef object([function JSObject]);
    JSGlobalContextRef context([frame globalContext]);
    JSObjectCallAsFunction(context, object, NULL, 0, NULL, NULL);

    /*if (settings != NULL)
        settings->setJavaScriptCanOpenWindowsAutomatically(no);*/

    [preferences setJavaScriptCanOpenWindowsAutomatically:maybe];

    WebThreadUnlock();
}

- (void) reloadButtonClicked {
    [self reloadURL];
}

- (void) _customButtonClicked {
    [self reloadButtonClicked];
}

- (void) customButtonClicked {
#if !AlwaysReload
    if (function_ != nil)
        [self callFunction:function_];
    else
#endif
    [self _customButtonClicked];
}

+ (float) defaultWidth {
    return 980;
}

@end
