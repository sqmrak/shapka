#include "fp_document.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static fp_document_status parse(const char *s, fp_document_token *t, size_t cap, size_t *n)
{
    return fp_document_parse((const uint8_t *)s, strlen(s), t, cap, n);
}

int main(void)
{
    fp_document_token t[32];
    size_t n;
    assert(parse("[2,0,[[295,\"Apple\",16],[139,\"iOS\",0]]]", t, 32, &n) == FP_DOCUMENT_OK);
    assert(n == 12 && t[0].children == 3 && t[3].children == 2);
    assert(t[4].parent == 3 && t[5].parent == 4 && t[6].type == FP_DOCUMENT_STRING);
    assert(parse("[1,\"x\\u0401\\n\",-123,[]]", t, 32, &n) == FP_DOCUMENT_OK);
    assert(parse("[1,]", t, 32, &n) == FP_DOCUMENT_INVALID && n == 0);
    assert(parse("[1", t, 32, &n) == FP_DOCUMENT_INVALID);
    assert(parse("[\"x\\u00z0\"]", t, 32, &n) == FP_DOCUMENT_INVALID);
    assert(parse("[true]", t, 32, &n) == FP_DOCUMENT_INVALID);
    assert(parse("[1] trailing", t, 32, &n) == FP_DOCUMENT_INVALID);
    assert(parse("[1,2]", t, 2, &n) == FP_DOCUMENT_LIMIT);
    { const uint8_t input[] = {0xcf, '"', '\\', '\n'};
      uint8_t result[32];
      assert(fp_document_quote(input, sizeof(input), result, sizeof(result), &n) == FP_DOCUMENT_OK);
      assert(n == 13 && result[0] == '"' && result[1] == 0xcf && result[n - 1] == '"');
      assert(fp_document_quote(input, sizeof(input), result, n - 1, &n) == FP_DOCUMENT_LIMIT && n == 0); }
    puts("document tests passed");
    return 0;
}
