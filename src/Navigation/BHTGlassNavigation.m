#import "BHTGlassNavigation.h"
#import "Core/BHTManager.h"
#import "Core/BHTSettings.h"
#import "Compatibility/BHTHostCompatibility.h"
#import "CustomTabBar/CustomTabBarUtility.h"
#import "Likes/BHTLikesTab.h"
#import "ThemeColor/Palette.h"
#import "ThemeColor/BHTThemePresets.h"
#import "Headers/Helpers.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/loader.h>
#include <string.h>

static BOOL BHTGlassABIIsSupported(void) {
    static BOOL supported;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        void* symbol = dlsym(RTLD_DEFAULT,
            "$s11XNavigation16TabBarControllerC11replaceTabs_9selectingySayAC0B0VG_AC0B10IdentifierVtF");
        Dl_info info = {0};
        if (!symbol || !dladdr(symbol, &info) || !info.dli_fbase || !info.dli_fname ||
            !strstr(info.dli_fname, "/XServiceLibraries.framework/XServiceLibraries")) return;
        const struct mach_header_64* header = info.dli_fbase;
        if (header->magic != MH_MAGIC_64 || header->ncmds > 4096 || header->sizeofcmds > 1048576) return;
        const uint8_t expectedUUID[16] = {0x97, 0x79, 0xc1, 0x06, 0xb1, 0xda, 0x3e, 0x48,
                                          0x99, 0x5d, 0x4a, 0xea, 0xae, 0xa9, 0x57, 0x4a};
        const uint8_t* cursor = (const uint8_t*)(header + 1);
        const uint8_t* end = cursor + header->sizeofcmds;
        for (uint32_t i = 0; i < header->ncmds && cursor + sizeof(struct load_command) <= end; i++) {
            const struct load_command* command = (const struct load_command*)cursor;
            if (command->cmdsize < sizeof(*command) || cursor + command->cmdsize > end) return;
            if (command->cmd == LC_UUID && command->cmdsize >= sizeof(struct uuid_command)) {
                supported = memcmp(((const struct uuid_command*)command)->uuid, expectedUUID, sizeof(expectedUUID)) == 0;
                return;
            }
            cursor += command->cmdsize;
        }
    });
    return supported;
}

#if defined(__arm64__)
// replaceTabs(_:selecting:) takes a concrete Swift Array word and the two
// String words of TabIdentifier. Its receiver is in swiftself (x20).
__asm__(
    ".text\n.p2align 2\n"
    ".private_extern _BHTInvokeGlassReplaceTabs\n"
    "_BHTInvokeGlassReplaceTabs:\n"
    "stp x29, x30, [sp, #-32]!\n"
    "str x20, [sp, #16]\n"
    "mov x29, sp\n"
    "mov x20, x3\n"
    "blr x4\n"
    "ldr x20, [sp, #16]\n"
    "ldp x29, x30, [sp], #32\n"
    "ret\n"
);
#endif

@interface BHTGlassNavigationRuntime : NSObject
+ (BOOL)needsUpdateForController:(id)controller account:(id)account generation:(NSUInteger)generation;
+ (NSArray*)applyToController:(id)controller account:(id)account generation:(NSUInteger)generation
                 visiblePages:(NSArray*)pages registry:(NSArray*)registry
              settingsFactory:(UIViewController* (^)(void))settingsFactory
                 likesFactory:(UIViewController* (^)(void))likesFactory;
+ (NSDictionary*)diagnosticSnapshot;
@end

static NSHashTable<UIViewController*>* BHTGlassOwners(void) {
    static NSHashTable* owners;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        owners = [NSHashTable weakObjectsHashTable];
        for (NSString* name in @[BHTThemeDidChangeNotification, BHTSettingsProfileDidApplyNotification]) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(__unused NSNotification* notification) { BHTRefreshGlassNavigation(); }];
        }
    });
    return owners;
}

