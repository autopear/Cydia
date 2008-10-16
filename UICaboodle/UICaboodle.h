#define __STDC_LIMIT_MACROS
#include <stdint.h>

#include <objc/objc.h>

#include <sys/time.h>
#include <time.h>

#define _forever \
    for (;;)

extern struct timeval _ltv;
extern bool _itv;

#define _trace() do { \
    struct timeval _ctv; \
    gettimeofday(&_ctv, NULL); \
    if (!_itv) { \
        _itv = true; \
        _ltv = _ctv; \
    } \
    fprintf(stderr, "%lu.%.6u[%f]:_trace()@%s:%u[%s]\n", \
        _ctv.tv_sec, _ctv.tv_usec, \
        (_ctv.tv_sec - _ltv.tv_sec) + (_ctv.tv_usec - _ltv.tv_usec) / 1000000.0, \
        __FILE__, __LINE__, __FUNCTION__\
    ); \
    _ltv = _ctv; \
} while (false)

#define _assert(test) do \
    if (!(test)) { \
        fprintf(stderr, "_assert(%d:%s)@%s:%u[%s]\n", errno, #test, __FILE__, __LINE__, __FUNCTION__); \
        exit(-1); \
    } \
while (false)

#define _not(type) ((type) ~ (type) 0)

#define _transient

#define _label__(x) _label ## x
#define _label_(y) _label__(y)
#define _label _label_(__LINE__)

#define _packed \
    __attribute__((packed))
