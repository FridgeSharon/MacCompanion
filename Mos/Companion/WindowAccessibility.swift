import Cocoa

struct CompanionWindowKey: Hashable { let pid: pid_t; let number: CGWindowID }
struct CompanionWindow {
    let key: CompanionWindowKey
    let element: AXUIElement
    let rawFrame: CGRect
    let titlebar: Bool
    var hitPath: [String] = [] // role names only, opt-in diagnostics; no text/content
}

/// One serial lane for window inspection, native correction, and direct placement.
/// Event callbacks only capture lightweight input; AX messaging never runs there.
enum WindowAccessibility {
    static let queue = DispatchQueue(label: "com.github.FridgeSharon.MacCompanion.window-placement", qos: .userInitiated)
    // Read-only first-click verification must not queue behind a full app scan.
    static let inputInspectionQueue = DispatchQueue(label: "com.github.FridgeSharon.MacCompanion.titlebar-inspection", qos: .userInteractive)
    private static let diagnostics = ProcessInfo.processInfo.arguments.contains("--companion-diagnostics")
    static func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }
    static func frame(_ element: AXUIElement) -> CGRect? { StageManagerGuardian.frame(element) }
    static func flipped(_ frame: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
    }
    static func serverInfo(_ number: CGWindowID) -> [String: Any]? {
        (CGWindowListCopyWindowInfo(.optionIncludingWindow, number) as? [[String: Any]])?.first {
            ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == number
        }
    }
    static func serverFrame(_ number: CGWindowID) -> CGRect? {
        guard let bounds = serverInfo(number)?[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: bounds)
    }
    static func eligible(_ element: AXUIElement) -> Bool {
        value(element, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole &&
            value(element, kAXMinimizedAttribute) as? Bool != true && value(element, "AXFullScreen") as? Bool != true
    }
    static func hit(at point: CGPoint, number requestedNumber: CGWindowID, config: CompanionConfiguration) -> CompanionWindow? {
        // Global NSEvent monitors can receive a CGEvent whose WindowServer fields
        // are zero. Resolve that case from the on-screen z-order, off the input path.
        let requested = requestedNumber == 0 ? nil : serverInfo(requestedNumber)
        let windows = requested.map { [$0] } ?? []
        var info = WindowHitSelection.select(at: point, requested: requested, windows: windows)
        if info == nil {
            let visible = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            info = WindowHitSelection.select(at: point, requested: nil, windows: visible)
        }
        guard let info, let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
              let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
              pid != getpid(), let app = NSRunningApplication(processIdentifier: pid),
              !CompanionSettings.matches(paths: config.excludedPaths, bundlePath: app.bundleURL?.path, executablePath: app.executableURL?.path) else { return nil }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.08)
        let server = CGRect(dictionaryRepresentation: info[kCGWindowBounds as String] as? NSDictionary ?? [:])
        guard let server else { return nil }
        var reported: AXUIElement?
        AXUIElementCopyElementAtPosition(application, Float(point.x), Float(point.y), &reported)
        // Resolve the target AX window independently when Catalyst returns no
        // element, or a nearest control with no useful AXWindow relationship.
        let list = value(application, kAXWindowsAttribute) as? [AXUIElement] ?? []
        guard let window = list.first(where: {
            eligible($0) && frame($0).map { StageLayout.near($0, server, tolerance: 5) } == true
        }), let rawFrame = frame(window) else { return nil }
        AXUIElementSetMessagingTimeout(window, 0.08)
        func bounded(_ initial: AXUIElement) -> AXUIElement? {
            BoundedAccessibilityHit.resolve(initial, at: point,
                frame: { self.frame($0) },
                parent: { element in
                    guard let parent = value(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
                    return unsafeBitCast(parent, to: AXUIElement.self)
                }, children: { value($0, kAXChildrenAttribute) as? [AXUIElement] ?? [] },
                isControl: { TitlebarHitRegion.isControl(role: value($0, kAXRoleAttribute) as? String ?? "", identifier: value($0, kAXIdentifierAttribute) as? String ?? "") })
        }
        guard let hit = reported.flatMap(bounded) ?? bounded(window) else { return nil }
        var path: [String] = []
        let titlebar = isTitlebar(hit, window: window, point: point, frame: rawFrame, path: &path)
        return CompanionWindow(key: CompanionWindowKey(pid: pid, number: number), element: window,
            rawFrame: rawFrame, titlebar: titlebar, hitPath: path)
    }
    static func focused(pid: pid_t, config: CompanionConfiguration) -> CompanionWindow? {
        guard pid != getpid(), let app = NSRunningApplication(processIdentifier: pid),
              !CompanionSettings.matches(paths: config.excludedPaths, bundlePath: app.bundleURL?.path, executablePath: app.executableURL?.path) else { return nil }
        let application = AXUIElementCreateApplication(pid); AXUIElementSetMessagingTimeout(application, 0.08)
        guard let focused = value(application, kAXFocusedWindowAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let window = unsafeBitCast(focused, to: AXUIElement.self); AXUIElementSetMessagingTimeout(window, 0.08)
        guard eligible(window), let raw = frame(window),
              let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]])?.first(where: {
                  guard ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                        $0[kCGWindowLayer as String] as? Int == 0,
                        let bounds = $0[kCGWindowBounds as String] as? NSDictionary,
                        let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
                  return StageLayout.near(raw, rect, tolerance: 5)
              }), let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { return nil }
        return CompanionWindow(key: CompanionWindowKey(pid: pid, number: number), element: window, rawFrame: raw, titlebar: false)
    }
    private static func isTitlebar(_ hit: AXUIElement, window: AXUIElement, point: CGPoint, frame: CGRect, path: inout [String]) -> Bool {
        let close = value(window, kAXCloseButtonAttribute).flatMap { raw -> CGRect? in
            guard CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
            return self.frame(unsafeBitCast(raw, to: AXUIElement.self))
        }
        let height = TitlebarHitRegion.nativeHeight(window: frame, closeButton: close)
        if diagnostics { path.append("native-titlebar-height=\(height)") }
        var current = hit
        var nodes: [TitlebarHitRegion.Node] = []
        for _ in 0..<20 {
            guard let role = value(current, kAXRoleAttribute) as? String else { return false }
            let identifier = value(current, kAXIdentifierAttribute) as? String ?? ""
            if diagnostics {
                let subrole = value(current, kAXSubroleAttribute) as? String ?? ""
                path.append(role + " frame=" + (self.frame(current).map(NSStringFromRect) ?? "nil") + " id=" + identifier + " subrole=" + subrole)
            } else { path.append(role) }
            let toolbar = role == kAXToolbarRole || identifier == "WDSNavigationBar" ? self.frame(current) : nil
            nodes.append(TitlebarHitRegion.Node(role: role, frame: toolbar, identifier: identifier))
            if role == kAXWindowRole {
                return CFEqual(current, window) && TitlebarHitRegion.contains(point, window: frame, path: nodes, nativeHeight: height)
            }
            if !diagnostics && TitlebarHitRegion.isControl(role: role, identifier: identifier) { return false }
            guard let parent = value(current, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return false }
            current = unsafeBitCast(parent, to: AXUIElement.self)
        }
        return false
    }
    @discardableResult static func placeRaw(_ target: CGRect, on window: AXUIElement, bounds: CGRect) -> CGRect? {
        guard target.width > 0, target.height > 0, eligible(window) else { return nil }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &settable) == .success, settable.boolValue else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.08)
        return AccessibilityFrameTransaction.perform(
            readEnhanced: { value(app, "AXEnhancedUserInterface") as? Bool },
            writeEnhanced: { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, $0 ? kCFBooleanTrue : kCFBooleanFalse) == .success },
            adjustment: { placeImmediate(target, on: window, bounds: bounds) })
    }
    private static func placeImmediate(_ target: CGRect, on window: AXUIElement, bounds: CGRect) -> CGRect? {
        if let current = frame(window), !WindowLayoutGeometry.resizeBeforeMove(current: current, target: target, bounds: bounds) {
            var initialPoint = target.origin
            guard let position = AXValueCreate(.cgPoint, &initialPoint),
                  AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position) == .success else { return nil }
        }
        var size = target.size
        guard let sizeValue = AXValueCreate(.cgSize, &size),
              AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) == .success,
              let accepted = frame(window) else { return nil }
        var point = target.origin
        if abs(target.maxX - bounds.maxX) < 2 && abs(target.minX - bounds.minX) > 2 { point.x = bounds.maxX - accepted.width }
        if abs(target.maxY - bounds.maxY) < 2 && abs(target.minY - bounds.minY) > 2 { point.y = bounds.maxY - accepted.height }
        point.x = min(max(point.x, bounds.minX), max(bounds.minX, bounds.maxX - accepted.width))
        point.y = min(max(point.y, bounds.minY), max(bounds.minY, bounds.maxY - accepted.height))
        guard let position = AXValueCreate(.cgPoint, &point),
              AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position) == .success else { return nil }
        return frame(window)
    }
}

/// Enhanced UI handling studied from Rectangle (Ryan Hanson and contributors,
/// MIT; see Rectangle-LICENSE.txt). This variant always restores the prior mode.
/// Chromium can animate AX frame writes in Enhanced UI mode. Keep the two writes
/// and their readback in one transaction, preserving the app's prior accessibility
/// setting even on an early failure. Unlike a persistent accessibility policy,
/// this never leaves Enhanced UI disabled between window actions.
enum AccessibilityFrameTransaction {
    static func perform<T>(readEnhanced: () -> Bool?, writeEnhanced: (Bool) -> Bool, adjustment: () -> T) -> T {
        let wasEnhanced = readEnhanced() == true
        if wasEnhanced { _ = writeEnhanced(false) }
        defer { if wasEnhanced { _ = writeEnhanced(true) } }
        return adjustment()
    }
}
