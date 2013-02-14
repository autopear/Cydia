/* Cydia - iPhone UIKit Front-End for Debian APT
 * Copyright (C) 2008-2012  Jay Freeman (saurik)
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

#include "CyteKit/dispatchEvent.h"
#include "CyteKit/WebView.h"

#include <CydiaSubstrate/CydiaSubstrate.h>

#include "iPhonePrivate.h"

// CYWebPolicyDecision* {{{
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

@implementation CyteWebView : UIWebView

#if ShowInternals
#include "CyteKit/UCInternal.h"
#endif

- (id) initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame]) != nil) {
    } return self;
}

- (void) dealloc {
    if (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iPhoneOS_3_0) {
        UIWebViewInternal *&_internal(MSHookIvar<UIWebViewInternal *>(self, "_internal"));
        if (&_internal != NULL) {
            UIWebViewWebViewDelegate *&webViewDelegate(MSHookIvar<UIWebViewWebViewDelegate *>(_internal, "webViewDelegate"));
            if (&webViewDelegate != NULL)
                [webViewDelegate _clearUIWebView];
        }
    }

    [super dealloc];
}

- (NSString *) description {
    return [NSString stringWithFormat:@"<%s: %p, %@>", class_getName([self class]), self, [[[self request] URL] absoluteString]];
}

- (id<CyteWebViewDelegate>) delegate {
    return (id<CyteWebViewDelegate>) [super delegate];
}

- (void) setDelegate:(id<CyteWebViewDelegate>)delegate {
    [super setDelegate:delegate];
}

/*- (WebView *) webView:(WebView *)view createWebViewWithRequest:(NSURLRequest *)request {
    id<CyteWebViewDelegate> delegate([self delegate]);
    WebView *created(nil);
    if (created == nil && [delegate respondsToSelector:@selector(webView:createWebViewWithRequest:)])
        created = [delegate webView:view createWebViewWithRequest:request];
    if (created == nil && [UIWebView instancesRespondToSelector:@selector(webView:createWebViewWithRequest:)])
        created = [super webView:view createWebViewWithRequest:request];
    return created;
}*/

// webView:addMessageToConsole: (X.Xx) {{{
static void $UIWebViewWebViewDelegate$webView$addMessageToConsole$(UIWebViewWebViewDelegate *self, SEL sel, WebView *view, NSDictionary *message) {
    UIWebView *uiWebView(MSHookIvar<UIWebView *>(self, "uiWebView"));
    if ([uiWebView respondsToSelector:@selector(webView:addMessageToConsole:)])
        [uiWebView webView:view addMessageToConsole:message];
}

- (void) webView:(WebView *)view addMessageToConsole:(NSDictionary *)message {
    id<CyteWebViewDelegate> delegate([self delegate]);
    if ([delegate respondsToSelector:@selector(webView:addMessageToConsole:)])
        [delegate webView:view addMessageToConsole:message];
    if ([UIWebView instancesRespondToSelector:@selector(webView:addMessageToConsole:)])
        [super webView:view addMessageToConsole:message];
}
// }}}
// webView:decidePolicyForNavigationAction:request:frame:decisionListener: (2.0+) {{{
- (void) webView:(WebView *)view decidePolicyForNavigationAction:(NSDictionary *)action request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener {
    id<CyteWebViewDelegate> delegate([self delegate]);
    CYWebPolicyDecisionMediator *mediator([[[CYWebPolicyDecisionMediator alloc] initWithListener:listener] autorelease]);
    if (![mediator decided] && [delegate respondsToSelector:@selector(webView:decidePolicyForNavigationAction:request:frame:decisionListener:)])
        [delegate webView:view decidePolicyForNavigationAction:action request:request frame:frame decisionListener:mediator];
    if (![mediator decided] && [UIWebView instancesRespondToSelector:@selector(webView:decidePolicyForNavigationAction:request:frame:decisionListener:)])
        [super webView:view decidePolicyForNavigationAction:action request:request frame:frame decisionListener:mediator];
    if ([delegate respondsToSelector:@selector(webView:didDecidePolicy:forNavigationAction:request:frame:)])
        [delegate webView:view didDecidePolicy:[mediator decision] forNavigationAction:action request:request frame:frame];
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
    id<CyteWebViewDelegate> delegate([self delegate]);
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
    id<CyteWebViewDelegate> delegate([self delegate]);
    if ([delegate respondsToSelector:@selector(webView:didClearWindowObject:forFrame:)])
        [delegate webView:view didClearWindowObject:window forFrame:frame];
    if ([UIWebView instancesRespondToSelector:@selector(webView:didClearWindowObject:forFrame:)])
        [super webView:view didClearWindowObject:window forFrame:frame];
}
// }}}
// webView:didCommitLoadForFrame: (3.0+) {{{
static void $UIWebViewWebViewDelegate$webView$didCommitLoadForFrame$(UIWebViewWebViewDelegate *self, SEL sel, WebView *view, WebFrame *frame) {
    UIWebView *uiWebView(MSHookIvar<UIWebView *>(self, "uiWebView"));
    if ([uiWebView respondsToSelector:@selector(webView:didCommitLoadForFrame:)])
        [uiWebView webView:view didCommitLoadForFrame:frame];
}

