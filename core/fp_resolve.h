#ifndef FP_RESOLVE_H
#define FP_RESOLVE_H

#include "fp_session.h"

#define FP_ADDRESS_LIMIT 8u

/* returns host-order ipv4 addresses; timed out lookups finish on a detached worker */
fp_session_status fp_resolve_ipv4(const char *host, int timeout_ms, uint32_t *addresses,
                                  size_t capacity, size_t *count);

#endif
