//
//  Timeline.x
//  NeoFreeBird
//

#import "HookHelpers.h"
#import "Compatibility/BHTCompatibilityReporter.h"
#import "Timeline/BHTForYouKeywordFilter.h"
#import <stddef.h>
#import <stdint.h>
#import <string.h>

// MARK: - For You timeline identity

// X exposes both For You and Following through TIMELINE_HOME.  Never infer the
// selected feed from that display location, localized tab titles, or whichever
// tab happens to be visible.  Instead, carry the primary Home model's identity
// through its deserialized URT timeline and only filter the controller that
// owns that exact object.  Every unknown runtime shape deliberately fails open.
static char kBHTForYouTimelineRoleKey;
static char kBHTForYouKeywordDecisionKey;
static char kBHTForYouControllerGenerationKey;

typedef NS_ENUM(NSInteger, BHTHomeTimelineRole) {
    BHTHomeTimelineRoleNonForYou = 0,
    BHTHomeTimelineRolePrimaryForYou = 1,
    BHTHomeTimelineRoleAmbiguous = 2,
};

@interface BHTHomeTimelineRegistryEntry : NSObject
@property(nonatomic, weak) id timeline;
@property(nonatomic) BHTHomeTimelineRole role;
@end

@implementation BHTHomeTimelineRegistryEntry
@end

@interface BHTForYouKeywordDecisionCache : NSObject
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL hidden;
@property(nonatomic, copy) NSArray<NSString*>* usernameCandidates;
@property(nonatomic, copy) NSArray<NSString*>* postTextCandidates;
@end

@implementation BHTForYouKeywordDecisionCache
@end

static NSMutableArray<BHTHomeTimelineRegistryEntry*>*
    BHTHomeTimelineRegistry;

static NSObject* BHTHomeTimelineRegistryLock(void) {
    static NSObject* lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [NSObject new]; });
    return lock;
}

static void BHTRegisterHomeTimelineRole(
    id timeline, BHTHomeTimelineRole role) {
    if (!timeline) return;
    @synchronized(BHTHomeTimelineRegistryLock()) {
        if (!BHTHomeTimelineRegistry) {
            BHTHomeTimelineRegistry = [NSMutableArray array];
        }
        for (NSInteger index =
                 (NSInteger)BHTHomeTimelineRegistry.count - 1;
             index >= 0; index--) {
            BHTHomeTimelineRegistryEntry* entry =
                BHTHomeTimelineRegistry[(NSUInteger)index];
            id registeredTimeline = entry.timeline;
            if (!registeredTimeline) {
                [BHTHomeTimelineRegistry
                    removeObjectAtIndex:(NSUInteger)index];
                continue;
            }
            if (registeredTimeline == timeline) {
                entry.role = role;
                return;
            }
        }
        BHTHomeTimelineRegistryEntry* entry =
            [BHTHomeTimelineRegistryEntry new];
        entry.timeline = timeline;
        entry.role = role;
        [BHTHomeTimelineRegistry addObject:entry];
    }
}

static NSNumber* BHTHomeTimelineRoleForTrustedPointer(
    const void* candidate) {
    if (!candidate) return nil;
    @synchronized(BHTHomeTimelineRegistryLock()) {
        for (NSInteger index =
                 (NSInteger)BHTHomeTimelineRegistry.count - 1;
             index >= 0; index--) {
            BHTHomeTimelineRegistryEntry* entry =
                BHTHomeTimelineRegistry[(NSUInteger)index];
            id timeline = entry.timeline;
            if (!timeline) {
                [BHTHomeTimelineRegistry
                    removeObjectAtIndex:(NSUInteger)index];
                continue;
            }
            if ((__bridge const void*)timeline == candidate) {
                return @(entry.role);
            }
        }
    }
    return nil;
}

