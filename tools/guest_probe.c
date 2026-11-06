#define _POSIX_C_SOURCE 200809L
#include "fp_session.h"
#include <netdb.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

int main(void)
{
    struct addrinfo hints, *addresses, *it;
    int fd = -1;
    fp_session session;
    fp_reply reply;
    fp_session_status status;
    const char *hello = "[\"1.9.43\",\"\",\"\",1,0]";
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET; hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo("app.4pda.to", "993", &hints, &addresses)) return 1;
    for (it = addresses; it; it = it->ai_next) {
        fd = socket(it->ai_family, it->ai_socktype, it->ai_protocol);
        if (fd < 0) continue;
        if (!connect(fd, it->ai_addr, it->ai_addrlen)) break;
        close(fd); fd = -1;
    }
    freeaddrinfo(addresses);
    if (fd < 0) { fprintf(stderr, "connect failed\n"); return 1; }
    if (fp_session_init(&session, fd) != FP_SESSION_OK) { close(fd); return 1; }
    status = fp_session_request(&session, "ah", (const uint8_t *)hello, strlen(hello), 10000, &reply);
    if (status != FP_SESSION_OK) { fprintf(stderr, "hello: session error %d\n", status); fp_session_close(&session); return 1; }
    if (reply.status != 0) { fprintf(stderr, "hello: server status %d\n", reply.status); fp_reply_clear(&reply); fp_session_close(&session); return 1; }
    fp_reply_clear(&reply);
    status = fp_session_request(&session, "fi", (const uint8_t *)"[]", 2, 10000, &reply);
    if (status != FP_SESSION_OK) { fprintf(stderr, "forums: session error %d\n", status); fp_session_close(&session); return 1; }
    printf("forums: server status %d, %zu bytes\n", reply.status, reply.length);
    status = reply.status == 0 ? FP_SESSION_OK : FP_SESSION_PROTOCOL;
    fp_reply_clear(&reply);
    if (status != FP_SESSION_OK) { fp_session_close(&session); return 1; }
    {
        const char *operations[] = {"fs", "fr"};
        const char *arguments[] = {"[139,0,30]", "[272100,0,20,0]"};
        unsigned i;
        for (i = 0; i < 2; i++) {
            status = fp_session_request(&session, operations[i], (const uint8_t *)arguments[i], strlen(arguments[i]), 10000, &reply);
            if (status != FP_SESSION_OK) { fprintf(stderr, "%s: session error %d\n", operations[i], status); fp_session_close(&session); return 1; }
            printf("%s: server status %d, %zu bytes\n", operations[i], reply.status, reply.length);
            status = reply.status == 0 ? FP_SESSION_OK : FP_SESSION_PROTOCOL;
            fp_reply_clear(&reply);
            if (status != FP_SESSION_OK) { fp_session_close(&session); return 1; }
        }
    }
    fp_session_close(&session);
    return 0;
}
