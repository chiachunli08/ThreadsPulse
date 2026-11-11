#import "TPLeeSu.h"
#import "TPLeeSuCache.h"
#import "TPLeeSuLocation.h"
#import "TPLeeSuScheduler.h"
#import "TPPrefs.h"
#import "TPDownloader.h"
#import "TPHUD.h"
#import "TPLocalization.h"
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

static const void *TPLeeSuButtonKey = &TPLeeSuButtonKey;
static const void *TPLeeSuUserKey = &TPLeeSuUserKey;
@class TPLeeSuManager;
static TPLeeSuManager *gTPLeeSuManager;
static NSTimeInterval TPNow(void) { return NSDate.date.timeIntervalSince1970; }
static BOOL TPTrustedURL(NSURL *url) {
    return [url.scheme isEqualToString:@"https"] &&
        ([(url.host ?: @"") isEqualToString:@"www.threads.com"] || [url.host isEqualToString:@"threads.com"]);
}

static BOOL TPLeeSuHeaderOnScreen(UIView *header) {
    UIWindow *window = header.window;
    if (!window) return NO;
    CGRect visible = CGRectIntersection([header convertRect:header.bounds toView:window], window.bounds);
    for (UIView *v = header; v && v != window; v = v.superview) {
        if (v.hidden || v.alpha < 0.01) return NO;
        if (v.clipsToBounds) visible = CGRectIntersection(visible, [v convertRect:v.bounds toView:window]);
    }
    return !CGRectIsNull(visible) && !CGRectIsEmpty(visible);
}

@interface TPLeeSuReadyHandler : NSObject <WKScriptMessageHandler>
@property(nonatomic, weak) id<WKScriptMessageHandler> target;
@end
@implementation TPLeeSuReadyHandler
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    [self.target userContentController:controller didReceiveScriptMessage:message];
}
@end

@interface TPLeeSuManager : NSObject <WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler>
@property(nonatomic, strong) WKWebView *web;
@property(nonatomic, strong) TPLeeSuCache *cache;
@property(nonatomic, strong) NSHashTable<UIView *> *headers;
@property(nonatomic, strong) TPLeeSuScheduler *scheduler;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *retryAfter;
@property(nonatomic) BOOL ready;
@property(nonatomic) BOOL refreshScheduled;
@property(nonatomic) BOOL refreshingHeaders;
@property(nonatomic) NSUInteger timerGeneration;
@property(nonatomic) NSTimeInterval scheduledDeadline;
@property(nonatomic) NSUInteger generation;
@property(nonatomic, weak) UIViewController *loginController;
+ (instancetype)shared;
- (void)update:(UIView *)header;
- (void)pump;
- (void)requestPump;
@end

