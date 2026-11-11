#import "TPLeeSuScheduler.h"
@interface TPLeeSuScheduler ()
@property(nonatomic, strong) NSMutableArray<NSString *> *pending;
@property(nonatomic, strong) NSMutableSet<NSString *> *inFlight;
@property(nonatomic) NSTimeInterval nextStart;
@end
@implementation TPLeeSuScheduler
- (instancetype)init {
    if ((self = [super init])) { _pending = [NSMutableArray array]; _inFlight = [NSMutableSet set]; }
    return self;
}
- (void)updateVisibleIDs:(NSArray<NSString *> *)userIDs {
    // Replace stale scroll backlog with current viewport order; deduplicate authors.
    NSMutableOrderedSet *visible = [NSMutableOrderedSet orderedSet];
    for (NSString *userID in userIDs) if (userID.length && ![self.inFlight containsObject:userID]) [visible addObject:userID];
    self.pending = [visible.array mutableCopy];
}
- (NSTimeInterval)delayUntilNextAt:(NSTimeInterval)now {
    if (!self.pending.count || self.inFlight.count >= 2) return -1;
    return MAX(0, MAX(self.nextStart, self.pausedUntil) - now);
}
- (NSString *)takeNextAt:(NSTimeInterval)now {
    NSTimeInterval delay = [self delayUntilNextAt:now];
    if (delay < 0 || delay > 0) return nil;
    NSString *userID = self.pending.firstObject;
    [self.pending removeObjectAtIndex:0]; [self.inFlight addObject:userID];
    self.nextStart = now + 1.0;
    return userID;
}
- (void)finishID:(NSString *)userID { if (userID) [self.inFlight removeObject:userID]; }
- (void)cancelPending { [self.pending removeAllObjects]; }
@end
