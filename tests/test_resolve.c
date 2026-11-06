#include "fp_resolve.h"
#include <assert.h>
#include <stdio.h>
int main(void)
{
    uint32_t addresses[FP_ADDRESS_LIMIT];
    size_t count = 99;
    assert(fp_resolve_ipv4("localhost", 2000, addresses, FP_ADDRESS_LIMIT, &count) == FP_SESSION_OK);
    assert(count > 0 && addresses[0] != 0);
    assert(fp_resolve_ipv4("", 2000, addresses, FP_ADDRESS_LIMIT, &count) == FP_SESSION_ARGUMENT && count == 0);
    assert(fp_resolve_ipv4("localhost", 0, addresses, FP_ADDRESS_LIMIT, &count) == FP_SESSION_ARGUMENT);
    puts("resolver tests passed");
    return 0;
}
