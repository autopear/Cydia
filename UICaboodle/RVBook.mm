#import "RVBook.h"

#import <UIKit/UINavigationBar.h>
#import <UIKit/UINavigationItem.h>

#import <UIKit/UITransitionView.h>

#import <UIKit/UIView-Geometry.h>
#import <UIKit/UIView-Hierarchy.h>

#import <Foundation/Foundation.h>
#import <CoreGraphics/CGGeometry.h>

#include <cstdio>
#include <cstdlib>

#include <errno.h>

#import "RVPage.h"

@interface NSObject (UICaboodleRVBook)
- (float) widthForButtonContents:(float)width;
@end

@implementation NSObject (UICaboodleRVBook)

- (float) widthForButtonContents:(float)width {
    return width;
}

@end

@interface UIImage (UICaboodleRVBook)
- (float) widthForButtonContents:(float)width;
@end

@implementation UIImage (UICaboodleRVBook)

- (float) widthForButtonContents:(float)width {
    return [self size].width + 8;
}

@end

@interface RVNavigationBar : UINavigationBar {
}

- (id) createButtonWithContents:(id)contents width:(float)width barStyle:(int)barStyle buttonStyle:(int)style isRight:(BOOL)right;
@end

@implementation RVNavigationBar

- (id) createButtonWithContents:(id)contents width:(float)width barStyle:(int)barStyle buttonStyle:(int)style isRight:(BOOL)right {
    float adjust = [contents widthForButtonContents:width];
    width = adjust;
    return [super createButtonWithContents:contents width:width barStyle:barStyle buttonStyle:style isRight:right];
}

@end

@implementation RVBook

- (void) dealloc {
    [navbar_ setDelegate:nil];
    if (toolbar_ != nil)
        [toolbar_ setDelegate:nil];

    [pages_ release];
    [navbar_ release];
    [transition_ release];
    if (toolbar_ != nil)
        [toolbar_ release];
    [super dealloc];
}

- (UINavigationBar *) navigationBar {
    return navbar_;
}

- (void) navigationBar:(UINavigationBar *)navbar buttonClicked:(int)button {
    _assert([pages_ count] != 0);
    RVPage *page = [pages_ lastObject];
    switch (button) {
        case 0: [page _rightButtonClicked]; break;
        case 1: [page _leftButtonClicked]; break;
    }
}

- (void) navigationBar:(UINavigationBar *)navbar poppedItem:(UINavigationItem *)item {
    _assert([pages_ count] != 0);
    if (!resetting_)
        [[pages_ lastObject] setPageActive:NO];
    [pages_ removeLastObject];
    if (!resetting_)
        [self resetViewAnimated:YES toPage:[pages_ lastObject]];
}

- (id) initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame]) != nil) {
        pages_ = [[NSMutableArray arrayWithCapacity:4] retain];

        struct CGRect bounds = [self bounds];
        CGSize navsize = [UINavigationBar defaultSize];
        CGRect navrect = {{0, 0}, navsize};

        navbar_ = [[RVNavigationBar alloc] initWithFrame:navrect];
        [self addSubview:navbar_];

        [navbar_ setBarStyle:0];
        [navbar_ setDelegate:self];

        transition_ = [[UITransitionView alloc] initWithFrame:CGRectMake(
            bounds.origin.x, bounds.origin.y + navsize.height, bounds.size.width, bounds.size.height - navsize.height
        )];

        [self addSubview:transition_];
    } return self;
}

- (void) setDelegate:(id)delegate {
    delegate_ = delegate;
}

- (void) setPage:(RVPage *)page {
    if ([pages_ count] != 0)
        [[pages_ lastObject] setPageActive:NO];

    [navbar_ disableAnimation];
    resetting_ = true;
    for (unsigned i(0), pages([pages_ count]); i != pages; ++i)
        [navbar_ popNavigationItem];
    resetting_ = false;

    [self pushPage:page];
    [navbar_ enableAnimation];
}

- (void) swapPage:(RVPage *)page {
    if ([pages_ count] == 0)
        return [self pushPage:page];

    [[pages_ lastObject] setPageActive:NO];

    [navbar_ disableAnimation];
    resetting_ = true;
    [navbar_ popNavigationItem];
    resetting_ = false;

    [self pushPage:page animated:NO];
    [navbar_ enableAnimation];
}

- (void) pushPage:(RVPage *)page animated:(BOOL)animated {
    NSString *title = [self getTitleForPage:page];

    NSString *backButtonTitle = [page backButtonTitle];
    if (backButtonTitle == nil)
        backButtonTitle = title;

    UINavigationItem *navitem = [[[UINavigationItem alloc] initWithTitle:title] autorelease];
    [navitem setBackButtonTitle:backButtonTitle];
    [navbar_ pushNavigationItem:navitem];

    [page setFrame:[transition_ bounds]];
    [transition_ transition:(animated ? 1 : 0) toView:page];
    [page setPageActive:YES];

    [pages_ addObject:page];
    [self reloadButtonsForPage:page];

    [navbar_ setAccessoryView:[page accessoryView] animate:animated removeOnPop:NO];
}

