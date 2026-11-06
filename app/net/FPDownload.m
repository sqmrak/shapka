#import "FPDownload.h"

#define FP_DOWNLOAD_LIMIT (1024ULL * 1024ULL * 1024ULL)

static NSError *FPDownloadError(NSString *message)
{
    return [NSError errorWithDomain:@"com.pageflip.shapka.download" code:1
                           userInfo:[NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey]];
}

static BOOL FPDownloadURLAllowed(NSURL *url)
{
    return url && [[[url scheme] lowercaseString] isEqualToString:@"https"] && [[url host] length] &&
        ![[url user] length] && ![[url password] length];
}

@implementation FPDownload
- (id)initWithURL:(NSURL *)url name:(NSString *)name completion:(FPDownloadCompletion)completion
{
    self = [super init];
    if (self) {
        NSArray *directories = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *directory = [directories count] ? [directories objectAtIndex:0] : nil;
        NSString *safeName = [name lastPathComponent];
        NSString *identifier = [[NSProcessInfo processInfo] globallyUniqueString];
        if (![safeName length] || [safeName isEqualToString:@"."] || [safeName isEqualToString:@".."] || [safeName hasPrefix:@"."])
            safeName = @"file";
        safeName = [safeName stringByReplacingOccurrencesOfString:@":" withString:@"_"];
        if ([safeName length] > 150) safeName = [safeName substringToIndex:150];
        _finalPath = [[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", identifier, safeName]] copy];
        _temporaryPath = [[directory stringByAppendingPathComponent:[NSString stringWithFormat:@".%@.part", identifier]] copy];
        _completion = [completion copy];
        if (!directory || !FPDownloadURLAllowed(url) || !_completion) { [self release]; return nil; }
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60];
        [request setValue:@"identity" forHTTPHeaderField:@"Accept-Encoding"];
        _connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
        if (!_connection) { [self release]; return nil; }
    }
    return self;
}
- (void)dealloc
{
    [_connection cancel];
    [_connection release];
    [_stream close];
    [_stream release];
    if (_temporaryPath) [[NSFileManager defaultManager] removeItemAtPath:_temporaryPath error:NULL];
    [_temporaryPath release];
    [_finalPath release];
    [_completion release];
    [super dealloc];
}
- (void)finish:(NSError *)error
{
    if (_finished) return;
    _finished = YES;
    [_connection cancel];
    [_stream close];
    if (!error) {
        NSError *moveError = nil;
        if (![[NSFileManager defaultManager] moveItemAtPath:_temporaryPath toPath:_finalPath error:&moveError]) error = moveError;
    }
    if (error) [[NSFileManager defaultManager] removeItemAtPath:_temporaryPath error:NULL];
    [[self retain] autorelease];
    _completion(error ? nil : _finalPath, error);
}
- (void)start
{
    _stream = [[NSOutputStream alloc] initToFileAtPath:_temporaryPath append:NO];
    if (!_stream) { [self finish:FPDownloadError(@"Не удалось создать файл")]; return; }
    [_stream open];
    [_connection scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [_connection start];
}
- (void)cancel { [self finish:FPDownloadError(@"Загрузка отменена")]; }
- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response
{
    (void)connection;
    if ((response && ++_redirects > 10) || !FPDownloadURLAllowed([request URL])) {
        [self finish:FPDownloadError(@"Сервер перенаправил загрузку на небезопасный адрес")];
        return nil;
    }
    return request;
}
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    (void)connection;
    if (![response isKindOfClass:[NSHTTPURLResponse class]] || [(NSHTTPURLResponse *)response statusCode] != 200 ||
        [response expectedContentLength] > (long long)FP_DOWNLOAD_LIMIT ||
        [[[response MIMEType] lowercaseString] isEqualToString:@"text/html"]) {
        [self finish:FPDownloadError(@"Сервер не вернул файл или файл слишком велик")];
        return;
    }
    _expected = [response expectedContentLength];
    _acceptedResponse = YES;
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    const uint8_t *bytes = [data bytes];
    NSUInteger length = [data length], offset = 0;
    (void)connection;
    if (_finished) return;
    if (!_acceptedResponse) { [self finish:FPDownloadError(@"Сервер не подтвердил загрузку")]; return; }
    if (length > FP_DOWNLOAD_LIMIT - _received) { [self finish:FPDownloadError(@"Файл слишком велик")]; return; }
    while (offset < length) {
        NSInteger count = [_stream write:bytes + offset maxLength:length - offset];
        if (count <= 0) { [self finish:[_stream streamError] ? [_stream streamError] : FPDownloadError(@"Не удалось записать файл")]; return; }
        offset += (NSUInteger)count;
    }
    _received += length;
}
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error { (void)connection; [self finish:error]; }
- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    (void)connection;
    if (!_acceptedResponse || (_expected >= 0 && _received != (unsigned long long)_expected)) {
        [self finish:FPDownloadError(@"Файл получен не полностью")];
        return;
    }
    [self finish:nil];
}
@end
