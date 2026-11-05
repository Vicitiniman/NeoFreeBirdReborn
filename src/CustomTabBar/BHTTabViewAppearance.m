#import "BHTTabViewAppearance.h"
#import "Hooks/HookHelpers.h"

static char BHTTabLabelKey;
static char BHTTabTitleOverrideKey;
static char BHTTabLabelLayoutStateKey;

@interface BHTTabLabelLayoutState : NSObject
@property(nonatomic, weak) UIView* shiftedView;
@property(nonatomic) CGPoint originalCenter;
@property(nonatomic) CGPoint appliedCenter;
@end
@implementation BHTTabLabelLayoutState
@end

static id BHTTabObject(id object, NSString* name) {
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod([object class], selector);
    if (!method || method_getNumberOfArguments(method) != 2) return nil;
    char result[32] = {0};
    method_getReturnType(method, result, sizeof(result));
    if (result[0] != '@') return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static NSString* BHTTabTitle(UIView* tabView) {
    NSString* title = objc_getAssociatedObject(tabView, &BHTTabTitleOverrideKey);
    if (!title) title = BHTTabObject(tabView, @"title");
    return [title isKindOfClass:NSString.class] ? title : @"";
}

void BHTSetTabViewTitleOverride(UIView* tabView, NSString* title) {
    if (!tabView) return;
    NSString* existing = objc_getAssociatedObject(tabView, &BHTTabTitleOverrideKey);
    if (existing == title || [existing isEqualToString:title]) return;
    objc_setAssociatedObject(tabView, &BHTTabTitleOverrideKey, title,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
    BHTRefreshTabViewAppearance(tabView);
    [tabView setNeedsLayout];
}

void BHTRefreshTabViewAppearance(UIView* tabView) {
    if (!tabView) return;
    BOOL show = [BHTSettings boolForKey:@"restore_tab_labels"];
    UILabel* label = objc_getAssociatedObject(tabView, &BHTTabLabelKey);
    // With labels off there is no label to update. Messaging nil reports
    // hidden == NO, which otherwise schedules a new layout on every pass.
    if (!show && !label) return;
    if (show && !label) {
        label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
        label.textAlignment = NSTextAlignmentCenter;
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.8;
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        label.userInteractionEnabled = NO;
        label.isAccessibilityElement = NO;
        [tabView addSubview:label];
        objc_setAssociatedObject(tabView, &BHTTabLabelKey, label,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [tabView setNeedsLayout];
    }
    NSString* title = BHTTabTitle(tabView);
    if (![label.text isEqualToString:title]) label.text = title;
    BOOL hidden = !show || title.length == 0;
    if (label.hidden != hidden) {
        label.hidden = hidden;
        [tabView setNeedsLayout];
    }
    if (hidden) return;
    BOOL selected = NO;
    SEL selector = NSSelectorFromString(@"isSelected");
    Method method = class_getInstanceMethod([tabView class], selector);
    if (method && method_getNumberOfArguments(method) == 2) {
        char result[16] = {0};
        method_getReturnType(method, result, sizeof(result));
        if (result[0] == 'B' || result[0] == 'c') {
            selected = ((BOOL (*)(id, SEL))objc_msgSend)(tabView, selector);
        }
    }
    label.textColor = selected ? CurrentAccentColor() : [Palette currentSecondaryTextColor];
}

void BHTPrepareTabViewLayout(UIView* tabView) {
    BHTTabLabelLayoutState* state =
        objc_getAssociatedObject(tabView, &BHTTabLabelLayoutStateKey);
    UIView* shifted = state.shiftedView;
    // Restore only our last adjustment. If X already moved the view (for an
    // animation or a new layout), keep that newer native position.
    if (shifted && fabs(shifted.center.x - state.appliedCenter.x) < 0.5 &&
        fabs(shifted.center.y - state.appliedCenter.y) < 0.5) {
        shifted.center = state.originalCenter;
    }
    state.shiftedView = nil;
}

void BHTLayoutTabViewAppearance(UIView* tabView) {
    BHTRefreshTabViewAppearance(tabView);
    UILabel* label = objc_getAssociatedObject(tabView, &BHTTabLabelKey);
    if (!label || label.hidden || CGRectIsEmpty(tabView.bounds)) return;
    CGRect bounds = tabView.bounds;
    UIImageView* icon = BHTTabObject(tabView, @"imageView");
    CGRect iconFrame = CGRectZero;
    if ([icon isKindOfClass:UIImageView.class] && [icon isDescendantOfView:tabView]) {
        iconFrame = [icon convertRect:icon.bounds toView:tabView];
    }
    BOOL horizontal = CGRectGetWidth(bounds) > 104 && CGRectGetHeight(bounds) < 72;
    if (horizontal && !CGRectIsEmpty(iconFrame) &&
        CGRectGetMaxX(iconFrame) < CGRectGetMidX(bounds)) {
        CGFloat left = CGRectGetMaxX(iconFrame) + 8;
        label.textAlignment = NSTextAlignmentLeft;
        label.frame = CGRectMake(left, CGRectGetMinY(bounds),
                                 MAX(0, CGRectGetMaxX(bounds) - left - 8),
                                 CGRectGetHeight(bounds));
    } else {
        label.textAlignment = NSTextAlignmentCenter;
        CGFloat height = MIN(13, CGRectGetHeight(bounds));
        label.frame = CGRectMake(CGRectGetMinX(bounds) + 2,
                                 CGRectGetMaxY(bounds) - height,
                                 MAX(0, CGRectGetWidth(bounds) - 4), height);
        CGFloat shift = MIN(8, MAX(0, CGRectGetMaxY(iconFrame) + 1 - CGRectGetMinY(label.frame)));
        UIView* container = BHTTabObject(tabView, @"transformContainer");
        if (![container isKindOfClass:UIView.class] || container == tabView ||
            ![container isDescendantOfView:tabView]) container = icon;
        if (shift > 0 && container && !CGRectIsEmpty(iconFrame)) {
            BHTTabLabelLayoutState* state =
                objc_getAssociatedObject(tabView, &BHTTabLabelLayoutStateKey);
            if (!state) {
                state = [BHTTabLabelLayoutState new];
                objc_setAssociatedObject(tabView, &BHTTabLabelLayoutStateKey, state,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            state.shiftedView = container;
            state.originalCenter = container.center;
            container.center = CGPointMake(container.center.x, container.center.y - shift);
            state.appliedCenter = container.center;
        }
    }
    if (tabView.subviews.lastObject != label) {
        [tabView bringSubviewToFront:label];
    }
}
