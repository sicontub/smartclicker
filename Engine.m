// SmartClicker - iOS port of Smart AutoClicker by Nain57 (GPL-3)
#import "Engine.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <objc/runtime.h>
#include <mach/mach_time.h>
#include <math.h>

#pragma mark - Private API (resolved with dlsym so nothing hard-links to private symbols)

typedef void *IOHIDEventRef;
typedef void *IOHIDEventSystemClientRef;
typedef void *ACSurfaceRef;
typedef void (*IOHIDCallback)(void *target, void *refcon, void *service, IOHIDEventRef event);

static IOHIDEventRef (*p_CreateDigitizer)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t,
                                          double, double, double, double, double, bool, bool, uint32_t);
static IOHIDEventRef (*p_CreateFinger)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, double, double, double,
                                       double, double, bool, bool, uint32_t);
static void (*p_AppendEvent)(IOHIDEventRef, IOHIDEventRef, uint32_t);
static void (*p_SetInteger)(IOHIDEventRef, uint32_t, long);
static void (*p_SetFloat)(IOHIDEventRef, uint32_t, double);
static void (*p_SetSenderID)(IOHIDEventRef, uint64_t);
static uint64_t (*p_GetSenderID)(IOHIDEventRef);
static int (*p_GetType)(IOHIDEventRef);
static IOHIDEventSystemClientRef (*p_ClientCreate)(CFAllocatorRef);
static void (*p_ClientDispatch)(IOHIDEventSystemClientRef, IOHIDEventRef);
static void (*p_ClientSchedule)(IOHIDEventSystemClientRef, CFRunLoopRef, CFStringRef);
static void (*p_ClientRegister)(IOHIDEventSystemClientRef, IOHIDCallback, void *, void *);
static void (*p_ClientUnregister)(IOHIDEventSystemClientRef, IOHIDCallback, void *, void *);
static ACSurfaceRef (*p_SurfaceCreate)(CFDictionaryRef);
static size_t (*p_SurfaceAlign)(CFStringRef, size_t);
static int (*p_SurfaceLock)(ACSurfaceRef, uint32_t, uint32_t *);
static int (*p_SurfaceUnlock)(ACSurfaceRef, uint32_t, uint32_t *);
static void *(*p_SurfaceBase)(ACSurfaceRef);
static size_t (*p_SurfaceBPR)(ACSurfaceRef);
static void (*p_RenderDisplay)(uint32_t, CFStringRef, ACSurfaceRef, int, int);
static void (*p_CaptureDisplay)(uint32_t, CFStringRef, ACSurfaceRef, int, int);
static void (*p_CaptureDisplayT)(uint32_t, CFStringRef, ACSurfaceRef, int, int, CATransform3D);
static void (*p_RenderDisplayT)(uint32_t, CFStringRef, ACSurfaceRef, int, int, CATransform3D);
static uint32_t (*p_ServerPort)(int);
static UIImage *(*p_UICreateScreenUIImage)(void);

void ac_loadSymbols(void) {
  dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
  dlopen("/System/Library/Frameworks/IOSurface.framework/IOSurface", RTLD_NOW);
#define LOAD(var, name) var = (__typeof__(var))dlsym(RTLD_DEFAULT, name)
  LOAD(p_CreateDigitizer, "IOHIDEventCreateDigitizerEvent");
  LOAD(p_CreateFinger, "IOHIDEventCreateDigitizerFingerEvent");
  LOAD(p_AppendEvent, "IOHIDEventAppendEvent");
  LOAD(p_SetInteger, "IOHIDEventSetIntegerValue");
  LOAD(p_SetFloat, "IOHIDEventSetFloatValue");
  LOAD(p_SetSenderID, "IOHIDEventSetSenderID");
  LOAD(p_GetSenderID, "IOHIDEventGetSenderID");
  LOAD(p_GetType, "IOHIDEventGetType");
  LOAD(p_ClientCreate, "IOHIDEventSystemClientCreate");
  LOAD(p_ClientDispatch, "IOHIDEventSystemClientDispatchEvent");
  LOAD(p_ClientSchedule, "IOHIDEventSystemClientScheduleWithRunLoop");
  LOAD(p_ClientRegister, "IOHIDEventSystemClientRegisterEventCallback");
  LOAD(p_ClientUnregister, "IOHIDEventSystemClientUnregisterEventCallback");
  LOAD(p_SurfaceCreate, "IOSurfaceCreate");
  LOAD(p_SurfaceAlign, "IOSurfaceAlignProperty");
  LOAD(p_SurfaceLock, "IOSurfaceLock");
  LOAD(p_SurfaceUnlock, "IOSurfaceUnlock");
  LOAD(p_SurfaceBase, "IOSurfaceGetBaseAddress");
  LOAD(p_SurfaceBPR, "IOSurfaceGetBytesPerRow");
  LOAD(p_RenderDisplay, "CARenderServerRenderDisplay");
  LOAD(p_CaptureDisplay, "CARenderServerCaptureDisplay");
  LOAD(p_CaptureDisplayT, "CARenderServerCaptureDisplayWithTransform");
  LOAD(p_RenderDisplayT, "CARenderServerRenderDisplayWithTransform");
  LOAD(p_ServerPort, "CARenderServerGetServerPort");
  LOAD(p_UICreateScreenUIImage, "_UICreateScreenUIImage");
#undef LOAD
}

