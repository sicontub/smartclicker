// small Material-style UI kit for the overlay and the app
#pragma once
#import <UIKit/UIKit.h>

UIColor *SCRGB(uint32_t argb);
#define SC_PRIMARY SCRGB(0xFF4CAF50)
#define SC_PRIMARY_DARK SCRGB(0xFF388E3C)
#define SC_ACCENT SCRGB(0xFF448AFF)
// light / dark versions, follow the system appearance
UIColor *SCDyn(uint32_t light, uint32_t dark);
// the phone's real light/dark setting (our windows don't always inherit it)
UIUserInterfaceStyle SCSystemStyle(void);
#define SC_DIALOG_BG SCDyn(0xFFFAFAFA, 0xFF303030)
#define SC_CARD_BG SCDyn(0xFFFFFFFF, 0xFF424242)
#define SC_LIST_BG SCDyn(0xFFEAEAEA, 0xFF212121)
#define SC_TEXT SCDyn(0xDE000000, 0xFFFFFFFF)
#define SC_HINT SCDyn(0x8A000000, 0x88FFFFFF)
#define SC_ON_PRIMARY [UIColor whiteColor]
#define SC_OVERLAY_BG SCRGB(0x77000000)

UIImage *SCIcon(NSString *name);

typedef void (^SCAction)(void);

@interface SCTap : UIControl
@property (copy) SCAction action;
+ (instancetype)tap:(SCAction)action;
@end

UIImageView *SCIconView(NSString *name, CGFloat size, UIColor *tint);
UILabel *SCLabel(NSString *text, CGFloat size, BOOL bold, UIColor *color);
UITextField *SCTextField(NSString *text, NSString *hint, BOOL numeric);
UIView *SCCard(NSString *header, NSArray<UIView *> *rows);
// 48pt row, label has tag 1
SCTap *SCItemRow(NSString *icon, NSString *text, BOOL chevron, SCAction tap);
UIView *SCHorizontalList(NSArray<UIView *> *cards);
// long-press to reorder the first `movable` cards
UIView *SCReorderableList(NSArray<UIView *> *cards, NSUInteger movable, void (^onMove)(NSUInteger from, NSUInteger to));
UIView *SCCardShell(void);
UIView *SCNewCopyCard(SCAction add, SCAction copy);
UIView *SCActionCard(NSString *icon, NSString *name, SCAction tap);
UIView *SCConditionCard(UIImage *image, BOOL detect, BOOL whole, SCAction tap);
UIView *SCEndConditionCard(NSString *name, NSInteger executions, SCAction tap);
UIView *SCSeparator(void);

@class SCDialogHost;
@interface SCDialog : UIView
- (instancetype)initWithTitle:(NSString *)title icon:(NSString *)icon;
@property (weak) SCDialogHost *host;
- (void)close;                             // pop this dialog
@property (copy) SCAction onShow;
@property (readonly) UIStackView *content;
@property BOOL fillHeight;                 // take the max height (lists)
- (void)setBody:(UIView *)view;
// left = DELETE, right = CANCEL / OK in order added
- (UIButton *)addButton:(NSString *)title left:(BOOL)left action:(SCAction)action;
- (void)setIconBar:(UIView *)bar;
- (CGFloat)preferredHeightForWidth:(CGFloat)width;
@end

UIView *SCIconBar(NSArray<NSArray *> *left, NSArray<NSArray *> *right); // items: @[iconName, SCAction]

@interface SCDialogHost : NSObject
- (instancetype)initWithContainer:(UIView *)container;
@property (readonly) UIView *container;
@property (copy) SCAction onEmpty;
- (void)push:(SCDialog *)dialog;
- (void)pop;
- (void)popAll;
@property (readonly) NSUInteger count;
@property (readonly) SCDialog *top;
- (void)relayout;
@end

UILabel *SCToast(NSString *text);

// rows: @[iconName or NSNull, title]
SCDialog *SCChoiceDialog(NSString *title, NSString *icon, NSArray<NSArray *> *items, void (^pick)(NSInteger index));
SCDialog *SCChoiceDialogCancel(NSString *title, NSString *icon, NSArray<NSArray *> *items, void (^pick)(NSInteger index), SCAction cancel);
SCDialog *SCEditDialog(NSString *title, NSString *text, NSString *hint, void (^done)(NSString *text));
SCDialog *SCConfirmDialog(NSString *title, NSString *message, SCAction ok);
