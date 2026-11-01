// AWDL control derived from James Howard's AWDLControl (MIT, 2026).
// See AWDLControl-LICENSE.txt. This service can change only awdl0's IFF_UP flag.
#import <Foundation/Foundation.h>
#import <sys/socket.h>
#import <sys/ioctl.h>
#import <net/if.h>
#import <net/route.h>
#import <fcntl.h>
#import <signal.h>
#import <unistd.h>

@protocol CompanionAWDLProtocol
- (void)setSuppressed:(BOOL)suppressed withReply:(void (^)(BOOL interfaceUp, int errorCode))reply;
@end

@interface CompanionAWDLService : NSObject <NSXPCListenerDelegate, CompanionAWDLProtocol>
@property dispatch_queue_t queue;
@property dispatch_source_t routeSource;
@property int controlFD;
@property BOOL suppressed;
@property BOOL connected;
@property NSXPCConnection *client;
- (int)enforce;
- (void)finish;
@end

@implementation CompanionAWDLService
- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.github.FridgeSharon.MacCompanion.awdl-helper", DISPATCH_QUEUE_SERIAL);
        _controlFD = socket(AF_INET, SOCK_DGRAM, 0);
        int routeFD = socket(AF_ROUTE, SOCK_RAW, 0);
        if (_controlFD < 0 || routeFD < 0 || fcntl(routeFD, F_SETFL, O_NONBLOCK) < 0) {
            if (_controlFD >= 0) close(_controlFD);
            if (routeFD >= 0) close(routeFD);
            return nil;
        }
        _routeSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, routeFD, 0, _queue);
        __weak typeof(self) weakSelf = self;
        dispatch_source_set_event_handler(_routeSource, ^{
            char buffer[8192];
            // Bound each drain; dispatch will deliver again if messages remain.
            for (int i = 0; i < 64; i++) {
                ssize_t n = read(routeFD, buffer, sizeof(buffer));
                if (n <= 0 && errno == EINTR) continue;
                if (n <= 0) break;
            }
            if (weakSelf.suppressed) [weakSelf enforce];
        });
        dispatch_source_set_cancel_handler(_routeSource, ^{ close(routeFD); });
        dispatch_resume(_routeSource);
    }
    return self;
}
- (int)flags:(struct ifreq *)request {
    memset(request, 0, sizeof(*request));
    strlcpy(request->ifr_name, "awdl0", IFNAMSIZ);
    return ioctl(self.controlFD, SIOCGIFFLAGS, request) == 0 ? 0 : errno;
}
- (int)enforce {
    struct ifreq request;
    int error = [self flags:&request];
    if (error) return error;
    BOOL up = (request.ifr_flags & IFF_UP) != 0;
    if (up == !self.suppressed) return 0;
    if (self.suppressed) request.ifr_flags &= ~IFF_UP;
    else request.ifr_flags |= IFF_UP;
    return ioctl(self.controlFD, SIOCSIFFLAGS, &request) == 0 ? 0 : errno;
}
- (void)setSuppressed:(BOOL)suppressed withReply:(void (^)(BOOL, int))reply {
    dispatch_async(self.queue, ^{
        self.suppressed = suppressed;
        int error = [self enforce];
        struct ifreq request;
        int readError = [self flags:&request];
        reply(readError == 0 && (request.ifr_flags & IFF_UP) != 0, error ?: readError);
    });
}
- (void)finish {
    // Runs on our serial queue after any pending request. Restore on app exit/crash,
    // connection loss, or launchd termination. No persistent suppression without a client.
    self.suppressed = NO;
    [self enforce];
    dispatch_source_cancel(self.routeSource);
    close(self.controlFD);
    exit(0);
}
- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection {
    @synchronized(self) {
        if (self.connected || connection.effectiveUserIdentifier == 0) return NO;
        self.connected = YES;
    }
    self.client = connection;
    __weak typeof(self) weakSelf = self;
    void (^end)(void) = ^{ dispatch_async(weakSelf.queue, ^{ [weakSelf finish]; }); };
    connection.invalidationHandler = end;
    connection.interruptionHandler = end;
    connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(CompanionAWDLProtocol)];
    connection.exportedObject = self;
    [connection resume];
    return YES;
}
@end

int main(void) {
    @autoreleasepool {
        if (geteuid() != 0) return 77;
        CompanionAWDLService *service = [CompanionAWDLService new];
        if (!service) return 1;
        // A crash restarts fail-open; otherwise launch on demand and exit with the app.
        dispatch_async(service.queue, ^{ [service enforce]; });
        NSXPCListener *listener = [[NSXPCListener alloc] initWithMachServiceName:@"com.github.FridgeSharon.MacCompanion.AWDLHelper"];
        [listener setConnectionCodeSigningRequirement:@"anchor apple generic and identifier \"com.github.FridgeSharon.MacCompanion\" and certificate leaf[subject.OU] = \"YOUR_TEAM_ID\""];
        listener.delegate = service;
        [listener resume];
        NSMutableArray *signals = [NSMutableArray new];
        for (NSNumber *number in @[@(SIGTERM), @(SIGINT)]) {
            signal(number.intValue, SIG_IGN);
            dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, number.intValue, 0, service.queue);
            dispatch_source_set_event_handler(source, ^{ [service finish]; });
            dispatch_resume(source);
            [signals addObject:source];
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), service.queue, ^{
            if (!service.connected) [service finish];
        });
        dispatch_main();
    }
}
