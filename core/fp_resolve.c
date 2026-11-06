#define _POSIX_C_SOURCE 200809L
#include "fp_resolve.h"
#include <errno.h>
#include <netdb.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>

#define FP_RESOLVER_WORKERS 4

typedef struct {
    pthread_mutex_t lock;
    pthread_cond_t condition;
    int done, abandoned, error;
    char host[254];
    uint32_t addresses[FP_ADDRESS_LIMIT];
    size_t count;
} fp_lookup;

static pthread_mutex_t resolver_lock = PTHREAD_MUTEX_INITIALIZER;
static unsigned resolver_workers;

static void lookup_free(fp_lookup *lookup)
{
    pthread_cond_destroy(&lookup->condition);
    pthread_mutex_destroy(&lookup->lock);
    free(lookup);
}

static void *lookup_thread(void *argument)
{
    fp_lookup *lookup = argument;
    struct addrinfo hints, *list = NULL, *item;
    int abandoned;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    lookup->error = getaddrinfo(lookup->host, NULL, &hints, &list);
    if (!lookup->error) {
        for (item = list; item && lookup->count < FP_ADDRESS_LIMIT; item = item->ai_next) {
            struct sockaddr_in *address = (struct sockaddr_in *)item->ai_addr;
            uint32_t value = ntohl(address->sin_addr.s_addr);
            size_t i;
            for (i = 0; i < lookup->count && lookup->addresses[i] != value; i++);
            if (i == lookup->count && value) lookup->addresses[lookup->count++] = value;
        }
        freeaddrinfo(list);
    }
    pthread_mutex_lock(&resolver_lock);
    resolver_workers--;
    pthread_mutex_unlock(&resolver_lock);
    pthread_mutex_lock(&lookup->lock);
    lookup->done = 1;
    abandoned = lookup->abandoned;
    if (!abandoned) pthread_cond_signal(&lookup->condition);
    pthread_mutex_unlock(&lookup->lock);
    if (abandoned) lookup_free(lookup);
    return NULL;
}

fp_session_status fp_resolve_ipv4(const char *host, int timeout_ms, uint32_t *addresses,
                                  size_t capacity, size_t *count)
{
    fp_lookup *lookup;
    pthread_t thread;
    pthread_attr_t attr;
    struct timeval now;
    struct timespec deadline;
    int result = 0;
    size_t length;
    fp_session_status status;
    if (count) *count = 0;
    if (!host || !addresses || !capacity || !count || timeout_ms <= 0) return FP_SESSION_ARGUMENT;
    length = strlen(host);
    if (!length || length > 253) return FP_SESSION_ARGUMENT;
    lookup = calloc(1, sizeof(*lookup));
    if (!lookup) return FP_SESSION_MEMORY;
    memcpy(lookup->host, host, length + 1);
    if (pthread_mutex_init(&lookup->lock, NULL) != 0) { free(lookup); return FP_SESSION_IO; }
    if (pthread_cond_init(&lookup->condition, NULL) != 0) { pthread_mutex_destroy(&lookup->lock); free(lookup); return FP_SESSION_IO; }
    pthread_mutex_lock(&resolver_lock);
    if (resolver_workers >= FP_RESOLVER_WORKERS) { pthread_mutex_unlock(&resolver_lock); lookup_free(lookup); return FP_SESSION_LIMIT; }
    resolver_workers++;
    pthread_mutex_unlock(&resolver_lock);
    if (pthread_attr_init(&attr) != 0) {
        pthread_mutex_lock(&resolver_lock); resolver_workers--; pthread_mutex_unlock(&resolver_lock);
        lookup_free(lookup); return FP_SESSION_IO;
    }
    result = pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    if (!result) result = pthread_create(&thread, &attr, lookup_thread, lookup);
    pthread_attr_destroy(&attr);
    if (result) {
        pthread_mutex_lock(&resolver_lock); resolver_workers--; pthread_mutex_unlock(&resolver_lock);
        lookup_free(lookup); return FP_SESSION_IO;
    }
    gettimeofday(&now, NULL);
    deadline.tv_sec = now.tv_sec + timeout_ms / 1000;
    deadline.tv_nsec = (long)now.tv_usec * 1000 + (long)(timeout_ms % 1000) * 1000000;
    if (deadline.tv_nsec >= 1000000000) { deadline.tv_sec++; deadline.tv_nsec -= 1000000000; }
    pthread_mutex_lock(&lookup->lock);
    while (!lookup->done && !result) result = pthread_cond_timedwait(&lookup->condition, &lookup->lock, &deadline);
    if (!lookup->done) {
        lookup->abandoned = 1;
        pthread_mutex_unlock(&lookup->lock);
        return result == ETIMEDOUT ? FP_SESSION_TIMEOUT : FP_SESSION_IO;
    }
    if (lookup->error || !lookup->count) status = FP_SESSION_IO;
    else if (lookup->count > capacity) status = FP_SESSION_LIMIT;
    else { memcpy(addresses, lookup->addresses, lookup->count * sizeof(*addresses)); *count = lookup->count; status = FP_SESSION_OK; }
    pthread_mutex_unlock(&lookup->lock);
    lookup_free(lookup);
    return status;
}
