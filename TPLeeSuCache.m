#import "TPLeeSuCache.h"
static const NSTimeInterval TPLeeSuTTL = 72 * 60 * 60;
@interface TPLeeSuCache ()
@property(nonatomic, strong) NSURL *url;
@property(nonatomic, strong) NSMutableDictionary *entries;
@end
@implementation TPLeeSuCache
- (instancetype)initWithURL:(NSURL *)url {
    if ((self = [super init])) {
        _url = url;
        NSData *data = [NSData dataWithContentsOfURL:url];
        id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        _entries = [NSMutableDictionary dictionary];
        if ([value isKindOfClass:NSDictionary.class]) {
            for (NSString *key in value) {
                id entry = value[key];
                if ([entry isKindOfClass:NSDictionary.class] && [entry[@"fetchedAt"] isKindOfClass:NSNumber.class])
                    _entries[key] = entry;
            }
        }
    }
    return self;
}
- (void)save {
    [NSFileManager.defaultManager createDirectoryAtURL:self.url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.entries options:0 error:nil];
    [data writeToURL:self.url options:NSDataWritingAtomic error:nil];
    [self.url setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
}
- (NSDictionary *)profileForID:(NSString *)userID now:(NSTimeInterval)now {
    NSDictionary *p = self.entries[userID];
    NSTimeInterval fetched = [p[@"fetchedAt"] doubleValue];
    if (!p || fetched > now || now - fetched >= TPLeeSuTTL) {
        if (p) { [self.entries removeObjectForKey:userID]; [self save]; }
        return nil;
    }
    return p;
}
- (void)store:(NSDictionary *)profile userID:(NSString *)userID now:(NSTimeInterval)now {
    if (!userID.length) return;
    NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:@{@"userID":userID, @"fetchedAt":@(now)}];
    // Explicit allowlist: no session data or unexpected server fields can reach disk/export.
    for (NSString *key in @[@"username", @"displayName", @"location", @"joined"]) {
        if ([profile[key] isKindOfClass:NSString.class]) entry[key] = profile[key];
    }
    self.entries[userID] = entry;
    [self profilesAt:now];
    if (self.entries.count > 2000) {
        NSArray *sorted = [self.entries keysSortedByValueUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"fetchedAt"] compare:b[@"fetchedAt"]];
        }];
        [self.entries removeObjectsForKeys:[sorted subarrayWithRange:NSMakeRange(0, self.entries.count - 2000)]];
    }
    [self save];
}
- (NSArray<NSDictionary *> *)profilesAt:(NSTimeInterval)now {
    for (NSString *key in self.entries.allKeys) [self profileForID:key now:now];
    return [self.entries.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [(a[@"username"] ?: a[@"userID"]) compare:(b[@"username"] ?: b[@"userID"])];
    }];
}
- (void)clear { [self.entries removeAllObjects]; [self save]; }
@end

BOOL TPLeeSuRecentAt(NSString *joined, NSDate *now) {
    if (![joined isKindOfClass:NSString.class] || !joined.length) return NO;
    NSRegularExpression *yearRE = [NSRegularExpression regularExpressionWithPattern:@"[0-9]{4}" options:0 error:nil];
    NSTextCheckingResult *yearMatch = [yearRE firstMatchInString:joined options:0 range:NSMakeRange(0, joined.length)];
    if (!yearMatch) return NO;
    NSInteger year = [[joined substringWithRange:yearMatch.range] integerValue], month = 0;
    NSRegularExpression *monthRE = [NSRegularExpression regularExpressionWithPattern:@"([0-9]{1,2})[月월]" options:0 error:nil];
    NSTextCheckingResult *match = [monthRE firstMatchInString:joined options:0 range:NSMakeRange(0, joined.length)];
    if (match) month = [[joined substringWithRange:[match rangeAtIndex:1]] integerValue];
    else {
        NSArray *months = @[@"jan", @"feb", @"mar", @"apr", @"may", @"jun", @"jul", @"aug", @"sep", @"oct", @"nov", @"dec"];
        for (NSUInteger i=0; i<months.count; i++) if ([joined.lowercaseString containsString:months[i]]) { month = i+1; break; }
    }
    if (month < 1 || month > 12) return NO;
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *current = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth fromDate:now];
    NSInteger delta = current.year * 12 + current.month - (year * 12 + month);
    return delta >= 0 && delta <= 2;
}
