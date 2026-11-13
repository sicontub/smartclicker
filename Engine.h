#pragma once
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define AC_DIR @"/var/mobile/Library/SmartClicker"
#define AC_JSON @"/var/mobile/Library/SmartClicker/scenarios.json"
#define AC_COARSE 8
#define AC_QUALITY_MIN 400
#define AC_QUALITY_MAX 1200
#define AC_QUALITY_DEFAULT 600
#define AC_BGRA_INFO (kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little)

static inline void ac_after(double sec, void (^b)(void)) {
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(sec * NSEC_PER_SEC)), dispatch_get_main_queue(), b);
}

extern CGSize gFixedSize;
extern CGFloat gNativeScale;
extern int gNativeW, gNativeH;

void ac_loadSymbols(void);
void ac_hidSetup(void);
bool ac_withScreen(void (^use)(const uint8_t *base, size_t bpr));

// scenarios.json:
// root { selected, scenarios: [ { id, name, detectionQuality (400..1200), endAll, endConditions: [ {event, executions} ],
//   events: [ { id, name, all, conditions: [ {id, name, x, y, w, h (native px), tol, whole, detect} ],
//               actions: [ {name, t: click|swipe|pause|app, x, y, x2, y2 (points), onCond, d (ms), bundleId, appName} ] } ] } ] }
extern NSMutableDictionary *gRoot;
NSMutableDictionary *ac_mutableDeep(id o);
NSString *ac_newId(void);
NSString *ac_condPath(NSString *cid);
NSMutableDictionary *ac_newScenario(NSString *name);
void ac_load(void);
void ac_save(void);
NSMutableArray *ac_scenarios(void);
NSMutableDictionary *ac_current(void);

extern volatile bool gRunning;
extern volatile bool gDebug;
// thread safe
NSDictionary *ac_debugInfo(void);
extern void (^gOnStop)(NSString *reason);
void ac_openApp(NSString *bundleId);
int ac_qualityFactor(NSDictionary *scenario);
void ac_play(NSDictionary *scenario); // blocking, call it from a background thread
