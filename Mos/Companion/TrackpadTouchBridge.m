#import "TrackpadTouchBridge.h"
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>
#import <os/lock.h>
#import <math.h>

// Only the first contact's common ABI prefix is read. No array stride assumptions
// or pointer-offset mutation are used. Future OS versions are gated out.
typedef struct {
    int32_t frame; double time; int32_t contact, state, finger, hand;
    float x, y;
} MCContactPrefix;
typedef void (*MCContactHandler)(CFTypeRef, const MCContactPrefix *, int, double, int);
typedef struct { CFTypeRef handle; uint64_t device, service; } MCDevice;
static MCDevice devices[16];
static int deviceCount;
static CFArrayRef deviceList;
static os_unfair_lock frameLock = OS_UNFAIR_LOCK_INIT;
static MCTrackpadFrameHandler frameHandler;
static CFArrayRef (*createList)(void);
static void (*registerFrame)(CFTypeRef, MCContactHandler);
static void (*unregisterFrame)(CFTypeRef, MCContactHandler);
static int (*startDevice)(CFTypeRef, int);
static int (*stopDevice)(CFTypeRef);
static io_service_t (*getService)(CFTypeRef);
static int (*getDeviceID)(CFTypeRef, uint64_t *);
static CFTypeRef (*copyHID)(CGEventRef);
static CFTypeID (*hidEventType)(void);
static uint64_t (*hidSender)(CFTypeRef);

static void receiveFrame(CFTypeRef device, const MCContactPrefix *contacts, int count, double time, int frame) {
    if (count < 0 || count > 16) return;
    if (count > 0 && (!contacts || !isfinite(contacts->x) || !isfinite(contacts->y) ||
        contacts->x < 0 || contacts->x > 1 || contacts->y < 0 || contacts->y > 1)) return;
    os_unfair_lock_lock(&frameLock);
    uint64_t identifier = 0;
    for (int i = 0; i < deviceCount; i++) if (devices[i].handle == device) { identifier = devices[i].device; break; }
    // Serialize delivery with stop/reset. The Swift receiver only updates its
    // locked recognition state and enqueues main-thread work; it never re-enters
    // this bridge or waits synchronously for the main thread.
    if (frameHandler && identifier) {
        if (count == 0) frameHandler(identifier, 0, 0, 0, 0, false, time);
        else frameHandler(identifier, count, contacts->x, contacts->y, contacts->contact,
                          contacts->state == 3 || contacts->state == 4, time);
    }
    os_unfair_lock_unlock(&frameLock);
}

static BOOL loadInterface(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSInteger major = NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
        if (major < 13 || major > 27) return;
        void *library = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW | RTLD_LOCAL);
        if (!library) return;
        createList = dlsym(library, "MTDeviceCreateList");
        registerFrame = dlsym(library, "MTRegisterContactFrameCallback");
        unregisterFrame = dlsym(library, "MTUnregisterContactFrameCallback");
        startDevice = dlsym(library, "MTDeviceStart"); stopDevice = dlsym(library, "MTDeviceStop");
        getService = dlsym(library, "MTDeviceGetService"); getDeviceID = dlsym(library, "MTDeviceGetDeviceID");
        void *sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL);
        if (sky) copyHID = dlsym(sky, "CGEventCopyIOHIDEvent");
        hidEventType = dlsym(RTLD_DEFAULT, "IOHIDEventGetTypeID");
        hidSender = dlsym(RTLD_DEFAULT, "IOHIDEventGetSenderID");
    });
    return createList && registerFrame && unregisterFrame && startDevice && stopDevice && getService && getDeviceID;
}

int MCStartTrackpadFrames(MCTrackpadFrameHandler handler) {
    MCStopTrackpadFrames();
    if (!handler || !loadInterface()) return 0;
    deviceList = createList();
    if (!deviceList) return 0;
    os_unfair_lock_lock(&frameLock); frameHandler = handler; os_unfair_lock_unlock(&frameLock);
    for (CFIndex i = 0; i < CFArrayGetCount(deviceList) && deviceCount < 16; i++) {
        CFTypeRef handle = CFArrayGetValueAtIndex(deviceList, i);
        io_service_t service = getService(handle);
        if (!service) continue;
        CFTypeRef name = IORegistryEntrySearchCFProperty(service, kIOServicePlane, CFSTR("Product"),
            kCFAllocatorDefault, kIORegistryIterateRecursively | kIORegistryIterateParents);
        io_name_t className = {0}; IOObjectGetClass(service, className);
        BOOL trackpad = strstr(className, "Trackpad") != NULL;
        if (name) {
            if (CFGetTypeID(name) == CFStringGetTypeID()) trackpad |= [(__bridge NSString *)name rangeOfString:@"trackpad" options:NSCaseInsensitiveSearch].location != NSNotFound;
            CFRelease(name);
        }
        if (!trackpad) continue; // Unknown devices and Magic Mouse are deliberately excluded.
        uint64_t identifier = 0, registry = 0;
        getDeviceID(handle, &identifier); IORegistryEntryGetRegistryEntryID(service, &registry);
        if (!identifier) identifier = registry;
        if (!identifier) continue;
        os_unfair_lock_lock(&frameLock);
        devices[deviceCount++] = (MCDevice){handle, identifier, registry};
        os_unfair_lock_unlock(&frameLock);
        registerFrame(handle, receiveFrame);
        if (startDevice(handle, 0) != 0) {
            unregisterFrame(handle, receiveFrame);
            os_unfair_lock_lock(&frameLock); deviceCount--; os_unfair_lock_unlock(&frameLock);
        }
    }
    return deviceCount;
}

void MCStopTrackpadFrames(void) {
    os_unfair_lock_lock(&frameLock);
    frameHandler = NULL;
    int count = deviceCount; deviceCount = 0;
    os_unfair_lock_unlock(&frameLock);
    for (int i = 0; i < count; i++) {
        unregisterFrame(devices[i].handle, receiveFrame); stopDevice(devices[i].handle);
    }
    if (deviceList) { CFRelease(deviceList); deviceList = NULL; }
}

@protocol MCSenderEvent <NSObject>
@property(readonly) uint64_t senderID;
@end

uint64_t MCTrackpadDeviceForEvent(CGEventRef event) {
    if (!copyHID) return 0;
    CFTypeRef hid = copyHID(event);
    if (!hid) return 0;
    uint64_t sender = 0;
    if (hidSender && hidEventType && CFGetTypeID(hid) == hidEventType()) sender = hidSender(hid);
    @try {
        id<MCSenderEvent> object = (__bridge id)hid;
        if (!sender && [object respondsToSelector:@selector(senderID)]) sender = object.senderID;
    } @catch (NSException *exception) {}
    CFRelease(hid);
    if (!sender) return 0;
    uint64_t identifier = 0;
    os_unfair_lock_lock(&frameLock);
    for (int i = 0; i < deviceCount; i++) {
        if (sender == devices[i].device || sender == devices[i].service) { identifier = devices[i].device; break; }
    }
    os_unfair_lock_unlock(&frameLock);
    return identifier;
}
