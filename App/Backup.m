// Smart AutoClicker backup import/export
#import "Backup.h"
#import <UIKit/UIKit.h>
#import "../Engine.h"
#include <zlib.h>

#define AC_BACKUP_VERSION 8
#define AC_RGBA_INFO (kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big)

#pragma mark - Minimal zip reader / writer (stored + deflate, no zip64)

static uint16_t rd16(const uint8_t *p) { return (uint16_t)(p[0] | p[1] << 8); }
static uint32_t rd32(const uint8_t *p) { return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }

static NSDictionary<NSString *, NSData *> *ac_unzip(NSData *zip) {
  const uint8_t *b = zip.bytes;
  NSUInteger n = zip.length;
  if (n < 22) return nil;
  NSInteger eocd = -1;
  for (NSInteger i = (NSInteger)n - 22; i >= 0 && i >= (NSInteger)n - 22 - 65535; i--)
    if (rd32(b + i) == 0x06054b50) { eocd = i; break; }
  if (eocd < 0) return nil;
  NSUInteger count = rd16(b + eocd + 10), off = rd32(b + eocd + 16);
  NSMutableDictionary *out = [NSMutableDictionary new];
  for (NSUInteger k = 0; k < count; k++) {
    if (off + 46 > n || rd32(b + off) != 0x02014b50) return nil;
    const uint8_t *c = b + off;
    uint16_t method = rd16(c + 10), nameLen = rd16(c + 28), extraLen = rd16(c + 30), commentLen = rd16(c + 32);
    uint32_t csize = rd32(c + 20), usize = rd32(c + 24), loff = rd32(c + 42);
    if (off + 46 + nameLen > n) return nil;
    NSString *name = [[NSString alloc] initWithBytes:c + 46 length:nameLen encoding:NSUTF8StringEncoding];
    off += 46 + nameLen + extraLen + commentLen;
    if (!name || [name hasSuffix:@"/"]) continue;
    if (loff + 30 > n || rd32(b + loff) != 0x04034b50) return nil;
    NSUInteger data = loff + 30 + rd16(b + loff + 26) + rd16(b + loff + 28);
    if (data + csize > n) return nil;
    if (method == 0) {
      out[name] = [NSData dataWithBytes:b + data length:csize];
    } else if (method == 8) {
      NSMutableData *u = [NSMutableData dataWithLength:usize];
      z_stream s = {0};
      if (inflateInit2(&s, -MAX_WBITS) != Z_OK) return nil;
      s.next_in = (Bytef *)(b + data); s.avail_in = csize;
      s.next_out = u.mutableBytes; s.avail_out = usize;
      int r = inflate(&s, Z_FINISH);
      inflateEnd(&s);
      if (r != Z_STREAM_END) continue;
      u.length = s.total_out;
      out[name] = u;
    }
  }
  return out;
}

@interface ACZipWriter : NSObject
- (void)add:(NSString *)name data:(NSData *)data;
- (NSData *)finish;
@end

