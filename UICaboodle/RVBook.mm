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

@implementation RVBook

- (void) dealloc {
    [navbar_ setDelegate:nil];

    [pages_ release];
    [navbar_ release];
    [transition_ release];
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

        navbar_ = [[UINavigationBar alloc] initWithFrame:navrect];
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

- (void) pushPage:(RVPage *)page {
    if ([pages_ count] != 0)
        [[pages_ lastObject] setPageActive:NO];

    NSString *title = [self getTitleForPage:page];

    NSString *backButtonTitle = [page backButtonTitle];
    if (backButtonTitle == nil)
        backButtonTitle = title;

    UINavigationItem *navitem = [[[UINavigationItem alloc] initWithTitle:title] autorelease];
    [navitem setBackButtonTitle:backButtonTitle];
    [navbar_ pushNavigationItem:navitem];

    BOOL animated = [pages_ count] == 0 ? NO : YES;
    [page setFrame:[transition_ bounds]];
    [transition_ transition:(animated ? 1 : 0) toView:page];
    [page setPageActive:YES];

    [pages_ addObject:page];
    [self reloadButtonsForPage:page];

    [navbar_ setAccessoryView:[page accessoryView] animate:animated removeOnPop:NO];
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

- (void) setTitle:(NSString *)title forPage:(RVPage *)page {
    if ([pages_ count] == 0 || page != [pages_ lastObject])
        return;
    UINavigationItem *navitem = [navbar_ topItem];
    [navitem setTitle:title];
}

- (void) setBackButtonTitle:(NSString *)title forPage:(RVPage *)page {
    if ([pages_ count] == 0 || page != [pages_ lastObject])
        return;
    UINavigationItem *navitem = [navbar_ topItem];
    [navitem setBackButtonTitle:title];
}

- (void) reloadButtonsForPage:(RVPage *)page {
    if ([pages_ count] == 0 || page != [pages_ lastObject])
        return;
    NSString *leftButtonTitle([page leftButtonTitle]);
    UINavigationButtonStyle leftButtonStyle = [page leftButtonStyle];
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

@end
