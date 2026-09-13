//
//  DownloadInlineButton.m
//  NeoFreeBird
//
//  Original author: BandarHelal at 09/04/2022
//  Modified by: actuallyaridan at 27/04/2025
//

#import "Download/DownloadInlineButton.h"
#import <objc/runtime.h>
#import "Core/BHTBundle.h"
#import "Core/BHTManager.h"
#import "Core/BHTSettings.h"

#pragma mark - Helpers
static UIWindow* KeyWindow(void) {
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive ||
            ![scene isKindOfClass:UIWindowScene.class])
            continue;
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            if (window.isKeyWindow)
                return window;
        }
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

static UIViewController* TopMostController(void) {
    UIViewController* top = KeyWindow().rootViewController;
    BOOL advanced = YES;
    while (top && advanced) {
        advanced = NO;
        if (top.presentedViewController) {
            top = top.presentedViewController;
            advanced = YES;
        } else if ([top isKindOfClass:UINavigationController.class] &&
                   ((UINavigationController*)top).visibleViewController) {
            top = ((UINavigationController*)top).visibleViewController;
            advanced = YES;
        } else if ([top isKindOfClass:UITabBarController.class] &&
                   ((UITabBarController*)top).selectedViewController) {
            top = ((UITabBarController*)top).selectedViewController;
            advanced = YES;
        } else if (top.childViewControllers.count == 1) {
            top = top.childViewControllers.firstObject;
            advanced = YES;
        }
    }
    return top;
}

static BOOL BHTMediaLooksLikeGIF(TFSTwitterEntityMedia* media) {
    if (media.mediaType == 2) {
        return YES;
    }
    for (TFSTwitterEntityMediaVideoVariant* variant in
         media.videoInfo.variants) {
        if ([variant.url containsString:@"/tweet_video/"]) {
            return YES;
        }
    }
    return [media.videoInfo.primaryUrl containsString:@"/tweet_video/"];
}

static BOOL BHTVariantIsMP4(TFSTwitterEntityMediaVideoVariant* variant) {
    NSString* contentType = variant.contentType.lowercaseString;
    if ([contentType hasPrefix:@"video/mp4"]) {
        return YES;
    }
    NSURL* url = variant.url.length > 0
                     ? [NSURL URLWithString:variant.url]
                     : nil;
    return [url.pathExtension.lowercaseString isEqualToString:@"mp4"];
}

static BOOL BHTVariantIsHLS(TFSTwitterEntityMediaVideoVariant* variant) {
    NSString* contentType = variant.contentType.lowercaseString;
    if ([contentType containsString:@"mpegurl"]) {
        return YES;
    }
    NSURL* url = variant.url.length > 0
                     ? [NSURL URLWithString:variant.url]
                     : nil;
    return [url.pathExtension.lowercaseString isEqualToString:@"m3u8"];
}

static NSURL* BHTHighestQualityMP4URL(TFSTwitterEntityMedia* media) {
    TFSTwitterEntityMediaVideoVariant* best = nil;
    for (TFSTwitterEntityMediaVideoVariant* variant in
         media.videoInfo.variants) {
        if (!BHTVariantIsMP4(variant) || variant.url.length == 0) {
            continue;
        }
        if (!best || variant.bitrate > best.bitrate) {
            best = variant;
        }
    }
    return best.url.length > 0 ? [NSURL URLWithString:best.url] : nil;
}

static NSURL* BHTFallbackHLSURL(TFSTwitterEntityMedia* media) {
    for (TFSTwitterEntityMediaVideoVariant* variant in
         media.videoInfo.variants) {
        if (BHTVariantIsHLS(variant) && variant.url.length > 0) {
            return [NSURL URLWithString:variant.url];
        }
    }
    NSString* primary = media.videoInfo.primaryUrl;
    NSURL* primaryURL =
        primary.length > 0 ? [NSURL URLWithString:primary] : nil;
    return [primaryURL.pathExtension.lowercaseString isEqualToString:@"m3u8"]
               ? primaryURL
               : nil;
}

static NSURL* BHTTemporaryMediaURL(NSString* extension) {
    return [BHTManager temporaryFileURLWithExtension:extension];
}

static NSURL* BHTOriginalPhotoURL(TFSTwitterEntityMedia* media) {
    NSString* rawURL = media.mediaURL;
    if (rawURL.length == 0) {
        @try {
            id candidate = [media valueForKey:@"mediaURLHttps"];
            if ([candidate isKindOfClass:NSString.class]) {
                rawURL = candidate;
            }
        } @catch (__unused NSException* exception) {
        }
    }
    if (rawURL.length == 0) return nil;

    NSURLComponents* components =
        [NSURLComponents componentsWithString:rawURL];
    if (!components) return [NSURL URLWithString:rawURL];

    NSString* extension = components.path.pathExtension.lowercaseString;
    if (extension.length > 0) {
        components.path =
            [components.path stringByDeletingPathExtension];
    }

    NSMutableArray<NSURLQueryItem*>* queryItems =
        [NSMutableArray array];
    BOOL hasFormat = NO;
    for (NSURLQueryItem* item in components.queryItems ?: @[]) {
        if ([item.name isEqualToString:@"name"]) continue;
        if ([item.name isEqualToString:@"format"]) hasFormat = YES;
        [queryItems addObject:item];
    }
    if (!hasFormat && extension.length > 0) {
        [queryItems
            addObject:[NSURLQueryItem queryItemWithName:@"format"
                                                  value:extension]];
    }
    [queryItems addObject:
                    [NSURLQueryItem queryItemWithName:@"name"
                                               value:@"orig"]];
    components.queryItems = queryItems;
    return components.URL ?: [NSURL URLWithString:rawURL];
}

