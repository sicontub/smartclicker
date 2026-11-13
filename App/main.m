// SmartClicker app: scenario list
#import <UIKit/UIKit.h>
#import "../Engine.h"
#import "../Shared/SCMaterial.h"
#import "Backup.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <notify.h>

#define SC_FILZA_DOCS @"/var/mobile/Documents"

static NSArray<NSArray *> *SCFindBackups(void) {
  NSArray *roots = @[ @[ SC_FILZA_DOCS, @"Documents" ], @[ [AC_DIR stringByAppendingPathComponent:@"Backups"], @"SmartClicker backups" ] ];
  NSMutableArray *out = [NSMutableArray new];
  NSMutableSet *seen = [NSMutableSet new];
  NSFileManager *fm = [NSFileManager defaultManager];
  for (NSArray *r in roots) {
    // /var -> /private/var
    NSString *root = [r[0] stringByResolvingSymlinksInPath];
    NSDirectoryEnumerator *en = [fm enumeratorAtURL:[NSURL fileURLWithPath:root] includingPropertiesForKeys:@[ NSURLContentModificationDateKey ]
                                            options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:^BOOL(NSURL *u, NSError *e) { return YES; }];
    for (NSURL *u in en) {
      if (en.level > 4) { [en skipDescendants]; continue; }
      if (![u.pathExtension.lowercaseString isEqualToString:@"zip"] || [seen containsObject:u.path]) continue;
      [seen addObject:u.path];
      NSDate *date = nil;
      [u getResourceValue:&date forKey:NSURLContentModificationDateKey error:NULL];
      NSString *dir = [u.path.stringByDeletingLastPathComponent stringByResolvingSymlinksInPath];
      NSString *rel = [dir hasPrefix:root] ? [dir substringFromIndex:root.length] : @"";
      [out addObject:@[ u.path, [r[1] stringByAppendingString:rel], date ?: [NSDate distantPast] ]];
      if (out.count >= 200) break;
    }
  }
  [out sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [b[2] compare:a[2]]; }];
  return out;
}

@interface SCScenarioCell : UITableViewCell
@property (strong) UILabel *name, *details;
@property (strong) SCTap *rename, *remove;
@property (strong) UIView *check;
@property (strong) UIImageView *tick;
- (void)setSelecting:(BOOL)selecting checked:(BOOL)checked;
@end

