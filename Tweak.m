// SmartClicker overlay (runs in SpringBoard)
#import "Engine.h"
#import "Shared/SCMaterial.h"
#import <QuartzCore/QuartzCore.h>
#include <objc/runtime.h>
#include <objc/message.h>

static NSString *AC_px(double pt) { return [NSString stringWithFormat:@"%d", (int)round(pt * gNativeScale)]; }

static NSString *ac_actionIcon(NSString *t) {
  return [t isEqualToString:@"pause"] ? @"ic_wait" : [t isEqualToString:@"swipe"] ? @"ic_swipe" : [t isEqualToString:@"app"] ? @"ic_intent" : @"ic_click";
}

static id ac_get(id o, NSString *sel) {
  SEL s = NSSelectorFromString(sel);
  return [o respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil;
}

static NSArray<NSArray<NSString *> *> *ac_installedApps(void) {
  NSMutableArray *out = [NSMutableArray new];
  Class ws = NSClassFromString(@"LSApplicationWorkspace");
  id w = ac_get(ws, @"defaultWorkspace");
  NSMutableSet *seen = [NSMutableSet new];
  for (id p in ac_get(w, @"allInstalledApplications")) {
    NSString *bid = ac_get(p, @"bundleIdentifier");
    if (![bid isKindOfClass:[NSString class]] || [seen containsObject:bid]) continue;
    id tags = ac_get(p, @"appTags");
    if ([tags isKindOfClass:[NSArray class]] && [tags containsObject:@"hidden"]) continue;
    NSString *type = ac_get(p, @"applicationType");
    if ([type isKindOfClass:[NSString class]] && ![type isEqualToString:@"User"] && ![type isEqualToString:@"System"]) continue;
    if ([p respondsToSelector:NSSelectorFromString(@"isLaunchProhibited")] &&
        ((BOOL (*)(id, SEL))objc_msgSend)(p, NSSelectorFromString(@"isLaunchProhibited"))) continue;
    if ([bid isEqualToString:@"com.apple.springboard"] || [bid hasPrefix:@"com.apple.webapp"]) continue;
    NSString *name = ac_get(p, @"localizedName");
    if (![name isKindOfClass:[NSString class]] || !name.length) continue;
    [seen addObject:bid];
    [out addObject:@[ bid, name ]];
  }
  [out sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [a[1] localizedCaseInsensitiveCompare:b[1]]; }];
  return out;
}

static UIImage *ac_appIcon(NSString *bundleId) {
  static NSCache *cache;
  if (!cache) cache = [NSCache new];
  if (!bundleId.length) return nil;
  UIImage *img = [cache objectForKey:bundleId];
  if (img) return img;
  SEL s = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
  if ([UIImage respondsToSelector:s])
    img = ((UIImage * (*)(id, SEL, NSString *, int, CGFloat))objc_msgSend)([UIImage class], s, bundleId, 2, [UIScreen mainScreen].scale);
  if (img) [cache setObject:img forKey:bundleId];
  return img;
}

#pragma mark - Windows

@interface ACVC : UIViewController
@end
@implementation ACVC
- (BOOL)shouldAutorotate { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }
@end

static UIWindowScene *ac_scene(void) {
  for (id s in [UIApplication sharedApplication].connectedScenes.allObjects)
    if ([s isKindOfClass:[UIWindowScene class]]) return s;
  return nil;
}

// touches pass through to the app except on our views
@interface ACWindow : UIWindow
@property BOOL passThrough;
@end
@implementation ACWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
  UIView *v = [super hitTest:p withEvent:e];
  if (self.passThrough && (v == self || v == self.rootViewController.view || v.tag == 4242)) return nil;
  return v;
}
@end

static __weak UIWindow *gSpaceWin;

static UIWindow *ac_window(CGFloat level, BOOL passThrough) {
  UIWindowScene *scene = ac_scene();
  CGRect frame = scene ? scene.coordinateSpace.bounds : [UIScreen mainScreen].bounds;
  ACWindow *w = scene ? [[ACWindow alloc] initWithWindowScene:scene] : [[ACWindow alloc] initWithFrame:frame];
  if (CGRectIsEmpty(w.bounds)) w.frame = frame;
  frame = w.bounds;
  w.passThrough = passThrough;
  if (!gSpaceWin) gSpaceWin = w;
  w.windowLevel = level;
  w.backgroundColor = [UIColor clearColor];
  w.overrideUserInterfaceStyle = SCSystemStyle();
  ACVC *vc = [ACVC new];
  vc.view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, frame.size.height)];
  vc.view.backgroundColor = [UIColor clearColor];
  vc.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  w.rootViewController = vc;
  // rotate this instead of the vc's view
  UIView *content = [[UIView alloc] initWithFrame:vc.view.bounds];
  content.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  content.tag = 4242;
  [vc.view addSubview:content];
#ifndef SC_SHOWCASE
  @try { [w.layer setValue:@(0x12) forKey:@"disableUpdateMask"]; } @catch (id e) {} // keep out of screenshots
#endif
  return w;
}

#pragma mark - Orientation
// SpringBoard stays portrait on iPhone, so we rotate our own content

static double ac_orientAngle(long o) {
  switch (o) {
    case 3: return M_PI_2;   // UIInterfaceOrientationLandscapeRight
    case 4: return -M_PI_2;  // UIInterfaceOrientationLandscapeLeft
    case 2: return M_PI;     // UIInterfaceOrientationPortraitUpsideDown
    default: return 0;
  }
}

static id ac_send0(id o, NSString *sel) {
  SEL s = NSSelectorFromString(sel);
  return [o respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil;
}

// front app scene orientation, the other sources lag behind on quick rotations
static long ac_sceneOrientation(void) {
  id app = ac_send0([UIApplication sharedApplication], @"_accessibilityFrontMostApplication");
  if (!app) return 0;
  id mgr = ac_send0(NSClassFromString(@"SBSceneManagerCoordinator"), @"mainDisplaySceneManager");
  SEL find = NSSelectorFromString(@"existingSceneHandleForApplication:");
  if (![mgr respondsToSelector:find]) return 0;
  id handle = ((id (*)(id, SEL, id))objc_msgSend)(mgr, find, app);
  SEL cur = NSSelectorFromString(@"currentInterfaceOrientation");
  if (![handle respondsToSelector:cur]) return 0;
  long v = (long)((long long (*)(id, SEL))objc_msgSend)(handle, cur);
  return v >= 1 && v <= 4 ? v : 0;
}

static long ac_frontOrientation(void) {
  long sv = ac_sceneOrientation();
  if (sv) return sv;
  static id observer;
  if (!observer) observer = [NSClassFromString(@"FBSOrientationObserver") new];
  SEL active = NSSelectorFromString(@"activeInterfaceOrientation");
  if ([observer respondsToSelector:active]) {
    long v = (long)((long long (*)(id, SEL))objc_msgSend)(observer, active);
    if (v >= 1 && v <= 4) return v;
  }
  UIApplication *app = [UIApplication sharedApplication];
  for (NSString *name in @[ @"_frontMostAppOrientation", @"activeInterfaceOrientation" ]) {
    SEL s = NSSelectorFromString(name);
    if (![app respondsToSelector:s]) continue;
    long v = (long)((long long (*)(id, SEL))objc_msgSend)(app, s);
    if (v >= 1 && v <= 4) return v;
  }
  return 1;
}

static CGSize ac_spaceSize(void) {
  UIWindow *w = gSpaceWin;
  return w && !CGRectIsEmpty(w.bounds) ? w.bounds.size : [UIScreen mainScreen].bounds.size;
}

static long ac_windowSpaceOrientation(void) {
  UIScreen *scr = [UIScreen mainScreen];
  UIWindow *w = gSpaceWin;
  id<UICoordinateSpace> space = w ?: scr.coordinateSpace;
  CGPoint o = [space convertPoint:CGPointZero toCoordinateSpace:scr.fixedCoordinateSpace];
  CGPoint x = [space convertPoint:CGPointMake(100, 0) toCoordinateSpace:scr.fixedCoordinateSpace];
  CGFloat dx = x.x - o.x, dy = x.y - o.y;
  long r = fabs(dx) >= fabs(dy) ? (dx >= 0 ? 1 : 2) : (dy > 0 ? 3 : 4);
  // trust the window shape over the conversion
  CGSize sz = ac_spaceSize();
  BOOL wide = sz.width > sz.height;
  long f = ac_frontOrientation();
  if (!wide && (r == 3 || r == 4)) r = 1;
  if (wide && (f == 3 || f == 4)) r = f;
  else if (wide && (r == 1 || r == 2)) r = 3;
  return r;
}

static double ac_contentAngle(void) {
  long sb = ac_windowSpaceOrientation();
  double a = ac_orientAngle(ac_frontOrientation()) - ac_orientAngle(sb);
  while (a > M_PI + 0.01) a -= 2 * M_PI;
  while (a <= -M_PI + 0.01) a += 2 * M_PI;
  return a;
}
static BOOL ac_sideways(double a) { return fabs(fabs(a) - M_PI_2) < 0.1; }
static double ac_imageAngle(void) { return ac_orientAngle(ac_frontOrientation()); }

// screenshots are stored portrait
static UIImage *ac_upright(UIImage *img, double a) {
  if (!img.CGImage || fabs(a) < 0.1) return img;
  UIImageOrientation o = fabs(a - M_PI_2) < 0.1 ? UIImageOrientationLeft : fabs(a + M_PI_2) < 0.1 ? UIImageOrientationRight : UIImageOrientationDown;
  return [UIImage imageWithCGImage:img.CGImage scale:img.scale orientation:o];
}

static CGSize ac_contentSize(double a) {
  CGSize s = ac_spaceSize();
  return ac_sideways(a) ? CGSizeMake(s.height, s.width) : s;
}

static void ac_orientRoot(UIView *root, double a) {
  UIView *holder = root.superview;
  if (!holder) return;
  if (holder.window) holder.frame = holder.window.bounds; // might not be laid out yet
  CGRect wb = holder.bounds;
  root.autoresizingMask = UIViewAutoresizingNone;
  root.transform = CGAffineTransformIdentity;
  CGSize sz = ac_sideways(a) ? CGSizeMake(wb.size.height, wb.size.width) : wb.size;
  root.bounds = CGRectMake(0, 0, sz.width, sz.height);
  root.center = CGPointMake(CGRectGetMidX(wb), CGRectGetMidY(wb));
  root.transform = CGAffineTransformMakeRotation(a);
}

static UIView *ac_root(UIWindow *w) { return [w.rootViewController.view viewWithTag:4242]; }

static CGPoint ac_fixed(UIView *v, CGPoint p) {
  return [v convertPoint:p toCoordinateSpace:[UIScreen mainScreen].fixedCoordinateSpace];
}
static CGPoint ac_unfixed(UIView *v, CGPoint p) {
  return [v convertPoint:p fromCoordinateSpace:[UIScreen mainScreen].fixedCoordinateSpace];
}

#pragma mark - Click / swipe position selector (OverlaySelectorView.Click)

@interface ACPointPicker : UIView
@property BOOL swipe;
@property NSInteger count; // points chosen
@property CGPoint a, b;
@property (strong) CAShapeLayer *shapes;
@property (strong) UILabel *toast;
@end

@implementation ACPointPicker
- (instancetype)initWithFrame:(CGRect)f swipe:(BOOL)swipe {
  self = [super initWithFrame:f];
  self.swipe = swipe;
  self.backgroundColor = SC_OVERLAY_BG;
  self.shapes = [CAShapeLayer layer];
  [self.layer addSublayer:self.shapes];
  self.toast = SCToast(swipe ? @"Touch the position to start the swipe from." : @"Touch the position to click on.");
  [self addSubview:self.toast];
  [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)]];
  return self;
}
- (void)layoutSubviews {
  [super layoutSubviews];
  CGSize s = [self.toast sizeThatFits:CGSizeMake(self.bounds.size.width - 48, 200)];
  self.toast.frame = CGRectMake((self.bounds.size.width - s.width - 16) / 2, self.bounds.size.height - 120, s.width + 16, MAX(36, s.height + 12));
}
- (void)ring:(CGPoint)p color:(UIColor *)c {
  CAShapeLayer *r = [CAShapeLayer layer];
  r.path = [UIBezierPath bezierPathWithArcCenter:p radius:28 startAngle:0 endAngle:2 * M_PI clockwise:YES].CGPath;
  r.strokeColor = c.CGColor;
  r.fillColor = [UIColor clearColor].CGColor;
  r.lineWidth = 3;
  [self.shapes addSublayer:r];
  CAShapeLayer *dot = [CAShapeLayer layer];
  dot.path = [UIBezierPath bezierPathWithArcCenter:p radius:6 startAngle:0 endAngle:2 * M_PI clockwise:YES].CGPath;
  dot.fillColor = [UIColor whiteColor].CGColor;
  [self.shapes addSublayer:dot];
}
- (void)redraw {
  for (CALayer *l in [self.shapes.sublayers copy]) [l removeFromSuperlayer];
  if (self.count >= 2) {
    CAShapeLayer *line = [CAShapeLayer layer];
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:self.a];
    [p addLineToPoint:self.b];
    line.path = p.CGPath;
    line.strokeColor = [UIColor whiteColor].CGColor;
    line.lineWidth = 3;
    [self.shapes addSublayer:line];
  }
  if (self.count >= 1) [self ring:self.a color:SC_PRIMARY];
  if (self.count >= 2) [self ring:self.b color:SC_ACCENT];
}
- (void)tapped:(UITapGestureRecognizer *)g {
  CGPoint p = [g locationInView:self];
  if (!self.swipe) { self.a = p; self.count = 1; }
  else if (self.count != 1) { self.a = p; self.count = 1; self.toast.text = @"  Touch the position to end the swipe to.  "; }
  else { self.b = p; self.count = 2; self.toast.text = @"  Touch the position to start the swipe from.  "; }
  [self setNeedsLayout];
  [self redraw];
}
- (BOOL)done { return self.count >= (self.swipe ? 2 : 1); }
@end

