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

#include "CyteKit/ViewController.h"

#include <Foundation/Foundation.h>
#include <UIKit/UIKit.h>

extern bool IsWildcat_;

@implementation UIViewController (Cydia)

- (BOOL) hasLoaded {
    return YES;
}

- (void) reloadData {
    [self view];
}

- (void) unloadData {
    if (UIViewController *modal = [self modalViewController])
        [modal unloadData];
}

- (UIViewController *) parentOrPresentingViewController {
    if (UIViewController *parent = [self parentViewController])
        return parent;
    if ([self respondsToSelector:@selector(presentingViewController)])
        return [self presentingViewController];
    return nil;
}

@end

@implementation CyteViewController

- (void) setDelegate:(id)delegate {
    delegate_ = delegate;
}

- (id) delegate {
    return delegate_;
}

- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // Load on first appearance. We don't need to set the loaded flag here
    // because it is set for us the first time -reloadData is called.
    if (![self hasLoaded])
        [self reloadData];
}

- (BOOL) hasLoaded {
    return loaded_;
}

- (void) releaseSubviews {
    loaded_ = NO;
}

- (void) setView:(UIView *)view {
    // Nasty hack for 2.x-compatibility. In 3.0+, we can and
    // should just override -viewDidUnload instead.
    if (view == nil)
        [self releaseSubviews];

    [super setView:view];
}

- (void) reloadData {
    [super reloadData];

    // This is called automatically on the first appearance of a controller,
    // or any other time it needs to reload the information shown. However (!),
    // this is not called by any tab bar or navigation controller's -reloadData
    // method unless this controller returns YES from -hadLoaded.
    loaded_ = YES;
}

- (void) unloadData {
    loaded_ = NO;
    [super unloadData];
}

- (NSURL *) navigationURL {
    return nil;
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return IsWildcat_ || orientation == UIInterfaceOrientationPortrait;
}

@end
