#ifndef FP_HTTP_H
#define FP_HTTP_H

#include <stddef.h>
#include <stdint.h>

typedef enum { FP_HTTP_OK, FP_HTTP_ARGUMENT, FP_HTTP_INVALID, FP_HTTP_INCOMPLETE, FP_HTTP_LIMIT } fp_http_status;

/* bounded HTTP/1.x response framing for the news feed */

#define FP_HTTP_MAX_HEADERS 16384u
#define FP_HTTP_LOCATION_MAX 2048u

/* the status line and the headers a caller acts on, before any body byte is read */
typedef struct fp_http_head {
    int status;                             /* 200 to 599 */
    int chunked;
    int has_length;
    size_t content_length;
    size_t body_start;                      /* offset of the first body byte in the data */
    char location[FP_HTTP_LOCATION_MAX];   /* the Location value, or empty */
} fp_http_head;

typedef struct fp_http_response {
    int status;             /* 100 to 599 */
    size_t body_len;
} fp_http_response;

/* FP_HTTP_INCOMPLETE until the blank line that ends the headers has arrived */
fp_http_status fp_http_parse_head(const uint8_t *data, size_t len, int eof, fp_http_head *out);

/* data is everything received so far; eof says the connection is closed */
fp_http_status fp_http_parse_response(const uint8_t *data, size_t len, int eof, fp_http_response *out, uint8_t *body, size_t cap);

/* the start of a body whose connection was cut on purpose: every body byte that arrived is decoded, up to cap, and a missing rest is not an error; the head
   must be complete and the framing of what arrived must be valid */
fp_http_status fp_http_parse_prefix(const uint8_t *data, size_t len, fp_http_response *out, uint8_t *body, size_t cap);

#endif
