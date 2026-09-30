#import "Profile/BHTProfileTextSelection.h"

#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"
#import <objc/message.h>
#import <objc/runtime.h>

static char kBHTProfileTextInteractionKey;

static id BHTProfileTextObject(id object, NSString* selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static NSAttributedString* BHTProfileFieldText(UIView* field) {
    if ([field isKindOfClass:UILabel.class]) {
        UILabel* label = (UILabel*)field;
        return label.attributedText ?: [[NSAttributedString alloc] initWithString:label.text ?: @""];
    }
    id model = BHTProfileTextObject(field, @"textModel");
    id text = BHTProfileTextObject(model, @"attributedString");
    if (![text isKindOfClass:NSAttributedString.class]) {
        text = BHTProfileTextObject(field, @"text");
    }
    if ([text isKindOfClass:NSAttributedString.class]) return text;
    if ([text isKindOfClass:NSString.class]) {
        return [[NSAttributedString alloc] initWithString:text];
    }
    return nil;
}

@class BHTProfileTextInteraction;

@interface BHTSelectableProfileTextView : UITextView
@property(nonatomic, weak) BHTProfileTextInteraction* interaction;
@end

@interface BHTProfileTextInteraction : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, weak) UIView* field;
@property(nonatomic, weak) UIView* selectionSource;
@property(nonatomic, strong) BHTSelectableProfileTextView* selectionView;
@property(nonatomic, strong) UILongPressGestureRecognizer* longPress;
@property(nonatomic, strong) UITapGestureRecognizer* outsideTap;
@property(nonatomic, weak) UIPanGestureRecognizer* profilePan;
@property(nonatomic, strong) UIAccessibilityCustomAction* accessibilityAction;
@property(nonatomic) CGFloat originalAlpha;
@property(nonatomic) BOOL originalInteractionEnabled;
- (void)endSelection;
@end

static __weak BHTProfileTextInteraction* BHTActiveProfileTextInteraction;

@implementation BHTSelectableProfileTextView
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) [self.interaction endSelection];
}
@end

@implementation BHTProfileTextInteraction

- (UIView*)textSource {
    if ([self.field isKindOfClass:UIButton.class]) {
        return ((UIButton*)self.field).titleLabel;
    }
    return self.field;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer*)recognizer
       shouldReceiveTouch:(UITouch*)touch {
    if (recognizer == self.outsideTap) {
        return ![touch.view isDescendantOfView:self.selectionView];
    }
    return [BHTSettings boolForKey:@"copy_profile_info"] &&
           BHTProfileFieldText([self textSource]).length > 0;
}

- (void)selectAtPoint:(CGPoint)point {
    if (![BHTSettings boolForKey:@"copy_profile_info"]) return;
    UIView* source = [self textSource];
    NSAttributedString* text = BHTProfileFieldText(source);
    if (!source.window || !source.superview || !text.length) return;
    BHTEndProfileTextSelection();

    // Build UIKit's selection layer only while it is in use. Twitter's labels
    // and link recognizers continue to own every ordinary tap and layout pass.
    BHTSelectableProfileTextView* selection =
        [[BHTSelectableProfileTextView alloc] initWithFrame:source.frame];
    selection.editable = NO;
    selection.selectable = YES;
    selection.backgroundColor = UIColor.clearColor;
    selection.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    selection.textContainerInset = UIEdgeInsetsZero;
    selection.textContainer.lineFragmentPadding = 0;
    selection.showsVerticalScrollIndicator = NO;
    selection.showsHorizontalScrollIndicator = NO;
    selection.tintColor = self.field.tintColor;
    UIFont* font = BHTProfileTextObject(source, @"font");
    UIColor* color = BHTProfileTextObject(source, @"textColor");
    NSDictionary* attributes = [text attributesAtIndex:0 effectiveRange:NULL];
    if (![font isKindOfClass:UIFont.class]) font = attributes[NSFontAttributeName];
    if (![color isKindOfClass:UIColor.class]) color = attributes[NSForegroundColorAttributeName];
    selection.font = [font isKindOfClass:UIFont.class] ? font :
        [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    selection.textColor = [color isKindOfClass:UIColor.class] ? color : UIColor.labelColor;
    if ([source isKindOfClass:UILabel.class]) {
        selection.textAlignment = ((UILabel*)source).textAlignment;
    }
    // Profile badges are attachments, not part of the name to copy.
    selection.text = [text.string stringByReplacingOccurrencesOfString:@"\uFFFC" withString:@""];
    selection.accessibilityLabel = source.accessibilityLabel;
    self.selectionSource = source;
    self.originalAlpha = source.alpha;
    self.selectionView = selection;
    selection.interaction = self;
    selection.translatesAutoresizingMaskIntoConstraints = NO;
    [source.superview addSubview:selection];
    [NSLayoutConstraint activateConstraints:@[
        [selection.leadingAnchor constraintEqualToAnchor:source.leadingAnchor],
        [selection.trailingAnchor constraintEqualToAnchor:source.trailingAnchor],
        [selection.topAnchor constraintEqualToAnchor:source.topAnchor],
        [selection.bottomAnchor constraintEqualToAnchor:source.bottomAnchor],
    ]];
    [source.superview layoutIfNeeded];
    source.alpha = 0;
    BHTActiveProfileTextInteraction = self;

    self.outsideTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(tappedOutside:)];
    self.outsideTap.delegate = self;
    self.outsideTap.cancelsTouchesInView = NO;
    [source.window addGestureRecognizer:self.outsideTap];
    for (UIView* ancestor = source.superview; ancestor; ancestor = ancestor.superview) {
        if ([ancestor isKindOfClass:UIScrollView.class]) {
            self.profilePan = ((UIScrollView*)ancestor).panGestureRecognizer;
            [self.profilePan addTarget:self action:@selector(profilePanned:)];
            break;
        }
    }

    [selection becomeFirstResponder];
    UITextPosition* position = [selection closestPositionToPoint:point];
    UITextRange* word = position ? [selection.tokenizer
        rangeEnclosingPosition:position withGranularity:UITextGranularityWord
                   inDirection:UITextStorageDirectionForward] : nil;
    if (!word && position &&
        [selection offsetFromPosition:selection.beginningOfDocument toPosition:position] > 0) {
        position = [selection positionFromPosition:position offset:-1];
        if (position) word = [selection.tokenizer rangeEnclosingPosition:position
            withGranularity:UITextGranularityWord inDirection:UITextStorageDirectionForward];
    }
    selection.selectedTextRange = word;
}

