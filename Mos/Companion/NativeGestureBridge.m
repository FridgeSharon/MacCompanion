// DockSwipe fields and gesture phases studied from Mac Mouse Fix by Noah Nuebling.
// Reference: 2dae68a01ebcb4c645161160a7872a60ecf58ace, TouchSimulator.m.
// See MacMouseFix-LICENSE.txt. This bridge uses SkyLight's exported setter rather
// than the reference's historical pointer-offset implementation.
#import "NativeGestureBridge.h"
#import <dlfcn.h>
#import <objc/runtime.h>
#import <mach/mach_time.h>

@protocol MCPrivateHIDEvent <NSObject>
- (instancetype)initWithType:(uint32_t)type timestamp:(uint64_t)timestamp senderID:(uint64_t)senderID;
- (void)setOptions:(uint32_t)options;
- (uint32_t)options;
- (void)setIntegerValue:(NSInteger)value forField:(uint32_t)field;
- (void)setDoubleValue:(double)value forField:(uint32_t)field;
- (NSInteger)integerValueForField:(uint32_t)field;
- (double)doubleValueForField:(uint32_t)field;
- (void)appendEvent:(id)event;
- (uint32_t)type;
@end

static void (*setHID)(CGEventRef, CFTypeRef);
static CFTypeRef (*copyHID)(CGEventRef);
static CFArrayRef (*copySpaces)(int);
static int (*connectionID)(void);
static Class hidClass;
static const uint32_t dockType = 23, velocityType = 9;
static const uint32_t motionField = (23 << 16) + 1;
static const uint32_t progressField = (23 << 16) + 2;
static const uint32_t flavorField = (23 << 16) + 5;

BOOL MCNativeGestureBridgeAvailable(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion != 27) return;
        void *sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL);
        dlopen("/System/Library/PrivateFrameworks/HID.framework/HID", RTLD_LAZY | RTLD_LOCAL);
        if (!sky) return;
        setHID = dlsym(sky, "SLEventSetIOHIDEvent");
        copyHID = dlsym(sky, "CGEventCopyIOHIDEvent");
        copySpaces = dlsym(sky, "SLSCopyManagedDisplaySpaces");
        if (!copySpaces) copySpaces = dlsym(sky, "CGSCopyManagedDisplaySpaces");
        connectionID = dlsym(sky, "SLSMainConnectionID");
        if (!connectionID) connectionID = dlsym(sky, "CGSMainConnectionID");
        hidClass = NSClassFromString(@"HIDEvent");
    });
    return setHID && copyHID && hidClass &&
        [hidClass instancesRespondToSelector:@selector(initWithType:timestamp:senderID:)] &&
        [hidClass instancesRespondToSelector:@selector(setOptions:)] &&
        [hidClass instancesRespondToSelector:@selector(setDoubleValue:forField:)];
}

static CGEventRef makeEvent(int motion, double progress, uint32_t phase, double velocity) {
    if (!MCNativeGestureBridgeAvailable() || (motion != 1 && motion != 2) ||
        !isfinite(progress) || !isfinite(velocity) || !(phase == 1 || phase == 2 || phase == 4 || phase == 8)) return NULL;
    @try {
        id<MCPrivateHIDEvent> hid = [(id<MCPrivateHIDEvent>)[hidClass alloc] initWithType:dockType timestamp:mach_absolute_time() senderID:0];
        if (!hid) return NULL;
        [hid setOptions:phase << 24];
        [hid setIntegerValue:motion forField:motionField];
        [hid setIntegerValue:3 forField:flavorField]; // Dock primary
        [hid setDoubleValue:progress forField:progressField];
        if (phase == 4 || phase == 8) {
            id<MCPrivateHIDEvent> child = [(id<MCPrivateHIDEvent>)[hidClass alloc] initWithType:velocityType timestamp:mach_absolute_time() senderID:0];
            if (!child) return NULL;
            [child setDoubleValue:velocity forField:(velocityType << 16)];
            [child setDoubleValue:velocity forField:(velocityType << 16) + 1];
            [child setDoubleValue:0 forField:(velocityType << 16) + 2];
            [hid appendEvent:child];
        }
        CGEventRef cg = CGEventCreate(NULL);
        if (!cg) return NULL;
        CGEventSetType(cg, (CGEventType)30);
        setHID(cg, (__bridge CFTypeRef)hid);
        CGEventSetIntegerValueField(cg, kCGEventSourceUserData, 0x4D434753); // MC native gesture
        return cg;
    } @catch (NSException *exception) { return NULL; }
}

BOOL MCNativeGestureBridgeRoundTrip(void) {
    CGEventRef event = makeEvent(1, 0.125, 1, 0);
    if (!event) return NO;
    BOOL valid = NO;
    CFTypeRef copied = copyHID(event);
    if (copied) {
        @try {
            id<MCPrivateHIDEvent> hid = (__bridge id)copied;
            valid = hid.type == dockType && ((hid.options >> 24) & 0xf) == 1 && [hid integerValueForField:motionField] == 1 &&
                fabs([hid doubleValueForField:progressField] - 0.125) < 0.0001;
        } @catch (NSException *exception) { valid = NO; }
        CFRelease(copied);
    }
    CFRelease(event);
    return valid;
}

BOOL MCPostDockSwipe(int motion, double progress, uint32_t phase, double velocity) {
    CGEventRef event = makeEvent(motion, progress, phase, velocity);
    if (!event) return NO;
    CGEventPost(kCGSessionEventTap, event);
    CFRelease(event);
    return YES;
}

NSInteger MCSpaceCountForDisplay(NSString *displayUUID) {
    if (!MCNativeGestureBridgeAvailable() || !copySpaces || !connectionID) return 1;
    CFArrayRef copied = copySpaces(connectionID());
    if (!copied) return 1;
    NSArray *displays = CFBridgingRelease(copied);
    for (NSDictionary *display in displays) {
        if ([display[@"Display Identifier"] isEqual:displayUUID]) return MAX(1, [display[@"Spaces"] count]);
    }
    return 1;
}

BOOL MCPhysicalMouseButtonDown(int button) {
    if (button < 0 || button > 31) return NO;
    return CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, (CGMouseButton)button);
}

NSDictionary *MCCopyDockSwipeSummary(CGEventRef event) {
    if (!event || !MCNativeGestureBridgeAvailable()) return nil;
    CFTypeRef copied = copyHID(event);
    if (!copied) return nil;
    NSDictionary *result = nil;
    @try {
        id<MCPrivateHIDEvent> hid = (__bridge id)copied;
        if (hid.type == dockType) {
            result = @{ @"event": @"trackpad-packet", @"motion": @([hid integerValueForField:motionField]),
                @"phase": @((hid.options >> 24) & 0xf), @"progress": @([hid doubleValueForField:progressField]),
                @"flavor": @([hid integerValueForField:flavorField]) };
        }
    } @catch (NSException *exception) {}
    CFRelease(copied);
    return result;
}