static void BHTMergeHomeTimelineRole(id timeline,
                                     BHTHomeTimelineRole incomingRole) {
    if (!timeline) return;
    @synchronized(timeline) {
        NSNumber* existing =
            objc_getAssociatedObject(timeline,
                                     &kBHTForYouTimelineRoleKey);
        BHTHomeTimelineRole mergedRole = incomingRole;
        if (existing &&
            existing.integerValue != (NSInteger)incomingRole) {
            // A model/stream observed in both roles is not safe to filter.
            // Preserve that ambiguity permanently rather than letting the
            // last factory call win.
            mergedRole = BHTHomeTimelineRoleAmbiguous;
        }
        objc_setAssociatedObject(timeline, &kBHTForYouTimelineRoleKey,
                                 @(mergedRole),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        BHTRegisterHomeTimelineRole(timeline, mergedRole);
    }
}

static NSNumber* BHTHomeTimelineRoleForTimeline(id timeline) {
    return timeline
               ? objc_getAssociatedObject(timeline,
                                          &kBHTForYouTimelineRoleKey)
               : nil;
}

// T1TimelineFactory names each model before it is handed to the segmented Home
// controller.  Marking both the getters and the final root-factory arguments
// covers cached and cold construction without guessing from view state.
%group BHTForYouTimelineProvenance

%hook T1TimelineFactory

- (id)homeTimelineForAccount:(id)account {
    id timeline = %orig;
    BHTMergeHomeTimelineRole(timeline,
                             BHTHomeTimelineRolePrimaryForYou);
    return timeline;
}

- (id)homeCountryFilteredTimelineForAccount:(id)account {
    id timeline = %orig;
    BHTMergeHomeTimelineRole(timeline,
                             BHTHomeTimelineRoleNonForYou);
    return timeline;
}

- (id)homeTopicFilteredTimelineForAccount:(id)account {
    id timeline = %orig;
    BHTMergeHomeTimelineRole(timeline,
                             BHTHomeTimelineRoleNonForYou);
    return timeline;
}

- (id)homeLatestTimelineForAccount:(id)account {
    id timeline = %orig;
    BHTMergeHomeTimelineRole(timeline,
                             BHTHomeTimelineRoleNonForYou);
    return timeline;
}

- (id)homeRankedFollowingTimelineForAccount:(id)account {
    id timeline = %orig;
    BHTMergeHomeTimelineRole(timeline,
                             BHTHomeTimelineRoleNonForYou);
    return timeline;
}

- (id)rootViewControllerForHomeTimeline:(id)homeTimeline
            homeCountryFilteredTimeline:(id)homeCountryFilteredTimeline
                     homeLatestTimeline:(id)homeLatestTimeline
            homeRankedFollowingTimeline:(id)homeRankedFollowingTimeline
                                account:(id)account {
    BHTMergeHomeTimelineRole(homeTimeline,
                             BHTHomeTimelineRolePrimaryForYou);
    BHTMergeHomeTimelineRole(homeCountryFilteredTimeline,
                             BHTHomeTimelineRoleNonForYou);
    BHTMergeHomeTimelineRole(homeLatestTimeline,
                             BHTHomeTimelineRoleNonForYou);
    BHTMergeHomeTimelineRole(homeRankedFollowingTimeline,
                             BHTHomeTimelineRoleNonForYou);
    return %orig;
}

%end

// TFNTwitterHomeTimeline converts the model above into the immutable URT
// timeline stored by T1URTViewController.  Propagate the explicit role across
// that boundary; a missing role stays missing rather than becoming For You.
%hook TFNTwitterHomeTimeline

- (id)deserializeStream {
    id timeline = %orig;
    NSNumber* role = BHTHomeTimelineRoleForTimeline(self);
    if (timeline && role) {
        BHTMergeHomeTimelineRole(
            timeline, (BHTHomeTimelineRole)role.integerValue);
    }
    return timeline;
}

%end

%end

// MARK: - Hide custom timelines

static __weak NSObject* PinnedTimelinesRepository;
static NSArray* LastPinnedTimelineModels;
static BOOL PinnedTimelinesWriteBypass = NO;

// Applies a toggle without relaunching. Hiding rewrites the UNCHANGED pinned
// list purely to republish — updatePinnedTimelines: persists server-side, so
// anything else would unpin for real; the delegate hook below swaps in the
// empty list on the way through.
void applyHideCustomTimelinesSetting(void) {
    NSObject* repository = PinnedTimelinesRepository;
    if (!repository) {
        return;
    }

    if ([BHTSettings boolForKey:@"hide_custom_timelines"]) {
        NSArray* models = LastPinnedTimelineModels;
        if (models.count > 0) {
            PinnedTimelinesWriteBypass = YES;
            ((void (*)(id, SEL, id))objc_msgSend)(repository, @selector(updatePinnedTimelines:), models);
            PinnedTimelinesWriteBypass = NO;
        }
    } else if ([repository respondsToSelector:@selector(fetchPinnedTimelinesWithThrottleEnabled:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(
            repository, @selector(fetchPinnedTimelinesWithThrottleEnabled:), NO);
    }
}

// The trailing accessory is only reconfigured while the strip is showing, so a
// button built before hiding mid-session survives; sync its visibility here. The
// property is a Swift lazy var whose storage ivar KVC can't see, hence the fallback.
static void SyncHomeAddTabButton(id container, BOOL hidden) {
    UIView* button = nil;

    @try {
        button = [container valueForKey:@"addTabButton"];
    } @catch (__unused NSException* exception) {
        unsigned int ivarCount = 0;
        Ivar* ivars = class_copyIvarList([container class], &ivarCount);
        for (unsigned int i = 0; i < ivarCount; i++) {
            const char* name = ivar_getName(ivars[i]);
            if (name && strstr(name, "addTabButton")) {
                button = object_getIvar(container, ivars[i]);
                break;
            }
        }
        free(ivars);
    }

    if ([button isKindOfClass:[UIView class]]) {
        button.hidden = hidden;
    }
}

// The repository publishes the pinned list through this single delegate call, so
// handing it an empty array hides the tabs without touching persisted state.
%hook _TtC32TwitterHomeFeatureImplementation35HomeTimelineContainerViewController

- (void)pinnedTimelinesRepository:(id)repository
    didChangeWithPinnedTimelineModels:(NSArray*)models {
    PinnedTimelinesRepository = repository;
    if (models.count > 0) {
        LastPinnedTimelineModels = [models copy];
    }
    BOOL hide = [BHTSettings boolForKey:@"hide_custom_timelines"];

    %orig(repository, hide ? @[] : models);
    SyncHomeAddTabButton(self, hide);
}

- (id)tfn_navigationBarAccessoryView {
    id accessoryView = %orig;
    SyncHomeAddTabButton(self, [BHTSettings boolForKey:@"hide_custom_timelines"]);
    return accessoryView;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SyncHomeAddTabButton(self, [BHTSettings boolForKey:@"hide_custom_timelines"]);
}

- (BOOL)tfn_supportsTabBarCollapsing {
    return [BHTSettings boolForKey:@"no_tab_bar_hiding"] ? NO : %orig;
}

- (BOOL)tfn_prefersTabBarPinned {
    return [BHTSettings boolForKey:@"no_tab_bar_hiding"] ? YES : %orig;
}

%end

// X 12.9 also registers an Objective-C-visible compatibility name for the Home
// container.  Keep the same safe, non-persisting behavior on that path.
%group BHTX129HomeContainer

%hook HomeTimelineContainerViewController

- (void)pinnedTimelinesRepository:(id)repository
    didChangeWithPinnedTimelineModels:(NSArray*)models {
    PinnedTimelinesRepository = repository;
    if (models.count > 0) LastPinnedTimelineModels = [models copy];
    BOOL hide = [BHTSettings boolForKey:@"hide_custom_timelines"];
    %orig(repository, hide ? @[] : models);
    SyncHomeAddTabButton(self, hide);
}

- (id)tfn_navigationBarAccessoryView {
    id accessory = %orig;
    SyncHomeAddTabButton(self, [BHTSettings boolForKey:@"hide_custom_timelines"]);
    return accessory;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SyncHomeAddTabButton(self, [BHTSettings boolForKey:@"hide_custom_timelines"]);
}

- (BOOL)tfn_supportsTabBarCollapsing {
    return [BHTSettings boolForKey:@"no_tab_bar_hiding"] ? NO : %orig;
}

- (BOOL)tfn_prefersTabBarPinned {
    return [BHTSettings boolForKey:@"no_tab_bar_hiding"] ? YES : %orig;
}

%end

%end

// While hiding, the overridden pinned-tabs feature switches make the app compute
// an empty pinned list; freeze writes so it can't overwrite the real tabs.
%hook _TtC32TwitterHomeFeatureImplementation31CachedPinnedTimelinesRepository

- (void)updatePinnedTimelines:(id)timelines {
    if (!PinnedTimelinesWriteBypass && [BHTSettings boolForKey:@"hide_custom_timelines"]) {
        return;
    }

    %orig;
}

%end

// MARK: - Force tweet images to full frame

%hook T1StandardStatusAttachmentViewAdapter

// attachmentType 2 = photos, displayType 1 = full frame
- (NSUInteger)displayType {
    if (self.attachmentType == 2) {
        return [BHTSettings boolForKey:@"force_tweet_full_frame"] ? 1 : %orig;
    }

    return %orig;
}

%end

// MARK: - Hide the Spaces bar

// The bar is still the repurposed Fleets line; both home timeline implementations
// share this visibility gate, re-evaluated on every content or settings update.
%hook T1FleetLineHeaderController

- (BOOL)_t1_shouldShowFleetLine {
    if ([BHTSettings boolForKey:@"hide_spaces"]) {
        return NO;
    }

    return %orig;
}

%end

// Target the update-indicator controller rather than every TFNPillControl in
// the app (other sheets and banners reuse that control class).
%hook TUIUpdateIndicator

- (void)viewDidLayoutSubviews {
    %orig;
    if ([BHTSettings boolForKey:@"hide_timeline_prompts"]) {
        self.pillControl.hidden = YES;
        self.pillControl.alpha = 0;
        self.pillControl.userInteractionEnabled = NO;
    }
}

%end

// MARK: - Hide "Discover more", who-to-follow and prompts

// Resolves the class by name so mangled Swift names work; NSStringFromClass
// would only ever produce the demangled dotted form.
static BOOL IsInHierarchyOfClass(UIViewController* viewController, NSString* className) {
    Class targetClass = NSClassFromString(className);
    if (!targetClass) {
        return NO;
    }

    UIViewController* currentVC = viewController;

    while (currentVC) {
        if ([currentVC isKindOfClass:targetClass]) {
            return YES;
        }

        if (currentVC.parentViewController) {
            currentVC = currentVC.parentViewController;
        } else if (currentVC.navigationController) {
            currentVC = currentVC.navigationController;
        } else if (currentVC.presentingViewController) {
            currentVC = currentVC.presentingViewController;
        } else {
            break;
        }
    }

    return NO;
}

static NSString* ItemEntryID(id viewModel) {
    if (![viewModel respondsToSelector:@selector(entryID)]) {
        return nil;
    }

    NSString* entryID = [viewModel performSelector:@selector(entryID)];
    return [entryID isKindOfClass:[NSString class]] ? entryID : nil;
}

static NSString* ItemScribeComponent(id viewModel) {
    if (![viewModel respondsToSelector:@selector(scribeComponent)]) {
        return nil;
    }

    NSString* component = [viewModel performSelector:@selector(scribeComponent)];
    return [component isKindOfClass:[NSString class]] ? component : nil;
}

static const char* SkipObjCTypeQualifiers(const char* type) {
    if (!type) return NULL;
    while (*type == 'r' || *type == 'n' || *type == 'N' ||
           *type == 'o' || *type == 'O' || *type == 'R' ||
           *type == 'V') {
        type++;
    }
    return type;
}

static BOOL MethodReturnsObject(id object, SEL selector) {
    if (!object || !selector ||
        ![object respondsToSelector:selector]) {
        return NO;
    }
    Method method =
        class_getInstanceMethod([object class], selector);
    if (!method) return NO;
    char returnType[32] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    const char* unqualified =
        SkipObjCTypeQualifiers(returnType);
    return unqualified && unqualified[0] == '@';
}

static id ItemObjectValueAllowingUntypedIvar(
    id viewModel, SEL selector, const char* ivarName,
    BOOL allowUntypedIvar) {
    if (!viewModel) return nil;

    if (MethodReturnsObject(viewModel, selector)) {
        return ((id (*)(id, SEL))objc_msgSend)(viewModel, selector);
    }

    Ivar ivar = class_getInstanceVariable([viewModel class], ivarName);
    if (!ivar && ivarName[0] != '_') {
        NSString* name = [NSString stringWithUTF8String:ivarName];
        NSString* underscored = [@"_" stringByAppendingString:name];
        ivar = class_getInstanceVariable([viewModel class], underscored.UTF8String);
    }
    if (!ivar) return nil;

    const char* type =
        SkipObjCTypeQualifiers(ivar_getTypeEncoding(ivar));
    BOOL objectIvar = type && type[0] == '@';
    BOOL untypedIvar =
        !type || type[0] == '\0' || type[0] == '?';
    if (!objectIvar &&
        !(allowUntypedIvar && untypedIvar)) {
        return nil;
    }
    return object_getIvar(viewModel, ivar);
}

static id ItemObjectValue(id viewModel, SEL selector,
                          const char* ivarName) {
    return ItemObjectValueAllowingUntypedIvar(
        viewModel, selector, ivarName, NO);
}

static void* BHTUntypedIvarPointer(
    id object, const char* ivarName) {
    if (!object || !ivarName) return NULL;
    Ivar ivar = class_getInstanceVariable([object class], ivarName);
    if (!ivar && ivarName[0] != '_') {
        NSString* name =
            [NSString stringWithUTF8String:ivarName];
        NSString* underscored =
            [@"_" stringByAppendingString:name];
        ivar = class_getInstanceVariable(
            [object class], underscored.UTF8String);
    }
    if (!ivar) return NULL;

    const char* type =
        SkipObjCTypeQualifiers(ivar_getTypeEncoding(ivar));
    if (type && type[0] != '\0' && type[0] != '?') {
        return NULL;
    }

    ptrdiff_t offset = ivar_getOffset(ivar);
    Class runtimeClass = object_getClass(object);
    if (offset < 0 || !runtimeClass) return NULL;
    size_t unsignedOffset = (size_t)offset;
    size_t instanceSize = class_getInstanceSize(runtimeClass);
    if (unsignedOffset > instanceSize ||
        sizeof(void*) > instanceSize - unsignedOffset) {
        return NULL;
    }

    uintptr_t base = (uintptr_t)(__bridge void*)object;
    void* value = NULL;
    memcpy(&value, (const void*)(base + unsignedOffset),
           sizeof(value));
    return value;
}

static NSString* ItemStringValue(id object, SEL selector,
                                 const char* ivarName) {
    id value = ItemObjectValue(object, selector, ivarName);
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static NSString* ItemReadableTextValue(id object, SEL selector,
                                       const char* ivarName) {
    id value = ItemObjectValue(object, selector, ivarName);
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSAttributedString.class]) {
        return [(NSAttributedString*)value string];
    }

    // X may expose display text through a small model rather than a raw
    // NSString. Follow only its public-facing string/text accessors and stop
    // after one level so timeline filtering remains bounded.
    for (NSString* nestedSelectorName in @[@"string", @"text",
                                            @"displayText"]) {
        SEL nestedSelector = NSSelectorFromString(nestedSelectorName);
        id nested =
            ItemObjectValue(value, nestedSelector,
                            nestedSelectorName.UTF8String);
        if ([nested isKindOfClass:NSString.class]) return nested;
        if ([nested isKindOfClass:NSAttributedString.class]) {
            return [(NSAttributedString*)nested string];
        }
    }
    return nil;
}

static Class BHTStatusItemViewModelClass(void) {
    static Class cls;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cls = NSClassFromString(
            @"T1URTTimelineStatusItemViewModel");
    });
    return cls;
}

