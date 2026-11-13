// Android backup zip layout:
//   <scenarioId>/<scenarioId>.json      { version: 8, screenWidth, screenHeight, scenario: { scenario, events, endConditions } }
//   <scenarioId>/Condition_<number>     raw RGBA_8888 pixels of a condition, (areaRight-areaLeft) x (areaBottom-areaTop)
#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

typedef struct {
  NSInteger imported, failed, skippedActions;
  BOOL otherScreen; // positions were rescaled
  CGSize screen;
} ACImportResult;

// appends to gRoot, caller saves
BOOL ac_importBackup(NSString *zipPath, ACImportResult *result, void (^progress)(NSInteger done));

// skips events Android would reject, and Open app actions
BOOL ac_exportBackup(NSArray<NSDictionary *> *scenarios, CGSize screen, NSString *zipPath, NSInteger *skippedEvents,
                     NSInteger *skippedApps, void (^progress)(NSInteger done));
