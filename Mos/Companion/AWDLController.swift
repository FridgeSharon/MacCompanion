import Cocoa
import Network
import ServiceManagement

// Mirrors AWDLControl's modes; keep preference import separate from mouse settings.
enum AWDLMode: Int, CaseIterable {
    case game = 0, on = 1, off = 2
    var title: String {
        NSLocalizedString(["Automatic for games", "AWDL on", "AWDL off"][rawValue], comment: "AWDL mode")
    }
    func suppress(onWiFi: Bool, gameActive: Bool, sessionActive: Bool = true) -> Bool {
        switch self { case .game: return sessionActive && onWiFi && gameActive; case .on: return false; case .off: return true }
    }
    static func isGame(_ info: [String: Any]) -> Bool {
        info["LSApplicationCategoryType"] as? String == "public.app-category.games" || (info["LSSupportsGameMode"] as? Bool == true)
    }
}

/// Waking a display does not necessarily reactivate this user's session.
struct AWDLSessionState {
    private var awake = true
    private var active = true
    var allowsAutomaticSuppression: Bool { awake && active }

    mutating func receive(_ name: Notification.Name) {
        switch name {
        case NSWorkspace.willSleepNotification: awake = false
        case NSWorkspace.didWakeNotification: awake = true
        case NSWorkspace.sessionDidResignActiveNotification: active = false
        case NSWorkspace.sessionDidBecomeActiveNotification: active = true
        default: break
        }
    }
}

@objc(CompanionAWDLProtocol) protocol CompanionAWDLProtocol {
    @objc(setSuppressed:withReply:) func setSuppressed(_ suppressed: Bool, withReply reply: @escaping (Bool, Int32) -> Void)
}

