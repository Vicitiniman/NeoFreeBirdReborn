#import "BHTGlassOpacityViewController.h"
#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"
#import "Navigation/BHTLiquidGlassDesign.h"
#import "ThemeColor/Palette.h"
#include <math.h>

extern UIColor* CurrentAccentColor(void);
static NSString* BHTGlassLabel(NSString* key) { return [[BHTBundle sharedBundle] localizedStringForKey:key]; }

@interface BHTGlassOpacityViewController ()
@property(nonatomic, strong) UISlider* slider;
@property(nonatomic, strong) UILabel* valueLabel;
@property(nonatomic, strong) UILabel* detailLabel;
@property(nonatomic, strong) UILabel* clearLabel;
@property(nonatomic, strong) UILabel* opaqueLabel;
@property(nonatomic, strong) UIButton* resetButton;
@end

@implementation BHTGlassOpacityViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = BHTGlassLabel(@"GLASS_OPACITY_TITLE");
    self.detailLabel = [UILabel new];
    self.detailLabel.text = BHTGlassLabel(@"GLASS_OPACITY_DETAIL");
    self.detailLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.detailLabel.adjustsFontForContentSizeCategory = YES;
    self.detailLabel.numberOfLines = 0;
    self.valueLabel = [UILabel new];
    self.valueLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleLargeTitle];
    self.valueLabel.adjustsFontForContentSizeCategory = YES;
    self.valueLabel.textAlignment = NSTextAlignmentCenter;
    self.slider = [UISlider new];
    self.slider.minimumValue = 0;
    self.slider.maximumValue = 100;
    self.slider.value = BHTGlassDockOpacity([BHTSettings integerForKey:@"glass_opacity"], NO) * 100;
    self.slider.accessibilityLabel = self.title;
    [self.slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    self.clearLabel = [UILabel new];
    self.clearLabel.text = BHTGlassLabel(@"GLASS_OPACITY_CLEAR");
    self.opaqueLabel = [UILabel new];
    self.opaqueLabel.text = BHTGlassLabel(@"GLASS_OPACITY_OPAQUE");
    for (UILabel* label in @[self.clearLabel, self.opaqueLabel]) {
        label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        label.adjustsFontForContentSizeCategory = YES;
    }
    UIStackView* endpoints = [[UIStackView alloc] initWithArrangedSubviews:@[self.clearLabel, self.opaqueLabel]];
    endpoints.distribution = UIStackViewDistributionEqualSpacing;
    self.resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.resetButton setTitle:BHTGlassLabel(@"GLASS_OPACITY_RESET") forState:UIControlStateNormal];
    [self.resetButton addTarget:self action:@selector(resetOpacity) forControlEvents:UIControlEventTouchUpInside];
    UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:
        @[self.detailLabel, self.valueLabel, self.slider, endpoints, self.resetButton]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 18;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    UIScrollView* scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.contentLayoutGuide.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:28],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-28],
        [stack.centerXAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.centerXAnchor],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:24],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-24],
        [stack.widthAnchor constraintLessThanOrEqualToConstant:440],
        [self.slider.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        [self.resetButton.heightAnchor constraintGreaterThanOrEqualToConstant:44]
    ]];
    NSLayoutConstraint* width = [stack.widthAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.widthAnchor constant:-48];
    width.priority = UILayoutPriorityDefaultHigh;
    width.active = YES;
    [self updateValueLabel];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.view.backgroundColor = [Palette currentBackgroundColor];
    self.detailLabel.textColor = [Palette currentTextColor];
    self.valueLabel.textColor = [Palette currentTextColor];
    self.clearLabel.textColor = [Palette currentSecondaryTextColor];
    self.opaqueLabel.textColor = [Palette currentSecondaryTextColor];
    self.slider.tintColor = CurrentAccentColor() ?: UIColor.systemBlueColor;
    self.resetButton.tintColor = self.slider.tintColor;
}
- (void)updateValueLabel {
    NSNumberFormatter* formatter = [NSNumberFormatter new];
    formatter.numberStyle = NSNumberFormatterPercentStyle;
    formatter.maximumFractionDigits = 0;
    NSString* value = [formatter stringFromNumber:@(round(self.slider.value) / 100)];
    self.valueLabel.text = value;
    self.slider.accessibilityValue = value;
}
- (void)sliderChanged:(UISlider*)slider {
    NSInteger value = (NSInteger)round(slider.value);
    [self updateValueLabel];
    if ([BHTSettings integerForKey:@"glass_opacity"] == value) return;
    [NSUserDefaults.standardUserDefaults setInteger:value forKey:@"glass_opacity"];
    [BHTSettings notePreferencesChanged];
    BHTRefreshLiquidGlassDesign();
}
- (void)resetOpacity {
    self.slider.value = 0;
    [self sliderChanged:self.slider];
}
@end
