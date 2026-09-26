//
//  TFNHeaders.h
//  BHTwitter
//
//  Created by BandarHelal
//

#import <UIKit/UIKit.h>
#import "TFSHeaders.h"

@interface TFNTwitterAccount : NSObject
@property (nonatomic, strong) NSString* displayFullName;
@property (nonatomic, strong) NSString* username;
@property (nonatomic, strong) NSString* displayUsername;
@property (nonatomic, strong) NSString* fullName;
@property (nonatomic, strong) id scribe;
@end

@interface TFNTableView : UITableView
@end

@interface TFNPillControl : UIControl
@property (nonatomic, copy) NSString* text;
@end

@interface TFNDataViewController : UIViewController
@property (readonly, nonatomic) TFNTableView* tableView;
@property (readonly, nonatomic) NSString* adDisplayLocation;
@end

@interface TFNItemsDataViewController : TFNDataViewController
@property (copy, nonatomic) NSArray* sections;
@end

@interface TFNNavigationController : UINavigationController
@end

@interface TFNActionItem : NSObject
@property (copy, nonatomic) NSString* title;
@property (copy, nonatomic) NSString* imageName;
@property (nonatomic, getter=isDisabled) BOOL disabled;
+ (instancetype)cancelActionItemWithAction:(void (^)(void))arg1;
+ (instancetype)cancelActionItemWithTitle:(NSString*)arg1;
+ (instancetype)actionItemWithTitle:(NSString*)arg1 action:(void (^)(void))arg2;
+ (instancetype)actionItemWithTitle:(NSString*)arg1
                          imageName:(NSString*)arg2
                             action:(void (^)(void))arg3;
+ (instancetype)actionItemWithTitle:(NSString*)arg1
                           subtitle:(NSString*)arg2
                          imageName:(NSString*)arg3
                             action:(void (^)(void))arg4;
+ (instancetype)nestedMenuWithTitle:(NSString*)arg1 items:(NSArray*)arg2;
@end

@interface TFNAttributedTextModel : NSObject
@property (copy, nonatomic) NSAttributedString* attributedString;
- (instancetype)initWithAttributedString:(NSMutableAttributedString*)arg;
@end

@interface TFNAttributedTextView : UIView
- (void)setTextModel:(id)model;
@end

@interface TFNActiveTextItem : NSObject
- (instancetype)initWithTextModel:(id)arg activeRanges:(id)arg1;
@end

@interface TFNMenuSheetViewController : TFNItemsDataViewController
@property (nonatomic, assign, readwrite) BOOL shouldPresentAsMenu;
@property (retain, nonatomic) UIView* sourceView;
- (instancetype)initWithTitle:(NSString*)sheetTitle
                  actionItems:(NSArray*)actionItems;
- (instancetype)initWithMessage:(NSString*)sheetMessage
                    actionItems:(NSArray*)actionItems;
- (instancetype)initWithActionItems:(NSArray*)actionItems;
- (instancetype)initWithTitle:(NSString*)sheetTitle
                   titleStyle:(long long)sheetTitleStyle
                      message:(NSString*)sheetMessage
              messageIconName:(id)sheetMessageIconName
           actionItemSections:(NSArray*)actionItemSections;
- (void)tfnPresentedCustomPresentFromViewController:(id)arg1
                                           animated:(BOOL)arg2
                                         completion:(void (^)(void))arg3;
@end

@interface TFNHUD : NSObject
- (instancetype)initWithText:(NSString*)text;
- (void)setText:(NSString*)text;
- (void)show;
- (void)hide;
@end

@interface TFNSettingsNavigationItem : NSObject
- (instancetype)initWithTitle:(NSString*)arg1
                       detail:(NSString*)arg2
                     iconName:(NSString*)arg3
            controllerFactory:(UIViewController* (^)(void))arg4;
- (instancetype)initWithTitle:(NSString*)arg1
                       detail:(NSString*)arg2
            controllerFactory:(UIViewController* (^)(void))arg4;
@end

@interface TFNButton : UIButton
+ (id)buttonWithImage:(id)arg1 style:(long long)arg2 sizeClass:(long long)arg3;
+ (id)buttonWithTitle:(id)arg1
           imageNamed:(id)arg2
                style:(long long)arg3
            sizeClass:(long long)arg4;
@end

@interface TFNTwitterStatus : NSObject
@property (readonly, nonatomic) NSDictionary* scribeParameters;
@property (readonly, nonatomic) _Bool isPromoted;
@property (readonly, nonatomic) TFSTwitterEntitySet* entities;
@property (nonatomic, copy) NSString* fromUserName;
@property (nonatomic, assign) NSInteger statusID;
- (id)composerSource;
- (BOOL)isPoliticalAd;
- (BOOL)isIssueAd;
- (BOOL)isRTBCreative;
- (BOOL)isPrerollContent;
- (BOOL)isAdsVideoCard;
- (BOOL)allowDynamicAd;
- (id)sspMetadata;
- (id)promotedContent;
- (id)init;
@end

@interface TFNTwitterCanonicalUser : NSObject
- (BOOL)isProfileBioTranslatable;
- (BOOL)isProfileTranslationEnabled;
@end

@interface TFNTwitter : NSObject
+ (instancetype)sharedTwitter;
@property (readonly, nonatomic) NSArray* accounts;
@end

@interface TFNTwitterComposition : NSObject
@property (nonatomic, strong) NSDate* undoableAddedDate;
@property (nonatomic, assign) double undoTimeInterval;
@end

@interface UIViewController (TFNPresentation)
- (void)tfn_dismissAnimated:(id)sender;
- (void)tfn_presentFromViewController:(UIViewController*)viewController
                             animated:(BOOL)animated;
@end

@interface TFNPreviewConfiguration : NSObject
+ (instancetype)configurationWithPreviewViewControllerBlock:
                    (UIViewController* (^)(void))previewViewControllerBlock
                                               actionItems:(NSArray*)actionItems
                                                sourceView:(UIView*)sourceView
                                                sourceRect:(CGRect)sourceRect;
@end

@interface TFNTitleView : UIView
+ (instancetype)titleViewWithTitle:(NSString*)title
                          subtitle:(NSString*)subTitle;
@end

@interface UIImage (TFNAdditions)
+ (id)tfn_vectorImageNamed:(id)arg1
                  fitsSize:(struct CGSize)arg2
                 fillColor:(id)arg3;
+ (BOOL)tfn_vectorImageExistsNamed:(id)arg1
                          fitsSize:(struct CGSize)arg2
                              size:(out struct CGSize*)arg3;
+ (id)tfn_vectorImageNamed:(id)arg1
    highContrastVariantNamed:(id)arg2
                    fitsSize:(struct CGSize)arg3
                   fillColor:(id)arg4;
+ (id)tfn_vectorImageNamed:(id)arg1 height:(double)arg2 fillColor:(id)arg3;
+ (void)tfn_vectorImageSetOverrideContainersDirectoryURL:(NSURL*)arg1;
+ (NSURL*)tfn_vectorImageOverrideContainersDirectoryURL;
+ (void)tfn_vectorImageSetSearchDirectoryURLs:(NSArray*)arg1;
+ (NSArray*)tfn_vectorImageSearchDirectoryURLs;
+ (void)tfn_vectorImageSetOverrideContainerName:(NSString*)arg1;
+ (NSString*)tfn_vectorImageOverrideContainerName;
@end
