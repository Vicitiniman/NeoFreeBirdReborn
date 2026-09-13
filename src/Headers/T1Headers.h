//
//  T1Headers.h
//  BHTwitter
//
//  Created by BandarHelal
//

#import <SafariServices/SafariServices.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "TFNHeaders.h"
#import "TFSHeaders.h"

@interface T1AppDelegate : UIResponder <UIApplicationDelegate>
@property (retain, nonatomic) UIWindow* window;
@end

// The "new posts" pill shown at the top of the timeline
@interface TUIUpdateIndicator : UIViewController
@property (nonatomic, strong) TFNPillControl* pillControl;
@end

@interface TUIFollowControlCustomScreenshot : UIView
@end

@interface _TtC14T1TwitterSwift27TrendsSidebarViewController : UIViewController
@end

@interface T1UserRecommendationsViewController : UIViewController
@end

@interface HomeTimelineContainerViewController : UIViewController
@end

@interface TTMAssetVideoFile : NSObject
@property (nonatomic, copy, readonly) NSString* filePath;
@property (nonatomic, assign, readonly) CGFloat duration;

@end

@interface TTMAssetVoiceRecording : TTMAssetVideoFile
@property (nonatomic, strong, readwrite) NSNumber* totalDurationMillis;
@end

@interface T1MediaAttachmentsViewCell : UICollectionViewCell
@property (nonatomic, strong, readwrite) id attachment;
@property (nonatomic, strong) UIButton* uploadButton;
@end

@interface T1MediaAttachmentsViewCell () <UINavigationControllerDelegate,
                                          UIImagePickerControllerDelegate>
@end

@interface T1StandardStatusAttachmentViewAdapter : NSObject
@property (nonatomic, assign, readonly) NSUInteger attachmentType;
@end

#pragma mark - Tab bar

@interface T1PanelIdentity : NSObject
+ (NSString*)iconImageNameForPanelID:(long long)panelID;
@end

@interface T1PlayerMediaEntitySessionProducible : NSObject
- (instancetype)initWithMediaEntity:(id)mediaEntity
              contentMediaIdentifier:(id)contentMediaIdentifier
                     ownerIdentifier:(id)ownerIdentifier
                      baseScribeItem:(id)baseScribeItem
                   promotedContent:(id)promotedContent;
@end

@interface T1TabView : UIView
@property (readonly, nonatomic) UILabel* titleLabel;
@property (readonly, nonatomic) long long panelID;
@property (copy, nonatomic) NSString* scribePage;
@property (readonly, nonatomic) NSString* title;
@property (readonly, nonatomic) NSString* imageName;
@property (retain, nonatomic) UIColor* iconColor;
@property (readonly, nonatomic, getter=isSelected) BOOL selected;
- (instancetype)initWithFrame:(CGRect)frame
                         title:(NSString*)title
                     imageName:(NSString*)imageName
                       panelID:(long long)panelID;
- (void)_t1_updateTitleLabel;
- (void)_t1_updateImageViewAnimated:(BOOL)animated;
@end

@interface T1TabBarViewController : UIViewController
@property (copy, nonatomic) NSArray* tabViews;
- (BOOL)tfn_supportsTabBarCollapsing;
- (BOOL)tfn_prefersTabBarPinned;
@end

@protocol T1AppNavigationTabEntryContentControllerFactory <NSObject>
- (UIViewController*)createContentController;
- (UIViewController*)rootTabViewController;
@end

// Each entry backs one tab and owns its T1TabView; the app orders both the tab
// buttons and their content view controllers from this single array. X 12.9
// asks every entry for a content-controller factory before it asks that
// factory for either controller, so all three methods are required.
@protocol T1AppNavigationTabEntry <NSObject>
- (T1TabView*)tabView;
- (long long)panelID;
- (id<T1AppNavigationTabEntryContentControllerFactory>)contentControllerFactory;
- (BOOL)isExcludedFromTabBar;
- (BOOL)isTabViewSideBarOnly;
@optional
- (void)setupForTabBarPresentation;
- (void)addContentReadyDependantObservers;
@end