@implementation SCScenarioCell
- (instancetype)initWithStyle:(UITableViewCellStyle)s reuseIdentifier:(NSString *)r {
  self = [super initWithStyle:s reuseIdentifier:r];
  self.backgroundColor = [UIColor clearColor];
  UIView *sel = [UIView new];
  sel.backgroundColor = SCDyn(0x22000000, 0x22FFFFFF);
  self.selectedBackgroundView = sel;
  self.name = SCLabel(@"", 17, YES, SC_TEXT);
  self.details = SCLabel(@"", 14, NO, SC_HINT);
  self.details.font = [UIFont italicSystemFontOfSize:14];
  self.rename = [SCTap tap:nil];
  self.remove = [SCTap tap:nil];
  for (SCTap *b in @[ self.rename, self.remove ]) {
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b.widthAnchor constraintEqualToConstant:44].active = YES;
    [b.heightAnchor constraintEqualToConstant:44].active = YES;
  }
  UIImageView *ri = SCIconView(@"ic_rename", 24, nil), *di = SCIconView(@"ic_cancel", 24, nil);
  [self.rename addSubview:ri];
  [self.remove addSubview:di];
  self.check = [UIView new];
  self.check.translatesAutoresizingMaskIntoConstraints = NO;
  self.check.layer.cornerRadius = 2;
  self.check.layer.borderWidth = 2;
  self.check.userInteractionEnabled = NO;
  self.tick = SCIconView(@"ic_confirm", 18, SC_ON_PRIMARY);
  [self.check addSubview:self.tick];
  for (UIView *v in @[ self.name, self.details, self.rename, self.remove, self.check ]) [self.contentView addSubview:v];
  [NSLayoutConstraint activateConstraints:@[
    [ri.centerXAnchor constraintEqualToAnchor:self.rename.centerXAnchor], [ri.centerYAnchor constraintEqualToAnchor:self.rename.centerYAnchor],
    [di.centerXAnchor constraintEqualToAnchor:self.remove.centerXAnchor], [di.centerYAnchor constraintEqualToAnchor:self.remove.centerYAnchor],
    [self.remove.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8],
    [self.remove.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
    [self.rename.trailingAnchor constraintEqualToAnchor:self.remove.leadingAnchor],
    [self.rename.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
    [self.name.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
    [self.name.trailingAnchor constraintEqualToAnchor:self.rename.leadingAnchor constant:-8],
    [self.name.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
    [self.details.leadingAnchor constraintEqualToAnchor:self.name.leadingAnchor],
    [self.details.trailingAnchor constraintEqualToAnchor:self.name.trailingAnchor],
    [self.details.topAnchor constraintEqualToAnchor:self.name.bottomAnchor constant:2],
    [self.check.widthAnchor constraintEqualToConstant:20], [self.check.heightAnchor constraintEqualToConstant:20],
    [self.check.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
    [self.check.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
    [self.tick.centerXAnchor constraintEqualToAnchor:self.check.centerXAnchor], [self.tick.centerYAnchor constraintEqualToAnchor:self.check.centerYAnchor],
  ]];
  [self setSelecting:NO checked:NO];
  return self;
}

- (void)setSelecting:(BOOL)selecting checked:(BOOL)checked {
  self.rename.hidden = self.remove.hidden = selecting;
  self.check.hidden = !selecting;
  self.check.backgroundColor = checked ? SC_ACCENT : [UIColor clearColor];
  self.check.layer.borderColor = [(checked ? SC_ACCENT : SC_HINT) resolvedColorWithTraitCollection:self.traitCollection].CGColor;
  self.tick.hidden = !checked;
}
@end

@interface SCBackupUI : NSObject
@property (weak) SCDialog *dialog;
@property (strong) SCDialog *pending; // keeps the dialog alive until it is on screen
@property (weak) UILabel *status;
@property (weak) UIImageView *icon;
@property (weak) UIView *warn;
@end
@implementation SCBackupUI
@end

@interface SCListViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate>
@property (strong) UITableView *table;
@property (strong) UIStackView *menu, *selectMenu;
@property (strong) UIImageView *fabIcon;
@property (strong) NSMutableSet<NSString *> *checked;
@property (copy) void (^pickedFile)(NSURL *url);
@property (copy) void (^pickCancelled)(void);
@property (strong) UITextField *search;
@property (strong) UIView *searchBar;
@property (strong) NSArray<NSDictionary *> *shown;
- (void)importFile:(NSURL *)url;
@property (strong) UILabel *empty;
@property (strong) UIView *dim;
@property (strong) SCDialogHost *host;
@end

@implementation SCListViewController

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = SC_DIALOG_BG;

  UIView *status = [UIView new], *bar = [UIView new];
  status.backgroundColor = SC_PRIMARY_DARK;
  bar.backgroundColor = SC_PRIMARY;
  bar.layer.shadowColor = [UIColor blackColor].CGColor;
  bar.layer.shadowOpacity = 0.3;
  bar.layer.shadowOffset = CGSizeMake(0, 2);
  bar.layer.shadowRadius = 3;
  UILabel *title = SCLabel(@"Scenarios", 20, NO, SC_ON_PRIMARY);
  title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightMedium];
  [bar addSubview:title];
  __weak SCListViewController *ws = self;
  self.menu = [self toolbarIcons:@[ @[ @"ic_load", ^{ [ws openImport]; } ], @[ @"ic_save", ^{ [ws startSelection]; } ],
                                    @[ @"ic_search", ^{ [ws openSearch]; } ] ]];
  self.selectMenu = [self toolbarIcons:@[ @[ @"ic_cancel", ^{ [ws endSelection]; } ], @[ @"ic_select_all", ^{ [ws selectAll]; } ] ]];
  self.selectMenu.hidden = YES;
  for (UIStackView *m in @[ self.menu, self.selectMenu ]) {
    [bar addSubview:m];
    [NSLayoutConstraint activateConstraints:@[
      [m.trailingAnchor constraintEqualToAnchor:bar.safeAreaLayoutGuide.trailingAnchor constant:-4], [m.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor]
    ]];
  }
  self.searchBar = [UIView new];
  self.searchBar.backgroundColor = SC_PRIMARY;
  self.searchBar.hidden = YES;
  self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
  SCTap *back = [SCTap tap:^{ [ws closeSearch]; }];
  back.translatesAutoresizingMaskIntoConstraints = NO;
  UIImageView *bi = SCIconView(@"ic_cancel", 24, SC_ON_PRIMARY);
  [back addSubview:bi];
  self.search = SCTextField(@"", @"Search", NO);
  self.search.font = [UIFont systemFontOfSize:18];
  self.search.textColor = SC_ON_PRIMARY;
  self.search.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Search" attributes:@{NSForegroundColorAttributeName : SCRGB(0xAAFFFFFF)}];
  self.search.returnKeyType = UIReturnKeySearch;
  [self.search addAction:[UIAction actionWithHandler:^(UIAction *a) { [ws reload]; }] forControlEvents:UIControlEventEditingChanged];
  [self.searchBar addSubview:back];
  [self.searchBar addSubview:self.search];
  [bar addSubview:self.searchBar];
  [NSLayoutConstraint activateConstraints:@[
    [self.searchBar.topAnchor constraintEqualToAnchor:bar.topAnchor], [self.searchBar.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor],
    [self.searchBar.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor], [self.searchBar.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor],
    [back.leadingAnchor constraintEqualToAnchor:self.searchBar.safeAreaLayoutGuide.leadingAnchor constant:4], [back.centerYAnchor constraintEqualToAnchor:self.searchBar.centerYAnchor],
    [back.widthAnchor constraintEqualToConstant:48], [back.heightAnchor constraintEqualToConstant:48],
    [bi.centerXAnchor constraintEqualToAnchor:back.centerXAnchor], [bi.centerYAnchor constraintEqualToAnchor:back.centerYAnchor],
    [self.search.leadingAnchor constraintEqualToAnchor:back.trailingAnchor constant:8],
    [self.search.trailingAnchor constraintEqualToAnchor:self.searchBar.safeAreaLayoutGuide.trailingAnchor constant:-16],
    [self.search.centerYAnchor constraintEqualToAnchor:self.searchBar.centerYAnchor],
  ]];

  self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
  self.table.backgroundColor = [UIColor clearColor];
  self.table.separatorColor = SCDyn(0x33000000, 0x33FFFFFF);
  self.table.rowHeight = 62;
  self.table.dataSource = self;
  self.table.delegate = self;
  self.table.tableFooterView = [UIView new];
  self.table.contentInset = UIEdgeInsetsMake(0, 0, 88, 0);
  [self.table registerClass:[SCScenarioCell class] forCellReuseIdentifier:@"s"];
  self.empty = SCLabel(@"No scenario.", 17, NO, SC_TEXT);
  self.empty.textAlignment = NSTextAlignmentCenter;
  self.table.backgroundView = self.empty;

  SCTap *fab = [SCTap tap:^{ if (ws.checked) [ws openExport]; else [ws newScenario]; }];
  fab.backgroundColor = SC_PRIMARY;
  fab.layer.cornerRadius = 28;
  fab.layer.shadowColor = [UIColor blackColor].CGColor;
  fab.layer.shadowOpacity = 0.4;
  fab.layer.shadowOffset = CGSizeMake(0, 3);
  fab.layer.shadowRadius = 4;
  UIImageView *plus = SCIconView(@"ic_add", 26, SC_ON_PRIMARY);
  self.fabIcon = plus;
  [fab addSubview:plus];

  for (UIView *v in @[ self.table, status, bar, fab ]) { v.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:v]; }
  UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [status.topAnchor constraintEqualToAnchor:self.view.topAnchor], [status.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [status.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [status.bottomAnchor constraintEqualToAnchor:safe.topAnchor],
    [bar.topAnchor constraintEqualToAnchor:safe.topAnchor], [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [bar.heightAnchor constraintEqualToConstant:56],
    [title.leadingAnchor constraintEqualToAnchor:bar.safeAreaLayoutGuide.leadingAnchor constant:16], [title.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
    [self.table.topAnchor constraintEqualToAnchor:bar.bottomAnchor], [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [fab.widthAnchor constraintEqualToConstant:56], [fab.heightAnchor constraintEqualToConstant:56],
    [fab.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16], [fab.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-16],
    [plus.centerXAnchor constraintEqualToAnchor:fab.centerXAnchor], [plus.centerYAnchor constraintEqualToAnchor:fab.centerYAnchor],
  ]];

  self.dim = [[UIView alloc] initWithFrame:self.view.bounds];
  self.dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  self.dim.backgroundColor = SCRGB(0x99000000);
  self.dim.hidden = YES;
  [self.view addSubview:self.dim];
  self.host = [[SCDialogHost alloc] initWithContainer:self.dim];
  self.host.onEmpty = ^{ ws.dim.hidden = YES; };

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:UIApplicationDidBecomeActiveNotification object:nil];
  [self reload];
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  [self.host relayout];
}

- (void)reload {
  ac_load();
  NSString *q = self.searchBar.hidden ? @"" : [self.search.text.lowercaseString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  if (q.length) {
    NSMutableArray *m = [NSMutableArray new];
    for (NSDictionary *sc in ac_scenarios()) if ([[sc[@"name"] lowercaseString] containsString:q]) [m addObject:sc];
    self.shown = m;
  } else self.shown = [ac_scenarios() copy];
  self.empty.hidden = self.shown.count > 0;
  [self.table reloadData];
}

- (void)openSearch {
  [self endSelection];
  self.menu.hidden = YES;
  self.searchBar.hidden = NO;
  self.search.text = @"";
  [self.search becomeFirstResponder];
  [self reload];
}

- (void)closeSearch {
  [self.search resignFirstResponder];
  self.searchBar.hidden = YES;
  self.menu.hidden = self.checked != nil;
  [self reload];
}

- (void)push:(SCDialog *)d {
  self.dim.hidden = NO;
  [self.view bringSubviewToFront:self.dim];
  [self.host push:d];
}

- (void)newScenario {
  [self push:SCEditDialog(@"New scenario", @"", @"Name", ^(NSString *name) {
    ac_load();
    [ac_scenarios() addObject:ac_newScenario(name)];
    ac_save();
    [self reload];
  })];
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.shown.count; }

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
  SCScenarioCell *c = [t dequeueReusableCellWithIdentifier:@"s" forIndexPath:ip];
  NSDictionary *sc = self.shown[ip.row];
  NSString *sid = sc[@"id"];
  c.name.text = sc[@"name"];
  NSUInteger n = [sc[@"events"] count];
  c.details.text = [NSString stringWithFormat:@"%lu event%@", (unsigned long)n, n == 1 ? @"" : @"s"];
  [c setSelecting:self.checked != nil checked:[self.checked containsObject:sid]];
  __weak SCListViewController *ws = self;
  c.rename.action = ^{
    [ws push:SCEditDialog(@"Rename scenario", sc[@"name"], @"Name", ^(NSString *name) {
      ac_load();
      for (NSMutableDictionary *s in ac_scenarios()) if ([s[@"id"] isEqual:sid]) s[@"name"] = name;
      ac_save();
      [ws reload];
    })];
  };
  c.remove.action = ^{
    [ws push:SCConfirmDialog(@"Delete scenario", [NSString stringWithFormat:@"This will delete %@. Are you sure ?", sc[@"name"]], ^{
      ac_load();
      NSMutableArray *all = ac_scenarios();
      for (NSUInteger i = 0; i < all.count; i++) if ([all[i][@"id"] isEqual:sid]) { [all removeObjectAtIndex:i]; break; }
      ac_save();
      [ws reload];
    })];
  };
  return c;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
  [t deselectRowAtIndexPath:ip animated:YES];
  if (self.checked) {
    NSString *sid = self.shown[ip.row][@"id"];
    if ([self.checked containsObject:sid]) [self.checked removeObject:sid]; else [self.checked addObject:sid];
    [t reloadRowsAtIndexPaths:@[ ip ] withRowAnimation:UITableViewRowAnimationNone];
    return;
  }
  NSString *sid = self.shown[ip.row][@"id"];
  ac_load();
  NSArray *all = ac_scenarios();
  for (NSUInteger i = 0; i < all.count; i++) if ([all[i][@"id"] isEqual:sid]) gRoot[@"selected"] = @(i);
  ac_save();
  notify_post("com.wmhakuifan.smartclicker/show");
  // go home so the menu can be used over other apps
  UIApplication *app = [UIApplication sharedApplication];
  if ([app respondsToSelector:@selector(suspend)]) [app performSelector:@selector(suspend)];
}
#pragma mark - Toolbar

- (UIStackView *)toolbarIcons:(NSArray<NSArray *> *)items {
  NSMutableArray *views = [NSMutableArray new];
  for (NSArray *it in items) {
    SCTap *b = [SCTap tap:it[1]];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b.widthAnchor constraintEqualToConstant:48].active = YES;
    [b.heightAnchor constraintEqualToConstant:48].active = YES;
    UIImageView *iv = SCIconView(it[0], 24, SC_ON_PRIMARY);
    [b addSubview:iv];
    [iv.centerXAnchor constraintEqualToAnchor:b.centerXAnchor].active = YES;
    [iv.centerYAnchor constraintEqualToAnchor:b.centerYAnchor].active = YES;
    [views addObject:b];
  }
  UIStackView *st = [[UIStackView alloc] initWithArrangedSubviews:views];
  st.translatesAutoresizingMaskIntoConstraints = NO;
  return st;
}

#pragma mark - Export selection mode (like the Android list with checkboxes)

- (void)startSelection {
  ac_load();
  if (!ac_scenarios().count) { [self toast:@"No scenario."]; return; }
  [self closeSearch];
  self.checked = [NSMutableSet new];
  self.menu.hidden = YES;
  self.selectMenu.hidden = NO;
  self.fabIcon.image = SCIcon(@"ic_save");
  [self.table reloadData];
}

- (void)endSelection {
  self.checked = nil;
  self.menu.hidden = NO;
  self.selectMenu.hidden = YES;
  self.fabIcon.image = SCIcon(@"ic_add");
  [self.table reloadData];
}

- (void)selectAll {
  BOOL all = self.checked.count == self.shown.count;
  [self.checked removeAllObjects];
  if (!all) for (NSDictionary *sc in self.shown) [self.checked addObject:sc[@"id"]];
  [self.table reloadData];
}

- (void)toast:(NSString *)text {
  UILabel *t = SCToast(text);
  t.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:t];
  [NSLayoutConstraint activateConstraints:@[
    [t.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [t.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-96]
  ]];
  ac_after(2.0, ^{ [UIView animateWithDuration:0.3 animations:^{ t.alpha = 0; } completion:^(BOOL f) { [t removeFromSuperview]; }]; });
}

#pragma mark - Backup dialog (dialog_backup)

- (SCBackupUI *)backupDialog:(NSString *)title fileRow:(NSString *)fileText onFile:(void (^)(SCBackupUI *ui))onFile {
  SCBackupUI *ui = [SCBackupUI new];
  SCDialog *d = [[SCDialog alloc] initWithTitle:title icon:nil];
  [d.content addArrangedSubview:SCItemRow(nil, fileText, onFile != nil, ^{ if (onFile) onFile(ui); })];
  UIImageView *icon = SCIconView(nil, 62, nil);
  icon.tintColor = SC_PRIMARY;
  icon.hidden = YES;
  UILabel *status = SCLabel(@"", 16, NO, SC_TEXT);
  status.numberOfLines = 0;
  status.textAlignment = NSTextAlignmentCenter;
  status.hidden = YES;
  UIView *iconWrap = [UIView new];
  [iconWrap addSubview:icon];
  [NSLayoutConstraint activateConstraints:@[
    [icon.centerXAnchor constraintEqualToAnchor:iconWrap.centerXAnchor],
    [icon.topAnchor constraintEqualToAnchor:iconWrap.topAnchor constant:12],
    [icon.bottomAnchor constraintEqualToAnchor:iconWrap.bottomAnchor constant:-4],
  ]];
  UILabel *warn = SCLabel(@"Some of the imported scenarios have been generated from a device with a different screen and this might "
                          @"cause issues with the detection and action coordinates.\n\nPositions have been rescaled to this screen. "
                          @"If something isn't detected, take new screenshots for your conditions and update your click/swipe positions.",
                          15, NO, SC_TEXT);
  warn.numberOfLines = 0;
  warn.textAlignment = NSTextAlignmentCenter;
  UIView *warnWrap = [UIView new];
  [warnWrap addSubview:warn];
  warn.translatesAutoresizingMaskIntoConstraints = NO;
  status.translatesAutoresizingMaskIntoConstraints = NO;
  UIView *statusWrap = [UIView new];
  [statusWrap addSubview:status];
  [NSLayoutConstraint activateConstraints:@[
    [warn.leadingAnchor constraintEqualToAnchor:warnWrap.leadingAnchor constant:16], [warn.trailingAnchor constraintEqualToAnchor:warnWrap.trailingAnchor constant:-16],
    [warn.topAnchor constraintEqualToAnchor:warnWrap.topAnchor constant:8], [warn.bottomAnchor constraintEqualToAnchor:warnWrap.bottomAnchor constant:-8],
    [status.leadingAnchor constraintEqualToAnchor:statusWrap.leadingAnchor constant:16], [status.trailingAnchor constraintEqualToAnchor:statusWrap.trailingAnchor constant:-16],
    [status.topAnchor constraintEqualToAnchor:statusWrap.topAnchor constant:8], [status.bottomAnchor constraintEqualToAnchor:statusWrap.bottomAnchor constant:-8],
  ]];
  iconWrap.hidden = YES;
  statusWrap.hidden = YES;
  warnWrap.hidden = YES;
  [d.content addArrangedSubview:iconWrap];
  [d.content addArrangedSubview:statusWrap];
  [d.content addArrangedSubview:warnWrap];
  [d.content addArrangedSubview:SCSeparator()];
  ui.dialog = d;
  ui.pending = d;
  ui.status = status;
  ui.icon = icon;
  ui.warn = warnWrap;
  return ui;
}

static void SCShowStatus(SCBackupUI *ui, NSString *iconName, NSString *text) {
  ui.status.text = text;
  ui.status.hidden = ui.status.superview.hidden = NO;
  ui.icon.image = iconName ? SCIcon(iconName) : nil;
  ui.icon.tintColor = [iconName isEqualToString:@"ic_warning"] ? SCRGB(0xFFFFC107) : SC_PRIMARY;
  ui.icon.hidden = ui.icon.superview.hidden = iconName == nil;
  [ui.dialog.host relayout];
}

- (void)presentPicker:(UIDocumentPickerViewController *)p then:(void (^)(NSURL *url))done cancelled:(void (^)(void))cancelled {
  p.delegate = self;
  p.allowsMultipleSelection = NO;
  p.overrideUserInterfaceStyle = self.view.window.overrideUserInterfaceStyle;
  self.pickedFile = done;
  self.pickCancelled = cancelled;
  [self presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
  void (^done)(NSURL *) = self.pickedFile;
  self.pickedFile = nil;
  self.pickCancelled = nil;
  if (done && urls.firstObject) done(urls.firstObject);
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)c {
  void (^cancelled)(void) = self.pickCancelled;
  self.pickedFile = nil;
  self.pickCancelled = nil;
  if (cancelled) cancelled();
}

#pragma mark Import

- (void)chooseImportLocation:(SCBackupUI *)ui {
  __weak SCListViewController *ws = self;
  [self push:SCChoiceDialog(@"Where is your archive located?", nil, @[ @[ [NSNull null], @"Files App" ], @[ [NSNull null], @"Filza Documents" ] ], ^(NSInteger where) {
    if (where == 0) {
      UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeZIP ] asCopy:YES];
      [ws presentPicker:p then:^(NSURL *url) { [ws runImport:url ui:ui]; } cancelled:^{ [ws chooseImportLocation:ui]; }];
      return;
    }
    NSArray *found = SCFindBackups();
    if (!found.count) {
      SCShowStatus(ui, @"ic_warning", @"No .zip file found in /var/mobile/Documents.");
      return;
    }
    NSDateFormatter *df = [NSDateFormatter new];
    df.dateStyle = NSDateFormatterShortStyle;
    df.timeStyle = NSDateFormatterShortStyle;
    NSMutableArray *items = [NSMutableArray new];
    for (NSArray *f in found)
      [items addObject:@[ [NSNull null], [NSString stringWithFormat:@"%@\n%@ · %@", [f[0] lastPathComponent], f[1], [df stringFromDate:f[2]]] ]];
    [ws push:SCChoiceDialogCancel(@"Select backup file", nil, items, ^(NSInteger i) {
      [ws runImport:[NSURL fileURLWithPath:found[i][0]] ui:ui];
    }, ^{ [ws chooseImportLocation:ui]; })];
  })];
}

- (void)openImport {
  __weak SCListViewController *ws = self;
  SCBackupUI *ui = [self backupDialog:@"Import backup" fileRow:@"Select backup file" onFile:^(SCBackupUI *ui) { [ws chooseImportLocation:ui]; }];
  SCDialog *d = ui.dialog;
  __weak SCDialog *wd = d;
  [d addButton:@"Cancel" left:NO action:^{ [wd close]; }];
  [d addButton:@"OK" left:NO action:^{ [wd close]; }];
  [self push:d];
  ui.pending = nil;
}

- (void)importFile:(NSURL *)url {
  [self endSelection];
  [self.host popAll];
  SCBackupUI *ui = [self backupDialog:@"Import backup" fileRow:url.lastPathComponent onFile:nil];
  __weak SCDialog *wd = ui.dialog;
  [ui.dialog addButton:@"OK" left:NO action:^{ [wd close]; }];
  [self push:ui.dialog];
  ui.pending = nil;
  [self runImport:url ui:ui];
}

- (void)runImport:(NSURL *)url ui:(SCBackupUI *)ui {
  BOOL scoped = [url startAccessingSecurityScopedResource];
  NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"import-backup.zip"];
  [[NSFileManager defaultManager] removeItemAtPath:tmp error:NULL];
  BOOL copied = [[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:tmp] error:NULL];
  if (scoped) [url stopAccessingSecurityScopedResource];
  ui.warn.hidden = YES;
  SCShowStatus(ui, nil, @"Importing backup…");
  if (!copied) tmp = url.path;
  __weak SCListViewController *ws = self;
  ac_after(0.05, ^{
    ac_load();
    ACImportResult r;
    BOOL ok = ac_importBackup(tmp, &r, nil);
    if (r.imported) {
      gRoot[@"backupScreen"] = @[ @(r.screen.width), @(r.screen.height) ];
      ac_save();
    }
    [[NSFileManager defaultManager] removeItemAtPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"import-backup.zip"] error:NULL];
    [ws reload];
    if (!ok || (!r.imported && r.failed)) {
      SCShowStatus(ui, @"ic_warning", @"An error has occurred and the backup import has been cancelled");
    } else {
      NSMutableString *t = [NSMutableString stringWithFormat:@"Import completed\n%ld scenario%@ imported", (long)r.imported, r.imported == 1 ? @"" : @"s"];
      if (r.failed) [t appendFormat:@"\n%ld scenario%@ couldn't be read", (long)r.failed, r.failed == 1 ? @"" : @"s"];
      if (r.skippedActions) [t appendFormat:@"\n%ld Intent action%@ skipped (not available on iOS)", (long)r.skippedActions, r.skippedActions == 1 ? @"" : @"s"];
      ui.warn.hidden = !r.otherScreen;
      SCShowStatus(ui, r.failed ? @"ic_warning" : @"ic_confirm", t);
    }
  });
}

