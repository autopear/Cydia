#ifndef CYDIA_UIKITPRIVATE_H
#define CYDIA_UIKITPRIVATE_H

// #include <*> {{{
#include <GraphicsServices/GraphicsServices.h>
#include <UIKit/UIKit.h>
// }}}
// #import <*> {{{
#import <WebKit/DOMHTMLIFrameElement.h>
#import <WebKit/WebFrame.h>
#import <WebKit/WebPreferences.h>
// }}}
// typedef enum {*} *; {{{
typedef enum {
    UIGestureAttributeMinDegrees,                 /*float*/
    UIGestureAttributeMaxDegrees,                 /*float*/
    UIGestureAttributeMinScale,                   /*float*/
    UIGestureAttributeMaxScale,                   /*float*/
    UIGestureAttributeIsZoomRubberBandEnabled,    /*BOOL*/
    UIGestureAttributeZoomsFromCurrentToMinOrMax, /*BOOL*/
    UIGestureAttributeVisibleSize,                /*CGSize*/
    UIGestureAttributeUpdatesScroller,            /*BOOL*/
} UIGestureAttribute;

typedef enum {
    UINavigationButtonStyleNormal,
    UINavigationButtonStyleBack,
    UINavigationButtonStyleHighlighted,
    UINavigationButtonStyleDestructive
} UINavigationButtonStyle;

typedef enum {
    UIProgressIndicatorStyleLargeWhite,
    UIProgressIndicatorStyleMediumWhite,
    UIProgressIndicatorStyleMediumBrown,
    UIProgressIndicatorStyleSmallWhite,
    UIProgressIndicatorStyleSmallBlack,
    UIProgressIndicatorStyleTinyWhite,
} UIProgressIndicatorStyle;
// }}}
// #define * * {{{
#define UIDataDetectorTypeAutomatic 0x80000000
// }}}
// @class Web*; {{{
@class WebDataSource;
@class WebScriptObject;
@class WebView;
// }}}
// @protocol *; {{{
@protocol WebPolicyDecisionListener;
// }}}

// @interface * : UIView {{{
@interface UIFormAssistant : UIView
+ (UIFormAssistant *) sharedFormAssistant;
- (CGRect) peripheralFrame;
@end

@interface UIKeyboard : UIView
+ (void) initImplementationNow;
@end

@interface UIProgressBar : UIView
+ (CGSize) defaultSize;
- (void) setProgress:(float)progress;
- (void) setStyle:(NSInteger)style;
@end

@interface UIProgressHUD : UIView
- (void) hide;
- (void) setText:(NSString *)text;
- (void) showInView:(UIView *)view;
@end

@interface UIProgressIndicator : UIView
+ (CGSize) defaultSizeForStyle:(NSUInteger)style;
- (NSUInteger) activityIndicatorViewStyle;
- (void) setStyle:(UIProgressIndicatorStyle)style;
- (void) startAnimation;
@end

@interface UIScroller : UIView
- (CGSize) contentSize;
- (void) setDirectionalScrolling:(BOOL)directional;
- (void) setEventMode:(NSInteger)mode;
- (void) setOffset:(CGPoint)offset;
- (void) setScrollDecelerationFactor:(float)factor;
- (void) setScrollHysteresis:(float)hysteresis;
- (void) setScrollerIndicatorStyle:(UIScrollViewIndicatorStyle)style;
- (void) setThumbDetectionEnabled:(BOOL)enabled;
@end

@interface UITextLabel : UIView
- (void) setCentersHorizontally:(BOOL)centers;
- (void) setColor:(UIColor *)color;
- (void) setFont:(UIFont *)font;
- (void) setText:(NSString *)text;
@end

@interface UITransitionView : UIView
@end

