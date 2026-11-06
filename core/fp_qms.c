#include "fp_qms.h"
#include "fp_document.h"
#include <stdlib.h>

#define QMS_TOKEN_LIMIT 32768u
#define QMS_MISSING ((size_t)-1)
typedef struct { fp_document_token *tokens; size_t *ends; size_t count; } qms_doc;

static size_t child(const qms_doc *doc, size_t parent, size_t position)
{
    if (parent >= doc->count || doc->tokens[parent].type != FP_DOCUMENT_ARRAY || position >= doc->tokens[parent].children) return QMS_MISSING;
    size_t index = parent + 1;
    while (position--) index = doc->ends[index];
    return index;
}
static int type(const qms_doc *doc, size_t index, fp_document_type wanted)
{
    return index < doc->count && doc->tokens[index].type == wanted;
}
static int array(const qms_doc *doc, size_t index, size_t min, size_t max)
{
    return type(doc, index, FP_DOCUMENT_ARRAY) && doc->tokens[index].children >= min && doc->tokens[index].children <= max;
}
static int contacts(const qms_doc *doc)
{
    size_t list = child(doc, 0, 2);
    if (!array(doc, list, 0, 1000)) return 0;
    for (size_t i = 0; i < doc->tokens[list].children; i++) {
        size_t person = child(doc, list, i), threads;
        if (!array(doc, person, 8, 1024) || !type(doc, child(doc, person, 0), FP_DOCUMENT_INTEGER) ||
            !type(doc, child(doc, person, 1), FP_DOCUMENT_STRING)) return 0;
        threads = child(doc, person, 7);
        if (!array(doc, threads, 0, 1000)) return 0;
        for (size_t j = 0; j < doc->tokens[threads].children; j++) {
            size_t thread = child(doc, threads, j);
            if (!array(doc, thread, 4, 1024) || !type(doc, child(doc, thread, 0), FP_DOCUMENT_INTEGER) ||
                !type(doc, child(doc, thread, 3), FP_DOCUMENT_STRING)) return 0;
        }
    }
    return 1;
}
static int talk(const qms_doc *doc)
{
    size_t messages = child(doc, 0, 15);
    if (!type(doc, child(doc, 0, 5), FP_DOCUMENT_STRING) || !array(doc, messages, 0, 128)) return 0;
    for (size_t i = 0; i < doc->tokens[messages].children; i++) {
        size_t message = child(doc, messages, i), files;
        if (!array(doc, message, 5, 1024) || !type(doc, child(doc, message, 0), FP_DOCUMENT_INTEGER) ||
            !type(doc, child(doc, message, 1), FP_DOCUMENT_INTEGER) || !type(doc, child(doc, message, 2), FP_DOCUMENT_INTEGER) ||
            !type(doc, child(doc, message, 3), FP_DOCUMENT_STRING)) return 0;
        files = child(doc, message, 4);
        if (!array(doc, files, 0, 128)) return 0;
        for (size_t j = 0; j < doc->tokens[files].children; j++) {
            size_t file = child(doc, files, j);
            if (!array(doc, file, 4, 1024) || !type(doc, child(doc, file, 0), FP_DOCUMENT_INTEGER) ||
                !type(doc, child(doc, file, 1), FP_DOCUMENT_INTEGER) || !type(doc, child(doc, file, 2), FP_DOCUMENT_STRING)) return 0;
        }
    }
    return 1;
}
int fp_qms_validate(const uint8_t *data, size_t length, fp_qms_kind kind)
{
    qms_doc doc;
    size_t capacity = length < QMS_TOKEN_LIMIT ? length : QMS_TOKEN_LIMIT;
    int valid = 0;
    if (!data || !length || length > 4u * 1024u * 1024u || (kind != FP_QMS_CONTACTS && kind != FP_QMS_TALK)) return 0;
    doc.tokens = malloc(capacity * sizeof(*doc.tokens));
    doc.ends = malloc(capacity * sizeof(*doc.ends));
    if (!doc.tokens || !doc.ends) { free(doc.tokens); free(doc.ends); return 0; }
    if (fp_document_parse(data, length, doc.tokens, capacity, &doc.count) == FP_DOCUMENT_OK &&
        array(&doc, 0, 3, QMS_TOKEN_LIMIT)) {
        for (size_t i = 0; i < doc.count; i++) doc.ends[i] = i + 1;
        for (size_t i = doc.count; i-- > 1;) {
            size_t parent = doc.tokens[i].parent;
            if (parent != FP_DOCUMENT_NO_PARENT && doc.ends[i] > doc.ends[parent]) doc.ends[parent] = doc.ends[i];
        }
        if (type(&doc, child(&doc, 0, 0), FP_DOCUMENT_INTEGER) && type(&doc, child(&doc, 0, 1), FP_DOCUMENT_INTEGER))
            valid = kind == FP_QMS_CONTACTS ? contacts(&doc) : talk(&doc);
    }
    free(doc.tokens);
    free(doc.ends);
    return valid;
}