static NSString* BHTPhotoExtension(NSURL* sourceURL,
                                   NSURLResponse* response) {
    NSURLComponents* components =
        [NSURLComponents componentsWithURL:sourceURL
                   resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem* item in components.queryItems ?: @[]) {
        if ([item.name isEqualToString:@"format"] &&
            item.value.length > 0) {
            return item.value.lowercaseString;
        }
    }
    NSString* suggested =
        response.suggestedFilename.pathExtension.lowercaseString;
    return suggested.length > 0 ? suggested : @"jpg";
}

#pragma mark - DownloadInlineButton
@interface DownloadInlineButton ()
@property (nonatomic, strong) TFNHUD* hud;
@end

@implementation DownloadInlineButton

#pragma mark - Temporary media sharing

- (void)bhtPresentExportError:(NSString*)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.hud hide];
        UIAlertController* alert = [UIAlertController
            alertControllerWithTitle:
                [[BHTBundle sharedBundle]
                    localizedTwitterStringForKey:@"ERROR_ALERT_TITLE"]
                             message:message.length > 0
                                         ? message
                                         : [[BHTBundle sharedBundle]
                                               localizedStringForKey:
                                                   @"UNKNOWN_ERROR"]
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:
                   [UIAlertAction
                       actionWithTitle:[[BHTBundle sharedBundle]
                                           localizedTwitterStringForKey:
                                               @"OK_ACTION_LABEL"]
                                 style:UIAlertActionStyleDefault
                               handler:nil]];
        [TopMostController() presentViewController:alert
                                          animated:YES
                                        completion:nil];
    });
}

- (void)bhtPresentShareSheetForTemporaryURL:(NSURL*)fileURL {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.hud hide];
        UIViewController* presenter = TopMostController();
        if (!presenter || !fileURL) {
            [self bhtPresentExportError:nil];
            return;
        }

        UIActivityViewController* activity =
            [[UIActivityViewController alloc]
                initWithActivityItems:@[fileURL]
                applicationActivities:nil];
        activity.completionWithItemsHandler =
            ^(UIActivityType activityType, BOOL completed,
              NSArray* returnedItems, NSError* activityError) {
                [[NSFileManager defaultManager]
                    removeItemAtURL:fileURL
                             error:nil];
            };
        if (activity.popoverPresentationController) {
            activity.popoverPresentationController.sourceView =
                presenter.view;
            activity.popoverPresentationController.sourceRect =
                CGRectMake(CGRectGetMidX(presenter.view.bounds),
                           CGRectGetMidY(presenter.view.bounds), 1, 1);
        }
        [presenter presentViewController:activity
                               animated:YES
                             completion:nil];
    });
}

- (void)bhtShareTemporaryMP4File:(NSURL*)sourceFile asGIF:(BOOL)asGIF {
    if (!asGIF) {
        [self bhtPresentShareSheetForTemporaryURL:sourceFile];
        return;
    }

    NSURL* gifFile = BHTTemporaryMediaURL(@"gif");
    NSArray<NSString*>* command = @[
        @"-y", @"-nostdin", @"-hide_banner", @"-loglevel", @"error",
        @"-i", sourceFile.path, @"-an", @"-filter_complex",
        @"split[a][b];[a]palettegen[p];[b][p]paletteuse", @"-loop", @"0",
        gifFile.path
    ];
    [FFmpegKit
        executeWithArgumentsAsync:command
        withCompleteCallback:^(FFmpegSession* session) {
            [[NSFileManager defaultManager] removeItemAtURL:sourceFile
                                                     error:nil];
            if ([ReturnCode isSuccess:[session getReturnCode]]) {
                [self bhtPresentShareSheetForTemporaryURL:gifFile];
            } else {
                [[NSFileManager defaultManager] removeItemAtURL:gifFile
                                                         error:nil];
                [self bhtPresentExportError:nil];
            }
        }
        withLogCallback:nil
        withStatisticsCallback:nil];
}

