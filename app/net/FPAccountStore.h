#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include "fp_auth.h"

@interface FPAccountStore : NSObject
+ (OSStatus)loadAccount:(fp_auth_account *)account;
+ (OSStatus)saveAccount:(const fp_auth_account *)account;
/* the key stays in memory only: for a login that was not asked to be remembered */
/* YES when the key of the member is in the keychain and not only in memory */
+ (BOOL)isPersisted;
+ (void)keepForSession:(const fp_auth_account *)account;
+ (OSStatus)removeAccount;
+ (NSDictionary *)profileForMember:(NSInteger)member;
+ (void)rememberName:(NSString *)name avatar:(NSString *)avatar forMember:(NSInteger)member;
@end
