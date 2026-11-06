#import "FPProtocolDocument.h"
#include "fp_document.h"
#include "fp_text.h"
#include <errno.h>
#include <stdlib.h>
#include <string.h>

static id FPProtocolValue(const uint8_t *bytes, fp_document_token *tokens, size_t count, size_t *index)
{
    fp_document_token *token;
    if (*index >= count) return nil;
    token = &tokens[(*index)++];
    if (token->type == FP_DOCUMENT_ARRAY) {
        NSMutableArray *items = [NSMutableArray arrayWithCapacity:token->children];
        for (size_t i = 0; i < token->children; i++) {
            id value = FPProtocolValue(bytes, tokens, count, index);
            if (!value) return nil;
            [items addObject:value];
        }
        return items;
    }
    if (token->type == FP_DOCUMENT_INTEGER) {
        char number[32], *end;
        long long value;
        if (!token->length || token->length >= sizeof(number)) return nil;
        memcpy(number, bytes + token->offset, token->length);
        number[token->length] = 0;
        errno = 0;
        value = strtoll(number, &end, 10);
        if (errno || *end) return nil;
        return [NSNumber numberWithLongLong:value];
    }
    if (token->type == FP_DOCUMENT_STRING && token->length >= 2) {
        fp_span span = {bytes + token->offset + 1, token->length - 2};
        size_t capacity = FP_TEXT_UTF8_BOUND(span.length), written = 0;
        char *buffer = malloc(capacity);
        if (!buffer) return nil;
        if (fp_text_decode(span, buffer, capacity, &written) != FP_TEXT_OK) { free(buffer); return nil; }
        written = fp_text_unescape_entities(buffer, written, buffer, capacity);
        NSString *value = [[[NSString alloc] initWithBytes:buffer length:written encoding:NSUTF8StringEncoding] autorelease];
        free(buffer);
        return value;
    }
    return nil;
}

NSArray *FPProtocolDocument(NSData *data)
{
    size_t count = 0, index = 0, capacity = MIN([data length], (NSUInteger)32768);
    fp_document_token *tokens;
    id result = nil;
    if (!capacity || [data length] > 4 * 1024 * 1024) return nil;
    tokens = malloc(capacity * sizeof(*tokens));
    if (!tokens) return nil;
    if (fp_document_parse([data bytes], [data length], tokens, capacity, &count) == FP_DOCUMENT_OK)
        result = FPProtocolValue([data bytes], tokens, count, &index);
    free(tokens);
    return [result isKindOfClass:[NSArray class]] && index == count ? result : nil;
}