- (void)shareHighestQualityMediaEntities:(NSArray*)mediaEntities {
    NSMutableArray<TFSTwitterEntityMedia*>* candidates =
        [NSMutableArray array];
    for (id candidate in mediaEntities) {
        if ([candidate respondsToSelector:@selector(videoInfo)] &&
            [candidate videoInfo].variants.count > 0) {
            [candidates addObject:candidate];
        }
    }
    if (candidates.count > 1) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController* presenter = TopMostController();
            if (!presenter) {
                [self bhtPresentExportError:nil];
                return;
            }
            BHTBundle* bundle = [BHTBundle sharedBundle];
            UIAlertController* chooser =
                [UIAlertController
                    alertControllerWithTitle:
                        [bundle localizedStringForKey:
                                    @"MEDIA_ACTION_CHOOSE_SHARE_TITLE"]
                                     message:nil
                              preferredStyle:
                                  UIAlertControllerStyleActionSheet];
            [candidates
                enumerateObjectsUsingBlock:
                    ^(TFSTwitterEntityMedia* candidate, NSUInteger index,
                      __unused BOOL* stop) {
                NSString* formatKey =
                    BHTMediaLooksLikeGIF(candidate)
                        ? @"MEDIA_ACTION_SHARE_GIF_NUMBER_TITLE"
                        : @"MEDIA_ACTION_SHARE_VIDEO_NUMBER_TITLE";
                NSString* title =
                    [NSString
                        localizedStringWithFormat:
                            [bundle localizedStringForKey:formatKey],
                            (unsigned long)index + 1];
                [chooser
                    addAction:
                        [UIAlertAction
                            actionWithTitle:title
                                     style:UIAlertActionStyleDefault
                                   handler:
                                       ^(__unused UIAlertAction* action) {
                    [self
                        shareHighestQualityMediaEntities:@[candidate]];
                }]];
            }];
            [chooser
                addAction:
                    [UIAlertAction
                        actionWithTitle:
                            [bundle localizedTwitterStringForKey:
                                        @"CANCEL_ACTION_LABEL"]
                                 style:UIAlertActionStyleCancel
                               handler:nil]];
            if (chooser.popoverPresentationController) {
                chooser.popoverPresentationController.sourceView =
                    presenter.view;
                chooser.popoverPresentationController.sourceRect =
                    CGRectMake(CGRectGetMidX(presenter.view.bounds),
                               CGRectGetMidY(presenter.view.bounds), 1, 1);
            }
            [presenter presentViewController:chooser
                                    animated:YES
                                  completion:nil];
        });
        return;
    }

    TFSTwitterEntityMedia* media = candidates.firstObject;
    NSURL* sourceURL = media ? BHTHighestQualityMP4URL(media) : nil;
    NSURL* hlsURL = sourceURL ? nil : BHTFallbackHLSURL(media);
    sourceURL = sourceURL ?: hlsURL;
    if (!sourceURL) {
        [self bhtPresentExportError:nil];
        return;
    }

    [self.hud hide];
    self.hud = [[objc_getClass("TFNHUD") alloc]
        initWithText:[[BHTBundle sharedBundle]
                         localizedStringForKey:
                             @"BHT_DOWNLOAD_PROGRESS"]];
    [self.hud show];

    BOOL exportAsGIF = BHTMediaLooksLikeGIF(media);
    NSURL* sourceFile = BHTTemporaryMediaURL(@"mp4");
    if (hlsURL) {
        NSArray<NSString*>* command = @[
            @"-y", @"-nostdin", @"-hide_banner", @"-loglevel", @"error",
            @"-i", hlsURL.absoluteString, @"-c", @"copy", @"-movflags",
            @"+faststart", sourceFile.path
        ];
        [FFmpegKit
            executeWithArgumentsAsync:command
            withCompleteCallback:^(FFmpegSession* session) {
                if ([ReturnCode isSuccess:[session getReturnCode]]) {
                    [self bhtShareTemporaryMP4File:sourceFile
                                             asGIF:exportAsGIF];
                } else {
                    [[NSFileManager defaultManager]
                        removeItemAtURL:sourceFile
                                 error:nil];
                    [self bhtPresentExportError:nil];
                }
            }
            withLogCallback:nil
            withStatisticsCallback:nil];
        return;
    }

    NSURLSessionDownloadTask* task =
        [[NSURLSession sharedSession]
            downloadTaskWithURL:sourceURL
             completionHandler:^(NSURL* location, NSURLResponse* response,
                                 NSError* error) {
                 if (error || !location) {
                     [self bhtPresentExportError:error.localizedDescription];
                     return;
                 }
                 if ([response isKindOfClass:NSHTTPURLResponse.class]) {
                     NSInteger statusCode =
                         ((NSHTTPURLResponse*)response).statusCode;
                     if (statusCode < 200 || statusCode >= 300) {
                         [self bhtPresentExportError:
                                   [NSString
                                       stringWithFormat:
                                           @"Download failed (HTTP %ld: %@).",
                                           (long)statusCode,
                                           [NSHTTPURLResponse
                                               localizedStringForStatusCode:
                                                   statusCode]]];
                         return;
                     }
                 }

                 NSError* moveError = nil;
                 [[NSFileManager defaultManager]
                     moveItemAtURL:location
                            toURL:sourceFile
                            error:&moveError];
                 if (moveError) {
                     [self bhtPresentExportError:
                               moveError.localizedDescription];
                     return;
                 }

                 [self bhtShareTemporaryMP4File:sourceFile
                                          asGIF:exportAsGIF];
             }];
    [task resume];
}

