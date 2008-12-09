#import "ResetView.h"


#include <WebKit/DOMCSSPrimitiveValue.h>
#include <WebKit/DOMCSSStyleDeclaration.h>
#include <WebKit/DOMDocument.h>
#include <WebKit/DOMHTMLBodyElement.h>
#include <WebKit/DOMNodeList.h>
#include <WebKit/DOMRGBColor.h>

#include <WebKit/WebFrame.h>
#include <WebKit/WebPolicyDelegate.h>
#include <WebKit/WebPreferences.h>
#include <WebKit/WebScriptObject.h>

#import <WebKit/WebView.h>
#import <WebKit/WebView-WebPrivate.h>

#include <WebCore/Page.h>
#include <WebCore/Settings.h>

#import <JavaScriptCore/JavaScriptCore.h>

@class NSMutableArray;
@class NSString;
@class NSURL;
@class NSURLRequest;

@class UIProgressIndicator;
@class UIScroller;
@class UIDocumentWebView;

@class WebView;

@class Database;
@class IndirectDelegate;

@interface BrowserView : RVPage {
    UIScroller *scroller_;
    UIWebDocumentView *webview_;
    UIProgressIndicator *indicator_;
    IndirectDelegate *indirect_;
    NSURLAuthenticationChallenge *challenge_;

    bool error_;
    NSURLRequest *request_;

    NSNumber *confirm_;
    NSString *title_;
    bool loading_;
    bool reloading_;

    NSString *button_;
    NSString *style_;
    WebScriptObject *function_;

    bool pushed_;
}

- (void) alertSheet:(UIActionSheet *)sheet buttonClicked:(int)button;

- (void) loadURL:(NSURL *)url cachePolicy:(NSURLRequestCachePolicy)policy;
- (void) loadURL:(NSURL *)url;

- (void) loadRequest:(NSURLRequest *)request;
- (void) reloadURL;

- (WebView *) webView;

- (id) initWithBook:(RVBook *)book;

- (void) webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame;
- (void) webView:(WebView *)sender didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame;

@end