#pragma mark Export

- (CGSize)exportScreen {
  NSArray *s = gRoot[@"exportScreen"] ?: gRoot[@"backupScreen"];
  if ([s isKindOfClass:[NSArray class]] && s.count == 2 && [s[0] doubleValue] > 0 && [s[1] doubleValue] > 0)
    return CGSizeMake([s[0] doubleValue], [s[1] doubleValue]);
  return [UIScreen mainScreen].nativeBounds.size;
}

- (void)openExport {
  if (!self.checked.count) { [self toast:@"Select the scenarios to export"]; return; }
  ac_load();
  NSMutableArray *list = [NSMutableArray new];
  for (NSDictionary *sc in ac_scenarios()) if ([self.checked containsObject:sc[@"id"]]) [list addObject:sc];
  __weak SCListViewController *ws = self;
  SCBackupUI *ui = [self backupDialog:@"Create backup" fileRow:@"Select output folder" onFile:^(SCBackupUI *ui) {
    [ws chooseExportLocation:list ui:ui];
  }];
  SCDialog *d = ui.dialog;
  // android doesn't rescale backups
  CGSize scr = [self exportScreen];
  SCTap *size = SCItemRow(nil, @"", YES, nil);
  UILabel *sizeLabel = [size viewWithTag:1];
  void (^showSize)(CGSize) = ^(CGSize s) {
    sizeLabel.text = [NSString stringWithFormat:@"Target screen: %d × %d px%@", (int)s.width, (int)s.height,
                      CGSizeEqualToSize(s, [UIScreen mainScreen].nativeBounds.size) ? @" (this iPhone)" : @""];
  };
  showSize(scr);
  size.action = ^{
    CGSize cur = [ws exportScreen];
    [ws push:SCEditDialog(@"Target screen (portrait px)", [NSString stringWithFormat:@"%dx%d", (int)cur.width, (int)cur.height], @"e.g. 1080x2400",
                          ^(NSString *text) {
      NSArray *parts = [[text lowercaseString] componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"x× ,*"]];
      NSMutableArray *nums = [NSMutableArray new];
      for (NSString *p in parts) if (p.intValue > 0) [nums addObject:@(p.intValue)];
      if (nums.count != 2) { [ws toast:@"Use width x height, e.g. 1080x2400"]; return; }
      CGSize s = CGSizeMake(MIN([nums[0] intValue], [nums[1] intValue]), MAX([nums[0] intValue], [nums[1] intValue]));
      ac_load();
      gRoot[@"exportScreen"] = @[ @(s.width), @(s.height) ];
      ac_save();
      showSize(s);
    })];
  };
  [d.content insertArrangedSubview:size atIndex:0];
  UILabel *hint = SCLabel(@"Set this to the Android phone's screen resolution so positions line up there.", 13, NO, SC_HINT);
  hint.numberOfLines = 0;
  hint.translatesAutoresizingMaskIntoConstraints = NO;
  UIView *hw = [UIView new];
  [hw addSubview:hint];
  [NSLayoutConstraint activateConstraints:@[
    [hint.leadingAnchor constraintEqualToAnchor:hw.leadingAnchor constant:16], [hint.trailingAnchor constraintEqualToAnchor:hw.trailingAnchor constant:-16],
    [hint.topAnchor constraintEqualToAnchor:hw.topAnchor], [hint.bottomAnchor constraintEqualToAnchor:hw.bottomAnchor constant:-4],
  ]];
  [d.content insertArrangedSubview:hw atIndex:1];
  [d.content insertArrangedSubview:SCSeparator() atIndex:2];
  __weak SCDialog *wd = d;
  [d addButton:@"Cancel" left:NO action:^{ [wd close]; }];
  [d addButton:@"OK" left:NO action:^{ [wd close]; [ws endSelection]; }];
  [self push:d];
  ui.pending = nil;
}

