// Minimal UIKit stand-ins for the Foundation runner. The production adapter
// is compiled below these; layout requests are coalesced like a UI transaction.
@class UIColor;
@interface UIView : NSObject
@property(nonatomic, strong) UIColor* backgroundColor;
@property(nonatomic) BOOL opaque;
@property(nonatomic) CGRect frame;
@property(nonatomic) CGRect bounds;
@property(nonatomic) CGPoint center;
@property(nonatomic, getter=isHidden) BOOL hidden;
@property(nonatomic) BOOL userInteractionEnabled;
@property(nonatomic) BOOL isAccessibilityElement;
@property(nonatomic) BOOL accessibilityElementsHidden;
@property(nonatomic, weak) UIView* superview;
@property(nonatomic, weak) UIView* window;
@property(nonatomic, readonly) NSArray<UIView*>* subviews;
@property(nonatomic) BOOL layoutPending;
@property(nonatomic) NSUInteger layoutRequestCount;
@property(nonatomic) NSUInteger reorderCount;
- (instancetype)initWithFrame:(CGRect)frame;
- (void)addSubview:(UIView*)view;
- (void)removeFromSuperview;
- (void)bringSubviewToFront:(UIView*)view;
- (void)setNeedsLayout;
- (BOOL)isDescendantOfView:(UIView*)view;
- (CGRect)convertRect:(CGRect)rect toView:(UIView*)view;
+ (void)performWithoutAnimation:(void (^)(void))changes;
@end

@implementation UIView {
    NSMutableArray<UIView*>* _children;
}
+ (void)performWithoutAnimation:(void (^)(void))changes { changes(); }
- (instancetype)init { return [self initWithFrame:CGRectZero]; }
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super init])) {
        _children = [NSMutableArray array];
        _frame = frame;
    }
    return self;
}
- (CGRect)bounds { return CGRectMake(0, 0, self.frame.size.width, self.frame.size.height); }
- (void)setBounds:(CGRect)bounds {
    CGRect frame = self.frame;
    frame.size = bounds.size;
    self.frame = frame;
}
- (CGPoint)center { return CGPointMake(CGRectGetMidX(self.frame), CGRectGetMidY(self.frame)); }
- (void)setCenter:(CGPoint)center {
    CGRect frame = self.frame;
    frame.origin = CGPointMake(center.x - frame.size.width / 2, center.y - frame.size.height / 2);
    self.frame = frame;
}
- (NSArray<UIView*>*)subviews { return [_children copy]; }
- (void)addSubview:(UIView*)view {
    [_children addObject:view];
    view.superview = self;
    [self setNeedsLayout];
}
- (void)bringSubviewToFront:(UIView*)view {
    self.reorderCount++;
    [_children removeObjectIdenticalTo:view];
    [_children addObject:view];
    [self setNeedsLayout];
}
- (void)removeFromSuperview {
    UIView* parent = self.superview;
    if (parent) [parent->_children removeObjectIdenticalTo:self];
    self.superview = nil;
}
- (void)setNeedsLayout {
    self.layoutPending = YES;
    self.layoutRequestCount++;
}
- (BOOL)isDescendantOfView:(UIView*)view {
    for (UIView* ancestor = self; ancestor; ancestor = ancestor.superview) {
        if (ancestor == view) return YES;
    }
    return NO;
}
- (CGRect)convertRect:(CGRect)rect toView:(UIView*)view {
    for (UIView* ancestor = self; ancestor && ancestor != view; ancestor = ancestor.superview) {
        rect.origin.x += ancestor.frame.origin.x;
        rect.origin.y += ancestor.frame.origin.y;
    }
    return rect;
}
@end

@interface UIImageView : UIView @end
@implementation UIImageView @end
@interface UIColor : NSObject
+ (instancetype)clearColor;
@property(nonatomic, readonly) CGColorRef CGColor;
- (instancetype)colorWithAlphaComponent:(CGFloat)alpha;
@end
@implementation UIColor {
    CGColorRef _testColor;
}
- (instancetype)init {
    if ((self = [super init])) _testColor = CGColorCreateGenericRGB(0, 0, 0, 1);
    return self;
}
- (void)dealloc { if (_testColor) CGColorRelease(_testColor); }
- (CGColorRef)CGColor { return _testColor; }
- (instancetype)colorWithAlphaComponent:(CGFloat)alpha {
    UIColor* color = [UIColor new];
    CGColorRelease(color->_testColor);
    color->_testColor = CGColorCreateCopyWithAlpha(self.CGColor, alpha);
    return color;
}
+ (instancetype)clearColor {
    static UIColor* clear;
    if (!clear) clear = [[self new] colorWithAlphaComponent:0];
    return clear;
}
@end
@interface UIFont : NSObject
+ (instancetype)systemFontOfSize:(CGFloat)size weight:(CGFloat)weight;
@end
@implementation UIFont
+ (instancetype)systemFontOfSize:(CGFloat)size weight:(CGFloat)weight { return [self new]; }
@end
static const CGFloat UIFontWeightMedium = 0.23;
enum { NSTextAlignmentLeft, NSTextAlignmentCenter };
enum { NSLineBreakByTruncatingTail = 4 };
@interface UILabel : UIView
@property(nonatomic, copy) NSString* text;
@property(nonatomic, strong) UIFont* font;
@property(nonatomic, strong) UIColor* textColor;
@property(nonatomic) NSInteger textAlignment;
@property(nonatomic) NSInteger lineBreakMode;
@property(nonatomic) BOOL adjustsFontSizeToFitWidth;
@property(nonatomic) CGFloat minimumScaleFactor;
@end
@implementation UILabel @end

static UIColor* CurrentAccentColor(void) {
    static UIColor* color;
    if (!color) color = [UIColor new];
    return color;
}
@interface Palette : NSObject
+ (UIColor*)currentSecondaryTextColor;
@end
@implementation Palette
+ (UIColor*)currentSecondaryTextColor {
    static UIColor* color;
    if (!color) color = [UIColor new];
    return color;
}
@end

void BHTRefreshTabViewAppearance(UIView* tabView);
