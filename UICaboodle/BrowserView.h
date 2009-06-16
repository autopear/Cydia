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

@interface WebScriptObject (UICaboodle)
- (unsigned) count;
- (id) objectAtIndex:(unsigned)index;
@end

@protocol BrowserViewDelegate
- (RVPage *) pageForURL:(NSURL *)url hasTag:(int *)tag;
@end

@interface BrowserView : RVPage <
    RVBookHook
> {
    UIScroller *scroller_;
    UIWebDocumentView *webview_;
    UIProgressIndicator *indicator_;
    IndirectDelegate *indirect_;
    NSURLAuthenticationChallenge *challenge_;

    bool error_;
    NSURLRequest *request_;

    NSNumber *confirm_;
    NSNumber *sensitive_;
    NSString *title_;
    NSMutableSet *loading_;
    bool reloading_;

    NSString *button_;
    NSString *style_;

    WebScriptObject *function_;
    WebScriptObject *closer_;
    WebScriptObject *special_;
    WebScriptObject *finish_;

    bool pushed_;

    float width_;
    bool popup_;

    CGSize size_;
    bool editing_;
}

- (void) alertSheet:(UIActionSheet *)sheet buttonClicked:(int)button;

- (void) loadURL:(NSURL *)url cachePolicy:(NSURLRequestCachePolicy)policy;
- (void) loadURL:(NSURL *)url;

- (void) loadRequest:(NSURLRequest *)request;
- (void) reloadURL;
- (bool) isLoading;

- (void) fixScroller;

- (WebView *) webView;
- (UIWebDocumentView *) documentView;

- (id) initWithBook:(RVBook *)book;
- (id) initWithBook:(RVBook *)book forWidth:(float)width;

- (NSString *) stringByEvaluatingJavaScriptFromString:(NSString *)script;
- (void) callFunction:(WebScriptObject *)function;

- (void) webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame;
- (void) webView:(WebView *)sender didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame;

- (NSURLRequest *) webView:(WebView *)sender resource:(id)identifier willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse fromDataSource:(WebDataSource *)source;

+ (float) defaultWidth;
- (void) setViewportWidth:(float)width;

- (void) setButtonImage:(NSString *)button withStyle:(NSString *)style toFunction:(id)function;
- (void) setButtonTitle:(NSString *)button withStyle:(NSString *)style toFunction:(id)function;
- (void) setFinishHook:(id)function;
- (void) setPopupHook:(id)function;

- (id) _rightButtonTitle;

- (bool) promptForSensitive:(NSString *)name;
- (bool) allowSensitiveRequests;

@end
