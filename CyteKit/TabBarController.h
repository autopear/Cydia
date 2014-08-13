/* Cydia - iPhone UIKit Front-End for Debian APT
 * Copyright (C) 2008-2014  Jay Freeman (saurik)
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

#ifndef CyteKit_TabBarController_H
#define CyteKit_TabBarController_H

#include <CyteKit/UCPlatform.h>
#include <CyteKit/ViewController.h>

#include <UIKit/UIKit.h>

#include <Menes/ObjectHandle.h>

@interface UITabBarController (Cydia)
@end

@interface CyteTabBarController : UITabBarController {
    _transient UIViewController *transient_;
    _H<UIViewController> remembered_;
}

- (UIViewController *) unselectedViewController;
- (void) setUnselectedViewController:(UIViewController *)transient;

@end

#endif//CyteKit_TabBarController_H
