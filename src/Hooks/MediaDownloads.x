//
//  MediaDownloads.x
//  NeoFreeBird
//

#import "HookHelpers.h"
#import "Compatibility/BHTCompatibilityReporter.h"
#import "MediaActions/BHTMediaActionUtility.h"

static char kBHTVideoDownloadMediaKey;
static char kBHTVideoDownloadHandlerKey;
static char kBHTInlineDownloadLongPressKey;
static char kBHTInlineDownloadHandlerKey;
static char kBHTCarouselDownloadLongPressKey;
static char kBHTCarouselDownloadHandlerKey;
static char kBHTMediaActionDownloaderKey;
static char kBHTMediaActionKindKey;
static char kBHTMediaActionKindTokenKey;
static char kBHTMediaActionInjectedKey;
static NSString* const kBHTPendingMediaActionKindThreadKey =
    @"BHTPendingMediaActionKind";

static id BHTObjectForSelector(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static BOOL BHTNativeMediaActionBuilderAvailable(void) {
    SEL selector = NSSelectorFromString(
        @"t1_mediaActivityViewActionItemsForStatus:account:image:mediaInfo:shortTitles:sourceView:");
    return class_getInstanceMethod(UIViewController.class, selector) != NULL;
}

// Do not key video detection off mediaType alone. X 12.9 has multiple media
// model bridges and the numeric enum value is not stable across all of them;
// videoInfo.variants is the reliable indication that the entity is downloadable.
static BOOL BHTIsDownloadableVideoEntity(id media) {
    id videoInfo = BHTObjectForSelector(media, @selector(videoInfo));
    NSArray* variants = BHTObjectForSelector(videoInfo, @selector(variants));
    return variants.count > 0;
}


static void BHTPrioritizeDownloadLongPress(
    UIView* root,
    UILongPressGestureRecognizer* downloadRecognizer) {
    if (!root || !downloadRecognizer) return;
    EnumerateSubviewsRecursively(root, ^(UIView* view) {
        for (UIGestureRecognizer* recognizer in view.gestureRecognizers) {
            if (recognizer != downloadRecognizer &&
                [recognizer
                    isKindOfClass:UILongPressGestureRecognizer.class]) {
                [recognizer
                    requireGestureRecognizerToFail:downloadRecognizer];
            }
        }
    });
}

static NSArray<TFSTwitterEntityMedia*>* BHTVideoEntitiesFromMediaInfos(
    NSArray* mediaInfos) {
    NSMutableArray<TFSTwitterEntityMedia*>* entities = [NSMutableArray array];
    for (id info in mediaInfos) {
        TFSTwitterEntityMedia* media =
            [info respondsToSelector:@selector(mediaEntity)]
                ? [info mediaEntity]
                : info;
        if (BHTIsDownloadableVideoEntity(media)) {
            [entities addObject:media];
        }
    }
    return [entities copy];
}

static TFSTwitterEntityMedia* BHTVideoEntityAtPressLocation(
    UIView* mediaView,
    UILongPressGestureRecognizer* recognizer) {
    SEL indexSelector = @selector(mediaIndexAtPoint:);
    SEL infoSelector = @selector(mediaInfoAtIndex:);
    if (![mediaView respondsToSelector:indexSelector] ||
        ![mediaView respondsToSelector:infoSelector]) {
        return nil;
    }

    CGPoint point = [recognizer locationInView:mediaView];
    NSInteger index =
        ((NSInteger (*)(id, SEL, CGPoint))objc_msgSend)(
            mediaView, indexSelector, point);
    if (index < 0) return nil;

    id mediaInfo =
        ((id (*)(id, SEL, NSInteger))objc_msgSend)(
            mediaView, infoSelector, index);
    id media = BHTObjectForSelector(mediaInfo, @selector(mediaEntity));
    return BHTIsDownloadableVideoEntity(media) ? media : nil;
}

static TFSTwitterEntityMedia* BHTMediaEntityFromInlineView(id inlineView) {
    id viewModel = BHTObjectForSelector(inlineView, @selector(viewModel));

    // T1InlineMediaViewModel exposes the playing entity through
    // playerSessionProducer.sessionProducible.mediaEntity.
    id producer =
        BHTObjectForSelector(viewModel, @selector(playerSessionProducer));
    id producible =
        BHTObjectForSelector(producer, @selector(sessionProducible));
    id media = BHTObjectForSelector(producible, @selector(mediaEntity));

    // Nearby X builds expose one of these shorter paths instead.
    if (!media) {
        media = BHTObjectForSelector(viewModel, @selector(mediaEntity));
    }
    if (!media) {
        media = BHTObjectForSelector(inlineView, @selector(mediaEntity));
    }
    return BHTIsDownloadableVideoEntity(media) ? media : nil;
}

static BOOL BHTLooksLikeMediaEntity(id object) {
    return object &&
           [object respondsToSelector:@selector(mediaType)] &&
           ([object respondsToSelector:@selector(mediaURL)] ||
            [object respondsToSelector:@selector(videoInfo)]);
}

static NSArray* BHTMediaEntitiesFromStatus(id status) {
    NSMutableArray* results = [NSMutableArray array];
    NSMutableSet* seen = [NSMutableSet set];
    void (^appendMedia)(NSArray*) = ^(NSArray* mediaEntities) {
        for (id media in mediaEntities) {
            if (!BHTLooksLikeMediaEntity(media)) continue;
            NSValue* identity =
                [NSValue valueWithNonretainedObject:media];
            if ([seen containsObject:identity]) continue;
            [seen addObject:identity];
            [results addObject:media];
        }
    };

    if (BHTLooksLikeMediaEntity(status)) {
        appendMedia(@[status]);
    }
    id nestedStatus = BHTObjectForSelector(status, @selector(status));
    NSArray* sources =
        nestedStatus && nestedStatus != status ? @[status, nestedStatus]
                                               : @[status ?: NSNull.null];
    for (id source in sources) {
        if (source == NSNull.null) continue;
        id wrappedMedia =
            BHTObjectForSelector(source, @selector(mediaEntity));
        if (wrappedMedia) {
            appendMedia(@[wrappedMedia]);
        }
        appendMedia(BHTObjectForSelector(
            source, @selector(representedMediaEntities)));
        for (NSString* selectorName in
             @[@"extendedEntities", @"entities"]) {
            id entitySet = BHTObjectForSelector(
                source, NSSelectorFromString(selectorName));
            appendMedia(BHTObjectForSelector(entitySet, @selector(media)));
        }
    }
    return [results copy];
}

static NSArray* BHTMergedMediaEntities(id firstSource, id secondSource) {
    NSMutableArray* merged = [NSMutableArray array];
    NSMutableSet* seen = [NSMutableSet set];
    for (id source in @[firstSource ?: NSNull.null,
                        secondSource ?: NSNull.null]) {
        if (source == NSNull.null) continue;

        NSArray* entities = BHTMediaEntitiesFromStatus(source);
        for (id media in entities) {
            NSValue* identity =
                [NSValue valueWithNonretainedObject:media];
            if ([seen containsObject:identity]) continue;
            [seen addObject:identity];
            [merged addObject:media];
        }
    }
    return [merged copy];
}

static NSArray* BHTActionTargetMediaEntities(id shareableEntity, id status) {
    // Player/photo menus normally pass the tapped media (or a wrapper
    // containing only that media) as shareableEntity. Keep that primary target
    // isolated so a video elsewhere in a mixed-media status cannot turn a
    // tapped photo's menu into the Video menu. Tweet-level overflow menus fall
    // back to the full status collection and retain the existing multi-item
    // picker behavior.
    if (BHTLooksLikeMediaEntity(shareableEntity)) {
        return @[shareableEntity];
    }
    NSArray* primary = BHTMediaEntitiesFromStatus(shareableEntity);
    if (primary.count == 1) {
        return primary;
    }
    return BHTMergedMediaEntities(shareableEntity, status);
}

static NSArray* BHTVideoEntitiesFromStatus(id status) {
    NSMutableArray* videos = [NSMutableArray array];
    for (id media in BHTMediaEntitiesFromStatus(status)) {
        if (BHTIsDownloadableVideoEntity(media)) {
            [videos addObject:media];
        }
    }
    return [videos copy];
}

static NSArray* BHTVideoEntitiesFromMediaEntities(NSArray* mediaEntities) {
    NSMutableArray* videos = [NSMutableArray array];
    for (id media in mediaEntities) {
        if (BHTIsDownloadableVideoEntity(media)) {
            [videos addObject:media];
        }
    }
    return [videos copy];
}

static BOOL BHTMediaEntityLooksLikeGIF(id media) {
    if ([media respondsToSelector:@selector(mediaType)] &&
        ((TFSTwitterEntityMedia*)media).mediaType == 2) {
        return YES;
    }
    id videoInfo = BHTObjectForSelector(media, @selector(videoInfo));
    for (id variant in
         BHTObjectForSelector(videoInfo, @selector(variants))) {
        NSString* rawURL = BHTObjectForSelector(variant, @selector(url));
        if ([rawURL containsString:@"/tweet_video/"]) {
            return YES;
        }
    }
    NSString* primaryURL =
        BHTObjectForSelector(videoInfo, @selector(primaryUrl));
    return [primaryURL containsString:@"/tweet_video/"];
}


// MARK: - Tweet video/GIF long press

// X 12.9 gives its own inline download action priority and routes non-Blue
// accounts to an upsell. Install a media-specific long press that wins that
// recognizer race and opens NeoFreeBird's quality/GIF picker directly.
%hook _TtC21TweetMediaAttachments14MultiMediaView
%property (nonatomic, strong) UILongPressGestureRecognizer* bhtDownloadLongPress;
%property (nonatomic, strong) DownloadInlineButton* bhtDownloadHandler;
- (void)layoutSubviews {
    %orig;

    NSArray* entities =
        BHTVideoEntitiesFromMediaInfos(self.inlineMediaInfos);
    BOOL enabled = [BHTSettings boolForKey:@"download_videos"] &&
                   entities.count > 0 &&
                   !BHTNativeMediaActionBuilderAvailable();
    if (enabled && !self.bhtDownloadLongPress) {
        UILongPressGestureRecognizer* recognizer =
            [[UILongPressGestureRecognizer alloc]
                initWithTarget:self
                        action:@selector(bhtHandleVideoDownloadLongPress:)];
        recognizer.minimumPressDuration = 0.4;
        recognizer.cancelsTouchesInView = NO;
        self.bhtDownloadLongPress = recognizer;
        [self addGestureRecognizer:recognizer];
    }
    self.bhtDownloadLongPress.enabled = enabled;

    if (enabled)
        BHTPrioritizeDownloadLongPress(
            self, self.bhtDownloadLongPress);
}
%new
- (void)bhtHandleVideoDownloadLongPress:
    (UILongPressGestureRecognizer*)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan ||
        ![BHTSettings boolForKey:@"download_videos"]) {
        return;
    }
    TFSTwitterEntityMedia* media =
        BHTVideoEntityAtPressLocation(self, recognizer);
    if (!media) return;
    if (!self.bhtDownloadHandler) {
        self.bhtDownloadHandler = [%c(DownloadInlineButton) new];
    }
    [self.bhtDownloadHandler
        presentDownloadOptionsForMediaEntities:@[media]];
}
%end

