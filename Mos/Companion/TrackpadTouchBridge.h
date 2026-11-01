#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>

// Original Mac Companion implementation. Only Apple's platform interface is loaded;
// no code, framework binary or assets from Middle/MiddleClick are included.
typedef void (*MCTrackpadFrameHandler)(uint64_t device, int count, double x, double y,
                                      int contact, bool touching, double timestamp);
// Start/stop on the main thread; frame delivery occurs on the device callback thread.
int MCStartTrackpadFrames(MCTrackpadFrameHandler handler);
void MCStopTrackpadFrames(void);
uint64_t MCTrackpadDeviceForEvent(CGEventRef event);
