//
//  AppLifecycle.x
//  NeoFreeBird
//

#import "HookHelpers.h"
#import "Branding/BHTBranding.h"
#import <stdlib.h>

// MARK: - Padlock helpers

static const NSInteger PadlockOverlayTag = 909;

static NSArray<UIWindow*>* allActiveWindows(void) {
    NSMutableArray<UIWindow*>* result = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene* ws = (UIWindowScene*)scene;
                for (UIWindow* w in ws.windows) {
                    if (!w.hidden)
                        [result addObject:w];
                }
            }
        }
    }
    if (result.count == 0) {
        for (UIWindow* w in UIApplication.sharedApplication.windows) {
            if (!w.hidden)
                [result addObject:w];
        }
    }
    return result;
}

static UIWindow* activeKeyWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene* ws = (UIWindowScene*)scene;
                for (UIWindow* w in ws.windows) {
                    if (w.isKeyWindow)
                        return w;
                }
                for (UIWindow* w in ws.windows) {
                    if (!w.hidden)
                        return w;
                }
            }
        }
    }
    for (UIWindow* w in UIApplication.sharedApplication.windows) {
        if (w.isKeyWindow)
            return w;
    }
    for (UIWindow* w in UIApplication.sharedApplication.windows) {
        if (!w.hidden)
            return w;
    }
    return nil;
}

static UIViewController* topViewController(UIViewController* root) {
    if (!root)
        return nil;
    UIViewController* vc = root;
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    if ([vc isKindOfClass:[UINavigationController class]]) {
        vc = ((UINavigationController*)vc).visibleViewController ?: vc;
    }
    if ([vc isKindOfClass:[UITabBarController class]]) {
        UIViewController* sel = ((UITabBarController*)vc).selectedViewController;
        if (sel)
            vc = sel;
    }
    return vc;
}

static void showPadlockOverlay(void) {
    UIWindow* window = activeKeyWindow();
    if (!window)
        return;

    for (UIWindow* w in allActiveWindows()) {
        for (UIView* v in w.subviews) {
            if (v.tag == PadlockOverlayTag)
                [v removeFromSuperview];
        }
    }

    UIView* overlay = [[UIView alloc] initWithFrame:window.bounds];
    overlay.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.backgroundColor = UIColor.systemBackgroundColor;
    overlay.userInteractionEnabled = YES;
    overlay.tag = PadlockOverlayTag;

    UIImageView* icon = [[UIImageView alloc]
        initWithImage:[UIImage systemImageNamed:@"lock.fill"]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = UIColor.labelColor;

    UILabel* label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text =
        [[BHTBundle sharedBundle] localizedStringForKey:@"PADLOCK_LOCKED_LABEL"];
    label.textColor = UIColor.labelColor;
    label.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
    label.textAlignment = NSTextAlignmentCenter;

    [overlay addSubview:icon];
    [overlay addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [icon.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor
                                           constant:-20],
        [label.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
        [label.topAnchor constraintEqualToAnchor:icon.bottomAnchor
                                        constant:8]
    ]];

    [window addSubview:overlay];
}

static void removePadlockOverlay(void) {
    for (UIWindow* w in allActiveWindows()) {
        NSMutableArray<UIView*>* toRemove = [NSMutableArray array];
        for (UIView* v in w.subviews) {
            if (v.tag == PadlockOverlayTag)
                [toRemove addObject:v];
        }
        for (UIView* v in toRemove)
            [v removeFromSuperview];
    }
}

// Deliberately in-memory only: the padlock must always re-prompt after a
// relaunch, so persisting this would only risk skipping it.
static BOOL padlockAuthenticated = NO;
static BOOL padlockPresentationRetryScheduled = NO;
static NSUInteger padlockAuthenticationGeneration = 0;
static __weak AuthViewController* activePadlockController = nil;

static BOOL isAuthenticated(void) {
    return padlockAuthenticated;
}

static void setAuthenticated(BOOL yes) {
    padlockAuthenticated = yes;
}

static void presentAuthIfNeeded(void);

static void retryPadlockPresentation(void) {
    if (padlockPresentationRetryScheduled) return;
    padlockPresentationRetryScheduled = YES;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)(250 * NSEC_PER_MSEC)),
        dispatch_get_main_queue(), ^{
            padlockPresentationRetryScheduled = NO;
            if ([BHTSettings boolForKey:@"padlock"] &&
                !isAuthenticated() &&
                UIApplication.sharedApplication.applicationState ==
                    UIApplicationStateActive) {
                presentAuthIfNeeded();
            }
        });
}

