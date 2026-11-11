#import <Foundation/Foundation.h>
#import "TPLeeSuCache.h"
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
    [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
    puts("Lee Su cache/date tests passed");
} return 0; }
