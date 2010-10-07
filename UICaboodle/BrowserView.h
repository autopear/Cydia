#import "ResetView.h"

#include <WebKit/DOMNodeList.h>
#include <WebKit/WebFrame.h>
#include <WebKit/WebScriptObject.h>
#include <WebKit/WebView.h>

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

@protocol BrowserControllerDelegate
- (CYViewController *) pageForURL:(NSURL *)url hasTag:(int *)tag;
@end

@interface BrowserController : CYViewController <
    HookProtocol
> {
    UIScroller *scroller_;
    UIWebDocumentView *document_;
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

    Class class_;

    id reloaditem_;
    id loadingitem_;
}

+ (void) _initialize;

- (void) loadURL:(NSURL *)url cachePolicy:(NSURLRequestCachePolicy)policy;
- (void) loadURL:(NSURL *)url;

- (void) loadRequest:(NSURLRequest *)request;
- (void) reloadURL;
- (bool) isLoading;

- (void) fixScroller;

- (WebView *) webView;
- (UIWebDocumentView *) documentView;

- (id) init;
- (id) initWithWidth:(float)width;
- (id) initWithWidth:(float)width ofClass:(Class)_class;

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

- (bool) promptForSensitive:(NSString *)name;
- (bool) allowSensitiveRequests;

- (void) alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)button;
- (void) customButtonClicked;
- (void) applyRightButton;

- (void) _startLoading;
- (void) close;

@end
