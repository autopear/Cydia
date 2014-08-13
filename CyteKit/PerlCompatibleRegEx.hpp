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

#ifndef Cydia_PerlCompatibleRegEx_HPP
#define Cydia_PerlCompatibleRegEx_HPP

#include <pcre.h>

#include "CyteKit/UCPlatform.h"
#include "CyteKit/stringWithUTF8Bytes.h"

class Pcre {
  private:
    pcre *code_;
    pcre_extra *study_;
    int capture_;
    int *matches_;
    const char *data_;

  public:
    Pcre() :
        code_(NULL),
        study_(NULL),
        data_(NULL)
    {
    }

    Pcre(const char *regex, NSString *data = nil) :
        code_(NULL),
        study_(NULL),
        data_(NULL)
    {
        this->operator =(regex);

        if (data != nil)
            this->operator ()(data);
    }

    void operator =(const char *regex) {
        _assert(code_ == NULL);

        const char *error;
        int offset;
        code_ = pcre_compile(regex, 0, &error, &offset, NULL);

        if (code_ == NULL) {
            fprintf(stderr, "%d:%s\n", offset, error);
            _assert(false);
        }

        pcre_fullinfo(code_, study_, PCRE_INFO_CAPTURECOUNT, &capture_);
        _assert(capture_ >= 0);
        matches_ = new int[(capture_ + 1) * 3];
    }

    ~Pcre() {
        pcre_free(code_);
        delete matches_;
    }

    NSString *operator [](size_t match) const {
        return [NSString stringWithUTF8Bytes:(data_ + matches_[match * 2]) length:(matches_[match * 2 + 1] - matches_[match * 2])];
    }

    _finline bool operator ()(NSString *data) {
        // XXX: length is for characters, not for bytes
        return operator ()([data UTF8String], [data length]);
    }

    _finline bool operator ()(const char *data) {
        return operator ()(data, strlen(data));
    }

    bool operator ()(const char *data, size_t size) {
        if (pcre_exec(code_, study_, data, size, 0, 0, matches_, (capture_ + 1) * 3) >= 0) {
            data_ = data;
            return true;
        } else {
            data_ = NULL;
            return false;
        }
    }

    operator bool() const {
        return data_ != NULL;
    }

    NSString *operator ->*(NSString *format) const {
        id values[capture_];
        for (int i(0); i != capture_; ++i)
            values[i] = this->operator [](i + 1);

        return [[[NSString alloc] initWithFormat:format arguments:reinterpret_cast<va_list>(values)] autorelease];
    }
};

#endif//Cydia_PerlCompatibleRegEx_HPP
