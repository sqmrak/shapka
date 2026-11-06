#include "fp_compose.h"
#include <stdio.h>
#include <string.h>

static fp_document_status append(uint8_t *out, size_t capacity, size_t *at, const char *text)
{
    size_t length = strlen(text);
    if (length > capacity - *at) return FP_DOCUMENT_LIMIT;
    memcpy(out + *at, text, length);
    *at += length;
    return FP_DOCUMENT_OK;
}

static fp_document_status quote(uint8_t *out, size_t capacity, size_t *at, const uint8_t *text, size_t length)
{
    size_t n = 0;
    fp_document_status status = fp_document_quote(text, length, out + *at, capacity - *at, &n);
    if (status == FP_DOCUMENT_OK) *at += n;
    return status;
}

fp_document_status fp_compose_reply(int32_t topic, const uint8_t *text, size_t text_length,
                                     uint8_t *out, size_t capacity, size_t *written)
{
    char prefix[32];
    size_t at = 0;
    if (written) *written = 0;
    if (!written || !out || !text || !text_length || topic <= 0) return FP_DOCUMENT_INVALID;
    snprintf(prefix, sizeof(prefix), "[%d,0,0,", (int)topic);
    if (append(out, capacity, &at, prefix) != FP_DOCUMENT_OK ||
        quote(out, capacity, &at, text, text_length) != FP_DOCUMENT_OK ||
        append(out, capacity, &at, ",[]]") != FP_DOCUMENT_OK) return FP_DOCUMENT_LIMIT;
    *written = at;
    return FP_DOCUMENT_OK;
}

fp_document_status fp_compose_message(int32_t member, const uint8_t *text, size_t text_length,
                                       const uint8_t *subject, size_t subject_length,
                                       uint8_t *out, size_t capacity, size_t *written)
{
    char middle[32];
    size_t at = 0;
    if (written) *written = 0;
    if (!written || !out || !text || !text_length || !subject || !subject_length || member <= 0) return FP_DOCUMENT_INVALID;
    snprintf(middle, sizeof(middle), ",[],%d,", (int)member);
    if (append(out, capacity, &at, "[0,") != FP_DOCUMENT_OK ||
        quote(out, capacity, &at, text, text_length) != FP_DOCUMENT_OK ||
        append(out, capacity, &at, middle) != FP_DOCUMENT_OK ||
        quote(out, capacity, &at, subject, subject_length) != FP_DOCUMENT_OK ||
        append(out, capacity, &at, "]") != FP_DOCUMENT_OK) return FP_DOCUMENT_LIMIT;
    *written = at;
    return FP_DOCUMENT_OK;
}

fp_document_status fp_compose_qms_reply(int32_t dialog, const uint8_t *text, size_t text_length,
                                         uint8_t *out, size_t capacity, size_t *written)
{
    char prefix[32];
    size_t at = 0;
    if (written) *written = 0;
    if (!written || !out || !text || !text_length || dialog <= 0) return FP_DOCUMENT_INVALID;
    snprintf(prefix, sizeof(prefix), "[%d,", (int)dialog);
    if (append(out, capacity, &at, prefix) != FP_DOCUMENT_OK ||
        quote(out, capacity, &at, text, text_length) != FP_DOCUMENT_OK ||
        append(out, capacity, &at, ",[]]") != FP_DOCUMENT_OK) return FP_DOCUMENT_LIMIT;
    *written = at;
    return FP_DOCUMENT_OK;
}

fp_document_status fp_compose_post_vote(int32_t post, int32_t vote, uint8_t *out, size_t capacity, size_t *written)
{
    char text[40];
    int n;
    if (written) *written = 0;
    if (!written || !out || post <= 0 || vote < 0 || vote > 2) return FP_DOCUMENT_INVALID;
    n = snprintf(text, sizeof(text), "[%d,%d]", (int)post, (int)vote);
    if (n < 0 || (size_t)n >= capacity) return FP_DOCUMENT_LIMIT;
    memcpy(out, text, (size_t)n);
    *written = (size_t)n;
    return FP_DOCUMENT_OK;
}

fp_document_status fp_compose_karma(int32_t member, int up, int32_t post, const uint8_t *reason, size_t reason_length,
                                     uint8_t *out, size_t capacity, size_t *written)
{
    char prefix[48];
    size_t at = 0;
    if (written) *written = 0;
    if (!written || !out || !reason || !reason_length || member <= 0 || post <= 0) return FP_DOCUMENT_INVALID;
    snprintf(prefix, sizeof(prefix), "[%d,%d,%d,", (int)member, up ? 1 : 0, (int)post);
    if (append(out, capacity, &at, prefix) != FP_DOCUMENT_OK ||
        quote(out, capacity, &at, reason, reason_length) != FP_DOCUMENT_OK ||
        append(out, capacity, &at, "]") != FP_DOCUMENT_OK) return FP_DOCUMENT_LIMIT;
    *written = at;
    return FP_DOCUMENT_OK;
}

const char *fp_compose_karma_refusal(int32_t status)
{
    static const char *const text[] = {
        "Изменение репутации заблокировано",
        "Вы не можете менять репутацию самому себе",
        "У вас недостаточно постов, чтобы менять репутацию",
        "У вас слишком низкая репутация",
        "Вы больше не можете менять репутацию сегодня",
        "Вы больше не можете менять репутацию этому человеку сегодня",
        "Вы больше не можете менять репутацию за этот пост",
        "В данный момент вы не можете изменить репутацию этому человеку",
        "Изменение отклонено, т.к. вы недавно ставили минус этому человеку",
        "Изменение отклонено, т.к. пользователь недавно поставил вам минус"
    };
    if (status < 4 || status > 13) return NULL;
    return text[status - 4];
}
