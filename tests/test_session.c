#define _POSIX_C_SOURCE 200809L
#include "fp_session.h"
#include "fp_auth.h"
#include "fp_client.h"
#include "fp_frame.h"
#include <assert.h>
#include <signal.h>
#include <netinet/in.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

static void read_all(int fd, void *buffer, size_t count)
{
    size_t pos = 0;
    while (pos < count) {
        ssize_t n = read(fd, (char *)buffer + pos, count - pos);
        assert(n > 0);
        pos += (size_t)n;
    }
}

static void on_event(void *context, const uint8_t *document, size_t length)
{
    int *seen = context;
    assert(length == 9 && memcmp(document, "[30309,0]", 9) == 0);
    (*seen)++;
}

static void quiet_server(int fd)
{
    uint8_t wire[128];
    const uint8_t answer[] = {0x82, 8, '[', '1', ',', '0', ',', '4', '2', ']'};
    read_all(fd, wire, 2);
    assert(wire[1] < 126);
    read_all(fd, wire + 2, wire[1]);
    assert(write(fd, answer, sizeof(answer)) == sizeof(answer));
    /* keep the peer open until the client has checked the stale readiness */
    assert(read(fd, wire, 1) == 0);
    close(fd);
}

static void server(int fd)
{
    uint8_t wire[1024], decoded[1024];
    size_t count, output;
    fp_frame frame;
    const uint8_t ping[] = {0x89, 1, 'x'};
    const uint8_t event[] = {0x82, 9, '[', '3', '0', '3', '0', '9', ',', '0', ']'};
    const uint8_t answer[] = {0x82, 8, '[', '1', ',', '0', ',', '4', '2', ']'};
    read_all(fd, wire, 2);
    assert(wire[1] < 126);
    count = wire[1] + 2;
    read_all(fd, wire + 2, count - 2);
    assert(fp_frame_read(wire, count, &frame) == FP_FRAME_OK);
    assert(fp_frame_inflate(&frame, decoded, sizeof(decoded), &output) == FP_FRAME_OK);
    assert(output == strlen("[1,\"fi\"]") && !memcmp(decoded, "[1,\"fi\"]", output));
    assert(write(fd, ping, sizeof(ping)) == sizeof(ping));
    read_all(fd, wire, sizeof(ping));
    assert(wire[0] == 0x8a && wire[1] == 1 && wire[2] == 'x');
    assert(write(fd, event, sizeof(event)) == sizeof(event));
    for (count = 0; count < sizeof(answer); count++) assert(write(fd, answer + count, 1) == 1);
    close(fd);
}

