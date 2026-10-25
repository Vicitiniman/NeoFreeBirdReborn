#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// The single source of truth for NeoFreeBird's classic Twitter bird. Keeping
// the bundled image lookup here ensures Home and iPad navigation use the same
// template, while launch can use a larger texture of that exact artwork.
FOUNDATION_EXPORT UIImage* _Nullable BHTTwitterBirdTemplateImage(void);
FOUNDATION_EXPORT UIImage* _Nullable BHTTwitterBirdLaunchTemplateImage(void);

FOUNDATION_EXPORT void BHTApplyTwitterBirdToImageView(
    UIImageView* imageView, UIColor* tintColor);
FOUNDATION_EXPORT void BHTApplyTwitterBirdLaunchToImageView(
    UIImageView* imageView, UIColor* tintColor);

NS_ASSUME_NONNULL_END
