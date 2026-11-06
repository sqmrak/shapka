#import "FPNetwork.h"
#import "FPAccountStore.h"
#include "fp_auth.h"
#include "fp_client.h"
#include "fp_guest.h"
#include <unistd.h>

NSString *const FPNetworkEventNotification = @"FPNetworkEvent";
NSString *const FPNetworkStateNotification = @"FPNetworkState";

static NSString *const FPNetworkErrorDomain = @"com.sqmrak.shapka.network";

static NSError *FPError(NSInteger code, NSString *description)
{
    return [NSError errorWithDomain:FPNetworkErrorDomain code:code
                           userInfo:[NSDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey]];
}

/* the login server answers only over tls; a network that drops its handshake leaves a timeout, which is said plainly so it is not taken for a wrong password */
static NSString *FPSecureLoginMessage(fp_session_status status)
{
    if (status == FP_SESSION_TIMEOUT) return @"Для входа нужно защищённое соединение, а сервер входа не ответил за 15 секунд. Сеть может блокировать этот адрес: попробуйте другую сеть или VPN";
    if (status == FP_SESSION_SECURITY) return @"Сертификат сервера входа не прошёл проверку, пароль не отправлен";
    return [NSString stringWithFormat:@"Для входа нужно защищённое соединение, а подключиться к серверу входа не удалось (код %d)", (int)status];
}

static void FPComplete(FPNetworkCompletion completion, NSData *document, NSInteger serverStatus, NSError *error)
{
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{ completion(document, serverStatus, error); });
}

@interface FPNetwork ()
- (void)stopReading;
- (BOOL)startReading;
- (void)attempt:(FPNetworkCompletion)completion retry:(BOOL)retry generation:(NSUInteger)generation;
- (void)scheduleReconnect;
- (void)notifyState:(NSError *)error;
@end

static void FPNetworkEvent(void *context, const uint8_t *document, size_t length)
{
    FPNetwork *network = (FPNetwork *)context;
    NSData *data = [NSData dataWithBytes:document length:length];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:FPNetworkEventNotification object:network
                                                          userInfo:[NSDictionary dictionaryWithObject:data forKey:@"document"]];
    });
}

@implementation FPNetwork

- (id)initWithHost:(NSString *)host rootsPath:(NSString *)rootsPath
{
    self = [super init];
    if (self) {
        _host = [host copy];
        _rootsPath = [rootsPath copy];
        _session.fd = -1;
        _queue = dispatch_queue_create("com.sqmrak.shapka.network", DISPATCH_QUEUE_SERIAL);
        if (!_host || !_rootsPath || !_queue) { [self release]; return nil; }
    }
    return self;
}

- (void)connectWithCompletion:(FPNetworkCompletion)completion
{
    [self attempt:completion retry:NO generation:0];
}

