#import "ObjCCatch.h"
#import <objc/runtime.h>

@implementation ObjCCatch

+ (NSString *)run:(NS_NOESCAPE void (^)(void))block {
    @try {
        block();
        return nil;
    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"%@: %@", e.name, e.reason ?: @""];
    }
}

+ (id)valueOf:(id)object forKey:(NSString *)key error:(NSString **)error {
    @try {
        return [object valueForKey:key];
    } @catch (NSException *e) {
        if (error) *error = [NSString stringWithFormat:@"%@: %@", e.name, e.reason ?: @""];
        return nil;
    }
}

+ (NSArray<NSString *> *)propertyNamesOfClass:(Class)cls {
    NSMutableOrderedSet *out = [NSMutableOrderedSet orderedSet];
    for (Class c = cls; c && c != [NSObject class]; c = class_getSuperclass(c)) {
        unsigned int n = 0;
        objc_property_t *props = class_copyPropertyList(c, &n);
        for (unsigned int i = 0; i < n; i++) {
            [out addObject:[NSString stringWithUTF8String:property_getName(props[i])]];
        }
        free(props);
    }
    return out.array;
}

+ (NSArray<NSString *> *)getterNamesOfClass:(Class)cls {
    NSMutableOrderedSet *out = [NSMutableOrderedSet orderedSet];
    for (Class c = cls; c && c != [NSObject class]; c = class_getSuperclass(c)) {
        unsigned int n = 0;
        Method *ms = class_copyMethodList(c, &n);
        for (unsigned int i = 0; i < n; i++) {
            if (method_getNumberOfArguments(ms[i]) == 2) { // self + _cmd
                [out addObject:NSStringFromSelector(method_getName(ms[i]))];
            }
        }
        free(ms);
    }
    return out.array;
}

@end
