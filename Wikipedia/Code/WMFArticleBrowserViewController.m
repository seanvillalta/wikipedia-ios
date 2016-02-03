
#import "WMFArticleBrowserViewController.h"
#import "UIColor+WMFHexColor.h"
#import "Wikipedia-Swift.h"

#import "MWKDataStore.h"
#import "MWKUserDataStore.h"
#import "MWKLanguageLinkController.h"

#import "MWKTitle.h"
#import "MWKHistoryList.h"
#import "MWKHistoryEntry.h"
#import "MWKLanguageLink.h"

#import <Masonry/Masonry.h>
#import <BlocksKit/BlocksKit+UIKit.h>

#import "UIViewController+WMFSearch.h"
#import "WMFSaveButtonController.h"
#import "UIViewController+WMFStoryboardUtilities.h"
#import "UIBarButtonItem+WMFButtonConvenience.h"
#import "PiwikTracker+WMFExtensions.h"
#import "WMFShareOptionsController.h"
#import "WMFShareFunnel.h"

#import "WMFArticleViewController.h"
#import "LanguagesViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface WMFNavigationController : UINavigationController

@end

@implementation WMFNavigationController

- (UIStatusBarStyle)preferredStatusBarStyle{
    return UIStatusBarStyleLightContent;
}

@end

@interface WMFArticleBrowserViewController ()<UINavigationControllerDelegate, WMFArticleViewControllerDelegate, LanguageSelectionDelegate>

@property (nonatomic, strong, readwrite) UINavigationController* internalNavigationController;
@property (nonatomic, strong) NSMutableArray<MWKTitle*>* navigationTitleStack;
@property (nonatomic, assign) NSUInteger currentIndex;
@property (nonatomic, strong) WMFArticleViewController* currentViewController;

@property (nonatomic, strong, nullable) WMFArticleViewController* initialViewController;
@property (nonatomic, strong, nullable) id<WMFAnalyticsLogging> initialViewControllerSource;

@property (strong, nonatomic) UIProgressView* progressView;

@property (nonatomic, strong) UIBarButtonItem* refreshToolbarItem;
@property (nonatomic, strong) UIBarButtonItem* backToolbarItem;
@property (nonatomic, strong) UIBarButtonItem* forwardToolbarItem;
@property (nonatomic, strong) UIBarButtonItem* saveToolbarItem;
@property (nonatomic, strong) UIBarButtonItem* languagesToolbarItem;
@property (nonatomic, strong) UIBarButtonItem* shareToolbarItem;
@property (nonatomic, strong) UIBarButtonItem* tableOfContentsToolbarItem;

@property (nonatomic, strong) WMFSaveButtonController* saveButtonController;

@property (strong, nonatomic, nullable) WMFShareOptionsController* shareOptionsController;

@end

@implementation WMFArticleBrowserViewController

- (instancetype)initWithDataStore:(MWKDataStore*)dataStore {
    NSParameterAssert(dataStore);
    self = [super init];
    if (self) {
        self.dataStore = dataStore;
    }
    return self;
}

+ (UINavigationController*)embeddedBrowserViewControllerWithDataStore:(MWKDataStore*)dataStore {
    NSParameterAssert(dataStore);
    WMFArticleBrowserViewController* vc = [[WMFArticleBrowserViewController alloc] initWithDataStore:dataStore];
    return [[WMFNavigationController alloc] initWithRootViewController:vc];
}

+ (UINavigationController*)embeddedBrowserViewControllerWithDataStore:(MWKDataStore*)dataStore articleTitle:(MWKTitle*)title restoreScrollPosition:(BOOL)restoreScrollPosition source:(nullable id<WMFAnalyticsLogging>)source {
    WMFArticleViewController* vc = [[WMFArticleViewController alloc] initWithArticleTitle:title dataStore:dataStore];
    vc.restoreScrollPositionOnArticleLoad = restoreScrollPosition;
    return [self embeddedBrowserViewControllerWithArticleViewController:vc source:source];
}

