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

#include "CyteKit/dispatchEvent.h"
#include "CyteKit/WebThreadLocked.hpp"

#include <WebCore/WebEvent.h>

#include <WebKit/WebFrame.h>
#include <WebKit/WebScriptObject.h>
#include <WebKit/WebView.h>

#include <objc/runtime.h>

#include <CydiaSubstrate/CydiaSubstrate.h>

@implementation UIWebDocumentView (CyteDispatchEvent)

- (void) dispatchEvent:(NSString *)event {
    WebThreadLocked lock;

    NSString *script([NSString stringWithFormat:@
        "(function() {"
            "var event = this.document.createEvent('Events');"
            "event.initEvent('%@', false, false);"
            "this.document.dispatchEvent(event);"
        "})();"
    , event]);

    NSMutableArray *frames([NSMutableArray arrayWithObjects:
        [[self webView] mainFrame]
    , nil]);

    while (WebFrame *frame = [frames lastObject]) {
        WebScriptObject *object([frame windowObject]);
        [object evaluateWebScript:script];
        [frames removeLastObject];
        [frames addObjectsFromArray:[frame childFrames]];
    }
}

@end

MSHook(void, UIWebBrowserView$_webTouchEventsRecognized$, UIWebBrowserView *self, SEL _cmd, UIWebTouchEventsGestureRecognizer *recognizer) {
    _UIWebBrowserView$_webTouchEventsRecognized$(self, _cmd, recognizer);

    switch ([recognizer type]) {
        case WebEventTouchEnd:
            [self dispatchEvent:@"CydiaTouchEnd"];
        break;

        case WebEventTouchCancel:
            [self dispatchEvent:@"CydiaTouchCancel"];
        break;
    }
}

__attribute__((__constructor__)) static void $() {
    if (Class $UIWebBrowserView = objc_getClass("UIWebBrowserView")) {
        if (Method method = class_getInstanceMethod($UIWebBrowserView, @selector(_webTouchEventsRecognized:))) {
            _UIWebBrowserView$_webTouchEventsRecognized$ = reinterpret_cast<void (*)(UIWebBrowserView *, SEL, UIWebTouchEventsGestureRecognizer *)>(method_getImplementation(method));
            method_setImplementation(method, reinterpret_cast<IMP>(&$UIWebBrowserView$_webTouchEventsRecognized$));
        }
    }
}