#pragma mark - Touch injection

static IOHIDEventSystemClientRef gHIDClient;
static uint64_t gSenderID = 0x000000010000027FULL;
static bool gSenderLearned;
CGSize gFixedSize;
CGFloat gNativeScale;
int gNativeW, gNativeH;

// grab the real touchscreen sender id from the first touch
static void ac_hidCallback(void *target, void *refcon, void *service, IOHIDEventRef event) {
  if (gSenderLearned || !event || !p_GetType || !p_GetSenderID) return;
  if (p_GetType(event) == 11 /* digitizer */) {
    uint64_t s = p_GetSenderID(event);
    if (s) { gSenderID = s; gSenderLearned = true; }
  }
}

void ac_hidSetup(void) {
  if (gHIDClient || !p_ClientCreate) return;
  gHIDClient = p_ClientCreate(kCFAllocatorDefault);
  if (gHIDClient && p_ClientSchedule && p_ClientRegister) {
    p_ClientSchedule(gHIDClient, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    p_ClientRegister(gHIDClient, ac_hidCallback, NULL, NULL);
  }
}

// phase: 0 down, 1 move, 2 up
static void ac_touch(int phase, CGPoint pt) {
  if (!gHIDClient || !p_CreateDigitizer || !p_CreateFinger || !p_ClientDispatch) return;
  double nx = pt.x / gFixedSize.width, ny = pt.y / gFixedSize.height;
  if (nx < 0) nx = 0; if (nx > 1) nx = 1; if (ny < 0) ny = 0; if (ny > 1) ny = 1;
  bool touching = phase != 2;
  uint32_t mask = phase == 1 ? 0x4 /* position */ : 0x3 /* range|touch */;
  uint64_t t = mach_absolute_time();
  IOHIDEventRef hand = p_CreateDigitizer(kCFAllocatorDefault, t, 3 /* hand */, 0, 0, mask, 0, nx, ny, 0, 0, 0,
                                         touching, touching, 0);
  IOHIDEventRef finger = p_CreateFinger(kCFAllocatorDefault, t, 1, 2, mask, nx, ny, 0, touching ? 1.0 : 0.0, 0,
                                        touching, touching, 0);
  if (!hand || !finger) { if (hand) CFRelease(hand); if (finger) CFRelease(finger); return; }
  if (p_SetFloat) {
    p_SetFloat(finger, 0xB0014, 0.04); // major radius
    p_SetFloat(finger, 0xB0015, 0.04); // minor radius
  }
  if (p_SetInteger) p_SetInteger(hand, 0xB0019, 1); // isDisplayIntegrated
  p_AppendEvent(hand, finger, 0);
  if (p_SetSenderID) p_SetSenderID(hand, gSenderID);
  p_ClientDispatch(gHIDClient, hand);
  CFRelease(finger);
  CFRelease(hand);
}

#pragma mark - Screen capture and image matching

typedef struct { int w, h; uint8_t *px; } ACGray;

static ACSurfaceRef gSurface;
static uint8_t *gFallbackBuf;
static NSString *gDisplayName;
static int gCaptureFn;

static NSArray<NSString *> *ac_displayNames(void) {
  NSMutableArray *names = [NSMutableArray new];
  Class cd = objc_getClass("CADisplay");
  @try {
    if ([cd respondsToSelector:@selector(mainDisplay)]) {
      id d = [cd performSelector:@selector(mainDisplay)];
      NSString *n = [d respondsToSelector:@selector(name)] ? [d performSelector:@selector(name)] : nil;
      if ([n isKindOfClass:[NSString class]] && n.length) [names addObject:n];
    }
    if ([cd respondsToSelector:@selector(displays)])
      for (id d in [cd performSelector:@selector(displays)]) {
        NSString *n = [d respondsToSelector:@selector(name)] ? [d performSelector:@selector(name)] : nil;
        if ([n isKindOfClass:[NSString class]] && n.length && ![names containsObject:n]) [names addObject:n];
      }
  } @catch (id e) {}
  for (NSString *n in @[ @"LCD", @"primary", @"display0", @"builtin" ]) if (![names containsObject:n]) [names addObject:n];
  return names;
}

static bool gProbed;

// 1 Capture, 2 Render, 3/4 the WithTransform ones, +10 = pass the server port
static void ac_callCapture(int fn, NSString *name) {
  uint32_t port = fn >= 10 && p_ServerPort ? p_ServerPort(0) : 0;
  CFStringRef n = (__bridge CFStringRef)name;
  switch (fn % 10) {
    case 1: if (p_CaptureDisplay) p_CaptureDisplay(port, n, gSurface, 0, 0); break;
    case 2: if (p_RenderDisplay) p_RenderDisplay(port, n, gSurface, 0, 0); break;
    case 3: if (p_CaptureDisplayT) p_CaptureDisplayT(port, n, gSurface, 0, 0, CATransform3DIdentity); break;
    case 4: if (p_RenderDisplayT) p_RenderDisplayT(port, n, gSurface, 0, 0, CATransform3DIdentity); break;
  }
}

static bool ac_frameHasContent(const uint8_t *base, size_t bpr);

// try everything once, stick with whatever works
static void ac_probeCapture(void) {
  gProbed = true;
  NSArray *names = ac_displayNames();
  int fns[] = {1, 2, 3, 4, 11, 12, 13, 14};
  for (unsigned i = 0; i < sizeof(fns) / sizeof(fns[0]); i++) {
    int fn = fns[i];
    if (fn % 10 == 1 && !p_CaptureDisplay) continue;
    if (fn % 10 == 2 && !p_RenderDisplay) continue;
    if (fn % 10 == 3 && !p_CaptureDisplayT) continue;
    if (fn % 10 == 4 && !p_RenderDisplayT) continue;
    if (fn >= 10 && !p_ServerPort) continue;
    for (NSString *name in names) {
      p_SurfaceLock(gSurface, 0, NULL);
      memset(p_SurfaceBase(gSurface), 0, p_SurfaceBPR(gSurface) * (size_t)gNativeH);
      p_SurfaceUnlock(gSurface, 0, NULL);
      ac_callCapture(fn, name);
      p_SurfaceLock(gSurface, 1, NULL);
      bool any = ac_frameHasContent((const uint8_t *)p_SurfaceBase(gSurface), p_SurfaceBPR(gSurface));
      p_SurfaceUnlock(gSurface, 1, NULL);
      if (any && !gCaptureFn) { gCaptureFn = fn; gDisplayName = name; }
    }
  }
}

static bool ac_frameHasContent(const uint8_t *base, size_t bpr) {
  for (int y = 0; y < gNativeH; y += 37)
    for (int x = 0; x < gNativeW; x += 29)
      if (base[(size_t)y * bpr + x * 4 + 3] || base[(size_t)y * bpr + x * 4 + 1] || base[(size_t)y * bpr + x * 4 + 2]) return true;
  return false;
}

static void ac_grayDownsample(const ACGray *in, int f, ACGray *out) {
  out->w = in->w / f; out->h = in->h / f;
  out->px = (uint8_t *)malloc((size_t)(out->w > 0 ? out->w : 1) * (out->h > 0 ? out->h : 1));
  int n = f * f;
  for (int by = 0; by < out->h; by++)
    for (int bx = 0; bx < out->w; bx++) {
      unsigned sum = 0;
      for (int yy = 0; yy < f; yy++) {
        const uint8_t *row = in->px + (size_t)(by * f + yy) * in->w + (size_t)bx * f;
        for (int xx = 0; xx < f; xx++) sum += row[xx];
      }
      out->px[by * out->w + bx] = (uint8_t)(sum / n);
    }
}

static void ac_grayFromBGRA(const uint8_t *base, size_t bpr, int x0, int y0, int w, int h, int f, ACGray *out) {
  out->w = w / f; out->h = h / f;
  out->px = (uint8_t *)malloc((size_t)(out->w > 0 ? out->w : 1) * (out->h > 0 ? out->h : 1));
  int n = f * f;
  for (int by = 0; by < out->h; by++) {
    for (int bx = 0; bx < out->w; bx++) {
      unsigned sum = 0;
      for (int yy = 0; yy < f; yy++) {
        const uint8_t *row = base + (size_t)(y0 + by * f + yy) * bpr + (size_t)(x0 + bx * f) * 4;
        for (int xx = 0; xx < f; xx++, row += 4) sum += (row[2] * 77u + row[1] * 150u + row[0] * 29u) >> 8;
      }
      out->px[by * out->w + bx] = (uint8_t)(sum / n);
    }
  }
}

bool ac_withScreen(void (^use)(const uint8_t *base, size_t bpr)) {
  if (!gSurface && p_SurfaceCreate) {
    // render server wants 64-byte aligned strides
    size_t bpr = (size_t)gNativeW * 4, alloc;
    if (p_SurfaceAlign) bpr = p_SurfaceAlign(CFSTR("IOSurfaceBytesPerRow"), bpr);
    alloc = bpr * (size_t)gNativeH;
    if (p_SurfaceAlign) alloc = p_SurfaceAlign(CFSTR("IOSurfaceAllocSize"), alloc);
    NSDictionary *props = @{
      @"IOSurfaceWidth" : @(gNativeW), @"IOSurfaceHeight" : @(gNativeH), @"IOSurfaceBytesPerElement" : @4,
      @"IOSurfaceBytesPerRow" : @(bpr), @"IOSurfacePixelFormat" : @(0x42475241 /* 'BGRA' */),
      @"IOSurfaceAllocSize" : @(alloc), @"IOSurfaceIsGlobal" : @YES
    };
    gSurface = p_SurfaceCreate((__bridge CFDictionaryRef)props);
  }
  if (gSurface && p_SurfaceLock) {
    if (!gCaptureFn && !gProbed) ac_probeCapture();
    if (gCaptureFn) {
      ac_callCapture(gCaptureFn, gDisplayName);
      p_SurfaceLock(gSurface, 1, NULL);
      const uint8_t *base = (const uint8_t *)p_SurfaceBase(gSurface);
      size_t bpr = p_SurfaceBPR(gSurface);
      bool any = ac_frameHasContent(base, bpr);
      if (any) {
        // uncached memory
        if (!gFallbackBuf) gFallbackBuf = (uint8_t *)malloc((size_t)gNativeW * gNativeH * 4);
        for (int y = 0; y < gNativeH; y++) memcpy(gFallbackBuf + (size_t)y * gNativeW * 4, base + (size_t)y * bpr, (size_t)gNativeW * 4);
        p_SurfaceUnlock(gSurface, 1, NULL);
        use(gFallbackBuf, (size_t)gNativeW * 4);
        return true;
      }
      p_SurfaceUnlock(gSurface, 1, NULL);
    }
  }
  // slow fallback
  if (!p_UICreateScreenUIImage) return false;
  __block CGImageRef cg = NULL;
  void (^grab)(void) = ^{
    UIImage *img = p_UICreateScreenUIImage();
    if (img && img.CGImage) { cg = img.CGImage; CFRetain(cg); }
    if (img) CFRelease((__bridge CFTypeRef)img); // +1 retained
  };
  if ([NSThread isMainThread]) grab(); else dispatch_sync(dispatch_get_main_queue(), grab);
  if (!cg) return false;
  if (!gFallbackBuf) gFallbackBuf = (uint8_t *)malloc((size_t)gNativeW * gNativeH * 4);
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGContextRef ctx = CGBitmapContextCreate(gFallbackBuf, gNativeW, gNativeH, 8, gNativeW * 4, cs, AC_BGRA_INFO);
  CGContextDrawImage(ctx, CGRectMake(0, 0, gNativeW, gNativeH), cg);
  CGContextRelease(ctx);
  CGColorSpaceRelease(cs);
  CGImageRelease(cg);
  use(gFallbackBuf, (size_t)gNativeW * 4);
  return true;
}

static double ac_diffAt(const ACGray *fr, const ACGray *t, int ox, int oy, double limit) {
  unsigned long n = (unsigned long)t->w * t->h, maxSad = (unsigned long)(limit / 100.0 * 255.0 * n) + 1, sad = 0;
  for (int y = 0; y < t->h; y++) {
    const uint8_t *a = fr->px + (size_t)(oy + y) * fr->w + ox, *b = t->px + (size_t)y * t->w;
    for (int x = 0; x < t->w; x++) { int d = a[x] - b[x]; sad += d < 0 ? -d : d; }
    if (sad > maxSad) return 101;
  }
  return sad * 100.0 / (255.0 * n);
}

#pragma mark - Runtime model used while a scenario plays

@interface ACCond : NSObject
@property int x, y, w, h; // native px
@property double tolerance;
@property BOOL whole, detect;
@property CGPoint found;
@property (copy) NSString *name;
@property double lastConf; // 0..100
@end
@implementation ACCond { @public ACGray fine, coarse; uint8_t *bgra, *small; int sw, sh; BOOL ok; BOOL seen; }
- (void)dealloc { free(fine.px); free(coarse.px); free(bgra); free(small); }
@end

NSString *ac_condPath(NSString *cid) {
  return [AC_DIR stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.png", cid]];
}

int ac_qualityFactor(NSDictionary *scenario) {
  double q = [scenario[@"detectionQuality"] doubleValue];
  if (q <= 0) q = AC_QUALITY_DEFAULT;
  q = MIN(AC_QUALITY_MAX, MAX(AC_QUALITY_MIN, q));
  int side = MAX(gNativeW, gNativeH);
  if (side <= 0) side = 1334;
  return (int)MIN(8, MAX(1, lround(side / q)));
}
static int ac_coarseStep(int f) { return MAX(1, (int)lround(8.0 / f)); }

static uint8_t *ac_shrinkBGR(const uint8_t *src, size_t stride, int x0, int y0, int ow, int oh, int f) {
  uint8_t *out = (uint8_t *)malloc((size_t)ow * oh * 3);
  unsigned n = (unsigned)f * f;
  for (int y = 0; y < oh; y++) {
    for (int x = 0; x < ow; x++) {
      unsigned b = 0, g = 0, r = 0;
      for (int j = 0; j < f; j++) {
        const uint8_t *p = src + (size_t)(y0 + y * f + j) * stride + (size_t)(x0 + x * f) * 4;
        for (int i = 0; i < f; i++, p += 4) { b += p[0]; g += p[1]; r += p[2]; }
      }
      uint8_t *o = out + ((size_t)y * ow + x) * 3;
      o[0] = (b + n / 2) / n; o[1] = (g + n / 2) / n; o[2] = (r + n / 2) / n;
    }
  }
  return out;
}

// TM_CCOEFF_NORMED + mean colour diff, same as the android detector
static void ac_score(const uint8_t *a, size_t as, int abpp, const uint8_t *t, size_t ts, int tbpp, int w, int h, double *conf, double *colorDiff) {
  uint64_t sa[3] = {0}, st[3] = {0}, saa = 0, stt = 0, sat = 0;
  for (int y = 0; y < h; y++) {
    const uint8_t *p = a + (size_t)y * as, *q = t + (size_t)y * ts;
    uint32_t ra[3] = {0}, rt[3] = {0}; uint64_t raa = 0, rtt = 0, rat = 0;
    for (int x = 0; x < w; x++, p += abpp, q += tbpp) {
      for (int c = 0; c < 3; c++) {
        uint32_t u = p[c], v = q[c];
        ra[c] += u; rt[c] += v; raa += u * u; rtt += v * v; rat += u * v;
      }
    }
    for (int c = 0; c < 3; c++) { sa[c] += ra[c]; st[c] += rt[c]; }
    saa += raa; stt += rtt; sat += rat;
  }
  double n = (double)w * h, num = (double)sat, va = (double)saa, vt = (double)stt, cd = 0;
  for (int c = 0; c < 3; c++) {
    num -= (double)sa[c] * st[c] / n;
    va -= (double)sa[c] * sa[c] / n;
    vt -= (double)st[c] * st[c] / n;
    cd += fabs((double)sa[c] - (double)st[c]) / n;
  }
  double d = sqrt(MAX(va, 0)) * sqrt(MAX(vt, 0));
  if (fabs(num) < d) num /= d;
  else if (fabs(num) < d * 1.125) num = num > 0 ? 1 : -1;
  else num = 0; // flat image, opencv gives 0 here too
  *conf = num;
  *colorDiff = cd * 100.0 / 765.0;
}

static bool ac_valid(double conf, double colorDiff, double tol) {
  return conf > (100.0 - tol) / 100.0 && colorDiff < tol;
}

static ACCond *ac_loadCond(NSDictionary *d, int f) {
  int fc = f * ac_coarseStep(f);
  ACCond *c = [ACCond new];
  c.x = [d[@"x"] intValue]; c.y = [d[@"y"] intValue]; c.w = [d[@"w"] intValue]; c.h = [d[@"h"] intValue];
  c.tolerance = [d[@"tol"] doubleValue]; c.whole = [d[@"whole"] boolValue]; c.detect = [d[@"detect"] boolValue];
  c.name = d[@"name"] ?: @"Condition";
  UIImage *img = [UIImage imageWithContentsOfFile:ac_condPath(d[@"id"])];
  if (!img || !img.CGImage || c.w < fc || c.h < fc) return c;
  int w = c.w, h = c.h;
  uint8_t *buf = (uint8_t *)calloc((size_t)w * h, 4);
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGContextRef ctx = CGBitmapContextCreate(buf, w, h, 8, w * 4, cs, AC_BGRA_INFO);
  CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), img.CGImage);
  CGContextRelease(ctx);
  CGColorSpaceRelease(cs);
  ac_grayFromBGRA(buf, w * 4, 0, 0, w, h, f, &c->fine);
  ac_grayDownsample(&c->fine, ac_coarseStep(f), &c->coarse);
  c->bgra = buf;
  c->ok = c->fine.w > 0 && c->coarse.w > 0;
  if (c->ok) {
    c->sw = c->fine.w; c->sh = c->fine.h;
    c->small = ac_shrinkBGR(buf, (size_t)w * 4, 0, 0, c->sw, c->sh, f);
  }
  return c;
}