@implementation ACZipWriter {
  NSMutableData *_out, *_dir;
  NSUInteger _count;
}
- (instancetype)init {
  if ((self = [super init])) { _out = [NSMutableData new]; _dir = [NSMutableData new]; }
  return self;
}
static void w16(NSMutableData *d, uint16_t v) { uint8_t b[2] = {v & 0xff, v >> 8}; [d appendBytes:b length:2]; }
static void w32(NSMutableData *d, uint32_t v) { uint8_t b[4] = {v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, v >> 24}; [d appendBytes:b length:4]; }
- (void)add:(NSString *)name data:(NSData *)data {
  NSData *nm = [name dataUsingEncoding:NSUTF8StringEncoding];
  uLong crc = crc32(0, data.bytes, (uInt)data.length);
  NSMutableData *comp = [NSMutableData dataWithLength:compressBound((uLong)data.length) + 64];
  z_stream s = {0};
  deflateInit2(&s, 6, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY);
  s.next_in = (Bytef *)data.bytes; s.avail_in = (uInt)data.length;
  s.next_out = comp.mutableBytes; s.avail_out = (uInt)comp.length;
  deflate(&s, Z_FINISH);
  comp.length = s.total_out;
  deflateEnd(&s);
  uint32_t off = (uint32_t)_out.length;
  // DOS time/date: 2024-01-01 00:00
  uint16_t dtime = 0, ddate = (uint16_t)(((2024 - 1980) << 9) | (1 << 5) | 1);
  w32(_out, 0x04034b50); w16(_out, 20); w16(_out, 0x0800); w16(_out, 8); w16(_out, dtime); w16(_out, ddate);
  w32(_out, (uint32_t)crc); w32(_out, (uint32_t)comp.length); w32(_out, (uint32_t)data.length);
  w16(_out, (uint16_t)nm.length); w16(_out, 0);
  [_out appendData:nm]; [_out appendData:comp];
  w32(_dir, 0x02014b50); w16(_dir, 20); w16(_dir, 20); w16(_dir, 0x0800); w16(_dir, 8); w16(_dir, dtime); w16(_dir, ddate);
  w32(_dir, (uint32_t)crc); w32(_dir, (uint32_t)comp.length); w32(_dir, (uint32_t)data.length);
  w16(_dir, (uint16_t)nm.length); w16(_dir, 0); w16(_dir, 0); w16(_dir, 0); w16(_dir, 0); w32(_dir, 0); w32(_dir, off);
  [_dir appendData:nm];
  _count++;
}
- (NSData *)finish {
  uint32_t dirOff = (uint32_t)_out.length;
  [_out appendData:_dir];
  w32(_out, 0x06054b50); w16(_out, 0); w16(_out, 0); w16(_out, (uint16_t)_count); w16(_out, (uint16_t)_count);
  w32(_out, (uint32_t)_dir.length); w32(_out, dirOff); w16(_out, 0);
  return _out;
}
@end

#pragma mark - Helpers

static UIScreen *ac_screen(void) { return [UIScreen mainScreen]; }
static CGSize ac_fixedPts(void) { return ac_screen().fixedCoordinateSpace.bounds.size; }
static CGSize ac_nativePx(void) { return ac_screen().nativeBounds.size; }

static long ac_num(id o, long def) { return [o isKindOfClass:[NSNumber class]] ? [o longValue] : def; }
static NSString *ac_str(id o, NSString *def) { return [o isKindOfClass:[NSString class]] && [o length] ? o : def; }

static CGImageRef ac_resample(CGImageRef src, int dw, int dh, double ox, double oy, double sw, double sh) {
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGContextRef ctx = CGBitmapContextCreate(NULL, dw, dh, 8, dw * 4, cs, AC_RGBA_INFO);
  CGColorSpaceRelease(cs);
  if (!ctx) return NULL;
  CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
  // flip, CG is bottom-left
  CGContextDrawImage(ctx, CGRectMake(ox, dh - oy - sh, sw, sh), src);
  CGImageRef img = CGBitmapContextCreateImage(ctx);
  CGContextRelease(ctx);
  return img;
}

static CGImageRef ac_imageFromRGBA(NSData *raw, int w, int h) {
  if (w <= 0 || h <= 0 || raw.length < (NSUInteger)w * h * 4) return NULL;
  CGDataProviderRef p = CGDataProviderCreateWithCFData((__bridge CFDataRef)raw);
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGImageRef img = CGImageCreate(w, h, 8, 32, w * 4, cs, AC_RGBA_INFO, p, NULL, NO, kCGRenderingIntentDefault);
  CGColorSpaceRelease(cs);
  CGDataProviderRelease(p);
  return img;
}

#pragma mark - Import

