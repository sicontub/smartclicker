#import "SCMaterial.h"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#import <QuartzCore/QuartzCore.h>
#include "Icons.h"
#include <objc/message.h>

UIColor *SCRGB(uint32_t c) {
  return [UIColor colorWithRed:((c >> 16) & 0xFF) / 255.0 green:((c >> 8) & 0xFF) / 255.0 blue:(c & 0xFF) / 255.0
                         alpha:((c >> 24) & 0xFF) / 255.0];
}

UIColor *SCDyn(uint32_t light, uint32_t dark) {
  UIColor *l = SCRGB(light), *d = SCRGB(dark);
  return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
    return t.userInterfaceStyle == UIUserInterfaceStyleDark ? d : l;
  }];
}

UIUserInterfaceStyle SCSystemStyle(void) {
  Class mode = NSClassFromString(@"UISUserInterfaceStyleMode");
  SEL mv = NSSelectorFromString(@"modeValue");
  if (mode) {
    id m = [mode new];
    if ([m respondsToSelector:mv]) {
      long v = (long)((long long (*)(id, SEL))objc_msgSend)(m, mv);
      if (v == 2) return UIUserInterfaceStyleDark;
      if (v == 1) return UIUserInterfaceStyleLight;
    }
  }
  Class arb = NSClassFromString(@"UIUserInterfaceStyleArbiter");
  SEL shared = NSSelectorFromString(@"sharedInstance"), cur = NSSelectorFromString(@"currentStyle");
  if ([arb respondsToSelector:shared]) {
    id a = ((id (*)(id, SEL))objc_msgSend)(arb, shared);
    if ([a respondsToSelector:cur]) {
      long v = (long)((long long (*)(id, SEL))objc_msgSend)(a, cur);
      if (v == UIUserInterfaceStyleDark || v == UIUserInterfaceStyleLight) return (UIUserInterfaceStyle)v;
    }
  }
  return [UIScreen mainScreen].traitCollection.userInterfaceStyle;
}

