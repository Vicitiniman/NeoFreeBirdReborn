#import "Login/BHTWebSessionVault.h"
#import "Login/BHTWebSessionSecurity.h"
#import <Security/Security.h>

static NSString* const BHTVaultService = @"com.neofreebird.secure-web-session.v2";
static NSDictionary* BHTVaultQuery(NSString* service, NSString* account) {
    NSMutableDictionary* query = [@{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: service,
    } mutableCopy];
    if (account) query[(__bridge id)kSecAttrAccount] = account;
    return query;
}

static BOOL BHTVaultWrite(NSDictionary* session) {
    NSString* account = [session[@"userID"] stringValue];
    NSData* data = [NSPropertyListSerialization dataWithPropertyList:session
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    if (!data || data.length > 8192) return NO;
    NSDictionary* query = BHTVaultQuery(BHTVaultService, account);
    NSDictionary* update = @{
        (__bridge id)kSecValueData: data,
        // Native background refresh must still see the session while the
        // phone is locked. It remains device-only and unavailable until the
        // first unlock following a reboot.
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    };
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)update);
    if (status == errSecItemNotFound) {
        NSMutableDictionary* item = [query mutableCopy];
        [item addEntriesFromDictionary:update];
        status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    }
    return status == errSecSuccess;
}

static NSDictionary* BHTVaultDecode(id data) {
    if (![data isKindOfClass:NSData.class] || [data length] > 8192) return nil;
    return BHTWebSessionValidatedSession([NSPropertyListSerialization propertyListWithData:data
        options:NSPropertyListImmutable format:NULL error:nil]);
}

static BHTWebSessionVaultReadStatus BHTVaultRead(NSArray** records) {
    NSMutableDictionary* query = [BHTVaultQuery(BHTVaultService, nil) mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecReturnAttributes] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitAll;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    id items = CFBridgingRelease(result);
    if (status != errSecSuccess && status != errSecItemNotFound) return BHTWebSessionVaultReadUnavailable;
    NSMutableArray* sessions = [NSMutableArray array];
    NSArray* rows = [items isKindOfClass:NSArray.class] ? items :
        ([items isKindOfClass:NSDictionary.class] ? @[items] : @[]);
    for (id item in rows) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSDictionary* session = BHTVaultDecode(item[(__bridge id)kSecValueData]);
        if (session && [[session[@"userID"] stringValue] isEqual:item[(__bridge id)kSecAttrAccount]]) {
            [sessions addObject:session];
        }
    }

    // Upgrade the beta 65 single-session item without asking the user to
    // sign in again. Never remove the legacy item until its replacement is
    // durably stored, and never overwrite a newer per-account session.
    NSDictionary* legacyQuery = BHTVaultQuery(@"com.neofreebird.secure-web-session.v1", @"active");
    NSMutableDictionary* legacyRead = [legacyQuery mutableCopy];
    legacyRead[(__bridge id)kSecReturnData] = @YES;
    legacyRead[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    result = NULL;
    OSStatus legacyStatus = SecItemCopyMatching((__bridge CFDictionaryRef)legacyRead, &result);
    NSData* legacyData = CFBridgingRelease(result);
    BOOL complete = legacyStatus == errSecSuccess || legacyStatus == errSecItemNotFound;
    NSDictionary* legacy = legacyStatus == errSecSuccess ? BHTVaultDecode(legacyData) : nil;
    if (legacy) {
        BOOL alreadySaved = NO;
        for (NSDictionary* session in sessions) {
            if ([session[@"userID"] isEqual:legacy[@"userID"]]) { alreadySaved = YES; break; }
        }
        BOOL migrated = alreadySaved || BHTVaultWrite(legacy);
        if (!alreadySaved) [sessions addObject:legacy];
        if (migrated) SecItemDelete((__bridge CFDictionaryRef)legacyQuery);
        else complete = NO;
    }
    *records = [sessions copy];
    return complete ? BHTWebSessionVaultReadComplete : BHTWebSessionVaultReadUnavailable;
}

@interface BHTWebSessionVault ()
@property(nonatomic, copy) BHTWebSessionVaultRead readBlock;
@property(nonatomic, copy) BHTWebSessionVaultWrite writeBlock;
@property(nonatomic, copy) BHTWebSessionVaultRemove removeBlock;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, NSDictionary*>* cache;
@property(nonatomic, strong) NSMutableSet<NSNumber*>* removed;
@property(nonatomic) BOOL loaded;
@property(nonatomic) BOOL readUnavailable;
@property(nonatomic) NSTimeInterval retryTime;
@end