static NSMutableDictionary *ac_importCondition(NSDictionary *c, NSData *raw, double kx, double ky, int nw, int nh) {
  long l = ac_num(c[@"areaLeft"], 0), t = ac_num(c[@"areaTop"], 0), r = ac_num(c[@"areaRight"], 0), b = ac_num(c[@"areaBottom"], 0);
  int aw = (int)(r - l), ah = (int)(b - t);
  CGImageRef src = ac_imageFromRGBA(raw, aw, ah);
  if (!src) return nil;
  double fx = l * kx, fy = t * ky, fw = aw * kx, fh = ah * ky;
  // snap inwards to the 8px grid (crop, don't stretch)
  int x0 = (int)ceil(fx / AC_COARSE) * AC_COARSE, y0 = (int)ceil(fy / AC_COARSE) * AC_COARSE;
  int x1 = (int)floor((fx + fw) / AC_COARSE) * AC_COARSE, y1 = (int)floor((fy + fh) / AC_COARSE) * AC_COARSE;
  if (x1 - x0 < 16 || y1 - y0 < 16) { // too small, snap to nearest and stretch a bit
    x0 = (int)round(fx / AC_COARSE) * AC_COARSE; y0 = (int)round(fy / AC_COARSE) * AC_COARSE;
    x1 = x0 + MAX(16, (int)round(fw / AC_COARSE) * AC_COARSE); y1 = y0 + MAX(16, (int)round(fh / AC_COARSE) * AC_COARSE);
    fx = x0; fy = y0; fw = x1 - x0; fh = y1 - y0;
  }
  x0 = MAX(0, x0); y0 = MAX(0, y0); x1 = MIN(nw / AC_COARSE * AC_COARSE, x1); y1 = MIN(nh / AC_COARSE * AC_COARSE, y1);
  int w = x1 - x0, h = y1 - y0;
  if (w < AC_COARSE || h < AC_COARSE) { CGImageRelease(src); return nil; }
  CGImageRef img = ac_resample(src, w, h, fx - x0, fy - y0, fw, fh);
  CGImageRelease(src);
  if (!img) return nil;
  NSString *cid = ac_newId();
  BOOL ok = [UIImagePNGRepresentation([UIImage imageWithCGImage:img]) writeToFile:ac_condPath(cid) atomically:YES];
  CGImageRelease(img);
  if (!ok) return nil;
  long thr = ac_num(c[@"threshold"], 4);
  return ac_mutableDeep(@{
    @"id" : cid, @"name" : ac_str(c[@"name"], @"Condition"), @"x" : @(x0), @"y" : @(y0), @"w" : @(w), @"h" : @(h),
    @"tol" : @(MAX(0, MIN(20, thr))), @"whole" : @(ac_num(c[@"detectionType"], 1) == 2),
    @"detect" : @([c[@"shouldBeDetected"] isKindOfClass:[NSNumber class]] ? [c[@"shouldBeDetected"] boolValue] : YES)
  });
}

static NSArray *ac_byPriority(NSArray *list, NSString *key) {
  if (![list isKindOfClass:[NSArray class]]) return @[];
  return [list sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(id a, id b) {
    long pa = ac_num(key ? a[key][@"priority"] : a[@"priority"], 0), pb = ac_num(key ? b[key][@"priority"] : b[@"priority"], 0);
    return pa < pb ? NSOrderedAscending : pa > pb ? NSOrderedDescending : NSOrderedSame;
  }];
}