- (NSArray<TFSTwitterEntityMedia*>*)bhtPhotoMediaEntities:
    (NSArray*)mediaEntities {
    NSMutableArray<TFSTwitterEntityMedia*>* photos =
        [NSMutableArray array];
    for (id candidate in mediaEntities) {
        if (![candidate respondsToSelector:@selector(mediaType)] ||
            ![candidate respondsToSelector:@selector(mediaURL)]) {
            continue;
        }
        TFSTwitterEntityMedia* media = candidate;
        if (media.videoInfo.variants.count == 0 &&
            BHTOriginalPhotoURL(media) != nil) {
            [photos addObject:media];
        }
    }
    return [photos copy];
}

- (TFSTwitterEntityMedia*)bhtFirstPhotoMediaEntity:(NSArray*)mediaEntities {
    return [self bhtPhotoMediaEntities:mediaEntities].firstObject;
}

- (BOOL)bhtPresentPhotoChooserIfNeeded:(NSArray*)mediaEntities
                                sharing:(BOOL)sharing {
    NSArray<TFSTwitterEntityMedia*>* photos =
        [self bhtPhotoMediaEntities:mediaEntities];
    if (photos.count <= 1) return NO;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController* presenter = TopMostController();
        if (!presenter) {
            [self bhtPresentExportError:nil];
            return;
        }
        BHTBundle* bundle = [BHTBundle sharedBundle];
        UIAlertController* chooser =
            [UIAlertController
                alertControllerWithTitle:
                    [bundle localizedStringForKey:
                                @"MEDIA_ACTION_CHOOSE_PHOTO_TITLE"]
                                 message:nil
                          preferredStyle:UIAlertControllerStyleActionSheet];
        [photos
            enumerateObjectsUsingBlock:
                ^(TFSTwitterEntityMedia* photo, NSUInteger index,
                  __unused BOOL* stop) {
            NSString* title =
                [NSString
                    localizedStringWithFormat:
                        [bundle localizedStringForKey:
                                    @"MEDIA_ACTION_PHOTO_NUMBER_TITLE"],
                        (unsigned long)index + 1];
            [chooser
                addAction:
                    [UIAlertAction
                        actionWithTitle:title
                                 style:UIAlertActionStyleDefault
                               handler:^(__unused UIAlertAction* action) {
                if (sharing) {
                    [self
                        shareOriginalPhotoMediaEntities:@[photo]];
                } else {
                    [self
                        downloadOriginalPhotoMediaEntities:@[photo]];
                }
            }]];
        }];
        [chooser
            addAction:
                [UIAlertAction
                    actionWithTitle:
                        [bundle localizedTwitterStringForKey:
                                    @"CANCEL_ACTION_LABEL"]
                             style:UIAlertActionStyleCancel
                           handler:nil]];
        if (chooser.popoverPresentationController) {
            chooser.popoverPresentationController.sourceView =
                presenter.view;
            chooser.popoverPresentationController.sourceRect =
                CGRectMake(CGRectGetMidX(presenter.view.bounds),
                           CGRectGetMidY(presenter.view.bounds), 1, 1);
        }
        [presenter presentViewController:chooser
                                animated:YES
                              completion:nil];
    });
    return YES;
}

- (void)bhtDownloadOriginalPhotoMediaEntities:(NSArray*)mediaEntities
                                   completion:
                                       (void (^)(NSURL*, NSError*))completion {
    TFSTwitterEntityMedia* media =
        [self bhtFirstPhotoMediaEntity:mediaEntities];
    NSURL* sourceURL = media ? BHTOriginalPhotoURL(media) : nil;
    if (!sourceURL) {
        NSError* error = [NSError
            errorWithDomain:@"com.bhtwitter.media"
                       code:1
                   userInfo:@{
                       NSLocalizedDescriptionKey:
                           @"The original photo URL is unavailable."
                   }];
        if (completion) completion(nil, error);
        return;
    }

    [self.hud hide];
    self.hud = [[objc_getClass("TFNHUD") alloc]
        initWithText:[[BHTBundle sharedBundle]
                         localizedStringForKey:
                             @"BHT_DOWNLOAD_PROGRESS"]];
    [self.hud show];

    NSURLSessionDownloadTask* task =
        [[NSURLSession sharedSession]
            downloadTaskWithURL:sourceURL
             completionHandler:^(NSURL* location, NSURLResponse* response,
                                 NSError* error) {
                 if (!error &&
                     [response isKindOfClass:NSHTTPURLResponse.class]) {
                     NSInteger statusCode =
                         ((NSHTTPURLResponse*)response).statusCode;
                     if (statusCode < 200 || statusCode >= 300) {
                         error = [NSError
                             errorWithDomain:@"com.bhtwitter.media"
                                        code:statusCode
                                    userInfo:@{
                                        NSLocalizedDescriptionKey:
                                            [NSString
                                                stringWithFormat:
                                                    @"The photo server returned HTTP %ld.",
                                                    (long)statusCode]
                                    }];
                     }
                 }

                 NSURL* retainedURL = nil;
                 if (!error && location) {
                     retainedURL =
                         BHTTemporaryMediaURL(
                             BHTPhotoExtension(sourceURL, response));
                     NSError* moveError = nil;
                     if (![[NSFileManager defaultManager]
                             moveItemAtURL:location
                                    toURL:retainedURL
                                    error:&moveError]) {
                         retainedURL = nil;
                         error = moveError;
                     }
                 }
                 dispatch_async(dispatch_get_main_queue(), ^{
                     if (completion) completion(retainedURL, error);
                 });
             }];
    [task resume];
}