+ (UINavigationController*)embeddedBrowserViewControllerWithArticleViewController:(WMFArticleViewController*)viewController source:(nullable id<WMFAnalyticsLogging>)source {
    NSParameterAssert(viewController);
    WMFArticleBrowserViewController* vc = [[WMFArticleBrowserViewController alloc] initWithDataStore:viewController.dataStore];
    WMFNavigationController* nav = [[WMFNavigationController alloc] initWithRootViewController:vc];
    [vc pushArticleViewController:viewController source:source animated:NO];
    return nav;
}

#pragma mark - Accessors

- (UIProgressView*)progressView {
    if (!_progressView) {
        UIProgressView* progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
        progress.translatesAutoresizingMaskIntoConstraints = NO;
        progress.trackTintColor                            = [UIColor clearColor];
        progress.tintColor                                 = [UIColor wmf_blueTintColor];
        _progressView                                      = progress;
    }

    return _progressView;
}

- (UIBarButtonItem*)tableOfContentsToolbarItem {
    if (!_tableOfContentsToolbarItem) {
        _tableOfContentsToolbarItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"toc"]
                                                                       style:UIBarButtonItemStylePlain
                                                                      target:self
                                                                      action:@selector(showTableOfContents)];
        _tableOfContentsToolbarItem.accessibilityLabel = MWLocalizedString(@"table-of-contents-button-label", nil);
        return _tableOfContentsToolbarItem;
    }
    return _tableOfContentsToolbarItem;
}

- (UIBarButtonItem*)saveToolbarItem {
    if (!_saveToolbarItem) {
        _saveToolbarItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"save"] style:UIBarButtonItemStylePlain target:nil action:nil];
    }
    return _saveToolbarItem;
}

- (UIBarButtonItem*)refreshToolbarItem {
    if (!_refreshToolbarItem) {
        _refreshToolbarItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"refresh"]
                                                               style:UIBarButtonItemStylePlain
                                                              target:self
                                                              action:@selector(fetchArticleIfNeeded)];
    }
    return _refreshToolbarItem;
}

- (UIBarButtonItem*)backToolbarItem {
    if (!_backToolbarItem) {
        _backToolbarItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"chevron-left"]
                                                            style:UIBarButtonItemStylePlain
                                                           target:self
                                                           action:@selector(navigateBack)];
    }
    return _backToolbarItem;
}

- (UIBarButtonItem*)forwardToolbarItem {
    if (!_forwardToolbarItem) {
        _forwardToolbarItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"chevron-right"]
                                                               style:UIBarButtonItemStylePlain
                                                              target:self
                                                              action:@selector(navigateForward)];
    }
    return _forwardToolbarItem;
}

- (UIBarButtonItem*)flexibleSpaceToolbarItem {
    return [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                         target:nil
                                                         action:NULL];
}

- (UIBarButtonItem*)shareToolbarItem {
    if (!_shareToolbarItem) {
        _shareToolbarItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(showShareSheet)];
    }
    return _shareToolbarItem;
}

- (UIBarButtonItem*)languagesToolbarItem {
    if (!_languagesToolbarItem) {
        _languagesToolbarItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"language"]
                                                                 style:UIBarButtonItemStylePlain
                                                                target:self
                                                                action:@selector(showLanguagePicker)];
    }
    return _languagesToolbarItem;
}

- (nullable WMFShareOptionsController*)shareOptionsController {
    NSParameterAssert([[self currentArticleViewController] article]);
    if (![[self currentArticleViewController] article]) {
        return nil;
    }
    if (!_shareOptionsController) {
        _shareOptionsController = [[WMFShareOptionsController alloc] initWithArticle:[[self currentArticleViewController] article]
                                                                         shareFunnel:[[self currentArticleViewController] shareFunnel]];
    }
    return _shareOptionsController;
}

