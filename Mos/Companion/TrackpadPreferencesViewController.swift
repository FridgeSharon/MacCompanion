import Cocoa

final class TrackpadPreferencesViewController: NSViewController {
    private let enabled = NSButton(checkboxWithTitle: NSLocalizedString("Enable trackpad middle-click", comment: "Trackpad setting"), target: nil, action: nil)
    private let tap = NSButton(checkboxWithTitle: NSLocalizedString("Three-finger tap", comment: "Trackpad setting"), target: nil, action: nil)
    private let click = NSButton(checkboxWithTitle: NSLocalizedString("Three-finger physical click", comment: "Trackpad setting"), target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
    private var observer: NSObjectProtocol?

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 380))
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        let heading = NSTextField(labelWithString: NSLocalizedString("Trackpad middle-click", comment: "Trackpad heading"))
        heading.font = .boldSystemFont(ofSize: 13); stack.addArrangedSubview(heading)
        for button in [enabled, tap, click] {
            button.target = self; button.action = #selector(changed(_:)); stack.addArrangedSubview(button)
        }
        status.setAccessibilityLabel(NSLocalizedString("Trackpad middle-click status", comment: "Trackpad status"))
        stack.addArrangedSubview(status)
        let help = NSTextField(wrappingLabelWithString: NSLocalizedString(
            "Tap opens a middle click. Physical click holds the middle button until release and supports dragging. Existing mouse buttons keep their normal behavior.", comment: "Trackpad help"))
        help.textColor = .secondaryLabelColor; stack.addArrangedSubview(help)
        let settings = NSButton(title: NSLocalizedString("Trackpad settings…", comment: "Trackpad settings link"), target: self, action: #selector(openSettings))
        stack.addArrangedSubview(settings)
        let compatibility = NSTextField(wrappingLabelWithString: NSLocalizedString(
            "Experimental: uses macOS touch interfaces. Native three-finger Look Up or three-finger drag can conflict; these system settings are never changed automatically.", comment: "Trackpad compatibility"))
        compatibility.textColor = .secondaryLabelColor; compatibility.font = .systemFont(ofSize: 11)
        stack.addArrangedSubview(compatibility)
        root.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20)])
        view = root
        observer = NotificationCenter.default.addObserver(forName: TrackpadMiddleController.changed, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        refresh()
    }
    override func viewWillAppear() { super.viewWillAppear(); refresh() }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    private func refresh() {
        let controller = TrackpadMiddleController.shared
        enabled.state = controller.enabled ? .on : .off
        tap.state = controller.tapEnabled ? .on : .off; tap.isEnabled = controller.enabled
        click.state = controller.clickEnabled ? .on : .off; click.isEnabled = controller.enabled
        status.stringValue = controller.status
    }
    @objc private func changed(_ sender: NSButton) {
        let controller = TrackpadMiddleController.shared
        if sender === enabled { controller.configure(enabled: sender.state == .on) }
        else if sender === tap { controller.configure(tap: sender.state == .on) }
        else { controller.configure(click: sender.state == .on) }
        refresh()
    }
    @objc private func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.trackpad")!)
    }
}