#pragma mark - Play / pause icon with Android's morph animation (anim_play_pause / anim_pause_play)

// paths from the apk (path_play / path_pause)
static CGPathRef ac_playPausePath(BOOL pause, CGFloat size) {
  static const CGFloat play[2][4][2] = {{{34, 22}, {34, 64}, {100, 64}, {100, 64}}, {{34, 106}, {34, 64}, {100, 64}, {100, 64}}};
  static const CGFloat paus[2][4][2] = {{{25, 33}, {25, 56}, {103, 56}, {103, 33}}, {{25, 95}, {25, 72}, {103, 72}, {103, 95}}};
  CGFloat k = size / 128.0;
  CGMutablePathRef p = CGPathCreateMutable();
  for (int sp = 0; sp < 2; sp++) {
    for (int i = 0; i < 4; i++) {
      const CGFloat *pt = pause ? paus[sp][i] : play[sp][i];
      if (i == 0) CGPathMoveToPoint(p, NULL, pt[0] * k, pt[1] * k);
      else CGPathAddLineToPoint(p, NULL, pt[0] * k, pt[1] * k);
    }
    CGPathCloseSubpath(p);
  }
  return p;
}

@interface ACPlayPauseView : UIView
@property (strong) CAShapeLayer *shape;
@property BOOL playing;
- (void)setPlaying:(BOOL)playing animated:(BOOL)animated;
@end

@implementation ACPlayPauseView
- (instancetype)initWithFrame:(CGRect)f {
  self = [super initWithFrame:f];
  self.userInteractionEnabled = NO;
  self.shape = [CAShapeLayer layer];
  self.shape.frame = self.bounds;
  self.shape.fillColor = [UIColor whiteColor].CGColor;
  CGPathRef p = ac_playPausePath(NO, f.size.width);
  self.shape.path = p;
  CGPathRelease(p);
  [self.layer addSublayer:self.shape];
  return self;
}
- (void)setPlaying:(BOOL)playing animated:(BOOL)animated {
  if (playing == self.playing && self.shape.path) return;
  CGPathRef to = ac_playPausePath(playing, self.bounds.size.width);
  CGFloat angle = playing ? M_PI_2 : 0;
  if (animated) {
    CAMediaTimingFunction *fosi = [CAMediaTimingFunction functionWithControlPoints:0.4 :0.0 :0.2 :1.0];
    CABasicAnimation *morph = [CABasicAnimation animationWithKeyPath:@"path"];
    morph.fromValue = (__bridge id)self.shape.path;
    morph.toValue = (__bridge id)to;
    CABasicAnimation *rot = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    rot.fromValue = [self.shape valueForKeyPath:@"transform.rotation.z"];
    rot.toValue = @(angle);
    CAAnimationGroup *g = [CAAnimationGroup animation];
    g.animations = @[ morph, rot ];
    g.duration = 0.175;
    g.timingFunction = fosi;
    [self.shape addAnimation:g forKey:@"morph"];
  }
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.shape.path = to;
  [self.shape setValue:@(angle) forKeyPath:@"transform.rotation.z"];
  [CATransaction commit];
  CGPathRelease(to);
  self.playing = playing;
}
@end

#pragma mark - Condition area selector (frozen screenshot + resizable selection)

// port of android's ConditionSelectorView
@interface ACAreaPicker : UIView <UIGestureRecognizerDelegate>
@property (strong) UIImageView *shot;
@property CGRect capture; // where the screenshot is drawn
@property CGFloat zoom;
@property CGRect sel;
@property CGSize minSel;
@property NSInteger zone; // 0 none, 1-4 edges, 5 move, 6 pan
@property CGRect startSel, startCapture;
@property BOOL pinching;
@property (strong) CAShapeLayer *border, *fill;
@property (strong) UIImageView *hint;
@property (strong) NSTimer *hintTimer;
@end

#define SEL_HANDLE 30.0
#define SEL_INNER 10.0
#define SEL_BORDER 4.0
#define SEL_RADIUS 2.0
#define ZOOM_MIN 0.8
#define ZOOM_MAX 5.0

@implementation ACAreaPicker
- (instancetype)initWithFrame:(CGRect)f image:(UIImage *)img {
  self = [super initWithFrame:f];
  self.backgroundColor = [UIColor blackColor];
  self.clipsToBounds = YES;
  self.zoom = 1;
  self.capture = self.bounds;
  self.shot = [[UIImageView alloc] initWithFrame:self.bounds];
  self.shot.image = img;
  self.shot.contentMode = UIViewContentModeScaleToFill;
  self.shot.layer.magnificationFilter = kCAFilterNearest;
  [self addSubview:self.shot];
  self.fill = [CAShapeLayer layer];
  self.fill.fillColor = SC_OVERLAY_BG.CGColor;
  [self.layer addSublayer:self.fill];
  self.border = [CAShapeLayer layer];
  self.border.strokeColor = [UIColor whiteColor].CGColor;
  self.border.fillColor = [UIColor clearColor].CGColor;
  self.border.lineWidth = SEL_BORDER;
  [self.layer addSublayer:self.border];
  // 230x130dp default, same as android
  CGFloat w = MIN(230, f.size.width - 16), h = MIN(130, f.size.height - 16);
  self.sel = CGRectMake((f.size.width - w) / 2, (f.size.height - h) / 2, w, h);
  self.minSel = CGSizeMake(f.size.width * 0.1, f.size.height * 0.05);
  self.hint = [[UIImageView alloc] initWithImage:SCIcon(@"ic_hint_move")];
  self.hint.tintColor = [UIColor whiteColor];
  self.hint.frame = CGRectMake(0, 0, 50, 50);
  [self addSubview:self.hint];
  UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
  pan.maximumNumberOfTouches = 2;
  pan.delegate = self;
  [self addGestureRecognizer:pan];
  UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinch:)];
  pinch.delegate = self;
  [self addGestureRecognizer:pinch];
  [self redraw];
  [self showHint];
  return self;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b {
  return YES;
}

- (void)redraw {
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.shot.frame = self.capture;
  self.border.path = [UIBezierPath bezierPathWithRoundedRect:self.sel cornerRadius:SEL_RADIUS].CGPath;
  self.fill.path = [UIBezierPath bezierPathWithRect:CGRectInset(self.sel, SEL_BORDER / 2, SEL_BORDER / 2)].CGPath;
  [CATransaction commit];
  self.hint.center = CGPointMake(CGRectGetMidX(self.sel), CGRectGetMidY(self.sel));
}

- (void)showHint {
  [self.hintTimer invalidate];
  self.hint.alpha = 1;
  __weak ACAreaPicker *ws = self;
  self.hintTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer *t) {
    [UIView animateWithDuration:0.5 animations:^{ ws.hint.alpha = 0; }];
  }];
}

// box -> screenshot coords
- (CGRect)selection {
  CGRect r = CGRectIntersection(CGRectInset(self.sel, SEL_BORDER / 2, SEL_BORDER / 2), self.capture);
  if (CGRectIsNull(r)) return CGRectNull;
  r = CGRectMake((r.origin.x - self.capture.origin.x) / self.zoom, (r.origin.y - self.capture.origin.y) / self.zoom,
                 r.size.width / self.zoom, r.size.height / self.zoom);
  return CGRectIntersection(r, self.bounds);
}

- (void)setZoomLevel:(CGFloat)z pivot:(CGPoint)pivot {
  z = MAX(ZOOM_MIN, MIN(ZOOM_MAX, z));
  if (z == self.zoom) return;
  if (z < 1) pivot = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
  CGRect c = self.capture;
  CGFloat ratio = z / self.zoom;
  CGFloat dw = c.size.width * ratio - c.size.width, dh = c.size.height * ratio - c.size.height;
  CGFloat px = (pivot.x - c.origin.x) / c.size.width, py = (pivot.y - c.origin.y) / c.size.height;
  c.origin.x -= dw * px;
  c.origin.y -= dh * py;
  c.size.width += dw;
  c.size.height += dh;
  self.capture = c;
  self.zoom = z;
  [self redraw];
}

- (void)pinch:(UIPinchGestureRecognizer *)g {
  if (g.state == UIGestureRecognizerStateBegan) {
    // two fingers = zoom
    if (self.zone >= 1 && self.zone <= 5) { self.sel = self.startSel; [self redraw]; }
    self.zone = 6;
    self.pinching = YES;
  }
  if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) { self.pinching = NO; g.scale = 1; return; }
  if (g.state == UIGestureRecognizerStateChanged) [self setZoomLevel:self.zoom * g.scale pivot:[g locationInView:self]];
  g.scale = 1;
}

// keep 20% of the screenshot on screen
- (void)panCaptureBy:(CGPoint)d {
  CGRect c = self.capture, b = self.bounds;
  CGFloat mw = b.size.width * 0.2, mh = b.size.height * 0.2;
  if (d.x > 0 && c.origin.x + d.x > CGRectGetMaxX(b) - mw) d.x = 0;
  if (d.x < 0 && CGRectGetMaxX(c) + d.x < b.origin.x + mw) d.x = 0;
  if (d.y > 0 && c.origin.y + d.y > CGRectGetMaxY(b) - mh) d.y = 0;
  if (d.y < 0 && CGRectGetMaxY(c) + d.y < b.origin.y + mh) d.y = 0;
  c.origin.x += d.x;
  c.origin.y += d.y;
  self.capture = c;
  [self redraw];
}