- (void)downloadOriginalPhotoMediaEntities:(NSArray*)mediaEntities {
    if ([self bhtPresentPhotoChooserIfNeeded:mediaEntities
                                     sharing:NO]) {
        return;
    }
    [self
        bhtDownloadOriginalPhotoMediaEntities:mediaEntities
                                  completion:^(NSURL* fileURL,
                                               NSError* error) {
        if (error || !fileURL) {
            [self bhtPresentExportError:error.localizedDescription];
            return;
        }

        void (^savePhoto)(void) = ^{
            [[PHPhotoLibrary sharedPhotoLibrary]
                performChanges:^{
                    [PHAssetChangeRequest
                        creationRequestForAssetFromImageAtFileURL:fileURL];
                }
                completionHandler:^(BOOL success, NSError* saveError) {
                    [[NSFileManager defaultManager]
                        removeItemAtURL:fileURL
                                 error:nil];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.hud hide];
                        if (success) {
                            UINotificationFeedbackGenerator* feedback =
                                [UINotificationFeedbackGenerator new];
                            [feedback
                                notificationOccurred:
                                    UINotificationFeedbackTypeSuccess];
                        } else {
                            [self
                                bhtPresentExportError:
                                    saveError.localizedDescription];
                        }
                    });
                }];
        };

        PHAuthorizationStatus status =
            [PHPhotoLibrary authorizationStatusForAccessLevel:
                                PHAccessLevelAddOnly];
        if (status == PHAuthorizationStatusAuthorized ||
            status == PHAuthorizationStatusLimited) {
            savePhoto();
            return;
        }
        if (status == PHAuthorizationStatusNotDetermined) {
            [PHPhotoLibrary
                requestAuthorizationForAccessLevel:PHAccessLevelAddOnly
                                           handler:
                ^(PHAuthorizationStatus requestedStatus) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (requestedStatus ==
                                PHAuthorizationStatusAuthorized ||
                            requestedStatus ==
                                PHAuthorizationStatusLimited) {
                            savePhoto();
                        } else {
                            [[NSFileManager defaultManager]
                                removeItemAtURL:fileURL
                                         error:nil];
                            [self
                                bhtPresentExportError:
                                    @"Allow photo access in Settings to download this photo."];
                        }
                    });
                }];
            return;
        }

        [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
        [self bhtPresentExportError:
                  @"Allow photo access in Settings to download this photo."];
    }];
}

- (void)shareOriginalPhotoMediaEntities:(NSArray*)mediaEntities {
    if ([self bhtPresentPhotoChooserIfNeeded:mediaEntities
                                     sharing:YES]) {
        return;
    }
    [self
        bhtDownloadOriginalPhotoMediaEntities:mediaEntities
                                  completion:^(NSURL* fileURL,
                                               NSError* error) {
        if (error || !fileURL) {
            [self bhtPresentExportError:error.localizedDescription];
            return;
        }
        [self bhtPresentShareSheetForTemporaryURL:fileURL];
    }];
}

