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

#ifndef Cydia_ProgressEvent_H
#define Cydia_ProgressEvent_H

#include <Foundation/Foundation.h>

#include <CydiaSubstrate/CydiaSubstrate.h>

#include <apt-pkg/acquire.h>

@interface CydiaProgressEvent : NSObject {
    _H<NSString> message_;
    _H<NSString> type_;

    _H<NSArray> item_;
    _H<NSString> package_;
    _H<NSString> url_;
    _H<NSString> version_;
}

+ (CydiaProgressEvent *) eventWithMessage:(NSString *)message ofType:(NSString *)type;
+ (CydiaProgressEvent *) eventWithMessage:(NSString *)message ofType:(NSString *)type forPackage:(NSString *)package;
+ (CydiaProgressEvent *) eventWithMessage:(NSString *)message ofType:(NSString *)type forItem:(pkgAcquire::ItemDesc &)item;

- (id) initWithMessage:(NSString *)message ofType:(NSString *)type;

- (NSString *) message;
- (NSString *) type;

- (NSArray *) item;
- (NSString *) package;
- (NSString *) url;
- (NSString *) version;

- (void) setItem:(NSArray *)item;
- (void) setPackage:(NSString *)package;
- (void) setURL:(NSString *)url;
- (void) setVersion:(NSString *)version;

- (NSString *) compound:(NSString *)value;
- (NSString *) compoundMessage;
- (NSString *) compoundTitle;

@end

@protocol ProgressDelegate
- (void) addProgressEvent:(CydiaProgressEvent *)event;
- (void) setProgressPercent:(NSNumber *)percent;
- (void) setProgressStatus:(NSDictionary *)status;
- (void) setProgressCancellable:(NSNumber *)cancellable;
- (bool) isProgressCancelled;
- (void) setTitle:(NSString *)title;
@end

#endif//Cydia_ProgressEvent_H
