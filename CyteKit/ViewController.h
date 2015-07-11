/* Cydia - iPhone UIKit Front-End for Debian APT
 * Copyright (C) 2008-2015  Jay Freeman (saurik)
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

#ifndef CyteKit_ViewController_H
#define CyteKit_ViewController_H

#include <CyteKit/UCPlatform.h>

#include <UIKit/UIKit.h>

#include <Menes/ObjectHandle.h>

@interface UIViewController (Cydia)
- (BOOL) hasLoaded;
- (void) reloadData;
- (void) unloadData;
- (UIViewController *) parentOrPresentingViewController;
@end

@interface CyteViewController : UIViewController {
    _transient id delegate_;
    BOOL loaded_;
    _H<UIColor> color_;
}

// The default implementation of this method is essentially a no-op,
// but calling the superclass implementation is *required*.
- (void) reloadData;

- (void) unloadData;

// This URL is used to save the state of the view controller. Return
// nil if you cannot or should not save the URL for this page.
- (NSURL *) navigationURL;

// By default, this delegate is unused. However, it's provided here in case
// you need some kind of delegate in a subclass.
- (void) setDelegate:(id)delegate;
- (id) delegate;

// Override this in subclasses if you manage the "has seen first load" state yourself.
- (BOOL) hasLoaded;

// This is called when the view managed by the view controller is released.
// That is not always when the controller itself is released: it also can
// happen when more memory is needed by the system or whenever the controller
// just happens not to be visible.
- (void) releaseSubviews;

- (void) setPageColor:(UIColor *)color;

@end

#endif//CyteKit_ViewController_H