#pragma mark - Download handler
- (void)presentDownloadOptionsForMediaEntities:(NSArray*)mediaEntities {
    @try {
        NSAttributedString* titleString = [[NSAttributedString alloc]
            initWithString:[[BHTBundle sharedBundle]
                               localizedStringForKey:@"DOWNLOAD_MENU_TITLE"]
                attributes:@{
                    NSFontAttributeName: [BHTManager menuTitleFont],
                    NSForegroundColorAttributeName: UIColor.labelColor
                }];
        TFNActiveTextItem* title = [[objc_getClass("TFNActiveTextItem") alloc]
            initWithTextModel:[[objc_getClass("TFNAttributedTextModel") alloc]
                                  initWithAttributedString:titleString]
                 activeRanges:nil];

        void (^showHUD)(NSString*) = ^(NSString* text) {
            [self.hud hide];
            self.hud = [[objc_getClass("TFNHUD") alloc] initWithText:text];
            [self.hud show];
        };
        void (^dismissHUD)(void) = ^{
            [self.hud hide];
        };

        NSString* downloadingText = [[BHTBundle sharedBundle]
            localizedStringForKey:@"BHT_DOWNLOAD_PROGRESS"];

        void (^presentError)(NSString*) = ^(NSString* message) {
            dispatch_async(dispatch_get_main_queue(), ^{
                dismissHUD();
                UINotificationFeedbackGenerator* feedback =
                    [UINotificationFeedbackGenerator new];
                [feedback prepare];
                [feedback notificationOccurred:UINotificationFeedbackTypeError];

                UIAlertController* alert = [UIAlertController
                    alertControllerWithTitle:
                        [[BHTBundle sharedBundle]
                            localizedTwitterStringForKey:@"ERROR_ALERT_TITLE"]
                                     message:message.length > 0
                                                 ? message
                                                 : [[BHTBundle sharedBundle]
                                                       localizedStringForKey:
                                                           @"UNKNOWN_ERROR"]
                              preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:
                           [UIAlertAction
                               actionWithTitle:[[BHTBundle sharedBundle]
                                                   localizedTwitterStringForKey:
                                                       @"OK_ACTION_LABEL"]
                                         style:UIAlertActionStyleDefault
                                       handler:nil]];
                [TopMostController() presentViewController:alert
                                                  animated:YES
                                                completion:nil];
            });
        };

        void (^finishFile)(NSURL*, NSString*) =
            ^(NSURL* outFile, NSString* ext) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    dismissHUD();
                    UINotificationFeedbackGenerator* feedback =
                        [UINotificationFeedbackGenerator new];
                    [feedback prepare];

                    if (![BHTSettings boolForKey:@"direct_save"]) {
                        [BHTManager showSaveVC:outFile];
                    } else {
                        void (^saved)(BOOL, NSError*) =
                            ^(BOOL success, NSError* error) {
                                if (success) {
                                    [feedback notificationOccurred:
                                                  UINotificationFeedbackTypeSuccess];
                                } else {
                                    [feedback notificationOccurred:
                                                  UINotificationFeedbackTypeError];
                                    presentError(error.localizedDescription);
                                }
                                [[NSFileManager defaultManager]
                                    removeItemAtURL:outFile
                                             error:nil];
                            };
                        if ([ext isEqualToString:@"gif"]) {
                            [BHTManager saveGIF:outFile completion:saved];
                        } else {
                            [BHTManager save:outFile completion:saved];
                        }
                    }
                });
            };

        // Direct MP4 variants do not need transcoding. NSURLSession is more
        // reliable for X's signed CDN URLs and avoids making an otherwise valid
        // download depend on FFmpeg's HTTPS command parser.
        void (^downloadMP4)(NSURL*) = ^(NSURL* url) {
            showHUD(downloadingText);
            NSURL* outFile =
                [BHTManager temporaryFileURLWithExtension:@"mp4"];
            NSURLSessionDownloadTask* task =
                [[NSURLSession sharedSession]
                    downloadTaskWithURL:url
                     completionHandler:^(NSURL* location,
                                         NSURLResponse* response,
                                         NSError* error) {
                         if (error || !location) {
                             presentError(error.localizedDescription);
                             return;
                         }
                         if ([response isKindOfClass:NSHTTPURLResponse.class] &&
                             !NSLocationInRange(
                                 ((NSHTTPURLResponse*)response).statusCode,
                                 NSMakeRange(200, 100))) {
                             NSInteger statusCode =
                                 ((NSHTTPURLResponse*)response).statusCode;
                             presentError([NSString
                                 stringWithFormat:@"Download failed (HTTP %ld: %@).",
                                                  (long)statusCode,
                                                  [NSHTTPURLResponse
                                                      localizedStringForStatusCode:
                                                          statusCode]]);
                             return;
                         }

                         NSError* moveError = nil;
                         [[NSFileManager defaultManager]
                             moveItemAtURL:location
                                    toURL:outFile
                                    error:&moveError];
                         if (moveError) {
                             presentError(moveError.localizedDescription);
                             return;
                         }
                         finishFile(outFile, @"mp4");
                     }];
            [task resume];
        };

        // Use FFmpeg's argument-array API so signed URLs and filter graphs are
        // never split or re-tokenized. cleanupFile is removed after conversion.
        void (^ffmpegDownload)(NSArray<NSString*>*, NSString*, double, NSURL*) =
            ^(NSArray<NSString*>* args, NSString* ext, double durationMs,
              NSURL* cleanupFile) {
            showHUD(downloadingText);
            NSURL* outFile =
                [BHTManager temporaryFileURLWithExtension:ext];
            NSMutableArray<NSString*>* command = [NSMutableArray arrayWithArray:@[
                @"-y", @"-nostdin", @"-hide_banner", @"-loglevel", @"error"
            ]];
            [command addObjectsFromArray:args];
            [command addObject:outFile.path];
            [FFmpegKit
                executeWithArgumentsAsync:command
                withCompleteCallback:^(FFmpegSession* session) {
                    ReturnCode* returnCode = [session getReturnCode];
                    if (cleanupFile) {
                        [[NSFileManager defaultManager]
                            removeItemAtURL:cleanupFile
                                     error:nil];
                    }
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if ([ReturnCode isSuccess:returnCode]) {
                            finishFile(outFile, ext);
                        } else {
                            presentError(nil);
                        }
                    });
                }
                withLogCallback:nil
                withStatisticsCallback:^(Statistics* statistics) {
                    NSString* detail;
                    if (durationMs > 0) {
                        detail = [BHTManager
                            getDownloadingPercent:MIN([statistics getTime] / durationMs,
                                                      1.0)];
                    } else if ([statistics getSize] > 0) {
                        detail = [NSByteCountFormatter
                            stringFromByteCount:[statistics getSize]
                                     countStyle:NSByteCountFormatterCountStyleFile];
                    } else {
                        return;
                    }
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.hud
                            setText:[NSString stringWithFormat:@"%@ %@", downloadingText,
                                                               detail]];
                    });
                }];
        };

        // X serves animated GIF posts as MP4 loops. Fetch the source with the
        // native networking stack first, then feed FFmpeg a local path for the
        // palette conversion.
        void (^downloadGIF)(NSURL*, double) =
            ^(NSURL* url, double durationMs) {
                showHUD(downloadingText);
                NSURL* inputFile =
                    [BHTManager temporaryFileURLWithExtension:@"mp4"];
                NSURLSessionDownloadTask* task =
                    [[NSURLSession sharedSession]
                        downloadTaskWithURL:url
                         completionHandler:^(NSURL* location,
                                             NSURLResponse* response,
                                             NSError* error) {
                             if (error || !location) {
                                 presentError(error.localizedDescription);
                                 return;
                             }
                             if ([response
                                     isKindOfClass:NSHTTPURLResponse.class] &&
                                 !NSLocationInRange(
                                     ((NSHTTPURLResponse*)response).statusCode,
                                     NSMakeRange(200, 100))) {
                                 NSInteger statusCode =
                                     ((NSHTTPURLResponse*)response).statusCode;
                                 presentError([NSString
                                     stringWithFormat:
                                         @"Download failed (HTTP %ld: %@).",
                                         (long)statusCode,
                                         [NSHTTPURLResponse
                                             localizedStringForStatusCode:
                                                 statusCode]]);
                                 return;
                             }

                             NSError* moveError = nil;
                             [[NSFileManager defaultManager]
                                 moveItemAtURL:location
                                        toURL:inputFile
                                        error:&moveError];
                             if (moveError) {
                                 presentError(moveError.localizedDescription);
                                 return;
                             }

                             dispatch_async(dispatch_get_main_queue(), ^{
                                 ffmpegDownload(
                                     @[
                                         @"-i", inputFile.path, @"-an",
                                         @"-filter_complex",
                                         @"split[a][b];[a]palettegen[p];[b][p]paletteuse",
                                         @"-loop", @"0"
                                     ],
                                     @"gif", durationMs, inputFile);
                             });
                         }];
                [task resume];
            };

        // Variant builders
        TFNActionItem* (^makeMP4Item)(NSURL*, double, NSString*) =
            ^TFNActionItem*(NSURL* url, double durationMs, NSString* itemTitle) {
                return [objc_getClass("TFNActionItem")
                    actionItemWithTitle:itemTitle
                              imageName:@"arrow_down_circle_stroke"
                                 action:^{
                                     downloadMP4(url);
                                 }];
            };

        TFNActionItem* (^makeGIFItem)(NSURL*, double) = ^TFNActionItem*(
            NSURL* url, double durationMs) {
            return [objc_getClass("TFNActionItem")
                actionItemWithTitle:
                    [[BHTBundle sharedBundle]
                        localizedStringForKey:@"DOWNLOAD_AS_GIF_OPTION_TITLE"]
                          imageName:@"arrow_down_circle_stroke"
                             action:^{
                                 downloadGIF(url, durationMs);
                             }];
        };

        TFNActionItem* (^makeHLSItem)(NSURL*, NSString*, double) = ^TFNActionItem*(
            NSURL* url, NSString* resolution, double durationMs) {
            return [objc_getClass("TFNActionItem")
                actionItemWithTitle:resolution
                          imageName:@"arrow_down_circle_stroke"
                             action:^{
                                 ffmpegDownload(
                                     @[
                                         @"-i", url.absoluteString, @"-vf",
                                         [NSString
                                             stringWithFormat:
                                                 @"scale=%@:flags=lanczos",
                                                 resolution],
                                         @"-c:v", @"h264_videotoolbox",
                                         @"-b:v", @"2M", @"-c:a", @"copy"
                                     ],
                                     @"mp4", durationMs, nil);
                             }];
        };

        // videoInfo.variants backs both video (mediaType 3) and GIF (mediaType 2);
        // photos carry no videoInfo. Probing the playlist supplies the duration
        // for progress and any HLS-only resolutions, so every quality is offered
        // in a single sheet. mp4 variants win when both carry the same
        // resolution; media without a playlist (GIFs) skips the probe entirely.
        void (^buildVariantItems)(TFSTwitterEntityMedia*, void (^)(NSArray*)) = ^(
            TFSTwitterEntityMedia* media, void (^done)(NSArray*)) {
            NSMutableArray<NSURL*>* mp4URLs = [NSMutableArray new];
            NSURL* m3u8URL = nil;
            for (TFSTwitterEntityMediaVideoVariant* variant in media.videoInfo
                     .variants) {
                NSURL* url =
                    variant.url.length ? [NSURL URLWithString:variant.url] : nil;
                if (!url)
                    continue;

                if (BHTVariantIsMP4(variant))
                    [mp4URLs addObject:url];
                else if (BHTVariantIsHLS(variant) && !m3u8URL)
                    m3u8URL = url;
            }

            NSMutableArray* items = [NSMutableArray new];
            NSMutableSet<NSString*>* offered = [NSMutableSet new];
            void (^appendMP4Items)(double) = ^(double durationMs) {
                BOOL isGIF = BHTMediaLooksLikeGIF(media);
                for (NSURL* url in mp4URLs) {
                    NSString* itemTitle =
                        isGIF ? [[BHTBundle sharedBundle]
                                    localizedStringForKey:@"DOWNLOAD_AS_MP4_OPTION_TITLE"]
                              : [BHTManager getVideoQuality:url.absoluteString];
                    [offered addObject:[BHTManager getVideoQuality:url.absoluteString]];
                    [items addObject:makeMP4Item(url, durationMs, itemTitle)];
                    if (isGIF)
                        [items addObject:makeGIFItem(url, durationMs)];
                }
            };

            if (!m3u8URL) {
                appendMP4Items(0);
                done(items);
                return;
            }

            showHUD([[BHTBundle sharedBundle]
                localizedStringForKey:@"FETCHING_PROGRESS_TITLE"]);
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                MediaInformation* info = [BHTManager getM3U8Information:m3u8URL];
                double durationMs = [info getDuration].doubleValue * 1000.0;

                dispatch_async(dispatch_get_main_queue(), ^{
                    dismissHUD();
                    appendMP4Items(durationMs);
                    for (StreamInformation* stream in [info getStreams]) {
                        NSNumber* width = [stream getWidth];
                        NSNumber* height = [stream getHeight];
                        if (width == nil || height == nil)
                            continue;

                        NSString* resolution =
                            [NSString stringWithFormat:@"%@x%@", width, height];
                        if ([offered containsObject:resolution])
                            continue;

                        [offered addObject:resolution];
                        [items addObject:makeHLSItem(m3u8URL, resolution, durationMs)];
                    }
                    done(items);
                });
            });
        };

        // Filter to video/GIF so grouping keys off the real video count, not the
        // raw media count.
        NSMutableArray<TFSTwitterEntityMedia*>* videoEntities =
            [NSMutableArray new];
        for (TFSTwitterEntityMedia* media in mediaEntities) {
            if (media.videoInfo.variants.count > 0) {
                [videoEntities addObject:media];
            }
        }

        void (^presentSheet)(NSArray*) = ^(NSArray* items) {
            NSMutableArray* actions = [NSMutableArray arrayWithObject:title];
            [actions addObjectsFromArray:items];

            TFNMenuSheetViewController* sheet =
                [[objc_getClass("TFNMenuSheetViewController") alloc]
                    initWithActionItems:actions.copy];
            [sheet tfnPresentedCustomPresentFromViewController:TopMostController()
                                                      animated:YES
                                                    completion:nil];
        };

        if (videoEntities.count > 1) {
            NSMutableArray* groups = [NSMutableArray new];
            [videoEntities enumerateObjectsUsingBlock:^(TFSTwitterEntityMedia* media,
                                                        NSUInteger idx, BOOL* stop) {
                [groups
                    addObject:[objc_getClass("TFNActionItem")
                                  actionItemWithTitle:
                                      [NSString
                                          stringWithFormat:
                                              [[BHTBundle sharedBundle]
                                                  localizedStringForKey:
                                                      @"DOWNLOAD_VIDEO_NUMBER_TITLE"],
                                              (unsigned long)idx + 1]
                                            imageName:@"arrow_down_circle_stroke"
                                               action:^{
                                                   buildVariantItems(media, presentSheet);
                                               }]];
            }];
            presentSheet(groups);
        } else {
            buildVariantItems(videoEntities.firstObject, presentSheet);
        }
    } @catch (__unused NSException* ex) {
        UIAlertController* alert = [UIAlertController
            alertControllerWithTitle:
                [[BHTBundle sharedBundle]
                    localizedTwitterStringForKey:@"ERROR_ALERT_TITLE"]
                             message:[[BHTBundle sharedBundle]
                                         localizedStringForKey:@"UNKNOWN_ERROR"]
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction
                             actionWithTitle:[[BHTBundle sharedBundle]
                                                 localizedTwitterStringForKey:
                                                     @"OK_ACTION_LABEL"]
                                       style:UIAlertActionStyleDefault
                                     handler:nil]];
        [TopMostController() presentViewController:alert
                                          animated:YES
                                        completion:nil];
    }
}

@end
