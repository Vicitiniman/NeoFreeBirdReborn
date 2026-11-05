#import "BHTGlassDockView.h"
#import "BHTLiquidGlassPolicy.h"
#import "Core/BHTBundle.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

static id BHTDockObject(id object, NSString* name) {
    Method method = class_getInstanceMethod([object class], NSSelectorFromString(name));
    char type[16] = {0};
    if (!method || method_getNumberOfArguments(method) != 2) return nil;
    method_getReturnType(method, type, sizeof(type));
    return type[0] == '@' ? ((id (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(name)) : nil;
}

static NSUInteger BHTDockNumber(id object, NSString* name) {
    Method method = class_getInstanceMethod([object class], NSSelectorFromString(name));
    char type[16] = {0};
    if (!method || method_getNumberOfArguments(method) != 2) return 0;
    method_getReturnType(method, type, sizeof(type));
    SEL selector = NSSelectorFromString(name);
    if (type[0] == 'B' || type[0] == 'c') return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
    if (type[0] == 'Q' || type[0] == 'q') return ((NSUInteger (*)(id, SEL))objc_msgSend)(object, selector);
    return 0;
}

@interface BHTGlassDockButton : UIControl
@property(nonatomic, weak) UIView* originalTab;
@property(nonatomic, weak) UIViewController* owner;
@property(nonatomic, strong) UIImageView* glyph;
@property(nonatomic, strong) UILabel* caption;
@property(nonatomic, strong) UILabel* badge;
@property(nonatomic, copy) NSString* symbol;
@property(nonatomic) BOOL showsCaption;
- (void)refreshWithLabels:(BOOL)labels text:(UIColor*)text accent:(UIColor*)accent;
@end

@implementation BHTGlassDockButton
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.isAccessibilityElement = YES;
        _glyph = [UIImageView new];
        _glyph.contentMode = UIViewContentModeScaleAspectFit;
        _caption = [UILabel new];
        _caption.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
        _caption.textAlignment = NSTextAlignmentCenter;
        _caption.adjustsFontSizeToFitWidth = YES;
        _caption.minimumScaleFactor = 0.8;
        _badge = [UILabel new];
        _badge.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
        _badge.textAlignment = NSTextAlignmentCenter;
        _badge.textColor = UIColor.whiteColor;
        _badge.backgroundColor = UIColor.systemRedColor;
        _badge.clipsToBounds = YES;
        for (UIView* child in @[_glyph, _caption, _badge]) {
            child.userInteractionEnabled = NO;
            child.isAccessibilityElement = NO;
            [self addSubview:child];
        }
        [self addTarget:self action:@selector(activate) forControlEvents:UIControlEventTouchUpInside];
        [self addTarget:self action:@selector(press) forControlEvents:UIControlEventTouchDown];
        [self addTarget:self action:@selector(releasePress) forControlEvents:UIControlEventTouchUpInside |
            UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
        UILongPressGestureRecognizer* longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hold:)];
        longPress.minimumPressDuration = 0.5;
        [self addGestureRecognizer:longPress];
    }
    return self;
}
- (void)press {
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionBeginFromCurrentState |
        UIViewAnimationOptionAllowUserInteraction animations:^{ self.transform = CGAffineTransformMakeScale(0.88, 0.88); } completion:nil];
}
- (void)releasePress {
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.32 delay:0 usingSpringWithDamping:0.72
        initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
        animations:^{ self.transform = CGAffineTransformIdentity; } completion:nil];
}
- (void)activate { BHTGlassDockRoute(self.owner, self.originalTab, NO); }
- (BOOL)showOptions:(id)sender { return BHTGlassDockRoute(self.owner, self.originalTab, YES); }
- (void)hold:(UILongPressGestureRecognizer*)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) { [self releasePress]; [self showOptions:gesture]; }
}
- (BOOL)accessibilityActivate { return BHTGlassDockRoute(self.owner, self.originalTab, NO); }
- (void)refreshWithLabels:(BOOL)labels text:(UIColor*)text accent:(UIColor*)accent {
    UIView* native = self.originalTab;
    NSString* page = BHTDockObject(native, @"scribePage");
    NSString* title = BHTDockObject(native, @"title");
    if (![page isKindOfClass:NSString.class]) page = @"";
    if (![title isKindOfClass:NSString.class] || !title.length) title = page;
    BOOL selected = BHTDockNumber(native, @"isSelected") != 0;
    self.selected = selected;
    self.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
    self.accessibilityLabel = title;
    if (![self.caption.text isEqual:title]) self.caption.text = title;
    self.showsCaption = labels;
    if (self.caption.hidden == labels) { self.caption.hidden = !labels; [self setNeedsLayout]; }
    NSString* symbol = BHTGlassDockSymbol(page, selected);
    if (![self.symbol isEqual:symbol]) {
        UIImageSymbolConfiguration* config = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightMedium];
        self.glyph.image = [UIImage systemImageNamed:symbol withConfiguration:config] ?:
            [UIImage systemImageNamed:@"square.grid.2x2" withConfiguration:config];
        self.symbol = symbol;
    }
    UIColor* foreground = selected ? accent : text;
    if (![self.glyph.tintColor isEqual:foreground]) self.glyph.tintColor = foreground;
    if (![self.caption.textColor isEqual:foreground]) self.caption.textColor = foreground;
    NSUInteger count = BHTDockNumber(native, @"badgeCount");
    BOOL unread = BHTDockNumber(native, @"hasUnreadContent") != 0;
    UIColor* badgeColor = count ? UIColor.systemRedColor : accent;
    if (![self.badge.backgroundColor isEqual:badgeColor]) self.badge.backgroundColor = badgeColor;
    NSString* badge = count ? (count > 999 ? @"999+" : [NSString stringWithFormat:@"%lu", (unsigned long)count]) : @"";
    if (![self.badge.text isEqual:badge]) { self.badge.text = badge; [self setNeedsLayout]; }
    if (self.badge.hidden != !(count || unread)) { self.badge.hidden = !(count || unread); [self setNeedsLayout]; }
    self.accessibilityValue = count ? [NSString localizedStringWithFormat:
        [[BHTBundle sharedBundle] localizedStringForKey:@"GLASS_DOCK_UNREAD_FORMAT"], badge] : nil;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    CGFloat centerY = CGRectGetMidY(bounds) - (self.showsCaption ? 6 : 0);
    self.glyph.frame = CGRectMake(CGRectGetMidX(bounds) - 13, centerY - 13, 26, 26);
    self.caption.frame = CGRectMake(2, centerY + 13, MAX(0, bounds.size.width - 4), 13);
    BOOL dot = self.badge.text.length == 0;
    CGFloat width = dot ? 6 : MAX(17, [self.badge sizeThatFits:CGSizeMake(44, 17)].width + 8);
    CGFloat height = dot ? 6 : 17;
    CGFloat badgeX = MAX(1, MIN(CGRectGetMidX(bounds) + 6, CGRectGetMaxX(bounds) - width - 1));
    self.badge.frame = CGRectMake(badgeX, centerY - 17, width, height);
    self.badge.layer.cornerRadius = height / 2;
}
@end