static Class BHTTwitterStatusClass(void) {
    static Class cls;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cls = NSClassFromString(@"TFNTwitterStatus");
    });
    return cls;
}

static UIViewController* NearestURTTimelineController(
    TFNItemsDataViewController* dataViewController, Class targetClass) {
    UIViewController* current = dataViewController;
    for (NSUInteger depth = 0;
         current && depth < 16; depth++) {
        if ([current isKindOfClass:targetClass]) return current;

        UIViewController* next = current.parentViewController;
        if (!next || next == current) {
            next = current.navigationController;
        }
        if (!next || next == current) break;
        current = next;
    }

    // X 12.9 delivers sections through an inner items controller. Its UIKit
    // containment metadata can be temporarily incomplete during setup, while
    // the loaded view's responder chain still reaches the owning URT
    // controller. Keep this bounded and accept only the exact runtime class.
    if (dataViewController.isViewLoaded) {
        UIResponder* responder =
            dataViewController.view.nextResponder;
        for (NSUInteger depth = 0;
             responder && depth < 32; depth++) {
            if ([responder isKindOfClass:targetClass] &&
                [responder isKindOfClass:UIViewController.class]) {
                return (UIViewController*)responder;
            }
            UIResponder* next = responder.nextResponder;
            if (!next || next == responder) break;
            responder = next;
        }
    }
    return nil;
}

