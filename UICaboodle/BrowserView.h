#import "ResetView.h"

@class NSMutableArray;
@class NSString;
@class NSURL;
@class NSURLRequest;

@class UIProgressIndicator;
@class UIScroller;
@class UIWebView;

@class Database;

@interface BrowserView : RVPage {
    _transient Database *database_;
    UIScroller *scroller_;
    UIWebView *webview_;
    NSMutableArray *urls_;
    UIProgressIndicator *indicator_;

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

- (id) initWithBook:(RVBook *)book database:(Database *)database;

@end
