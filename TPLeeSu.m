#import "TPLeeSu.h"
#import "TPLeeSuCache.h"
#import "TPLeeSuLocation.h"
#import "TPPrefs.h"
#import "TPDownloader.h"
#import "TPHUD.h"
#import "TPLocalization.h"
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

static const void *TPLeeSuButtonKey = &TPLeeSuButtonKey;
static const void *TPLeeSuUserKey = &TPLeeSuUserKey;
static NSTimeInterval TPNow(void) { return NSDate.date.timeIntervalSince1970; }
static BOOL TPTrustedURL(NSURL *url) {
    return [url.scheme isEqualToString:@"https"] &&
        ([(url.host ?: @"") isEqualToString:@"www.threads.com"] || [url.host isEqualToString:@"threads.com"]);
}

@interface TPLeeSuManager : NSObject <WKNavigationDelegate, WKUIDelegate>
@property(nonatomic, strong) WKWebView *web;
@property(nonatomic, strong) TPLeeSuCache *cache;
@property(nonatomic, strong) NSHashTable<UIView *> *headers;
@property(nonatomic, strong) NSMutableArray<NSString *> *queue;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *retryAfter;
@property(nonatomic, copy) NSString *activeID;
@property(nonatomic) BOOL busy;
@property(nonatomic) BOOL ready;
@property(nonatomic) BOOL scheduled;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSTimeInterval pausedUntil;
@property(nonatomic, weak) UIViewController *loginController;
+ (instancetype)shared;
- (void)update:(UIView *)header;
- (void)pump;
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
- (void)cancel { [self dismissViewControllerAnimated:YES completion:^{ [self.web removeFromSuperview]; }]; }
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
    dispatch_once(&once, ^{ m = [TPLeeSuManager new]; }); return m;
}
- (instancetype)init {
    if ((self = [super init])) {
        NSURL *base = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        _cache = [[TPLeeSuCache alloc] initWithURL:[base URLByAppendingPathComponent:@"ThreadsPulse/LeeSu-profiles.json"]];
        _headers = NSHashTable.weakObjectsHashTable; _queue = [NSMutableArray array]; _retryAfter = [NSMutableDictionary dictionary];
        _pausedUntil = [NSUserDefaults.standardUserDefaults doubleForKey:@"TPLeeSuPausedUntil"];
        WKWebViewConfiguration *config = [WKWebViewConfiguration new];
        config.websiteDataStore = WKWebsiteDataStore.defaultDataStore;
        NSString *script = [NSString stringWithContentsOfURL:[TPResourceBundle() URLForResource:@"LeeSuBridge" withExtension:@"js"] encoding:NSUTF8StringEncoding error:nil];
        if (script) [config.userContentController addUserScript:[[WKUserScript alloc] initWithSource:script injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES]];
        _web = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 390, 800) configuration:config];
        _web.navigationDelegate = self; _web.UIDelegate = self;
        [_web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://www.threads.com/"]]];
    }
    return self;
}
- (void)webView:(WKWebView *)web didFinishNavigation:(WKNavigation *)navigation {
    if (!TPTrustedURL(web.URL)) { self.ready = NO; return; }
    [web evaluateJavaScript:@"window.TPLeeSu ? window.TPLeeSu.ready() : false" completionHandler:^(id value, NSError *error) {
        self.ready = !error && [value respondsToSelector:@selector(boolValue)] && [value boolValue];
        if (self.ready) { for (UIView *h in self.headers.allObjects) [self update:h]; [self pump]; }
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
- (void)schedule {
    if (self.scheduled) return; self.scheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ self.scheduled = NO; [self pump]; });
}
- (BOOL)visibleID:(NSString *)userID {
    for (UIView *h in self.headers.allObjects) if (h.window && [objc_getAssociatedObject(h, TPLeeSuUserKey) isEqual:userID]) return YES;
    return NO;
}
- (void)pump {
    if (self.busy || self.scheduled || !self.ready || ![TPPrefs boolForKey:TPKeyLeeSu]) return;
    if (self.pausedUntil > TPNow()) {
        self.scheduled = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((self.pausedUntil - TPNow() + 1) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self.scheduled = NO;
            for (UIView *h in self.headers.allObjects) [self update:h];
            [self pump];
        });
        return;
    }
    NSString *userID;
    while (self.queue.count) {
        NSString *candidate = self.queue.firstObject; [self.queue removeObjectAtIndex:0];
        if ([self visibleID:candidate] && ![self.cache profileForID:candidate now:TPNow()] && [self.retryAfter[candidate] doubleValue] <= TPNow()) { userID = candidate; break; }
    }
    if (!userID || !TPTrustedURL(self.web.URL)) return;
    self.busy = YES; self.activeID = userID;
    NSUInteger generation = self.generation;
    [self.web callAsyncJavaScript:@"return window.TPLeeSu ? await window.TPLeeSu.profile(userID) : {_loginRequired:true};" arguments:@{@"userID": userID} inFrame:nil inContentWorld:WKContentWorld.pageWorld completionHandler:^(id result, NSError *error) {
        self.busy = NO; self.activeID = nil;
        NSDictionary *info = [result isKindOfClass:NSDictionary.class] ? result : nil;
        if (generation != self.generation) { [self schedule]; return; }
        if ([info[@"_rateLimited"] boolValue]) {
            self.pausedUntil = TPNow() + 15 * 60;
            [NSUserDefaults.standardUserDefaults setDouble:self.pausedUntil forKey:@"TPLeeSuPausedUntil"];
            [TPHUD toast:TPL(@"Lee Su Threads paused for 15 minutes (rate limit)")];
        } else if ([info[@"_loginRequired"] boolValue]) {
            self.ready = NO;
            [TPHUD toast:TPL(@"Connect Threads in Pulse → Lee Su Threads")];
        } else if (!error && info && !info[@"_error"] && ([info[@"location"] length] || [info[@"joined"] length])) {
            [self.cache store:info userID:userID now:TPNow()];
        } else { self.retryAfter[userID] = @(TPNow() + 5 * 60); }
        for (UIView *h in self.headers.allObjects) [self update:h];
        [self schedule];
    }];
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
    if (!profile && self.ready && ![self.activeID isEqual:userID] && ![self.queue containsObject:userID] && [self.retryAfter[userID] doubleValue] <= TPNow()) {
        if (self.queue.count >= 100) [self.queue removeObjectAtIndex:0];
        [self.queue addObject:userID]; [self schedule];
    }
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
    m.generation++; [m.cache clear]; [m.queue removeAllObjects]; [m.retryAfter removeAllObjects];
    for (UIView *header in m.headers.allObjects) {
        ((UIButton *)objc_getAssociatedObject(header, TPLeeSuButtonKey)).hidden = YES;
    }
    [TPHUD toast:TPL(@"Profile cache cleared")];
}
