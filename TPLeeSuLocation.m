#import "TPLeeSuLocation.h"
#import "TPLocalization.h"

static NSString *TPLeeSuNormalizeLocation(NSString *location) {
    NSArray *parts = [location componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray *words = [NSMutableArray array];
    for (NSString *part in parts) if (part.length) [words addObject:part];
    return [[[words componentsJoinedByString:@" "] precomposedStringWithCanonicalMapping] lowercaseString];
}

NSString *TPLeeSuLocationLabel(NSString *location) {
    if (![location isKindOfClass:NSString.class] || !location.length) return @"";
    static NSDictionary<NSString *, NSString *> *lookup;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *url = [TPResourceBundle() URLForResource:@"LeeSuLocationFlags" withExtension:@"json"];
        NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
        id source = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSMutableDictionary *map = [NSMutableDictionary dictionary];
        if ([source isKindOfClass:NSDictionary.class]) {
            for (NSString *flag in source) {
                NSDictionary *entry = source[flag];
                if (![entry isKindOfClass:NSDictionary.class]) continue;
                for (NSString *key in @[@"en", @"zh_TW", @"zh_CN", @"ja", @"ko", @"common"]) {
                    id names = entry[key];
                    if (![names isKindOfClass:NSArray.class]) continue;
                    for (id name in names) if ([name isKindOfClass:NSString.class] && [name length])
                        map[TPLeeSuNormalizeLocation(name)] = flag;
                }
                if ([entry[@"iso"] isKindOfClass:NSString.class]) map[TPLeeSuNormalizeLocation(entry[@"iso"])] = flag;
            }
        }
        // Common Traditional Chinese and Japanese variants absent from the table.
        map[@"臺灣"] = @"🇹🇼";
        map[@"台湾"] = @"🇹🇼";
        lookup = [map copy];
    });
    NSString *flag = lookup[TPLeeSuNormalizeLocation(location)];
    NSString *name = [location stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return flag ? [NSString stringWithFormat:@"%@ %@", flag, name] : location;
}