static bool ac_match(ACCond *c, const uint8_t *screen, const ACGray *fine, const ACGray *coarse, int f) {
  c.lastConf = 0;
  if (!c->ok || !screen) return false;
  double conf, cdiff;
  if (!c.whole) {
    c.found = CGPointMake((c.x + c.w / 2.0) / gNativeScale, (c.y + c.h / 2.0) / gNativeScale);
    if (c.x < 0 || c.y < 0 || c.x + c.w > gNativeW || c.y + c.h > gNativeH) return false;
    ac_score(screen + (size_t)c.y * gNativeW * 4 + (size_t)c.x * 4, (size_t)gNativeW * 4, 4, c->bgra, (size_t)c.w * 4, 4, c.w, c.h, &conf, &cdiff);
    c.lastConf = MAX(0, MIN(1, conf)) * 100;
    return ac_valid(conf, cdiff, c.tolerance);
  }
  // gray search for candidates, then score them like android
  int cx[3] = {-1, -1, -1}, cy[3] = {-1, -1, -1};
  double cd[3] = {101, 101, 101};
  for (int y = 0; y + c->coarse.h <= coarse->h; y++) {
    for (int x = 0; x + c->coarse.w <= coarse->w; x++) {
      double d = ac_diffAt(coarse, &c->coarse, x, y, cd[2]);
      if (d >= cd[2]) continue;
      int i = 2;
      while (i > 0 && cd[i - 1] > d) { cd[i] = cd[i - 1]; cx[i] = cx[i - 1]; cy[i] = cy[i - 1]; i--; }
      cd[i] = d; cx[i] = x; cy[i] = y;
    }
  }
  int cs = ac_coarseStep(f), r = cs + 1;
  bool found = false; double bestConf = -2;
  int px[3], py[3], np = 0;
  for (int k = 0; k < 3; k++) {
    if (cx[k] < 0) continue;
    int bx = cx[k] * cs, by = cy[k] * cs, fx = -1, fy = -1;
    double best = 101;
    for (int y = by - r; y <= by + r; y++) {
      if (y < 0 || y + c->fine.h > fine->h) continue;
      for (int x = bx - r; x <= bx + r; x++) {
        if (x < 0 || x + c->fine.w > fine->w) continue;
        double d = ac_diffAt(fine, &c->fine, x, y, best);
        if (d < best) { best = d; fx = x; fy = y; }
      }
    }
    if (fx < 0) continue;
    bool dup = false;
    for (int j = 0; j < np; j++) if (px[j] == fx && py[j] == fy) dup = true;
    if (dup) continue;
    px[np] = fx; py[np] = fy; np++;
    if ((fx + c->sw) * f > gNativeW || (fy + c->sh) * f > gNativeH) continue;
    uint8_t *reg = ac_shrinkBGR(screen, (size_t)gNativeW * 4, fx * f, fy * f, c->sw, c->sh, f);
    ac_score(reg, (size_t)c->sw * 3, 3, c->small, (size_t)c->sw * 3, 3, c->sw, c->sh, &conf, &cdiff);
    free(reg);
    bool v = ac_valid(conf, cdiff, c.tolerance);
    if ((v && !found) || (v == found && conf > bestConf)) {
      found = v; bestConf = conf;
      c.found = CGPointMake((fx * f + c.w / 2.0) / gNativeScale, (fy * f + c.h / 2.0) / gNativeScale);
    }
  }
  c.lastConf = MAX(0, MIN(1, bestConf)) * 100;
  return found;
}

