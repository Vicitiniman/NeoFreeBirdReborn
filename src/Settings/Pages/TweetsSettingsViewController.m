//
//  TweetsSettingsViewController.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Settings/Pages/TweetsSettingsViewController.h"
#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"
#import "Headers/TWHeaders.h"
#import "Reply/BHTWebReplyFallback.h"
#import "Settings/ModernSettingsCells.h"

@implementation TweetsSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [NSNotificationCenter.defaultCenter
        addObserver:self
           selector:
               @selector(webReplyAccountLabelDidChange:)
               name:
                   BHTWebReplyAccountLabelDidChangeNotification
             object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter
        removeObserver:self
                  name:
                      BHTWebReplyAccountLabelDidChangeNotification
                object:nil];
}

- (void)webReplyAccountLabelDidChange:
    (__unused NSNotification*)notification {
    [self.tableView reloadData];
}

- (NSString*)pageKey {
    return @"tweets";
}

- (void)switchChanged:(UISwitch*)sender {
    NSString* key = BHTSettingsKeyForSwitch(sender);
    BOOL enablingWebReply =
        [key isEqualToString:@"web_reply_fallback"] && sender.isOn;
    [super switchChanged:sender];
    if (!enablingWebReply) return;

    BHTBundle* bundle = BHTBundle.sharedBundle;
    UIAlertController* disclosure = [UIAlertController
        alertControllerWithTitle:
            [bundle localizedStringForKey:@"WEB_REPLY_FALLBACK_TITLE"]
                         message:
            [bundle localizedStringForKey:
                        @"WEB_REPLY_FALLBACK_DISCLOSURE"]
                  preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [disclosure addAction:[UIAlertAction
        actionWithTitle:
            [bundle localizedStringForKey:
                        @"WEB_REPLY_FALLBACK_SIGN_IN_NOW"]
                  style:UIAlertActionStyleDefault
                handler:^(__unused UIAlertAction* action) {
                    dispatch_after(
                        dispatch_time(
                            DISPATCH_TIME_NOW,
                            (int64_t)(0.35 * NSEC_PER_SEC)),
                        dispatch_get_main_queue(), ^{
                            BHTPresentWebReplySignInSetup(
                                weakSelf);
                        });
                }]];
    [disclosure addAction:[UIAlertAction
        actionWithTitle:
            [bundle localizedStringForKey:
                        @"WEB_REPLY_FALLBACK_NOT_NOW"]
                  style:UIAlertActionStyleCancel
                handler:nil]];

    __weak UISwitch* weakSender = sender;
    [disclosure addAction:[UIAlertAction
        actionWithTitle:
            [bundle localizedStringForKey:
                        @"WEB_REPLY_FALLBACK_TURN_OFF"]
                  style:UIAlertActionStyleDestructive
                handler:^(__unused UIAlertAction* action) {
                    UISwitch* strongSender = weakSender;
                    if (!strongSender) {
                        [NSUserDefaults.standardUserDefaults
                            setBool:NO
                             forKey:@"web_reply_fallback"];
                        [weakSelf.tableView reloadData];
                        return;
                    }
                    strongSender.on = NO;
                    [weakSelf switchChanged:strongSender];
                }]];
    [self presentViewController:disclosure
                       animated:YES
                     completion:nil];
}

- (void)showWebReplySignInSetup:
    (__unused NSDictionary*)data {
    BHTPresentWebReplyAccountManager(self);
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    NSDictionary* settingData = [self settingAtIndexPath:indexPath];
    if ([settingData[@"key"]
            isEqualToString:@"web_reply_sign_in_setup"]) {
        ModernSettingsCompactButtonCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"CompactButtonCell"
                                            forIndexPath:indexPath];
        NSString* title = [[BHTBundle sharedBundle]
            localizedStringForKey:
                settingData[@"titleKey"]];
        [cell configureWithTitle:title
                       subtitle:
                           [self webReplyAccountSubtitle]];
        return cell;
    }
    if ([settingData[@"key"] isEqualToString:@"undo_tweet_timeout"]) {
        ModernSettingsCompactButtonCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"CompactButtonCell"
                                            forIndexPath:indexPath];
        NSString* title = [[BHTBundle sharedBundle] localizedStringForKey:settingData[@"titleKey"]];
        [cell configureWithTitle:title subtitle:[self undoTimeoutSubtitle]];
        return cell;
    }
    return [super tableView:tableView cellForRowAtIndexPath:indexPath];
}

- (NSString*)webReplyAccountSubtitle {
    BHTBundle* bundle = BHTBundle.sharedBundle;
    NSString* label = BHTWebReplyAccountLabel();
    if (label.length == 0) {
        return [bundle
            localizedStringForKey:
                @"WEB_REPLY_ACCOUNT_LABEL_NONE"];
    }
    return [NSString
        stringWithFormat:
            [bundle localizedStringForKey:
                        @"WEB_REPLY_ACCOUNT_LABEL_FORMAT"],
            label];
}

// A timeout of 0 reads as "Off"; any positive value shows its seconds.
- (NSString*)labelForTimeout:(NSInteger)seconds {
    if (seconds <= 0) {
        return [[BHTBundle sharedBundle] localizedStringForKey:@"UNDO_SEND_OFF"];
    }
    NSString* format = [[BHTBundle sharedBundle]
        localizedStringForKey:@"UNDO_SEND_SECONDS_FORMAT"];
    return [NSString stringWithFormat:format, (long)seconds];
}

- (NSString*)undoTimeoutSubtitle {
    return [self labelForTimeout:[BHTSettings integerForKey:@"undo_tweet_timeout"]];
}

// Off plus the same durations Twitter offers in its own premium undo settings.
- (void)showUndoTimeoutPicker:(NSDictionary*)sender {
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"UNDO_TWEET_TITLE"]
                         message:[[BHTBundle sharedBundle]
                                     localizedStringForKey:@"UNDO_SEND_DESCRIPTION"]
                  preferredStyle:UIAlertControllerStyleAlert];

    for (NSNumber* seconds in @[@0, @5, @10, @20, @30, @60]) {
        [alert addAction:[UIAlertAction actionWithTitle:[self labelForTimeout:seconds.integerValue]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction* action) {
                                                    [[NSUserDefaults standardUserDefaults]
                                                        setInteger:seconds.integerValue
                                                            forKey:@"undo_tweet_timeout"];
                                                    [self.tableView reloadData];
                                                }]];
    }

    [alert addAction:[UIAlertAction
                         actionWithTitle:[[BHTBundle sharedBundle]
                                             localizedTwitterStringForKey:@"CANCEL_ACTION_LABEL"]
                                   style:UIAlertActionStyleCancel
                                 handler:nil]];

    [self presentViewController:alert animated:YES completion:nil];
}

@end