@interface TPLeeSuLoginController : UIViewController
@property(nonatomic, strong) WKWebView *web;
@end
@implementation TPLeeSuLoginController
- (void)loadView { self.view = self.web; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = TPL(@"Lee Su Threads Login");
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:TPL(@"Done") style:UIBarButtonItemStyleDone target:self action:@selector(close)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:TPL(@"Cancel") style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItems = @[self.navigationItem.rightBarButtonItem, [[UIBarButtonItem alloc] initWithTitle:TPL(@"Reload") style:UIBarButtonItemStylePlain target:self action:@selector(reload)]];
}
- (void)cancel { [self dismissViewControllerAnimated:YES completion:^{ [self.web removeFromSuperview]; [TPLeeSuManager.shared requestPump]; }]; }
- (void)reload { [self.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://www.threads.com/"]]]; }
- (void)close {
    [self.web evaluateJavaScript:@"window.TPLeeSu ? window.TPLeeSu.ready() : false" completionHandler:^(id result, NSError *error) {
        TPLeeSuManager *m = TPLeeSuManager.shared;
        m.ready = !error && [result respondsToSelector:@selector(boolValue)] && [result boolValue];
        [TPHUD toast:TPL(m.ready ? @"Lee Su Threads connected" : @"Finish signing in to Threads on the web, then tap Done")];
        if (!m.ready) return;
        [self dismissViewControllerAnimated:YES completion:^{
            [m.web removeFromSuperview];
            [m.retryAfter removeAllObjects];
            for (UIView *h in m.headers.allObjects) [m update:h];
            [m pump];
        }];
    }];
}
@end

@implementation TPLeeSuManager
+ (instancetype)shared {
    static TPLeeSuManager *m; static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [TPLeeSuManager new]; gTPLeeSuManager = m; }); return m;
}
- (instancetype)init {
    if ((self = [super init])) {
        NSURL *base = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        _cache = [[TPLeeSuCache alloc] initWithURL:[base URLByAppendingPathComponent:@"ThreadsPulse/LeeSu-profiles.json"]];
        _headers = NSHashTable.weakObjectsHashTable; _scheduler = [TPLeeSuScheduler new]; _retryAfter = [NSMutableDictionary dictionary];
        _scheduler.pausedUntil = [NSUserDefaults.standardUserDefaults doubleForKey:@"TPLeeSuPausedUntil"];
        WKWebViewConfiguration *config = [WKWebViewConfiguration new];
        config.websiteDataStore = WKWebsiteDataStore.defaultDataStore;
        TPLeeSuReadyHandler *handler = [TPLeeSuReadyHandler new]; handler.target = self;
        [config.userContentController addScriptMessageHandler:handler name:@"TPLeeSuReady"];
        NSString *script = [NSString stringWithContentsOfURL:[TPResourceBundle() URLForResource:@"LeeSuBridge" withExtension:@"js"] encoding:NSUTF8StringEncoding error:nil];
        if (script) [config.userContentController addUserScript:[[WKUserScript alloc] initWithSource:script injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES]];
        _web = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 390, 800) configuration:config];
        _web.navigationDelegate = self; _web.UIDelegate = self;
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { [self requestPump]; }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            self.timerGeneration++; self.scheduledDeadline = 0; [self.scheduler cancelPending];
        }];
        [_web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://www.threads.com/"]]];
    }
    return self;
}
- (void)webView:(WKWebView *)web didStartProvisionalNavigation:(WKNavigation *)navigation {
    self.ready = NO; self.generation++; self.timerGeneration++; self.scheduledDeadline = 0;
    [self.scheduler cancelPending];
}
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.name isEqualToString:@"TPLeeSuReady"] || !message.frameInfo.mainFrame || !TPTrustedURL(message.frameInfo.request.URL)) return;
    if (![message.body isKindOfClass:NSNumber.class] || ![message.body boolValue]) return;
    self.ready = YES; [self requestPump];
}
- (void)webView:(WKWebView *)web didFinishNavigation:(WKNavigation *)navigation {
    if (!TPTrustedURL(web.URL)) { self.ready = NO; return; }
    [web evaluateJavaScript:@"window.TPLeeSu ? window.TPLeeSu.ready() : false" completionHandler:^(id value, NSError *error) {
        self.ready = !error && [value respondsToSelector:@selector(boolValue)] && [value boolValue];
        if (self.ready) { for (UIView *h in self.headers.allObjects) [self update:h]; [self requestPump]; }
    }];
}
- (void)webView:(WKWebView *)web decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))handler {
    NSURL *url = action.request.URL;
    // Permit only HTTPS web navigation. Authentication may pass through instagram.com.
    NSString *host = url.host.lowercaseString ?: @"";
    BOOL authHost = [host isEqualToString:@"instagram.com"] || [host hasSuffix:@".instagram.com"] || [host isEqualToString:@"facebook.com"] || [host hasSuffix:@".facebook.com"];
    BOOL allowed = TPTrustedURL(url) || ([url.scheme isEqualToString:@"https"] && authHost);
    handler(allowed ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}
- (WKWebView *)webView:(WKWebView *)web createWebViewWithConfiguration:(WKWebViewConfiguration *)config forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {
    if (!action.targetFrame) [web loadRequest:action.request]; return nil;
}
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)web { self.ready = NO; [web reload]; }
- (void)requestPump {
    // Many headers lay out in one scroll frame; refresh the viewport once per run loop.
    if (self.refreshScheduled) return; self.refreshScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{ self.refreshScheduled = NO; [self pump]; });
}
- (void)refreshVisibleRequests {
    NSMutableArray<UIView *> *onScreen = [NSMutableArray array];
    for (UIView *h in self.headers.allObjects) if (TPLeeSuHeaderOnScreen(h)) [onScreen addObject:h];
    NSArray<UIView *> *headers = [onScreen sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGFloat ay = [a convertRect:a.bounds toView:a.window].origin.y;
        CGFloat by = [b convertRect:b.bounds toView:b.window].origin.y;
        return ay < by ? NSOrderedAscending : ay > by ? NSOrderedDescending : NSOrderedSame;
    }];
    NSMutableArray *visible = [NSMutableArray array];
    NSTimeInterval now = TPNow();
    for (UIView *header in headers) {
        NSString *userID = objc_getAssociatedObject(header, TPLeeSuUserKey);
        if (userID.length && ![self.cache profileForID:userID now:now] && [self.retryAfter[userID] doubleValue] <= now) [visible addObject:userID];
    }
    [self.scheduler updateVisibleIDs:visible];
}
- (void)scheduleNext {
    NSTimeInterval now = TPNow(), delay = [self.scheduler delayUntilNextAt:now];
    if (delay < 0) { self.timerGeneration++; self.scheduledDeadline = 0; return; }
    NSTimeInterval deadline = now + delay;
    if (self.scheduledDeadline > 0 && self.scheduledDeadline <= deadline + 0.001) return;
    self.scheduledDeadline = deadline;
    NSUInteger token = ++self.timerGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token != self.timerGeneration) return;
        self.scheduledDeadline = 0; [self pump];
    });
}
- (void)pump {
    if (!self.ready || ![TPPrefs boolForKey:TPKeyLeeSu] || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    if (self.loginController.isViewLoaded && self.loginController.view.window) return;
    if (!TPTrustedURL(self.web.URL)) return;
    // Scrolling can reveal a previously laid-out cell without relaying out its header.
    self.refreshingHeaders = YES;
    for (UIView *h in self.headers.allObjects) if (TPLeeSuHeaderOnScreen(h)) [self update:h];
    self.refreshingHeaders = NO;
    [self refreshVisibleRequests];
    NSString *userID = [self.scheduler takeNextAt:TPNow()];
    if (!userID) { [self scheduleNext]; return; }
    NSUInteger generation = self.generation;
    [self.web callAsyncJavaScript:@"return window.TPLeeSu ? await window.TPLeeSu.profile(userID) : {_loginRequired:true};" arguments:@{@"userID": userID} inFrame:nil inContentWorld:WKContentWorld.pageWorld completionHandler:^(id result, NSError *error) {
        [self.scheduler finishID:userID];
        NSDictionary *info = [result isKindOfClass:NSDictionary.class] ? result : nil;
        if (generation != self.generation) { [self requestPump]; return; }
        if ([info[@"_rateLimited"] boolValue]) {
            self.scheduler.pausedUntil = TPNow() + 15 * 60;
            [NSUserDefaults.standardUserDefaults setDouble:self.scheduler.pausedUntil forKey:@"TPLeeSuPausedUntil"];
            [TPHUD toast:TPL(@"Lee Su Threads paused for 15 minutes (rate limit)")];
        } else if ([info[@"_loginRequired"] boolValue]) {
            self.ready = NO;
            [TPHUD toast:TPL(@"Connect Threads in Pulse → Lee Su Threads")];
        } else if (!error && info && !info[@"_error"] && ([info[@"location"] length] || [info[@"joined"] length])) {
            [self.cache store:info userID:userID now:TPNow()];
        } else { self.retryAfter[userID] = @(TPNow() + 5 * 60); }
        for (UIView *h in self.headers.allObjects) if (TPLeeSuHeaderOnScreen(h)) [self update:h];
        [self requestPump];
    }];
    [self scheduleNext];
}
- (void)showProfile:(UIButton *)button {
    NSString *userID = objc_getAssociatedObject(button, TPLeeSuUserKey);
    NSDictionary *p = [self.cache profileForID:userID now:TPNow()];
    NSString *message;
    if (p) message = [NSString stringWithFormat:@"%@: %@\n%@: %@", TPL(@"Based in"), [p[@"location"] length] ? TPLeeSuLocationLabel(p[@"location"]) : TPL(@"Not shared"), TPL(@"Joined"), [p[@"joined"] length] ? p[@"joined"] : @"—"];
    else message = TPL(@"Connect Threads in Pulse → Lee Su Threads");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:p[@"username"] ?: @"Lee Su Threads" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:TPL(@"Done") style:UIAlertActionStyleCancel handler:nil]];
    [[TPDownloader topViewController] presentViewController:alert animated:YES completion:nil];
}
- (void)update:(UIView *)header {
    UIButton *button = objc_getAssociatedObject(header, TPLeeSuButtonKey);
    if (![TPPrefs boolForKey:TPKeyLeeSu] || !header.window) { button.hidden = YES; return; }
    [self.headers addObject:header];
    // These object ivars and userPK selector were verified in Threads 455.0 metadata.
    UIView *picture = [TPDownloader ivarValue:header name:@"profilePictureView"];
    NSMutableArray *views = [NSMutableArray array]; if ([picture isKindOfClass:UIView.class]) [views addObject:picture];
    NSString *userID;
    for (NSUInteger i=0; i<views.count && i<40; i++) {
        UIView *v = views[i];
        id value = [TPDownloader safeValue:v key:@"userPK"];
        if ([value isKindOfClass:NSString.class] && [value rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound && [value length]) { userID = value; break; }
        [views addObjectsFromArray:v.subviews];
    }
    objc_setAssociatedObject(header, TPLeeSuUserKey, userID, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (!userID) { button.hidden = YES; return; }
    if (!button) {
        button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
        button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        button.backgroundColor = UIColor.secondarySystemBackgroundColor;
        button.layer.cornerRadius = 6;
        [button addTarget:self action:@selector(showProfile:) forControlEvents:UIControlEventTouchUpInside];
        [header addSubview:button]; objc_setAssociatedObject(header, TPLeeSuButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(button, TPLeeSuUserKey, userID, OBJC_ASSOCIATION_COPY_NONATOMIC);
    NSDictionary *profile = [self.cache profileForID:userID now:TPNow()];
    NSString *title = profile ? ([profile[@"location"] length] ? TPLeeSuLocationLabel(profile[@"location"]) : TPL(@"Not shared")) : @"⌖";
    // Upstream dates have month precision; use its current two-month new-user rule.
    if ([TPPrefs boolForKey:TPKeyLeeSuNew] && TPLeeSuRecentAt(profile[@"joined"], NSDate.date)) title = [@"🆕 " stringByAppendingString:title];
    [button setTitle:title forState:UIControlStateNormal];
    button.accessibilityLabel = [NSString stringWithFormat:@"Lee Su Threads: %@", title];
    // Reserve the existing gap after the author title. Never cover the author or menu.
    UIView *label = [TPDownloader ivarValue:header name:@"titleLabel"];
    UIView *more = [TPDownloader ivarValue:header name:@"$__lazy_storage_$_moreButton"];
    CGRect r = [label isKindOfClass:UIView.class] ? [header convertRect:label.bounds fromView:label] : CGRectZero;
    CGFloat start = CGRectGetMaxX(r) + 4;
    CGFloat end = [more isKindOfClass:UIView.class] && more.superview ? CGRectGetMinX([header convertRect:more.bounds fromView:more]) - 4 : header.bounds.size.width - 32;
    CGFloat width = MIN(100, end - start);
    button.hidden = CGRectIsEmpty(r) || width < 18;
    button.frame = CGRectMake(start, MAX(0, CGRectGetMidY(r) - 9), MAX(0, width), 18);
    // Compact headers have no title gap: keep a small badge at the avatar's lower edge.
    if (button.hidden && [picture isKindOfClass:UIView.class] && picture.superview) {
        CGRect avatar = [header convertRect:picture.bounds fromView:picture];
        if (avatar.size.width >= 24) {
            button.frame = CGRectMake(avatar.origin.x, MAX(0, CGRectGetMaxY(avatar) - 12), avatar.size.width, 12);
            button.hidden = NO;
        }
    }
    if (!button.hidden) [header bringSubviewToFront:button];
    if (!profile && self.ready && !self.refreshingHeaders) [self requestPump];
}
@end

@interface TPLeeSuProfilesController : UITableViewController
@property(nonatomic, strong) NSArray<NSDictionary *> *profiles;
@property(nonatomic, strong) NSArray<NSString *> *locations;
@property(nonatomic, strong) NSDictionary<NSString *, NSNumber *> *counts;
@end
@implementation TPLeeSuProfilesController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"Lee Su Threads";
    self.profiles = [TPLeeSuManager.shared.cache profilesAt:TPNow()];
    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    for (NSDictionary *p in self.profiles) { NSString *s = [p[@"location"] length] ? p[@"location"] : TPL(@"Not shared"); counts[s] = @([counts[s] integerValue] + 1); }
    self.counts = counts;
    self.locations = [counts.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 2; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return section == 0 ? self.locations.count : self.profiles.count; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section { return TPL(section == 0 ? @"Location Statistics" : @"Cached Profiles"); }
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    return section == 1 ? TPL(@"Public profile data stays on this device for 72 hours. New-user marks use month precision (current month and previous two months).") : nil;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"profile"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"profile"];
    if (path.section == 0) {
        NSString *s = self.locations[path.row]; cell.textLabel.text = [NSString stringWithFormat:@"%@ · %@", TPLeeSuLocationLabel(s), self.counts[s]]; cell.detailTextLabel.text = nil;
    } else {
        NSDictionary *p = self.profiles[path.row];
        NSString *name = [p[@"username"] length] ? [@"@" stringByAppendingString:p[@"username"]] : p[@"userID"];
        cell.textLabel.text = [NSString stringWithFormat:@"%@ · %@", name, [p[@"location"] length] ? TPLeeSuLocationLabel(p[@"location"]) : @"—"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@: %@", TPL(@"Joined"), p[@"joined"] ?: @"—"];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone; return cell;
}
@end

void TPLeeSuUpdateHeader(UIView *header) {
    if (![TPPrefs boolForKey:TPKeyLeeSu]) { ((UIButton *)objc_getAssociatedObject(header, TPLeeSuButtonKey)).hidden = YES; return; }
    [TPLeeSuManager.shared update:header];
}
void TPLeeSuViewportChanged(void) {
    // Do not initialize WebKit for unrelated scroll views or disabled features.
    if (gTPLeeSuManager && [TPPrefs boolForKey:TPKeyLeeSu]) [gTPLeeSuManager requestPump];
}
void TPLeeSuShowLogin(UIViewController *presenter) {
    TPLeeSuManager *m = TPLeeSuManager.shared;
    TPLeeSuLoginController *vc = [TPLeeSuLoginController new]; vc.web = m.web; m.loginController = vc;
    [m.web removeFromSuperview];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [presenter presentViewController:nav animated:YES completion:nil];
}
void TPLeeSuShowProfiles(UIViewController *presenter) {
    TPLeeSuProfilesController *vc = [[TPLeeSuProfilesController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    [presenter.navigationController pushViewController:vc animated:YES];
}
void TPLeeSuExport(UIViewController *presenter, UIView *source) {
    NSDictionary *root = @{@"app":@"ThreadsPulse-LeeSu", @"profiles":[TPLeeSuManager.shared.cache profilesAt:TPNow()]};
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:nil];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"LeeSu-Profiles.json"]];
    if (![data writeToURL:url atomically:YES]) { [TPHUD toast:TPL(@"Export failed")]; return; }
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    activity.popoverPresentationController.sourceView = source; activity.popoverPresentationController.sourceRect = source.bounds;
    [presenter presentViewController:activity animated:YES completion:nil];
}
void TPLeeSuClear(void) {
    TPLeeSuManager *m = TPLeeSuManager.shared;
    m.generation++; [m.cache clear]; [m.scheduler cancelPending]; [m.retryAfter removeAllObjects];
    for (UIView *header in m.headers.allObjects) {
        ((UIButton *)objc_getAssociatedObject(header, TPLeeSuButtonKey)).hidden = YES;
    }
    [TPHUD toast:TPL(@"Profile cache cleared")];
}
