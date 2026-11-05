#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString* const BHTTargetAppVersion;
FOUNDATION_EXPORT NSString* const BHTTargetAppBuild;

// Account/network hooks only support the app build whose interfaces were
// audited. An unrelated build must not inherit private-layout support.
FOUNDATION_EXPORT BOOL BHTHostVersionIsSupported(NSString* _Nullable version,
                                               NSString* _Nullable build);
FOUNDATION_EXPORT BOOL BHTIsSupportedHost(void);
FOUNDATION_EXPORT BOOL BHTAccountRemovalMethodIsSupported(Method _Nullable method);

NS_ASSUME_NONNULL_END
