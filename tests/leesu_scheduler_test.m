#import <Foundation/Foundation.h>
#import "TPLeeSuScheduler.h"
#import <math.h>
#import <float.h>
int main(void) { @autoreleasepool {
    TPLeeSuScheduler *s = [TPLeeSuScheduler new];
    [s updateVisibleIDs:@[@"a", @"a", @"b", @"c"]];
    NSCAssert([[s takeNextAt:100] isEqual:@"a"], @"first visible author starts immediately");
    NSCAssert([s takeNextAt:100] == nil && [s takeNextAt:100.9] == nil, @"no burst, even with free slots");
    NSCAssert([[s takeNextAt:101] isEqual:@"b"], @"second author starts while first is slow");
    NSCAssert([s takeNextAt:102] == nil && [s delayUntilNextAt:102] < 0, @"at most two requests in flight");
    [s finishID:@"b"];
    [s updateVisibleIDs:@[@"a", @"d", @"d"]];
    NSCAssert([[s takeNextAt:102] isEqual:@"d"], @"drop offscreen c, dedupe d, never duplicate in-flight a");
    [s finishID:@"a"]; [s finishID:@"d"];
    [s updateVisibleIDs:@[@"e"]]; s.pausedUntil=1003;
    NSCAssert([s takeNextAt:103] == nil && fabs([s delayUntilNextAt:103]-900)<0.001, @"429 pause blocks all starts");
    NSCAssert([s takeNextAt:1002.9] == nil, @"cooldown is not shortened by scroll/slot completion");
    NSCAssert([[s takeNextAt:1003] isEqual:@"e"], @"resume after cooldown");
    [s finishID:@"e"]; [s updateVisibleIDs:@[@"f"]]; [s cancelPending];
    NSCAssert([s takeNextAt:1005] == nil && [s delayUntilNextAt:1005]<0, @"no work/timer after pending cancellation");

    // Controlled scheduling comparison: 20 cache misses, each response takes 200ms.
    s = [TPLeeSuScheduler new];
    NSMutableArray *ids = [NSMutableArray array];
    for (NSInteger i=0;i<20;i++) [ids addObject:[@(i) stringValue]];
    [s updateVisibleIDs:ids];
    NSMutableArray<NSDictionary *> *responses = [NSMutableArray array];
    NSTimeInterval now=0, first=-1, last=0;
    NSInteger completed=0;
    while (completed<20) {
        for (NSDictionary *r in [responses copy]) if ([r[@"at"] doubleValue] <= now+0.000001) {
            [s finishID:r[@"id"]]; [responses removeObject:r]; completed++;
            if (first<0) first=now; last=now;
        }
        NSString *userID = [s takeNextAt:now];
        if (userID) [responses addObject:@{@"id":userID, @"at":@(now+0.2)}];
        NSCAssert(responses.count<=2, @"bounded concurrency during a full feed");
        if (completed==20) break;
        NSTimeInterval next=DBL_MAX;
        for (NSDictionary *r in responses) next=MIN(next,[r[@"at"] doubleValue]);
        NSTimeInterval delay=[s delayUntilNextAt:now]; if (delay>=0) next=MIN(next,now+delay);
        NSCAssert(next>now && next<DBL_MAX, @"scheduler makes progress without spinning"); now=next;
    }
    NSCAssert(fabs(first-0.2)<0.001 && fabs(last-19.2)<0.001, @"no completion-based 3-second wait");
    printf("Scheduler tests passed; 20 simulated 200ms responses: 64.0s old / %.1fs new (not a live network benchmark)\n",last);
} return 0; }