int main(void)
{
    int pair[2], status, seen = 0;
    pid_t pid;
    fp_session session;
    fp_reply reply;
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
    pid = fork();
    assert(pid >= 0);
    if (!pid) { close(pair[0]); server(pair[1]); _exit(0); }
    close(pair[1]);
    assert(fp_session_init(&session, pair[0]) == FP_SESSION_OK);
    fp_session_set_event_handler(&session, on_event, &seen);
    assert(fp_session_request(&session, "fi", (const uint8_t *)"[]", 2, 3000, &reply) == FP_SESSION_OK);
    assert(seen == 1);
    assert(reply.status == 0 && reply.length == 8 && !memcmp(reply.data, "[1,0,42]", 8));
    fp_reply_clear(&reply);
    fp_session_close(&session);
    assert(waitpid(pid, &status, 0) == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0);

    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
    pid = fork();
    assert(pid >= 0);
    if (!pid) { close(pair[0]); quiet_server(pair[1]); _exit(0); }
    close(pair[1]);
    assert(fp_session_init(&session, pair[0]) == FP_SESSION_OK);
    assert(fp_session_request(&session, "fi", (const uint8_t *)"[]", 2, 3000, &reply) == FP_SESSION_OK);
    assert(!fp_session_read_ready(&session));
    assert(session.fd >= 0);
    fp_reply_clear(&reply);
    fp_session_close(&session);
    assert(waitpid(pid, &status, 0) == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0);

    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
    assert(fp_session_init(&session, pair[0]) == FP_SESSION_OK);
    assert(fp_session_request(&session, "fi", (const uint8_t *)"[1,]", 4, 100, &reply) == FP_SESSION_ARGUMENT);
    assert(fp_session_request(&session, "fi", (const uint8_t *)"[]", 2, 50, &reply) == FP_SESSION_TIMEOUT);
    assert(session.fd == -1);
    assert(fp_session_request(&session, "fi", (const uint8_t *)"[]", 2, 50, &reply) == FP_SESSION_CLOSED);
    close(pair[1]);
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
    assert(fp_session_init(&session, pair[0]) == FP_SESSION_OK);
    close(pair[1]);
    { fp_session_status closed = fp_session_request(&session, "fi", (const uint8_t *)"[]", 2, 100, &reply);
      assert(closed == FP_SESSION_IO || closed == FP_SESSION_EOF); }
    assert(session.fd == -1);
    {
        int listener = socket(AF_INET, SOCK_STREAM, 0);
        struct sockaddr_in address;
        socklen_t address_length = sizeof(address);
        assert(listener >= 0);
        memset(&address, 0, sizeof(address));
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        assert(bind(listener, (struct sockaddr *)&address, sizeof(address)) == 0);
        assert(listen(listener, 1) == 0);
        assert(getsockname(listener, (struct sockaddr *)&address, &address_length) == 0);
        pid = fork();
        assert(pid >= 0);
        if (!pid) { int peer = accept(listener, NULL, NULL); assert(peer >= 0); server(peer); close(listener); _exit(0); }
        assert(fp_client_connect_guest(&session, "127.0.0.1", ntohs(address.sin_port), 1000) == FP_SESSION_OK);
        fp_session_set_event_handler(&session, on_event, &seen);
        assert(fp_session_request(&session, "fi", (const uint8_t *)"[]", 2, 1000, &reply) == FP_SESSION_OK);
        fp_reply_clear(&reply);
        fp_session_close(&session);
        close(listener);
        assert(waitpid(pid, &status, 0) == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    }
    {
        const uint8_t event[] = {0x82, 9, '[', '3', '0', '3', '0', '9', ',', '0', ']'};
        assert(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
        assert(fp_session_init(&session, pair[0]) == FP_SESSION_OK);
        fp_session_set_event_handler(&session, on_event, &seen);
        assert(!fp_session_read_ready(&session));
        { const uint8_t ping[] = {0x89, 1, 'z'}; uint8_t pong[3];
          assert(write(pair[1], ping, sizeof(ping)) == sizeof(ping));
          assert(fp_session_read_ready(&session));
          assert(fp_session_wait_event(&session, 1000) == FP_SESSION_OK);
          assert(!fp_session_read_ready(&session));
          read_all(pair[1], pong, sizeof(pong));
          assert(pong[0] == 0x8a && pong[1] == 1 && pong[2] == 'z'); }
        assert(write(pair[1], event, sizeof(event)) == sizeof(event));
        assert(fp_session_wait_event(&session, 1000) == FP_SESSION_OK);
        assert(seen == 3);
        assert(fp_session_wait_event(&session, 50) == FP_SESSION_TIMEOUT);
        assert(session.fd == -1);
        close(pair[1]);
    }
    {
        fp_auth_account account;
        assert(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
        assert(fp_session_init(&session, pair[0]) == FP_SESSION_OK);
        assert(fp_auth_login(&session, (const uint8_t *)"user", 4, (const uint8_t *)"pass", 4, 0, 0, 1000, &account, &reply) == FP_SESSION_SECURITY);
        assert(account.member_id == 0 && account.key_length == 0);
        fp_session_close(&session);
        close(pair[1]);
    }
    {
        assert(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
        assert(fp_session_init(&session, pair[0]) == FP_SESSION_OK);
        close(pair[1]);
        assert(fp_session_read_ready(&session));
        fp_session_close(&session);
    }
    puts("session tests passed");
    return 0;
}