static BOOL BHTIsPrimaryForYouURTController(id urtController) {
    Class urtControllerClass = NSClassFromString(@"T1URTViewController");
    if (!urtControllerClass ||
        ![urtController isKindOfClass:urtControllerClass]) {
        BHTRecordForYouFilterDiagnostic(
            BHTForYouFilterDiagnosticControllerOwnerMissing);
        return NO;
    }
    NSString* location =
        ItemStringValue(urtController, @selector(adDisplayLocation),
                        "adDisplayLocation");
    if (![location isEqualToString:@"TIMELINE_HOME"]) {
        BHTRecordForYouFilterDiagnostic(
            BHTForYouFilterDiagnosticControllerNonHome);
        return NO;
    }

    // Prefer the current Home provider's explicit primary controller. Both
    // eager and lazy providers separate it from Following and custom feeds.
    // Do not use the selected index or infer the feed from a localized title.
    Class homeClass = NSClassFromString(
        @"TwitterHomeFeatureImplementation.HomeTimelineContainerViewController");
    Class bridge = NSClassFromString(@"BHTHomeTimelineRuntime");
    SEL primarySelector = NSSelectorFromString(
        @"primaryTimelineControllerInContainer:");
    NSMutableArray<UIViewController*>* ancestors = [NSMutableArray array];
    UIViewController* ancestor = urtController;
    for (NSUInteger depth = 0; ancestor && depth < 16; depth++) {
        if (homeClass && [ancestor isKindOfClass:homeClass] &&
            [bridge respondsToSelector:primarySelector]) {
            id primary = ((id (*)(id, SEL, id))objc_msgSend)(
                bridge, primarySelector, ancestor);
            if ([primary isKindOfClass:UIViewController.class]) {
                BOOL ownsPrimary = [ancestors indexOfObjectIdenticalTo:primary] != NSNotFound;
                BHTRecordForYouFilterDiagnostic(
                    BHTForYouFilterDiagnosticProviderOwnerResolved);
                BHTRecordForYouFilterDiagnostic(
                    ownsPrimary ? BHTForYouFilterDiagnosticControllerPrimary
                                : BHTForYouFilterDiagnosticControllerNonForYou);
                return ownsPrimary;
            }
            BHTRecordForYouFilterDiagnostic(
                BHTForYouFilterDiagnosticProviderOwnerMissing);
            break;
        }
        [ancestors addObject:ancestor];
        UIViewController* parent = ancestor.parentViewController;
        if (parent == ancestor) break;
        ancestor = parent;
    }

    // Older Home construction paths expose `urtTimeline` as a Swift-backed ivar with an empty
    // Objective-C type encoding and no accessor. A typed future accessor/ivar
    // remains preferred. For this exact runtime shape, compare the raw pointer
    // with the weak registry of objects returned by X's verified deserializer
    // before making any Objective-C call on it.
    id urtTimeline =
        ItemObjectValue(
            urtController, NSSelectorFromString(@"urtTimeline"),
            "urtTimeline");
    NSNumber* role = BHTHomeTimelineRoleForTimeline(urtTimeline);
    if (!urtTimeline) {
        void* rawTimeline =
            BHTUntypedIvarPointer(urtController, "urtTimeline");
        role =
            BHTHomeTimelineRoleForTrustedPointer(rawTimeline);
    }
    BHTRecordForYouFilterDiagnostic(
        role
            ? BHTForYouFilterDiagnosticTimelineObjectResolved
            : BHTForYouFilterDiagnosticTimelineObjectMissing);
    // Re-evaluate the current object on every section update. Never carry a
    // positive controller decision across an unknown or explicitly non-For You
    // timeline, since X is free to reuse controllers between feeds.
    if (!role) {
        BHTRecordForYouFilterDiagnostic(
            BHTForYouFilterDiagnosticControllerUnknown);
        return NO;
    }
    BOOL primary =
        role.integerValue == BHTHomeTimelineRolePrimaryForYou;
    BHTRecordForYouFilterDiagnostic(
        primary ? BHTForYouFilterDiagnosticControllerPrimary
                : BHTForYouFilterDiagnosticControllerNonForYou);
    return primary;
}