UIImage *SCIcon(NSString *name) {
  static NSMutableDictionary *cache;
  if (!cache) cache = [NSMutableDictionary new];
  if (!name) return nil;
  UIImage *img = cache[name];
  if (img) return img;
  for (const SCIconData *d = sc_icons; d->name; d++) {
    if (strcmp(d->name, name.UTF8String) == 0) {
      UIImage *raw = [UIImage imageWithData:[NSData dataWithBytesNoCopy:(void *)d->data length:d->len freeWhenDone:NO] scale:4];
      img = [raw imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
      break;
    }
  }
  if (img) cache[name] = img;
  return img;
}

#pragma mark - Controls

@implementation SCTap
+ (instancetype)tap:(SCAction)action {
  SCTap *t = [SCTap new];
  t.action = action;
  [t addTarget:t action:@selector(fire) forControlEvents:UIControlEventTouchUpInside];
  return t;
}
- (void)fire { if (self.action) self.action(); }
- (void)setHighlighted:(BOOL)h {
  [super setHighlighted:h];
  self.alpha = h ? 0.55 : 1.0;
}
@end

UIImageView *SCIconView(NSString *name, CGFloat size, UIColor *tint) {
  UIImageView *v = [[UIImageView alloc] initWithImage:SCIcon(name)];
  v.tintColor = tint ?: SC_TEXT;
  v.contentMode = UIViewContentModeScaleAspectFit;
  v.translatesAutoresizingMaskIntoConstraints = NO;
  if (size > 0) {
    [v.widthAnchor constraintEqualToConstant:size].active = YES;
    [v.heightAnchor constraintEqualToConstant:size].active = YES;
  }
  v.userInteractionEnabled = NO;
  return v;
}

UILabel *SCLabel(NSString *text, CGFloat size, BOOL bold, UIColor *color) {
  UILabel *l = [UILabel new];
  l.text = text;
  l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
  l.textColor = color ?: SC_TEXT;
  l.translatesAutoresizingMaskIntoConstraints = NO;
  return l;
}

@interface SCField : UITextField
@end
@implementation SCField
- (void)drawRect:(CGRect)r {
  [super drawRect:r];
  [(self.isFirstResponder ? SC_PRIMARY : SC_HINT) setFill];
  UIRectFill(CGRectMake(0, r.size.height - (self.isFirstResponder ? 2 : 1), r.size.width, self.isFirstResponder ? 2 : 1));
}
- (BOOL)becomeFirstResponder { BOOL b = [super becomeFirstResponder]; [self setNeedsDisplay]; return b; }
- (BOOL)resignFirstResponder { BOOL b = [super resignFirstResponder]; [self setNeedsDisplay]; return b; }
- (void)done { [self resignFirstResponder]; }
@end

UITextField *SCTextField(NSString *text, NSString *hint, BOOL numeric) {
  SCField *f = [SCField new];
  f.text = text;
  f.textColor = SC_TEXT;
  f.tintColor = SC_PRIMARY;
  f.font = [UIFont systemFontOfSize:17];
  f.backgroundColor = [UIColor clearColor];
  f.attributedPlaceholder = [[NSAttributedString alloc] initWithString:hint ?: @"" attributes:@{NSForegroundColorAttributeName : SC_HINT}];
  f.keyboardType = numeric ? UIKeyboardTypeNumberPad : UIKeyboardTypeDefault;
  f.keyboardAppearance = UIKeyboardAppearanceDefault;
  f.returnKeyType = UIReturnKeyDone;
  f.clearButtonMode = UITextFieldViewModeNever;
  [f addTarget:f action:@selector(done) forControlEvents:UIControlEventEditingDidEndOnExit];
  UIToolbar *bar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
  bar.barStyle = UIBarStyleBlack;
  bar.tintColor = SC_PRIMARY;
  bar.items = @[
    [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
    [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:f action:@selector(done)]
  ];
  f.inputAccessoryView = bar;
  f.translatesAutoresizingMaskIntoConstraints = NO;
  [f.heightAnchor constraintEqualToConstant:48].active = YES;
  return f;
}

UIView *SCSeparator(void) {
  UIView *v = [UIView new];
  v.backgroundColor = SCRGB(0x33FFFFFF);
  v.translatesAutoresizingMaskIntoConstraints = NO;
  [v.heightAnchor constraintEqualToConstant:1].active = YES;
  return v;
}

static UIView *SCPadded(UIView *v, CGFloat h) {
  UIView *wrap = [UIView new];
  wrap.translatesAutoresizingMaskIntoConstraints = NO;
  [wrap addSubview:v];
  v.translatesAutoresizingMaskIntoConstraints = NO;
  [NSLayoutConstraint activateConstraints:@[
    [v.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:h],
    [v.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-h],
    [v.topAnchor constraintEqualToAnchor:wrap.topAnchor],
    [v.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor],
  ]];
  return wrap;
}

UIView *SCCard(NSString *header, NSArray<UIView *> *rows) {
  UIView *card = [UIView new];
  card.backgroundColor = SC_CARD_BG;
  card.layer.cornerRadius = 4;
  card.layer.masksToBounds = YES;
  card.translatesAutoresizingMaskIntoConstraints = NO;
  UILabel *h = SCLabel(header, 14, YES, SC_ON_PRIMARY);
  UIView *hbg = [UIView new];
  hbg.backgroundColor = SC_PRIMARY;
  [hbg addSubview:h];
  [NSLayoutConstraint activateConstraints:@[
    [h.leadingAnchor constraintEqualToAnchor:hbg.leadingAnchor constant:8],
    [h.trailingAnchor constraintEqualToAnchor:hbg.trailingAnchor constant:-8],
    [h.topAnchor constraintEqualToAnchor:hbg.topAnchor constant:8],
    [h.bottomAnchor constraintEqualToAnchor:hbg.bottomAnchor constant:-8],
  ]];
  NSMutableArray *all = [NSMutableArray arrayWithObject:hbg];
  for (UIView *r in rows) {
    BOOL full = [r isKindOfClass:[UIScrollView class]] || r.tag == 99; // horizontal lists go edge to edge
    [all addObject:full ? r : SCPadded(r, 8)];
  }
  UIStackView *st = [[UIStackView alloc] initWithArrangedSubviews:all];
  st.axis = UILayoutConstraintAxisVertical;
  st.translatesAutoresizingMaskIntoConstraints = NO;
  [card addSubview:st];
  [NSLayoutConstraint activateConstraints:@[
    [st.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
    [st.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
    [st.topAnchor constraintEqualToAnchor:card.topAnchor],
    [st.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-4],
  ]];
  UIView *outer = [UIView new];
  outer.translatesAutoresizingMaskIntoConstraints = NO;
  [outer addSubview:card];
  [NSLayoutConstraint activateConstraints:@[
    [card.leadingAnchor constraintEqualToAnchor:outer.leadingAnchor constant:16],
    [card.trailingAnchor constraintEqualToAnchor:outer.trailingAnchor constant:-16],
    [card.topAnchor constraintEqualToAnchor:outer.topAnchor constant:8],
    [card.bottomAnchor constraintEqualToAnchor:outer.bottomAnchor constant:-8],
  ]];
  return outer;
}

SCTap *SCItemRow(NSString *icon, NSString *text, BOOL chevron, SCAction tap) {
  SCTap *row = [SCTap tap:tap];
  row.translatesAutoresizingMaskIntoConstraints = NO;
  [row.heightAnchor constraintGreaterThanOrEqualToConstant:48].active = YES;
  NSMutableArray *parts = [NSMutableArray new];
  if (icon) [parts addObject:SCIconView(icon, 24, nil)];
  UILabel *l = SCLabel(text, 16, NO, SC_TEXT);
  l.numberOfLines = 0;
  l.tag = 1;
  [parts addObject:l];
  if (chevron) [parts addObject:SCIconView(@"ic_chevron", 24, nil)];
  UIStackView *st = [[UIStackView alloc] initWithArrangedSubviews:parts];
  st.spacing = 8;
  st.alignment = UIStackViewAlignmentCenter;
  st.userInteractionEnabled = NO;
  st.translatesAutoresizingMaskIntoConstraints = NO;
  [row addSubview:st];
  [NSLayoutConstraint activateConstraints:@[
    [st.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:8],
    [st.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-8],
    [st.topAnchor constraintEqualToAnchor:row.topAnchor constant:8],
    [st.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-8],
  ]];
  return row;
}

UIView *SCHorizontalList(NSArray<UIView *> *cards) {
  UIScrollView *sv = [UIScrollView new];
  sv.backgroundColor = SC_LIST_BG;
  sv.showsHorizontalScrollIndicator = YES;
  sv.alwaysBounceHorizontal = YES;
  sv.translatesAutoresizingMaskIntoConstraints = NO;
  [sv.heightAnchor constraintEqualToConstant:124].active = YES;
  UIStackView *st = [[UIStackView alloc] initWithArrangedSubviews:cards];
  st.spacing = 16;
  st.alignment = UIStackViewAlignmentCenter;
  st.translatesAutoresizingMaskIntoConstraints = NO;
  [sv addSubview:st];
  [NSLayoutConstraint activateConstraints:@[
    [st.leadingAnchor constraintEqualToAnchor:sv.contentLayoutGuide.leadingAnchor constant:8],
    [st.trailingAnchor constraintEqualToAnchor:sv.contentLayoutGuide.trailingAnchor constant:-8],
    [st.topAnchor constraintEqualToAnchor:sv.contentLayoutGuide.topAnchor],
    [st.bottomAnchor constraintEqualToAnchor:sv.contentLayoutGuide.bottomAnchor],
    [st.heightAnchor constraintEqualToAnchor:sv.frameLayoutGuide.heightAnchor],
  ]];
  return sv;
}

@interface SCReorderList : UIScrollView
@property (strong) UIStackView *stack;
@property NSUInteger movable, fromIdx, curIdx;
@property (strong) UIView *lifted;
@property CGFloat grab;
@property (copy) void (^onMove)(NSUInteger from, NSUInteger to);
@end

@implementation SCReorderList
- (void)longPress:(UILongPressGestureRecognizer *)g {
  CGPoint p = [g locationInView:self];
  NSArray *cards = self.stack.arrangedSubviews;
  if (g.state == UIGestureRecognizerStateBegan) {
    for (NSUInteger i = 0; i < self.movable && i < cards.count; i++) {
      UIView *c = cards[i];
      if (CGRectContainsPoint([c convertRect:c.bounds toView:self], p)) {
        self.lifted = c;
        self.fromIdx = self.curIdx = i;
        self.grab = p.x - c.layer.position.x;
        [self.stack bringSubviewToFront:c];
        [UIView animateWithDuration:0.15 animations:^{ c.transform = CGAffineTransformMakeScale(1.08, 1.08); c.alpha = 0.85; }];
        break;
      }
    }
    return;
  }
  UIView *c = self.lifted;
  if (!c) return;
  if (g.state == UIGestureRecognizerStateChanged) {
    // scroll near the edges
    CGFloat edge = 40, max = MAX(0, self.contentSize.width - self.bounds.size.width), off = self.contentOffset.x;
    CGFloat vx = p.x - off;
    if (vx > self.bounds.size.width - edge && off < max) off = MIN(max, off + 8);
    else if (vx < edge && off > 0) off = MAX(0, off - 8);
    self.contentOffset = CGPointMake(off, 0);
    CGFloat want = p.x - self.grab;
    // swap once we pass the neighbour
    if (self.curIdx + 1 < self.movable && self.curIdx + 1 < cards.count && want > ((UIView *)cards[self.curIdx + 1]).layer.position.x) {
      self.curIdx++;
      [self.stack insertArrangedSubview:c atIndex:self.curIdx];
      [UIView animateWithDuration:0.15 animations:^{ [self.stack layoutIfNeeded]; }];
    } else if (self.curIdx > 0 && want < ((UIView *)cards[self.curIdx - 1]).layer.position.x) {
      self.curIdx--;
      [self.stack insertArrangedSubview:c atIndex:self.curIdx];
      [UIView animateWithDuration:0.15 animations:^{ [self.stack layoutIfNeeded]; }];
    }
    [self.stack layoutIfNeeded];
    c.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(1.08, 1.08), CGAffineTransformMakeTranslation(want - c.layer.position.x, 0));
    return;
  }
  self.lifted = nil;
  [UIView animateWithDuration:0.2 animations:^{ c.transform = CGAffineTransformIdentity; c.alpha = 1; }];
  if (self.curIdx != self.fromIdx && self.onMove) self.onMove(self.fromIdx, self.curIdx);
}
@end

UIView *SCReorderableList(NSArray<UIView *> *cards, NSUInteger movable, void (^onMove)(NSUInteger from, NSUInteger to)) {
  SCReorderList *sv = [SCReorderList new];
  sv.backgroundColor = SC_LIST_BG;
  sv.showsHorizontalScrollIndicator = YES;
  sv.alwaysBounceHorizontal = YES;
  sv.translatesAutoresizingMaskIntoConstraints = NO;
  [sv.heightAnchor constraintEqualToConstant:124].active = YES;
  UIStackView *st = [[UIStackView alloc] initWithArrangedSubviews:cards];
  st.spacing = 16;
  st.alignment = UIStackViewAlignmentCenter;
  st.translatesAutoresizingMaskIntoConstraints = NO;
  [sv addSubview:st];
  [NSLayoutConstraint activateConstraints:@[
    [st.leadingAnchor constraintEqualToAnchor:sv.contentLayoutGuide.leadingAnchor constant:8],
    [st.trailingAnchor constraintEqualToAnchor:sv.contentLayoutGuide.trailingAnchor constant:-8],
    [st.topAnchor constraintEqualToAnchor:sv.contentLayoutGuide.topAnchor],
    [st.bottomAnchor constraintEqualToAnchor:sv.contentLayoutGuide.bottomAnchor],
    [st.heightAnchor constraintEqualToAnchor:sv.frameLayoutGuide.heightAnchor],
  ]];
  sv.stack = st;
  sv.movable = movable;
  sv.onMove = onMove;
  UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:sv action:@selector(longPress:)];
  lp.minimumPressDuration = 0.3;
  [sv addGestureRecognizer:lp];
  return sv;
}

UIView *SCCardShell(void) {
  UIView *c = [UIView new];
  c.backgroundColor = SC_CARD_BG;
  c.layer.cornerRadius = 4;
  c.layer.shadowColor = [UIColor blackColor].CGColor;
  c.layer.shadowOpacity = 0.35;
  c.layer.shadowRadius = 2;
  c.layer.shadowOffset = CGSizeMake(0, 1);
  c.translatesAutoresizingMaskIntoConstraints = NO;
  [c.widthAnchor constraintEqualToConstant:100].active = YES;
  [c.heightAnchor constraintEqualToConstant:100].active = YES;
  return c;
}

static void SCFill(UIView *parent, UIView *child) {
  child.translatesAutoresizingMaskIntoConstraints = NO;
  [parent addSubview:child];
  [NSLayoutConstraint activateConstraints:@[
    [child.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor],
    [child.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor],
    [child.topAnchor constraintEqualToAnchor:parent.topAnchor],
    [child.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor],
  ]];
}

UIView *SCNewCopyCard(SCAction add, SCAction copy) {
  UIView *c = SCCardShell();
  SCTap *a = [SCTap tap:add];
  UIImageView *ai = SCIconView(@"ic_add", copy ? 32 : 40, nil);
  [a addSubview:ai];
  [ai.centerXAnchor constraintEqualToAnchor:a.centerXAnchor].active = YES;
  [ai.centerYAnchor constraintEqualToAnchor:a.centerYAnchor].active = YES;
  if (!copy) { SCFill(c, a); return c; }
  SCTap *b = [SCTap tap:copy];
  UIImageView *bi = SCIconView(@"ic_copy", 28, nil);
  [b addSubview:bi];
  [bi.centerXAnchor constraintEqualToAnchor:b.centerXAnchor].active = YES;
  [bi.centerYAnchor constraintEqualToAnchor:b.centerYAnchor].active = YES;
  UIView *sep = [UIView new];
  sep.backgroundColor = SCRGB(0x55FFFFFF);
  sep.translatesAutoresizingMaskIntoConstraints = NO;
  [sep.widthAnchor constraintEqualToConstant:1].active = YES;
  UIStackView *st = [[UIStackView alloc] initWithArrangedSubviews:@[ a, sep, b ]];
  st.alignment = UIStackViewAlignmentFill;
  [a.widthAnchor constraintEqualToAnchor:b.widthAnchor].active = YES;
  SCFill(c, st);
  [sep.heightAnchor constraintEqualToConstant:70].active = YES;
  st.alignment = UIStackViewAlignmentCenter;
  [a.heightAnchor constraintEqualToConstant:100].active = YES;
  [b.heightAnchor constraintEqualToConstant:100].active = YES;
  return c;
}

UIView *SCActionCard(NSString *icon, NSString *name, SCAction tap) {
  UIView *c = SCCardShell();
  SCTap *t = [SCTap tap:tap];
  SCFill(c, t);
  UIImageView *iv = SCIconView(icon, 50, nil);
  UILabel *l = SCLabel(name, 14, NO, SC_TEXT);
  l.textAlignment = NSTextAlignmentCenter;
  [t addSubview:iv];
  [t addSubview:l];
  [NSLayoutConstraint activateConstraints:@[
    [iv.centerXAnchor constraintEqualToAnchor:t.centerXAnchor],
    [iv.topAnchor constraintEqualToAnchor:t.topAnchor constant:12],
    [l.leadingAnchor constraintEqualToAnchor:t.leadingAnchor constant:8],
    [l.trailingAnchor constraintEqualToAnchor:t.trailingAnchor constant:-8],
    [l.topAnchor constraintEqualToAnchor:iv.bottomAnchor constant:8],
  ]];
  return c;
}

@interface SCGradientView : UIView
@end
@implementation SCGradientView
+ (Class)layerClass { return [CAGradientLayer class]; }
@end

UIView *SCConditionCard(UIImage *image, BOOL detect, BOOL whole, SCAction tap) {
  UIView *c = SCCardShell();
  c.clipsToBounds = YES;
  SCTap *t = [SCTap tap:tap];
  SCFill(c, t);
  UIImageView *iv = [[UIImageView alloc] initWithImage:image];
  iv.contentMode = UIViewContentModeScaleAspectFit;
  iv.userInteractionEnabled = NO;
  SCFill(t, iv);
  SCGradientView *g = [SCGradientView new];
  CAGradientLayer *gl = (CAGradientLayer *)g.layer;
  gl.colors = @[ (id)SCRGB(0x00000000).CGColor, (id)SCRGB(0x88000000).CGColor, (id)SCRGB(0xFF000000).CGColor ];
  gl.locations = @[ @0, @0.3, @1 ];
  g.userInteractionEnabled = NO;
  g.translatesAutoresizingMaskIntoConstraints = NO;
  [t addSubview:g];
  UIImageView *d = SCIconView(detect ? @"ic_confirm" : @"ic_cancel", 24, SC_ON_PRIMARY);
  UIImageView *w = SCIconView(whole ? @"ic_detect_whole_screen" : @"ic_detect_exact", 24, SC_ON_PRIMARY);
  [g addSubview:d];
  [g addSubview:w];
  [NSLayoutConstraint activateConstraints:@[
    [g.leadingAnchor constraintEqualToAnchor:t.leadingAnchor], [g.trailingAnchor constraintEqualToAnchor:t.trailingAnchor],
    [g.bottomAnchor constraintEqualToAnchor:t.bottomAnchor], [g.heightAnchor constraintEqualToConstant:30],
    [d.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:6], [d.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
    [w.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-6], [w.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
  ]];
  return c;
}

UIView *SCEndConditionCard(NSString *name, NSInteger executions, SCAction tap) {
  UIView *c = SCCardShell();
  SCTap *t = [SCTap tap:tap];
  SCFill(c, t);
  UILabel *n = SCLabel(name, 14, NO, SC_TEXT);
  n.numberOfLines = 2;
  n.textAlignment = NSTextAlignmentCenter;
  UIView *sep = SCSeparator();
  UILabel *x = SCLabel([NSString stringWithFormat:@"x%ld", (long)executions], 22, NO, SC_TEXT);
  x.textAlignment = NSTextAlignmentCenter;
  for (UIView *v in @[ n, sep, x ]) [t addSubview:v];
  [NSLayoutConstraint activateConstraints:@[
    [n.leadingAnchor constraintEqualToAnchor:t.leadingAnchor constant:8], [n.trailingAnchor constraintEqualToAnchor:t.trailingAnchor constant:-8],
    [n.centerYAnchor constraintEqualToAnchor:t.topAnchor constant:25],
    [sep.leadingAnchor constraintEqualToAnchor:t.leadingAnchor constant:8], [sep.trailingAnchor constraintEqualToAnchor:t.trailingAnchor constant:-8],
    [sep.centerYAnchor constraintEqualToAnchor:t.centerYAnchor],
    [x.centerXAnchor constraintEqualToAnchor:t.centerXAnchor], [x.centerYAnchor constraintEqualToAnchor:t.topAnchor constant:75],
  ]];
  return c;
}

UIView *SCIconBar(NSArray<NSArray *> *left, NSArray<NSArray *> *right) {
  UIView *bar = [UIView new];
  bar.backgroundColor = SC_PRIMARY;
  bar.translatesAutoresizingMaskIntoConstraints = NO;
  [bar.heightAnchor constraintEqualToConstant:50].active = YES;
  NSMutableArray *views = [NSMutableArray new];
  for (NSUInteger i = 0; i < left.count; i++) {
    if (i > 0) {
      UIView *sep = [UIView new];
      sep.backgroundColor = [UIColor whiteColor];
      sep.translatesAutoresizingMaskIntoConstraints = NO;
      [sep.widthAnchor constraintEqualToConstant:1].active = YES;
      [sep.heightAnchor constraintEqualToConstant:30].active = YES;
      [views addObject:sep];
    }
    SCTap *t = [SCTap tap:left[i][1]];
    t.translatesAutoresizingMaskIntoConstraints = NO;
    [t.widthAnchor constraintEqualToConstant:50].active = YES;
    [t.heightAnchor constraintEqualToConstant:50].active = YES;
    UIImageView *iv = SCIconView(left[i][0], 26, SC_ON_PRIMARY);
    [t addSubview:iv];
    [iv.centerXAnchor constraintEqualToAnchor:t.centerXAnchor].active = YES;
    [iv.centerYAnchor constraintEqualToAnchor:t.centerYAnchor].active = YES;
    [views addObject:t];
  }
  UIView *spacer = [UIView new];
  [spacer setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisHorizontal];
  [views addObject:spacer];
  for (NSArray *it in right) {
    SCTap *t = [SCTap tap:it[1]];
    t.translatesAutoresizingMaskIntoConstraints = NO;
    [t.widthAnchor constraintEqualToConstant:50].active = YES;
    [t.heightAnchor constraintEqualToConstant:50].active = YES;
    UIImageView *iv = SCIconView(it[0], 26, SC_ON_PRIMARY);
    [t addSubview:iv];
    [iv.centerXAnchor constraintEqualToAnchor:t.centerXAnchor].active = YES;
    [iv.centerYAnchor constraintEqualToAnchor:t.centerYAnchor].active = YES;
    [views addObject:t];
  }
  UIStackView *st = [[UIStackView alloc] initWithArrangedSubviews:views];
  st.alignment = UIStackViewAlignmentCenter;
  st.spacing = 4;
  st.translatesAutoresizingMaskIntoConstraints = NO;
  [bar addSubview:st];
  [NSLayoutConstraint activateConstraints:@[
    [st.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:4],
    [st.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-4],
    [st.topAnchor constraintEqualToAnchor:bar.topAnchor], [st.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor],
  ]];
  return bar;
}

UILabel *SCToast(NSString *text) {
  UILabel *l = [UILabel new];
  l.text = [NSString stringWithFormat:@"  %@  ", text];
  l.font = [UIFont systemFontOfSize:15];
  l.textColor = [UIColor whiteColor];
  l.backgroundColor = SCRGB(0xE6323232);
  l.textAlignment = NSTextAlignmentCenter;
  l.numberOfLines = 0;
  l.layer.cornerRadius = 18;
  l.layer.masksToBounds = YES;
  return l;
}

#pragma mark - Dialog

@interface SCDialogHost ()
- (void)popDialog:(SCDialog *)d;
@end

@implementation SCDialog {
  UIView *_titleBar, *_bottom, *_bodyHost;
  UIScrollView *_scroll;
  UIStackView *_content, *_buttonsLeft, *_buttonsRight;
}

- (instancetype)initWithTitle:(NSString *)title icon:(NSString *)icon {
  self = [super initWithFrame:CGRectMake(0, 0, 320, 200)];
  self.backgroundColor = SC_DIALOG_BG;
  self.layer.cornerRadius = 4;
  self.layer.masksToBounds = YES;

  _titleBar = [UIView new];
  _titleBar.backgroundColor = SC_PRIMARY_DARK;
  _titleBar.translatesAutoresizingMaskIntoConstraints = NO;
  UILabel *t = SCLabel(title, 20, NO, SC_ON_PRIMARY);
  t.font = [UIFont systemFontOfSize:20 weight:UIFontWeightMedium];
  [_titleBar addSubview:t];
  NSLayoutXAxisAnchor *titleLead = _titleBar.leadingAnchor;
  CGFloat titleInset = 24;
  if (icon) {
    UIImageView *iv = SCIconView(icon, 28, SC_ON_PRIMARY);
    [_titleBar addSubview:iv];
    [iv.leadingAnchor constraintEqualToAnchor:_titleBar.leadingAnchor constant:22].active = YES;
    [iv.centerYAnchor constraintEqualToAnchor:_titleBar.centerYAnchor].active = YES;
    titleLead = iv.trailingAnchor;
    titleInset = 14;
  }
  [NSLayoutConstraint activateConstraints:@[
    [t.leadingAnchor constraintEqualToAnchor:titleLead constant:titleInset],
    [t.trailingAnchor constraintLessThanOrEqualToAnchor:_titleBar.trailingAnchor constant:-16],
    [t.centerYAnchor constraintEqualToAnchor:_titleBar.centerYAnchor],
    [_titleBar.heightAnchor constraintEqualToConstant:56],
  ]];

  _bodyHost = [UIView new];
  _bodyHost.translatesAutoresizingMaskIntoConstraints = NO;
  _scroll = [UIScrollView new];
  _scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
  _scroll.indicatorStyle = UIScrollViewIndicatorStyleWhite;
  _content = [UIStackView new];
  _content.axis = UILayoutConstraintAxisVertical;
  _content.translatesAutoresizingMaskIntoConstraints = NO;
  [_scroll addSubview:_content];
  [NSLayoutConstraint activateConstraints:@[
    [_content.leadingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.leadingAnchor],
    [_content.trailingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.trailingAnchor],
    [_content.topAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.topAnchor constant:8],
    [_content.bottomAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.bottomAnchor constant:-8],
    [_content.widthAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.widthAnchor],
  ]];
  SCFill(_bodyHost, _scroll);

  _buttonsLeft = [UIStackView new];
  _buttonsRight = [UIStackView new];
  _buttonsRight.spacing = 8;
  _bottom = [UIView new];
  _bottom.translatesAutoresizingMaskIntoConstraints = NO;
  UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ _buttonsLeft, [UIView new], _buttonsRight ]];
  row.translatesAutoresizingMaskIntoConstraints = NO;
  [_bottom addSubview:row];
  [NSLayoutConstraint activateConstraints:@[
    [row.leadingAnchor constraintEqualToAnchor:_bottom.leadingAnchor constant:8],
    [row.trailingAnchor constraintEqualToAnchor:_bottom.trailingAnchor constant:-8],
    [row.topAnchor constraintEqualToAnchor:_bottom.topAnchor constant:4],
    [row.bottomAnchor constraintEqualToAnchor:_bottom.bottomAnchor constant:-4],
    [_bottom.heightAnchor constraintEqualToConstant:52],
  ]];

  UIStackView *v = [[UIStackView alloc] initWithArrangedSubviews:@[ _titleBar, _bodyHost, _bottom ]];
  v.axis = UILayoutConstraintAxisVertical;
  SCFill(self, v);
  _bottom.hidden = YES;
  [self addGestureRecognizer:({
    UITapGestureRecognizer *g = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(endEdit)];
    g.cancelsTouchesInView = NO;
    g;
  })];
  return self;
}

- (void)endEdit { [self endEditing:YES]; }
- (UIStackView *)content { return _content; }

- (void)setBody:(UIView *)view {
  [_scroll removeFromSuperview];
  _scroll = nil;
  SCFill(_bodyHost, view);
}

- (UIButton *)addButton:(NSString *)title left:(BOOL)left action:(SCAction)action {
  UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
  [b setTitle:title.uppercaseString forState:UIControlStateNormal];
  b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
  [b setTitleColor:SC_PRIMARY forState:UIControlStateNormal];
  [b setTitleColor:SC_HINT forState:UIControlStateDisabled];
  b.contentEdgeInsets = UIEdgeInsetsMake(8, 12, 8, 12);
  [b addAction:[UIAction actionWithHandler:^(UIAction *a) { action(); }] forControlEvents:UIControlEventTouchUpInside];
  [(left ? _buttonsLeft : _buttonsRight) addArrangedSubview:b];
  _bottom.hidden = NO;
  return b;
}

- (void)setIconBar:(UIView *)bar {
  for (UIView *v in _bottom.subviews) [v removeFromSuperview];
  _bottom.hidden = NO;
  for (NSLayoutConstraint *c in _bottom.constraints)
    if (c.firstAttribute == NSLayoutAttributeHeight && c.firstItem == _bottom) c.constant = 50;
  SCFill(_bottom, bar);
}

- (CGFloat)preferredHeightForWidth:(CGFloat)width {
  CGFloat h = 56 + (_bottom.hidden ? 0 : 52);
  if (_scroll) {
    CGSize s = [_content systemLayoutSizeFittingSize:CGSizeMake(width, 0)
                       withHorizontalFittingPriority:UILayoutPriorityRequired
                             verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    h += s.height + 16;
  } else {
    h += 300;
  }
  return h;
}

- (void)close { [self.host popDialog:self]; }
@end

@implementation SCDialogHost {
  NSMutableArray<SCDialog *> *_stack;
  UIEdgeInsets _kb;
}
- (instancetype)initWithContainer:(UIView *)container {
  self = [super init];
  _container = container;
  _stack = [NSMutableArray new];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillChangeFrameNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardHide:) name:UIKeyboardWillHideNotification object:nil];
  return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)keyboard:(NSNotification *)n {
  if (!_container.window) return;
  CGRect kb = [n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
  CGRect b = _container.bounds;
  CGRect k = CGRectIntersection(b, [_container convertRect:kb fromCoordinateSpace:_container.window.screen.coordinateSpace]);
  UIEdgeInsets in = UIEdgeInsetsZero;
  if (!CGRectIsNull(k) && k.size.width > 1 && k.size.height > 1) {
    // rotated overlay: the keyboard can sit on any edge
    if (k.size.width >= b.size.width * 0.8) {
      if (CGRectGetMaxY(k) >= CGRectGetMaxY(b) - 1) in.bottom = k.size.height; else in.top = CGRectGetMaxY(k);
    } else if (k.size.height >= b.size.height * 0.8) {
      if (CGRectGetMaxX(k) >= CGRectGetMaxX(b) - 1) in.right = k.size.width; else in.left = CGRectGetMaxX(k);
    }
  }
  _kb = in;
  [UIView animateWithDuration:0.25 animations:^{ [self relayout]; }];
}
- (void)keyboardHide:(NSNotification *)n {
  _kb = UIEdgeInsetsZero;
  [UIView animateWithDuration:0.25 animations:^{ [self relayout]; }];
}
- (NSUInteger)count { return _stack.count; }
- (SCDialog *)top { return _stack.lastObject; }

- (void)relayout {
  SCDialog *d = _stack.lastObject;
  if (!d) return;
  CGRect b = _container.bounds;
  UIEdgeInsets safe = _container.safeAreaInsets;
  CGFloat m = b.size.height < 500 ? 8 : 24;
  safe.top = MAX(safe.top, _kb.top);
  safe.bottom = MAX(safe.bottom, _kb.bottom);
  safe.left = MAX(safe.left, _kb.left);
  safe.right = MAX(safe.right, _kb.right);
  if (_kb.top || _kb.bottom) m = MIN(m, 8);
  CGRect area = UIEdgeInsetsInsetRect(b, UIEdgeInsetsMake(safe.top + m, safe.left + 16, safe.bottom + m, safe.right + 16));
  CGFloat w = MIN(area.size.width, 560);
  CGFloat maxH = MAX(120, area.size.height);
  CGFloat h = d.fillHeight ? maxH : MIN(maxH, [d preferredHeightForWidth:w]);
  d.frame = CGRectMake(floor(CGRectGetMidX(area) - w / 2), floor(CGRectGetMidY(area) - h / 2), w, h);
  [d layoutIfNeeded];
}

- (void)show:(SCDialog *)d {
  for (SCDialog *o in _stack) o.hidden = (o != d);
  [self relayout];
  if (d.onShow) d.onShow();
}

- (void)push:(SCDialog *)dialog {
  [_container endEditing:YES];
  dialog.host = self;
  [_stack addObject:dialog];
  [_container addSubview:dialog];
  [self show:dialog];
  dialog.alpha = 0;
  dialog.transform = CGAffineTransformMakeScale(0.94, 0.94);
  [UIView animateWithDuration:0.15 animations:^{ dialog.alpha = 1; dialog.transform = CGAffineTransformIdentity; }];
}

- (void)popDialog:(SCDialog *)d {
  [_container endEditing:YES];
  if (![_stack containsObject:d]) return;
  [d removeFromSuperview];
  [_stack removeObject:d];
  if (_stack.count) [self show:_stack.lastObject];
  else if (self.onEmpty) self.onEmpty();
}

- (void)pop { if (_stack.lastObject) [self popDialog:_stack.lastObject]; }

- (void)popAll {
  for (SCDialog *d in _stack) [d removeFromSuperview];
  [_stack removeAllObjects];
  if (self.onEmpty) self.onEmpty();
}
@end

#pragma mark - Stock dialogs

SCDialog *SCChoiceDialog(NSString *title, NSString *icon, NSArray<NSArray *> *items, void (^pick)(NSInteger index)) {
  return SCChoiceDialogCancel(title, icon, items, pick, nil);
}

SCDialog *SCChoiceDialogCancel(NSString *title, NSString *icon, NSArray<NSArray *> *items, void (^pick)(NSInteger index), SCAction cancel) {
  SCDialog *d = [[SCDialog alloc] initWithTitle:title icon:icon];
  __weak SCDialog *wd = d;
  for (NSInteger i = 0; i < (NSInteger)items.count; i++) {
    id ic = items[i][0];
    SCTap *row = SCItemRow([ic isKindOfClass:[NSString class]] ? ic : nil, items[i][1], NO, ^{
      [wd close];
      pick(i);
    });
    UIView *wrap = [UIView new];
    [wrap addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
      [row.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:16],
      [row.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-16],
      [row.topAnchor constraintEqualToAnchor:wrap.topAnchor], [row.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor],
    ]];
    [d.content addArrangedSubview:wrap];
  }
  [d addButton:@"Cancel" left:NO action:^{ [wd close]; if (cancel) cancel(); }];
  return d;
}