- (void)attempt:(FPNetworkCompletion)completion retry:(BOOL)retry generation:(NSUInteger)generation
{
    dispatch_async(_queue, ^{
        if (retry && (!_wantsConnection || generation != _generation)) return;
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        fp_auth_account account;
        fp_reply reply;
        fp_session_status status;
        OSStatus keyStatus;
        char args[128];
        int length;
        NSData *document = nil;
        NSInteger serverStatus = 0;
        NSError *error = nil;
        BOOL retryable = NO;
        _wantsConnection = YES;
        if (!retry) _retryCount = 0;
        _generation++;
        [self stopReading];
        fp_auth_clear(&account);
        fp_session_close(&_session);
        keyStatus = [FPAccountStore loadAccount:&account];
        if (keyStatus != errSecSuccess && keyStatus != errSecItemNotFound) {
            /* jailbreak signing can leave keychain access unavailable even for a guest */
            NSLog(@"Shapka: keychain read failed (%d), continuing as guest", (int)keyStatus);
            fp_auth_clear(&account);
        }
        /* appbk.4pda.to is the secure websocket host the android client takes from its provision file; app.4pda.ru never answered the handshake */
        status = fp_client_connect(&_session, [_host UTF8String], 443, [_rootsPath fileSystemRepresentation], NO, account.member_id > 0 ? 15000 : 4000);
        /* the android guest endpoint accepts public reads when its tls websocket is unreachable */
        if (account.member_id == 0 && (status == FP_SESSION_TIMEOUT || status == FP_SESSION_IO || status == FP_SESSION_EOF)) {
            status = fp_client_connect_guest(&_session, "app.4pda.to", 993, 10000);
        }
        if (status != FP_SESSION_OK) { retryable = status == FP_SESSION_TIMEOUT || status == FP_SESSION_IO || status == FP_SESSION_EOF; error = FPError(status, @"Не удалось установить защищённое соединение"); goto done; }
        length = snprintf(args, sizeof(args), "[\"1.9.43\",\"\",\"\",1,%d]", (int)account.member_id);
        if (length < 0 || (size_t)length >= sizeof(args)) { error = FPError(FP_SESSION_LIMIT, @"Неверные параметры подключения"); goto failed; }
        status = fp_session_request(&_session, "ah", (const uint8_t *)args, (size_t)length, 15000, &reply);
        if (status != FP_SESSION_OK) { retryable = status == FP_SESSION_TIMEOUT || status == FP_SESSION_IO || status == FP_SESSION_EOF; error = FPError(status, @"Ошибка приветствия сервера"); goto failed; }
        serverStatus = reply.status;
        document = [NSData dataWithBytes:reply.data length:reply.length];
        fp_reply_clear(&reply);
        if (serverStatus != 0) { error = FPError(serverStatus, @"Сервер отклонил подключение"); goto failed; }
        if (account.member_id > 0) {
            status = fp_auth_resume(&_session, &account, account.hidden, 15000, &reply);
            if (status != FP_SESSION_OK) { retryable = status == FP_SESSION_TIMEOUT || status == FP_SESSION_IO || status == FP_SESSION_EOF; error = FPError(status, @"Не удалось восстановить вход"); goto failed; }
            serverStatus = reply.status;
            document = [NSData dataWithBytes:reply.data length:reply.length];
            fp_reply_clear(&reply);
            if (serverStatus != 0) { error = FPError(serverStatus, @"Сервер отклонил ключ входа"); goto failed; }
        }
        fp_session_set_event_handler(&_session, FPNetworkEvent, self);
        if (![self startReading]) { error = FPError(FP_SESSION_IO, @"Не удалось получать события сервера"); retryable = YES; goto failed; }
        _retryCount = 0;
        goto done;
failed:
        fp_session_close(&_session);
done:
        fp_auth_clear(&account);
        [self notifyState:error];
        FPComplete(completion, document, serverStatus, error);
        if (error && retryable) [self scheduleReconnect];
        [pool drain];
    });
}

- (void)login:(NSString *)login password:(NSString *)password hidden:(BOOL)hidden
      captcha:(NSInteger)captcha remember:(BOOL)remember completion:(FPNetworkCompletion)completion
{
    dispatch_async(_queue, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSData *user = [login dataUsingEncoding:NSWindowsCP1251StringEncoding allowLossyConversion:NO];
        NSData *secret = [password dataUsingEncoding:NSWindowsCP1251StringEncoding allowLossyConversion:NO];
        NSData *document = nil;
        NSError *error = nil;
        NSInteger serverStatus = 0;
        fp_auth_account account;
        fp_reply reply;
        fp_session_status status;
        fp_auth_clear(&account);
        if (!user || !secret || captcha < 0 || captcha > INT32_MAX) {
            error = FPError(FP_SESSION_ARGUMENT, @"Логин или пароль содержит неподдерживаемые символы");
            goto done;
        }
        if (!_session.tls && _session.fd >= 0) {
            static const char hello[] = "[\"1.9.43\",\"\",\"\",1,0]";
            [self stopReading];
            fp_session_close(&_session);
            status = fp_client_connect(&_session, [_host UTF8String], 443, [_rootsPath fileSystemRepresentation], NO, 15000);
            if (status != FP_SESSION_OK) { error = FPError(status, FPSecureLoginMessage(status)); [self notifyState:error]; [self scheduleReconnect]; goto done; }
            status = fp_session_request(&_session, "ah", (const uint8_t *)hello, sizeof(hello) - 1, 15000, &reply);
            if (status != FP_SESSION_OK) { error = FPError(status, @"Ошибка приветствия сервера"); fp_session_close(&_session); [self notifyState:error]; [self scheduleReconnect]; goto done; }
            serverStatus = reply.status;
            fp_reply_clear(&reply);
            if (serverStatus != 0) { error = FPError(serverStatus, @"Сервер отклонил подключение"); fp_session_close(&_session); [self notifyState:error]; goto done; }
            fp_session_set_event_handler(&_session, FPNetworkEvent, self);
            if (![self startReading]) { error = FPError(FP_SESSION_IO, @"Не удалось получать события сервера"); fp_session_close(&_session); [self notifyState:error]; [self scheduleReconnect]; goto done; }
        }
        status = fp_auth_login(&_session, [user bytes], [user length], [secret bytes], [secret length],
                               hidden, (int32_t)captcha, 15000, &account, &reply);
        if (status != FP_SESSION_OK) { error = FPError(status, @"Не удалось выполнить вход"); if (_session.fd < 0) { [self stopReading]; [self notifyState:error]; [self scheduleReconnect]; } goto done; }
        serverStatus = reply.status;
        if (serverStatus != 0) document = [NSData dataWithBytes:reply.data length:reply.length];
        fp_reply_clear(&reply);
        if (serverStatus == 0) {
            OSStatus keyStatus = errSecSuccess;
            if (remember) keyStatus = [FPAccountStore saveAccount:&account];
            else [FPAccountStore keepForSession:&account];
            if (keyStatus != errSecSuccess) {
                /* a keychain that refuses the write (-25308 on a build signed without the keychain entitlement) must not throw away a login the server accepted:
                   the key lasts until the app ends and the login screen says it was not saved */
                NSLog(@"Shapka: keychain save failed (%d), the login lasts until the app ends", (int)keyStatus);
                [FPAccountStore keepForSession:&account];
            }
        }
done:
        fp_auth_clear(&account);
        FPComplete(completion, document, serverStatus, error);
        [pool drain];
    });
}