- (void)pan:(UIPanGestureRecognizer *)g {
  if (g.state == UIGestureRecognizerStateBegan) {
    CGPoint p = [g locationInView:self], t = [g translationInView:self];
    p = CGPointMake(p.x - t.x, p.y - t.y);
    CGRect r = self.sel;
    BOOL big = r.size.width > SEL_HANDLE && r.size.height > SEL_HANDLE;
    CGFloat in = big ? SEL_INNER : 0;
    // left, top, right, bottom, move
    if (CGRectContainsPoint(CGRectMake(r.origin.x - SEL_HANDLE, r.origin.y, SEL_HANDLE + in, r.size.height), p)) self.zone = 1;
    else if (CGRectContainsPoint(CGRectMake(r.origin.x, r.origin.y - SEL_HANDLE, r.size.width, SEL_HANDLE + in), p)) self.zone = 2;
    else if (CGRectContainsPoint(CGRectMake(CGRectGetMaxX(r) - in, r.origin.y, SEL_HANDLE + in, r.size.height), p)) self.zone = 3;
    else if (CGRectContainsPoint(CGRectMake(r.origin.x, CGRectGetMaxY(r) - in, r.size.width, SEL_HANDLE + in), p)) self.zone = 4;
    else if (CGRectContainsPoint(r, p)) self.zone = 5;
    else self.zone = 6;
    self.startSel = r;
    self.startCapture = self.capture;
    if (self.zone <= 5) [self showHint];
  }
  if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
    self.zone = 0;
    return;
  }
  CGPoint t = [g translationInView:self];
  [g setTranslation:CGPointZero inView:self];
  if (self.pinching || g.numberOfTouches > 1) { if (self.zone == 6) [self panCaptureBy:t]; return; }
  if (self.zone == 6) { [self panCaptureBy:t]; return; }
  CGRect r = self.sel;
  CGSize m = self.minSel;
  switch (self.zone) {
    case 1: { CGFloat nl = MIN(r.origin.x + t.x, CGRectGetMaxX(r) - m.width); r.size.width = CGRectGetMaxX(r) - nl; r.origin.x = nl; break; }
    case 2: { CGFloat nt = MIN(r.origin.y + t.y, CGRectGetMaxY(r) - m.height); r.size.height = CGRectGetMaxY(r) - nt; r.origin.y = nt; break; }
    case 3: r.size.width = MAX(CGRectGetMaxX(r) + t.x, r.origin.x + m.width) - r.origin.x; break;
    case 4: r.size.height = MAX(CGRectGetMaxY(r) + t.y, r.origin.y + m.height) - r.origin.y; break;
    case 5: { CGRect moved = CGRectOffset(r, t.x, t.y); if (CGRectContainsRect(self.bounds, moved)) r = moved; break; }
    default: return;
  }
  r = CGRectIntersection(r, self.bounds);
  if (!CGRectIsNull(r)) self.sel = r;
  [self redraw];
}
@end

#pragma mark - Event list table (item_event)

@interface ACEventCell : UITableViewCell
@property (strong) UILabel *name;
@property (strong) UIStackView *icons;
@end
@implementation ACEventCell
- (instancetype)initWithStyle:(UITableViewCellStyle)s reuseIdentifier:(NSString *)r {
  self = [super initWithStyle:s reuseIdentifier:r];
  self.backgroundColor = [UIColor clearColor];
  UIView *sel = [UIView new];
  sel.backgroundColor = SCDyn(0x22000000, 0x22FFFFFF);
  self.selectedBackgroundView = sel;
  self.name = SCLabel(@"", 17, YES, SC_TEXT);
  self.icons = [UIStackView new];
  self.icons.spacing = 8;
  self.icons.translatesAutoresizingMaskIntoConstraints = NO;
  [self.contentView addSubview:self.name];
  [self.contentView addSubview:self.icons];
  UIImageView *chev = SCIconView(@"ic_chevron", 24, nil);
  [self.contentView addSubview:chev];
  self.showsReorderControl = YES;
  [NSLayoutConstraint activateConstraints:@[
    [self.name.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
    [self.name.trailingAnchor constraintEqualToAnchor:chev.leadingAnchor constant:-8],
    [self.name.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
    [self.icons.leadingAnchor constraintEqualToAnchor:self.name.leadingAnchor],
    [self.icons.topAnchor constraintEqualToAnchor:self.name.bottomAnchor constant:4],
    [self.icons.heightAnchor constraintEqualToConstant:20],
    [chev.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
    [chev.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
  ]];
  return self;
}
@end

@interface ACEventTable : NSObject <UITableViewDataSource, UITableViewDelegate>
@property (strong) UITableView *table;
@property (strong) UILabel *empty;
@property (strong) NSMutableArray *events;
@property (copy) void (^select)(NSInteger i);
@end
@implementation ACEventTable
- (instancetype)init {
  self = [super init];
  self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
  self.table.backgroundColor = [UIColor clearColor];
  self.table.separatorColor = SCDyn(0x33000000, 0x33FFFFFF);
  self.table.rowHeight = 62;
  self.table.dataSource = self;
  self.table.delegate = self;
  self.table.indicatorStyle = UIScrollViewIndicatorStyleWhite;
  self.table.tableFooterView = [UIView new];
  [self.table registerClass:[ACEventCell class] forCellReuseIdentifier:@"e"];
  self.empty = SCLabel(@"No events.", 17, NO, SC_TEXT);
  self.empty.textAlignment = NSTextAlignmentCenter;
  self.table.backgroundView = self.empty;
  return self;
}
- (void)reload { self.empty.hidden = self.events.count > 0; [self.table reloadData]; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.events.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
  ACEventCell *c = [t dequeueReusableCellWithIdentifier:@"e" forIndexPath:ip];
  NSDictionary *e = self.events[ip.row];
  c.name.text = e[@"name"];
  for (UIView *v in [c.icons.arrangedSubviews copy]) [v removeFromSuperview];
  for (NSDictionary *a in e[@"actions"]) [c.icons addArrangedSubview:SCIconView(ac_actionIcon(a[@"t"]), 20, nil)];
  return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
  [t deselectRowAtIndexPath:ip animated:YES];
  if (!t.editing && self.select) self.select(ip.row);
}
- (BOOL)tableView:(UITableView *)t canMoveRowAtIndexPath:(NSIndexPath *)ip { return YES; }
- (UITableViewCellEditingStyle)tableView:(UITableView *)t editingStyleForRowAtIndexPath:(NSIndexPath *)ip { return UITableViewCellEditingStyleNone; }
- (BOOL)tableView:(UITableView *)t shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)ip { return NO; }
- (void)tableView:(UITableView *)t moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
  id o = self.events[from.row];
  [self.events removeObjectAtIndex:from.row];
  [self.events insertObject:o atIndex:to.row];
}
@end

#pragma mark - Overlay controller

@interface ACOverlay : NSObject
@property (strong) UIWindow *menuWin, *dialogWin, *pickWin, *debugWin;
@property (strong) UIView *menuPanel, *debugBox;
@property (strong) UILabel *dbgEvent, *dbgCond, *dbgConf, *dbgCurrent;
@property (strong) NSTimer *debugTimer;
@property (strong) SCDialogHost *host;
@property (strong) NSMutableDictionary *edit;
@property (strong) ACEventTable *eventTable;
@property (strong) id playIcon;
@property (strong) UIView *listButton;
@property (copy) SCAction menuConfirm, menuCancel, menuCapture;
@property CGPoint menuOrigin;
@property BOOL ready, wanted, menuPlaced;
@property double rot;
@property CGSize space;
@property NSInteger menuMode;
@property (strong) NSTimer *orientTimer;
@end

@implementation ACOverlay {
  uint8_t *_frame;
}

+ (instancetype)shared {
  static ACOverlay *o;
  if (!o) o = [ACOverlay new];
  return o;
}

- (void)setup {
  UIScreen *s = [UIScreen mainScreen];
  gFixedSize = s.fixedCoordinateSpace.bounds.size;
  gNativeScale = s.nativeScale;
  gNativeW = (int)s.nativeBounds.size.width;
  gNativeH = (int)s.nativeBounds.size.height;
  ac_hidSetup();
  __weak ACOverlay *ws = self;
  gOnStop = ^(NSString *reason) {
    BOOL wasDebug = gDebug;
    gDebug = false;
    [ws stopDebugDisplay];
    if (wasDebug && ws.wanted && !ws.menuWin.hidden && ws.playIcon) [ws buildMenu:0];
    [ws refreshPlay];
  };
  self.ready = YES;
  if (self.wanted) [self show];
}

#pragma mark Floating menu (overlay_menu / overlay_validation_menu)

- (SCTap *)menuButton:(NSString *)icon action:(SCAction)a {
  SCTap *t = [SCTap tap:a];
  t.frame = CGRectMake(0, 0, 48, 48);
  UIImageView *iv = [[UIImageView alloc] initWithImage:SCIcon(icon)];
  iv.tintColor = [UIColor whiteColor];
  iv.frame = CGRectMake(4, 4, 40, 40);
  iv.contentMode = UIViewContentModeScaleAspectFit;
  iv.tag = 7;
  [t addSubview:iv];
  return t;
}

// mode: 0 = main, 1 = validation (confirm/cancel), 2 = capture (screenshot/cancel)
- (void)buildMenu:(NSInteger)mode {
  self.menuMode = mode;
  NSMutableArray<UIView *> *buttons = [NSMutableArray new];
  __weak ACOverlay *ws = self;
  self.playIcon = nil;
  self.listButton = nil;
  if (mode == 0) {
    SCTap *play = [self menuButton:@"ic_play_arrow" action:^{ [ws togglePlay:NO]; }];
    UIView *img = [play viewWithTag:7];
    ACPlayPauseView *pp = [[ACPlayPauseView alloc] initWithFrame:img.frame];
    [img removeFromSuperview];
    [play addSubview:pp];
    [pp setPlaying:gRunning animated:NO];
    self.playIcon = pp;
    // long press = debug mode
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(playLongPress:)];
    lp.minimumPressDuration = 0.5;
    [play addGestureRecognizer:lp];
    SCTap *list = [self menuButton:@"ic_click_list" action:^{ if (!gRunning) [ws openEventList]; }];
    self.listButton = list;
    [buttons addObjectsFromArray:@[ play, [self menuButton:@"ic_stop" action:^{ [ws stopClicker]; }], list ]];
  } else if (mode == 1) {
    [buttons addObject:[self menuButton:@"ic_confirm" action:^{ if (ws.menuConfirm) ws.menuConfirm(); }]];
    [buttons addObject:[self menuButton:@"ic_cancel" action:^{ if (ws.menuCancel) ws.menuCancel(); }]];
  } else {
    [buttons addObject:[self menuButton:@"ic_screenshot" action:^{ if (ws.menuCapture) ws.menuCapture(); }]];
    [buttons addObject:[self menuButton:@"ic_cancel" action:^{ if (ws.menuCancel) ws.menuCancel(); }]];
  }
  SCTap *move = [self menuButton:@"ic_move" action:nil];
  [move addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragMenu:)]];
  [buttons addObject:move];

  BOOL debugPanel = mode == 0 && gDebug && gRunning;
  CGFloat w = 56 + (debugPanel ? 200 : 0), h = 8 + 48 * buttons.count;
  double a = self.rot;
  CGSize sb = ac_contentSize(a);
  if (!self.menuPlaced) {
    // saved per orientation like android
    NSDictionary *pos = [NSDictionary dictionaryWithContentsOfFile:[AC_DIR stringByAppendingPathComponent:@"menu.plist"]];
    BOOL land = sb.width > sb.height;
    NSString *kx = land ? @"lx" : @"x", *ky = land ? @"ly" : @"y";
    self.menuOrigin = pos[kx] ? CGPointMake([pos[kx] doubleValue], [pos[ky] doubleValue]) : CGPointMake(4, sb.height * 0.3);
    self.menuPlaced = YES;
  }
  CGPoint o = self.menuOrigin;
  o.x = MAX(0, MIN(o.x, sb.width - w));
  o.y = MAX(0, MIN(o.y, sb.height - h));
  self.menuOrigin = o;
  if (!self.menuWin) self.menuWin = ac_window(1100, YES);
  UIView *root = ac_root(self.menuWin);
  ac_orientRoot(root, a);
  for (UIView *v in [root.subviews copy]) [v removeFromSuperview];
  UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(o.x, o.y, w, h)];
  panel.backgroundColor = SC_OVERLAY_BG;
  panel.layer.cornerRadius = 10;
  panel.layer.masksToBounds = YES;
  [root addSubview:panel];
  self.menuPanel = panel;
  for (NSUInteger i = 0; i < buttons.count; i++) {
    buttons[i].frame = CGRectMake(4, 4 + 48 * i, 48, 48);
    [panel addSubview:buttons[i]];
  }
  if (debugPanel) [self buildDebugPanelIn:panel frame:CGRectMake(56, 0, 200, h)];
  else { self.dbgEvent = self.dbgCond = self.dbgConf = self.dbgCurrent = nil; }
  BOOL appearing = self.menuWin.hidden || self.menuWin.alpha < 1;
  self.menuWin.hidden = NO;
  if (appearing) {
    self.menuWin.alpha = 0;
    panel.transform = CGAffineTransformMakeScale(0.85, 0.85);
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
      self.menuWin.alpha = 1;
      panel.transform = CGAffineTransformIdentity;
    } completion:nil];
  }
  [self refreshPlay];
}