@interface BHTGlassDockView ()
@property(nonatomic, strong) UIScrollView* scroll;
@property(nonatomic, strong) UIView* lens;
@property(nonatomic, strong) CAGradientLayer* rim;
@property(nonatomic, strong) CAGradientLayer* sheen;
@property(nonatomic, strong) NSArray<BHTGlassDockButton*>* buttons;
@property(nonatomic, copy) NSArray<UIView*>* nativeTabs;
@property(nonatomic) BOOL vertical;
@property(nonatomic) NSUInteger selectionUpdates;
@property(nonatomic) CGRect lensTarget;
@property(nonatomic) NSInteger configuredAppearance;
@end

@implementation BHTGlassDockView
- (instancetype)initWithEffect:(UIVisualEffect*)effect {
    if ((self = [super initWithEffect:effect])) {
        self.isAccessibilityElement = NO;
        self.accessibilityContainerType = UIAccessibilityContainerTypeSemanticGroup;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clipsToBounds = YES;
        _rim = [CAGradientLayer layer];
        _rim.colors = @[(id)[UIColor.whiteColor colorWithAlphaComponent:0.22].CGColor,
            (id)[UIColor.whiteColor colorWithAlphaComponent:0.015].CGColor,
            (id)[UIColor.whiteColor colorWithAlphaComponent:0.06].CGColor];
        _rim.locations = @[@0, @0.52, @1];
        [self.contentView.layer addSublayer:_rim];
        _scroll = [UIScrollView new];
        _scroll.showsHorizontalScrollIndicator = NO;
        _scroll.showsVerticalScrollIndicator = NO;
        _scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        [self.contentView addSubview:_scroll];
        _lens = [UIView new];
        _lens.userInteractionEnabled = NO;
        _lens.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.12];
        _lens.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:0.18].CGColor;
        _lens.layer.borderWidth = 0.5;
        _lens.layer.cornerCurve = kCACornerCurveContinuous;
        _lens.clipsToBounds = YES;
        [_scroll addSubview:_lens];
        _sheen = [CAGradientLayer layer];
        _sheen.colors = @[(id)[UIColor.whiteColor colorWithAlphaComponent:0.2].CGColor,
            (id)UIColor.clearColor.CGColor];
        [_lens.layer addSublayer:_sheen];
    }
    return self;
}
- (NSUInteger)buttonCount { return self.buttons.count; }
- (void)updateTabs:(NSArray<UIView*>*)tabs owner:(UIViewController*)owner vertical:(BOOL)vertical
        showLabels:(BOOL)labels textColor:(UIColor*)text accent:(UIColor*)accent {
    NSInteger appearance = self.overrideUserInterfaceStyle;
    if (self.configuredAppearance != appearance) {
        self.configuredAppearance = appearance;
        BOOL dark = appearance == UIUserInterfaceStyleDark;
        self.lens.backgroundColor = dark ? [UIColor.whiteColor colorWithAlphaComponent:0.12] :
            [UIColor.blackColor colorWithAlphaComponent:0.06];
        self.lens.layer.borderColor = [(dark ? UIColor.whiteColor : UIColor.blackColor)
            colorWithAlphaComponent:dark ? 0.18 : 0.08].CGColor;
    }
    BOOL changed = ![self.nativeTabs isEqualToArray:tabs];
    if (changed) {
        for (UIView* button in self.buttons) [button removeFromSuperview];
        NSMutableArray* buttons = [NSMutableArray array];
        for (UIView* native in tabs) {
            BHTGlassDockButton* button = [[BHTGlassDockButton alloc] initWithFrame:CGRectZero];
            button.originalTab = native;
            button.owner = owner;
            if (BHTGlassDockCanRoute(owner, YES)) button.accessibilityCustomActions = @[
                [[UIAccessibilityCustomAction alloc] initWithName:[[BHTBundle sharedBundle] localizedStringForKey:@"GLASS_DOCK_OPTIONS"]
                    target:button selector:@selector(showOptions:)]];
            [self.scroll addSubview:button];
            [buttons addObject:button];
        }
        self.buttons = buttons;
        self.nativeTabs = tabs;
        self.accessibilityElements = buttons;
        self.lensTarget = CGRectZero;
    }
    self.vertical = vertical;
    for (BHTGlassDockButton* button in self.buttons) {
        button.owner = owner;
        [button refreshWithLabels:labels text:text accent:accent];
    }
    [self layoutDock];
}
- (void)layoutSubviews { [super layoutSubviews]; [self layoutDock]; }
- (void)layoutDock {
    if (CGRectIsEmpty(self.bounds)) return;
    CGRect bounds = self.contentView.bounds;
    if (!CGRectEqualToRect(self.scroll.frame, bounds)) self.scroll.frame = bounds;
    CGSize content = BHTGlassDockContentSize(bounds.size, self.buttons.count, self.vertical);
    if (!CGSizeEqualToSize(self.scroll.contentSize, content)) self.scroll.contentSize = content;
    CGRect selected = CGRectZero;
    for (NSUInteger index = 0; index < self.buttons.count; index++) {
        BHTGlassDockButton* button = self.buttons[index];
        CGRect frame = BHTGlassDockItemFrame(bounds.size, index, self.buttons.count, self.vertical);
        CGRect buttonBounds = CGRectMake(0, 0, frame.size.width, frame.size.height);
        CGPoint center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
        if (!CGRectEqualToRect(button.bounds, buttonBounds)) button.bounds = buttonBounds;
        if (!CGPointEqualToPoint(button.center, center)) button.center = center;
        if (button.selected) selected = CGRectInset(frame, self.vertical ? 5 : 3, self.vertical ? 3 : 5);
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!CGRectEqualToRect(self.rim.frame, bounds)) self.rim.frame = bounds;
    [CATransaction commit];
    if (!CGRectEqualToRect(selected, self.lensTarget)) {
        BOOL animate = self.window && !CGRectIsEmpty(self.lensTarget) && !CGRectIsEmpty(selected) &&
            !UIAccessibilityIsReduceMotionEnabled();
        self.lensTarget = selected;
        self.selectionUpdates++;
        void (^layout)(void) = ^{
            self.lens.frame = selected;
            self.lens.layer.cornerRadius = MIN(selected.size.width, selected.size.height) / 2;
        };
        if (animate) [UIView animateWithDuration:0.36 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0
            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:layout completion:nil];
        else layout();
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.sheen.frame = CGRectMake(0, 0, selected.size.width, selected.size.height);
        [CATransaction commit];
        if (!CGRectIsEmpty(selected) && !self.scroll.dragging && !self.scroll.decelerating)
            [self.scroll scrollRectToVisible:CGRectInset(selected, -8, -8) animated:animate];
    }
    if (self.lens.hidden != CGRectIsEmpty(selected)) self.lens.hidden = CGRectIsEmpty(selected);
}
@end