static BOOL IsPrimaryForYouTimelineController(
    TFNItemsDataViewController* dataViewController) {
    if (!dataViewController) return NO;

    NSString* dataLocation = ItemStringValue(
        dataViewController, @selector(adDisplayLocation),
        "adDisplayLocation");
    if (dataLocation.length > 0 &&
        ![dataLocation isEqualToString:@"TIMELINE_HOME"]) {
        BHTRecordForYouFilterDiagnostic(
            BHTForYouFilterDiagnosticControllerNonHome);
        return NO;
    }

    Class urtControllerClass = NSClassFromString(@"T1URTViewController");
    if (!urtControllerClass) {
        BHTRecordForYouFilterDiagnostic(
            BHTForYouFilterDiagnosticControllerOwnerMissing);
        return NO;
    }

    // In X 12.9 T1URTViewController is itself a verified subclass of
    // TFNItemsDataViewController. Prefer that exact relationship and bounded
    // UIKit ancestry. Some Home section snapshots are delivered by a separate
    // helper controller with no declared owner link; those deliberately fail
    // open here and are handled later by the exact T1URT render callbacks.
    UIViewController* urtController =
        NearestURTTimelineController(
            dataViewController, urtControllerClass);
    if (!urtController) {
        BHTRecordForYouFilterDiagnostic(
            BHTForYouFilterDiagnosticDirectOwnerMissing);
        BHTRecordForYouFilterDiagnostic(
            BHTForYouFilterDiagnosticControllerOwnerMissing);
        return NO;
    }
    BHTRecordForYouFilterDiagnostic(
        BHTForYouFilterDiagnosticDirectOwnerResolved);
    return BHTIsPrimaryForYouURTController(urtController);
}

static BOOL BHTIsKeywordStatusViewModel(id viewModel) {
    Class statusItem = BHTStatusItemViewModelClass();
    Class status = BHTTwitterStatusClass();
    Class composition = NSClassFromString(@"T1CompositionStatusViewModel");
    return (statusItem && [viewModel isKindOfClass:statusItem]) ||
           (status && [viewModel isKindOfClass:status]) ||
           (composition && [viewModel isKindOfClass:composition]);
}

static id StatusFromTimelineItem(id item) {
    id viewModel = unwrapDataViewItem(item);
    Class statusClass = BHTTwitterStatusClass();
    if (!statusClass || !BHTIsKeywordStatusViewModel(viewModel)) {
        return nil;
    }
    if ([viewModel isKindOfClass:statusClass]) return viewModel;

    // Prefer X 12.9's compatibility accessor because its Objective-C return
    // signature can be verified before messaging it.
    id tweet =
        ItemObjectValue(viewModel, NSSelectorFromString(@"tweet"), "tweet");
    if ([tweet isKindOfClass:statusClass]) return tweet;

    // Some builds store the same object only in a Swift-backed `status` ivar
    // without a useful type encoding. Keep this narrow, final fallback after
    // the verified accessor and validate the resolved class immediately.
    id status = ItemObjectValueAllowingUntypedIvar(
        viewModel, NSSelectorFromString(@"status"), "status", YES);
    return [status isKindOfClass:statusClass] ? status : nil;
}

static id RepresentedStatus(id status) {
    if (!status) return nil;
    Class statusClass = BHTTwitterStatusClass();
    if (!statusClass) return nil;

    id represented =
        ItemObjectValue(status, NSSelectorFromString(@"representedStatus"),
                        "representedStatus");
    if ([represented isKindOfClass:statusClass]) {
        return represented;
    }

    id retweeted =
        ItemObjectValue(status, NSSelectorFromString(@"retweetedStatus"),
                        "retweetedStatus");
    return [retweeted isKindOfClass:statusClass] ? retweeted : status;
}

static void AddUsernameCandidates(NSMutableArray<NSString*>* candidates,
                                  id status) {
    if (!status) return;
    NSArray<NSString*>* values = @[
        ItemStringValue(status, NSSelectorFromString(@"fromUserName"),
                        "fromUserName") ?: @"",
        ItemStringValue(status, NSSelectorFromString(@"fromUserFullName"),
                        "fromUserFullName") ?: @"",
    ];
    for (NSString* value in values) {
        if (value.length > 0 && ![candidates containsObject:value]) {
            [candidates addObject:value];
        }
    }
}

static const NSUInteger BHTForYouMaximumMentionCandidates = 32;
static const NSUInteger BHTForYouMaximumMentionScanLength = 32768;
static const NSUInteger BHTTwitterHandleMaximumLength = 15;

static BOOL IsTwitterHandleCharacter(unichar character) {
    return (character >= 'a' && character <= 'z') ||
           (character >= 'A' && character <= 'Z') ||
           (character >= '0' && character <= '9') ||
           character == '_';
}

static void AddMentionUsernameCandidates(
    NSMutableArray<NSString*>* candidates,
    NSArray<NSString*>* trustedTextCandidates) {
    NSUInteger addedMentionCount = 0;
    for (id candidateValue in trustedTextCandidates) {
        if (addedMentionCount >= BHTForYouMaximumMentionCandidates) break;
        if (![candidateValue isKindOfClass:NSString.class]) continue;

        NSString* text = candidateValue;
        NSUInteger scanLength =
            MIN(text.length, BHTForYouMaximumMentionScanLength);
        for (NSUInteger index = 0;
             index < scanLength &&
             addedMentionCount < BHTForYouMaximumMentionCandidates;
             index++) {
            if ([text characterAtIndex:index] != '@') continue;

            // Do not treat the domain part of an email address, an embedded
            // identifier, or the second character of @@text as a mention.
            if (index > 0) {
                unichar previous = [text characterAtIndex:index - 1];
                if (IsTwitterHandleCharacter(previous) || previous == '@') {
                    continue;
                }
            }

            NSUInteger handleStart = index + 1;
            NSUInteger handleEnd = handleStart;
            while (handleEnd < scanLength &&
                   IsTwitterHandleCharacter(
                       [text characterAtIndex:handleEnd]) &&
                   handleEnd - handleStart <=
                       BHTTwitterHandleMaximumLength) {
                handleEnd++;
            }

            NSUInteger handleLength = handleEnd - handleStart;
            BOOL handleContinues =
                handleEnd < text.length &&
                IsTwitterHandleCharacter(
                    [text characterAtIndex:handleEnd]);
            if (handleLength == 0 ||
                handleLength > BHTTwitterHandleMaximumLength ||
                handleContinues) {
                continue;
            }

            NSString* handle =
                [text substringWithRange:
                          NSMakeRange(handleStart, handleLength)];
            if (![candidates containsObject:handle]) {
                [candidates addObject:handle];
                addedMentionCount++;
                BHTRecordForYouFilterDiagnostic(
                    BHTForYouFilterDiagnosticMentionHandleCandidateExtracted);
            }
            index = handleEnd - 1;
        }
    }
}

