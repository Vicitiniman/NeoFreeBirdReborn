#import "BHTHostCompatibility.h"
#include <string.h>

NSString* const BHTTargetAppVersion = @"12.40.1";
NSString* const BHTTargetAppBuild = @"1";

BOOL BHTHostVersionIsSupported(NSString* version, NSString* build) {
    return [version isKindOfClass:NSString.class] &&
           [build isKindOfClass:NSString.class] &&
           [version isEqualToString:BHTTargetAppVersion] &&
           [build isEqualToString:BHTTargetAppBuild];
}

BOOL BHTIsSupportedHost(void) {
    return BHTHostVersionIsSupported(
        [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
        [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"]);
}

BOOL BHTAccountRemovalMethodIsSupported(Method method) {
    if (!method) return NO;
    NSMethodSignature* signature =
        [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    return signature.numberOfArguments == 5 &&
           strcmp(signature.methodReturnType, "v") == 0 &&
           [signature getArgumentTypeAtIndex:2][0] == '@' &&
           strcmp([signature getArgumentTypeAtIndex:3], "q") == 0 &&
           strcmp([signature getArgumentTypeAtIndex:4], "@?") == 0;
}