- (void)buildDebugPanelIn:(UIView *)root frame:(CGRect)f {
  UIView *panel = [[UIView alloc] initWithFrame:f];
  UIView *sepV = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 2, f.size.height)];
  sepV.backgroundColor = [UIColor whiteColor];
  [panel addSubview:sepV];
  CGFloat sepY = round(f.size.height * 0.35);
  UIView *sepH = [[UIView alloc] initWithFrame:CGRectMake(2, sepY, f.size.width - 2, 2)];
  sepH.backgroundColor = [UIColor whiteColor];
  [panel addSubview:sepH];
  UILabel *(^mk)(CGFloat, CGFloat, CGFloat) = ^UILabel *(CGFloat y, CGFloat hh, CGFloat size) {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(6, y, f.size.width - 10, hh)];
    l.textColor = [UIColor whiteColor];
    l.font = [UIFont systemFontOfSize:size];
    l.textAlignment = NSTextAlignmentCenter;
    l.lineBreakMode = NSLineBreakByTruncatingMiddle;
    l.adjustsFontSizeToFitWidth = size > 20;
    [panel addSubview:l];
    return l;
  };
  CGFloat lh = (sepY - 6) / 3;
  self.dbgEvent = mk(3, lh, 12);
  self.dbgCond = mk(3 + lh, lh, 12);
  self.dbgConf = mk(3 + 2 * lh, lh, 12);
  self.dbgCurrent = mk(sepY + 2, f.size.height - sepY - 2, 34);
  self.dbgEvent.text = @"-";
  self.dbgCond.text = @"-";
  self.dbgConf.text = @"-";
  self.dbgCurrent.text = @"-";
  [root addSubview:panel];
}

- (void)playLongPress:(UILongPressGestureRecognizer *)g {
  if (g.state != UIGestureRecognizerStateBegan) return;
  if (gRunning) return;
  [self togglePlay:YES];
}

- (void)startDebugDisplay {
  if (!self.debugWin) {
    self.debugWin = ac_window(1095, YES);
    self.debugWin.userInteractionEnabled = NO;
    UIView *box = [UIView new];
    box.layer.borderColor = [UIColor colorWithRed:0 green:1 blue:0 alpha:1].CGColor;
    box.layer.borderWidth = 5;
    [self.debugWin.rootViewController.view addSubview:box];
    self.debugBox = box;
  }
  self.debugWin.hidden = YES;
  [self.debugTimer invalidate];
  __weak ACOverlay *ws = self;
  self.debugTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) { [ws updateDebug]; }];
}

- (void)stopDebugDisplay {
  [self.debugTimer invalidate];
  self.debugTimer = nil;
  self.debugWin.hidden = YES;
}

- (void)updateDebug {
  NSDictionary *d = ac_debugInfo();
  if (!d) return;
  if (d[@"event"]) self.dbgEvent.text = d[@"event"];
  if (d[@"condition"]) self.dbgCond.text = d[@"condition"];
  if (d[@"confidence"]) self.dbgConf.text = [NSString stringWithFormat:@"%.2f %%", [d[@"confidence"] doubleValue]];
  if (d[@"current"]) self.dbgCurrent.text = [NSString stringWithFormat:@"%.2f %%", [d[@"current"] doubleValue]];
  CGRect r = [d[@"rect"] CGRectValue];
  if (CGRectIsEmpty(r)) { self.debugWin.hidden = YES; return; }
  CGFloat pad = 10.0 / MAX(1, [UIScreen mainScreen].scale);
  UIView *host = self.debugWin.rootViewController.view;
  CGPoint o = ac_unfixed(host, r.origin), e = ac_unfixed(host, CGPointMake(CGRectGetMaxX(r), CGRectGetMaxY(r)));
  CGRect v = CGRectMake(MIN(o.x, e.x), MIN(o.y, e.y), fabs(e.x - o.x), fabs(e.y - o.y));
  self.debugBox.frame = CGRectInset(v, -pad - 5, -pad - 5);
  self.debugWin.hidden = NO;
}

- (void)dragMenu:(UIPanGestureRecognizer *)g {
  UIView *root = ac_root(self.menuWin), *panel = self.menuPanel;
  CGPoint t = [g translationInView:root];
  CGSize sb = root.bounds.size, sz = panel.bounds.size;
  CGPoint o = self.menuOrigin;
  o.x = MAX(0, MIN(o.x + t.x, sb.width - sz.width));
  o.y = MAX(0, MIN(o.y + t.y, sb.height - sz.height));
  self.menuOrigin = o;
  panel.frame = CGRectMake(o.x, o.y, sz.width, sz.height);
  [g setTranslation:CGPointZero inView:root];
  if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
    [[NSFileManager defaultManager] createDirectoryAtPath:AC_DIR withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *path = [AC_DIR stringByAppendingPathComponent:@"menu.plist"];
    NSMutableDictionary *pos = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary new];
    BOOL land = sb.width > sb.height;
    pos[land ? @"lx" : @"x"] = @(o.x);
    pos[land ? @"ly" : @"y"] = @(o.y);
    [pos writeToFile:path atomically:YES];
  }
}

#pragma mark Orientation

- (void)startOrientationWatch {
  if (!self.menuWin) self.menuWin = ac_window(1100, YES);
  self.rot = ac_contentAngle();
  self.space = ac_spaceSize();
  [self.orientTimer invalidate];
  __weak ACOverlay *ws = self;
  self.orientTimer = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *t) { [ws checkOrientation]; }];
  [[NSRunLoop mainRunLoop] addTimer:self.orientTimer forMode:NSRunLoopCommonModes];
}

- (void)checkOrientation {
  static int tick;
  if (++tick % 8 == 0) {
    UIUserInterfaceStyle st = SCSystemStyle();
    for (UIWindow *w in @[ self.menuWin ?: (id)[NSNull null], self.dialogWin ?: (id)[NSNull null], self.pickWin ?: (id)[NSNull null] ])
      if ([w isKindOfClass:[UIWindow class]] && w.overrideUserInterfaceStyle != st) w.overrideUserInterfaceStyle = st;
  }
  double a = ac_contentAngle();
  CGSize sp = ac_spaceSize();
  if (fabs(a - self.rot) < 0.01 && CGSizeEqualToSize(sp, self.space)) return;
  self.space = sp;
  self.menuPlaced = NO;
  self.rot = a;
  if (self.menuWin && !self.menuWin.hidden) [self buildMenu:self.menuMode];
  if (self.dialogWin && !self.dialogWin.hidden) {
    ac_orientRoot(ac_root(self.dialogWin), a);
    [self.host relayout];
  }
  UIView *pr = ac_root(self.pickWin);
  if (self.pickWin && [pr.subviews.firstObject isKindOfClass:[ACPointPicker class]]) ac_orientRoot(pr, a);
}

- (void)refreshPlay {
  ACPlayPauseView *pp = self.playIcon;
  [pp setPlaying:gRunning animated:YES];
  [UIView animateWithDuration:0.175 animations:^{ self.listButton.alpha = gRunning ? 0.4 : 1; }];
}

#pragma mark Show / hide / play

- (void)show {
  self.wanted = YES;
  if (!self.ready) return;
  ac_load();
  if (self.host.count) { SCAction e = self.host.onEmpty; self.host.onEmpty = nil; [self.host popAll]; self.host.onEmpty = e; }
  self.dialogWin.hidden = YES;
  self.pickWin.hidden = YES;
  self.pickWin = nil;
  [self startOrientationWatch];
  [self buildMenu:0];
}

- (void)hide {
  self.wanted = NO;
  gRunning = false;
  gDebug = false;
  [self stopDebugDisplay];
  [self.orientTimer invalidate];
  self.orientTimer = nil;
  UIWindow *mw = self.menuWin;
  UIView *panel = self.menuPanel;
  [UIView animateWithDuration:0.15 animations:^{
    mw.alpha = 0;
    panel.transform = CGAffineTransformMakeScale(0.85, 0.85);
  } completion:^(BOOL fin) {
    if (mw.alpha < 0.01) mw.hidden = YES;
    panel.transform = CGAffineTransformIdentity;
  }];
  self.pickWin.hidden = YES;
  self.pickWin = nil;
  [self freeFrame];
  self.host.onEmpty = nil;
  [self.host popAll];
  self.dialogWin.hidden = YES;
  self.host = nil;
  self.dialogWin = nil;
}

- (void)stopClicker {
  [self hide];
}

- (void)togglePlay:(BOOL)debug {
  if (gRunning) { gRunning = false; [self refreshPlay]; return; }
  ac_load();
  NSDictionary *sc = ac_mutableDeep(ac_current());
  if ([sc[@"events"] count] == 0) { [self openEventList]; return; }
  gDebug = debug;
  gRunning = true;
  if (debug) { [self buildMenu:0]; [self startDebugDisplay]; }
  [self refreshPlay];
  NSThread *t = [[NSThread alloc] initWithBlock:^{ ac_play(sc); }];
  t.qualityOfService = NSQualityOfServiceUserInteractive; // otherwise passes get throttled
  [t start];
}

#pragma mark Dialog plumbing

- (void)push:(SCDialog *)d {
  if (!self.dialogWin) {
    self.dialogWin = ac_window(1090, NO);
    UIView *root = ac_root(self.dialogWin);
    root.backgroundColor = SCRGB(0x99000000);
    self.host = [[SCDialogHost alloc] initWithContainer:root];
    __weak ACOverlay *ws = self;
    self.host.onEmpty = ^{
      ws.dialogWin.hidden = YES;
      [ws.dialogWin resignKeyWindow];
      if (ws.wanted) [ws buildMenu:0];
    };
  }
  self.menuWin.hidden = YES;
  if (!self.host.count) ac_orientRoot(ac_root(self.dialogWin), self.rot);
  self.dialogWin.overrideUserInterfaceStyle = SCSystemStyle();
  [self.dialogWin makeKeyAndVisible];
  [self.host push:d];
}

- (void)suspendDialogs { [self.dialogWin endEditing:YES]; self.dialogWin.hidden = YES; }
- (void)resumeDialogs {
  self.pickWin.hidden = YES;
  self.pickWin = nil;
  if (self.host.count) {
    self.menuWin.hidden = YES;
    ac_orientRoot(ac_root(self.dialogWin), self.rot);
    [self.dialogWin makeKeyAndVisible];
    [self.host relayout];
  }
  else [self buildMenu:0];
}

- (void)pickPosition:(BOOL)swipe done:(void (^)(CGPoint a, CGPoint b))done {
  [self suspendDialogs];
  self.pickWin = ac_window(1080, NO);
  ac_orientRoot(ac_root(self.pickWin), self.rot);
  ACPointPicker *p = [[ACPointPicker alloc] initWithFrame:ac_root(self.pickWin).bounds swipe:swipe];
  p.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [ac_root(self.pickWin) addSubview:p];
  self.pickWin.hidden = NO;
  __weak ACOverlay *ws = self;
  __weak ACPointPicker *wp = p;
  self.menuCancel = ^{ [ws resumeDialogs]; };
  self.menuConfirm = ^{
    if (![wp done]) return;
    CGPoint a = ac_fixed(wp, wp.a), bb = ac_fixed(wp, wp.b);
    [ws resumeDialogs];
    done(a, bb);
  };
  [self buildMenu:1];
}