// Mixed-media and multi-item posts use the separate carousel class, which has
// the same media-info API but is not a MultiMediaView subclass.
%hook _TtC21TweetMediaAttachments22MultiMediaCarouselView
- (void)layoutSubviews {
    %orig;

    NSArray* entities =
        BHTVideoEntitiesFromMediaInfos(self.inlineMediaInfos);
    BOOL enabled = [BHTSettings boolForKey:@"download_videos"] &&
                   entities.count > 0 &&
                   !BHTNativeMediaActionBuilderAvailable();
    UILongPressGestureRecognizer* recognizer =
        objc_getAssociatedObject(self, &kBHTCarouselDownloadLongPressKey);
    if (enabled && !recognizer) {
        recognizer = [[UILongPressGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(bhtHandleCarouselDownloadLongPress:)];
        recognizer.minimumPressDuration = 0.4;
        recognizer.cancelsTouchesInView = NO;
        objc_setAssociatedObject(
            self, &kBHTCarouselDownloadLongPressKey, recognizer,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self addGestureRecognizer:recognizer];
    }
    recognizer.enabled = enabled;

    if (enabled)
        BHTPrioritizeDownloadLongPress(self, recognizer);
}
%new
- (void)bhtHandleCarouselDownloadLongPress:
    (UILongPressGestureRecognizer*)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan ||
        ![BHTSettings boolForKey:@"download_videos"]) {
        return;
    }

    TFSTwitterEntityMedia* media =
        BHTVideoEntityAtPressLocation(self, recognizer);
    if (!media) return;

    DownloadInlineButton* handler =
        objc_getAssociatedObject(self, &kBHTCarouselDownloadHandlerKey);
    if (!handler) {
        handler = [%c(DownloadInlineButton) new];
        objc_setAssociatedObject(
            self, &kBHTCarouselDownloadHandlerKey, handler,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [handler presentDownloadOptionsForMediaEntities:@[media]];
}
%end

// Timeline videos can still use the legacy T1InlineMediaView while GIFs use
// TweetMediaAttachments.MultiMediaView. Cover that path as well so both media
// types expose the same NeoFreeBird long-press menu.
%hook T1InlineMediaView
- (void)layoutSubviews {
    %orig;

    TFSTwitterEntityMedia* media = BHTMediaEntityFromInlineView(self);
    BOOL enabled =
        [BHTSettings boolForKey:@"download_videos"] && media != nil &&
        !BHTNativeMediaActionBuilderAvailable();
    UILongPressGestureRecognizer* recognizer =
        objc_getAssociatedObject(self, &kBHTInlineDownloadLongPressKey);
    if (enabled && !recognizer) {
        recognizer = [[UILongPressGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(bhtHandleInlineVideoDownloadLongPress:)];
        recognizer.minimumPressDuration = 0.4;
        recognizer.cancelsTouchesInView = NO;
        objc_setAssociatedObject(
            self, &kBHTInlineDownloadLongPressKey, recognizer,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self addGestureRecognizer:recognizer];
    }
    recognizer.enabled = enabled;

    if (enabled)
        BHTPrioritizeDownloadLongPress(self, recognizer);
}
%new
- (void)bhtHandleInlineVideoDownloadLongPress:
    (UILongPressGestureRecognizer*)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan ||
        ![BHTSettings boolForKey:@"download_videos"]) {
        return;
    }

    TFSTwitterEntityMedia* media = BHTMediaEntityFromInlineView(self);
    if (!media) return;

    DownloadInlineButton* handler =
        objc_getAssociatedObject(self, &kBHTInlineDownloadHandlerKey);
    if (!handler) {
        handler = [%c(DownloadInlineButton) new];
        objc_setAssociatedObject(
            self, &kBHTInlineDownloadHandlerKey, handler,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [handler presentDownloadOptionsForMediaEntities:@[media]];
}
%end

// X's video-settings row can still be reached from the player menu. Make it
// eligible for video/GIF entities, retain the source entity on the native model,
// then replace tappedDownload with the same NeoFreeBird picker.
%hook TFSTwitterEntityMedia
- (BOOL)allowDownload {
    if ([BHTSettings boolForKey:@"download_videos"] &&
        BHTIsDownloadableVideoEntity(self)) {
        return YES;
    }
    return %orig;
}
%end

%hook T1VideoDownloadViewModel

+ (id)makeVideDownloaderWithAccount:(id)account
                 fromViewController:(UIViewController*)viewController
                        mediaEntity:
                            (TFSTwitterEntityMedia*)mediaEntity
                    statusViewModel:(id)statusViewModel {
    id downloader = %orig;
    if (downloader &&
        [BHTSettings boolForKey:@"download_videos"] &&
        BHTIsDownloadableVideoEntity(mediaEntity)) {
        objc_setAssociatedObject(
            downloader, &kBHTVideoDownloadMediaKey, mediaEntity,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return downloader;
}

- (void)tappedDownload {
    TFSTwitterEntityMedia* media =
        objc_getAssociatedObject(self, &kBHTVideoDownloadMediaKey);
    if ([BHTSettings boolForKey:@"download_videos"] && media) {
        DownloadInlineButton* handler =
            objc_getAssociatedObject(self, &kBHTVideoDownloadHandlerKey);
        if (!handler) {
            handler = [%c(DownloadInlineButton) new];
            objc_setAssociatedObject(
                self, &kBHTVideoDownloadHandlerKey, handler,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [handler presentDownloadOptionsForMediaEntities:@[media]];
        });
        return;
    }
    %orig;
}
%end

// MARK: - DM video download

// The DM UI is Swift now: media messages live in DMConversation.MessageAttachmentView,
// which hosts a shared TweetMediaAttachments media view exposing its models through
// -inlineMediaInfos. Collect the entities from whichever descendant carries them.
static NSArray* DMVideoEntities(UIView* attachmentView) {
    NSMutableArray* entities = [NSMutableArray new];

    EnumerateSubviewsRecursively(attachmentView, ^(UIView* view) {
        if (![view respondsToSelector:@selector(inlineMediaInfos)]) {
            return;
        }

        for (TFSTwitterMediaInfo* info in
             [(_TtC21TweetMediaAttachments14MultiMediaView*)view inlineMediaInfos]) {
            TFSTwitterEntityMedia* media = info.mediaEntity;
            if (media.videoInfo.variants.count > 0) {
                [entities addObject:media];
            }
        }
    });

    return [entities copy];
}

%hook _TtC16ChatConversation21MessageAttachmentView
%property (nonatomic, strong) UIContextMenuInteraction* downloadMenuInteraction;
%property (nonatomic, strong) DownloadInlineButton* downloadHandler;
- (void)layoutSubviews {
    %orig;

    if ([BHTSettings boolForKey:@"download_videos"] &&
        [BHTSettings boolForKey:@"dm_media_downloads"] &&
        self.downloadMenuInteraction == nil) {
        self.downloadMenuInteraction = [[UIContextMenuInteraction alloc] initWithDelegate:self];
        [self addInteraction:self.downloadMenuInteraction];
    }
}
%new
- (UIContextMenuConfiguration*)contextMenuInteraction:(UIContextMenuInteraction*)interaction
                       configurationForMenuAtLocation:(CGPoint)location {
    if (![BHTSettings boolForKey:@"download_videos"] ||
        ![BHTSettings boolForKey:@"dm_media_downloads"]) {
        return nil;
    }
    NSArray* videoEntities = DMVideoEntities(self);
    if (videoEntities.count == 0) {
        return nil;
    }

    return [UIContextMenuConfiguration
        configurationWithIdentifier:nil
                    previewProvider:nil
                     actionProvider:^UIMenu* _Nullable(
                         NSArray<UIMenuElement*>* _Nonnull suggestedActions) {
                         UIAction* saveAction = [UIAction
                             actionWithTitle:
                                 [[BHTBundle sharedBundle]
                                     localizedTwitterStringForKey:@"DOWNLOAD_ACTIVITY_VIEW_LABEL"]
                                       image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                                  identifier:nil
                                     handler:^(__kindof UIAction* _Nonnull action) {
                                         if (self.downloadHandler == nil) {
                                             self.downloadHandler = [%c(DownloadInlineButton) new];
                                         }
                                         [self.downloadHandler
                                             presentDownloadOptionsForMediaEntities:videoEntities];
                                     }];
                         return [UIMenu menuWithTitle:@"" children:@[saveAction]];
                     }];
}
%end

// MARK: - Upload custom voice

// Overwrites the recording at the attachment's existing file path, so the
// composer picks up the replacement without any model changes.
%hook T1MediaAttachmentsViewCell
%property (nonatomic, strong) UIButton* uploadButton;
- (void)updateCellElements {
    %orig;

    BOOL isVoiceRecording = [self.attachment isKindOfClass:%c(TTMAssetVoiceRecording)];

    BOOL customUploadEnabled = [BHTSettings boolForKey:@"custom_voice_upload"];

    if (customUploadEnabled && isVoiceRecording && self.uploadButton == nil) {
        TFNButton* removeButton = [self valueForKey:@"_removeButton"];
        if (removeButton == nil) {
            return;
        }

        self.uploadButton = [UIButton buttonWithType:UIButtonTypeCustom];
        UIImageSymbolConfiguration* smallConfig =
            [UIImageSymbolConfiguration configurationWithScale:UIImageSymbolScaleSmall];
        UIImage* arrowUpImage = [UIImage systemImageNamed:@"arrow.up" withConfiguration:smallConfig];
        [self.uploadButton setImage:arrowUpImage forState:UIControlStateNormal];
        [self.uploadButton addTarget:self
                              action:@selector(handleUploadButton:)
                    forControlEvents:UIControlEventTouchUpInside];
        [self.uploadButton setTintColor:UIColor.labelColor];
        [self.uploadButton setBackgroundColor:[UIColor blackColor]];
        [self.uploadButton.layer setCornerRadius:29 / 2];
        [self.uploadButton setTranslatesAutoresizingMaskIntoConstraints:false];

        [self addSubview:self.uploadButton];
        [NSLayoutConstraint activateConstraints:@[
            [self.uploadButton.trailingAnchor constraintEqualToAnchor:removeButton.leadingAnchor
                                                             constant:-10],
            [self.uploadButton.topAnchor constraintEqualToAnchor:removeButton.topAnchor],
            [self.uploadButton.widthAnchor constraintEqualToConstant:29],
            [self.uploadButton.heightAnchor constraintEqualToConstant:29],
        ]];
    }

    self.uploadButton.hidden = !customUploadEnabled || !isVoiceRecording;
}
%new
- (void)handleUploadButton:(UIButton*)sender {
    if (![BHTSettings boolForKey:@"custom_voice_upload"]) {
        return;
    }
    UIImagePickerController* videoPicker = [[UIImagePickerController alloc] init];
    videoPicker.mediaTypes = @[(NSString*)kUTTypeMovie];
    videoPicker.delegate = self;

    [topMostController() presentViewController:videoPicker animated:YES completion:nil];
}
%new
- (void)imagePickerController:(UIImagePickerController*)picker
    didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id>*)info {
    NSURL* videoURL = info[UIImagePickerControllerMediaURL];
    TTMAssetVoiceRecording* attachment = self.attachment;
    NSURL* recorder_url = [NSURL fileURLWithPath:attachment.filePath];

    if (recorder_url != nil) {
        NSFileManager* fileManager = [NSFileManager defaultManager];

        NSError* error = nil;
        if ([fileManager fileExistsAtPath:[recorder_url path]]) {
            [fileManager removeItemAtURL:recorder_url error:&error];
            if (error) {
                NSLog(@"[BHTwitter] Error removing existing file: %@", error);
            }
        }

        [fileManager copyItemAtURL:videoURL toURL:recorder_url error:&error];
        if (error) {
            NSLog(@"[BHTwitter] Error copying file: %@", error);
        }
    }

    [picker dismissViewControllerAnimated:true completion:nil];
}
%new
- (void)imagePickerControllerDidCancel:(UIImagePickerController*)picker {
    [picker dismissViewControllerAnimated:true completion:nil];
}
%end

// MARK: - Save tweet as an image

%hook TTAStatusInlineShareButton
- (void)didLongPressActionButton:(UILongPressGestureRecognizer*)gestureRecognizer {
    if ([BHTSettings boolForKey:@"tweet_to_image"]) {
        if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
            UIView* statusView = self.superview;
            while (statusView && ![statusView respondsToSelector:@selector(eventHandler)]) {
                statusView = statusView.superview;
            }

            UIView* tweetView = nil;
            id eventHandler = [(T1StandardStatusView*)statusView eventHandler];
            if ([eventHandler isKindOfClass:UIView.class]) {
                tweetView = eventHandler;
            }

            if (tweetView == nil) {
                UIView* ancestor = self.superview;
                while (ancestor && ![ancestor isKindOfClass:UITableViewCell.class] &&
                       ![ancestor isKindOfClass:UICollectionViewCell.class]) {
                    ancestor = ancestor.superview;
                }
                tweetView = ancestor;
            }

            if (tweetView == nil) {
                return %orig;
            }

            UIImage* tweetImage = imageFromView(tweetView);
            NSData* pngData = UIImagePNGRepresentation(tweetImage);
            NSURL* pngURL =
                [BHTManager temporaryFileURLWithExtension:@"png"];
            [pngData writeToURL:pngURL atomically:YES];
            UIActivityViewController* acVC =
                [[UIActivityViewController alloc] initWithActivityItems:@[pngURL]
                                                  applicationActivities:nil];
            if (is_iPad()) {
                acVC.popoverPresentationController.sourceView = self;
                acVC.popoverPresentationController.sourceRect = self.frame;
            }
            [topMostController() presentViewController:acVC animated:true completion:nil];
            return;
        }
    }
    return %orig;
}
%end

// MARK: - Native timeline media menus

static BHTMediaActionKind BHTMediaActionKindForEntities(
    NSArray* allMediaEntities) {
    NSArray* videoEntities =
        BHTVideoEntitiesFromMediaEntities(allMediaEntities);
    if (videoEntities.count == 0) {
        return BHTMediaActionKindPhoto;
    }
    return BHTMediaEntityLooksLikeGIF(videoEntities.firstObject)
               ? BHTMediaActionKindGIF
               : BHTMediaActionKindVideo;
}

static NSString* BHTMediaActionKindName(BHTMediaActionKind kind) {
    switch (kind) {
        case BHTMediaActionKindPhoto:
            return @"photo";
        case BHTMediaActionKindGIF:
            return @"gif";
        case BHTMediaActionKindVideo:
        default:
            return @"video";
    }
}

static void BHTSetPendingMediaActionKind(BHTMediaActionKind kind) {
    NSNumber* pendingKind = @(kind);
    NSMutableDictionary* threadDictionary =
        NSThread.currentThread.threadDictionary;
    threadDictionary[kBHTPendingMediaActionKindThreadKey] =
        pendingKind;
    // The preview factory is called synchronously by X. Expire this fallback
    // on the next run-loop turn so an aborted menu build cannot affect a later
    // unrelated preview.
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([threadDictionary[kBHTPendingMediaActionKindThreadKey]
                isEqual:pendingKind]) {
            [threadDictionary
                removeObjectForKey:
                    kBHTPendingMediaActionKindThreadKey];
        }
    });
}

