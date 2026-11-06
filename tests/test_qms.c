#include "fp_qms.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define CHECK(s,kind) fp_qms_validate((const uint8_t *)(s), strlen(s), (kind))
int main(void)
{
    const char *contacts = "[1,0,[[42,\"name\",0,\"\",0,0,0,[[7,0,0,\"subject\"]]]]]";
    const char *talk = "[1,0,0,0,0,\"subject\",0,\"name\",0,0,0,0,0,0,0,[[7,42,123,\"hi\",[[9,0,\"file\",10]]]]]";
    assert(CHECK(contacts, FP_QMS_CONTACTS));
    assert(CHECK(talk, FP_QMS_TALK));
    assert(!CHECK("[1,0,[[42,3,0,\"\",0,0,0,[]]]]", FP_QMS_CONTACTS));
    assert(!CHECK("[1,0,0,0,0,\"subject\",0,0,0,0,0,0,0,0,0,[[7,42,123,\"hi\",[[9,0,3,10]]]]]", FP_QMS_TALK));
    for (size_t i = 0; i < strlen(talk); i++) assert(!fp_qms_validate((const uint8_t *)talk, i, FP_QMS_TALK));
    puts("qms tests passed");
    return 0;
}