- (void)captureCondition:(void (^)(NSMutableDictionary *cond))done {
  [self suspendDialogs];
  __weak ACOverlay *ws = self;
  self.menuCancel = ^{ [ws freeFrame]; [ws resumeDialogs]; };
  self.menuCapture = ^{ [ws grabFrameThen:done]; };
  [self buildMenu:2];
}

- (void)freeFrame { free(_frame); _frame = NULL; }

- (void)grabFrameThen:(void (^)(NSMutableDictionary *cond))done {
  self.menuWin.hidden = YES;
  ac_after(0.25, ^{
    [self freeFrame];
    size_t bytes = (size_t)gNativeW * gNativeH * 4;
    uint8_t *buf = (uint8_t *)malloc(bytes);
    bool ok = ac_withScreen(^(const uint8_t *base, size_t bpr) {
      for (int y = 0; y < gNativeH; y++) memcpy(buf + (size_t)y * gNativeW * 4, base + (size_t)y * bpr, (size_t)gNativeW * 4);
    });
    if (!ok) { free(buf); self.menuWin.hidden = NO; return; }
    self->_frame = buf;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(buf, gNativeW, gNativeH, 8, gNativeW * 4, cs, AC_BGRA_INFO);
    CGImageRef cg = CGBitmapContextCreateImage(ctx);
    UIImage *img = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    CGContextRelease(ctx);
    CGColorSpaceRelease(cs);

    self.pickWin = ac_window(1080, NO);
    UIView *root = ac_root(self.pickWin);
    ac_orientRoot(root, self.rot);
    ACAreaPicker *p = [[ACAreaPicker alloc] initWithFrame:root.bounds image:ac_upright(img, ac_imageAngle())];
    [root addSubview:p];
    CGPoint o = ac_unfixed(p, CGPointZero), e = ac_unfixed(p, CGPointMake(gFixedSize.width, gFixedSize.height));
    p.capture = CGRectMake(MIN(o.x, e.x), MIN(o.y, e.y), fabs(e.x - o.x), fabs(e.y - o.y));
    [p redraw];
    self.pickWin.hidden = NO;
    __weak ACOverlay *ws = self;
    __weak ACAreaPicker *wp = p;
    self.menuCancel = ^{ [ws freeFrame]; [ws resumeDialogs]; };
    self.menuConfirm = ^{
      NSMutableDictionary *c = [ws saveAreaFrom:wp];
      [ws freeFrame];
      [ws resumeDialogs];
      if (c) done(c);
    };
    [self buildMenu:1];
  });
}

- (NSMutableDictionary *)saveAreaFrom:(ACAreaPicker *)p {
  if (!_frame || !p) return nil;
  CGRect sel = [p selection];
  if (CGRectIsNull(sel) || sel.size.width < 1 || sel.size.height < 1) return nil;
  CGPoint a = ac_fixed(p, sel.origin), b = ac_fixed(p, CGPointMake(CGRectGetMaxX(sel), CGRectGetMaxY(sel)));
  CGRect r = CGRectMake(MIN(a.x, b.x), MIN(a.y, b.y), fabs(b.x - a.x), fabs(b.y - a.y));
  int x = (int)floor(r.origin.x * gNativeScale / AC_COARSE) * AC_COARSE;
  int y = (int)floor(r.origin.y * gNativeScale / AC_COARSE) * AC_COARSE;
  int w = MAX(32, (int)round(r.size.width * gNativeScale / AC_COARSE) * AC_COARSE);
  int h = MAX(32, (int)round(r.size.height * gNativeScale / AC_COARSE) * AC_COARSE);
  x = MAX(0, x);
  y = MAX(0, y);
  if (x + w > gNativeW) w = (gNativeW - x) / AC_COARSE * AC_COARSE;
  if (y + h > gNativeH) h = (gNativeH - y) / AC_COARSE * AC_COARSE;
  uint8_t *crop = (uint8_t *)malloc((size_t)w * h * 4);
  for (int yy = 0; yy < h; yy++) memcpy(crop + (size_t)yy * w * 4, _frame + ((size_t)(y + yy) * gNativeW + x) * 4, (size_t)w * 4);
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGContextRef ctx = CGBitmapContextCreate(crop, w, h, 8, w * 4, cs, AC_BGRA_INFO);
  CGImageRef img = CGBitmapContextCreateImage(ctx);
  NSString *cid = ac_newId();
  [[NSFileManager defaultManager] createDirectoryAtPath:AC_DIR withIntermediateDirectories:YES attributes:nil error:NULL];
  BOOL saved = img && [UIImagePNGRepresentation([UIImage imageWithCGImage:img]) writeToFile:ac_condPath(cid) atomically:YES];
  if (img) CGImageRelease(img);
  CGContextRelease(ctx);
  CGColorSpaceRelease(cs);
  free(crop);
  if (!saved) return nil;
  return ac_mutableDeep(@{ @"id" : cid, @"name" : @"Condition", @"x" : @(x), @"y" : @(y), @"w" : @(w), @"h" : @(h),
                           @"tol" : @8, @"whole" : @NO, @"detect" : @YES });
}

#pragma mark Helpers

- (void)rememberWait:(NSDictionary *)a deleted:(BOOL)del {
  if (del || ![a[@"t"] isEqualToString:@"pause"] || !a[@"d"]) return;
  gRoot[@"lastWait"] = a[@"d"];
  ac_save();
}

- (UIView *)centerText:(NSString *)t {
  UILabel *l = SCLabel(t, 16, NO, SC_TEXT);
  l.textAlignment = NSTextAlignmentCenter;
  l.numberOfLines = 0;
  [l.heightAnchor constraintGreaterThanOrEqualToConstant:48].active = YES;
  return l;
}

- (UITextField *)field:(NSString *)text hint:(NSString *)hint numeric:(BOOL)num changed:(void (^)(NSString *))changed {
  UITextField *f = SCTextField(text, hint, num);
  __weak UITextField *wf = f;
  [f addAction:[UIAction actionWithHandler:^(UIAction *a) {
    static NSSet *defaults;
    if (!defaults) defaults = [NSSet setWithArray:@[ @"Default event", @"Event", @"Condition", @"Click", @"Swipe", @"Wait", @"Pause", @"Open app" ]];
    if (num || ![defaults containsObject:wf.text]) return;
    dispatch_async(dispatch_get_main_queue(), ^{ [wf selectAll:nil]; });
  }] forControlEvents:UIControlEventEditingDidBegin];
  [f addAction:[UIAction actionWithHandler:^(UIAction *a) { changed(wf.text ?: @""); }] forControlEvents:UIControlEventEditingChanged];
  return f;
}

- (NSMutableDictionary *)cloneCondition:(NSDictionary *)c {
  NSMutableDictionary *n = ac_mutableDeep(c);
  n[@"id"] = ac_newId();
  [[NSFileManager defaultManager] copyItemAtPath:ac_condPath(c[@"id"]) toPath:ac_condPath(n[@"id"]) error:NULL];
  return n;
}

- (NSMutableDictionary *)cloneEvent:(NSDictionary *)e {
  NSMutableDictionary *n = ac_mutableDeep(e);
  n[@"id"] = ac_newId();
  NSMutableArray *conds = [NSMutableArray new];
  for (NSDictionary *c in e[@"conditions"]) [conds addObject:[self cloneCondition:c]];
  n[@"conditions"] = conds;
  return n;
}

- (NSString *)actionDetails:(NSDictionary *)a {
  NSString *t = a[@"t"];
  if ([t isEqualToString:@"pause"]) return [NSString stringWithFormat:@"During %@ ms", a[@"d"]];
  if ([t isEqualToString:@"app"]) return [a[@"appName"] length] ? [NSString stringWithFormat:@"Open %@", a[@"appName"]] : @"No application selected";
  if ([t isEqualToString:@"swipe"])
    return [NSString stringWithFormat:@"During %@ ms from [%@, %@] to [%@, %@]", a[@"d"], AC_px([a[@"x"] doubleValue]),
                                      AC_px([a[@"y"] doubleValue]), AC_px([a[@"x2"] doubleValue]), AC_px([a[@"y2"] doubleValue])];
  if ([a[@"onCond"] boolValue]) return [NSString stringWithFormat:@"During %@ ms on condition", a[@"d"]];
  return [NSString stringWithFormat:@"During %@ ms at [%@, %@]", a[@"d"], AC_px([a[@"x"] doubleValue]), AC_px([a[@"y"] doubleValue])];
}

// sections: @[header, @[ @[icon, title, detail, block] ]]
- (SCDialog *)copyDialog:(NSArray *)sections empty:(NSString *)empty {
  return [self listDialog:@"Copy from" icon:@"ic_copy" sections:sections empty:empty];
}

- (SCDialog *)listDialog:(NSString *)title icon:(NSString *)titleIcon sections:(NSArray *)sections empty:(NSString *)empty {
  BOOL apps = [titleIcon isEqualToString:@"ic_intent"];
  SCDialog *d = [[SCDialog alloc] initWithTitle:title icon:titleIcon];
  d.fillHeight = YES;
  __weak SCDialog *wd = d;
  BOOL any = NO;
  NSMutableArray<NSArray *> *rows = [NSMutableArray new];
  NSMutableArray<NSArray *> *heads = [NSMutableArray new];
  UITextField *search = SCTextField(@"", @"Search by name", NO);
  UIImageView *mag = SCIconView(@"ic_search", 22, SC_HINT);
  UIView *sw = [UIView new];
  [sw addSubview:mag];
  [sw addSubview:search];
  [NSLayoutConstraint activateConstraints:@[
    [mag.leadingAnchor constraintEqualToAnchor:sw.leadingAnchor constant:16], [mag.centerYAnchor constraintEqualToAnchor:search.centerYAnchor],
    [search.leadingAnchor constraintEqualToAnchor:mag.trailingAnchor constant:12], [search.trailingAnchor constraintEqualToAnchor:sw.trailingAnchor constant:-16],
    [search.topAnchor constraintEqualToAnchor:sw.topAnchor constant:4], [search.bottomAnchor constraintEqualToAnchor:sw.bottomAnchor],
  ]];
  [d.content addArrangedSubview:sw];
  [d.content addArrangedSubview:SCSeparator()];
  __weak UITextField *wsearch = search;
  [search addAction:[UIAction actionWithHandler:^(UIAction *ac) {
    NSString *q = [wsearch.text.lowercaseString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    for (NSArray *hs in heads) {
      BOOL anyShown = NO;
      for (NSArray *r in hs[1]) {
        BOOL show = !q.length || [r[1] containsString:q];
        ((UIView *)r[0]).hidden = !show;
        anyShown |= show;
      }
      ((UIView *)hs[0]).hidden = !anyShown;
    }
  }] forControlEvents:UIControlEventEditingChanged];
  for (NSArray *sec in sections) {
    NSArray *items = sec[1];
    if (!items.count) continue;
    any = YES;
    UILabel *h = SCLabel(sec[0], 14, YES, SC_PRIMARY);
    UIView *hw = [UIView new];
    [hw addSubview:h];
    [NSLayoutConstraint activateConstraints:@[
      [h.leadingAnchor constraintEqualToAnchor:hw.leadingAnchor constant:16], [h.topAnchor constraintEqualToAnchor:hw.topAnchor constant:12],
      [h.bottomAnchor constraintEqualToAnchor:hw.bottomAnchor constant:-4],
    ]];
    [d.content addArrangedSubview:hw];
    NSMutableArray *secRows = [NSMutableArray new];
    [heads addObject:@[ hw, secRows ]];
    for (NSArray *it in items) {
      SCAction blk = it[3];
      SCTap *row = [SCTap tap:^{ [wd close]; blk(); }];
      [secRows addObject:@[ row, [it[1] lowercaseString] ?: @"" ]];
      [rows addObject:secRows.lastObject];
      row.translatesAutoresizingMaskIntoConstraints = NO;
      UIView *icon;
      if ([it[0] isKindOfClass:[UIImage class]]) {
        UIImageView *iv = [[UIImageView alloc] initWithImage:it[0]];
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.backgroundColor = apps ? [UIColor clearColor] : [UIColor blackColor];
        iv.translatesAutoresizingMaskIntoConstraints = NO;
        [iv.widthAnchor constraintEqualToConstant:apps ? 48 : 44].active = YES;
        [iv.heightAnchor constraintEqualToConstant:apps ? 48 : 44].active = YES;
        icon = iv;
      } else icon = SCIconView(it[0], 28, nil);
      UILabel *t = SCLabel(it[1], 17, YES, SC_TEXT);
      UILabel *s = SCLabel(it[2], 14, NO, SC_HINT);
      s.font = [UIFont italicSystemFontOfSize:14];
      s.numberOfLines = 0;
      s.hidden = ![it[2] length];
      UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[ t, s ]];
      texts.axis = UILayoutConstraintAxisVertical;
      UIStackView *st = [[UIStackView alloc] initWithArrangedSubviews:@[ icon, texts ]];
      st.spacing = 12;
      st.alignment = UIStackViewAlignmentCenter;
      st.userInteractionEnabled = NO;
      st.translatesAutoresizingMaskIntoConstraints = NO;
      [row addSubview:st];
      [NSLayoutConstraint activateConstraints:@[
        [st.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16], [st.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16],
        [st.topAnchor constraintEqualToAnchor:row.topAnchor constant:8], [st.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-8],
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:62],
      ]];
      [d.content addArrangedSubview:row];
    }
  }
  if (!any) { [d.content addArrangedSubview:[self centerText:empty]]; d.fillHeight = NO; sw.hidden = YES; }
  [d addButton:@"Cancel" left:NO action:^{ [wd close]; }];
  return d;
}

