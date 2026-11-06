#ifndef FP_QMS_H
#define FP_QMS_H
#include <stddef.h>
#include <stdint.h>
typedef enum { FP_QMS_CONTACTS, FP_QMS_TALK } fp_qms_kind;
/* validates the fields used by the qms screens */
int fp_qms_validate(const uint8_t *data, size_t length, fp_qms_kind kind);
#endif
