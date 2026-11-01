#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// macOS 27 DockSwipe bridge. No private object-memory offsets are used.
BOOL MCNativeGestureBridgeAvailable(void);
BOOL MCNativeGestureBridgeRoundTrip(void); // allocates/reads events; never posts input
BOOL MCPostDockSwipe(int motion, double progress, uint32_t phase, double velocity);
NSInteger MCSpaceCountForDisplay(NSString *displayUUID);

BOOL MCPhysicalMouseButtonDown(int button);

NSDictionary *MCCopyDockSwipeSummary(CGEventRef event); // diagnostics only; never posts

#import "TrackpadTouchBridge.h"
