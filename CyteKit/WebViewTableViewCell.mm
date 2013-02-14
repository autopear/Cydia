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

#include "CyteKit/WebViewTableViewCell.h"
#include "iPhonePrivate.h"

@interface WebView (Apple)
- (void) _setLayoutInterval:(float)interval;
- (void) _setAllowsMessaging:(BOOL)allows;
@end

@implementation CyteWebViewTableViewCell

+ (CyteWebViewTableViewCell *) cellWithRequest:(NSURLRequest *)request {
    CyteWebViewTableViewCell *cell([[[self alloc] initWithRequest:request] autorelease]);
    return cell;
}

- (id) initWithRequest:request {
    if ((self = [super init]) != nil) {
        UIView *view(self);

        webview_ = [[[CyteWebView alloc] initWithFrame:[view bounds]] autorelease];
        [webview_ setDelegate:self];
        [view addSubview:webview_];

        [webview_ setScalesPageToFit:YES];

        UIWebDocumentView *document([webview_ _documentView]);
        WebView *webview([document webView]);
        [webview setShouldUpdateWhileOffscreen:NO];

        if ([document respondsToSelector:@selector(setAllowsMessaging:)])
            [document setAllowsMessaging:YES];
        if ([webview respondsToSelector:@selector(_setAllowsMessaging:)])
            [webview _setAllowsMessaging:YES];

        UIScrollView *scroller([webview_ scrollView]);
        [scroller setScrollingEnabled:NO];
        [scroller setFixedBackgroundPattern:YES];
        [scroller setBackgroundColor:[UIColor clearColor]];

        WebPreferences *preferences([webview preferences]);
        [preferences setCacheModel:WebCacheModelDocumentBrowser];
        [preferences setJavaScriptCanOpenWindowsAutomatically:YES];
        [preferences setOfflineWebApplicationCacheEnabled:YES];

        [webview_ loadRequest:request];

        [webview_ setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)];
    } return self;
}

- (id) delegate {
    return [webview_ delegate];
}

- (void) setDelegate:(id)delegate {
    [webview_ setDelegate:delegate];
}

@end
