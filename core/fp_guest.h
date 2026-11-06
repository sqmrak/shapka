#ifndef FP_GUEST_H
#define FP_GUEST_H

#include <stddef.h>
#include <stdint.h>

/* the cleartext guest route carries only bounded public read requests */
int fp_guest_request_allowed(const char *operation, const uint8_t *document, size_t length);

#endif
