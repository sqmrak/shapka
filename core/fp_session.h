#ifndef FP_SESSION_H
#define FP_SESSION_H

#include <stddef.h>
#include <stdint.h>

/* the session owns its connected descriptor and runs on one thread */
typedef enum {
    FP_SESSION_OK = 0,
    FP_SESSION_ARGUMENT,
    FP_SESSION_TIMEOUT,
    FP_SESSION_EOF,
    FP_SESSION_IO,
    FP_SESSION_PROTOCOL,
    FP_SESSION_LIMIT,
    FP_SESSION_MEMORY,
    FP_SESSION_CLOSED,
    FP_SESSION_SECURITY
} fp_session_status;

typedef void (*fp_session_event_fn)(void *context, const uint8_t *document, size_t length);

typedef struct {
    int fd;
    uint32_t next_id;
    fp_session_event_fn event;
    void *event_context;
    void *tls_context;
    void *tls;
    /* the handshake hello goes out in small pieces, for a network that reads the server name of one segment */
    int tls_split;
} fp_session;

typedef struct {
    uint8_t *data;
    size_t length;
    int32_t status;
} fp_reply;

/* opens a direct ipv4 connection; address is in host byte order */
fp_session_status fp_session_connect_ipv4(fp_session *session, uint32_t address, uint16_t port, int timeout_ms);

/* on success takes ownership of a connected socket, on failure ownership stays with the caller */
fp_session_status fp_session_init(fp_session *session, int connected_fd);
/* negotiates tls with the supplied roots and verifies the hostname */
fp_session_status fp_session_tls_connect(fp_session *session, const char *hostname, const char *roots_path, int timeout_ms);

/* upgrades a connected socket with verified tls and the app websocket handshake */
fp_session_status fp_session_start_tls(fp_session *session, const char *hostname,
                                       const char *roots_path, int timeout_ms);
void fp_session_close(fp_session *session);
void fp_session_set_event_handler(fp_session *session, fp_session_event_fn event, void *context);
void fp_reply_clear(fp_reply *reply);

/* processes one server event or control frame; timeout closes the connection */
fp_session_status fp_session_wait_event(fp_session *session, int timeout_ms);
int fp_session_has_buffered(const fp_session *session);
/* a read source can fire after a request has consumed the available bytes */
int fp_session_read_ready(const fp_session *session);

/* arguments is a windows-1251 document array, including its brackets; clear each reply before reuse */
/* the event callback runs on the calling thread and must not reenter the session */
fp_session_status fp_session_request(fp_session *session, const char operation[2],
                                     const uint8_t *arguments, size_t arguments_length,
                                     int timeout_ms, fp_reply *reply);

#endif