static void BHTSetSourceMediaActionKind(
    UIView* sourceView,
    BHTMediaActionKind kind) {
    if (!sourceView) return;

    NSObject* token = [NSObject new];
    objc_setAssociatedObject(
        sourceView, &kBHTMediaActionKindKey, @(kind),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(
        sourceView, &kBHTMediaActionKindTokenKey, token,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // Only the synchronous preview factory should consume this fallback.
    // Expire it on the next run-loop turn so a source view reused by another
    // preview cannot inherit a stale media kind.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (objc_getAssociatedObject(
                sourceView, &kBHTMediaActionKindTokenKey) == token) {
            objc_setAssociatedObject(
                sourceView, &kBHTMediaActionKindKey, nil,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(
                sourceView, &kBHTMediaActionKindTokenKey, nil,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    });
}

static NSArray* BHTConfiguredNativeMediaActionItems(
    id owner,
    NSArray* origItems,
    NSArray* allMediaEntities) {
    if (allMediaEntities.count == 0) {
        return origItems ?: @[];
    }

    NSArray* mediaEntities =
        BHTVideoEntitiesFromMediaEntities(allMediaEntities);
    BHTMediaActionKind mediaKind =
        BHTMediaActionKindForEntities(allMediaEntities);
    BOOL isPhoto = mediaKind == BHTMediaActionKindPhoto;
    BOOL isGIF = mediaKind == BHTMediaActionKindGIF;
    NSMutableArray* newItems =
        origItems ? [origItems mutableCopy] : [NSMutableArray array];

    BOOL alreadyInjected = NO;
    for (id item in newItems) {
        if ([objc_getAssociatedObject(
                 item, &kBHTMediaActionInjectedKey) boolValue]) {
            alreadyInjected = YES;
            break;
        }
    }
    if (alreadyInjected) {
        NSArray* configured =
            BHTMediaActionApplyPreferences(newItems, mediaKind);
        for (id item in configured) {
            objc_setAssociatedObject(
                item, &kBHTMediaActionKindKey, @(mediaKind),
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return configured;
    }

    if (!isPhoto &&
        ![BHTSettings boolForKey:@"download_videos"]) {
        NSArray* configured =
            BHTMediaActionApplyPreferences(newItems, mediaKind);
        for (id item in configured) {
            objc_setAssociatedObject(
                item, &kBHTMediaActionKindKey, @(mediaKind),
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return configured;
    }

    DownloadInlineButton* downloader =
        objc_getAssociatedObject(owner, &kBHTMediaActionDownloaderKey);
    if (!downloader) {
        downloader = [%c(DownloadInlineButton) new];
        objc_setAssociatedObject(
            owner, &kBHTMediaActionDownloaderKey, downloader,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    TFNActionItem* downloadItem = [%c(TFNActionItem)
        actionItemWithTitle:
            [[BHTBundle sharedBundle]
                localizedStringForKey:
                    isPhoto ? @"MEDIA_ACTION_DOWNLOAD_PHOTO_MENU_TITLE"
                            : (isGIF
                                   ? @"MEDIA_ACTION_DOWNLOAD_GIF_MENU_TITLE"
                                   : @"MEDIA_ACTION_DOWNLOAD_VIDEO_MENU_TITLE")]
                  imageName:@"arrow_down_circle_stroke"
                     action:^{
                         // Let X close its preview menu before presenting the
                         // quality picker, Photos permission prompt, or HUD.
                         dispatch_async(dispatch_get_main_queue(), ^{
                             if (isPhoto) {
                                 [downloader
                                     downloadOriginalPhotoMediaEntities:
                                         allMediaEntities];
                             } else {
                                 [downloader
                                     presentDownloadOptionsForMediaEntities:
                                         mediaEntities];
                             }
                         });
                     }];
    BHTMediaActionSetIdentifier(
        downloadItem, BHTMediaActionDownloadIdentifier);
    objc_setAssociatedObject(
        downloadItem, &kBHTMediaActionInjectedKey, @YES,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    TFNActionItem* shareFileItem = [%c(TFNActionItem)
        actionItemWithTitle:
            [[BHTBundle sharedBundle]
                localizedStringForKey:
                    isPhoto
                        ? @"MEDIA_ACTION_SHARE_PHOTO_FILE_MENU_TITLE"
                        : (isGIF
                               ? @"MEDIA_ACTION_SHARE_GIF_FILE_MENU_TITLE"
                               : @"MEDIA_ACTION_SHARE_VIDEO_FILE_MENU_TITLE")]
                  imageName:@"share_stroke_bold"
                     action:^{
                         // This exports a temporary original/highest-quality
                         // file and opens Apple's share sheet without adding
                         // anything to Photos.
                         dispatch_async(dispatch_get_main_queue(), ^{
                             if (isPhoto) {
                                 [downloader
                                     shareOriginalPhotoMediaEntities:
                                         allMediaEntities];
                             } else {
                                 [downloader
                                     shareHighestQualityMediaEntities:
                                         mediaEntities];
                             }
                         });
                     }];
    BHTMediaActionSetIdentifier(
        shareFileItem, BHTMediaActionShareFileIdentifier);
    objc_setAssociatedObject(
        shareFileItem, &kBHTMediaActionInjectedKey, @YES,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [newItems addObject:downloadItem];
    [newItems addObject:shareFileItem];

    NSArray* configured =
        BHTMediaActionApplyPreferences(newItems, mediaKind);
    for (id item in configured) {
        objc_setAssociatedObject(
            item, &kBHTMediaActionKindKey, @(mediaKind),
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return configured;
}

// X 12.9's timeline photo/video preview handlers call this media-specific
// builder. The older _t1_actionItemsForStatus: path below is for a different,
// general Tweet action sheet and never sees the long-press menu in the
// recording.
%hook UIViewController
- (NSArray*)t1_mediaActivityViewActionItemsForStatus:(id)status
                                             account:(id)account
                                               image:(UIImage*)image
                                           mediaInfo:(id)mediaInfo
                                         shortTitles:(BOOL)shortTitles
                                          sourceView:(UIView*)sourceView {
    NSArray* origItems = %orig;
    NSArray* allMediaEntities =
        BHTActionTargetMediaEntities(mediaInfo, status);
    NSArray* configuredItems = BHTConfiguredNativeMediaActionItems(
        self, origItems, allMediaEntities);
    // Returned items normally carry the kind into the final preview. The
    // source-view fallback is only needed when the user hides every builder
    // row and X later appends its untagged Share Via action.
    if (allMediaEntities.count > 0 && sourceView &&
        configuredItems.count == 0) {
        BHTSetSourceMediaActionKind(
            sourceView,
            BHTMediaActionKindForEntities(allMediaEntities));
    }
    NSString* kindName =
        allMediaEntities.count > 0
            ? BHTMediaActionKindName(
                  BHTMediaActionKindForEntities(allMediaEntities))
            : @"unknown";
    BHTRecordMediaActionObservation(
        @"timelineBuilder", kindName,
        origItems.count, configuredItems.count, allMediaEntities.count);
    return configuredItems;
}

// X's player-preview wrapper calls the full selector above with sourceView=nil.
// Normally the tagged returned items carry the media kind into the final
// preview. If the user hides every builder item, preserve the kind only for
// this wrapper's synchronous final-preview call so Share Via can also stay
// hidden without leaking state from unrelated full-selector routes.
- (NSArray*)t1_mediaActivityViewActionItemsForStatus:(id)status
                                             account:(id)account
                                               image:(UIImage*)image
                                           mediaInfo:(id)mediaInfo
                                         shortTitles:(BOOL)shortTitles {
    NSArray* configuredItems = %orig;
    if (configuredItems.count == 0) {
        NSArray* allMediaEntities =
            BHTActionTargetMediaEntities(mediaInfo, status);
        if (allMediaEntities.count > 0) {
            BHTSetPendingMediaActionKind(
                BHTMediaActionKindForEntities(allMediaEntities));
        }
    }
    return configuredItems;
}

// Retain the older general action-sheet hook for overflow/player routes that
// still use it, but share the exact same download and preference pipeline.
- (NSArray*)_t1_actionItemsForStatus:(__unsafe_unretained id)status
                             account:(__unsafe_unretained id)account
                     shareableEntity:(__unsafe_unretained id)shareableEntity
                           entityURL:(__unsafe_unretained id)entityURL
                              source:(__unsafe_unretained id)source
                             options:(NSUInteger)options
                     scribeComponent:(__unsafe_unretained id)scribeComponent
                           doneBlock:
                               (void (^ __autoreleasing *)(void))doneBlock {
    NSArray* origItems = %orig;
    NSArray* allMediaEntities =
        BHTActionTargetMediaEntities(shareableEntity, status);
    NSArray* configuredItems = BHTConfiguredNativeMediaActionItems(
        self, origItems, allMediaEntities);
    if (allMediaEntities.count > 0) {
        BHTMediaActionKind kind =
            BHTMediaActionKindForEntities(allMediaEntities);
        BHTRecordMediaActionObservation(
            @"legacyBuilder", BHTMediaActionKindName(kind),
            origItems.count, configuredItems.count,
            allMediaEntities.count);
    }
    return configuredItems;
}
%end

// The timeline handler appends Share Via after the media builder returns.
// Reapply the selected order to the final action array so that row can also be
// moved or hidden. Only menus tagged by the media builder/source view are
// touched, leaving every unrelated preview menu native.
%hook TFNPreviewConfiguration
+ (id)configurationWithPreviewViewControllerBlock:
          (UIViewController* (^)(void))previewViewControllerBlock
                                      actionItems:
                                          (__unsafe_unretained NSArray*)actionItems
                                       sourceView:
                                           (__unsafe_unretained UIView*)sourceView
                                       sourceRect:(CGRect)sourceRect {
    NSNumber* kindNumber = nil;
    for (id item in actionItems) {
        kindNumber =
            objc_getAssociatedObject(item, &kBHTMediaActionKindKey);
        if (kindNumber) break;
    }
    if (!kindNumber) {
        kindNumber =
            objc_getAssociatedObject(sourceView, &kBHTMediaActionKindKey);
    }
    NSMutableDictionary* threadDictionary =
        NSThread.currentThread.threadDictionary;
    if (!kindNumber) {
        kindNumber =
            threadDictionary[kBHTPendingMediaActionKindThreadKey];
    }
    [threadDictionary
        removeObjectForKey:kBHTPendingMediaActionKindThreadKey];

    NSArray* preparedItems = actionItems;
    if (kindNumber) {
        NSMutableArray* untaggedItems = [NSMutableArray array];
        for (id item in actionItems) {
            if (!objc_getAssociatedObject(item,
                                          &kBHTMediaActionKindKey)) {
                [untaggedItems addObject:item];
            }
        }
        // X 12.9 appends exactly one Share Via item after the media builder.
        // Giving that localized/title-only row a stable identifier makes it
        // obey the editor in every language.
        if (untaggedItems.count == 1) {
            BHTMediaActionSetIdentifier(
                untaggedItems.firstObject,
                BHTMediaActionShareViaIdentifier);
        }
        preparedItems = actionItems;
    }
    NSArray* configuredItems =
        kindNumber
            ? BHTMediaActionApplyPreferences(
                  preparedItems,
                  (BHTMediaActionKind)kindNumber.integerValue)
            : preparedItems;
    if (kindNumber) {
        BHTMediaActionKind kind =
            (BHTMediaActionKind)kindNumber.integerValue;
        BHTRecordMediaActionObservation(
            @"timelineFinalPreview", BHTMediaActionKindName(kind),
            actionItems.count, configuredItems.count, 0);
    }
    if (kindNumber && sourceView) {
        objc_setAssociatedObject(
            sourceView, &kBHTMediaActionKindKey, nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(
            sourceView, &kBHTMediaActionKindTokenKey, nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return %orig(previewViewControllerBlock, configuredItems, sourceView,
                 sourceRect);
}
%end