static NSArray<NSString*>* UsernameCandidatesForStatuses(
    id outerStatus, id representedStatus,
    NSArray<NSString*>* trustedTextCandidates) {
    NSMutableArray<NSString*>* candidates =
        [NSMutableArray arrayWithCapacity:8];
    AddUsernameCandidates(candidates, representedStatus);
    if (outerStatus != representedStatus) {
        // Include the reposting account as well as the visible post author.
        AddUsernameCandidates(candidates, outerStatus);
    }
    // The account filter also covers explicit @handles in the post without
    // broadening it to ordinary body text. This lets a saved `grok` account
    // filter match `@grok`, while words such as "grok" still belong in the
    // separate post-text filter.
    AddMentionUsernameCandidates(candidates, trustedTextCandidates);
    return [candidates copy];
}

static void AddPostTextCandidate(
    NSMutableArray<NSString*>* candidates, NSString* value) {
    if (value.length > 0 && ![candidates containsObject:value]) {
        [candidates addObject:value];
    }
}

static void AddPostTextCandidatesFromDisplayModel(
    NSMutableArray<NSString*>* textCandidates, id model) {
    if (!model) return;
    struct {
        const char* selector;
        const char* ivar;
    } candidates[] = {
        {"attributedString", "attributedString"},
        {"string", "string"},
        {"text", "text"},
        {"displayText", "displayText"},
    };
    for (NSUInteger index = 0;
         index < sizeof(candidates) / sizeof(candidates[0]); index++) {
        NSString* value = ItemReadableTextValue(
            model,
            NSSelectorFromString(
                [NSString stringWithUTF8String:
                              candidates[index].selector]),
            candidates[index].ivar);
        AddPostTextCandidate(textCandidates, value);
    }
}

static NSArray<NSString*>* PostTextCandidates(id status) {
    if (!status) return @[];
    NSMutableArray<NSString*>* candidates =
        [NSMutableArray arrayWithCapacity:10];

    // fullText/displayText can omit reply mentions. The canonical model owns
    // the original primary post text; it is separate from any quoted post.
    id canonical = ItemObjectValue(
        status, NSSelectorFromString(@"canonicalStatus"), "_canonicalStatus");
    AddPostTextCandidate(candidates, ItemReadableTextValue(
        canonical, NSSelectorFromString(@"originalText"), "originalText"));

    // A hydrated post can have mention entities before its original text.
    // Prefer X's unmention-aware list and accept only native mention entities.
    SEL entitySelector = NSSelectorFromString(@"entitiesRemovingUnmentioned");
    id entities = MethodReturnsObject(status, entitySelector)
        ? ItemObjectValue(status, entitySelector, "entitiesRemovingUnmentioned")
        : ItemObjectValue(status, NSSelectorFromString(@"entities"), "entities");
    Class mentionClass = NSClassFromString(@"TFSTwitterEntityUserMention");
    if (mentionClass && [entities isKindOfClass:NSArray.class]) {
        NSUInteger inspected = 0;
        for (id entity in entities) {
            if (inspected++ >= 128) break;
            if (![entity isKindOfClass:mentionClass]) continue;
            NSString* handle = ItemStringValue(
                entity, NSSelectorFromString(@"username"), "username");
            if (handle.length > 0 && handle.length <= BHTTwitterHandleMaximumLength) {
                AddPostTextCandidate(candidates,
                    [@"@" stringByAppendingString:handle]);
            }
        }
    }

    // Note Tweets can expose a shortened legacy `text`, while X's display
    // model can omit leading reply mentions. Inspect every trusted primary
    // representation instead of returning the first nonempty one.
    id fullNoteModel = ItemObjectValue(
        status,
        NSSelectorFromString(
            @"_tfn_fullNoteTweetDisplayTextModel"),
        "_fullNoteTweetDisplayTextModel");
    AddPostTextCandidatesFromDisplayModel(candidates, fullNoteModel);

    id displayTextModel =
        ItemObjectValue(status,
                        NSSelectorFromString(@"displayTextModel"),
                        "_displayTextModel");
    AddPostTextCandidatesFromDisplayModel(candidates, displayTextModel);

    struct {
        const char* selector;
        const char* ivar;
    } rawFields[] = {
        {"fullText", "fullText"},
        {"text", "text"},
        {"displayText", "displayText"},
        {"originalText", "originalText"},
    };

    for (NSUInteger index = 0;
         index < sizeof(rawFields) / sizeof(rawFields[0]); index++) {
        NSString* value =
            ItemReadableTextValue(
                status,
                NSSelectorFromString(
                    [NSString stringWithUTF8String:
                                  rawFields[index].selector]),
                rawFields[index].ivar);
        AddPostTextCandidate(candidates, value);
    }
    return [candidates copy];
}

static BOOL ComputeShouldHideForYouKeywordItem(
    NSArray<NSString*>* usernameCandidates,
    NSArray<NSString*>* postTextCandidates,
    BOOL hasUsernameFilters, BOOL hasPostTextFilters) {
    if (hasUsernameFilters) {
        BOOL matchesUsername = [BHTForYouKeywordFilter
            matchesAnyUsernameCandidate:usernameCandidates];
        if (matchesUsername) {
            BHTRecordForYouFilterDiagnostic(
                BHTForYouFilterDiagnosticUsernameMatch);
            return YES;
        }
    }

    if (hasPostTextFilters) {
        if ([BHTForYouKeywordFilter
                matchesAnyPostTextCandidate:postTextCandidates]) {
            BHTRecordForYouFilterDiagnostic(
                BHTForYouFilterDiagnosticPostTextMatch);
            return YES;
        }
    }

    BHTRecordForYouFilterDiagnostic(
        BHTForYouFilterDiagnosticNoMatch);
    return NO;
}