@interface T1TabbedAppNavigationViewController : UIViewController
- (void)setVisibleTabEntries:(NSArray<id<T1AppNavigationTabEntry>>*)entries;
// Recomputes the visible tab set at runtime (rebuilds buttons and content).
- (void)recalculateVisiblePanels;
@end

#pragma mark - Settings

// T1GenericSettingsViewController backs the 12.3 "settings revamp" root and its
// sub-pages; T1SettingsViewController is the legacy fallback root.
@interface T1GenericSettingsViewController : TFNItemsDataViewController
@property (nonatomic, strong) TFNTwitterAccount* account;
@end

@interface T1SettingsViewController : TFNItemsDataViewController
@property (nonatomic, strong) TFNTwitterAccount* account;
@end

#pragma mark - Profile

@interface T1ProfileActionButtonSpec : NSObject
- (instancetype)initWithPosition:(NSUInteger)position
                        priority:(NSUInteger)priority
                 visibilityBlock:(BOOL (^)(double))visibilityBlock
             buttonCreationBlock:(UIView* (^)(void))buttonCreationBlock;
@end

@interface T1ProfileUserViewModel : NSObject
@property (readonly, copy, nonatomic) NSString* location;
@property (readonly, copy, nonatomic) NSString* fullName;
@property (readonly, copy, nonatomic) NSString* username;
@property (readonly, copy, nonatomic) NSString* bio;
@property (readonly, copy, nonatomic) NSString* url;
@end

@interface T1ProfileHeaderViewController : UIViewController
@property (retain, nonatomic) T1ProfileUserViewModel* viewModel;
@end

#pragma mark - Status views

@protocol T1StatusInlineActionButtonDelegate <NSObject>
@end
@protocol TTAStatusInlineActionButtonDelegate <NSObject>
@end

@interface TTAStatusInlineActionButton : UIView
- (void)didTap;
@end

@interface TTAStatusInlineFavoriteButton : TTAStatusInlineActionButton
@end

@interface TTAStatusInlineShareButton : UIView
@property (nonatomic) __weak id<T1StatusInlineActionButtonDelegate> delegate;
@end

@interface TTAStatusInlineReplyButton : UIView
@property (nonatomic) __weak id<T1StatusInlineActionButtonDelegate> delegate;
- (void)didTap;
@end

@interface T1StatusViewInlineActionTapEventHandler : NSObject
- (void)performReplyActionWithAccount:(__unsafe_unretained id)account
                                event:(__unsafe_unretained id)event
                           controller:(__unsafe_unretained id)controller
                        scribeContext:(__unsafe_unretained id)scribeContext
                        scribeElement:(__unsafe_unretained id)scribeElement
                           parameters:(__unsafe_unretained id)parameters
                       originalStatus:(__unsafe_unretained id)originalStatus;
@end

@interface T1PersistentComposeViewController : UIViewController
@property (readonly, nonatomic) id statusViewModel;
- (void)persistentComposeViewDidTap:(id)sender;
@end

@protocol TTACoreStatusViewEventHandler <NSObject>
@end

@interface T1StatusCell : UITableViewCell <TTACoreStatusViewEventHandler>
@end

@interface T1StatusInlineActionsView
    : UIView <T1StatusInlineActionButtonDelegate>
@property (readonly, nonatomic) id viewModel;
@property (nonatomic) id delegate;
@end

@interface TTAStatusInlineActionsView
    : UIView <TTAStatusInlineActionButtonDelegate>
@property (readonly, nonatomic) id viewModel;
@property (nonatomic) id delegate;
@end

@interface T1StandardStatusView : UIView
@property (nonatomic) __weak id<TTACoreStatusViewEventHandler> eventHandler;
@property (readonly, nonatomic) UIView* visibleInlineActionsView;
@end

@interface T1TweetDetailsFocalStatusView : UIView
@property (nonatomic) __weak id<TTACoreStatusViewEventHandler> eventHandler;
@end