@implementation BHTWebSessionVault
- (instancetype)init {
    return [self initWithRead:^BHTWebSessionVaultReadStatus(NSArray** records) {
        return BHTVaultRead(records);
    } write:^BOOL(NSDictionary* session) { return BHTVaultWrite(session); }
    remove:^BOOL(uint64_t userID) {
        NSMutableDictionary* legacy = [BHTVaultQuery(@"com.neofreebird.secure-web-session.v1", @"active") mutableCopy];
        legacy[(__bridge id)kSecReturnData] = @YES;
        CFTypeRef data = NULL;
        OSStatus read = SecItemCopyMatching((__bridge CFDictionaryRef)legacy, &data);
        NSDictionary* old = BHTVaultDecode(CFBridgingRelease(data));
        if (read != errSecSuccess && read != errSecItemNotFound) return NO;
        if ([old[@"userID"] unsignedLongLongValue] == userID) {
            OSStatus removal = SecItemDelete((__bridge CFDictionaryRef)BHTVaultQuery(@"com.neofreebird.secure-web-session.v1", @"active"));
            if (removal != errSecSuccess && removal != errSecItemNotFound) return NO;
        }
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)BHTVaultQuery(BHTVaultService, [@(userID) stringValue]));
        return status == errSecSuccess || status == errSecItemNotFound;
    }];
}

- (instancetype)initWithRead:(BHTWebSessionVaultRead)read
                       write:(BHTWebSessionVaultWrite)write
                      remove:(BHTWebSessionVaultRemove)remove {
    if ((self = [super init])) {
        _readBlock = [read copy]; _writeBlock = [write copy]; _removeBlock = [remove copy];
        _cache = [NSMutableDictionary dictionary]; _removed = [NSMutableSet set];
    }
    return self;
}

- (void)loadIfNeeded {
    if (self.loaded || NSProcessInfo.processInfo.systemUptime < self.retryTime) return;
    NSArray* records = nil;
    BHTWebSessionVaultReadStatus status = self.readBlock(&records);
    for (id record in records) {
        NSDictionary* session = BHTWebSessionValidatedSession(record);
        NSNumber* userID = session[@"userID"];
        if (session && ![self.removed containsObject:userID]) self.cache[userID] = session;
    }
    self.loaded = status == BHTWebSessionVaultReadComplete;
    self.readUnavailable = !self.loaded;
    // Avoid a repeated locked-Keychain call for every account gate; unlock
    // and foreground notifications explicitly reset this short backoff.
    self.retryTime = self.loaded ? 0 : NSProcessInfo.processInfo.systemUptime + 1.0;
}

- (NSArray*)sessions {
    @synchronized(self) { [self loadIfNeeded]; return [self.cache.allValues copy]; }
}
- (NSDictionary*)sessionForUserID:(uint64_t)userID {
    @synchronized(self) { [self loadIfNeeded]; return self.cache[@(userID)]; }
}
- (BOOL)saveSession:(NSDictionary*)value {
    NSDictionary* session = BHTWebSessionValidatedSession(value);
    if (!session) return NO;
    @synchronized(self) {
        [self loadIfNeeded];
        if (!self.writeBlock(session)) return NO;
        self.cache[session[@"userID"]] = session;
        [self.removed removeObject:session[@"userID"]];
        return YES;
    }
}
- (BOOL)removeUserID:(uint64_t)userID {
    @synchronized(self) {
        if (!userID || !self.removeBlock(userID)) return NO;
        [self.cache removeObjectForKey:@(userID)];
        [self.removed addObject:@(userID)];
        return YES;
    }
}
- (BOOL)isRemovedUserID:(uint64_t)userID {
    @synchronized(self) { return [self.removed containsObject:@(userID)]; }
}
- (BOOL)updateSession:(NSDictionary*)session ifAuthMatches:(NSString*)auth {
    @synchronized(self) {
        NSDictionary* current = [self sessionForUserID:[session[@"userID"] unsignedLongLongValue]];
        if (![current[@"auth"] isEqual:auth]) return NO;
        return [self saveSession:session];
    }
}
- (void)retryAfterUnlock {
    @synchronized(self) { self.loaded = NO; self.retryTime = 0; }
}
@end
