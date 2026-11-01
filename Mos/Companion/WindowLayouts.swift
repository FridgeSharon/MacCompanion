import Cocoa

enum CompanionWindowLayout: String, CaseIterable {
    case fill, leftHalf, rightHalf, topHalf, bottomHalf, topLeft, topRight, bottomLeft, bottomRight, restore
    var title: String {
        let names: [Self: String] = [.fill: "Fill / Restore", .leftHalf: "Left half", .rightHalf: "Right half", .topHalf: "Top half", .bottomHalf: "Bottom half",
            .topLeft: "Top left quarter", .topRight: "Top right quarter", .bottomLeft: "Bottom left quarter", .bottomRight: "Bottom right quarter", .restore: "Restore floating size"]
        return NSLocalizedString(names[self]!, comment: "Window layout")
    }
    func frame(in area: CGRect) -> CGRect? {
        let fraction: CGRect
        switch self {
        case .fill: fraction = CGRect(x: 0, y: 0, width: 1, height: 1)
        case .leftHalf: fraction = CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: fraction = CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: fraction = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .bottomHalf: fraction = CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .topLeft: fraction = CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .topRight: fraction = CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .bottomLeft: fraction = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .bottomRight: fraction = CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .restore: return nil
        }
        // Round shared boundaries rather than widths independently: halves/quarters
        // meet exactly even when the usable width is an odd number of points.
        let x1 = (area.minX + fraction.minX * area.width).rounded()
        let y1 = (area.minY + fraction.minY * area.height).rounded()
        let x2 = (area.minX + fraction.maxX * area.width).rounded()
        let y2 = (area.minY + fraction.maxY * area.height).rounded()
        return CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
    }
}
struct CompanionScreen: Equatable {
    let id: String
    let frame: CGRect
    let visible: CGRect
    static func capture() -> [Self] {
        NSScreen.screens.map { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let uuid = number.flatMap { CGDisplayCreateUUIDFromDisplayID($0.uint32Value)?.takeRetainedValue() }
            let id = uuid.map { CFUUIDCreateString(nil, $0) as String } ?? "display-\(number?.uint32Value ?? 0)"
            return Self(id: id, frame: screen.frame, visible: screen.visibleFrame)
        }
    }
    func workingArea(config: CompanionConfiguration, stageOn: Bool, edge: StageEdge) -> CGRect {
        config.stageEnabled && stageOn ? StageLayout.reservedFrame(visible, width: config.stageWidth, edge: edge) : visible
    }
}
struct ManagedWindowPlacement {
    var layout: CompanionWindowLayout?
    var screenID: String
    var applied: CGRect
    var floating: CGRect
    var beforeFill: CGRect?
    var beforeFillLayout: CompanionWindowLayout?
}
enum WindowLayoutGeometry {
    /// Choose the ordering that avoids temporary screen overflow and macOS size
    /// clamping. Offscreen/cross-display moves still resize first.
    static func resizeBeforeMove(current: CGRect, target: CGRect, bounds: CGRect) -> Bool {
        guard bounds.insetBy(dx: -1, dy: -1).contains(current) else { return true }
        func overflow(_ rect: CGRect) -> CGFloat {
            max(0, bounds.minX - rect.minX) + max(0, rect.maxX - bounds.maxX) +
                max(0, bounds.minY - rect.minY) + max(0, rect.maxY - bounds.maxY)
        }
        let resized = overflow(CGRect(origin: current.origin, size: target.size))
        let moved = overflow(CGRect(origin: target.origin, size: current.size))
        return abs(resized - moved) <= 1 || resized < moved
    }
    static func fit(_ frame: CGRect, in bounds: CGRect) -> CGRect {
        let size = CGSize(width: min(frame.width, bounds.width), height: min(frame.height, bounds.height))
        return CGRect(x: min(max(frame.minX, bounds.minX), bounds.maxX - size.width),
                      y: min(max(frame.minY, bounds.minY), bounds.maxY - size.height), width: size.width, height: size.height)
    }
    static func screen(for frame: CGRect, preferredID: String?, screens: [CompanionScreen]) -> CompanionScreen? {
        if let preferredID, let matching = screens.first(where: { $0.id == preferredID }) { return matching }
        return screens.max { area($0.frame.intersection(frame)) < area($1.frame.intersection(frame)) }
    }
    private static func area(_ frame: CGRect) -> CGFloat { frame.isNull ? 0 : frame.width * frame.height }
    static func snap(at point: CGPoint, screen: CGRect) -> CompanionWindowLayout? {
        guard screen.insetBy(dx: -1, dy: -1).contains(point) else { return nil }
        let left = point.x - screen.minX, right = screen.maxX - point.x
        let top = screen.maxY - point.y, bottom = point.y - screen.minY
        if top <= 80 && left <= 80 { return .topLeft }
        if top <= 80 && right <= 80 { return .topRight }
        if bottom <= 80 && left <= 80 { return .bottomLeft }
        if bottom <= 80 && right <= 80 { return .bottomRight }
        if top <= 18 { return .fill }
        if left <= 18 { return .leftHalf }
        if right <= 18 { return .rightHalf }
        return nil
    }
    static func dragRestore(current: CGRect, floating: CGRect, downPoint: CGPoint, cursor: CGPoint, bounds: CGRect) -> CGRect {
        let fraction = min(1, max(0, (downPoint.x - current.minX) / max(1, current.width)))
        let topInset = min(40, max(0, current.maxY - downPoint.y))
        let restored = CGRect(x: cursor.x - floating.width * fraction, y: cursor.y + topInset - floating.height,
                              width: floating.width, height: floating.height)
        return fit(restored, in: bounds)
    }
}

