import Cocoa

private final class AWDLPreferencesDocumentView: NSView { override var isFlipped: Bool { true } }

final class AWDLPreferencesViewController: NSViewController {
    private let enabled = NSButton()
    private let mode = NSPopUpButton()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let approval = NSButton()
    private let remove = NSButton()
    private var observer: NSObjectProtocol?
    private func label(_ string: String, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: NSLocalizedString(string, comment: "AWDL preferences"))
        field.font = .systemFont(ofSize: secondary ? 11 : 13)
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        return field
    }
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 460))
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSScrollView(); container.hasVerticalScroller = true; container.drawsBackground = false
        container.translatesAutoresizingMaskIntoConstraints = false
        let document = AWDLPreferencesDocumentView(); document.translatesAutoresizingMaskIntoConstraints = false
        container.documentView = document; document.addSubview(stack); view.addSubview(container)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 620), view.heightAnchor.constraint(equalToConstant: 460),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor), container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.topAnchor.constraint(equalTo: view.topAnchor), container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            document.widthAnchor.constraint(equalTo: container.contentView.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: container.contentView.heightAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24)
        ])
        let heading = label("AWDL control"); heading.font = .boldSystemFont(ofSize: 13); stack.addArrangedSubview(heading)
        stack.addArrangedSubview(label("Reduce Wi-Fi interference during games by controlling Apple Wireless Direct Link."))
        enabled.setButtonType(.switch); enabled.title = NSLocalizedString("Enable AWDL control", comment: "")
        enabled.target = self; enabled.action = #selector(enabledChanged); stack.addArrangedSubview(enabled)
        mode.addItems(withTitles: AWDLMode.allCases.map(\.title)); mode.target = self; mode.action = #selector(modeChanged)
        mode.setAccessibilityLabel(NSLocalizedString("AWDL mode", comment: ""))
        let row = NSStackView(views: [label("Mode"), mode]); row.spacing = 12; stack.addArrangedSubview(row)
        stack.addArrangedSubview(label("Automatic mode disables AWDL only while the foreground app is a game and the connection uses Wi-Fi. Leaving the game restores AWDL.", secondary: true))
        status.font = .systemFont(ofSize: 13); status.setAccessibilityLabel(NSLocalizedString("AWDL status", comment: "")); stack.addArrangedSubview(status)
        stack.addArrangedSubview(label("AirDrop and Continuity are unavailable while AWDL is off. Quitting Mac Companion restores AWDL.", secondary: true))
        approval.title = NSLocalizedString("Open Login Items & Extensions…", comment: ""); approval.bezelStyle = .rounded
        approval.target = self; approval.action = #selector(openApproval)
        remove.title = NSLocalizedString("Remove helper", comment: ""); remove.bezelStyle = .rounded
        remove.target = self; remove.action = #selector(removeHelper)
        let buttons = NSStackView(views: [approval, remove]); buttons.spacing = 12; stack.addArrangedSubview(buttons)
        stack.addArrangedSubview(label("Includes AWDLControl functionality by James Howard (MIT license). The bundled helper runs with administrator privileges and controls only AWDL.", secondary: true))
        for field in stack.arrangedSubviews.compactMap({ $0 as? NSTextField }) {
            field.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        observer = NotificationCenter.default.addObserver(forName: AWDLController.changed, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        refresh()
    }
    override func viewWillAppear() { super.viewWillAppear(); refresh() }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    private func refresh() {
        let controller = AWDLController.shared
        enabled.state = controller.enabled ? .on : .off
        mode.selectItem(at: controller.mode.rawValue)
        // Mode can be chosen before installation; it takes effect after approval.
        status.stringValue = controller.status
        remove.isEnabled = controller.helperStatus != .notRegistered && controller.helperStatus != .notFound
    }
    @objc private func enabledChanged() { AWDLController.shared.setEnabled(enabled.state == .on); refresh() }
    @objc private func modeChanged() { AWDLController.shared.setMode(AWDLMode(rawValue: mode.indexOfSelectedItem) ?? .game); refresh() }
    @objc private func openApproval() { AWDLController.shared.openApproval() }
    @objc private func removeHelper() { AWDLController.shared.removeHelper(); refresh() }
}