#pragma mark - Storage

NSMutableDictionary *gRoot;

NSMutableDictionary *ac_mutableDeep(id o) {
  NSData *d = [NSJSONSerialization dataWithJSONObject:o options:0 error:NULL];
  return d ? [NSJSONSerialization JSONObjectWithData:d options:1 /* mutable containers */ error:NULL] : nil;
}

NSString *ac_newId(void) { return [NSUUID UUID].UUIDString; }

NSMutableDictionary *ac_newScenario(NSString *name) {
  return ac_mutableDeep(@{ @"id" : ac_newId(), @"name" : name, @"detectionQuality" : @(AC_QUALITY_DEFAULT), @"endAll" : @NO, @"endConditions" : @[], @"events" : @[] });
}

static void ac_cleanImages(void) {
  NSMutableSet *used = [NSMutableSet new];
  for (NSDictionary *sc in gRoot[@"scenarios"])
    for (NSDictionary *e in sc[@"events"])
      for (NSDictionary *c in e[@"conditions"]) if (c[@"id"]) [used addObject:[c[@"id"] stringByAppendingString:@".png"]];
  NSFileManager *fm = [NSFileManager defaultManager];
  for (NSString *f in [fm contentsOfDirectoryAtPath:AC_DIR error:NULL]) {
    if (![f hasSuffix:@".png"] || [used containsObject:f] || [f hasPrefix:@"tmp-"]) continue;
    NSString *path = [AC_DIR stringByAppendingPathComponent:f];
    // may belong to an event that is still being edited
    NSDate *made = [fm attributesOfItemAtPath:path error:NULL][NSFileModificationDate];
    if (made && -[made timeIntervalSinceNow] < 24 * 3600) continue;
    [fm removeItemAtPath:path error:NULL];
  }
}

