#include <objc/objc.h>

#include <sys/time.h>
#include <time.h>

#define _forever \
    for (;;)

#define _trace() do { \
    struct timeval _tv; \
    gettimeofday(&_tv, NULL); \
    fprintf(stderr, "%lu.%.6u:_trace()@%s:%u[%s]\n", _tv.tv_sec, _tv.tv_usec, __FILE__, __LINE__, __FUNCTION__); \
} while (false)

#define _assert(test) do \
    if (!(test)) { \
        fprintf(stderr, "_assert(%d:%s)@%s:%u[%s]\n", errno, #test, __FILE__, __LINE__, __FUNCTION__); \
        exit(-1); \
    } \
while (false)

#define _not(type) ((type) ~ (type) 0)

#define _transient
