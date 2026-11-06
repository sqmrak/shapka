#include "fp_session.h"
#include "fp_client.h"
#include "fp_auth.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
    fp_session session;
    fp_reply reply;
    fp_session_status status;
    int expected;
    fp_auth_account account;
    if (argc != 6 && argc != 7) return 2;
    expected = atoi(argv[4]);
    if (strcmp(argv[2], "localhost") == 0) {
        status = fp_client_connect(&session, argv[2], (uint16_t)atoi(argv[1]), argv[3], argc == 7 && atoi(argv[6]), 3000);
    } else {
        status = fp_session_connect_ipv4(&session, 0x7f000001u, (uint16_t)atoi(argv[1]), 2000);
        if (status != FP_SESSION_OK) return 3;
        status = fp_session_start_tls(&session, argv[2], argv[3], 3000);
    }
    if (expected) {
        if (status != FP_SESSION_OK) { fprintf(stderr, "tls status %d\n", status); return 4; }
        if (atoi(argv[5])) {
            status = fp_auth_login(&session, (const uint8_t *)"login", 5,
                                   (const uint8_t *)"secret", 6, 1, 123, 2000, &account, &reply);
            if (status == FP_SESSION_OK && (account.member_id != 123 || account.key_length != 7 || memcmp(account.key, "testkey", 7))) return 8;
            fp_reply_clear(&reply);
            status = fp_auth_resume(&session, &account, account.hidden, 2000, &reply);
            fp_auth_clear(&account);
        } else status = fp_session_request(&session, "fi", (const uint8_t *)"[]", 2, 2000, &reply);
        if (status != FP_SESSION_OK || reply.status != 0) return 5;
        fp_reply_clear(&reply);
        fp_session_close(&session);
        return 0;
    }
    if (status == FP_SESSION_OK) { fp_session_close(&session); return 6; }
    if (session.fd != -1) return 7;
    return 0;
}
