#import "CustomTabBar/BHTTabViewAppearance.h"
//
//  AppearanceSettingsViewController.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Settings/Pages/AppearanceSettingsViewController.h"
#import <objc/message.h>
#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"
#import "Headers/TWHeaders.h"
#import "Settings/ModernSettingsCells.h"
#import "Settings/Pages/PresetSettingsViewController.h"
#import "Navigation/BHTLiquidGlassDesign.h"

@interface AppearanceSettingsViewController () <UIFontPickerViewControllerDelegate>
@end

@implementation AppearanceSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.estimatedRowHeight = 60;
    [self.tableView registerClass:[ModernSettingsSimpleButtonCell class]
           forCellReuseIdentifier:@"SimpleButtonCell"];
}

- (NSString*)pageKey {
    return @"appearance";
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    NSDictionary* settingData = [self settingAtIndexPath:indexPath];
    if ([settingData[@"type"] isEqualToString:@"button"]) {
        ModernSettingsSimpleButtonCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"SimpleButtonCell"
                                            forIndexPath:indexPath];
        NSString* title = [[BHTBundle sharedBundle] localizedStringForKey:settingData[@"titleKey"]];
        [cell configureWithTitle:title];
        return cell;
    }
    return [super tableView:tableView cellForRowAtIndexPath:indexPath];
}

#pragma mark - Sub-page Navigation

- (void)showThemeViewController:(NSDictionary*)sender {
    PresetSettingsViewController* themes =
        [[PresetSettingsViewController alloc]
            initWithAccount:self.account];
    [self.navigationController pushViewController:themes animated:YES];
}

- (void)showAppIconViewController:(NSDictionary*)sender {
    Class AppIconViewControllerClass = objc_getClass("AppIconViewController");
    if (AppIconViewControllerClass) {
        UIViewController* appIconVC = [[AppIconViewControllerClass alloc] init];
        if (self.account) {
            [appIconVC.navigationItem
                setTitleView:[objc_getClass("TFNTitleView")
                                 titleViewWithTitle:[[BHTBundle sharedBundle]
                                                        localizedTwitterStringForKey:
                                                            @"SUBSCRIPTION_APP_ICON_SETTINGS_TITLE"]
                                           subtitle:self.account.displayUsername]];
        }
        [self.navigationController pushViewController:appIconVC animated:YES];
    }
}

- (void)showCustomTabBarVC:(NSDictionary*)sender {
    Class CustomTabBarViewControllerClass = objc_getClass("CustomTabBarViewController");
    if (CustomTabBarViewControllerClass) {
        UIViewController* customTabBarVC = [[CustomTabBarViewControllerClass alloc] init];
        if (self.account) {
            [customTabBarVC.navigationItem
                setTitleView:[objc_getClass("TFNTitleView")
                                 titleViewWithTitle:[[BHTBundle sharedBundle]
                                                        localizedStringForKey:
                                                            @"CUSTOM_TAB_BAR_SETTINGS_NAVIGATION_TITLE"]
                                           subtitle:self.account.displayUsername]];
        }
        [self.navigationController pushViewController:customTabBarVC animated:YES];
    }
}

- (void)showLikesNavigationVC:(NSDictionary*)sender {
    Class editorClass = objc_getClass("BHTLikesNavigationViewController");
    if (!editorClass) return;

    UIViewController* editor = [[editorClass alloc] init];
    if (self.account) {
        [editor.navigationItem
            setTitleView:
                [objc_getClass("TFNTitleView")
                    titleViewWithTitle:[[BHTBundle sharedBundle]
                                           localizedStringForKey:
                                               @"LIKES_NAVIGATION_SETTINGS_TITLE"]
                              subtitle:self.account.displayUsername]];
    }
    [self.navigationController pushViewController:editor animated:YES];
}

- (void)showSidebarNavigationVC:(NSDictionary*)sender {
    Class editorClass =
        objc_getClass("BHTSidebarNavigationViewController");
    if (!editorClass) return;

    UIViewController* editor = [[editorClass alloc] init];
    if (self.account) {
        [editor.navigationItem
            setTitleView:
                [objc_getClass("TFNTitleView")
                    titleViewWithTitle:[[BHTBundle sharedBundle]
                                           localizedStringForKey:
                                               @"SIDEBAR_NAVIGATION_SETTINGS_TITLE"]
                              subtitle:self.account.displayUsername]];
    }
    [self.navigationController pushViewController:editor animated:YES];
}

#pragma mark - Tab Bar Refresh

- (void)refreshAllTabViewsWithTheming {
    for (UIWindow* window in [UIApplication sharedApplication].windows) {
        if (window.isKeyWindow && window.rootViewController) {
            [self refreshTabViewsWithThemingInView:window.rootViewController.view];
        }
    }
}

- (void)refreshTabViewsWithThemingInView:(UIView*)view {
    if ([view isKindOfClass:NSClassFromString(@"T1TabView")]) {
        SEL selector = NSSelectorFromString(@"_t1_updateImageViewAnimated:");
        if ([view respondsToSelector:selector]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(view, selector, NO);
        }
        BHTRefreshTabViewAppearance(view);
        [view setNeedsLayout];
    }
    for (UIView* subview in view.subviews) {
        [self refreshTabViewsWithThemingInView:subview];
    }
}

