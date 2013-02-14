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

#include "CyteKit/MFMailComposeViewController-MailToURL.h"

#include <objc/runtime.h>
#include <dlfcn.h>

static void $MFMailComposeViewController$setMailToURL$(MFMailComposeViewController *self, SEL _cmd, NSURL *url) {
    NSString *scheme([url scheme]);

    if (scheme == nil || ![[scheme lowercaseString] isEqualToString:@"mailto"])
        [NSException raise:NSInvalidArgumentException format:@"-[MFMailComposeViewController setMailToURL:] - non-mailto: URL"];

    NSString *href([url absoluteString]);
    NSRange question([href rangeOfString:@"?"]);

    NSMutableArray *to([NSMutableArray arrayWithCapacity:1]);

    NSString *target, *query;
    if (question.location == NSNotFound) {
        target = [href substringFromIndex:7];
        query = nil;
    } else {
        target = [href substringWithRange:NSMakeRange(7, question.location - 7)];
        query = [href substringFromIndex:(question.location + 1)];
    }

    if ([target length] != 0)
        [to addObject:target];

    if (query != nil && [query length] != 0) {
        NSMutableArray *cc([NSMutableArray arrayWithCapacity:1]);
        NSMutableArray *bcc([NSMutableArray arrayWithCapacity:1]);

        for (NSString *assign in [query componentsSeparatedByString:@"&"]) {
            NSRange equal([assign rangeOfString:@"="]);
            if (equal.location == NSNotFound)
                continue;

            NSString *name([assign substringToIndex:equal.location]);
            NSString *value([assign substringFromIndex:(equal.location + 1)]);
            value = [value stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];

            if (false);
            else if ([name isEqualToString:@"attachment"]) {
                if (NSData *data = [NSData dataWithContentsOfFile:value])
                    [self addAttachmentData:data mimeType:@"application/octet-stream" fileName:[value lastPathComponent]];
            } else if ([name isEqualToString:@"bcc"])
                [bcc addObject:value];
            else if ([name isEqualToString:@"body"])
                [self setMessageBody:value isHTML:NO];
            else if ([name isEqualToString:@"cc"])
                [cc addObject:value];
            else if ([name isEqualToString:@"subject"])
                [self setSubject:value];
            else if ([name isEqualToString:@"to"])
                [to addObject:value];
        }

        [self setCcRecipients:cc];
        [self setBccRecipients:bcc];
    }

    [self setToRecipients:to];
}

__attribute__((__constructor__)) static void MFMailComposeViewController_CyteMailToURL() {
    dlopen("/System/Library/Frameworks/MessageUI.framework/MessageUI", RTLD_GLOBAL | RTLD_LAZY);
    if (Class MFMailComposeViewController = objc_getClass("MFMailComposeViewController"))
        class_addMethod(MFMailComposeViewController, @selector(setMailToURL:), (IMP) $MFMailComposeViewController$setMailToURL$, "v12@0:4@8");
}
