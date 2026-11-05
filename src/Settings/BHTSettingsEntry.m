#import "BHTSettingsEntry.h"
#import "Core/BHTBundle.h"
#import "Core/BHTManager.h"
#import "Settings/ModernSettingsViewController.h"
#import <objc/message.h>
#import <objc/runtime.h>
#include <math.h>

BOOL BHTSettingsEntryIsContainer(UIViewController* controller) {
    if (!controller) return NO;
    for (NSString* name in @[@"T1GenericSettingsViewController", @"T1SettingsViewController",
             @"XSettings.SettingsListViewController", @"_TtC9XSettings26SettingsListViewController",
             @"T1TwitterSwift.SettingsChromeViewController", @"_TtC14T1TwitterSwift28SettingsChromeViewController"]) {
        Class cls = NSClassFromString(name);
        if (cls && [controller isKindOfClass:cls]) return YES;
    }
    return NO;
}

BOOL BHTSettingsEntryIsRootController(UIViewController* controller) {
    if (!BHTSettingsEntryIsContainer(controller)) return NO;
    NSUInteger budget = 32;
    for (UIViewController* parent = controller.parentViewController; parent && budget; parent = parent.parentViewController, budget--) {
        if (BHTSettingsEntryIsContainer(parent)) return NO;
    }
    for (UIViewController* entry in controller.navigationController.viewControllers) {
        if (entry == controller) return YES;
        if (BHTSettingsEntryIsContainer(entry)) return NO;
    }
    // Custom containers need not include the content controller itself in a
    // UIKit navigation stack. No earlier settings owner means this is a root.
    return YES;
}

CGFloat BHTSettingsEntryAdditionalTop(CGFloat currentTop, CGFloat previousHeight, CGFloat height) {
    return currentTop - previousHeight + height;
}

CGFloat BHTSettingsEntryRestoredTop(CGFloat currentTop, CGFloat lastAppliedTop, CGFloat ownedHeight) {
    return fabs(currentTop - lastAppliedTop) < 0.5 ? currentTop - ownedHeight : currentTop;
}

CGRect BHTSettingsEntryButtonFrame(CGRect bounds, CGFloat safeTop, CGFloat safeLeft,
                                    CGFloat safeRight, CGFloat ownedHeight) {
    CGFloat left = MAX(0, safeLeft) + 16;
    CGFloat width = MAX(0, CGRectGetWidth(bounds) - left - MAX(0, safeRight) - 16);
    CGFloat top = CGRectGetMinY(bounds) + MAX(0, safeTop - ownedHeight);
    return CGRectMake(CGRectGetMinX(bounds) + left, top + 4, width, MAX(0, ownedHeight - 8));
}

@interface BHTModernSettingsEntryState : NSObject
@property(nonatomic, weak) UIViewController* controller;
@property(nonatomic, strong) UIButton* button;
@property(nonatomic) CGFloat ownedHeight;
@property(nonatomic) CGFloat lastAppliedAdditionalTop;
@property(nonatomic) BOOL updating;
@property(nonatomic) NSUInteger insetUpdates;
@end
@implementation BHTModernSettingsEntryState @end

static char BHTModernSettingsEntryKey;
static NSUInteger BHTModernSettingsEntryInstallCount;
static NSUInteger BHTModernSettingsEntryOpenCount;
static NSMutableDictionary<NSString*, NSNumber*>* BHTModernSettingsEntryCallbacks;

static NSHashTable<BHTModernSettingsEntryState*>* BHTModernSettingsEntries(void) {
    static NSHashTable* entries;
    static dispatch_once_t token;
    dispatch_once(&token, ^{ entries = [NSHashTable weakObjectsHashTable]; });
    return entries;
}

