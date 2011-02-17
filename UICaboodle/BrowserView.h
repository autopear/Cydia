#import <UICaboodle/RVPage.h>
#import <UICaboodle/RVBook.h>

#import <UIKit/UIKit.h>

#include <WebKit/DOMNodeList.h>
#include <WebKit/WebFrame.h>
#include <WebKit/WebScriptObject.h>
#include <WebKit/WebView.h>

#import <JavaScriptCore/JavaScriptCore.h>

@class NSMutableArray;
@class NSString;
@class NSURL;
@class NSURLRequest;

@class UIScroller;
@class UIDocumentWebView;

@class WebView;

@class Database;
@class IndirectDelegate;

@protocol CYWebViewDelegate <UIWebViewDelegate>
- (void) webView:(WebView *)view addMessageToConsole:(NSDictionary *)message;
- (void) webView:(WebView *)view decidePolicyForNavigationAction:(NSDictionary *)action request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener;
- (void) webView:(WebView *)view decidePolicyForNewWindowAction:(NSDictionary *)action request:(NSURLRequest *)request newFrameName:(NSString *)name decisionListener:(id<WebPolicyDecisionListener>)listener;
- (void) webView:(WebView *)view didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame;
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

@interface CYWebView : UIWebView
- (id<CYWebViewDelegate>) delegate;
@end

@interface WebScriptObject (UICaboodle)
- (NSUInteger) count;
- (id) objectAtIndex:(unsigned)index;
@end

@protocol BrowserControllerDelegate
- (void) retainNetworkActivityIndicator;
- (void) releaseNetworkActivityIndicator;
- (CYViewController *) pageForURL:(NSURL *)url;
@end

@interface BrowserController : CYViewController <
    CYWebViewDelegate,
    HookProtocol,
    UIWebViewDelegate
> {
    _transient CYWebView *webview_;
    _transient UIScrollView *scroller_;

    UIActivityIndicatorView *indicator_;
    IndirectDelegate *indirect_;
    NSURLAuthenticationChallenge *challenge_;

    bool error_;
    NSURLRequest *request_;

    _transient NSNumber *sensitive_;

    NSString *title_;
    NSMutableSet *loading_;

    // XXX: NSString * or UIImage *
    id custom_;
    NSString *style_;

    WebScriptObject *function_;
    WebScriptObject *closer_;

    float width_;
    Class class_;

    UIBarButtonItem *reloaditem_;
    UIBarButtonItem *loadingitem_;
}

+ (void) _initialize;

- (void) setURL:(NSURL *)url;

- (void) loadURL:(NSURL *)url cachePolicy:(NSURLRequestCachePolicy)policy;
- (void) loadURL:(NSURL *)url;

- (void) loadRequest:(NSURLRequest *)request;
- (void) reloadURL;
- (bool) isLoading;

- (id) init;
- (id) initWithURL:(NSURL *)url;
- (id) initWithWidth:(float)width;
- (id) initWithWidth:(float)width ofClass:(Class)_class;

- (void) callFunction:(WebScriptObject *)function;

- (void) webView:(WebView *)view didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame;
- (NSURLRequest *) webView:(WebView *)view resource:(id)identifier willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response fromDataSource:(WebDataSource *)source;

+ (float) defaultWidth;

- (void) setButtonImage:(NSString *)button withStyle:(NSString *)style toFunction:(id)function;
- (void) setButtonTitle:(NSString *)button withStyle:(NSString *)style toFunction:(id)function;
- (void) setPopupHook:(id)function;

- (void) alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)button;
- (void) customButtonClicked;
- (void) applyRightButton;

- (void) _didStartLoading;
- (void) _didFinishLoading;

- (void) close;

@end
