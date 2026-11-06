#include "fp_client.h"
#include "fp_resolve.h"
#include <sys/time.h>
#include <string.h>

static uint64_t current_ms(void)
{
    struct timeval now;
    if (gettimeofday(&now, NULL) != 0) return 0;
    return (uint64_t)now.tv_sec * 1000u + (uint64_t)now.tv_usec / 1000u;
}

fp_session_status fp_client_connect(fp_session *session, const char *host, uint16_t port,
                                    const char *roots_path, int split_hello, int timeout_ms)
{
    uint32_t addresses[FP_ADDRESS_LIMIT];
    size_t count, i;
    uint64_t start, now, elapsed;
    int remaining;
    fp_session_status status;
    if (!session || !host || !port || !roots_path || timeout_ms <= 0) return FP_SESSION_ARGUMENT;
    memset(session, 0, sizeof(*session));
    session->fd = -1;
    start = current_ms();
    if (!start) return FP_SESSION_IO;
    status = fp_resolve_ipv4(host, timeout_ms, addresses, FP_ADDRESS_LIMIT, &count);
    if (status != FP_SESSION_OK) return status;
    for (i = 0; i < count; i++) {
        now = current_ms();
        if (!now || now < start) return FP_SESSION_IO;
        elapsed = now - start;
        if (elapsed >= (uint64_t)timeout_ms) return FP_SESSION_TIMEOUT;
        remaining = timeout_ms - (int)elapsed;
        status = fp_session_connect_ipv4(session, addresses[i], port, remaining);
        if (status != FP_SESSION_OK) continue;
        now = current_ms();
        if (!now || now < start) { fp_session_close(session); return FP_SESSION_IO; }
        elapsed = now - start;
        if (elapsed >= (uint64_t)timeout_ms) { fp_session_close(session); return FP_SESSION_TIMEOUT; }
        session->tls_split = split_hello;
        status = fp_session_start_tls(session, host, roots_path, timeout_ms - (int)elapsed);
        if (status == FP_SESSION_OK || status == FP_SESSION_SECURITY || status == FP_SESSION_PROTOCOL) return status;
    }
    return status;
}

fp_session_status fp_client_connect_guest(fp_session *session, const char *host, uint16_t port, int timeout_ms)
{
    uint32_t addresses[FP_ADDRESS_LIMIT];
    size_t count, i;
    uint64_t start, now, elapsed;
    fp_session_status status;
    if (!session || !host || !port || timeout_ms <= 0) return FP_SESSION_ARGUMENT;
    memset(session, 0, sizeof(*session));
    session->fd = -1;
    start = current_ms();
    if (!start) return FP_SESSION_IO;
    status = fp_resolve_ipv4(host, timeout_ms, addresses, FP_ADDRESS_LIMIT, &count);
    if (status != FP_SESSION_OK) return status;
    for (i = 0; i < count; i++) {
        now = current_ms();
        if (!now || now < start) return FP_SESSION_IO;
        elapsed = now - start;
        if (elapsed >= (uint64_t)timeout_ms) return FP_SESSION_TIMEOUT;
        status = fp_session_connect_ipv4(session, addresses[i], port, timeout_ms - (int)elapsed);
        if (status == FP_SESSION_OK) return status;
    }
    return status;
}