- (UINavigationController*)internalNavigationController {
    if (!_internalNavigationController) {
        UINavigationController* nav = [[UINavigationController alloc] init];
        nav.navigationBarHidden = YES;
        nav.toolbarHidden       = YES;
        [self.view addSubview:nav.view];
        [nav.view mas_makeConstraints:^(MASConstraintMaker* make) {
            make.leading.and.trailing.and.top.and.bottom.equalTo(self.view);
        }];
        nav.delegate                  = self;
        _internalNavigationController = nav;
    }
    return _internalNavigationController;
}

- (WMFArticleViewController*)currentArticleViewController {
    return (WMFArticleViewController*)self.internalNavigationController.topViewController;
}

#pragma mark - UIViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.edgesForExtendedLayout = UIRectEdgeTop;

    self.navigationController.navigationBar.barTintColor = [UIColor blackColor];
    self.navigationController.navigationBar.translucent  = YES;
    self.navigationController.navigationBar.tintColor    = [UIColor whiteColor];
    self.navigationController.toolbarHidden              = NO;

    @weakify(self);
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] bk_initWithImage:[UIImage imageNamed:@"close"] style:UIBarButtonItemStylePlain handler:^(id sender) {
        @strongify(self);
        [self.navigationController dismissViewControllerAnimated:YES completion:NULL];
    }];
    self.navigationItem.rightBarButtonItem = [self wmf_searchBarButtonItem];

    UIImage* w = [UIImage imageNamed:@"W"];
    self.navigationItem.titleView           = [[UIImageView alloc] initWithImage:w];
    self.navigationItem.titleView.tintColor = [UIColor wmf_readerWGray];

    [self addProgressView];
    self.navigationTitleStack = [NSMutableArray array];

    if (self.initialViewController) {
        [self pushArticleViewController:self.initialViewController source:self.initialViewControllerSource animated:NO];
        self.initialViewController       = nil;
        self.initialViewControllerSource = nil;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSParameterAssert(self.navigationController);
}

- (void)viewWillDisappear:(BOOL)animated{
    [super viewWillDisappear:animated];
}

- (void)viewWillLayoutSubviews{
    [super viewWillLayoutSubviews];
    UIEdgeInsets insets = UIEdgeInsetsMake(self.navigationController.navigationBar.frame.size.height, 0.0, self.navigationController.toolbar.frame.size.height, 0.0);
    [[self.internalNavigationController viewControllers] enumerateObjectsUsingBlock:^(__kindof WMFArticleViewController * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        obj.contentInsets = insets;
    }];
}

//- (BOOL)discoveryMethodRequiresScrollPositionRestore {
//    if (self.discoveryMethod == MWKHistoryDiscoveryMethodSaved ||
//        self.discoveryMethod == MWKHistoryDiscoveryMethodBackForward ||
//        self.discoveryMethod == MWKHistoryDiscoveryMethodReloadFromNetwork ||
//        self.discoveryMethod == MWKHistoryDiscoveryMethodReloadFromCache) {
//        return YES;
//    }
//    return NO;
//}

#pragma mark - Navigation

- (void)pushArticleWithTitle:(MWKTitle*)title restoreScrollPosition:(BOOL)restoreScrollPosition source:(nullable id<WMFAnalyticsLogging>)source animated:(BOOL)animated {
    WMFArticleViewController* articleViewController =
        [[WMFArticleViewController alloc] initWithArticleTitle:title
                                                     dataStore:self.dataStore];
    [self pushArticleViewController:articleViewController source:source animated:animated];
}

- (void)pushArticleWithTitle:(MWKTitle*)title source:(nullable id<WMFAnalyticsLogging>)source animated:(BOOL)animated {
    [self pushArticleWithTitle:title restoreScrollPosition:NO source:source animated:animated];
}

- (void)pushArticleViewController:(WMFArticleViewController*)viewController source:(nullable id<WMFAnalyticsLogging>)source animated:(BOOL)animated {
    NSParameterAssert(self.navigationController);
    [[PiwikTracker sharedInstance] wmf_logView:viewController fromSource:source];
    [self.internalNavigationController pushViewController:viewController animated:animated];
}

