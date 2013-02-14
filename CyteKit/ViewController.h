/* Cydia - iPhone UIKit Front-End for Debian APT
 * Copyright (C) 2008-2012  Jay Freeman (saurik)
*/

/* Modified BSD License {{{ */
/*
 *        Redistribution and use in source and binary
 * forms, with or without modification, are permitted
 * provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the
 *    above copyright notice, this list of conditions
 *    and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the
 *    above copyright notice, this list of conditions
 *    and the following disclaimer in the documentation
 *    and/or other materials provided with the
 *    distribution.
 * 3. The name of the author may not be used to endorse
 *    or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS''
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING,
 * BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
 * TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
 * ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/
/* }}} */

#ifndef CyteKit_ViewController_H
#define CyteKit_ViewController_H

#include <CyteKit/UCPlatform.h>

#include <UIKit/UIKit.h>

@interface UIViewController (Cydia)
- (BOOL) hasLoaded;
- (void) reloadData;
- (void) unloadData;
- (UIViewController *) parentOrPresentingViewController;
@end

@interface CyteViewController : UIViewController {
    _transient id delegate_;
    BOOL loaded_;
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

@end

#endif//CyteKit_ViewController_H