- (void)refreshAllTabViews {
    for (UIWindow* window in [UIApplication sharedApplication].windows) {
        if (window.isKeyWindow && window.rootViewController) {
            [self refreshTabViewsInView:window.rootViewController.view];
        }
    }
}

- (void)refreshTabViewsInView:(UIView*)view {
    if ([view isKindOfClass:NSClassFromString(@"T1TabView")]) {
        SEL selector = NSSelectorFromString(@"_t1_updateImageViewAnimated:");
        if ([view respondsToSelector:selector]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(view, selector, NO);
        }
        BHTRefreshTabViewAppearance(view);
        [view setNeedsLayout];
    }
    for (UIView* subview in view.subviews) {
        [self refreshTabViewsInView:subview];
    }
}

- (void)switchChanged:(UISwitch*)sender {
    [super switchChanged:sender];
    NSString* key = BHTSettingsKeyForSwitch(sender);
    if ([key isEqualToString:@"liquid_glass_design"] || [key isEqualToString:@"classic_navigation"]) {
        if (sender.isOn) {
            NSString* other = [key isEqualToString:@"liquid_glass_design"] ? @"classic_navigation" : @"liquid_glass_design";
            [NSUserDefaults.standardUserDefaults setBool:NO forKey:other];
            [BHTSettings notePreferencesChanged];
            [self updateVisibleToggles];
        }
        BHTRefreshLiquidGlassDesign();
    } else if ([key isEqualToString:@"tab_bar_theming"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self refreshAllTabViewsWithTheming];
        });
    } else if ([key isEqualToString:@"restore_tab_labels"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self refreshAllTabViews];
        });
    }
}

#pragma mark - Font Pickers

- (void)showRegularFontPicker:(NSDictionary*)sender {
    UIFontPickerViewControllerConfiguration* configuration =
        [[UIFontPickerViewControllerConfiguration alloc] init];
    [configuration setFilteredTraits:UIFontDescriptorClassMask];
    [configuration setIncludeFaces:NO];
    UIFontPickerViewController* fontPicker =
        [[UIFontPickerViewController alloc] initWithConfiguration:configuration];
    fontPicker.delegate = (id<UIFontPickerViewControllerDelegate>)self;
    BHTMarkNeoFreeBirdFontPicker(fontPicker, @"regular");
    if (self.account) {
        [fontPicker.navigationItem
            setTitleView:
                [objc_getClass("TFNTitleView")
                    titleViewWithTitle:[[BHTBundle sharedBundle]
                                           localizedStringForKey:@"REGULAR_FONTS_PICKER_OPTION_TITLE"]
                              subtitle:self.account.displayUsername]];
    } else {
        fontPicker.title =
            [[BHTBundle sharedBundle] localizedStringForKey:@"REGULAR_FONTS_PICKER_OPTION_TITLE"];
    }
    [self.navigationController pushViewController:fontPicker animated:YES];
}

- (void)showBoldFontPicker:(NSDictionary*)sender {
    UIFontPickerViewControllerConfiguration* configuration =
        [[UIFontPickerViewControllerConfiguration alloc] init];
    [configuration setIncludeFaces:YES];
    [configuration setFilteredTraits:UIFontDescriptorClassMask];
    UIFontPickerViewController* fontPicker =
        [[UIFontPickerViewController alloc] initWithConfiguration:configuration];
    fontPicker.delegate = (id<UIFontPickerViewControllerDelegate>)self;
    BHTMarkNeoFreeBirdFontPicker(fontPicker, @"bold");
    if (self.account) {
        [fontPicker.navigationItem
            setTitleView:
                [objc_getClass("TFNTitleView")
                    titleViewWithTitle:[[BHTBundle sharedBundle]
                                           localizedStringForKey:@"BOLD_FONTS_PICKER_OPTION_TITLE"]
                              subtitle:self.account.displayUsername]];
    } else {
        fontPicker.title =
            [[BHTBundle sharedBundle] localizedStringForKey:@"BOLD_FONTS_PICKER_OPTION_TITLE"];
    }
    [self.navigationController pushViewController:fontPicker animated:YES];
}

- (void)fontPickerViewControllerDidPickFont:(UIFontPickerViewController*)viewController {
    UIFontDescriptor* descriptor = viewController.selectedFontDescriptor;
    NSString* fontName =
        descriptor.fontAttributes[UIFontDescriptorNameAttribute];
    if (fontName.length == 0) {
        fontName = [UIFont fontWithDescriptor:descriptor size:14].fontName;
    }
    if (fontName.length == 0) {
        fontName =
            descriptor.fontAttributes[UIFontDescriptorFamilyAttribute];
    }
    NSString* fontType = BHTFontTypeForPicker(viewController);
    NSString* key = [fontType isEqualToString:@"bold"]
                        ? @"bhtwitter_font_2"
                        : @"bhtwitter_font_1";
    if (fontName.length > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:fontName
                                                  forKey:key];
    }
    Class catalog = NSClassFromString(@"XFontCatalog");
    if ([catalog respondsToSelector:@selector(resetCachedFonts)]) {
        [catalog performSelector:@selector(resetCachedFonts)];
    }
    [self updateVisibleToggles];
    [self.tableView reloadData];
    [viewController.navigationController popViewControllerAnimated:YES];
}

@end