void ac_save(void) {
  [[NSFileManager defaultManager] createDirectoryAtPath:AC_DIR withIntermediateDirectories:YES attributes:nil error:NULL];
  NSData *d = [NSJSONSerialization dataWithJSONObject:gRoot options:1 error:NULL];
  [d writeToFile:AC_JSON atomically:YES];
  ac_cleanImages();
}

static void ac_migrate(NSMutableDictionary *sc) {
  if (!sc[@"id"]) sc[@"id"] = ac_newId();
  if (![sc[@"endConditions"] isKindOfClass:[NSMutableArray class]]) sc[@"endConditions"] = [NSMutableArray new];
  if (!sc[@"detectionQuality"]) { // old builds stored 8/4/2
    int q = [sc[@"quality"] intValue];
    sc[@"detectionQuality"] = @(q == 8 ? 400 : q == 2 ? 1200 : AC_QUALITY_DEFAULT);
  }
  [sc removeObjectForKey:@"quality"];
  for (NSMutableDictionary *e in sc[@"events"]) {
    if (!e[@"id"]) e[@"id"] = ac_newId();
    long stop = [e[@"stopAfter"] integerValue];
    if (stop > 0) [sc[@"endConditions"] addObject:ac_mutableDeep(@{ @"event" : e[@"id"], @"executions" : @(stop) })];
    [e removeObjectForKey:@"stopAfter"];
    [sc removeObjectForKey:@"interval"];
    for (NSMutableDictionary *a in e[@"actions"]) {
      if (!a[@"name"]) a[@"name"] = [a[@"t"] isEqualToString:@"pause"] ? @"Wait" : [a[@"t"] isEqualToString:@"swipe"] ? @"Swipe" : @"Click";
      if (a[@"cond"]) { [a removeObjectForKey:@"cond"]; a[@"onCond"] = @YES; }
    }
  }
}