static id BHTSettingsObjectGetter(id object, NSString* name) {
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod([object class], selector);
    if (!method || method_getNumberOfArguments(method) != 2) return nil;
    char type[16] = {0};
    method_getReturnType(method, type, sizeof(type));
    return type[0] == '@' ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

void BHTPresentSettingsFromController(UIViewController* controller) {
    if (!controller || !NSThread.isMainThread) return;
    UINavigationController* navigation = controller.navigationController;
    if ([navigation.topViewController isKindOfClass:ModernSettingsViewController.class]) return;
    id account = BHTSettingsObjectGetter(controller, @"account");
    if (!account) {
        Class host = NSClassFromString(@"T1HostViewController");
        SEL selector = NSSelectorFromString(@"sharedHostViewController");
        id shared = [host respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(host, selector) : nil;
        account = BHTSettingsObjectGetter(shared, @"currentAccount");
    }
    UIViewController* settings = [BHTManager BHTSettingsWithAccount:account];
    if (!settings) return;
    BHTModernSettingsEntryOpenCount++;
    if (navigation) {
        [navigation pushViewController:settings animated:YES];
    } else {
        UINavigationController* modal = [[UINavigationController alloc] initWithRootViewController:settings];
        __weak UINavigationController* weakModal = modal;
        UIAction* close = [UIAction actionWithTitle:@"Done" image:nil identifier:nil handler:^(__kindof UIAction* action) {
            [weakModal dismissViewControllerAnimated:YES completion:nil];
        }];
        settings.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithPrimaryAction:close menu:nil];
        [controller presentViewController:modal animated:YES completion:nil];
    }
}

void BHTInstallModernSettingsEntry(UIViewController* controller) {
    if (!NSThread.isMainThread || !controller.isViewLoaded) return;
    if (!BHTModernSettingsEntryCallbacks) BHTModernSettingsEntryCallbacks = [NSMutableDictionary dictionary];
    NSString* name = NSStringFromClass(controller.class);
    BHTModernSettingsEntryCallbacks[name] = @([BHTModernSettingsEntryCallbacks[name] unsignedIntegerValue] + 1);
    BHTModernSettingsEntryState* state = objc_getAssociatedObject(controller, &BHTModernSettingsEntryKey);
    if (!BHTSettingsEntryIsRootController(controller)) {
        if (state) {
            [state.button removeFromSuperview];
            UIEdgeInsets insets = controller.additionalSafeAreaInsets;
            CGFloat restored = BHTSettingsEntryRestoredTop(insets.top, state.lastAppliedAdditionalTop, state.ownedHeight);
            if (fabs(restored - insets.top) > 0.5) {
                insets.top = restored;
                controller.additionalSafeAreaInsets = insets;
            }
            [BHTModernSettingsEntries() removeObject:state];
            objc_setAssociatedObject(controller, &BHTModernSettingsEntryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    if (!state) {
        state = [BHTModernSettingsEntryState new];
        state.controller = controller;
        UIButtonConfiguration* configuration = [UIButtonConfiguration grayButtonConfiguration];
        configuration.title = [[BHTBundle sharedBundle] localizedStringForKey:@"NFB_SETTINGS_TITLE"];
        configuration.subtitle = [[BHTBundle sharedBundle] localizedStringForKey:@"NFB_SETTINGS_ENTRY_SUBTITLE"];
        configuration.image = [UIImage systemImageNamed:@"gearshape"];
        configuration.imagePadding = 12;
        configuration.contentInsets = NSDirectionalEdgeInsetsMake(12, 16, 12, 16);
        configuration.titleAlignment = UIButtonConfigurationTitleAlignmentLeading;
        configuration.baseForegroundColor = UIColor.labelColor;
        configuration.baseBackgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        configuration.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        state.button = [UIButton buttonWithConfiguration:configuration primaryAction:nil];
        state.button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
        state.button.accessibilityLabel = @"NeoFreeBird settings";
        state.button.accessibilityIdentifier = @"nfb.settings.entry";
        __weak UIViewController* weakController = controller;
        [state.button addAction:[UIAction actionWithTitle:@"NeoFreeBird" image:nil identifier:nil handler:^(__kindof UIAction* action) {
            BHTPresentSettingsFromController(weakController);
        }] forControlEvents:UIControlEventTouchUpInside];
        objc_setAssociatedObject(controller, &BHTModernSettingsEntryKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [BHTModernSettingsEntries() addObject:state];
        BHTModernSettingsEntryInstallCount++;
    }
    if (state.ownedHeight > 0 && fabs(controller.additionalSafeAreaInsets.top - state.lastAppliedAdditionalTop) > 0.5) {
        // A native transition replaced our padding. Treat it as the new base
        // on appearance, without fighting native inset changes on every layout.
        state.ownedHeight = 0;
    }
    if (state.button.superview != controller.view) [controller.view addSubview:state.button];
    BHTLayoutModernSettingsEntry(controller);
}

void BHTLayoutModernSettingsEntry(UIViewController* controller) {
    BHTModernSettingsEntryState* state = objc_getAssociatedObject(controller, &BHTModernSettingsEntryKey);
    if (!state || state.updating || !controller.isViewLoaded) return;
    state.updating = YES;
    @try {
        UIEdgeInsets safe = controller.view.safeAreaInsets;
        CGFloat width = MAX(0, CGRectGetWidth(controller.view.bounds) - safe.left - safe.right - 32);
        if (width <= 0) return;
        CGSize fitted = [state.button sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
        CGFloat height = MAX(64, ceil(fitted.height)) + 8;
        if (fabs(height - state.ownedHeight) > 0.5) {
            UIEdgeInsets insets = controller.additionalSafeAreaInsets;
            insets.top = BHTSettingsEntryAdditionalTop(insets.top, state.ownedHeight, height);
            state.ownedHeight = height;
            state.lastAppliedAdditionalTop = insets.top;
            state.insetUpdates++;
            controller.additionalSafeAreaInsets = insets;
        }
        safe = controller.view.safeAreaInsets;
        CGRect frame = BHTSettingsEntryButtonFrame(controller.view.bounds, safe.top, safe.left, safe.right, state.ownedHeight);
        if (!CGRectEqualToRect(state.button.frame, frame)) state.button.frame = frame;
        if (controller.view.subviews.lastObject != state.button) [controller.view bringSubviewToFront:state.button];
    } @finally {
        state.updating = NO;
    }
}

NSDictionary* BHTModernSettingsEntryDiagnosticSnapshot(void) {
    if (!NSThread.isMainThread) {
        __block NSDictionary* result;
        dispatch_sync(dispatch_get_main_queue(), ^{ result = BHTModernSettingsEntryDiagnosticSnapshot(); });
        return result;
    }
    NSMutableArray* entries = [NSMutableArray array];
    for (BHTModernSettingsEntryState* state in BHTModernSettingsEntries().allObjects) {
        UIViewController* owner = state.controller;
        if (!owner) continue;
        CGRect frame = state.button.frame;
        [entries addObject:@{@"class": NSStringFromClass(owner.class), @"windowAttached": @(state.button.window != nil),
            @"hidden": @(state.button.hidden), @"width": @(frame.size.width), @"height": @(frame.size.height),
            @"alpha": @(state.button.alpha), @"ownedSafeAreaHeight": @(state.ownedHeight), @"insetUpdates": @(state.insetUpdates)}];
    }
    return @{@"callbacksByClass": [BHTModernSettingsEntryCallbacks copy] ?: @{},
             @"installs": @(BHTModernSettingsEntryInstallCount), @"opens": @(BHTModernSettingsEntryOpenCount),
             @"entries": entries, @"dependsOnGlassNavigation": @NO, @"capturesScreenText": @NO};
}