static NSMutableDictionary *ac_importScenario(NSDictionary *root, NSString *folder, NSDictionary *files, ACImportResult *res) {
  NSDictionary *wrap = root[@"scenario"];
  NSDictionary *sc = [wrap isKindOfClass:[NSDictionary class]] ? wrap[@"scenario"] : nil;
  if (![sc isKindOfClass:[NSDictionary class]]) return nil;
  double sw = ac_num(root[@"screenWidth"], 0), sh = ac_num(root[@"screenHeight"], 0);
  CGSize pts = ac_fixedPts(), px = ac_nativePx();
  if (sw <= 0 || sh <= 0) { sw = px.width; sh = px.height; }
  res->screen = CGSizeMake(sw, sh);
  if (fabs(sw - px.width) > 0.5 || fabs(sh - px.height) > 0.5) res->otherScreen = YES;
  double kx = px.width / sw, ky = px.height / sh;           // Android px -> native px
  double px2ptX = pts.width / sw, px2ptY = pts.height / sh; // Android px -> points

  long q = ac_num(sc[@"detectionQuality"], 600);
  NSMutableDictionary *out = ac_newScenario(ac_str(sc[@"name"], @"Imported scenario"));
  out[@"detectionQuality"] = @(MIN(AC_QUALITY_MAX, MAX(AC_QUALITY_MIN, q)));
  out[@"endAll"] = @(ac_num(sc[@"endConditionOperator"], 2) == 1);

  NSMutableDictionary *eventIds = [NSMutableDictionary new];
  for (NSDictionary *ew in ac_byPriority(wrap[@"events"], @"event")) {
    NSDictionary *e = ew[@"event"];
    if (![e isKindOfClass:[NSDictionary class]]) continue;
    NSMutableDictionary *ev = ac_mutableDeep(@{
      @"id" : ac_newId(), @"name" : ac_str(e[@"name"], @"Event"), @"all" : @(ac_num(e[@"conditionOperator"], 1) == 1),
      @"conditions" : @[], @"actions" : @[]
    });
    if (e[@"id"]) eventIds[[e[@"id"] description]] = ev[@"id"];
    for (NSDictionary *c in ew[@"conditions"]) {
      if (![c isKindOfClass:[NSDictionary class]]) continue;
      NSString *path = [ac_str(c[@"path"], @"") lastPathComponent];
      NSData *raw = files[[folder stringByAppendingPathComponent:path]];
      NSMutableDictionary *cd = raw ? ac_importCondition(c, raw, kx, ky, (int)px.width, (int)px.height) : nil;
      if (cd) [ev[@"conditions"] addObject:cd];
    }
    for (NSDictionary *aw in ac_byPriority(ew[@"actions"], @"action")) {
      NSDictionary *a = aw[@"action"];
      if (![a isKindOfClass:[NSDictionary class]]) continue;
      NSString *type = ac_str(a[@"type"], @"");
      NSMutableDictionary *ac = [NSMutableDictionary new];
      if ([type isEqualToString:@"CLICK"]) {
        ac[@"t"] = @"click";
        ac[@"name"] = ac_str(a[@"name"], @"Click");
        ac[@"x"] = @(round(ac_num(a[@"x"], 0) * px2ptX)); ac[@"y"] = @(round(ac_num(a[@"y"], 0) * px2ptY));
        ac[@"onCond"] = @([a[@"clickOnCondition"] boolValue]);
        ac[@"d"] = @(ac_num(a[@"pressDuration"], 1));
      } else if ([type isEqualToString:@"SWIPE"]) {
        ac[@"t"] = @"swipe";
        ac[@"name"] = ac_str(a[@"name"], @"Swipe");
        ac[@"x"] = @(round(ac_num(a[@"fromX"], 0) * px2ptX)); ac[@"y"] = @(round(ac_num(a[@"fromY"], 0) * px2ptY));
        ac[@"x2"] = @(round(ac_num(a[@"toX"], 0) * px2ptX)); ac[@"y2"] = @(round(ac_num(a[@"toY"], 0) * px2ptY));
        ac[@"d"] = @(ac_num(a[@"swipeDuration"], 250));
      } else if ([type isEqualToString:@"PAUSE"]) {
        ac[@"t"] = @"pause";
        ac[@"name"] = ac_str(a[@"name"], @"Wait");
        ac[@"d"] = @(ac_num(a[@"pauseDuration"], 50));
      } else { // INTENT etc, nothing like it on iOS
        res->skippedActions++;
        continue;
      }
      [ev[@"actions"] addObject:ac];
    }
    [out[@"events"] addObject:ev];
  }
  NSArray *ends = wrap[@"endConditions"];
  if ([ends isKindOfClass:[NSArray class]])
    for (NSDictionary *ec in ends) {
      NSString *eid = [ec isKindOfClass:[NSDictionary class]] ? eventIds[[ec[@"eventId"] description]] : nil;
      if (eid) [out[@"endConditions"] addObject:ac_mutableDeep(@{ @"event" : eid, @"executions" : @(MAX(1, ac_num(ec[@"executions"], 1))) })];
    }
  return out;
}