void ac_load(void) {
  NSData *d = [NSData dataWithContentsOfFile:AC_JSON];
  id o = d ? [NSJSONSerialization JSONObjectWithData:d options:1 error:NULL] : nil;
  gRoot = nil;
  if ([o isKindOfClass:[NSMutableDictionary class]] && [o[@"scenarios"] isKindOfClass:[NSMutableArray class]]) gRoot = o;
  if (!gRoot) gRoot = ac_mutableDeep(@{ @"selected" : @0, @"scenarios" : @[] });
  for (NSMutableDictionary *sc in gRoot[@"scenarios"]) ac_migrate(sc);
}

NSMutableArray *ac_scenarios(void) { return gRoot[@"scenarios"]; }
NSMutableDictionary *ac_current(void) {
  if (ac_scenarios().count == 0) { [ac_scenarios() addObject:ac_newScenario(@"Scenario")]; ac_save(); }
  NSInteger i = [gRoot[@"selected"] integerValue];
  if (i < 0 || i >= (NSInteger)ac_scenarios().count) { i = 0; gRoot[@"selected"] = @0; }
  return ac_scenarios()[i];
}

#pragma mark - Player

volatile bool gRunning;
void (^gOnStop)(NSString *reason);

// usleep gets coalesced on background threads
static void ac_sleepExact(double ms) {
  static mach_timebase_info_data_t tb;
  if (!tb.denom) mach_timebase_info(&tb);
  uint64_t until = mach_absolute_time() + (uint64_t)(ms * 1e6 * tb.denom / tb.numer);
  mach_wait_until(until);
}

