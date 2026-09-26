#import "Branding/BHTBranding.h"

#import "Core/BHTBundle.h"
#import <math.h>

static UIImage* BHTTwitterBirdImageNamed(NSString* name) {
    NSBundle* bundle = [BHTBundle sharedBundle].mainBundle;
    return [[UIImage imageNamed:name
                       inBundle:bundle
  compatibleWithTraitCollection:nil]
        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

UIImage* BHTTwitterBirdTemplateImage(void) {
    static UIImage* image = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        image = BHTTwitterBirdImageNamed(@"twitter_bird");
    });
    return image;
}

UIImage* BHTTwitterBirdLaunchTemplateImage(void) {
    static UIImage* image = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        image = BHTTwitterBirdImageNamed(@"twitter_bird_launch");
    });
    return image;
}

static void BHTApplyTwitterBirdImageToImageView(UIImageView* imageView,
                                                UIImage* bird,
                                                UIColor* tintColor) {
    if (!imageView || !bird) return;
    imageView.image = bird;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.tintColor = tintColor;
    imageView.accessibilityLabel = @"Twitter";
}

void BHTApplyTwitterBirdToImageView(UIImageView* imageView,
                                    UIColor* tintColor) {
    BHTApplyTwitterBirdImageToImageView(
        imageView, BHTTwitterBirdTemplateImage(), tintColor);
}

void BHTApplyTwitterBirdLaunchToImageView(UIImageView* imageView,
                                          UIColor* tintColor) {
    if (!imageView) return;
    UIImage* bird = BHTTwitterBirdLaunchTemplateImage();
    CGSize existingPointSize = imageView.image.size;
    CGImageRef birdPixels = bird.CGImage;
    CGFloat targetPointSize =
        MAX(existingPointSize.width, existingPointSize.height);
    if (birdPixels && isfinite(targetPointSize) && targetPointSize > 0.0) {
        CGFloat pixelSize =
            MAX((CGFloat)CGImageGetWidth(birdPixels),
                (CGFloat)CGImageGetHeight(birdPixels));
        CGFloat scale = pixelSize / targetPointSize;
        if (isfinite(scale) && scale > 0.0) {
            // Keep X's original intrinsic logo size while retaining every
            // pixel in the larger launch-only texture.
            bird = [[UIImage imageWithCGImage:birdPixels
                                        scale:scale
                                  orientation:bird.imageOrientation]
                imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        }
    }
    BHTApplyTwitterBirdImageToImageView(
        imageView, bird, tintColor);
}
