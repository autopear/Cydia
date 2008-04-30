#include <objc/objc.h>

#define _trace() fprintf(stderr, "_trace()@%s:%u[%s]\n", __FILE__, __LINE__, __FUNCTION__)

#define _assert(test) do \
    if (!(test)) { \
        fprintf(stderr, "_assert(%d:%s)@%s:%u[%s]\n", errno, #test, __FILE__, __LINE__, __FUNCTION__); \
        exit(-1); \
    } \
while (false)

#define _not(type) ((type) ~ (type) 0)

#define _transient
