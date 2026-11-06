#include "fp_guest.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static int allow(const char *operation, const char *arguments)
{
    return fp_guest_request_allowed(operation, (const uint8_t *)arguments, strlen(arguments));
}

int main(void)
{
    assert(allow("fi", "[]"));
    assert(allow("sl", "[0,30,-1,0]"));
    assert(!allow("sl", "[0,30,-1,1]"));
    assert(allow("sa", "[462974]"));
    assert(!allow("sa", "[0]"));
    assert(!allow("sa", "[1,2]"));
    assert(allow("fn", "[238]"));
    assert(!allow("fn", "[0]"));
    assert(!allow("fn", "[238,1]"));
    assert(!allow("fn", "[\"238\"]"));
    assert(allow("fs", "[139,0,30]"));
    assert(allow("fr", "[123,20,20,0]"));
    assert(!allow("fi", "[\"private\"]"));
    assert(!allow("fs", "[139,0,\"password\"]"));
    assert(!allow("fs", "[139,0,201]"));
    assert(!allow("fr", "[123,0,20,1]"));
    assert(!allow("fr", "[123,-1,20,0]"));
    assert(!allow("ml", "[]"));
    puts("guest request tests passed");
    return 0;
}
