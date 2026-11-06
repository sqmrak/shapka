#include "fp_auth.h"
#include "fp_document.h"
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void wipe(void *memory, size_t length)
{
    volatile uint8_t *p = memory;
    while (length--) *p++ = 0;
}

void fp_auth_clear(fp_auth_account *account)
{
    if (account) wipe(account, sizeof(*account));
}

static int number(const uint8_t *data, const fp_document_token *token, int32_t *out)
{
    size_t i = token->offset, end = i + token->length;
    uint32_t value = 0;
    if (token->type != FP_DOCUMENT_INTEGER || i >= end) return 0;
    while (i < end) {
        unsigned digit = data[i++] - '0';
        if (digit > 9 || value > (INT32_MAX - digit) / 10) return 0;
        value = value * 10 + digit;
    }
    if (!value) return 0;
    *out = (int32_t)value;
    return 1;
}

static int parse_account(const fp_reply *reply, fp_auth_account *account)
{
    fp_document_token tokens[32];
    size_t count, pos, end, length = 0;
    if (fp_document_parse(reply->data, reply->length, tokens, 32, &count) != FP_DOCUMENT_OK ||
        count < 5 || tokens[0].children < 4 || tokens[3].parent != 0 || tokens[4].parent != 0 ||
        !number(reply->data, &tokens[3], &account->member_id) || tokens[4].type != FP_DOCUMENT_STRING) return 0;
    pos = tokens[4].offset + 1;
    end = tokens[4].offset + tokens[4].length - 1;
    while (pos < end) {
        uint8_t c = reply->data[pos++];
        if (c == '\\') {
            if (pos >= end) return 0;
            c = reply->data[pos++];
            if (c != '"' && c != '\\') return 0;
        }
        if (c < 0x21 || c > 0x7e || length == FP_AUTH_KEY_LIMIT) return 0;
        account->key[length++] = c;
    }
    account->key_length = length;
    return length > 0;
}

fp_session_status fp_auth_login(fp_session *session,
                                const uint8_t *login, size_t login_length,
                                const uint8_t *password, size_t password_length,
                                int hidden, int32_t captcha, int timeout_ms,
                                fp_auth_account *account, fp_reply *reply)
{
    uint8_t *args;
    size_t capacity, at = 0, length;
    int n;
    fp_session_status status;
    if (account) fp_auth_clear(account);
    if (reply) memset(reply, 0, sizeof(*reply));
    if (!session || !account || !reply || !login || !password || !login_length || !password_length ||
        login_length > FP_AUTH_TEXT_LIMIT || password_length > FP_AUTH_TEXT_LIMIT || captcha < 0) return FP_SESSION_ARGUMENT;
    if (!session->tls) return FP_SESSION_SECURITY;
    capacity = (login_length + password_length) * 6 + 64;
    args = malloc(capacity);
    if (!args) return FP_SESSION_MEMORY;
    args[at++] = '[';
    if (fp_document_quote(login, login_length, args + at, capacity - at, &length) != FP_DOCUMENT_OK) { status = FP_SESSION_LIMIT; goto done; }
    at += length; args[at++] = ',';
    if (fp_document_quote(password, password_length, args + at, capacity - at, &length) != FP_DOCUMENT_OK) { status = FP_SESSION_LIMIT; goto done; }
    at += length;
    n = snprintf((char *)args + at, capacity - at, ",%d,%d]", hidden ? 1 : 0, (int)captcha);
    if (n < 0 || (size_t)n >= capacity - at) { status = FP_SESSION_LIMIT; goto done; }
    at += (size_t)n;
    status = fp_session_request(session, "ml", args, at, timeout_ms, reply);
    if (status == FP_SESSION_OK && reply->status == 0 && !parse_account(reply, account)) {
        fp_auth_clear(account); status = FP_SESSION_PROTOCOL; fp_session_close(session);
    } else if (status == FP_SESSION_OK && reply->status == 0) {
        account->hidden = hidden ? 1 : 0;
    }
done:
    wipe(args, capacity); free(args);
    return status;
}

fp_session_status fp_auth_resume(fp_session *session, const fp_auth_account *account,
                                 int hidden, int timeout_ms, fp_reply *reply)
{
    uint8_t args[FP_AUTH_KEY_LIMIT * 2 + 64];
    size_t at, length;
    int n;
    fp_session_status status;
    if (reply) memset(reply, 0, sizeof(*reply));
    if (!session || !account || !reply || account->member_id <= 0 || !account->key_length || account->key_length > FP_AUTH_KEY_LIMIT) return FP_SESSION_ARGUMENT;
    if (!session->tls) return FP_SESSION_SECURITY;
    n = snprintf((char *)args, sizeof(args), "[%d,", (int)account->member_id);
    if (n < 0 || (size_t)n >= sizeof(args)) return FP_SESSION_LIMIT;
    at = (size_t)n;
    if (fp_document_quote(account->key, account->key_length, args + at, sizeof(args) - at - 4, &length) != FP_DOCUMENT_OK) { wipe(args, sizeof(args)); return FP_SESSION_LIMIT; }
    at += length;
    if (hidden) { args[at++] = ','; args[at++] = '1'; }
    args[at++] = ']';
    status = fp_session_request(session, "ma", args, at, timeout_ms, reply);
    wipe(args, sizeof(args));
    return status;
}
