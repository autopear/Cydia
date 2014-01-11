/* Cydia - iPhone UIKit Front-End for Debian APT
 * Copyright (C) 2008-2013  Jay Freeman (saurik)
*/

/* GNU General Public License, Version 3 {{{ */
/*
 * Cydia is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published
 * by the Free Software Foundation, either version 3 of the License,
 * or (at your option) any later version.
 *
 * Cydia is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Cydia.  If not, see <http://www.gnu.org/licenses/>.
**/
/* }}} */

#include "Cydia/LoadingViewController.h"

@implementation CydiaLoadingViewController

- (void) loadView {
    UIView *view([[[UIView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame]] autorelease]);
    [view setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)];
    [self setView:view];

    UITableView *table([[[UITableView alloc] initWithFrame:[[self view] bounds] style:UITableViewStyleGrouped] autorelease]);
    [table setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)];
    [[self view] addSubview:table];

    indicator_ = [[[CydiaLoadingView alloc] initWithFrame:[[self view] bounds]] autorelease];
    [indicator_ setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)];
    [[self view] addSubview:indicator_];

    tabbar_ = [[[UITabBar alloc] initWithFrame:CGRectMake(0, 0, 0, 49.0f)] autorelease];
    [tabbar_ setFrame:CGRectMake(0.0f, [[self view] bounds].size.height - [tabbar_ bounds].size.height, [[self view] bounds].size.width, [tabbar_ bounds].size.height)];
    [tabbar_ setAutoresizingMask:(UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth)];
    [[self view] addSubview:tabbar_];

    navbar_ = [[[UINavigationBar alloc] initWithFrame:CGRectMake(0, 0, 0, 44.0f)] autorelease];
    [navbar_ setFrame:CGRectMake(0.0f, 0.0f, [[self view] bounds].size.width, [navbar_ bounds].size.height)];
    [navbar_ setAutoresizingMask:(UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleWidth)];
    [[self view] addSubview:navbar_];
}

- (void) releaseSubviews {
    indicator_ = nil;
    tabbar_ = nil;
    navbar_ = nil;
}

@end