@interface UIWebDocumentView : UIView
- (CGRect) documentBounds;
- (void) enableReachability;
- (void) loadRequest:(NSURLRequest *)request;
- (void) redrawScaledDocument;
- (void) setAllowsImageSheet:(BOOL)allows;
- (void) setAllowsMessaging:(BOOL)allows;
- (void) setAutoresizes:(BOOL)autoresizes;
- (void) setContentsPosition:(NSInteger)position;
- (void) setDrawsBackground:(BOOL)draws;
- (void) _setDocumentType:(NSInteger)type;
- (void) setDrawsGrid:(BOOL)draws;
- (void) setInitialScale:(float)scale forDocumentTypes:(NSInteger)types;
- (void) setLogsTilingChanges:(BOOL)logs;
- (void) setMinimumScale:(float)scale forDocumentTypes:(NSInteger)types;
- (void) setMinimumSize:(CGSize)size;
- (void) setMaximumScale:(float)scale forDocumentTypes:(NSInteger)tpyes;
- (void) setSmoothsFonts:(BOOL)smooths;
- (void) setTileMinificationFilter:(NSString *)filter;
- (void) setTileSize:(CGSize)size;
- (void) setTilingEnabled:(BOOL)enabled;
- (void) setViewportSize:(CGSize)size forDocumentTypes:(NSInteger)types;
- (void) setZoomsFocusedFormControl:(BOOL)zooms;
- (void) useSelectionAssistantWithMode:(NSInteger)mode;
- (WebView *) webView;
@end

@interface UIWebViewWebViewDelegate : NSObject {
    @public UIWebView *uiWebView;
}

- (void) _clearUIWebView;

@end
// }}}
// @interface *Button : * {{{
@interface UINavigationButton : UIButton
- (id) initWithTitle:(NSString *)title style:(UINavigationButtonStyle)style;
- (void) setBarStyle:(UIBarStyle)style;
@end

@interface UIPushButton : UIControl
- (id) backgroundForState:(NSUInteger)state;
- (void) setAutosizesToFit:(BOOL)autosizes;
- (void) setBackground:(id)background forState:(NSUInteger)state;
- (void) setDrawsShadow:(BOOL)draws;
- (void) setStretchBackground:(BOOL)stretch;
- (void) setTitle:(NSString *)title;
- (void) setTitleFont:(UIFont *)font;
@end

@interface UIThreePartButton : UIPushButton
@end
// }}}
// @interface * : NS* {{{
@interface WebDefaultUIKitDelegate : NSObject
+ (WebDefaultUIKitDelegate *) sharedUIKitDelegate;
@end
// }}}
// @interface UIWeb* : * {{{
@interface UIWebBrowserView : UIWebDocumentView
@end

@interface UIWebTouchEventsGestureRecognizer : UIGestureRecognizer
- (int) type;
- (NSString *) _typeDescription;
@end
// }}}
// @interface WAK* : * {{{
@interface WAKWindow : NSObject
+ (BOOL) hasLandscapeOrientation;
@end
// }}}

// @interface NS* (*) {{{
@interface NSMutableURLRequest (Apple)
- (void) setHTTPShouldUsePipelining:(BOOL)pipelining;
@end

@interface NSString (Apple)
- (NSString *) stringByAddingPercentEscapes;
- (NSString *) stringByReplacingCharacter:(UniChar)from withCharacter:(UniChar)to;
@end

@interface NSURL (Apple)
- (BOOL) isGoogleMapsURL;
- (BOOL) isSpringboardHandledURL;
// XXX: make this an enum
- (NSURL *) itmsURL:(NSInteger *)store;
- (NSURL *) mapsURL;
- (NSURL *) phobosURL;
- (NSURL *) youTubeURL;
@end

@interface NSURLRequest (Apple)
+ (BOOL) allowsAnyHTTPSCertificateForHost:(NSString *)host;
+ (void) setAllowsAnyHTTPSCertificate:(BOOL)allow forHost:(NSString *)host;
@end

@interface NSValue (Apple)
+ (NSValue *) valueWithSize:(CGSize)size;
@end
// }}}
// @interface UI* (*) {{{
@interface UIActionSheet (Apple)
- (void) setContext:(NSString *)context;
- (NSString *) context;
@end

@interface UIAlertView (Apple)
- (void) addTextFieldWithValue:(NSString *)value label:(NSString *)label;
- (id) buttons;
- (NSString *) context;
- (void) setContext:(NSString *)context;
- (void) setNumberOfRows:(int)rows;
- (void) setRunsModal:(BOOL)modal;
- (UITextField *) textField;
- (UITextField *) textFieldAtIndex:(NSUInteger)index;
- (void) _updateFrameForDisplay;
@end

