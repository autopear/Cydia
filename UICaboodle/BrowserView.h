#import "ResetView.h"

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
    NSMutableArray *urls_;
    UIProgressIndicator *indicator_;
    IndirectDelegate *indirect_;

    NSString *title_;
    bool loading_;
    bool reloading_;

    bool pushed_;
}

- (void) loadURL:(NSURL *)url cachePolicy:(NSURLRequestCachePolicy)policy;
- (void) loadURL:(NSURL *)url;

- (void) loadRequest:(NSURLRequest *)request;
- (void) reloadURL;

- (WebView *) webView;

- (id) initWithBook:(RVBook *)book;

- (void) webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame;
- (void) webView:(WebView *)sender didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame;

@end
