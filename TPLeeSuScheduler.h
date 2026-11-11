#import <Foundation/Foundation.h>

/// Main-queue scheduler: immediate first start, >=1s between starts, <=2 in flight.
@interface TPLeeSuScheduler : NSObject
@property(nonatomic) NSTimeInterval pausedUntil;
- (void)updateVisibleIDs:(NSArray<NSString *> *)userIDs;
- (NSString *)takeNextAt:(NSTimeInterval)now;
- (void)finishID:(NSString *)userID;
/// Negative means no timer is needed (empty queue or both slots occupied).
- (NSTimeInterval)delayUntilNextAt:(NSTimeInterval)now;
- (void)cancelPending;
@end