static bool ac_sleepMs(double ms) {
  while (ms > 0 && gRunning) { double s = ms > 50 ? 50 : ms; ac_sleepExact(s); ms -= s; }
  return gRunning;
}

static double ac_jitter(double v, bool on, double frac) {
  if (!on || v <= 0) return v;
  return v * (1.0 - frac + (arc4random_uniform(2001) / 1000.0) * frac);
}

static CGPoint ac_jitterPt(CGPoint p, bool on) {
  if (!on) return p;
  return CGPointMake(p.x + (double)arc4random_uniform(9) - 4, p.y + (double)arc4random_uniform(9) - 4);
}

static void ac_doTap(CGPoint p, double pressMs) {
  ac_touch(0, p);
  ac_sleepExact(pressMs < 1 ? 1 : pressMs);
  ac_touch(2, p);
}

static void ac_doSwipe(CGPoint a, CGPoint b, double ms) {
  if (ms < 50) ms = 50;
  int steps = (int)(ms / 16);
  ac_touch(0, a);
  for (int i = 1; i <= steps && gRunning; i++) {
    ac_sleepExact(16);
    double t = (double)i / steps;
    ac_touch(1, CGPointMake(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t));
  }
  ac_touch(2, b);
}

volatile bool gDebug;
static NSDictionary *gDebugInfo;
static NSObject *gDebugLock;
NSDictionary *ac_debugInfo(void) {
  if (!gDebugLock) return nil;
  @synchronized(gDebugLock) { return gDebugInfo; }
}
static void ac_debugSet(NSDictionary *changes) {
  if (!gDebugLock) gDebugLock = [NSObject new];
  @synchronized(gDebugLock) {
    NSMutableDictionary *m = gDebugInfo ? [gDebugInfo mutableCopy] : [NSMutableDictionary new];
    [m addEntriesFromDictionary:changes];
    gDebugInfo = m;
  }
}

static CGRect ac_condRect(ACCond *c) {
  CGFloat s = gNativeScale > 0 ? gNativeScale : 2;
  if (c.whole) return CGRectMake(c.found.x - c.w / (2 * s), c.found.y - c.h / (2 * s), c.w / s, c.h / s);
  return CGRectMake(c.x / s, c.y / s, c.w / s, c.h / s);
}

void ac_openApp(NSString *bundleId) {
  if (![bundleId isKindOfClass:[NSString class]] || !bundleId.length) return;
  dispatch_async(dispatch_get_main_queue(), ^{
    UIApplication *app = [UIApplication sharedApplication];
    SEL sel = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
    if ([app respondsToSelector:sel]) ((BOOL (*)(id, SEL, NSString *, BOOL))objc_msgSend)(app, sel, bundleId, NO);
  });
}

