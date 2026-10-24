#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, BHTWebSessionVaultReadStatus) {
    BHTWebSessionVaultReadComplete,
    BHTWebSessionVaultReadUnavailable,
};
typedef BHTWebSessionVaultReadStatus (^BHTWebSessionVaultRead)(NSArray<NSDictionary*>* _Nullable * records);
typedef BOOL (^BHTWebSessionVaultWrite)(NSDictionary* session);
typedef BOOL (^BHTWebSessionVaultRemove)(uint64_t userID);

// One device-only Keychain item per numeric account ID. Read failures are
// retryable, never a cached empty account list. No credentials enter defaults.
@interface BHTWebSessionVault : NSObject
- (instancetype)init;
// Injectable persistence permits restart/locked-device regressions without
// touching the test machine's Keychain or using real account credentials.
- (instancetype)initWithRead:(BHTWebSessionVaultRead)read
                       write:(BHTWebSessionVaultWrite)write
                      remove:(BHTWebSessionVaultRemove)remove;
- (NSArray<NSDictionary*>*)sessions;
- (nullable NSDictionary*)sessionForUserID:(uint64_t)userID;
- (BOOL)saveSession:(NSDictionary*)session;
- (BOOL)removeUserID:(uint64_t)userID;
- (BOOL)isRemovedUserID:(uint64_t)userID;
- (BOOL)updateSession:(NSDictionary*)session ifAuthMatches:(NSString*)auth;
- (void)retryAfterUnlock;
@property(nonatomic, readonly) BOOL readUnavailable;
@end
NS_ASSUME_NONNULL_END
