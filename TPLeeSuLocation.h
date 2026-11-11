#import <Foundation/Foundation.h>

/// Prepend a flag to an exactly recognized country/territory, preserving its name.
/// Unknown and unshared locations remain unchanged; no city/sub-string inference.
NSString *TPLeeSuLocationLabel(NSString *location);