SCDialog *SCEditDialog(NSString *title, NSString *text, NSString *hint, void (^done)(NSString *text)) {
  SCDialog *d = [[SCDialog alloc] initWithTitle:title icon:nil];
  UITextField *f = SCTextField(text, hint, NO);
  UIView *wrap = [UIView new];
  [wrap addSubview:f];
  [NSLayoutConstraint activateConstraints:@[
    [f.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:24],
    [f.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-24],
    [f.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:8], [f.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor],
  ]];
  [d.content addArrangedSubview:wrap];
  __weak SCDialog *wd = d;
  __weak UITextField *wf = f;
  [d addButton:@"Cancel" left:NO action:^{ [wd close]; }];
  UIButton *ok = [d addButton:@"OK" left:NO action:^{
    NSString *t = [wf.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!t.length) return;
    [wd close];
    done(t);
  }];
  ok.enabled = text.length > 0;
  __weak UIButton *wok = ok;
  [f addAction:[UIAction actionWithHandler:^(UIAction *a) { wok.enabled = wf.text.length > 0; }]
      forControlEvents:UIControlEventEditingChanged];
  d.onShow = ^{ [wf becomeFirstResponder]; };
  return d;
}

SCDialog *SCConfirmDialog(NSString *title, NSString *message, SCAction ok) {
  SCDialog *d = [[SCDialog alloc] initWithTitle:title icon:nil];
  UILabel *l = SCLabel(message, 16, NO, SC_TEXT);
  l.numberOfLines = 0;
  UIView *wrap = [UIView new];
  [wrap addSubview:l];
  [NSLayoutConstraint activateConstraints:@[
    [l.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:24],
    [l.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-24],
    [l.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:12], [l.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor constant:-8],
  ]];
  [d.content addArrangedSubview:wrap];
  __weak SCDialog *wd = d;
  [d addButton:@"Cancel" left:NO action:^{ [wd close]; }];
  [d addButton:@"OK" left:NO action:^{ [wd close]; if (ok) ok(); }];
  return d;
}