@interface T1ConversationFocalStatusView : UIView
@property (nonatomic) __weak id<TTACoreStatusViewEventHandler> eventHandler;
- (void)layoutSubviews;
@property (nonatomic, readonly) id viewModel;
- (void)enumerateSubviewsRecursively:(void (^)(UIView*))block;
@end

@interface T1TweetComposeViewController : UIViewController
@end

#pragma mark - Media views

@class DownloadInlineButton;

// DM media message container (DMConversation.MessageAttachmentView)
@interface _TtC16ChatConversation21MessageAttachmentView : UIView
@property (nonatomic, strong) UIContextMenuInteraction* downloadMenuInteraction;
@property (nonatomic, strong) DownloadInlineButton* downloadHandler;
@end

@interface _TtC16ChatConversation21MessageAttachmentView () <
    UIContextMenuInteractionDelegate>
@end

// Shared componentized media views. MultiMediaCarouselView is a separate class,
// not a MultiMediaView subclass, but both expose -inlineMediaInfos.
@interface _TtC21TweetMediaAttachments14MultiMediaView : UIView
@property (nonatomic, readonly) NSArray* inlineMediaInfos;
@property (nonatomic, strong) UILongPressGestureRecognizer* bhtDownloadLongPress;
@property (nonatomic, strong) DownloadInlineButton* bhtDownloadHandler;
@end

@interface _TtC21TweetMediaAttachments22MultiMediaCarouselView : UIView
@property (nonatomic, readonly) NSArray* inlineMediaInfos;
@end

// X 12.9 can still use the legacy inline player for timeline VOD, depending on
// the post and feature switches.
@interface T1InlineMediaView : UIView
@end

// X 12.9 routes its native Blue-only video action through this model. NeoFreeBird
// associates the originating entity with it and substitutes its own quality
// picker when video downloads are enabled.
@interface T1VideoDownloadViewModel : NSObject

+ (id)makeVideDownloaderWithAccount:(id)account
                 fromViewController:(UIViewController*)viewController
                        mediaEntity:(TFSTwitterEntityMedia*)mediaEntity
                    statusViewModel:(id)statusViewModel;
- (void)tappedDownload;
@end

#pragma mark - Host & web views

@interface T1HostViewController : UIViewController
+ (instancetype)sharedHostViewController;
- (id)currentAccount;
@end

@interface T1BaseWebViewController : UIViewController
- (instancetype)initWithURL:(NSURL*)url;
- (instancetype)initWithAccount:(id)account;
- (void)setRootURL:(NSURL*)url;
- (void)setCurrentURL:(NSURL*)url;
@property (nonatomic, readonly) NSURL* currentURL;
- (WKWebView*)webView;
@end

@interface T1WebViewController : T1BaseWebViewController
- (instancetype)initWithRootURL:(NSURL*)rootURL
                        account:(id)account
             shouldAuthenticate:(BOOL)shouldAuthenticate
      shouldPresentAsNativePage:(BOOL)shouldPresentAsNativePage
                   sourceStatus:(id)sourceStatus
                scribeComponent:(id)scribeComponent
               scribeParameters:(id)scribeParameters;
@property (nonatomic, strong) id account;
- (BOOL)doesURLResultTypeOpenInWebview:(long long)resultType;
@end

@interface T1SafariViewController : SFSafariViewController
@property (nonatomic, readonly) NSURL* rootURL;
@end

#pragma mark - Status & timeline text

@interface T1StatusBodyTextView : UIView
@property (readonly, nonatomic) id viewModel;
@end

@interface _TtC10TwitterURT25URTTimelineTrendViewModel : NSObject
@property (nonatomic, readonly) NSDictionary* scribeItem;
@end

@interface T1ConversationFooterTextView : TFNAttributedTextView
@property (nonatomic, readonly) id viewModel;
- (void)updateFooterTextView;
@end

// Hooked for unrounded follower/following counts
@interface T1ProfileFriendsFollowingViewModel : NSObject
- (id)_t1_followCountTextWithLabel:(id)arg1
                     singularLabel:(id)arg2
                             count:(id)arg3
                       highlighted:(_Bool)arg4;
@end