#pragma mark Event list (dialog_event_list)

- (void)openEventList {
  ac_load();
  self.edit = ac_mutableDeep(ac_current());
  SCDialog *d = [[SCDialog alloc] initWithTitle:@"Event list" icon:@"ic_click_list"];
  d.fillHeight = YES;
  self.eventTable = [ACEventTable new];
  self.eventTable.events = self.edit[@"events"];
  __weak ACOverlay *ws = self;
  self.eventTable.select = ^(NSInteger i) { [ws openEvent:ws.edit[@"events"][i] isNew:NO]; };
  [d setBody:self.eventTable.table];
  [self normalBar:d];
  d.onShow = ^{ [ws.eventTable reload]; };
  [self push:d];
}

- (void)normalBar:(SCDialog *)d {
  __weak ACOverlay *ws = self;
  __weak SCDialog *wd = d;
  [d setIconBar:SCIconBar(
                    @[
                      @[ @"ic_add", ^{ [ws newEvent]; } ],
                      @[ @"ic_copy", ^{ [ws copyEvent]; } ],
                      @[ @"ic_reorder", ^{ [ws reorder:wd]; } ],
                      @[ @"ic_settings", ^{ [ws openSettings]; } ],
                    ],
                    @[ @[ @"ic_confirm", ^{ [ws saveEdit]; [wd close]; } ] ])];
}

- (void)reorder:(SCDialog *)d {
  if (![self.edit[@"events"] count]) return;
  NSArray *backup = [self.edit[@"events"] copy];
  [self.eventTable.table setEditing:YES animated:YES];
  __weak ACOverlay *ws = self;
  __weak SCDialog *wd = d;
  [d setIconBar:SCIconBar(@[], @[
       @[ @"ic_cancel", ^{
         [ws.edit[@"events"] setArray:backup];
         [ws.eventTable.table setEditing:NO animated:YES];
         [ws.eventTable reload];
         [ws normalBar:wd];
       } ],
       @[ @"ic_confirm", ^{
         [ws.eventTable.table setEditing:NO animated:YES];
         [ws.eventTable reload];
         [ws normalBar:wd];
       } ]
     ])];
}

- (void)saveEdit {
  if (!self.edit) return;
  ac_load();
  NSMutableArray *all = ac_scenarios();
  BOOL found = NO;
  for (NSUInteger i = 0; i < all.count; i++)
    if ([all[i][@"id"] isEqual:self.edit[@"id"]]) { all[i] = self.edit; found = YES; break; }
  if (!found) { [all addObject:self.edit]; gRoot[@"selected"] = @(all.count - 1); }
  ac_save();
}

- (void)newEvent {
  NSMutableDictionary *e = ac_mutableDeep(@{ @"id" : ac_newId(), @"name" : @"Default event", @"all" : @YES, @"conditions" : @[], @"actions" : @[] });
  [self openEvent:e isNew:YES];
}

- (void)copyEvent {
  NSMutableArray *mine = [NSMutableArray new], *others = [NSMutableArray new];
  __weak ACOverlay *ws = self;
  for (NSDictionary *e in self.edit[@"events"]) {
    NSString *det = [NSString stringWithFormat:@"%lu conditions, %lu actions", (unsigned long)[e[@"conditions"] count], (unsigned long)[e[@"actions"] count]];
    [mine addObject:@[ @"ic_click_list", e[@"name"], det, ^{ [ws openEvent:[ws cloneEvent:e] isNew:YES]; } ]];
  }
  for (NSDictionary *sc in ac_scenarios()) {
    if ([sc[@"id"] isEqual:self.edit[@"id"]]) continue;
    for (NSDictionary *e in sc[@"events"]) {
      NSString *det = [NSString stringWithFormat:@"%@ · %lu conditions, %lu actions", sc[@"name"], (unsigned long)[e[@"conditions"] count],
                                                 (unsigned long)[e[@"actions"] count]];
      [others addObject:@[ @"ic_click_list", e[@"name"], det, ^{ [ws openEvent:[ws cloneEvent:e] isNew:YES]; } ]];
    }
  }
  [self push:[self copyDialog:@[ @[ @"Events from this scenario", mine ], @[ @"Events from all scenarios", others ] ] empty:@"No events found."]];
}

#pragma mark Event configuration (dialog_event_config)

- (void)openEvent:(NSMutableDictionary *)original isNew:(BOOL)isNew {
  NSMutableDictionary *ev = ac_mutableDeep(original);
  SCDialog *d = [[SCDialog alloc] initWithTitle:@"Event configuration" icon:@"ic_click_list"];
  d.fillHeight = YES;
  __weak ACOverlay *ws = self;
  __weak SCDialog *wd = d;
  __block UIButton *okButton;
  void (^rebuild)(void);
  __block __weak void (^weakRebuild)(void);
  void (^validate)(void) = ^{ okButton.enabled = [ev[@"name"] length] > 0 && [ev[@"actions"] count] > 0; };
  rebuild = ^{
    SCDialog *dd = wd;
    if (!dd) return;
    for (UIView *v in [dd.content.arrangedSubviews copy]) [v removeFromSuperview];
    [dd.content addArrangedSubview:SCCard(@"Name", @[ [ws field:ev[@"name"] hint:@"Name" numeric:NO changed:^(NSString *t) {
                                            ev[@"name"] = t;
                                            validate();
                                          }] ])];
    NSMutableArray *ccards = [NSMutableArray new];
    NSMutableArray *conds = ev[@"conditions"];
    for (NSUInteger i = 0; i < conds.count; i++) {
      NSDictionary *c = conds[i];
      [ccards addObject:SCConditionCard(ac_upright([UIImage imageWithContentsOfFile:ac_condPath(c[@"id"])], ac_imageAngle()), [c[@"detect"] boolValue], [c[@"whole"] boolValue], ^{
        [ws openCondition:conds[i] isNew:NO done:^(NSMutableDictionary *nc, BOOL del) {
          if (del) [conds removeObjectAtIndex:i]; else conds[i] = nc;
          weakRebuild();
        }];
      })];
    }
    [ccards addObject:SCNewCopyCard(^{
      [ws captureCondition:^(NSMutableDictionary *nc) {
        [ws openCondition:nc isNew:YES done:^(NSMutableDictionary *c2, BOOL del) { if (!del) [conds addObject:c2]; weakRebuild(); }];
      }];
    }, ^{
      [ws copyConditionInto:ev done:^(NSMutableDictionary *nc) {
        [ws openCondition:nc isNew:YES done:^(NSMutableDictionary *c2, BOOL del) { if (!del) [conds addObject:c2]; weakRebuild(); }];
      }];
    })];
    BOOL all = [ev[@"all"] boolValue];
    SCTap *op = SCItemRow(nil, all ? @"All conditions are fulfilled" : @"At least one is fulfilled", YES, ^{
      [ws push:SCChoiceDialog(@"Conditions type", nil, @[ @[ @"ic_all_conditions", @"All conditions" ], @[ @"ic_one_condition", @"Only one condition" ] ],
                              ^(NSInteger idx) { ev[@"all"] = @(idx == 0); weakRebuild(); })];
    });
    UIView *clist = SCReorderableList(ccards, conds.count, ^(NSUInteger from, NSUInteger to) {
      id o = conds[from];
      [conds removeObjectAtIndex:from];
      [conds insertObject:o atIndex:to];
      weakRebuild();
    });
    [dd.content addArrangedSubview:SCCard(@"Conditions", @[ op, SCSeparator(), clist ])];
    NSMutableArray *acards = [NSMutableArray new];
    NSMutableArray *acts = ev[@"actions"];
    for (NSUInteger i = 0; i < acts.count; i++) {
      NSDictionary *a = acts[i];
      [acards addObject:SCActionCard(ac_actionIcon(a[@"t"]), a[@"name"], ^{
        [ws openAction:acts[i] event:ev isNew:NO done:^(NSMutableDictionary *na, BOOL del) {
          if (del) [acts removeObjectAtIndex:i]; else acts[i] = na;
          [ws rememberWait:na deleted:del];
          weakRebuild();
        }];
      })];
    }
    [acards addObject:SCNewCopyCard(^{
      [ws push:SCChoiceDialog(@"Action type", @"ic_add", @[ @[ @"ic_click", @"Click" ], @[ @"ic_swipe", @"Swipe" ], @[ @"ic_wait", @"Wait" ], @[ @"ic_intent", @"Open app" ] ], ^(NSInteger idx) {
        NSArray *defs = @[
          @{ @"name" : @"Click", @"t" : @"click", @"d" : @1, @"unset" : @YES },
          @{ @"name" : @"Swipe", @"t" : @"swipe", @"d" : @250, @"unset" : @YES },
          @{ @"name" : @"Wait", @"t" : @"pause", @"d" : gRoot[@"lastWait"] ?: @1000 },
          @{ @"name" : @"Open app", @"t" : @"app" },
        ];
        [ws openAction:ac_mutableDeep(defs[idx]) event:ev isNew:YES done:^(NSMutableDictionary *na, BOOL del) {
          if (!del) [acts addObject:na];
          [ws rememberWait:na deleted:del];
          weakRebuild();
        }];
      })];
    }, ^{
      [ws copyActionInto:ev done:^(NSMutableDictionary *na) {
        [ws openAction:na event:ev isNew:YES done:^(NSMutableDictionary *a2, BOOL del) { if (!del) [acts addObject:a2]; weakRebuild(); }];
      }];
    })];
    UIView *alist = SCReorderableList(acards, acts.count, ^(NSUInteger from, NSUInteger to) {
      id o = acts[from];
      [acts removeObjectAtIndex:from];
      [acts insertObject:o atIndex:to];
      weakRebuild();
    });
    [dd.content addArrangedSubview:SCCard(@"Actions", @[ alist ])];
    validate();
  };
  weakRebuild = rebuild;
  objc_setAssociatedObject(d, "rebuild", rebuild, OBJC_ASSOCIATION_COPY);
  weakRebuild = objc_getAssociatedObject(d, "rebuild");
  if (!isNew)
    [d addButton:@"Delete" left:YES action:^{
      NSMutableArray *evs = ws.edit[@"events"];
      for (NSUInteger i = 0; i < evs.count; i++) if ([evs[i][@"id"] isEqual:ev[@"id"]]) { [evs removeObjectAtIndex:i]; break; }
      NSMutableArray *ends = ws.edit[@"endConditions"];
      for (NSInteger i = (NSInteger)ends.count - 1; i >= 0; i--) if ([ends[i][@"event"] isEqual:ev[@"id"]]) [ends removeObjectAtIndex:i];
      [wd close];
    }];
  [d addButton:@"Cancel" left:NO action:^{ [wd close]; }];
  okButton = [d addButton:@"OK" left:NO action:^{
    NSMutableArray *evs = ws.edit[@"events"];
    BOOL found = NO;
    for (NSUInteger i = 0; i < evs.count; i++) if ([evs[i][@"id"] isEqual:ev[@"id"]]) { evs[i] = ev; found = YES; break; }
    if (!found) [evs addObject:ev];
    [wd close];
  }];
  weakRebuild();
  [self push:d];
}

