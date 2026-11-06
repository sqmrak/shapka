#include "fp_tls.h"
#include <arpa/inet.h>
#include <assert.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define TOTAL 300

typedef struct {
    int fd;
    size_t chunks, first, got;
    unsigned char data[TOTAL + 64];
} reader;

static void *read_all(void *arg)
{
    reader *r = (reader *)arg;
    while (r->got < TOTAL + 20) {
        ssize_t n = recv(r->fd, r->data + r->got, sizeof(r->data) - r->got, 0);
        if (n <= 0) break;
        if (!r->chunks) r->first = (size_t)n;
        r->chunks++;
        r->got += (size_t)n;
    }
    return NULL;
}

static void run(int split, size_t *chunks, size_t *first)
{
    int listener = socket(AF_INET, SOCK_STREAM, 0), client = socket(AF_INET, SOCK_STREAM, 0), peer, one = 1;
    struct sockaddr_in address;
    socklen_t size = sizeof(address);
    unsigned char payload[TOTAL], tail[20];
    reader r;
    pthread_t thread;
    BIO *bio;
    size_t i;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    assert(listener >= 0 && client >= 0);
    assert(bind(listener, (struct sockaddr *)&address, sizeof(address)) == 0 && listen(listener, 1) == 0);
    assert(getsockname(listener, (struct sockaddr *)&address, &size) == 0);
    assert(connect(client, (struct sockaddr *)&address, sizeof(address)) == 0);
    peer = accept(listener, NULL, NULL);
    assert(peer >= 0);
    setsockopt(client, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
    memset(&r, 0, sizeof(r));
    r.fd = peer;
    assert(pthread_create(&thread, NULL, read_all, &r) == 0);
    for (i = 0; i < TOTAL; i++) payload[i] = (unsigned char)i;
    for (i = 0; i < sizeof(tail); i++) tail[i] = (unsigned char)(0xa0 + i);
    bio = fp_tls_bio(client, split);
    assert(bio);
    assert(BIO_write(bio, payload, TOTAL) == TOTAL);
    /* only the first write is cut up */
    assert(BIO_write(bio, tail, (int)sizeof(tail)) == (int)sizeof(tail));
    BIO_free(bio);
    /* the bio does not own the descriptor */
    assert(write(client, "", 0) == 0);
    pthread_join(thread, NULL);
    assert(r.got == TOTAL + sizeof(tail));
    assert(memcmp(r.data, payload, TOTAL) == 0 && memcmp(r.data + TOTAL, tail, sizeof(tail)) == 0);
    *chunks = r.chunks;
    *first = r.first;
    close(client);
    close(peer);
    close(listener);
}

int main(void)
{
    size_t chunks, first;
    run(0, &chunks, &first);
    assert(first > FP_TLS_SPLIT_PIECE || chunks <= 2);
    run(1, &chunks, &first);
    /* a first piece of six bytes, then the rest in pieces, the second write whole */
    assert(first <= FP_TLS_SPLIT_PIECE);
    assert(chunks >= 20);
    assert(fp_tls_bio(-1, 1) == NULL);
    puts("tls split tests passed");
    return 0;
}