void ac_play(NSDictionary *scenario) {
  if (!gDebugLock) gDebugLock = [NSObject new];
  @synchronized(gDebugLock) { gDebugInfo = nil; }
  int f = ac_qualityFactor(scenario);
  // no interval, passes run back to back (capped at 60hz)
  double interval = 16;
  mach_timebase_info_data_t tb;
  mach_timebase_info(&tb);
  NSArray *ends = scenario[@"endConditions"];
  bool endAll = [scenario[@"endAll"] boolValue];
  bool rnd = [scenario[@"randomize"] boolValue];
  NSArray *events = scenario[@"events"];
  NSMutableArray *conds = [NSMutableArray new];
  bool needCapture = false;
  for (NSDictionary *e in events) {
    NSMutableArray *list = [NSMutableArray new];
    for (NSDictionary *cd in e[@"conditions"]) { [list addObject:ac_loadCond(cd, f)]; needCapture = true; }
    [conds addObject:list];
  }
  NSUInteger n = events.count;
  long *execs = (long *)calloc(n ? n : 1, sizeof(long));
  #define AC_MS(t0) ((double)(mach_absolute_time() - (t0)) * tb.numer / tb.denom / 1e6)
  NSString *reason = @"Stopped";
  ACGray fine = {0}, coarse = {0};
  while (gRunning) {
    @autoreleasepool {
      uint64_t start = mach_absolute_time();
      if (needCapture) {
        free(fine.px); free(coarse.px); fine.px = coarse.px = NULL;
        __block ACGray fi = {0}, co = {0};
        bool ok = ac_withScreen(^(const uint8_t *base, size_t bpr) {
          ac_grayFromBGRA(base, bpr, 0, 0, gNativeW, gNativeH, f, &fi);
          ac_grayDownsample(&fi, ac_coarseStep(f), &co);
        });
        if (!ok) { reason = @"Screen capture failed"; break; }
        fine = fi; coarse = co;
      }
      for (NSUInteger i = 0; i < n && gRunning; i++) {
        NSDictionary *e = events[i];
        NSArray *cl = conds[i];
        bool all = [e[@"all"] boolValue] || cl.count == 0;
        bool fulfilled = all;
        for (ACCond *c in cl) {
          bool seen = ac_match(c, gFallbackBuf, &fine, &coarse, f);
          c->seen = seen;
          if (gDebug) ac_debugSet(@{ @"current" : @(c.lastConf) });
          bool met = c.detect ? seen : !seen;
          if (all && !met) { fulfilled = false; break; }
          if (!all && met) { fulfilled = true; break; }
        }
        if (!fulfilled) continue;
        if (gDebug) {
          ACCond *pc = nil;
          for (ACCond *c in cl) if (c.detect && c->seen) { pc = c; break; }
          if (!pc) pc = cl.firstObject;
          NSMutableDictionary *dbg = [@{ @"event" : e[@"name"] ?: @"" } mutableCopy];
          if (pc) {
            dbg[@"condition"] = pc.name;
            dbg[@"confidence"] = @(pc.lastConf);
            dbg[@"rect"] = pc.detect && pc->seen ? [NSValue valueWithCGRect:ac_condRect(pc)] : [NSValue valueWithCGRect:CGRectZero];
          }
          ac_debugSet(dbg);
        }
        for (NSDictionary *a in e[@"actions"]) {
          if (!gRunning) break;
          NSString *t = a[@"t"];
          double d = ac_jitter([a[@"d"] doubleValue], rnd, 0.1);
          if ([t isEqualToString:@"pause"]) { ac_sleepMs(d); continue; }
          if ([t isEqualToString:@"app"]) { ac_openApp(a[@"bundleId"]); continue; }
          CGPoint p = CGPointMake([a[@"x"] doubleValue], [a[@"y"] doubleValue]);
          if ([a[@"onCond"] boolValue])
            for (ACCond *c in cl) if (c.detect && c->seen) { p = c.found; break; }
          p = ac_jitterPt(p, rnd);
          if ([t isEqualToString:@"swipe"])
            ac_doSwipe(p, ac_jitterPt(CGPointMake([a[@"x2"] doubleValue], [a[@"y2"] doubleValue]), rnd), d);
          else
            ac_doTap(p, d);
        }
        execs[i]++;
        if (ends.count) {
          NSUInteger reached = 0;
          for (NSDictionary *ec in ends) {
            for (NSUInteger k = 0; k < n; k++)
              if ([events[k][@"id"] isEqual:ec[@"event"]] && execs[k] >= [ec[@"executions"] integerValue]) { reached++; break; }
          }
          if (endAll ? reached == ends.count : reached > 0) { reason = @"End condition reached"; gRunning = false; }
        }
        break; // one event per pass, same as android
      }
      double elapsed = AC_MS(start);
      if (gRunning && elapsed < interval) ac_sleepMs(interval - elapsed);
    }
  }
  free(fine.px); free(coarse.px); free(execs);
  gRunning = false;
  dispatch_async(dispatch_get_main_queue(), ^{ if (gOnStop) gOnStop(reason); });
}
