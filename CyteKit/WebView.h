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

#ifndef CyteKit_CydiaBrowser_H
#define CyteKit_CydiaBrowser_H

#include <UIKit/UIKit.h>

#include <WebKit/DOMNodeList.h>
#include <WebKit/WebFrame.h>
#include <WebKit/WebPolicyDelegate.h>
#include <WebKit/WebScriptObject.h>
#include <WebKit/WebView.h>

#include <JavaScriptCore/JavaScriptCore.h>

enum CYWebPolicyDecision {
    CYWebPolicyDecisionUnknown,
    CYWebPolicyDecisionDownload,
    CYWebPolicyDecisionIgnore,
    CYWebPolicyDecisionUse,
};

@protocol CyteWebViewDelegate <UIWebViewDelegate>
@optional
- (void) webView:(WebView *)view addMessageToConsole:(NSDictionary *)message;
- (void) webView:(WebView *)view decidePolicyForNavigationAction:(NSDictionary *)action request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener;
- (void) webView:(WebView *)view decidePolicyForNewWindowAction:(NSDictionary *)action request:(NSURLRequest *)request newFrameName:(NSString *)name decisionListener:(id<WebPolicyDecisionListener>)listener;
- (void) webView:(WebView *)view didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame;
- (void) webView:(WebView *)view didCommitLoadForFrame:(WebFrame *)frame;
- (void) webView:(WebView *)view didDecidePolicy:(CYWebPolicyDecision)decision forNavigationAction:(NSDictionary *)action request:(NSURLRequest *)request frame:(WebFrame *)frame;
- (void) webView:(WebView *)view didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame;
- (void) webView:(WebView *)view didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame;
- (void) webView:(WebView *)view didFinishLoadForFrame:(WebFrame *)frame;
- (void) webView:(WebView *)view didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame;
- (void) webView:(WebView *)view didStartProvisionalLoadForFrame:(WebFrame *)frame;
- (NSURLRequest *) webView:(WebView *)view resource:(id)resource willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response fromDataSource:(WebDataSource *)source;
- (void) webViewClose:(WebView *)view;
- (bool) webView:(WebView *)view shouldRunJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame;
- (bool) webView:(WebView *)view shouldRunJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame;
- (bool) webView:(WebView *)view shouldRunJavaScriptTextInputPanelWithPrompt:(NSString *)prompt defaultText:(NSString *)text initiatedByFrame:(WebFrame *)frame;
- (void) webViewUpdateViewSettings:(UIWebView *)view;
@end

@interface CyteWebView : UIWebView {
}

- (id<CyteWebViewDelegate>) delegate;
- (void) setDelegate:(id<CyteWebViewDelegate>)delegate;

- (void) dispatchEvent:(NSString *)event;
- (void) reloadFromOrigin;
- (UIScrollView *) scrollView;
- (NSURLRequest *) request;

@end

#endif//CyteKit_CydiaBrowser_H
