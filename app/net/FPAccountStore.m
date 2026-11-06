#import "FPAccountStore.h"

static NSString *const FPAccountService = @"com.sqmrak.shapka.account";
static NSString *const FPAccountName = @"session";

static NSMutableDictionary *FPAccountQuery(void)
{
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:
            (id)kSecClassGenericPassword, (id)kSecClass,
            FPAccountService, (id)kSecAttrService,
            FPAccountName, (id)kSecAttrAccount, nil];
}

/* a login that was not asked to be remembered lives here until the app ends or the member logs out, so a dropped connection can resume it */
static fp_auth_account FPSessionAccount;
static BOOL FPHasSessionAccount;

@implementation FPAccountStore

+ (OSStatus)loadAccount:(fp_auth_account *)account
{
    NSMutableDictionary *query;
    CFTypeRef result = NULL;
    OSStatus status;
    NSData *data;
    const uint8_t *bytes;
    NSUInteger length;
    uint32_t member;
    if (!account) return errSecParam;
    fp_auth_clear(account);
    query = FPAccountQuery();
    [query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData];
    [query setObject:(id)kSecMatchLimitOne forKey:(id)kSecMatchLimit];
    status = SecItemCopyMatching((CFDictionaryRef)query, &result);
    if (status == errSecItemNotFound) {
        @synchronized(self) {
            if (!FPHasSessionAccount) return status;
            *account = FPSessionAccount;
        }
        return errSecSuccess;
    }
    if (status != errSecSuccess) return status;
    if (!result || CFGetTypeID(result) != CFDataGetTypeID()) {
        if (result) CFRelease(result);
        return errSecDecode;
    }
    data = (NSData *)result;
    length = [data length];
    bytes = [data bytes];
    if (length < 7 || length - 6 > FP_AUTH_KEY_LIMIT || bytes[0] != 1 || bytes[1] > 1) { CFRelease(result); return errSecDecode; }
    member = ((uint32_t)bytes[2] << 24) | ((uint32_t)bytes[3] << 16) | ((uint32_t)bytes[4] << 8) | bytes[5];
    if (!member || member > INT32_MAX) { CFRelease(result); return errSecDecode; }
    account->member_id = (int32_t)member;
    account->hidden = bytes[1];
    account->key_length = length - 6;
    memcpy(account->key, bytes + 6, account->key_length);
    CFRelease(result);
    return errSecSuccess;
}

+ (OSStatus)saveAccount:(const fp_auth_account *)account
{
    NSMutableDictionary *query;
    NSDictionary *attributes;
    NSMutableData *data;
    uint8_t idBytes[6];
    uint32_t member;
    OSStatus status;
    if (!account || account->member_id <= 0 || !account->key_length || account->key_length > FP_AUTH_KEY_LIMIT) return errSecParam;
    member = (uint32_t)account->member_id;
    idBytes[0] = 1; idBytes[1] = account->hidden ? 1 : 0;
    idBytes[2] = (uint8_t)(member >> 24); idBytes[3] = (uint8_t)(member >> 16);
    idBytes[4] = (uint8_t)(member >> 8); idBytes[5] = (uint8_t)member;
    data = [NSMutableData dataWithBytes:idBytes length:sizeof(idBytes)];
    [data appendBytes:account->key length:account->key_length];
    query = FPAccountQuery();
    attributes = [NSDictionary dictionaryWithObject:data forKey:(id)kSecValueData];
    status = SecItemUpdate((CFDictionaryRef)query, (CFDictionaryRef)attributes);
    if (status == errSecItemNotFound) {
        [query setObject:data forKey:(id)kSecValueData];
        [query setObject:(id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly forKey:(id)kSecAttrAccessible];
        status = SecItemAdd((CFDictionaryRef)query, NULL);
    }
    memset([data mutableBytes], 0, [data length]);
    if (status == errSecSuccess) @synchronized(self) { fp_auth_clear(&FPSessionAccount); FPHasSessionAccount = NO; }
    return status;
}

+ (BOOL)isPersisted
{
    NSMutableDictionary *query = FPAccountQuery();
    CFTypeRef result = NULL;
    OSStatus status;
    [query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData];
    status = SecItemCopyMatching((CFDictionaryRef)query, &result);
    if (result) CFRelease(result);
    return status == errSecSuccess;
}

+ (void)keepForSession:(const fp_auth_account *)account
{
    if (!account || account->member_id <= 0) return;
    @synchronized(self) { FPSessionAccount = *account; FPHasSessionAccount = YES; }
}

+ (OSStatus)removeAccount
{
    @synchronized(self) { fp_auth_clear(&FPSessionAccount); FPHasSessionAccount = NO; }
    OSStatus status = SecItemDelete((CFDictionaryRef)FPAccountQuery());
    return status == errSecItemNotFound ? errSecSuccess : status;
}

+ (NSDictionary *)profileForMember:(NSInteger)member
{
    if (member <= 0) return nil;
    NSString *key = [NSString stringWithFormat:@"account_profile_%ld", (long)member];
    NSDictionary *profile = [[NSUserDefaults standardUserDefaults] dictionaryForKey:key];
    return [profile isKindOfClass:[NSDictionary class]] ? profile : nil;
}

+ (void)rememberName:(NSString *)name avatar:(NSString *)avatar forMember:(NSInteger)member
{
    if (member <= 0) return;
    NSString *key = [NSString stringWithFormat:@"account_profile_%ld", (long)member];
    NSDictionary *old = [self profileForMember:member];
    NSMutableDictionary *profile = old ? [[old mutableCopy] autorelease] : [NSMutableDictionary dictionary];
    if ([name isKindOfClass:[NSString class]] && [name length] && [name length] <= 256) [profile setObject:name forKey:@"name"];
    if ([avatar isKindOfClass:[NSString class]] && [avatar length] <= 2048) [profile setObject:avatar forKey:@"avatar"];
    [[NSUserDefaults standardUserDefaults] setObject:profile forKey:key];
}

@end