static void presentAuthIfNeeded(void) {
    if (isAuthenticated()) {
        removePadlockOverlay();
        return;
    }

    UIWindow* window = activeKeyWindow();
    UIViewController* root = window.rootViewController;
    if (!window || !root) {
        showPadlockOverlay();
        retryPadlockPresentation();
        return;
    }

    UIViewController* host = topViewController(root);
    if (!host || !host.view.window) {
        retryPadlockPresentation();
        return;
    }
    if ([host isKindOfClass:AuthViewController.class]) {
        activePadlockController = (AuthViewController*)host;
        // The full-screen authentication surface now protects the content.
        // Remove the separate app-switcher cover so a failed/cancelled attempt
        // can expose its retry button.
        removePadlockOverlay();
        return;
    }
    if (activePadlockController.presentingViewController ||
        activePadlockController.isBeingPresented) {
        return;
    }
    if (host.isBeingPresented || host.isBeingDismissed) {
        retryPadlockPresentation();
        return;
    }

    AuthViewController* auth = [[AuthViewController alloc] init];
    NSUInteger authenticationGeneration =
        padlockAuthenticationGeneration;
    activePadlockController = auth;
    auth.completion = ^(BOOL authenticated) {
        BOOL lockEnabled =
            [BHTSettings boolForKey:@"padlock"];
        BOOL currentSuccess =
            authenticated &&
            authenticationGeneration ==
                padlockAuthenticationGeneration &&
            lockEnabled;

        if (!lockEnabled) {
            // A setting/profile change can disable the lock while the system
            // authentication sheet is open. Never leave its privacy overlay
            // stranded after the feature has been turned off.
            setAuthenticated(NO);
            removePadlockOverlay();
        } else if (currentSuccess) {
            // Face ID temporarily makes the app inactive. Accept the result
            // for the current foreground generation, then keep the privacy
            // cover until applicationDidBecomeActive if necessary.
            setAuthenticated(YES);
            if (UIApplication.sharedApplication.applicationState ==
                UIApplicationStateActive) {
                removePadlockOverlay();
            } else {
                showPadlockOverlay();
            }
        } else if (authenticated &&
                   UIApplication.sharedApplication.applicationState ==
                       UIApplicationStateActive) {
            setAuthenticated(NO);
            showPadlockOverlay();
            retryPadlockPresentation();
        } else {
            setAuthenticated(NO);
        }
        activePadlockController = nil;
    };
    auth.modalPresentationStyle = UIModalPresentationFullScreen;
    if ([auth respondsToSelector:@selector(setModalInPresentation:)]) {
        auth.modalInPresentation = YES;
    }

    // topViewController already walks to the final presented controller. Never
    // dismiss an unrelated compose/share/settings modal just to show the lock;
    // present above it and leave the user's navigation state intact.
    [host presentViewController:auth
                       animated:NO
                     completion:^{
                         removePadlockOverlay();
                     }];
}

// MARK: - App Delegate hooks

%hook T1AppDelegate

- (_Bool)application:(__unsafe_unretained UIApplication*)application
    didFinishLaunchingWithOptions:(__unsafe_unretained id)arg2 {
    _Bool orig = %orig;

    [BHTManager cleanCache];
    if ([BHTSettings boolForKey:@"flex_twitter"]) {
        [[%c(FLEXManager) sharedManager] showExplorer];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        applySelectedThemeColor();
    });

    return orig;
}

- (void)applicationDidBecomeActive:(__unsafe_unretained id)arg1 {
    %orig;

    applySelectedThemeColor();

    if ([BHTSettings boolForKey:@"padlock"]) {
        if (isAuthenticated()) {
            removePadlockOverlay();
        } else {
            showPadlockOverlay();
            dispatch_async(dispatch_get_main_queue(), ^{
                presentAuthIfNeeded();
            });
        }
    } else {
        removePadlockOverlay();
    }
}

- (void)applicationWillResignActive:(__unsafe_unretained id)arg1 {
    %orig;

    if ([BHTSettings boolForKey:@"padlock"]) {
        // Face ID and other system authentication sheets temporarily make the
        // app inactive. Cover the UI for privacy here, but invalidate the
        // authenticated session only after a real background transition.
        showPadlockOverlay();
    }

    if ([BHTSettings boolForKey:@"flex_twitter"]) {
        [[%c(FLEXManager) sharedManager] showExplorer];
    }
}