- (void)copyConditionInto:(NSDictionary *)ev done:(void (^)(NSMutableDictionary *))done {
  NSMutableArray *mine = [NSMutableArray new], *others = [NSMutableArray new];
  __weak ACOverlay *ws = self;
  void (^add)(NSMutableArray *, NSDictionary *, NSString *) = ^(NSMutableArray *list, NSDictionary *c, NSString *where) {
    UIImage *img = ac_upright([UIImage imageWithContentsOfFile:ac_condPath(c[@"id"])], ac_imageAngle()) ?: SCIcon(@"ic_screenshot");
    NSString *det = [NSString stringWithFormat:@"%@%@ · %@%%", where ?: @"", [c[@"detect"] boolValue] ? @"Visible" : @"Not visible", c[@"tol"]];
    [list addObject:@[ img, c[@"name"], det, ^{ done([ws cloneCondition:c]); } ]];
  };
  for (NSDictionary *c in ev[@"conditions"]) add(mine, c, nil);
  for (NSDictionary *sc in ac_scenarios())
    for (NSDictionary *e in ([sc[@"id"] isEqual:self.edit[@"id"]] ? self.edit : sc)[@"events"])
      if (![e[@"id"] isEqual:ev[@"id"]])
        for (NSDictionary *c in e[@"conditions"]) add(others, c, [NSString stringWithFormat:@"%@ · ", e[@"name"]]);
  [self push:[self copyDialog:@[ @[ @"Conditions from this event", mine ], @[ @"Conditions from all events", others ] ]
                        empty:@"Can't copy, you don't have any conditions."]];
}

- (void)copyActionInto:(NSDictionary *)ev done:(void (^)(NSMutableDictionary *))done {
  NSMutableArray *mine = [NSMutableArray new], *others = [NSMutableArray new];
  for (NSDictionary *a in ev[@"actions"])
    [mine addObject:@[ ac_actionIcon(a[@"t"]), a[@"name"], [self actionDetails:a], ^{ done(ac_mutableDeep(a)); } ]];
  for (NSDictionary *sc in ac_scenarios())
    for (NSDictionary *e in ([sc[@"id"] isEqual:self.edit[@"id"]] ? self.edit : sc)[@"events"])
      if (![e[@"id"] isEqual:ev[@"id"]])
        for (NSDictionary *a in e[@"actions"])
          [others addObject:@[ ac_actionIcon(a[@"t"]), a[@"name"], [self actionDetails:a], ^{ done(ac_mutableDeep(a)); } ]];
  [self push:[self copyDialog:@[ @[ @"Actions from this event", mine ], @[ @"Actions from all events", others ] ] empty:@"No actions found."]];
}

#pragma mark Condition configuration (dialog_condition_config)

static void ac_setRowIcon(SCTap *row, NSString *icon) {
  UIStackView *st = (UIStackView *)row.subviews.firstObject;
  if ([st isKindOfClass:[UIStackView class]] && [st.arrangedSubviews.firstObject isKindOfClass:[UIImageView class]])
    ((UIImageView *)st.arrangedSubviews.firstObject).image = SCIcon(icon);
}

- (void)openCondition:(NSMutableDictionary *)original isNew:(BOOL)isNew done:(void (^)(NSMutableDictionary *c, BOOL deleted))done {
  NSMutableDictionary *c = ac_mutableDeep(original);
  SCDialog *d = [[SCDialog alloc] initWithTitle:@"Condition" icon:@"ic_screenshot"];
  d.fillHeight = YES;
  __weak SCDialog *wd = d;
  __block UIButton *ok;
  UITextField *name = [self field:c[@"name"] hint:@"Name" numeric:NO changed:^(NSString *t) { c[@"name"] = t; ok.enabled = t.length > 0; }];
  [d.content addArrangedSubview:SCCard(@"Name", @[ name ])];

  UIImageView *iv = [[UIImageView alloc] initWithImage:ac_upright([UIImage imageWithContentsOfFile:ac_condPath(c[@"id"])], ac_imageAngle())];
  iv.contentMode = UIViewContentModeScaleAspectFit;
  iv.translatesAutoresizingMaskIntoConstraints = NO;
  CGFloat ih = MIN(200, MAX(60, [c[@"h"] doubleValue] / gNativeScale));
  [iv.heightAnchor constraintEqualToConstant:ih].active = YES;
  __block __weak SCTap *detRow, *typeRow;
  void (^refresh)(void) = ^{
    BOOL det = [c[@"detect"] boolValue], whole = [c[@"whole"] boolValue];
    ((UILabel *)[detRow viewWithTag:1]).text = det ? @"Visible" : @"Not visible";
    ac_setRowIcon(detRow, det ? @"ic_confirm" : @"ic_cancel");
    ((UILabel *)[typeRow viewWithTag:1]).text = whole ? @"Anywhere on screen" : @"At the same position";
    ac_setRowIcon(typeRow, whole ? @"ic_detect_whole_screen" : @"ic_detect_exact");
  };
  SCTap *dr = SCItemRow(@"ic_confirm", @"", NO, ^{ c[@"detect"] = @(![c[@"detect"] boolValue]); refresh(); });
  SCTap *tr = SCItemRow(@"ic_detect_exact", @"", NO, ^{ c[@"whole"] = @(![c[@"whole"] boolValue]); refresh(); });
  detRow = dr;
  typeRow = tr;
  refresh();
  [d.content addArrangedSubview:SCCard(@"Detection details", @[ iv, dr, tr ])];

  UILabel *tolLabel = SCLabel([NSString stringWithFormat:@"Tolerance: %d %%", [c[@"tol"] intValue]], 16, NO, SC_TEXT);
  [tolLabel.heightAnchor constraintEqualToConstant:40].active = YES;
  UISlider *sl = [UISlider new];
  sl.minimumValue = 0;
  sl.maximumValue = 20;
  sl.value = [c[@"tol"] floatValue];
  sl.minimumTrackTintColor = SC_PRIMARY;
  sl.thumbTintColor = SC_PRIMARY;
  [sl.heightAnchor constraintEqualToConstant:48].active = YES;
  __weak UISlider *wsl = sl;
  __weak UILabel *wtl = tolLabel;
  [sl addAction:[UIAction actionWithHandler:^(UIAction *a) {
        int v = (int)round(wsl.value);
        c[@"tol"] = @(v);
        wtl.text = [NSString stringWithFormat:@"Tolerance: %d %%", v];
      }]
      forControlEvents:UIControlEventValueChanged];
  [d.content addArrangedSubview:SCCard(@"Tolerated difference", @[ tolLabel, sl ])];

  if (!isNew) [d addButton:@"Delete" left:YES action:^{ [wd close]; done(c, YES); }];
  [d addButton:@"Cancel" left:NO action:^{ [wd close]; }];
  ok = [d addButton:@"OK" left:NO action:^{ [wd close]; done(c, NO); }];
  ok.enabled = [c[@"name"] length] > 0;
  [self push:d];
}

#pragma mark Action configuration (dialog_action_config)

- (void)openAction:(NSMutableDictionary *)original event:(NSDictionary *)ev isNew:(BOOL)isNew
              done:(void (^)(NSMutableDictionary *a, BOOL deleted))done {
  NSMutableDictionary *a = ac_mutableDeep(original);
  NSString *t = a[@"t"];
  BOOL app = [t isEqualToString:@"app"];
  NSString *title = [t isEqualToString:@"pause"] ? @"Wait" : [t isEqualToString:@"swipe"] ? @"Swipe" : app ? @"Open app" : @"Click";
  SCDialog *d = [[SCDialog alloc] initWithTitle:title icon:ac_actionIcon(t)];
  d.fillHeight = YES;
  __weak SCDialog *wd = d;
  __weak ACOverlay *ws = self;
  __block UIButton *ok;
  void (^validate)(void) = ^{
    BOOL v = [a[@"name"] length] > 0 && (app ? [a[@"bundleId"] length] > 0 : [a[@"d"] integerValue] > 0 && ![a[@"unset"] boolValue]);
    ok.enabled = v;
  };
  UITextField *nameField = [self field:a[@"name"] hint:@"Name" numeric:NO changed:^(NSString *s) { a[@"name"] = s; validate(); }];
  objc_setAssociatedObject(d, "nameField", nameField, OBJC_ASSOCIATION_ASSIGN);
  [d.content addArrangedSubview:SCCard(@"Name", @[ nameField ])];
  if (app) {
    __block __weak SCTap *appRow;
    UIImageView *iv = [UIImageView new];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    [iv.widthAnchor constraintEqualToConstant:48].active = YES;
    [iv.heightAnchor constraintEqualToConstant:48].active = YES;
    __weak UIImageView *wiv = iv;
    void (^appText)(void) = ^{
      ((UILabel *)[appRow viewWithTag:1]).text = [a[@"appName"] length] ? a[@"appName"] : @"No application selected";
      wiv.image = ac_appIcon(a[@"bundleId"]);
      wiv.hidden = !wiv.image;
      validate();
    };
    SCTap *row = SCItemRow(nil, @"", YES, ^{
      NSMutableArray *items = [NSMutableArray new];
      for (NSArray *ap in ac_installedApps()) {
        UIImage *img = ac_appIcon(ap[0]);
        [items addObject:@[ img ?: @"ic_intent", ap[1], @"", ^{
          a[@"bundleId"] = ap[0];
          if ([a[@"appName"] length] == 0 || [a[@"name"] isEqualToString:a[@"appName"]] || [a[@"name"] isEqualToString:@"Open app"]) {
            a[@"name"] = ap[1];
            ((UITextField *)objc_getAssociatedObject(wd, "nameField")).text = ap[1];
          }
          a[@"appName"] = ap[1];
          appText();
        } ]];
      }
      [ws push:[ws listDialog:@"Select an application" icon:@"ic_intent" sections:@[ @[ @"Applications", items ] ] empty:@"No application detected"]];
    });
    appRow = row;
    for (UIView *v in row.subviews)
      if ([v isKindOfClass:[UIStackView class]]) { [(UIStackView *)v insertArrangedSubview:iv atIndex:0]; ((UIStackView *)v).spacing = 16; }
    [d.content addArrangedSubview:SCCard(@"Start application", @[ row ])];
    if (!isNew) [d addButton:@"Delete" left:YES action:^{ [wd close]; done(a, YES); }];
    [d addButton:@"Cancel" left:NO action:^{ [wd close]; }];
    ok = [d addButton:@"OK" left:NO action:^{ [wd close]; done(a, NO); }];
    appText();
    validate();
    [self push:d];
    return;
  }
  NSString *durTitle = [t isEqualToString:@"pause"] ? @"Pause duration" : [t isEqualToString:@"swipe"] ? @"Swipe duration" : @"Press duration";
  UITextField *dur = [self field:[a[@"d"] description] hint:@"ms" numeric:YES changed:^(NSString *s) { a[@"d"] = @([s integerValue]); validate(); }];
  [d.content addArrangedSubview:SCCard(durTitle, @[ dur ])];

  if (![t isEqualToString:@"pause"]) {
    BOOL swipe = [t isEqualToString:@"swipe"];
    __block __weak SCTap *posRow;
    void (^posText)(void) = ^{
      NSString *s;
      if ([a[@"unset"] boolValue]) s = swipe ? @"No swipe position defined" : @"No click position defined";
      else if ([a[@"onCond"] boolValue]) s = @"On condition";
      else if (swipe)
        s = [NSString stringWithFormat:@"Swipe from %@, %@ to %@, %@", AC_px([a[@"x"] doubleValue]), AC_px([a[@"y"] doubleValue]),
                                       AC_px([a[@"x2"] doubleValue]), AC_px([a[@"y2"] doubleValue])];
      else s = [NSString stringWithFormat:@"Click on %@, %@", AC_px([a[@"x"] doubleValue]), AC_px([a[@"y"] doubleValue])];
      ((UILabel *)[posRow viewWithTag:1]).text = s;
      validate();
    };
    void (^pick)(void) = ^{
      [ws pickPosition:swipe done:^(CGPoint p1, CGPoint p2) {
        a[@"x"] = @(p1.x);
        a[@"y"] = @(p1.y);
        if (swipe) { a[@"x2"] = @(p2.x); a[@"y2"] = @(p2.y); }
        [a removeObjectForKey:@"unset"];
        [a removeObjectForKey:@"onCond"];
        posText();
      }];
    };
    SCTap *pr = SCItemRow(nil, @"", YES, ^{
      if (!swipe && [ev[@"conditions"] count]) {
        [ws push:SCChoiceDialog(@"Click position", nil, @[ @[ [NSNull null], @"On position…" ], @[ [NSNull null], @"On condition" ] ], ^(NSInteger i) {
          if (i == 0) pick();
          else { a[@"onCond"] = @YES; [a removeObjectForKey:@"unset"]; posText(); }
        })];
      } else pick();
    });
    posRow = pr;
    [d.content addArrangedSubview:SCCard(swipe ? @"Swipe position" : @"Click position", @[ pr ])];
    if (!isNew) [d addButton:@"Delete" left:YES action:^{ [wd close]; done(a, YES); }];
    [d addButton:@"Cancel" left:NO action:^{ [wd close]; }];
    ok = [d addButton:@"OK" left:NO action:^{ [wd close]; done(a, NO); }];
    posText();
  } else {
    if (!isNew) [d addButton:@"Delete" left:YES action:^{ [wd close]; done(a, YES); }];
    [d addButton:@"Cancel" left:NO action:^{ [wd close]; }];
    ok = [d addButton:@"OK" left:NO action:^{ [wd close]; done(a, NO); }];
  }
  validate();
  [self push:d];
}

