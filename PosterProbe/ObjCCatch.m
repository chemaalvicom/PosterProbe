#import "ObjCCatch.h"
#import <objc/runtime.h>
#include <signal.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>

static char gCrumb[2048] = "inicio";
static char gCrashPath[1024] = "";
static volatile sig_atomic_t gExceptionWritten = 0;

static void writeAll(int fd, const char *s) {
    size_t n = strlen(s);
    while (n > 0) {
        ssize_t w = write(fd, s, n);
        if (w <= 0) return;
        s += w; n -= (size_t)w;
    }
}

static void signalHandler(int sig) {
    if (!gExceptionWritten && gCrashPath[0]) {
        const char *kind = "Señal desconocida";
        switch (sig) {
            case SIGSEGV: kind = "SIGSEGV (acceso a memoria inválido)"; break;
            case SIGBUS:  kind = "SIGBUS (acceso a memoria inválido)"; break;
            case SIGABRT: kind = "SIGABRT (abortada)"; break;
            case SIGILL:  kind = "SIGILL (error fatal de Swift)"; break;
            case SIGTRAP: kind = "SIGTRAP (error fatal de Swift)"; break;
            case SIGFPE:  kind = "SIGFPE (error aritmético)"; break;
        }
        int fd = open(gCrashPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd >= 0) {
            writeAll(fd, "Cierre por señal: ");
            writeAll(fd, kind);
            writeAll(fd, "\nÚltimo paso: ");
            writeAll(fd, gCrumb);
            writeAll(fd, "\n");
            close(fd);
        }
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

static void exceptionHandler(NSException *e) {
    if (!gCrashPath[0]) return;
    NSString *s = [NSString stringWithFormat:
        @"Excepción no capturada: %@: %@\nÚltimo paso: %s\n\nPila:\n%@\n",
        e.name, e.reason ?: @"", gCrumb,
        [e.callStackSymbols componentsJoinedByString:@"\n"]];
    [s writeToFile:@(gCrashPath) atomically:NO encoding:NSUTF8StringEncoding error:nil];
    gExceptionWritten = 1;
}

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

+ (NSArray<NSString *> *)safePropertyNamesOfClass:(Class)cls {
    NSMutableOrderedSet *out = [NSMutableOrderedSet orderedSet];
    for (Class c = cls; c && c != [NSObject class]; c = class_getSuperclass(c)) {
        unsigned int n = 0;
        objc_property_t *props = class_copyPropertyList(c, &n);
        for (unsigned int i = 0; i < n; i++) {
            const char *a = property_getAttributes(props[i]);
            if (!a || a[0] != 'T') continue;
            char t = a[1];
            BOOL weak = strstr(a, ",W") != NULL;
            BOOL ok = NO;
            if (t == '@') ok = !weak;                                   // objeto fuerte
            else if (strchr("cislqCISLQfdB", t)) ok = YES;              // escalar
            else if (strncmp(a + 1, "{CG", 3) == 0) ok = YES;          // CGRect/CGPoint/CGSize
            if (ok) [out addObject:[NSString stringWithUTF8String:property_getName(props[i])]];
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
            if (method_getNumberOfArguments(ms[i]) == 2) {
                [out addObject:NSStringFromSelector(method_getName(ms[i]))];
            }
        }
        free(ms);
    }
    return out.array;
}

+ (NSData *)jsonData:(id)object {
    @try {
        if (![NSJSONSerialization isValidJSONObject:object]) return nil;
        return [NSJSONSerialization dataWithJSONObject:object
                                               options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                 error:nil];
    } @catch (NSException *e) {
        return nil;
    }
}

+ (NSData *)archive:(id)object {
    @try {
        return [NSKeyedArchiver archivedDataWithRootObject:object requiringSecureCoding:NO error:nil];
    } @catch (NSException *e) {
        return nil;
    }
}

+ (NSString *)describe:(id)object {
    @try {
        return [object description] ?: @"";
    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"<description lanzó %@>", e.name];
    }
}

+ (void)installCrashHandlerAtPath:(NSString *)path {
    strlcpy(gCrashPath, path.fileSystemRepresentation, sizeof gCrashPath);
    NSSetUncaughtExceptionHandler(&exceptionHandler);
    int sigs[] = {SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGTRAP, SIGFPE};
    for (size_t i = 0; i < sizeof sigs / sizeof sigs[0]; i++) signal(sigs[i], signalHandler);
}

+ (void)mark:(NSString *)step {
    const char *s = step.UTF8String;
    strlcpy(gCrumb, s ? s : "", sizeof gCrumb);
}

@end