- (void) webView:(WebView *)view didCommitLoadForFrame:(WebFrame *)frame {
    id<CyteWebViewDelegate> delegate([self delegate]);
    if ([delegate respondsToSelector:@selector(webView:didCommitLoadForFrame:)])
        [delegate webView:view didCommitLoadForFrame:frame];
    if ([UIWebView instancesRespondToSelector:@selector(webView:didCommitLoadForFrame:)])
        [super webView:view didCommitLoadForFrame:frame];
}
// }}}
// webView:didFailLoadWithError:forFrame: (2.0+) {{{
- (void) webView:(WebView *)view didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame {
    id<CyteWebViewDelegate> delegate([self delegate]);
    if ([delegate respondsToSelector:@selector(webView:didFailLoadWithError:forFrame:)])
        [delegate webView:view didFailLoadWithError:error forFrame:frame];
    if ([UIWebView instancesRespondToSelector:@selector(webView:didFailLoadWithError:forFrame:)])
        [super webView:view didFailLoadWithError:error forFrame:frame];
}
// }}}
// webView:didFailProvisionalLoadWithError:forFrame: (2.0+) {{{
- (void) webView:(WebView *)view didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame {
    id<CyteWebViewDelegate> delegate([self delegate]);
    if ([delegate respondsToSelector:@selector(webView:didFailProvisionalLoadWithError:forFrame:)])
        [delegate webView:view didFailProvisionalLoadWithError:error forFrame:frame];
    if ([UIWebView instancesRespondToSelector:@selector(webView:didFailProvisionalLoadWithError:forFrame:)])
        [super webView:view didFailProvisionalLoadWithError:error forFrame:frame];
}
// }}}
// webView:didFinishLoadForFrame: (2.0+) {{{
- (void) webView:(WebView *)view didFinishLoadForFrame:(WebFrame *)frame {
    id<CyteWebViewDelegate> delegate([self delegate]);
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
    id<CyteWebViewDelegate> delegate([self delegate]);
    if ([delegate respondsToSelector:@selector(webView:didReceiveTitle:forFrame:)])
        [delegate webView:view didReceiveTitle:title forFrame:frame];
    if ([UIWebView instancesRespondToSelector:@selector(webView:didReceiveTitle:forFrame:)])
        [super webView:view didReceiveTitle:title forFrame:frame];
}
// }}}
// webView:didStartProvisionalLoadForFrame: (2.0+) {{{
- (void) webView:(WebView *)view didStartProvisionalLoadForFrame:(WebFrame *)frame {
    id<CyteWebViewDelegate> delegate([self delegate]);
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
    id<CyteWebViewDelegate> delegate([self delegate]);
    if ([UIWebView instancesRespondToSelector:@selector(webView:resource:willSendRequest:redirectResponse:fromDataSource:)])
        request = [super webView:view resource:identifier willSendRequest:request redirectResponse:response fromDataSource:source];
    if ([delegate respondsToSelector:@selector(webView:resource:willSendRequest:redirectResponse:fromDataSource:)])
        request = [delegate webView:view resource:identifier willSendRequest:request redirectResponse:response fromDataSource:source];
    return request;
}
// }}}
// webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame: (2.1+) {{{
- (void) webView:(WebView *)view runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame {
    [[self retain] autorelease];
    id<CyteWebViewDelegate> delegate([self delegate]);
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
    [[self retain] autorelease];
    id<CyteWebViewDelegate> delegate([self delegate]);
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
    [[self retain] autorelease];
    id<CyteWebViewDelegate> delegate([self delegate]);
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
    id<CyteWebViewDelegate> delegate([self delegate]);
    if ([delegate respondsToSelector:@selector(webViewClose:)])
        [delegate webViewClose:view];
    if ([UIWebView instancesRespondToSelector:@selector(webViewClose:)])
        [super webViewClose:view];
}
// }}}