- (void)navigateBack {
    NSUInteger previousIndex = [self previousIndex];
    NSParameterAssert(previousIndex != NSNotFound);
    if (previousIndex == NSNotFound) {
        return;
    }
    self.currentViewController = [self.internalNavigationController viewControllers][previousIndex];
    self.currentIndex          = previousIndex;
    [self.internalNavigationController popViewControllerAnimated:YES];
}

- (void)navigateForward {
    NSUInteger nextIndex = [self nextIndex];
    NSParameterAssert(nextIndex != NSNotFound);
    if (nextIndex == NSNotFound) {
        return;
    }
    WMFArticleViewController* articleViewController =
        [[WMFArticleViewController alloc] initWithArticleTitle:self.navigationTitleStack[nextIndex]
                                                     dataStore:self.dataStore];
    articleViewController.restoreScrollPositionOnArticleLoad = YES;
    self.currentViewController                               = articleViewController;
    self.currentIndex                                        = nextIndex;
    [self pushArticleViewController:articleViewController source:nil animated:YES];
}

- (NSUInteger)previousIndex {
    if (self.currentIndex == 0 || self.currentIndex == NSNotFound) {
        return NSNotFound;
    }
    return self.currentIndex - 1;
}

- (NSUInteger)nextIndex {
    if (self.currentIndex + 1 > [self.navigationTitleStack count] - 1) {
        return NSNotFound;
    }
    return self.currentIndex + 1;
}

#pragma mark - Progress

- (void)addProgressView {
    NSAssert(!self.progressView.superview, @"Illegal attempt to re-add progress view.");
    [self.view addSubview:self.progressView];
    [self.progressView mas_makeConstraints:^(MASConstraintMaker* make) {
        make.top.equalTo(self.progressView.superview.mas_top);
        make.left.equalTo(self.progressView.superview.mas_left);
        make.right.equalTo(self.progressView.superview.mas_right);
        make.height.equalTo(@2.0);
    }];
}

#pragma mark - Toolbar Setup

- (void)setupToolbar {
    [self updateToolbarItemsIfNeeded];
    [self updateToolbarItemEnabledState];
}

- (void)updateToolbarItemsIfNeeded {
    if (!self.saveButtonController) {
        self.saveButtonController = [[WMFSaveButtonController alloc] initWithBarButtonItem:self.saveToolbarItem savedPageList:self.dataStore.userDataStore.savedPageList title:[[self currentArticleViewController] articleTitle]];
    } else {
        self.saveButtonController.title = [[self currentArticleViewController] articleTitle];
    }

    NSArray<UIBarButtonItem*>* toolbarItems =
        [NSArray arrayWithObjects:
         self.backToolbarItem, [UIBarButtonItem wmf_barButtonItemOfFixedWidth:36.0],
         self.forwardToolbarItem, [self flexibleSpaceToolbarItem],
         self.shareToolbarItem, [UIBarButtonItem wmf_barButtonItemOfFixedWidth:24.f],
         self.saveToolbarItem, [UIBarButtonItem wmf_barButtonItemOfFixedWidth:18.f],
         self.languagesToolbarItem, [UIBarButtonItem wmf_barButtonItemOfFixedWidth:24.0],
         self.tableOfContentsToolbarItem,
         nil];

    if (self.toolbarItems.count != toolbarItems.count) {
        // HAX: only update toolbar if # of items has changed, otherwise items will (somehow) get lost
        [self setToolbarItems:toolbarItems animated:YES];
    }
}