/// The unprivileged app owns game/network policy. The signed helper accepts only this
/// app and exposes one boolean operation, with no arbitrary commands or interface names.
final class AWDLController {
    static let shared = AWDLController()
    static let changed = Notification.Name("CompanionAWDLChanged")
    static let serviceName = "com.github.FridgeSharon.MacCompanion.AWDLHelper"
    private let service = SMAppService.daemon(plistName: "com.github.FridgeSharon.MacCompanion.AWDLHelper.plist")
    private var connection: NSXPCConnection?
    private var monitor: NWPathMonitor?
    private var tokens: [NSObjectProtocol] = []
    private var timer: Timer?
    private var onWiFi = false
    private var requestPending = false
    private var stopped = true
    private var session = AWDLSessionState()
    private var requestID: UInt64 = 0
    private(set) var interfaceUp: Bool?
    private(set) var status = NSLocalizedString("AWDL control is off", comment: "") {
        didSet { if oldValue != status { NotificationCenter.default.post(name: Self.changed, object: self) } }
    }
    private var lastError: String?
    private var desiredSuppression = false
    private let defaults: UserDefaults
    private(set) var mode: AWDLMode
    var enabled: Bool { defaults.bool(forKey: "companionAWDLEnabledV1") }
    var helperStatus: SMAppService.Status { service.status }
    var otherControllerRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.jh.AWDLControl").isEmpty
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.object(forKey: "companionAWDLModeV1") as? Int { mode = AWDLMode(rawValue: raw) ?? .game }
        else {
            let imported = UserDefaults(suiteName: "com.jh.AWDLControl")?.integer(forKey: "AWDLMode") ?? 0
            mode = AWDLMode(rawValue: imported) ?? .game
            if !AppRuntime.isRunningXCTest { defaults.set(mode.rawValue, forKey: "companionAWDLModeV1") }
        }
        if defaults.bool(forKey: "companionAWDLEnabledV1") {
            status = NSLocalizedString("Waiting for AWDL helper", comment: "")
        }
    }
    func start() {
        guard stopped, !AppRuntime.isRunningXCTest else { return }
        stopped = false
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                self?.session.receive(note.name); self?.refresh()
            })
        }
        let path = NWPathMonitor(); monitor = path
        path.pathUpdateHandler = { [weak self, weak path] update in
            DispatchQueue.main.async {
                guard let self, !self.stopped, self.monitor === path else { return }
                self.onWiFi = update.status == .satisfied && update.usesInterfaceType(.wifi)
                self.refresh()
            }
        }
        path.start(queue: DispatchQueue(label: "com.github.FridgeSharon.MacCompanion.network"))
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 0.5
        refresh()
    }
    func stop() {
        stopped = true; timer?.invalidate(); timer = nil; monitor?.cancel(); monitor = nil; onWiFi = false
        for token in tokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }; tokens.removeAll()
        disconnect() // helper restores AWDL before exiting, including after a client crash
    }
    func setMode(_ mode: AWDLMode) {
        self.mode = mode; defaults.set(mode.rawValue, forKey: "companionAWDLModeV1"); refresh()
        NotificationCenter.default.post(name: Self.changed, object: self)
    }
    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: "companionAWDLEnabledV1"); lastError = nil
        if enabled {
            do {
                if service.status == .notRegistered || service.status == .notFound { try service.register() }
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            } catch { lastError = error.localizedDescription }
        }
        refresh()
    }
    func openApproval() { SMAppService.openSystemSettingsLoginItems() }
    func removeHelper() {
        defaults.set(false, forKey: "companionAWDLEnabledV1"); disconnect()
        service.unregister { [weak self] error in
            DispatchQueue.main.async { self?.lastError = error?.localizedDescription; self?.refresh() }
        }
    }
    private func disconnect() {
        requestID &+= 1; requestPending = false
        let old = connection; connection = nil; interfaceUp = nil
        old?.invalidationHandler = nil; old?.interruptionHandler = nil; old?.invalidate()
    }
    func refresh() {
        guard !stopped else { return }
        guard enabled else { disconnect(); status = NSLocalizedString("AWDL control is off", comment: ""); return }
        guard !otherControllerRunning else {
            disconnect(); status = NSLocalizedString("Quit AWDLControl to use the integrated controls", comment: ""); return
        }
        guard service.status == .enabled else {
            disconnect()
            status = lastError ?? NSLocalizedString(service.status == .requiresApproval
                ? "Approve Mac Companion in Login Items & Extensions" : "Enable the bundled helper to control AWDL", comment: "")
            return
        }
        let active = NSWorkspace.shared.frontmostApplication
        let game = active?.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary }.map(AWDLMode.isGame) ?? false
        desiredSuppression = mode.suppress(onWiFi: onWiFi, gameActive: game,
            sessionActive: session.allowsAutomaticSuppression)
        if connection == nil {
            let client = NSXPCConnection(machServiceName: Self.serviceName, options: .privileged)
            client.remoteObjectInterface = NSXPCInterface(with: CompanionAWDLProtocol.self)
            client.setCodeSigningRequirement("anchor apple generic and identifier \"com.github.FridgeSharon.MacCompanion.AWDLHelper\" and certificate leaf[subject.OU] = \"YOUR_TEAM_ID\"")
            client.invalidationHandler = { [weak self, weak client] in
                DispatchQueue.main.async {
                    guard let self, self.connection === client else { return }
                    self.requestID &+= 1
                    self.connection = nil; self.requestPending = false; self.interfaceUp = nil
                    self.status = NSLocalizedString("AWDL helper disconnected; retrying", comment: "")
                }
            }
            client.interruptionHandler = client.invalidationHandler
            connection = client; client.resume()
        }
        guard !requestPending, let client = connection else { return }
        requestPending = true; requestID &+= 1; let id = requestID
        let object = client.remoteObjectProxyWithErrorHandler { [weak self] error in
            DispatchQueue.main.async {
                guard let self, self.requestID == id else { return }
                self.disconnect(); self.status = error.localizedDescription
            }
        }
        guard let proxy = object as? CompanionAWDLProtocol else {
            disconnect(); status = NSLocalizedString("AWDL helper disconnected; retrying", comment: ""); return
        }
        let requested = desiredSuppression
        if interfaceUp == nil || interfaceUp == requested {
            status = NSLocalizedString("Applying AWDL setting…", comment: "")
        }
        proxy.setSuppressed(requested) { [weak self] up, error in
            DispatchQueue.main.async {
                guard let self, self.requestID == id else { return }
                self.requestPending = false; self.interfaceUp = up
                if error != 0 { self.status = String(format: NSLocalizedString("Could not change AWDL: %@", comment: ""), String(cString: strerror(error))) }
                else if up == requested { self.status = NSLocalizedString("AWDL state changed externally; retrying", comment: "") }
                else if requested { self.status = NSLocalizedString("AWDL is off", comment: "") }
                else { self.status = NSLocalizedString("AWDL is on", comment: "") }
                if requested != self.desiredSuppression { self.refresh() }
            }
        }
        // A missing reply must not leave policy stuck indefinitely.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.requestID == id, self.requestPending else { return }
            self.disconnect(); self.status = NSLocalizedString("AWDL helper did not respond; retrying", comment: "")
        }
    }
}