- (void) _updateViewSettings {
    [super _updateViewSettings];

    id<CyteWebViewDelegate> delegate([self delegate]);
    if ([delegate respondsToSelector:@selector(webViewUpdateViewSettings:)])
        [delegate webViewUpdateViewSettings:self];
}

- (void) dispatchEvent:(NSString *)event {
    [[self _documentView] dispatchEvent:event];
}

- (void) reloadFromOrigin {
    [[[self _documentView] webView] reloadFromOrigin:nil];
}

- (UIScrollView *) scrollView {
    if ([self respondsToSelector:@selector(_scrollView)])
        return [self _scrollView];
    else if ([self respondsToSelector:@selector(_scroller)])
        return (UIScrollView *) [self _scroller];
    else return nil;
}

- (void) setNeedsLayout {
    [super setNeedsLayout];

    WebFrame *frame([[[self _documentView] webView] mainFrame]);
    if ([frame respondsToSelector:@selector(setNeedsLayout)])
        [frame setNeedsLayout];
}

- (NSURLRequest *) request {
    WebFrame *frame([[[self _documentView] webView] mainFrame]);
    return [([frame provisionalDataSource] ?: [frame dataSource]) request];
}

@end

static void $UIWebViewWebViewDelegate$_clearUIWebView(UIWebViewWebViewDelegate *self, SEL sel) {
    MSHookIvar<UIWebView *>(self, "uiWebView") = nil;
}

__attribute__((__constructor__)) static void $() {
    if (Class $UIWebViewWebViewDelegate = objc_getClass("UIWebViewWebViewDelegate")) {
        class_addMethod($UIWebViewWebViewDelegate, @selector(webView:addMessageToConsole:), (IMP) &$UIWebViewWebViewDelegate$webView$addMessageToConsole$, "v16@0:4@8@12");
        class_addMethod($UIWebViewWebViewDelegate, @selector(webView:decidePolicyForNewWindowAction:request:newFrameName:decisionListener:), (IMP) &$UIWebViewWebViewDelegate$webView$decidePolicyForNewWindowAction$request$newFrameName$decisionListener$, "v28@0:4@8@12@16@20@24");
        class_addMethod($UIWebViewWebViewDelegate, @selector(webView:didClearWindowObject:forFrame:), (IMP) &$UIWebViewWebViewDelegate$webView$didClearWindowObject$forFrame$, "v20@0:4@8@12@16");
        class_addMethod($UIWebViewWebViewDelegate, @selector(webView:didCommitLoadForFrame:), (IMP) &$UIWebViewWebViewDelegate$webView$didCommitLoadForFrame$, "v16@0:4@8@12");
        class_addMethod($UIWebViewWebViewDelegate, @selector(webView:didReceiveTitle:forFrame:), (IMP) &$UIWebViewWebViewDelegate$webView$didReceiveTitle$forFrame$, "v20@0:4@8@12@16");
        class_addMethod($UIWebViewWebViewDelegate, @selector(webView:resource:willSendRequest:redirectResponse:fromDataSource:), (IMP) &$UIWebViewWebViewDelegate$webView$resource$willSendRequest$redirectResponse$fromDataSource$, "@28@0:4@8@12@16@20@24");
        class_addMethod($UIWebViewWebViewDelegate, @selector(webViewClose:), (IMP) &$UIWebViewWebViewDelegate$webViewClose$, "v12@0:4@8");
        class_addMethod($UIWebViewWebViewDelegate, @selector(_clearUIWebView), (IMP) &$UIWebViewWebViewDelegate$_clearUIWebView, "v8@0:4");
    }
}