@interface UIApplication (Apple)
- (void) applicationSuspend:(GSEventRef)event;
- (void) _animateSuspension:(BOOL)suspend duration:(double)duration startTime:(double)start scale:(float)scale;
- (void) applicationOpenURL:(NSURL *)url;
- (void) applicationWillResignActive:(UIApplication *)application;
- (void) applicationWillSuspend;
- (void) launchApplicationWithIdentifier:(NSString *)identifier suspended:(BOOL)suspended;
- (void) openURL:(NSURL *)url asPanel:(BOOL)panel;
- (void) setStatusBarShowsProgress:(BOOL)shows;
- (void) _setSuspended:(BOOL)suspended;
- (void) terminateWithSuccess;
@end

@interface UIBarButtonItem (Apple)
- (UIView *) view;
@end

@interface UIColor (Apple)
+ (UIColor *) pinStripeColor;
@end

@interface UIControl (Apple)
- (void) addTarget:(id)target action:(SEL)action forEvents:(NSInteger)events;
@end

@interface UIDevice (Apple)
- (BOOL) isWildcat;
@end

@interface UIImage (Apple)
+ (UIImage *) applicationImageNamed:(NSString *)name;
+ (UIImage *) imageAtPath:(NSString *)path;
@end

@interface UINavigationBar (Apple)
+ (CGSize) defaultSize;
- (UIBarStyle) _barStyle:(BOOL)style;
@end

@interface UIScrollView (Apple)
- (void) setScrollingEnabled:(BOOL)enabled;
- (void) setShowBackgroundShadow:(BOOL)show;
@end

@interface UISearchBar (Apple)
- (UITextField *) searchField;
@end

@interface UITabBarController (Apple)
- (UITransitionView *) _transitionView;
- (void) concealTabBarSelection;
- (void) revealTabBarSelection;
@end

@interface UITabBarItem (Apple)
- (void) setAnimatedBadge:(BOOL)animated;
@end

@interface UITableViewCell (Apple)
- (float) selectionPercent;
- (void) _updateHighlightColorsForView:(id)view highlighted:(BOOL)highlighted;
@end

@interface UITextField (Apple)
- (UITextInputTraits *) textInputTraits;
@end

@interface UITextView (Apple)
- (UIFont *) font;
- (void) setAllowsRubberBanding:(BOOL)rubberbanding;
- (void) setFont:(UIFont *)font;
- (void) setMarginTop:(int)margin;
- (void) setTextColor:(UIColor *)color;
@end

@interface UIView (Apple)
- (UIScroller *) _scroller;
- (void) setClipsSubviews:(BOOL)clips;
- (void) setEnabledGestures:(NSInteger)gestures;
- (void) setFixedBackgroundPattern:(BOOL)fixed;
- (void) setGestureDelegate:(id)delegate;
- (void) setNeedsDisplayOnBoundsChange:(BOOL)needs;
- (void) setValue:(NSValue *)value forGestureAttribute:(NSInteger)attribute;
- (void) setZoomScale:(float)scale duration:(double)duration;
- (void) _setZoomScale:(float)scale duration:(double)duration;
@end

@interface UIViewController (Apple)
- (void) _updateLayoutForStatusBarAndInterfaceOrientation;
- (void) unloadView;
@end

@interface UIWindow (Apple)
- (UIResponder *) firstResponder;
- (void) makeKey:(UIApplication *)application;
- (void) orderFront:(UIApplication *)application;
@end