BOOL ac_importBackup(NSString *zipPath, ACImportResult *res, void (^progress)(NSInteger done)) {
  *res = (ACImportResult){0};
  NSData *zip = [NSData dataWithContentsOfFile:zipPath options:NSDataReadingMappedIfSafe error:NULL];
  NSDictionary *files = zip ? ac_unzip(zip) : nil;
  if (!files) return NO;
  [[NSFileManager defaultManager] createDirectoryAtPath:AC_DIR withIntermediateDirectories:YES attributes:nil error:NULL];
  BOOL any = NO;
  for (NSString *name in [files.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
    if (![name.pathExtension isEqualToString:@"json"]) continue;
    any = YES;
    @autoreleasepool {
      id root = [NSJSONSerialization JSONObjectWithData:files[name] options:0 error:NULL];
      NSMutableDictionary *sc = nil;
      if ([root isKindOfClass:[NSDictionary class]] && ac_num(root[@"version"], -1) >= AC_BACKUP_VERSION)
        sc = ac_importScenario(root, name.stringByDeletingLastPathComponent, files, res);
      if (sc) { [ac_scenarios() addObject:sc]; res->imported++; } else res->failed++;
    }
    if (progress) progress(res->imported + res->failed);
  }
  return any;
}

#pragma mark - Export

BOOL ac_exportBackup(NSArray<NSDictionary *> *scenarios, CGSize screen, NSString *zipPath, NSInteger *skippedEvents,
                     NSInteger *skippedApps, void (^progress)(NSInteger done)) {
  CGSize pts = ac_fixedPts(), px = ac_nativePx();
  int sw = (int)round(screen.width), sh = (int)round(screen.height);
  if (sw <= 0 || sh <= 0) { sw = (int)px.width; sh = (int)px.height; }
  double kx = sw / px.width, ky = sh / px.height;            // native px -> target px
  double pt2pxX = sw / pts.width, pt2pxY = sh / pts.height;  // points -> target px
  ACZipWriter *zw = [ACZipWriter new];
  NSInteger skipped = 0, apps = 0, done = 0;
  long nextId = 1;
  NSMutableSet *usedPaths = [NSMutableSet new];
  for (NSDictionary *sc in scenarios) {
    @autoreleasepool {
      long sid = (long)(done + 1);
      NSString *folder = [NSString stringWithFormat:@"%ld", sid];
      NSMutableArray *events = [NSMutableArray new];
      NSMutableDictionary *eventIds = [NSMutableDictionary new];
      long priority = 0;
      for (NSDictionary *e in sc[@"events"]) {
        NSArray *conds = e[@"conditions"];
        NSMutableArray *acts = [NSMutableArray new];
        for (NSDictionary *a in e[@"actions"]) {
          if ([a[@"t"] isEqualToString:@"app"]) apps++; else [acts addObject:a];
        }
        if (!conds.count || !acts.count) { skipped++; continue; }
        long eid = nextId++;
        if (e[@"id"]) eventIds[e[@"id"]] = @(eid);
        NSMutableArray *jc = [NSMutableArray new], *ja = [NSMutableArray new];
        for (NSDictionary *c in conds) {
          UIImage *png = [UIImage imageWithContentsOfFile:ac_condPath(c[@"id"])];
          if (!png.CGImage) continue;
          long x = [c[@"x"] longValue], y = [c[@"y"] longValue], w = [c[@"w"] longValue], h = [c[@"h"] longValue];
          long l = lround(x * kx), t = lround(y * ky), r = MAX(l + 1, lround((x + w) * kx)), b = MAX(t + 1, lround((y + h) * ky));
          r = MIN(r, sw); b = MIN(b, sh);
          int ow = (int)(r - l), oh = (int)(b - t);
          if (ow <= 0 || oh <= 0) continue;
          CGImageRef img = ac_resample(png.CGImage, ow, oh, 0, 0, ow, oh);
          if (!img) continue;
          NSData *rgba = CFBridgingRelease(CGDataProviderCopyData(CGImageGetDataProvider(img)));
          size_t bpr = CGImageGetBytesPerRow(img);
          CGImageRelease(img);
          NSMutableData *raw = [NSMutableData dataWithLength:(NSUInteger)ow * oh * 4];
          for (int yy = 0; yy < oh; yy++)
            memcpy((uint8_t *)raw.mutableBytes + (size_t)yy * ow * 4, (const uint8_t *)rgba.bytes + (size_t)yy * bpr, (size_t)ow * 4);
          NSString *path;
          do path = [NSString stringWithFormat:@"Condition_%d", (int32_t)arc4random()];
          while ([usedPaths containsObject:path]);
          [usedPaths addObject:path];
          [zw add:[folder stringByAppendingPathComponent:path] data:raw];
          [jc addObject:@{
            @"id" : @(nextId++), @"eventId" : @(eid), @"name" : ac_str(c[@"name"], @"Condition"), @"path" : path,
            @"areaLeft" : @(l), @"areaTop" : @(t), @"areaRight" : @(r), @"areaBottom" : @(b),
            @"threshold" : @(MAX(0, MIN(20, [c[@"tol"] longValue]))), @"detectionType" : @([c[@"whole"] boolValue] ? 2 : 1),
            @"shouldBeDetected" : @([c[@"detect"] boolValue])
          }];
        }
        if (!jc.count) { skipped++; [eventIds removeObjectForKey:e[@"id"]]; continue; }
        long ap = 0;
        for (NSDictionary *a in acts) {
          NSString *t = a[@"t"];
          NSMutableDictionary *ja1 = [@{ @"id" : @(nextId++), @"eventId" : @(eid), @"priority" : @(ap++) } mutableCopy];
          long d = [a[@"d"] longValue];
          if ([t isEqualToString:@"pause"]) {
            ja1[@"name"] = ac_str(a[@"name"], @"Pause"); ja1[@"type"] = @"PAUSE"; ja1[@"pauseDuration"] = @(MAX(1, d));
          } else if ([t isEqualToString:@"swipe"]) {
            ja1[@"name"] = ac_str(a[@"name"], @"Swipe"); ja1[@"type"] = @"SWIPE";
            ja1[@"fromX"] = @(lround([a[@"x"] doubleValue] * pt2pxX)); ja1[@"fromY"] = @(lround([a[@"y"] doubleValue] * pt2pxY));
            ja1[@"toX"] = @(lround([a[@"x2"] doubleValue] * pt2pxX)); ja1[@"toY"] = @(lround([a[@"y2"] doubleValue] * pt2pxY));
            ja1[@"swipeDuration"] = @(MAX(1, d));
          } else {
            ja1[@"name"] = ac_str(a[@"name"], @"Click"); ja1[@"type"] = @"CLICK";
            BOOL onCond = [a[@"onCond"] boolValue];
            if (!onCond) { ja1[@"x"] = @(lround([a[@"x"] doubleValue] * pt2pxX)); ja1[@"y"] = @(lround([a[@"y"] doubleValue] * pt2pxY)); }
            ja1[@"clickOnCondition"] = @(onCond);
            ja1[@"pressDuration"] = @(MAX(1, d));
          }
          [ja addObject:@{ @"action" : ja1, @"intentExtras" : @[] }];
        }
        [events addObject:@{
          @"event" : @{ @"id" : @(eid), @"scenarioId" : @(sid), @"name" : ac_str(e[@"name"], @"Event"),
                        @"conditionOperator" : @([e[@"all"] boolValue] ? 1 : 2), @"priority" : @(priority++), @"stopAfter" : [NSNull null] },
          @"actions" : ja, @"conditions" : jc
        }];
      }
      NSMutableArray *ends = [NSMutableArray new];
      for (NSDictionary *ec in sc[@"endConditions"]) {
        NSNumber *eid = eventIds[ec[@"event"] ?: @""];
        if (eid) [ends addObject:@{ @"id" : @(nextId++), @"scenarioId" : @(sid), @"eventId" : eid, @"executions" : @(MAX(1, [ec[@"executions"] longValue])) }];
      }
      long q = [sc[@"detectionQuality"] longValue];
      if (q <= 0) q = AC_QUALITY_DEFAULT;
      q = MIN(AC_QUALITY_MAX, MAX(AC_QUALITY_MIN, q));
      NSDictionary *root = @{
        @"version" : @(AC_BACKUP_VERSION), @"screenWidth" : @(sw), @"screenHeight" : @(sh),
        @"scenario" : @{
          @"scenario" : @{ @"id" : @(sid), @"name" : ac_str(sc[@"name"], @"Scenario"),
                           @"detectionQuality" : @(q), @"endConditionOperator" : @([sc[@"endAll"] boolValue] ? 1 : 2) },
          @"events" : events, @"endConditions" : ends
        }
      };
      NSData *json = [NSJSONSerialization dataWithJSONObject:root options:0 error:NULL];
      if (!json) return NO;
      [zw add:[NSString stringWithFormat:@"%@/%@.json", folder, folder] data:json];
    }
    done++;
    if (progress) progress(done);
  }
  if (skippedEvents) *skippedEvents = skipped;
  if (skippedApps) *skippedApps = apps;
  return [[zw finish] writeToFile:zipPath atomically:YES];
}
