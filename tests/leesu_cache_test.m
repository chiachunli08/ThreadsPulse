#import <Foundation/Foundation.h>
#import "TPLeeSuCache.h"
#import "TPLeeSuLocation.h"

// Exercise the same packaged flag data used by the iOS resource bundle.
NSBundle *TPResourceBundle(void) {
    NSString *path = [NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:@"layout/Library/Application Support/ThreadsPulse/ThreadsPulse.bundle"];
    return [NSBundle bundleWithPath:path];
}
int main(void) { @autoreleasepool {
    NSURL *dir = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    NSURL *url = [dir URLByAppendingPathComponent:@"profiles.json"];
    TPLeeSuCache *c = [[TPLeeSuCache alloc] initWithURL:url];
    [c store:@{@"username":@"alice", @"location":@"Taiwan", @"joined":@"2026年11月", @"fb_dtsg":@"secret"} userID:@"123" now:100];
    NSCAssert([[c profileForID:@"123" now:101][@"location"] isEqual:@"Taiwan"], @"cache hit");
    NSCAssert([c profileForID:@"456" now:101] == nil, @"user IDs cannot mix");
    NSCAssert([[c profileForID:@"123" now:101] objectForKey:@"fb_dtsg"] == nil, @"token allowlist");
    TPLeeSuCache *reloaded = [[TPLeeSuCache alloc] initWithURL:url];
    NSCAssert([reloaded profilesAt:101].count == 1, @"persistence");
    NSCAssert([reloaded profileForID:@"123" now:100+72*3600] == nil, @"72 hour expiration");
    [c clear]; NSCAssert([c profilesAt:101].count == 0, @"clear");
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *parts = [NSDateComponents new]; parts.year=2026; parts.month=11; parts.day=11;
    NSDate *now=[cal dateFromComponents:parts];
    for (NSString *joined in @[@"2026年11月", @"September 2026", @"2026년 10월"]) NSCAssert(TPLeeSuRecentAt(joined, now), @"recent multilingual date");
    for (NSString *joined in @[@"August 2026", @"December 2026", @"2026年13月", @"unknown"]) NSCAssert(!TPLeeSuRecentAt(joined, now), @"old/future/invalid date");
    NSDictionary *labels = @{
        @"台灣":@"🇹🇼 台灣", @"臺灣":@"🇹🇼 臺灣", @"Taiwan":@"🇹🇼 Taiwan", @"台湾":@"🇹🇼 台湾",
        @"日本":@"🇯🇵 日本", @"Japan":@"🇯🇵 Japan", @"TW":@"🇹🇼 TW", @"香港":@"🇭🇰 香港",
        @"미국":@"🇺🇸 미국", @" United States ":@"🇺🇸 United States",
        @"未分享":@"未分享", @"Not shared":@"Not shared", @"台北":@"台北",
        @"Japan and Taiwan":@"Japan and Taiwan", @"🇹🇼 台灣":@"🇹🇼 台灣", @"":@""
    };
    for (NSString *name in labels) NSCAssert([TPLeeSuLocationLabel(name) isEqualToString:labels[name]], @"flag + original region name: %@", name);
    NSCAssert([TPLeeSuLocationLabel(nil) isEqualToString:@""], @"missing location");
    [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
    puts("Lee Su cache/date/location tests passed");
} return 0; }
