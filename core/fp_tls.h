#ifndef FP_TLS_H
#define FP_TLS_H

#include <openssl/bio.h>

/* a socket bio for the tls connection; with split_hello set, the first write (the ClientHello) leaves in pieces of FP_TLS_SPLIT_PIECE bytes with a short gap,
   so a network that reads the server name out of one segment never sees it whole; everything after the first write is a plain socket write; the bio does
   not own the descriptor; NULL when the bio cannot be built */
#define FP_TLS_SPLIT_PIECE 6u
#define FP_TLS_SPLIT_PIECES 23u
#define FP_TLS_SPLIT_GAP_MS 12

BIO *fp_tls_bio(int fd, int split_hello);

#endif