#pragma mark Scenario settings (dialog_scenario_settings)

- (void)openSettings {
  NSMutableDictionary *st = ac_mutableDeep(@{ @"detectionQuality" : self.edit[@"detectionQuality"] ?: @(AC_QUALITY_DEFAULT), @"endAll" : self.edit[@"endAll"] ?: @NO,
                                              @"endConditions" : self.edit[@"endConditions"] ?: @[] });
  SCDialog *d = [[SCDialog alloc] initWithTitle:@"Scenario Settings" icon:@"ic_settings"];
  d.fillHeight = YES;
  __weak SCDialog *wd = d;
  __weak ACOverlay *ws = self;
  void (^rebuild)(void);
  __block __weak void (^weakRebuild)(void);
  rebuild = ^{
    SCDialog *dd = wd;
    if (!dd) return;
    for (UIView *v in [dd.content.arrangedSubviews copy]) [v removeFromSuperview];
    // 0..800 seekbar -> 400..1200
    UILabel *val = SCLabel([st[@"detectionQuality"] stringValue], 16, YES, SC_TEXT);
    val.textAlignment = NSTextAlignmentCenter;
    UISlider *sl = [UISlider new];
    sl.minimumValue = AC_QUALITY_MIN;
    sl.maximumValue = AC_QUALITY_MAX;
    sl.value = [st[@"detectionQuality"] floatValue];
    sl.minimumTrackTintColor = SC_PRIMARY;
    sl.thumbTintColor = SC_PRIMARY;
    [sl.heightAnchor constraintEqualToConstant:48].active = YES;
    __weak UISlider *wsl = sl;
    __weak UILabel *wval = val;
    void (^setQ)(long, BOOL) = ^(long q, BOOL moveSlider) {
      q = MIN(AC_QUALITY_MAX, MAX(AC_QUALITY_MIN, q));
      st[@"detectionQuality"] = @(q);
      wval.text = [NSString stringWithFormat:@"%ld", q];
      if (moveSlider) wsl.value = q;
    };
    [sl addAction:[UIAction actionWithHandler:^(UIAction *x) { setQ(lround(wsl.value), NO); }] forControlEvents:UIControlEventValueChanged];
    UIButton *(^stepper)(NSString *, long) = ^UIButton *(NSString *title, long step) {
      UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
      [b setTitle:title forState:UIControlStateNormal];
      [b setTitleColor:SC_TEXT forState:UIControlStateNormal];
      b.titleLabel.font = [UIFont systemFontOfSize:16];
      [b addAction:[UIAction actionWithHandler:^(UIAction *x) { setQ([st[@"detectionQuality"] longValue] + step, YES); }]
          forControlEvents:UIControlEventTouchUpInside];
      return b;
    };
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ stepper(@"\u2039 Speed", -1), val, stepper(@"Precision \u203A", 1) ]];
    row.distribution = UIStackViewDistributionEqualCentering;
    row.alignment = UIStackViewAlignmentCenter;
    [row.heightAnchor constraintEqualToConstant:48].active = YES;
    [dd.content addArrangedSubview:SCCard(@"Detection quality", @[ row, SCSeparator(), sl ])];

    NSArray *events = ws.edit[@"events"];
    NSMutableArray *ends = st[@"endConditions"];
    if (!events.count) {
      [dd.content addArrangedSubview:SCCard(@"End conditions", @[ [ws centerText:@"No events available"] ])];
    } else {
      SCTap *op = SCItemRow(nil, [st[@"endAll"] boolValue] ? @"All conditions are fulfilled" : @"At least one is fulfilled", YES, ^{
        [ws push:SCChoiceDialog(@"Conditions type", nil, @[ @[ @"ic_all_conditions", @"All conditions" ], @[ @"ic_one_condition", @"Only one condition" ] ],
                                ^(NSInteger i) { st[@"endAll"] = @(i == 0); weakRebuild(); })];
      });
      NSMutableArray *cards = [NSMutableArray new];
      for (NSUInteger i = 0; i < ends.count; i++) {
        NSString *en = @"?";
        for (NSDictionary *e in events) if ([e[@"id"] isEqual:ends[i][@"event"]]) en = e[@"name"];
        [cards addObject:SCEndConditionCard(en, [ends[i][@"executions"] integerValue], ^{
          [ws openEndCondition:ends[i] all:ends isNew:NO done:^(NSMutableDictionary *ec, BOOL del) {
            if (del) [ends removeObjectAtIndex:i]; else ends[i] = ec;
            weakRebuild();
          }];
        })];
      }
      [cards addObject:SCNewCopyCard(^{
        [ws openEndCondition:ac_mutableDeep(@{ @"executions" : @1 }) all:ends isNew:YES done:^(NSMutableDictionary *ec, BOOL del) {
          if (!del) [ends addObject:ec];
          weakRebuild();
        }];
      }, nil)];
      [dd.content addArrangedSubview:SCCard(@"End conditions", @[ op, SCSeparator(), SCHorizontalList(cards) ])];
    }
  };
  objc_setAssociatedObject(d, "rebuild", rebuild, OBJC_ASSOCIATION_COPY);
  weakRebuild = objc_getAssociatedObject(d, "rebuild");
  [d addButton:@"Cancel" left:NO action:^{ [wd close]; }];
  [d addButton:@"OK" left:NO action:^{
    ws.edit[@"detectionQuality"] = st[@"detectionQuality"];
    [ws.edit removeObjectForKey:@"quality"];
    ws.edit[@"endAll"] = st[@"endAll"];
    ws.edit[@"endConditions"] = st[@"endConditions"];
    [wd close];
  }];
  weakRebuild();
  [self push:d];
}

- (void)openEndCondition:(NSMutableDictionary *)original all:(NSArray *)all isNew:(BOOL)isNew
                    done:(void (^)(NSMutableDictionary *ec, BOOL deleted))done {
  NSMutableDictionary *ec = ac_mutableDeep(original);
  SCDialog *d = [[SCDialog alloc] initWithTitle:@"End Condition" icon:@"ic_stop"];
  __weak SCDialog *wd = d;
  __weak ACOverlay *ws = self;
  __block UIButton *ok;
  __block __weak SCTap *evRow;
  void (^validate)(void) = ^{ ok.enabled = ec[@"event"] != nil && [ec[@"executions"] integerValue] > 0; };
  void (^evText)(void) = ^{
    NSString *s = @"No Event selected";
    for (NSDictionary *e in ws.edit[@"events"]) if ([e[@"id"] isEqual:ec[@"event"]]) s = e[@"name"];
    UILabel *l = (UILabel *)[evRow viewWithTag:1];
    l.text = s;
    l.font = ec[@"event"] ? [UIFont boldSystemFontOfSize:17] : [UIFont systemFontOfSize:16];
    validate();
  };
  SCTap *er = SCItemRow(nil, @"", YES, ^{
    NSMutableArray *items = [NSMutableArray new], *ids = [NSMutableArray new];
    for (NSDictionary *e in ws.edit[@"events"]) {
      BOOL used = NO;
      for (NSDictionary *o in all) if (o != original && [o[@"event"] isEqual:e[@"id"]]) used = YES;
      if (used) continue;
      [items addObject:@[ @"ic_click_list", e[@"name"] ]];
      [ids addObject:e[@"id"]];
    }
    if (!items.count) { [ws push:SCConfirmDialog(@"Select an event", @"No Event created in the scenario", nil)]; return; }
    [ws push:SCChoiceDialog(@"Select an event", nil, items, ^(NSInteger i) { ec[@"event"] = ids[i]; evText(); })];
  });
  evRow = er;
  [d.content addArrangedSubview:SCCard(@"Event", @[ er ])];
  [d.content addArrangedSubview:SCCard(@"Executions", @[ [self field:[ec[@"executions"] description] hint:@"Executions" numeric:YES changed:^(NSString *s) {
                                         ec[@"executions"] = @([s integerValue]);
                                         validate();
                                       }] ])];
  if (!isNew) [d addButton:@"Delete" left:YES action:^{ [wd close]; done(ec, YES); }];
  [d addButton:@"Cancel" left:NO action:^{ [wd close]; }];
  ok = [d addButton:@"OK" left:NO action:^{ [wd close]; done(ec, NO); }];
  evText();
  [self push:d];
}

@end

#pragma mark - Entry

static void ac_showNote(CFNotificationCenterRef c, void *o, CFNotificationName n, const void *obj, CFDictionaryRef info) {
  dispatch_async(dispatch_get_main_queue(), ^{ [[ACOverlay shared] show]; });
}
static void ac_hideNote(CFNotificationCenterRef c, void *o, CFNotificationName n, const void *obj, CFDictionaryRef info) {
  dispatch_async(dispatch_get_main_queue(), ^{ [[ACOverlay shared] hide]; });
}

__attribute__((constructor)) static void ac_init(void) {
  ac_loadSymbols();
  CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, ac_showNote, CFSTR("com.wmhakuifan.smartclicker/show"), NULL,
                                  CFNotificationSuspensionBehaviorDeliverImmediately);
  CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, ac_hideNote, CFSTR("com.wmhakuifan.smartclicker/hide"), NULL,
                                  CFNotificationSuspensionBehaviorDeliverImmediately);
  [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) { ac_after(3.0, ^{ [[ACOverlay shared] setup]; }); }];
}