- (void)heldField:(UILongPressGestureRecognizer*)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        [self selectAtPoint:[recognizer locationInView:[self textSource]]];
    } else if (recognizer.state == UIGestureRecognizerStateEnded &&
               self.selectionView.selectedTextRange) {
        UITextView* selection = self.selectionView;
        CGRect rect = [selection firstRectForRange:selection.selectedTextRange];
        [UIMenuController.sharedMenuController showMenuFromView:selection rect:rect];
    }
}

- (BOOL)selectForAccessibility:(UIAccessibilityCustomAction*)action {
    UIView* source = [self textSource];
    [self selectAtPoint:CGPointMake(CGRectGetMidX(source.bounds), CGRectGetMidY(source.bounds))];
    return self.selectionView != nil;
}

- (void)tappedOutside:(UITapGestureRecognizer*)recognizer {
    if (recognizer.state == UIGestureRecognizerStateEnded) [self endSelection];
}

- (void)profilePanned:(UIPanGestureRecognizer*)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) [self endSelection];
}

- (void)endSelection {
    BHTSelectableProfileTextView* selection = self.selectionView;
    if (!selection) return;
    self.selectionView = nil;
    selection.interaction = nil;
    [selection resignFirstResponder];
    [UIMenuController.sharedMenuController hideMenu];
    [self.outsideTap.view removeGestureRecognizer:self.outsideTap];
    self.outsideTap = nil;
    [self.profilePan removeTarget:self action:@selector(profilePanned:)];
    self.profilePan = nil;
    self.selectionSource.alpha = self.originalAlpha;
    self.selectionSource = nil;
    [selection removeFromSuperview];
    if (BHTActiveProfileTextInteraction == self) BHTActiveProfileTextInteraction = nil;
}

@end

void BHTEndProfileTextSelection(void) {
    [BHTActiveProfileTextInteraction endSelection];
}

void BHTInstallProfileTextSelection(UIView* field) {
    if (![field isKindOfClass:UIView.class]) return;
    BHTProfileTextInteraction* interaction =
        objc_getAssociatedObject(field, &kBHTProfileTextInteractionKey);
    BOOL enabled = [BHTSettings boolForKey:@"copy_profile_info"];
    if (!enabled && !interaction) return;
    if (!interaction) {
        interaction = [BHTProfileTextInteraction new];
        interaction.field = field;
        interaction.originalInteractionEnabled = field.userInteractionEnabled;
        interaction.longPress = [[UILongPressGestureRecognizer alloc]
            initWithTarget:interaction action:@selector(heldField:)];
        interaction.longPress.minimumPressDuration = 0.5;
        interaction.longPress.delegate = interaction;
        for (UIGestureRecognizer* native in field.gestureRecognizers) {
            if ([native isKindOfClass:UILongPressGestureRecognizer.class]) {
                [native requireGestureRecognizerToFail:interaction.longPress];
            }
        }
        [field addGestureRecognizer:interaction.longPress];
        objc_setAssociatedObject(field, &kBHTProfileTextInteractionKey, interaction,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSString* title = [[BHTBundle sharedBundle] localizedStringForKey:@"PROFILE_SELECT_TEXT"];
        interaction.accessibilityAction = [[UIAccessibilityCustomAction alloc]
            initWithName:title target:interaction selector:@selector(selectForAccessibility:)];
    }
    NSArray* actions = field.accessibilityCustomActions ?: @[];
    if (enabled && ![actions containsObject:interaction.accessibilityAction]) {
        field.accessibilityCustomActions = [actions arrayByAddingObject:interaction.accessibilityAction];
    } else if (!enabled && [actions containsObject:interaction.accessibilityAction]) {
        NSMutableArray* remaining = [actions mutableCopy];
        [remaining removeObjectIdenticalTo:interaction.accessibilityAction];
        field.accessibilityCustomActions = remaining;
    }
    interaction.longPress.enabled = enabled;
    field.userInteractionEnabled = enabled || interaction.originalInteractionEnabled;
    if (!enabled) [interaction endSelection];
}