static id BHTNavigationObject(id object, NSString* name) {
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod([object class], selector);
    char type[16] = {0};
    if (!method || method_getNumberOfArguments(method) != 2) return nil;
    method_getReturnType(method, type, sizeof(type));
    return type[0] == '@' ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

static UIViewController* BHTFindGlassController(UIViewController* owner, NSUInteger depth, NSUInteger* budget) {
    if (!owner || depth > 6 || *budget == 0) return nil;
    (*budget)--;
    Class wanted = NSClassFromString(@"XNavigation.TabBarController");
    if (wanted && [owner isKindOfClass:wanted]) return owner;
    for (UIViewController* child in owner.childViewControllers) {
        UIViewController* found = BHTFindGlassController(child, depth + 1, budget);
        if (found) return found;
    }
    return nil;
}

static id BHTNavigationAccount(UIViewController* owner) {
    id account = BHTNavigationObject(owner, @"account");
    if (!account) account = BHTNavigationObject(BHTNavigationObject(owner, @"appNavigation"), @"account");
    if (!account) {
        Class host = NSClassFromString(@"T1HostViewController");
        id shared = [host respondsToSelector:NSSelectorFromString(@"sharedHostViewController")]
            ? ((id (*)(id, SEL))objc_msgSend)(host, NSSelectorFromString(@"sharedHostViewController")) : nil;
        account = BHTNavigationObject(shared, @"currentAccount");
    }
    return account;
}

void BHTUpdateGlassNavigation(UIViewController* owner) {
    if (!NSThread.isMainThread || !BHTIsSupportedHost() || !owner.isViewLoaded || !owner.view.window) return;
    if (!BHTGlassABIIsSupported()) return;
    NSUInteger budget = 32;
    UIViewController* controller = BHTFindGlassController(owner, 0, &budget);
    if (!controller) return;
    [BHTGlassOwners() addObject:owner];
    static char originalTintKey;
    BOOL themed = [BHTSettings boolForKey:@"tab_bar_theming"] ||
        [Palette customThemeColorForRole:BHTThemeColorBackgroundKey] != nil;
    id original = objc_getAssociatedObject(controller, &originalTintKey);
    if (themed) {
        if (!original) objc_setAssociatedObject(controller, &originalTintKey,
            controller.view.tintColor ?: NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIColor* accent = CurrentAccentColor();
        if (![controller.view.tintColor isEqual:accent]) controller.view.tintColor = accent;
    } else if (original) {
        controller.view.tintColor = original == NSNull.null ? nil : original;
        objc_setAssociatedObject(controller, &originalTintKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    id account = BHTNavigationAccount(owner);
    NSUInteger generation = [BHTSettings preferenceGeneration];
    if (![BHTGlassNavigationRuntime needsUpdateForController:controller account:account generation:generation]) return;
    NSArray* saved = [CustomTabBarUtility visiblePageIDsInOrder];
    NSMutableArray* pages = [saved ?: [CustomTabBarUtility defaultVisiblePageIDs] mutableCopy];
    if (!saved && [CustomTabBarUtility likesTabEnabled] && ![pages containsObject:@"likes"]) [pages addObject:@"likes"];
    NSArray* metadata = [BHTGlassNavigationRuntime applyToController:controller
        account:account generation:generation visiblePages:pages
        registry:[CustomTabBarUtility availableTabs]
        settingsFactory:^UIViewController* { return [BHTManager BHTSettingsWithAccount:account]; }
        likesFactory:^UIViewController* { return BHTMakeStandaloneLikesController(account); }];
    [CustomTabBarUtility recordTabMetadata:metadata];
}

BOOL BHTRefreshGlassNavigation(void) {
    if (!NSThread.isMainThread) return NO;
    BOOL found = NO;
    for (UIViewController* owner in BHTGlassOwners().allObjects) {
        if (owner.isViewLoaded && owner.view.window) { BHTUpdateGlassNavigation(owner); found = YES; }
    }
    return found;
}

static void BHTNavigationHierarchy(UIViewController* controller, NSUInteger depth,
                                    NSUInteger* budget, NSMutableArray* rows) {
    if (!controller || depth > 6 || *budget == 0) return;
    (*budget)--;
    [rows addObject:@{@"class": NSStringFromClass(controller.class), @"depth": @(depth),
                     @"loaded": @(controller.isViewLoaded),
                     @"onScreen": @(controller.isViewLoaded && controller.view.window != nil)}];
    for (UIViewController* child in controller.childViewControllers) BHTNavigationHierarchy(child, depth + 1, budget, rows);
    BHTNavigationHierarchy(controller.presentedViewController, depth + 1, budget, rows);
}

NSDictionary* BHTGlassNavigationDiagnosticSnapshot(void) {
    if (!NSThread.isMainThread) {
        __block NSDictionary* result;
        dispatch_sync(dispatch_get_main_queue(), ^{ result = BHTGlassNavigationDiagnosticSnapshot(); });
        return result;
    }
    NSMutableDictionary* result = [[BHTGlassNavigationRuntime diagnosticSnapshot] mutableCopy];
    NSMutableArray* hierarchy = [NSMutableArray array];
    NSUInteger budget = 64;
    for (UIWindow* window in UIApplication.sharedApplication.windows) {
        if (!window.hidden) BHTNavigationHierarchy(window.rootViewController, 0, &budget, hierarchy);
    }
    result[@"controllerHierarchy"] = hierarchy;
    result[@"capturesTextOrAccountIdentifiers"] = @NO;
    result[@"nativeGlassMaterialsPreserved"] = @YES;
    result[@"nativeABIImageMatches"] = @(BHTGlassABIIsSupported());
    return result;
}
