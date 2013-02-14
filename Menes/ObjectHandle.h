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

#ifndef Menes_ObjectHandle_H
#define Menes_ObjectHandle_H

#include "CyteKit/UCPlatform.h"

#include <CoreFoundation/CoreFoundation.h>
#include <Foundation/Foundation.h>

template <typename Type_, unsigned Delegate_>
struct MenesObjectHandle_;

template <typename Type_>
struct MenesObjectHandle_<Type_, 0> {
    static _finline void Execute(Type_ *value) {
    }
};

template <typename Type_>
struct MenesObjectHandle_<Type_, 1> {
    static _finline void Execute(Type_ *value) {
        [value setDelegate:nil];
    }
};

template <typename Type_>
struct MenesObjectHandle_<Type_, 2> {
    static _finline void Execute(Type_ *value) {
        [value setDelegate:nil];
        [value setDataSource:nil];
    }
};

template <typename Type_, unsigned Delegate_ = 0>
class MenesObjectHandle {
  private:
    Type_ *value_;

    _finline void Retain_() {
        if (value_ != nil)
            CFRetain((CFTypeRef) value_);
    }

    _finline void Release_(Type_ *value) {
        if (value != nil) {
            MenesObjectHandle_<Type_, Delegate_>::Execute(value);
            CFRelease((CFTypeRef) value);
        }
    }

  public:
    _finline MenesObjectHandle(const MenesObjectHandle &rhs) :
        value_(rhs.value_ == nil ? nil : (Type_ *) CFRetain((CFTypeRef) rhs.value_))
    {
    }

    _finline MenesObjectHandle(Type_ *value = NULL, bool mended = false) :
        value_(value)
    {
        if (!mended)
            Retain_();
    }

    _finline ~MenesObjectHandle() {
        Release_(value_);
    }

    _finline operator Type_ *() const {
        return value_;
    }

    _finline Type_ *operator ->() const {
        return value_;
    }

    _finline MenesObjectHandle &operator =(Type_ *value) {
        if (value_ != value) {
            Type_ *old(value_);
            value_ = value;
            Retain_();
            Release_(old);
        } return *this;
    }

    _finline MenesObjectHandle &operator =(const MenesObjectHandle &value) {
        return this->operator =(value.operator Type_ *());
    }
};

#define _H MenesObjectHandle

#define rproperty_(Class, field) \
    - (typeof(((Class*)nil)->_##field.operator->())) field { \
        return _##field; \
    }

#define wproperty_(Class, field, Field) \
    - (void) set##Field:(typeof(((Class*)nil)->_##field.operator->()))field { \
        _##field = field; \
    }

#define roproperty(Class, field) \
@implementation Class (Menes_##field) \
rproperty_(Class, field) \
@end

#define rwproperty(Class, field, Field) \
@implementation Class (Menes_##field) \
rproperty_(Class, field) \
wproperty_(Class, field, Field) \
@end

#endif//Menes_ObjectHandle_H
