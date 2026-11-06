#ifndef FP_AUTH_H
#define FP_AUTH_H

#include "fp_session.h"

#define FP_AUTH_KEY_LIMIT 1024u
#define FP_AUTH_TEXT_LIMIT 4096u

typedef struct {
    int32_t member_id;
    int hidden;
    uint8_t key[FP_AUTH_KEY_LIMIT];
    size_t key_length;
} fp_auth_account;

void fp_auth_clear(fp_auth_account *account);
/* the caller receives server status and any captcha response in reply */
fp_session_status fp_auth_login(fp_session *session,
                                const uint8_t *login, size_t login_length,
                                const uint8_t *password, size_t password_length,
                                int hidden, int32_t captcha, int timeout_ms,
                                fp_auth_account *account, fp_reply *reply);
fp_session_status fp_auth_resume(fp_session *session, const fp_auth_account *account,
                                 int hidden, int timeout_ms, fp_reply *reply);

#endif
