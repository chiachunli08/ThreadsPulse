#import <Foundation/Foundation.h>

/// Local public profile data only. Keys are immutable Threads user IDs.
@interface TPLeeSuCache : NSObject
- (instancetype)initWithURL:(NSURL *)url;
- (NSDictionary *)profileForID:(NSString *)userID now:(NSTimeInterval)now;
- (void)store:(NSDictionary *)profile userID:(NSString *)userID now:(NSTimeInterval)now;
- (NSArray<NSDictionary *> *)profilesAt:(NSTimeInterval)now;
- (void)clear;
@end
/// Same month-granularity rule as upstream isNewUser(joined, 2).
BOOL TPLeeSuRecentAt(NSString *joined, NSDate *now);
