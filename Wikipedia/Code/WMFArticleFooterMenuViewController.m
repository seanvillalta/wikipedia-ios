#import "WMFArticleFooterMenuViewController.h"
#import "WMFIntrinsicSizeTableView.h"
#import "MWKArticle.h"
#import <SSDataSources/SSDataSources.h>
#import "WMFArticleListTableViewController.h"
#import "WMFArticlePreviewFetcher.h"
#import "WMFArticleFooterMenuItem.h"
#import "UIViewController+WMFStoryboardUtilities.h"
#import "PageHistoryViewController.h"
#import "LanguagesViewController.h"
#import "MWKLanguageLinkController.h"
#import "MWKLanguageLink.h"
#import "UIViewController+WMFArticlePresentation.h"
#import "WMFDisambiguationPagesViewController.h"
#import "WMFPageIssuesViewController.h"
#import "WMFArticleFooterMenuDataSource.h"
#import "WMFArticleFooterMenuCell.h"
#import "UIView+WMFDefaultNib.h"
#import "UINavigationController+WMFHideEmptyToolbar.h"

NS_ASSUME_NONNULL_BEGIN

@interface WMFArticleFooterMenuViewController () <UITableViewDelegate, LanguageSelectionDelegate, UINavigationControllerDelegate>

@property (nonatomic, strong, readwrite) MWKArticle* article;

@property (nonatomic, strong) SSArrayDataSource* footerDataSource;

@property (nonatomic, strong) IBOutlet WMFIntrinsicSizeTableView* tableView;

@end

@implementation WMFArticleFooterMenuViewController

- (instancetype)initWithArticle:(MWKArticle*)article {
    self = [super init];
    if (self) {
        self.article = article;
    }
    return self;
}

#pragma mark - Accessors

- (MWKDataStore*)dataStore {
    return self.article.dataStore;
}

#pragma mark - UIViewController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
}

- (CGFloat)tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section {
    // HAX: collapses space between grouped table sections
    return 0.00001;
}

- (CGFloat)tableView:(UITableView*)tableView heightForFooterInSection:(NSInteger)section {
    // HAX: collapses space between grouped table sections
    return 0.00001;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self.tableView registerNib:[WMFArticleFooterMenuCell wmf_classNib] forCellReuseIdentifier:[WMFArticleFooterMenuCell identifier]];

    NSAssert(self.tableView.style == UITableViewStyleGrouped, @"Use grouped UITableView layout so we get separator above first cell and below last cell without having to implement any special logic");

    _footerDataSource               = [[WMFArticleFooterMenuDataSource alloc] initWithArticle:self.article];
    self.footerDataSource.tableView = self.tableView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    // HAX: (sorta) setting self.tableView.rowHeight = UITableViewAutomaticDimension was causing some strange constraint breakage. Using "tableView:heightForRowAtIndexPath:" for fixed height of 60 works fine for now.
    return 60;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    switch ([(WMFArticleFooterMenuItem*)[self.footerDataSource itemAtIndexPath:indexPath] type]) {
        case WMFArticleFooterMenuItemTypeLanguages:
            [self showLanguages];
            break;
        case WMFArticleFooterMenuItemTypeLastEdited:
            [self showEditHistory];
            break;
        case WMFArticleFooterMenuItemTypePageIssues:
            [self showPageIssues];
            break;
        case WMFArticleFooterMenuItemTypeDisambiguation:
            [self showDisambiguationItems];
            break;
    }
}

#pragma mark - Subview Actions

- (void)showDisambiguationItems {
    WMFDisambiguationPagesViewController* articleListVC = [[WMFDisambiguationPagesViewController alloc] initWithArticle:self.article dataStore:self.dataStore];
    articleListVC.title = MWLocalizedString(@"page-similar-titles", nil);
    UINavigationController* navController = [[UINavigationController alloc] initWithRootViewController:articleListVC];
    navController.delegate = self;
    [self presentViewController:navController animated:YES completion:nil];
}

- (void)navigationController:(UINavigationController*)navigationController
      willShowViewController:(UIViewController*)viewController
                    animated:(BOOL)animated {
    [navigationController wmf_hideToolbarIfViewControllerHasNoToolbarItems:viewController];
}

- (void)showEditHistory {
    PageHistoryViewController* editHistoryVC = [PageHistoryViewController wmf_initialViewControllerFromClassStoryboard];
    editHistoryVC.article = self.article;
    [self presentViewController:[[UINavigationController alloc] initWithRootViewController:editHistoryVC] animated:YES completion:nil];
}

- (void)showLanguages {
    LanguagesViewController* languagesVC = [LanguagesViewController wmf_initialViewControllerFromClassStoryboard];
    languagesVC.articleTitle              = self.article.title;
    languagesVC.languageSelectionDelegate = self;
    [self presentViewController:[[UINavigationController alloc] initWithRootViewController:languagesVC] animated:YES completion:nil];
}

- (void)languagesController:(LanguagesViewController*)controller didSelectLanguage:(MWKLanguageLink*)language {
    [[MWKLanguageLinkController sharedInstance] addPreferredLanguage:language];
    [self dismissViewControllerAnimated:YES completion:^{
        [self wmf_pushArticleViewControllerWithTitle:language.title discoveryMethod:MWKHistoryDiscoveryMethodLink dataStore:self.dataStore];
    }];
}

- (void)showPageIssues {
    WMFPageIssuesViewController* issuesVC = [[WMFPageIssuesViewController alloc] initWithStyle:UITableViewStyleGrouped];
    issuesVC.dataSource = [[SSArrayDataSource alloc] initWithItems:self.article.pageIssues];
    [self presentViewController:[[UINavigationController alloc] initWithRootViewController:issuesVC] animated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END
