import Cocoa

enum GestureDirection: String, Codable, CaseIterable {
    case up, down, left, right
    var title: String { NSLocalizedString(rawValue.capitalized, comment: "Gesture direction") }
}

enum CompanionAction: String, Codable, CaseIterable {
    case missionControl, appExpose, moveSpaceLeft, moveSpaceRight, showDesktop, back, forward, none
    var title: String {
        let labels: [Self: String] = [.missionControl: "missionControl", .appExpose: "App Exposé",
            .moveSpaceLeft: "Previous desktop", .moveSpaceRight: "Next desktop",
            .showDesktop: "showDesktop", .back: "Back", .forward: "Forward", .none: "Do nothing"]
        return NSLocalizedString(labels[self]!, comment: "Mouse gesture action")
    }
    func perform() {
        guard self != .none else { return }
        if self == .moveSpaceLeft || self == .moveSpaceRight {
            if let configured = SystemShortcut.resolveSystemShortcut(rawValue) {
                ShortcutExecutor.shared.execute(code: configured.code, flags: configured.modifiers)
            } else {
                // Fn-Control-Arrows are native window tiling on current macOS. Desktop
                // navigation must fall back to Control-Arrows without the Fn modifier.
                ShortcutExecutor.shared.execute(code: self == .moveSpaceLeft ? 123 : 124, flags: CGEventFlags.maskControl.rawValue)
            }
            return
        }
        let identifier = self == .back ? "navigateBack" : (self == .forward ? "navigateForward" : rawValue)
        ShortcutExecutor.shared.execute(named: identifier)
    }
}

enum GestureBackend: String, Codable { case actions, continuous }
enum WindowSizingMode: String, Codable { case nativeCorrection, direct }

struct CompanionConfiguration: Codable, Equatable {
    var gesturesEnabled = true
    // Quartz numbers 3 and 4 are the two standard thumb buttons (buttons 4 and 5 in UIs).
    var gestureButton = 3
    var gestureThreshold: Double = 40
    var up: CompanionAction = .missionControl
    var down: CompanionAction = .appExpose
    var left: CompanionAction = .moveSpaceLeft
    var right: CompanionAction = .moveSpaceRight
    var stageEnabled = true
    var stageWidth: Double = 151.2975
    var excludedPaths: [String] = []
    var gestureBackend: GestureBackend = .actions
    var trackpadPresetApplied = false
    var gestureSensitivity: Double = 1
    var windowSizingMode: WindowSizingMode = .nativeCorrection

    enum CodingKeys: String, CodingKey {
        case gesturesEnabled, gestureButton, gestureThreshold, up, down, left, right
        case stageEnabled, stageWidth, excludedPaths, gestureBackend, gestureSensitivity, windowSizingMode, trackpadPresetApplied
    }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        gesturesEnabled = try values.decodeIfPresent(Bool.self, forKey: .gesturesEnabled) ?? true
        gestureButton = try values.decodeIfPresent(Int.self, forKey: .gestureButton) ?? 3
        gestureThreshold = try values.decodeIfPresent(Double.self, forKey: .gestureThreshold) ?? 40
        up = try values.decodeIfPresent(CompanionAction.self, forKey: .up) ?? .missionControl
        down = try values.decodeIfPresent(CompanionAction.self, forKey: .down) ?? .appExpose
        left = try values.decodeIfPresent(CompanionAction.self, forKey: .left) ?? .moveSpaceLeft
        right = try values.decodeIfPresent(CompanionAction.self, forKey: .right) ?? .moveSpaceRight
        stageEnabled = try values.decodeIfPresent(Bool.self, forKey: .stageEnabled) ?? true
        stageWidth = try values.decodeIfPresent(Double.self, forKey: .stageWidth) ?? 151.2975
        excludedPaths = try values.decodeIfPresent([String].self, forKey: .excludedPaths) ?? []
        trackpadPresetApplied = try values.decodeIfPresent(Bool.self, forKey: .trackpadPresetApplied) ?? false
        gestureBackend = try values.decodeIfPresent(GestureBackend.self, forKey: .gestureBackend) ?? .actions
        gestureSensitivity = try values.decodeIfPresent(Double.self, forKey: .gestureSensitivity) ?? 1
        windowSizingMode = try values.decodeIfPresent(WindowSizingMode.self, forKey: .windowSizingMode) ?? .nativeCorrection
        validate()
    }
    func action(for direction: GestureDirection) -> CompanionAction {
        switch direction { case .up: return up; case .down: return down; case .left: return left; case .right: return right }
    }
    mutating func setAction(_ action: CompanionAction, for direction: GestureDirection) {
        switch direction { case .up: up = action; case .down: down = action; case .left: left = action; case .right: right = action }
    }
    mutating func selectBackend(_ backend: GestureBackend) {
        gestureBackend = backend
        if backend == .continuous && !trackpadPresetApplied {
            if left == .moveSpaceLeft && right == .moveSpaceRight { left = .moveSpaceRight; right = .moveSpaceLeft }
            trackpadPresetApplied = true
        }
    }
    mutating func validate() {
        gestureSensitivity = gestureSensitivity.isFinite ? min(3, max(0.25, gestureSensitivity)) : 1
        if ![3, 4].contains(gestureButton) { gestureButton = 3 }
        gestureThreshold = gestureThreshold.isFinite ? min(150, max(10, gestureThreshold)) : 40
        stageWidth = stageWidth.isFinite ? min(500, max(40, stageWidth)) : 151.2975
        excludedPaths = Array(Set(excludedPaths.filter { $0.hasPrefix("/") })).sorted()
    }
}

