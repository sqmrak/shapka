#ifndef FP_COMPOSE_H
#define FP_COMPOSE_H
#include <stddef.h>
#include <stdint.h>
#include "fp_document.h"

/* text and subject are windows-1251 with numeric entities for other characters */
fp_document_status fp_compose_reply(int32_t topic, const uint8_t *text, size_t text_length,
                                     uint8_t *out, size_t capacity, size_t *written);
fp_document_status fp_compose_message(int32_t member, const uint8_t *text, size_t text_length,
                                       const uint8_t *subject, size_t subject_length,
                                       uint8_t *out, size_t capacity, size_t *written);
fp_document_status fp_compose_qms_reply(int32_t dialog, const uint8_t *text, size_t text_length,
                                         uint8_t *out, size_t capacity, size_t *written);

/* the vote of fk: 2 is a plus, 1 a minus, 0 asks for the list of voters */
fp_document_status fp_compose_post_vote(int32_t post, int32_t vote, uint8_t *out, size_t capacity, size_t *written);
/* the reputation change of mr: member, direction, post and the reason, windows-1251 with numeric entities */
fp_document_status fp_compose_karma(int32_t member, int up, int32_t post, const uint8_t *reason, size_t reason_length,
                                     uint8_t *out, size_t capacity, size_t *written);
/* the text of an mr status the server uses to refuse a change, or NULL for a status without one */
const char *fp_compose_karma_refusal(int32_t status);
#endif
