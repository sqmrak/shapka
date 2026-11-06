#ifndef FP_CLIENT_H
#define FP_CLIENT_H

#include "fp_session.h"

/* use a new or closed session; never falls back from verified tls to cleartext */
/* split_hello cuts the first tls packet into small pieces, for a network that drops a hello whose server name sits in one segment; the certificate and the name
   are checked the same either way */
fp_session_status fp_client_connect(fp_session *session, const char *host, uint16_t port,
                                    const char *roots_path, int split_hello, int timeout_ms);

/* the original cleartext guest endpoint, for public read requests only */
fp_session_status fp_client_connect_guest(fp_session *session, const char *host, uint16_t port, int timeout_ms);

#endif