static BOOL ShouldHideForYouKeywordItem(
    id item, NSUInteger generation, BOOL hasUsernameFilters,
    BOOL hasPostTextFilters) {
    id cacheOwner = unwrapDataViewItem(item);
    if (!BHTIsKeywordStatusViewModel(cacheOwner)) {
        return NO;
    }

    id outerStatus = StatusFromTimelineItem(cacheOwner);
    if (!outerStatus) {
        BHTRecordForYouFilterDiagnostic(
            BHTForYouFilterDiagnosticMissingStatus);
        return NO;
    }
    id representedStatus = RepresentedStatus(outerStatus);
    if (!representedStatus) {
        BHTRecordForYouFilterDiagnostic(
            BHTForYouFilterDiagnosticMissingStatus);
        return NO;
    }

    NSArray<NSString*>* postTextCandidates =
        hasUsernameFilters || hasPostTextFilters
            ? PostTextCandidates(representedStatus)
            : @[];
    if (postTextCandidates.count > 0) {
        // Count only that a trusted representation was available. Never
        // export post text, handles, or saved filter values.
        BHTRecordForYouFilterDiagnostic(
            BHTForYouFilterDiagnosticTrustedTextCandidateSetNonEmpty);
    }
    NSArray<NSString*>* usernameCandidates =
        hasUsernameFilters
            ? UsernameCandidatesForStatuses(
                  outerStatus, representedStatus,
                  postTextCandidates)
            : @[];

    // X may hydrate or replace text after a section's first delivery. Cache
    // both decisions together with the exact trusted inputs rather than
    // treating the view model as permanently immutable. Repeated updates stay
    // cheap, while newly available fullText/@mentions automatically invalidate
    // an earlier NO. The strict controller gate keeps this cache out of
    // Following, and a filter edit changes the generation.
    BHTForYouKeywordDecisionCache* cached =
        objc_getAssociatedObject(outerStatus,
                                 &kBHTForYouKeywordDecisionKey);
    if ([cached
            isKindOfClass:BHTForYouKeywordDecisionCache.class] &&
        cached.generation == generation &&
        [cached.usernameCandidates
            isEqualToArray:usernameCandidates] &&
        [cached.postTextCandidates
            isEqualToArray:postTextCandidates]) {
        BHTRecordForYouFilterDiagnostic(
            BHTForYouFilterDiagnosticDecisionCacheHit);
        return cached.hidden;
    }

    BOOL hidden = ComputeShouldHideForYouKeywordItem(
        usernameCandidates, postTextCandidates, hasUsernameFilters,
        hasPostTextFilters);
    BHTForYouKeywordDecisionCache* updated =
        [BHTForYouKeywordDecisionCache new];
    updated.generation = generation;
    updated.hidden = hidden;
    updated.usernameCandidates = usernameCandidates;
    updated.postTextCandidates = postTextCandidates;
    objc_setAssociatedObject(
        outerStatus, &kBHTForYouKeywordDecisionKey, updated,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return hidden;
}

static BOOL BHTShouldHideForYouKeywordItemInURTController(
    id urtController, id item) {
    BOOL hasUsernameFilters = NO;
    BOOL hasPostTextFilters = NO;
    NSUInteger generation =
        [BHTForYouKeywordFilter
            filterGenerationWithUsernameFilters:&hasUsernameFilters
                                 postTextFilters:&hasPostTextFilters];
    if (!(hasUsernameFilters || hasPostTextFilters) ||
        !BHTIsPrimaryForYouURTController(urtController)) {
        return NO;
    }
    return ShouldHideForYouKeywordItem(
        item, generation, hasUsernameFilters, hasPostTextFilters);
}

static BOOL ItemHasTopicBanner(id viewModel) {
    id banner = ItemObjectValue(viewModel, NSSelectorFromString(@"banner"), "banner");
    NSString* bannerClass = banner ? NSStringFromClass([banner classForCoder]) : nil;
    return [bannerClass isEqualToString:@"TFNTwitterURTTimelineStatusTopicBanner"] ||
           [bannerClass hasSuffix:@".URTTimelineStatusTopicBanner"];
}

static BOOL StringContainsTopic(NSString* value) {
    return [value isKindOfClass:[NSString class]] &&
           [[value lowercaseString] containsString:@"topic"];
}

static BOOL StringIsTopicSuggestion(NSString* value) {
    if (!StringContainsTopic(value)) {
        return NO;
    }
    NSString* lower = [value lowercaseString];
    return [lower containsString:@"follow"] || [lower containsString:@"suggest"];
}

static BOOL ShouldHideTimelineItem(id item, BOOL hideWhoToFollow, BOOL hidePrompts,
                                   BOOL hideDiscoverMore, BOOL hideTopics,
                                   BOOL hideTopicsToFollow, BOOL inConversation,
                                   BOOL inProfile,
                                   BOOL filterForYouKeywords,
                                   NSUInteger keywordFilterGeneration,
                                   BOOL hasUsernameFilters,
                                   BOOL hasPostTextFilters) {
    id viewModel = unwrapDataViewItem(item);
    NSString* className = NSStringFromClass([viewModel classForCoder]);
    NSString* component = ItemScribeComponent(viewModel);
    NSString* entryID = ItemEntryID(viewModel);

    if (hidePrompts && [className isEqualToString:@"TwitterURT.URTTimelinePromptViewModel"]) {
        return YES;
    }

    if (hideWhoToFollow && [component isEqualToString:@"suggest_who_to_follow"]) {
        return YES;
    }

    if (hideTopics && ItemHasTopicBanner(viewModel)) {
        return YES;
    }

    BOOL isTopicCollection =
        [className isEqualToString:@"T1TwitterSwift.URTTimelineTopicCollectionViewModel"] ||
        [className isEqualToString:@"TwitterURT.URTTimelineTopicCollectionViewModel"] ||
        [className hasSuffix:@".URTTimelineTopicCollectionViewModel"];
    if (hideTopicsToFollow && inProfile &&
        (isTopicCollection || StringIsTopicSuggestion(component) ||
         StringIsTopicSuggestion(entryID))) {
        return YES;
    }

    if (hideTopics &&
        [className isEqualToString:@"TwitterURT.URTTimelinePromptViewModel"] &&
        (StringContainsTopic(component) || StringContainsTopic(entryID))) {
        return YES;
    }

    if (hideDiscoverMore && inConversation &&
        [entryID hasPrefix:@"tweetdetailrelatedtweets"]) {
        return YES;
    }

    if (hideWhoToFollow && [entryID containsString:@"who-to-follow"]) {
        return YES;
    }

    if (filterForYouKeywords &&
        ShouldHideForYouKeywordItem(
            viewModel, keywordFilterGeneration, hasUsernameFilters,
            hasPostTextFilters)) {
        return YES;
    }

    return NO;
}

static NSArray* FilteredTimelineSections(TFNItemsDataViewController* dataViewController,
                                         NSArray* sections) {
    BOOL hideWhoToFollow = [BHTSettings boolForKey:@"hide_who_to_follow"];
    BOOL hidePrompts = [BHTSettings boolForKey:@"hide_timeline_prompts"];
    BOOL hideDiscoverMore = [BHTSettings boolForKey:@"hide_discover_more"];
    BOOL hideTopics = [BHTSettings boolForKey:@"hide_topics"];
    BOOL hideTopicsToFollow = [BHTSettings boolForKey:@"hide_topics_to_follow"];
    BOOL inConversation =
        IsInHierarchyOfClass(dataViewController, @"T1ConversationContainerViewController");
    BOOL inProfile = IsInHierarchyOfClass(dataViewController, @"T1ProfileViewController");
    BOOL hasUsernameFilters = NO;
    BOOL hasPostTextFilters = NO;
    NSUInteger keywordFilterGeneration =
        [BHTForYouKeywordFilter
            filterGenerationWithUsernameFilters:&hasUsernameFilters
                                 postTextFilters:&hasPostTextFilters];
    BOOL filterForYouKeywords =
        (hasUsernameFilters || hasPostTextFilters) &&
        IsPrimaryForYouTimelineController(dataViewController);

    if (!hideWhoToFollow && !hidePrompts && !hideTopics &&
        !hideTopicsToFollow && !(hideDiscoverMore && inConversation) &&
        !filterForYouKeywords) {
        return sections;
    }

    // Modules can share a section with unrelated items, so filtering is per item;
    // a purely filtered section (like the Discover More one) empties and is dropped.
    BOOL modified = NO;
    NSMutableArray* filteredSections = [NSMutableArray arrayWithCapacity:sections.count];

    for (id section in sections) {
        if (![section isKindOfClass:[NSArray class]]) {
            [filteredSections addObject:section];
            continue;
        }

        NSArray* items = section;
        NSMutableIndexSet* removed = [NSMutableIndexSet indexSet];

        for (NSUInteger i = 0; i < items.count; i++) {
            if (ShouldHideTimelineItem(items[i], hideWhoToFollow, hidePrompts,
                                       hideDiscoverMore, hideTopics,
                                       hideTopicsToFollow, inConversation,
                                       inProfile, filterForYouKeywords,
                                       keywordFilterGeneration,
                                       hasUsernameFilters,
                                       hasPostTextFilters)) {
                [removed addIndex:i];
            }
        }

        if (removed.count == 0) {
            [filteredSections addObject:section];
            continue;
        }

        MarkEmptiedModuleChrome(items, removed);

        modified = YES;
        NSMutableArray* keptItems = [items mutableCopy];
        [keptItems removeObjectsAtIndexes:removed];
        if (keptItems.count > 0) {
            [filteredSections addObject:keptItems];
        }
    }

    return modified ? [filteredSections copy] : sections;
}

%hook T1URTViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;

    // Returning from NeoFreeBird settings must re-evaluate already-loaded
    // rows after either filter list changes. This reloads only X's local table
    // snapshot; it does not issue a timeline/network refresh.
    NSUInteger generation = [BHTForYouKeywordFilter filterGeneration];
    NSNumber* renderedGeneration =
        objc_getAssociatedObject(
            self, &kBHTForYouControllerGenerationKey);
    objc_setAssociatedObject(
        self, &kBHTForYouControllerGenerationKey, @(generation),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (renderedGeneration &&
        renderedGeneration.unsignedIntegerValue != generation &&
        [(UIViewController*)self isViewLoaded] &&
        BHTIsPrimaryForYouURTController(self)) {
        id tableView = ItemObjectValue(
            self, @selector(tableView), "tableView");
        if ([tableView isKindOfClass:UITableView.class]) {
            [(UITableView*)tableView reloadData];
            BHTRecordForYouFilterDiagnostic(
                BHTForYouFilterDiagnosticRenderReloaded);
        }
    }
}

- (double)tableViewHeightForItem:(id)item
                     atIndexPath:(NSIndexPath*)indexPath {
    if (BHTShouldHideForYouKeywordItemInURTController(self, item)) {
        BHTRecordForYouFilterDiagnostic(
            BHTForYouFilterDiagnosticRenderRowCollapsed);
        return 0.0;
    }
    return %orig;
}

- (double)estimatedTableViewHeightForItem:(id)item
                              atIndexPath:(NSIndexPath*)indexPath {
    if (BHTShouldHideForYouKeywordItemInURTController(self, item)) {
        BHTRecordForYouFilterDiagnostic(
            BHTForYouFilterDiagnosticRenderRowCollapsed);
        return 0.0;
    }
    return %orig;
}

%end

%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections restoreScrollPosition:(BOOL)restoreScrollPosition {
    %orig(FilteredTimelineSections(self, sections), restoreScrollPosition);
}

- (void)updateSections:(NSArray*)sections
    reconfigureItemIdentifiers:(NSArray*)identifiers
              withRowAnimation:(long long)animation
                    completion:(id)completion {
    %orig(FilteredTimelineSections(self, sections), identifiers, animation, completion);
}

%end

%ctor {
    %init;

    Class timelineFactoryClass = NSClassFromString(@"T1TimelineFactory");
    Class homeTimelineClass = NSClassFromString(@"TFNTwitterHomeTimeline");
    NSArray<NSString*>* requiredFactorySelectors = @[
        @"homeTimelineForAccount:",
        @"homeCountryFilteredTimelineForAccount:",
        @"homeTopicFilteredTimelineForAccount:",
        @"homeLatestTimelineForAccount:",
        @"homeRankedFollowingTimelineForAccount:",
        @"rootViewControllerForHomeTimeline:homeCountryFilteredTimeline:homeLatestTimeline:homeRankedFollowingTimeline:account:",
    ];
    BOOL canTrackForYouProvenance =
        timelineFactoryClass && homeTimelineClass &&
        [homeTimelineClass
            instancesRespondToSelector:@selector(deserializeStream)];
    for (NSString* selectorName in requiredFactorySelectors) {
        if (![timelineFactoryClass
                instancesRespondToSelector:NSSelectorFromString(
                                               selectorName)]) {
            canTrackForYouProvenance = NO;
            break;
        }
    }
    if (canTrackForYouProvenance) {
        %init(BHTForYouTimelineProvenance);
    }

    Class compatibilityClass = NSClassFromString(@"HomeTimelineContainerViewController");
    Class swiftClass = NSClassFromString(
        @"TwitterHomeFeatureImplementation.HomeTimelineContainerViewController");
    if (compatibilityClass && compatibilityClass != swiftClass) {
        %init(BHTX129HomeContainer);
    }
}
