#import "TPLocalization.h"
#import <dlfcn.h>

static NSBundle *TPBundle(void) {
    static NSBundle *bundle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *const rel = @"/Library/Application Support/ThreadsPulse/ThreadsPulse.bundle";
        NSMutableArray<NSString *> *paths = [NSMutableArray array];

        // Roothide：越獄根目錄是隨機路徑。有 libroothide 時直接問 jbroot()
        const char *(*jbroot)(const char *) = dlsym(RTLD_DEFAULT, "jbroot");
        if (jbroot) {
            const char *r = jbroot(rel.fileSystemRepresentation);
            if (r) [paths addObject:[NSString stringWithUTF8String:r]];
        }

        // 從 dylib 自己的位置推算越獄根目錄（Roothide／無根／有根都適用）
        Dl_info me;
        if (dladdr((const void *)&TPBundle, &me) && me.dli_fname) {
            NSString *dylib = [NSString stringWithUTF8String:me.dli_fname];
            for (NSString *marker in @[@"/Library/MobileSubstrate/DynamicLibraries/", @"/usr/lib/TweakInject/"]) {
                NSRange r = [dylib rangeOfString:marker];
                if (r.location != NSNotFound) {
                    [paths addObject:[[dylib substringToIndex:r.location] stringByAppendingString:rel]];
                    break;
                }
            }
        }

        [paths addObject:[@"/var/jb" stringByAppendingString:rel]];   // 無根越獄
        [paths addObject:rel];                                         // 有根越獄

        // 側載：bundle 放在 App 內（與 dylib 同層或 Frameworks 內）
        NSString *inApp = [NSBundle.mainBundle pathForResource:@"ThreadsPulse" ofType:@"bundle"];
        if (inApp) [paths addObject:inApp];
        [paths addObject:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/ThreadsPulse.bundle"]];

        Dl_info info;
        if (dladdr((const void *)&TPBundle, &info) && info.dli_fname) {
            NSString *dir = [[NSString stringWithUTF8String:info.dli_fname] stringByDeletingLastPathComponent];
            [paths addObject:[dir stringByAppendingPathComponent:@"ThreadsPulse.bundle"]];
        }

        for (NSString *p in paths) {
            if ([NSFileManager.defaultManager fileExistsAtPath:p]) {
                bundle = [NSBundle bundleWithPath:p];
                if (bundle) break;
            }
        }
    });
    return bundle;
}

NSString *TPLocalized(NSString *key) {
    NSBundle *b = TPBundle();
    if (!b) return key;
    return [b localizedStringForKey:key value:key table:nil];
}

NSBundle *TPResourceBundle(void) { return TPBundle(); }