/// Two close-tab clicks must never become a Fill after the first tab disappears.
struct TitlebarDoubleClick {
    private var first: (window: UInt32, point: CGPoint, time: Double, titlebar: Bool)?
    mutating func down(window: UInt32, point: CGPoint, time: Double, count: Int, titlebar: Bool) {
        if count == 1 { first = (window, point, time, titlebar) }
    }
    mutating func shouldFill(window: UInt32, point: CGPoint, time: Double, count: Int, titlebar: Bool, interval: Double) -> Bool {
        guard count == 2 else { return false }
        defer { first = nil }
        guard let first else { return false }
        return first.titlebar && titlebar && first.window == window && time - first.time <= interval &&
            abs(point.x - first.point.x) <= 5 && abs(point.y - first.point.y) <= 5
    }
    mutating func cancel() { first = nil }
}

/// Native toolbars can be nested below AppKit/SwiftUI/Catalyst groups. Inspect
/// the hit's ancestors before rejecting points below the standard title strip.
enum TitlebarHitRegion {
    struct Node { let role: String; let frame: CGRect?; var identifier: String = "" }
    static let controls: Set<String> = [kAXButtonRole, kAXPopUpButtonRole, kAXTextFieldRole, kAXTextAreaRole,
        kAXComboBoxRole, "AXLink", kAXRadioButtonRole, kAXMenuButtonRole, kAXCheckBoxRole, kAXSliderRole,
        kAXDisclosureTriangleRole, kAXIncrementorRole, kAXColorWellRole, kAXMenuItemRole, kAXScrollBarRole,
        kAXSplitterRole, "AXSwitch", "AXTab", "AXTabButton"]
    static func isControl(role: String, identifier: String) -> Bool {
        controls.contains(role) || identifier == "TokenizedSearchBar_TextView" || identifier == "ChatBar_ComposerTextView"
    }
    static func nativeHeight(window: CGRect, closeButton: CGRect?) -> CGFloat {
        guard let closeButton, closeButton.height > 0, closeButton.minY >= window.minY else { return 44 }
        let height = 2 * (closeButton.minY - window.minY) + closeButton.height
        return height >= 20 && height <= 160 ? height : 44
    }
    static func contains(_ point: CGPoint, window: CGRect, path: [Node], nativeHeight: CGFloat = 44) -> Bool {
        guard !path.contains(where: { isControl(role: $0.role, identifier: $0.identifier) }) else { return false }
        var region = CGRect(x: window.minX, y: window.minY, width: window.width, height: min(nativeHeight, window.height))
        for node in path {
            if node.identifier == "WDSNavigationBar", let navbar = node.frame,
               navbar.minY <= window.minY + 32, navbar.intersects(window) {
                // Catalyst's WDS header includes an entire search row in the
                // sidebar; only its first, 56-point caption band is draggable.
                let caption = navbar.intersection(CGRect(x: window.minX, y: window.minY, width: window.width, height: 56))
                if !caption.isNull { region = region.union(caption) }
            } else if node.role == kAXToolbarRole, let toolbar = node.frame,
                toolbar.minY <= region.maxY + 8, toolbar.maxY >= window.minY,
                toolbar.height <= 160, toolbar.intersects(window) { region = region.union(toolbar.intersection(window)) }
        }
        return region.contains(point)
    }
}

/// WindowServer's event target takes precedence over a raw stacking-list hit,
/// whose transparent helper windows may cover an otherwise empty title bar.
enum WindowHitSelection {
    static func select(at point: CGPoint, requested: [String: Any]?, windows: [[String: Any]]) -> [String: Any]? {
        func eligible(_ info: [String: Any]) -> Bool {
            guard info[kCGWindowLayer as String] as? Int == 0,
                  info[kCGWindowIsOnscreen as String] as? Bool == true,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
            return rect.contains(point)
        }
        if let requested, eligible(requested) { return requested }
        return windows.first(where: eligible)
    }
}