- (void)applicationDidEnterBackground:(__unsafe_unretained id)arg1 {
    %orig;

    if ([BHTSettings boolForKey:@"padlock"]) {
        // A completed authentication attempt that belongs to a prior foreground
        // session must never unlock the next one.
        padlockAuthenticationGeneration++;
        setAuthenticated(NO);
        showPadlockOverlay();
    }
}

%end

// MARK: - Restore Launch Animation

// The launch animation reveals the app through a growing X-shaped mask
// (revealMaskLayer / holePathInView); detach it so the logo zoom is kept but
// the splash simply fades out.

static char kBHTOriginalLaunchLogoImageKey;
static char kBHTLaunchResolvedLogoViewKey;

static void stripLaunchRevealMask(UIView* view) {
    // The X-shaped hole lives on the container subview's layer.mask; the top
    // view itself is unmasked, but clear it too for safety.
    view.layer.mask = nil;
    for (UIView* sub in view.subviews) {
        sub.layer.mask = nil;
    }
}

static UIImageView* launchImageViewFromCandidate(id candidate) {
    if ([candidate isKindOfClass:UIImageView.class]) {
        return candidate;
    }
    if (![candidate isKindOfClass:UIView.class]) return nil;

    __block UIImageView* nestedImage = nil;
    EnumerateSubviewsRecursively(candidate, ^(UIView* subview) {
        if (!nestedImage &&
            [subview isKindOfClass:UIImageView.class]) {
            nestedImage = (UIImageView*)subview;
        }
    });
    return nestedImage;
}