- (void)request:(NSString *)operation arguments:(NSData *)arguments completion:(FPNetworkCompletion)completion
{
    dispatch_async(_queue, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSData *code = [operation dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:NO];
        NSData *document = nil;
        NSError *error = nil;
        NSInteger serverStatus = 0;
        fp_reply reply;
        fp_session_status status;
        if ([code length] != 2 || !arguments) { error = FPError(FP_SESSION_ARGUMENT, @"Неверный запрос"); goto done; }
        if (!_session.tls && !fp_guest_request_allowed([operation UTF8String], [arguments bytes], [arguments length])) {
            error = FPError(FP_SESSION_SECURITY, @"Для этого действия нужно защищённое соединение"); goto done;
        }
        status = fp_session_request(&_session, [code bytes], [arguments bytes], [arguments length], 15000, &reply);
        if (status != FP_SESSION_OK) { NSLog(@"Shapka: request %@ failed with status %d", operation, (int)status); error = FPError(status, [NSString stringWithFormat:@"Ошибка сетевого запроса (код %d)", (int)status]); if (_session.fd < 0) { [self stopReading]; [self notifyState:error]; [self scheduleReconnect]; } goto done; }
        serverStatus = reply.status;
        document = [NSData dataWithBytes:reply.data length:reply.length];
        fp_reply_clear(&reply);
done:
        FPComplete(completion, document, serverStatus, error);
        [pool drain];
    });
}

- (void)notifyState:(NSError *)error
{
    NSDictionary *info = error ? [NSDictionary dictionaryWithObject:error forKey:@"error"] : [NSDictionary dictionary];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:FPNetworkStateNotification object:self userInfo:info];
    });
}

- (void)stopReading
{
    if (_readSource) {
        dispatch_source_cancel(_readSource);
        dispatch_release(_readSource);
        _readSource = NULL;
    }
}

- (void)scheduleReconnect
{
    NSUInteger generation;
    int delay;
    if (!_wantsConnection || _retryCount >= 5) return;
    delay = 1 << _retryCount++;
    generation = _generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)delay * NSEC_PER_SEC), _queue, ^{
        if (_wantsConnection && generation == _generation) [self attempt:nil retry:YES generation:generation];
    });
}

- (BOOL)startReading
{
    int watchFD;
    [self stopReading];
    watchFD = dup(_session.fd);
    if (watchFD < 0) return NO;
    _readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)watchFD, 0, _queue);
    if (!_readSource) {
        close(watchFD);
        return NO;
    }
    /* dispatch unregisters the read source asynchronously, so it owns a separate descriptor */
    dispatch_source_set_cancel_handler(_readSource, ^{ close(watchFD); });
    dispatch_source_set_event_handler(_readSource, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        fp_session_status status;
        /* a queued read event may outlive the request that already consumed its response */
        if (!fp_session_read_ready(&_session)) { [pool drain]; return; }
        do {
            status = fp_session_wait_event(&_session, 5000);
        } while (status == FP_SESSION_OK && fp_session_has_buffered(&_session));
        if (status != FP_SESSION_OK) {
            NSError *error = FPError(status, @"Соединение с сервером потеряно");
            [self stopReading];
            [self notifyState:error];
            [self scheduleReconnect];
        }
        [pool drain];
    });
    dispatch_resume(_readSource);
    return YES;
}

- (void)disconnect
{
    dispatch_async(_queue, ^{
        _wantsConnection = NO;
        _generation++;
        _retryCount = 0;
        [self stopReading];
        fp_session_close(&_session);
    });
}

- (void)dealloc
{
    fp_session_close(&_session);
    if (_queue) dispatch_release(_queue);
    [_host release];
    [_rootsPath release];
    [super dealloc];
}
@end