- (void)chooseExportLocation:(NSArray *)list ui:(SCBackupUI *)ui {
  __weak SCListViewController *ws = self;
  [self push:SCChoiceDialog(@"Where should the archive be saved?", nil, @[ @[ [NSNull null], @"Files App" ], @[ [NSNull null], @"Filza Documents" ] ], ^(NSInteger where) {
    [ws runExport:list ui:ui filza:where == 1];
  })];
}

- (void)runExport:(NSArray *)list ui:(SCBackupUI *)ui filza:(BOOL)filza {
  SCShowStatus(ui, nil, [NSString stringWithFormat:@"Creating backup: 0/%lu", (unsigned long)list.count]);
  CGSize scr = [self exportScreen];
  __weak SCListViewController *ws = self;
  ac_after(0.05, ^{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDateFormatter *df = [NSDateFormatter new];
    df.dateFormat = @"yyyy-MM-dd-HHmmss";
    NSString *name = [NSString stringWithFormat:@"SmartAutoClicker-Backup-%@.zip", [df stringFromDate:[NSDate date]]];
    NSString *dir, *where;
    if (filza) {
      dir = [SC_FILZA_DOCS stringByAppendingPathComponent:@"SmartClicker"];
      where = @"/var/mobile/Documents/SmartClicker";
      [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
      if (![fm isWritableFileAtPath:dir]) {
        dir = [AC_DIR stringByAppendingPathComponent:@"Backups"];
        where = dir;
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
      }
    } else {
      dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"export"];
      [fm removeItemAtPath:dir error:NULL];
      [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    NSString *path = [dir stringByAppendingPathComponent:name];
    NSInteger skipped = 0, apps = 0;
    BOOL ok = ac_exportBackup(list, scr, path, &skipped, &apps, nil);
    if (!ok) { SCShowStatus(ui, @"ic_warning", @"An error has occurred and the backup export has been cancelled"); return; }
    NSString *done = [NSString stringWithFormat:@"Backup completed\n%lu scenario%@ exported", (unsigned long)list.count, list.count == 1 ? @"" : @"s"];
    if (skipped) done = [done stringByAppendingFormat:@"\n%ld event%@ without a condition or action left out (Android needs both)",
                                                     (long)skipped, skipped == 1 ? @"" : @"s"];
    if (apps) done = [done stringByAppendingFormat:@"\n%ld Open app action%@ left out (not available on Android)", (long)apps, apps == 1 ? @"" : @"s"];
    NSString *icon = skipped || apps ? @"ic_warning" : @"ic_confirm";
    if (filza) {
      SCShowStatus(ui, icon, [done stringByAppendingFormat:@"\n\nSaved as %@ in %@", name, where]);
      return;
    }
    SCShowStatus(ui, nil, @"Choose where to save the backup…");
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[ [NSURL fileURLWithPath:path] ] asCopy:YES];
    [ws presentPicker:p then:^(NSURL *url) {
      [fm removeItemAtPath:dir error:NULL];
      SCShowStatus(ui, icon, [done stringByAppendingFormat:@"\n\nSaved as %@", url.lastPathComponent ?: name]);
    } cancelled:^{
      [fm removeItemAtPath:dir error:NULL];
      ui.status.superview.hidden = ui.icon.superview.hidden = YES;
      [ui.dialog.host relayout];
      [ws chooseExportLocation:list ui:ui];
    }];
  });
}

@end

@interface SCAppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation SCAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
  self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
  self.window.rootViewController = [SCListViewController new];
  self.window.overrideUserInterfaceStyle = SCSystemStyle();
  [self.window makeKeyAndVisible];
  return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
  UIUserInterfaceStyle st = SCSystemStyle();
  if (self.window.overrideUserInterfaceStyle != st) self.window.overrideUserInterfaceStyle = st;
}

// "Open in SmartClicker" for .zip backups
- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary *)options {
  SCListViewController *vc = (SCListViewController *)self.window.rootViewController;
  if (![vc isKindOfClass:[SCListViewController class]] || !url.isFileURL) return NO;
  [vc importFile:url];
  return YES;
}
@end

int main(int argc, char *argv[]) {
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([SCAppDelegate class]));
  }
}