- (void)updateToolbarItemEnabledState {
    self.backToolbarItem.enabled            = [self previousIndex] != NSNotFound;
    self.forwardToolbarItem.enabled         = [self nextIndex] != NSNotFound;
    self.refreshToolbarItem.enabled         = [[self currentArticleViewController] canRefresh];
    self.shareToolbarItem.enabled           = [[self currentArticleViewController] canShare];
    self.languagesToolbarItem.enabled       = [[self currentArticleViewController] hasLanguages];
    self.tableOfContentsToolbarItem.enabled = [[self currentArticleViewController] hasTableOfContents];
}

#pragma mark - Reload

- (void)fetchArticleIfNeeded {
    [[self currentArticleViewController] fetchArticleIfNeeded];
}

#pragma mark - ToC

- (void)showTableOfContents {
    [[self currentArticleViewController] showTableOfContents];
}

#pragma mark - Share

- (void)showShareSheet {
    [self showShareSheetFrombarButtonItem:self.shareToolbarItem];
}

- (void)showShareSheetFrombarButtonItem:(nullable UIBarButtonItem*)item {
    NSString* text = [[self currentArticleViewController] shareText];
    [[[self currentArticleViewController] shareFunnel] logShareButtonTappedResultingInSelection:text];
    [self.shareOptionsController presentShareOptionsWithSnippet:text inViewController:self fromBarButtonItem:item];
}

#pragma mark - Languages

- (void)showLanguagePicker {
    LanguagesViewController* languagesVC = [LanguagesViewController wmf_initialViewControllerFromClassStoryboard];
    languagesVC.articleTitle              = [[self currentArticleViewController] articleTitle];
    languagesVC.languageSelectionDelegate = self;
    [self.navigationController presentViewController:[[UINavigationController alloc] initWithRootViewController:languagesVC] animated:YES completion:nil];
}

- (void)languagesController:(LanguagesViewController*)controller didSelectLanguage:(MWKLanguageLink*)language {
    [[MWKLanguageLinkController sharedInstance] addPreferredLanguage:language];
    [self dismissViewControllerAnimated:YES completion:^{
        WMFArticleViewController* vc = [[WMFArticleViewController alloc] initWithArticleTitle:language.title dataStore:self.dataStore];
        [self.internalNavigationController pushViewController:vc animated:YES];
    }];
}

#pragma mark - WMFArticleViewControllerDelegate

- (void)articleControllerDidTapShareSelectedText:(WMFArticleViewController*)controller {
    [self showShareSheetFrombarButtonItem:nil];
}

- (void)articleControllerDidLoadArticle:(WMFArticleViewController*)controller {
    [self setupToolbar];
}

#pragma mark - UINavigationControllerDelegate

- (void)navigationController:(UINavigationController*)navigationController willShowViewController:(UIViewController*)viewController animated:(BOOL)animated {
    [[self currentArticleViewController] setDelegate:nil];
    [[self currentArticleViewController] setProgressView:nil];
}

- (void)navigationController:(UINavigationController*)navigationController didShowViewController:(UIViewController*)viewController animated:(BOOL)animated {
    if (self.currentViewController != viewController) {
        //unknown view controller being displayed
        //rebuild the navigation stack
        self.navigationTitleStack = [[[self.internalNavigationController viewControllers] bk_map:^id (WMFArticleViewController* obj) {
            return obj.articleTitle;
        }] mutableCopy];
        self.currentViewController = (WMFArticleViewController*)viewController;
        self.currentIndex          = [[navigationController viewControllers] count] - 1;
    }

    [self setupToolbar];

    self.shareOptionsController = nil;
    WMFArticleViewController* vc = (WMFArticleViewController*)viewController;
    [vc setDelegate:self];
    [vc setProgressView:self.progressView];
    //Delay this so any visual updates to lists are postponed until the article after the article is displayed
    //Some lists (like history) will show these artifacts as the push navigation is occuring.
    dispatchOnMainQueueAfterDelayInSeconds(0.5, ^{
        MWKHistoryList* historyList = vc.dataStore.userDataStore.historyList;
        [historyList addPageToHistoryWithTitle:vc.articleTitle];
        [historyList save];
    });
}

@end



NS_ASSUME_NONNULL_END