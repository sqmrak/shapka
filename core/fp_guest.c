#include "fp_guest.h"
#include "fp_document.h"
#include <limits.h>
#include <string.h>

int fp_guest_request_allowed(const char *operation, const uint8_t *document, size_t length)
{
    fp_document_token tokens[6];
    size_t count, expected, i, j;
    uint32_t values[4] = {0, 0, 0, 0};
    if (!operation || !document) return 0;
    if (!strcmp(operation, "sl")) return length == 11 && !memcmp(document, "[0,30,-1,0]", 11);
    if (!strcmp(operation, "fi")) expected = 0;
    else if (!strcmp(operation, "fn") || !strcmp(operation, "sa")) expected = 1;
    else if (!strcmp(operation, "fs")) expected = 3;
    else if (!strcmp(operation, "fr")) expected = 4;
    else return 0;
    if (fp_document_parse(document, length, tokens, 6, &count) != FP_DOCUMENT_OK ||
        count != expected + 1 || tokens[0].children != expected) return 0;
    for (i = 0; i < expected; i++) {
        fp_document_token *token = &tokens[i + 1];
        if (token->type != FP_DOCUMENT_INTEGER || token->parent != 0 || !token->length) return 0;
        for (j = 0; j < token->length; j++) {
            unsigned digit = (unsigned)document[token->offset + j] - (unsigned)'0';
            if (digit > 9 || values[i] > (INT32_MAX - digit) / 10) return 0;
            values[i] = values[i] * 10 + digit;
        }
    }
    if (expected && !values[0]) return 0;
    if (expected >= 3 && (!values[2] || values[2] > 200)) return 0;
    return expected != 4 || values[3] == 0;
}