static UIImageView* launchLogoImageView(UIView* launchView) {
    UIImageView* cached =
        objc_getAssociatedObject(launchView,
                                 &kBHTLaunchResolvedLogoViewKey);
    if (cached && [cached isDescendantOfView:launchView]) {
        return cached;
    }
    if (cached) {
        objc_setAssociatedObject(
            launchView, &kBHTLaunchResolvedLogoViewKey, nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // X 12.9's Swift implementation stores a lazy `logoView`. Prefer that
    // stable semantic path when it is Objective-C visible, then fall back to
    // the centered square image in the launch-only hierarchy.
    for (NSString* selectorName in
         @[@"logoView", @"logoImageView", @"xLogoImageView"]) {
        SEL selector = NSSelectorFromString(selectorName);
        if (![launchView respondsToSelector:selector]) continue;
        id candidate = nil;
        @try {
            candidate =
                ((id (*)(id, SEL))objc_msgSend)(launchView, selector);
        } @catch (__unused NSException* exception) {
        }
        UIImageView* candidateImage =
            launchImageViewFromCandidate(candidate);
        if (candidateImage) {
            objc_setAssociatedObject(
                launchView, &kBHTLaunchResolvedLogoViewKey,
                candidateImage, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return candidateImage;
        }
    }

    // The Swift field is named `$__lazy_storage_$_logoView` in X 12.9 and may
    // not have an Objective-C getter. Resolve object ivars by their semantic
    // name before using geometry as the final compatibility fallback.
    for (Class currentClass = launchView.class;
         currentClass && currentClass != UIView.class;
         currentClass = class_getSuperclass(currentClass)) {
        unsigned int count = 0;
        Ivar* ivars = class_copyIvarList(currentClass, &count);
        for (unsigned int index = 0; index < count; index++) {
            Ivar ivar = ivars[index];
            const char* name = ivar_getName(ivar);
            const char* type = ivar_getTypeEncoding(ivar);
            if (!name || !type || type[0] != '@') continue;
            NSString* ivarName =
                [NSString stringWithUTF8String:name].lowercaseString;
            if (![ivarName containsString:@"logoview"]) continue;
            id candidate = nil;
            @try {
                candidate = object_getIvar(launchView, ivar);
            } @catch (__unused NSException* exception) {
            }
            UIImageView* candidateImage =
                launchImageViewFromCandidate(candidate);
            if (candidateImage) {
                free(ivars);
                objc_setAssociatedObject(
                    launchView, &kBHTLaunchResolvedLogoViewKey,
                    candidateImage, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                return candidateImage;
            }
        }
        free(ivars);
    }

    CGPoint center =
        CGPointMake(CGRectGetMidX(launchView.bounds),
                    CGRectGetMidY(launchView.bounds));
    __block UIImageView* best = nil;
    __block CGFloat bestScore = CGFLOAT_MAX;
    EnumerateSubviewsRecursively(launchView, ^(UIView* candidate) {
        if (![candidate isKindOfClass:UIImageView.class] ||
            candidate.hidden || candidate.alpha < 0.05) {
            return;
        }
        UIImageView* imageView = (UIImageView*)candidate;
        CGRect rect =
            [imageView convertRect:imageView.bounds toView:launchView];
        CGFloat width = CGRectGetWidth(rect);
        CGFloat height = CGRectGetHeight(rect);
        if (width < 18.0 || height < 18.0 ||
            width > 180.0 || height > 180.0 ||
            fabs(width - height) > 20.0) {
            return;
        }
        CGFloat score =
            hypot(CGRectGetMidX(rect) - center.x,
                  CGRectGetMidY(rect) - center.y);
        if (score < bestScore) {
            best = imageView;
            bestScore = score;
        }
    });
    if (best) {
        objc_setAssociatedObject(
            launchView, &kBHTLaunchResolvedLogoViewKey, best,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return best;
}

static UIColor* launchLogoColor(void) {
    // Keep the animated bird aligned with the active preset/custom accent in
    // both light and dark appearances.
    return CurrentAccentColor();
}

static UIImageView* applyClassicLaunchBird(UIView* launchView) {
    UIImageView* logoView = launchLogoImageView(launchView);
    if (!logoView) return nil;
    if (!objc_getAssociatedObject(logoView,
                                  &kBHTOriginalLaunchLogoImageKey) &&
        logoView.image) {
        objc_setAssociatedObject(
            logoView, &kBHTOriginalLaunchLogoImageKey,
            logoView.image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BHTApplyTwitterBirdLaunchToImageView(logoView, launchLogoColor());
    return logoView;
}

static NSTimeInterval classicLaunchAnimationDuration(void) {
    if (UIAccessibilityIsReduceMotionEnabled()) return 0.16;
    return UIDevice.currentDevice.userInterfaceIdiom ==
                   UIUserInterfaceIdiomPad
               ? 0.26
               : 0.30;
}

%hook T1AnimatedLaunchScreenView

- (void)didMoveToWindow {
    %orig;
    // Run before the first window commit as well as after layout. The packaged
    // xLogo replacement covers the pre-injection system splash; this covers
    // the earliest frame owned by X's animated launch view.
    if ([BHTSettings boolForKey:@"restore_launch_animation"]) {
        UIView* launchView = (UIView*)self;
        stripLaunchRevealMask(launchView);
        UIImageView* logoView = applyClassicLaunchBird(launchView);
        if (launchView.window) {
            launchView.hidden = NO;
            launchView.alpha = 1.0;
            logoView.alpha = 1.0;
            logoView.transform = CGAffineTransformIdentity;
        }
    }
}

- (void)layoutSubviews {
    %orig;
    // layoutSubviews re-installs the mask each pass, so re-strip after %orig.
    if ([BHTSettings boolForKey:@"restore_launch_animation"]) {
        stripLaunchRevealMask((UIView*)self);
        applyClassicLaunchBird((UIView*)self);
    }
}

- (void)animateRevealWithCompletion:(id)completion {
    if (![BHTSettings boolForKey:@"restore_launch_animation"]) {
        %orig;
        return;
    }
    UIView* launchView = (UIView*)self;
    stripLaunchRevealMask(launchView);
    UIImageView* logoView = applyClassicLaunchBird(launchView);
    void (^completionBlock)(void) = [completion copy];

    // X's reveal animates a mask and repeatedly reconfigures the logo. That
    // path is costly on older iPads and magnifies the small navigation glyph.
    // A single compositor-backed scale and fade keeps the classic launch feel
    // while using the dedicated high-resolution bird.
    [launchView.layer removeAllAnimations];
    [logoView.layer removeAllAnimations];
    launchView.hidden = NO;
    launchView.alpha = 1.0;
    launchView.userInteractionEnabled = NO;
    logoView.alpha = 1.0;
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    logoView.transform =
        reduceMotion ? CGAffineTransformIdentity
                     : CGAffineTransformMakeScale(0.94, 0.94);

    [UIView animateWithDuration:classicLaunchAnimationDuration()
                          delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionCurveEaseOut |
                                UIViewAnimationOptionAllowAnimatedContent
                     animations:^{
                         launchView.alpha = 0.0;
                         if (!reduceMotion) {
                             logoView.transform =
                                 CGAffineTransformMakeScale(1.28, 1.28);
                         }
                     }
                     completion:^(__unused BOOL finished) {
                         launchView.hidden = YES;
                         if (completionBlock) completionBlock();
                     }];
}

%end
