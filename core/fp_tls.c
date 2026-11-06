#include "fp_tls.h"

#include <errno.h>
#include <poll.h>
#include <stdlib.h>
#include <sys/socket.h>

#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

typedef struct {
    int fd;
    int split_pending;
} fd_state;

static BIO_METHOD *fd_method;

static int would_block(void)
{
    return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR;
}

static int fd_write_plain(BIO *bio, fd_state *state, const char *data, int length)
{
    ssize_t n;
    BIO_clear_retry_flags(bio);
    n = send(state->fd, data, (size_t)length, MSG_NOSIGNAL);
    if (n >= 0) return (int)n;
    if (would_block()) BIO_set_retry_write(bio);
    return -1;
}

static int fd_write(BIO *bio, const char *data, int length)
{
    fd_state *state = (fd_state *)BIO_get_data(bio);
    int sent = 0, pieces = 0;
    if (!state || length <= 0) return 0;
    if (!state->split_pending || length <= (int)FP_TLS_SPLIT_PIECE) {
        int written = fd_write_plain(bio, state, data, length);
        if (written > 0) state->split_pending = 0;
        return written;
    }
    while (sent < length) {
        int piece = sent + (int)FP_TLS_SPLIT_PIECE < length && pieces < (int)FP_TLS_SPLIT_PIECES ? (int)FP_TLS_SPLIT_PIECE : length - sent;
        int written = fd_write_plain(bio, state, data + sent, piece);
        if (written <= 0) {
            /* what already left counts as written; openssl offers the rest again when the socket drains */
            if (sent > 0) { BIO_clear_retry_flags(bio); state->split_pending = 0; return sent; }
            return written;
        }
        sent += written;
        pieces++;
        /* the gap is what puts each piece in a segment of its own, nothing waits on it */
        if (sent < length) (void)poll(NULL, 0, FP_TLS_SPLIT_GAP_MS);
    }
    state->split_pending = 0;
    return sent;
}

static int fd_read(BIO *bio, char *data, int length)
{
    fd_state *state = (fd_state *)BIO_get_data(bio);
    ssize_t n;
    if (!state || !data || length <= 0) return 0;
    BIO_clear_retry_flags(bio);
    n = recv(state->fd, data, (size_t)length, 0);
    if (n > 0) return (int)n;
    if (n == 0) return 0;
    if (would_block()) BIO_set_retry_read(bio);
    return -1;
}

static long fd_ctrl(BIO *bio, int command, long number, void *pointer)
{
    (void)bio; (void)number; (void)pointer;
    /* openssl asks to flush after a handshake flight; a socket has nothing buffered here */
    return command == BIO_CTRL_FLUSH ? 1 : 0;
}

static int fd_create(BIO *bio)
{
    BIO_set_init(bio, 1);
    return 1;
}

static int fd_destroy(BIO *bio)
{
    free(BIO_get_data(bio));
    BIO_set_data(bio, NULL);
    return 1;
}

BIO *fp_tls_bio(int fd, int split_hello)
{
    BIO *bio;
    fd_state *state;
    if (fd < 0) return NULL;
    if (!fd_method) {
        fd_method = BIO_meth_new(BIO_get_new_index() | BIO_TYPE_SOURCE_SINK | BIO_TYPE_DESCRIPTOR, "fp socket");
        if (!fd_method) return NULL;
        if (!BIO_meth_set_write(fd_method, fd_write) || !BIO_meth_set_read(fd_method, fd_read) || !BIO_meth_set_ctrl(fd_method, fd_ctrl) ||
            !BIO_meth_set_create(fd_method, fd_create) || !BIO_meth_set_destroy(fd_method, fd_destroy)) {
            BIO_meth_free(fd_method);
            fd_method = NULL;
            return NULL;
        }
    }
    bio = BIO_new(fd_method);
    state = (fd_state *)calloc(1, sizeof(*state));
    if (!bio || !state) { free(state); BIO_free(bio); return NULL; }
    state->fd = fd;
    state->split_pending = split_hello != 0;
    BIO_set_data(bio, state);
    return bio;
}