final class CompanionSettings {
    static let shared = CompanionSettings()
    static let key = "companionConfigurationV1"
    static let changed = Notification.Name("CompanionConfigurationChanged")
    private(set) var configuration: CompanionConfiguration

    init(defaults: UserDefaults = .standard) {
        if let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode(CompanionConfiguration.self, from: data) {
            configuration = saved
        } else {
            configuration = CompanionConfiguration()
            let rectangle = UserDefaults(suiteName: "com.knollsoft.Rectangle")
            if let width = rectangle?.object(forKey: "stageSize") as? Double, width >= 40 { configuration.stageWidth = width }
            if let data = defaults.data(forKey: OptionItem.Application.Applications),
               let apps = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                configuration.excludedPaths = apps.compactMap { app in
                    guard app["inherit"] as? Bool == false,
                          let scroll = app["scroll"] as? [String: Any], scroll["smooth"] as? Bool == false else { return nil }
                    return app["path"] as? String
                }
            }
        }
        configuration.validate()
    }

    func update(_ body: (inout CompanionConfiguration) -> Void) {
        body(&configuration)
        configuration.validate()
        if !AppRuntime.isRunningXCTest, let data = try? JSONEncoder().encode(configuration) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
        CompanionGestureController.shared.cancel()
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    func isExcluded(_ app: NSRunningApplication?) -> Bool {
        guard let app else { return true }
        return Self.matches(paths: configuration.excludedPaths, bundlePath: app.bundleURL?.path, executablePath: app.executableURL?.path)
    }

    static func matches(paths: [String], bundlePath: String?, executablePath: String?) -> Bool {
        paths.contains { path in
            path == bundlePath || path == executablePath || executablePath?.hasPrefix(path + "/") == true
        }
    }

    // Copy only user configuration, once, before Options seeds defaults. Never copy Sparkle,
    // login-item registrations, window positions, device caches, or permission state.
    static func importMosPreferences(into defaults: UserDefaults = .standard, source: [String: Any]? = nil) {
        guard !AppRuntime.isRunningXCTest, !defaults.bool(forKey: "companionImportedMosV1") else { return }
        let source = source ?? UserDefaults(suiteName: "com.caldis.Mos")?.persistentDomain(forName: "com.caldis.Mos") ?? [:]
        let keys = ["optionsExist", "smooth", "reverse", "reverseVertical", "reverseHorizontal", "smoothVertical",
            "smoothHorizontal", "smoothSimTrackpad", "step", "speed", "duration", "deadZone", "dash", "toggle", "block",
            "buttonBindings", "allowlist", "applications"]
        for key in keys where defaults.object(forKey: key) == nil {
            if let value = source[key] { defaults.set(value, forKey: key) }
        }
        defaults.set(false, forKey: OptionItem.Update.CheckOnAppStart)
        defaults.set(false, forKey: OptionItem.Update.IncludingBetaVersion)
        defaults.set(true, forKey: "companionImportedMosV1")
    }
}
