#ifndef FP_BBCODE_H
#define FP_BBCODE_H

#include <stddef.h>
#include <stdint.h>

/* flat tree of a forum message: text runs, tag openings and tag closings in document order; all spans point
   into the utf-8 source, which keeps html entities for the caller to resolve per text run */

#define FP_BB_DEPTH_LIMIT 32u
#define FP_BB_SOURCE_LIMIT (256u * 1024u)

typedef enum {
    FP_BB_TAG_NONE = 0,
    FP_BB_B, FP_BB_I, FP_BB_U, FP_BB_S, FP_BB_COLOR, FP_BB_SIZE, FP_BB_URL, FP_BB_IMG,
    FP_BB_QUOTE, FP_BB_CODE, FP_BB_SPOILER, FP_BB_HIDE, FP_BB_MOD, FP_BB_EX, FP_BB_CUR,
    FP_BB_OFFTOP, FP_BB_LIST, FP_BB_ITEM, FP_BB_CENTER, FP_BB_LEFT, FP_BB_RIGHT, FP_BB_ATTACHMENT,
    FP_BB_SUB, FP_BB_SUP, FP_BB_TABLE, FP_BB_ROW, FP_BB_CELL, FP_BB_BREAK,
    /* known tags with no visible effect; their content stays */
    FP_BB_PLAIN
} fp_bb_tag;

typedef enum { FP_BB_TEXT, FP_BB_OPEN, FP_BB_CLOSE } fp_bb_kind;

typedef struct {
    fp_bb_kind kind;
    fp_bb_tag tag;
    /* text run for FP_BB_TEXT, tag argument for FP_BB_OPEN (unquoted, may hold nested tags) */
    size_t start;
    size_t length;
} fp_bb_node;

typedef enum { FP_BB_OK = 0, FP_BB_INVALID, FP_BB_LIMIT } fp_bb_status;

/* every opening is matched by a closing, except FP_BB_ITEM and FP_BB_BREAK which stand alone; img, code and
   attachment keep their body as one text run; on FP_BB_LIMIT the nodes written so far are valid */
fp_bb_status fp_bb_parse(const char *source, size_t length, fp_bb_node *nodes, size_t capacity, size_t *count);

/* nodes needed for a source of this length */
#define FP_BB_NODE_BOUND(length) ((length) + 33u)

/* finds name="value" or name=value in an argument; returns the span of the value */
int fp_bb_attribute(const char *arg, size_t length, const char *name, size_t *start, size_t *value_length);

/* reads a css color name or #rgb or #rrggbb; returns 0 when unknown */
int fp_bb_color(const char *arg, size_t length, uint32_t *rgb);

/* copies the text of a bbcode string without its tags; returns the length written, output is zero terminated */
size_t fp_bb_strip(const char *source, size_t length, char *output, size_t capacity);

#endif
