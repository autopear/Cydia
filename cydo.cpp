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

#include <cstdio>
#include <cstdlib>

#include <errno.h>
#include <sysexits.h>
#include <unistd.h>

#include <launch.h>

#include <Menes/Function.h>

typedef Function<void, const char *, launch_data_t> LaunchDataIterator;

void launch_data_dict_iterate(launch_data_t data, LaunchDataIterator code) {
    launch_data_dict_iterate(data, [](launch_data_t value, const char *name, void *baton) {
        (*static_cast<LaunchDataIterator *>(baton))(name, value);
    }, &code);
}

int main(int argc, char *argv[]) {
    auto request(launch_data_new_string(LAUNCH_KEY_GETJOBS));
    auto response(launch_msg(request));
    launch_data_free(request);

    _assert(response != NULL);
    _assert(launch_data_get_type(response) == LAUNCH_DATA_DICTIONARY);

    auto parent(getppid());

    auto cydia(false);

    launch_data_dict_iterate(response, [=, &cydia](const char *name, launch_data_t value) {
        if (launch_data_get_type(response) != LAUNCH_DATA_DICTIONARY)
            return;

        auto integer(launch_data_dict_lookup(value, LAUNCH_JOBKEY_PID));
        if (integer == NULL || launch_data_get_type(integer) != LAUNCH_DATA_INTEGER)
            return;

        auto pid(launch_data_get_integer(integer));
        if (pid != parent)
            return;

        auto variables(launch_data_dict_lookup(value, LAUNCH_JOBKEY_ENVIRONMENTVARIABLES));
        if (variables != NULL && launch_data_get_type(variables) == LAUNCH_DATA_DICTIONARY) {
            auto dyld(false);

            launch_data_dict_iterate(variables, [&dyld](const char *name, launch_data_t value) {
                if (strncmp(name, "DYLD_", 5) == 0)
                    dyld = true;
            });

            if (dyld)
                return;
        }

        auto string(launch_data_dict_lookup(value, LAUNCH_JOBKEY_PROGRAM));
        if (string == NULL || launch_data_get_type(string) != LAUNCH_DATA_STRING) {
            auto array(launch_data_dict_lookup(value, LAUNCH_JOBKEY_PROGRAMARGUMENTS));
            if (array == NULL || launch_data_get_type(array) != LAUNCH_DATA_ARRAY)
                return;
            if (launch_data_array_get_count(array) == 0)
                return;

            string = launch_data_array_get_index(array, 0);
            if (string == NULL || launch_data_get_type(string) != LAUNCH_DATA_STRING)
                return;
        }

        auto program(launch_data_get_string(string));
        if (program == NULL)
            return;

        if (strcmp(program, "/Applications/Cydia.app/Cydia") == 0)
            cydia = true;
    });

    if (!cydia) {
        fprintf(stderr, "thou shalt not pass\n");
        return EX_NOPERM;
    }

    setuid(0);
    setgid(0);

    if (argc < 2 || argv[1][0] != '/')
        argv[0] = "/usr/bin/dpkg";
    else {
        --argc;
        ++argv;
    }

    execv(argv[0], argv);
    return EX_UNAVAILABLE;
}