- (void) pushPage:(RVPage *)page {
    if ([pages_ count] != 0)
        [[pages_ lastObject] setPageActive:NO];
    [self pushPage:page animated:([pages_ count] == 0 ? NO : YES)];
}

- (void) pushBook:(RVBook *)book {
    [delegate_ popUpBook:book];
}

- (void) popPages:(unsigned)pages {
    if (pages == 0)
        return;

    [[pages_ lastObject] setPageActive:NO];

    resetting_ = true;
    for (unsigned i(0); i != pages; ++i)
        [navbar_ popNavigationItem];
    resetting_ = false;

    [self resetViewAnimated:YES toPage:[pages_ lastObject]];
}

- (void) resetViewAnimated:(BOOL)animated {
    resetting_ = true;

    if ([pages_ count] > 1) {
        [navbar_ disableAnimation];
        while ([pages_ count] != (animated ? 2 : 1))
            [navbar_ popNavigationItem];
        [navbar_ enableAnimation];
        if (animated)
            [navbar_ popNavigationItem];
    }

    resetting_ = false;

    [self resetViewAnimated:animated toPage:[pages_ lastObject]];
}

- (void) resetViewAnimated:(BOOL)animated toPage:(RVPage *)page {
    [page resetViewAnimated:animated];
    [page setFrame:[transition_ bounds]];
    [transition_ transition:(animated ? 2 : 0) toView:page];
    [page setPageActive:YES];
    [self reloadButtonsForPage:page];

    [navbar_ setAccessoryView:[page accessoryView] animate:animated removeOnPop:NO];
}

- (void) setBackButtonTitle:(NSString *)title forPage:(RVPage *)page {
    if ([pages_ count] == 0 || page != [pages_ lastObject])
        return;
    UINavigationItem *navitem = [navbar_ topItem];
    [navitem setBackButtonTitle:title];
}

- (void) reloadTitleForPage:(RVPage *)page {
    if ([pages_ count] == 0 || page != [pages_ lastObject])
        return;
    UINavigationItem *navitem = [navbar_ topItem];
    NSString *title = [self getTitleForPage:page];
    [navitem setTitle:title];
}

- (void) _leftButtonTitle:(NSString *&)leftButtonTitle style:(UINavigationButtonStyle &)leftButtonStyle forPage:(RVPage *)page {
    leftButtonTitle = [page leftButtonTitle];
    leftButtonStyle = [page leftButtonStyle];
}

- (void) reloadButtonsForPage:(RVPage *)page {
    if ([pages_ count] == 0 || page != [pages_ lastObject])
        return;

    NSString *leftButtonTitle;
    UINavigationButtonStyle leftButtonStyle;
    [self _leftButtonTitle:leftButtonTitle style:leftButtonStyle forPage:page];

    UINavigationButtonStyle rightButtonStyle = [page rightButtonStyle];
    //[navbar_ showButtonsWithLeftTitle:leftButtonTitle rightTitle:[page rightButtonTitle] leftBack:(leftButtonTitle == nil)];

    [navbar_
        showLeftButton:leftButtonTitle
        withStyle:leftButtonStyle
        rightButton:[page rightButtonTitle]
        withStyle:rightButtonStyle
    ];
}

- (NSString *) getTitleForPage:(RVPage *)page {
    return [page title];
}

- (void) reloadData {
    for (int i(0), e([pages_ count]); i != e; ++i) {
        RVPage *page([pages_ objectAtIndex:(e - i - 1)]);
        [page reloadData];
    }
}

- (CGRect) pageBounds {
    return [transition_ bounds];
}

- (void) close {
}

@end

@implementation RVPopUpBook

- (void) _leftButtonTitle:(NSString *&)leftButtonTitle style:(UINavigationButtonStyle &)leftButtonStyle forPage:(RVPage *)page {
    [super _leftButtonTitle:leftButtonTitle style:leftButtonStyle forPage:page];
    if ((cancel_ = leftButtonTitle == nil && [pages_ count] == 1)) {
        leftButtonTitle = @"Cancel";
        leftButtonStyle = UINavigationButtonStyleNormal;
    }
}

- (void) navigationBar:(UINavigationBar *)navbar buttonClicked:(int)button {
    if (button == 1 && cancel_)
        [self close];
    else
        [super navigationBar:navbar buttonClicked:button];
}

- (void) close {
    [self popFromSuperviewAnimated:YES];
}

@end