@interface UIWebView (Apple)
- (UIWebDocumentView *) _documentView;
- (UIScrollView *) _scrollView;
- (UIScroller *) _scroller;
- (void) _updateViewSettings;
- (void) webView:(WebView *)view addMessageToConsole:(NSDictionary *)message;
//- (WebView *) webView:(WebView *)view createWebViewWithRequest:(NSURLRequest *)request;
- (void) webView:(WebView *)view decidePolicyForNavigationAction:(NSDictionary *)action request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener;
- (void) webView:(WebView *)view decidePolicyForNewWindowAction:(NSDictionary *)action request:(NSURLRequest *)request newFrameName:(NSString *)name decisionListener:(id<WebPolicyDecisionListener>)listener;
- (void) webView:(WebView *)view didClearWindowObject:(WebScriptObject *)window forFrame:(WebFrame *)frame;
- (void) webView:(WebView *)view didCommitLoadForFrame:(WebFrame *)frame;
- (void) webView:(WebView *)view didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame;
- (void) webView:(WebView *)view didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame;
- (void) webView:(WebView *)view didFinishLoadForFrame:(WebFrame *)frame;
- (void) webView:(WebView *)view didReceiveTitle:(id)title forFrame:(id)frame;
- (void) webView:(WebView *)view didStartProvisionalLoadForFrame:(WebFrame *)frame;
- (NSURLRequest *) webView:(WebView *)view resource:(id)identifier willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response fromDataSource:(WebDataSource *)source;
- (void) webView:(WebView *)view runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame;
- (BOOL) webView:(WebView *)view runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame;
- (NSString *) webView:(WebView *)view runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt defaultText:(NSString *)text initiatedByFrame:(WebFrame *)frame;
- (void) webViewClose:(WebView *)view;
@end
// }}}
// @interface Web* (*) {{{
@interface WebFrame (Apple)
- (void) setNeedsLayout;
@end

@interface WebPreferences (Apple)
+ (void) _setInitialDefaultTextEncodingToSystemEncoding;
- (void) _setLayoutInterval:(NSInteger)interval;
- (void) setOfflineWebApplicationCacheEnabled:(BOOL)enabled;
@end
// }}}

// #ifndef AVAILABLE_MAC_OS_X_VERSION_10_6_AND_LATER {{{
#ifndef AVAILABLE_MAC_OS_X_VERSION_10_6_AND_LATER
#define AVAILABLE_MAC_OS_X_VERSION_10_6_AND_LATER
// XXX: this is a random jumble of garbage

typedef enum {
    UIModalPresentationFullScreen,
    UIModalPresentationPageSheet,
    UIModalPresentationFormSheet,
    UIModalPresentationCurrentContext,
} UIModalPresentationStyle;

#define kSCNetworkReachabilityFlagsConnectionOnTraffic kSCNetworkReachabilityFlagsConnectionAutomatic

#define UIBarStyleBlack UIBarStyleBlackOpaque

@class NSUndoManager;
@class UIPasteboard;

@interface UIActionSheet (iPad)
- (void) showFromBarButtonItem:(UIBarButtonItem *)item animated:(BOOL)animated;
@end

@interface UIViewController (iPad)
- (void) setModalPresentationStyle:(UIModalPresentationStyle)style;
@end

@interface UIApplication (iOS_3_0)
@property(nonatomic) BOOL applicationSupportsShakeToEdit;
@end

@interface UIScrollView (iOS_3_0)
@property(assign,nonatomic) float decelerationRate;
@end

@interface UIWebView (iOS_3_0)
@property(assign,nonatomic) NSUInteger dataDetectorTypes;
@end

extern float const UIScrollViewDecelerationRateNormal;

#endif//AVAILABLE_MAC_OS_X_VERSION_10_6_AND_LATER
// }}}
// #if __IPHONE_OS_VERSION_MIN_REQUIRED < 30000 {{{
#if __IPHONE_OS_VERSION_MIN_REQUIRED < 30000

#define kSCNetworkReachabilityFlagsConnectionOnDemand (1 << 5)
#define kCFCoreFoundationVersionNumber_iPhoneOS_3_0 478.47

#endif
// }}}

#ifndef kCFCoreFoundationVersionNumber_iPhoneOS_4_0
#define kCFCoreFoundationVersionNumber_iPhoneOS_4_0 550.32
#endif

@interface UIScreen (iOS_4_0)
@property(nonatomic,readonly) CGFloat scale;
@end

@interface DOMHTMLIFrameElement (IDL)
- (WebFrame *) contentFrame;
@end

// extern *; {{{
extern CFStringRef const kGSDisplayIdentifiersCapability;
extern float const UIWebViewGrowsAndShrinksToFitHeight;
extern float const UIWebViewScalesToFitScale;
// }}}
// extern "C" *(); {{{
extern "C" void *reboot2(uint64_t flags);
extern "C" mach_port_t SBSSpringBoardServerPort();
extern "C" UIImage *_UIImageWithName(NSString *name);
extern "C" void UISetColor(CGColorRef color);
// }}}

#endif//CYDIA_UIKITPRIVATE_H
