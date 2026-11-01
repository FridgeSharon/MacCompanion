import Cocoa

private final class CompanionPreferencesDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// Extends the existing AppKit preferences rather than introducing a second settings window.
final class CompanionPreferencesViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private var refreshTimer: Timer?
    private let gestureStatus = NSTextField(labelWithString: "")
    private let backendStatus = NSTextField(wrappingLabelWithString: "")
    private let sizingStatus = NSTextField(wrappingLabelWithString: "")
    private var sensitivitySlider: NSSlider?
    private let sensitivityValue = NSTextField(labelWithString: "")
    private let sizingMode = NSPopUpButton()
    private var directionPopups: [NSPopUpButton] = []
    private let stageStatus = NSTextField(labelWithString: "")
    private let thresholdValue = NSTextField(labelWithString: "")
    private let widthValue = NSTextField(labelWithString: "")
    private let table = NSTableView()
    private let removeButton = NSButton()

    private func text(_ value: String, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: NSLocalizedString(value, comment: "Companion settings"))
        field.font = .systemFont(ofSize: secondary ? 11 : 13)
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        return field
    }
    private func heading(_ value: String) -> NSTextField {
        let field = text(value); field.font = .boldSystemFont(ofSize: 13); return field
    }
    private func row(_ views: NSView...) -> NSStackView {
        let stack = NSStackView(views: views); stack.orientation = .horizontal; stack.alignment = .centerY; stack.spacing = 12
        return stack
    }
    private func toggle(_ value: String, state: Bool, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: NSLocalizedString(value, comment: "Companion switch"), target: self, action: action)
        button.state = state ? .on : .off
        return button
    }
    private func separator() -> NSBox { let line = NSBox(); line.boxType = .separator; return line }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 650))
        let config = CompanionSettings.shared.configuration
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSScrollView(); container.hasVerticalScroller = true; container.drawsBackground = false
        container.translatesAutoresizingMaskIntoConstraints = false
        let document = CompanionPreferencesDocumentView(); document.translatesAutoresizingMaskIntoConstraints = false
        container.documentView = document; document.addSubview(stack); view.addSubview(container)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 620), view.heightAnchor.constraint(equalToConstant: 650),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor), container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.topAnchor.constraint(equalTo: view.topAnchor), container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            document.widthAnchor.constraint(equalTo: container.contentView.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: container.contentView.heightAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20)
        ])
        stack.addArrangedSubview(heading("Mouse gestures"))
        stack.addArrangedSubview(toggle("Enable hold-and-move gestures", state: config.gesturesEnabled, action: #selector(gesturesChanged(_:))))
        let button = NSPopUpButton(); button.target = self; button.action = #selector(buttonChanged(_:))
        button.addItems(withTitles: [NSLocalizedString("Rear thumb button (button 4)", comment: ""), NSLocalizedString("Front thumb button (button 5)", comment: "")])
        button.selectItem(at: config.gestureButton == 3 ? 0 : 1)
        button.setAccessibilityLabel(NSLocalizedString("Gesture button", comment: ""))
        stack.addArrangedSubview(row(text("Hold"), button))
        let backend = NSPopUpButton(); backend.target = self; backend.action = #selector(backendChanged(_:))
        backend.addItems(withTitles: [NSLocalizedString("Action gestures", comment: ""), NSLocalizedString("Continuous gestures (experimental)", comment: "")])
        backend.selectItem(at: config.gestureBackend == .continuous ? 1 : 0)
        backend.setAccessibilityLabel(NSLocalizedString("Gesture style", comment: ""))
        stack.addArrangedSubview(row(text("Style"), backend))
        backendStatus.font = .systemFont(ofSize: 11); backendStatus.textColor = .secondaryLabelColor
        stack.addArrangedSubview(backendStatus)
        let sensitivity = NSSlider(value: config.gestureSensitivity, minValue: 0.25, maxValue: 3, target: self, action: #selector(sensitivityChanged(_:)))
        sensitivitySlider = sensitivity
        sensitivity.isEnabled = config.gestureBackend == .continuous
        sensitivity.widthAnchor.constraint(equalToConstant: 180).isActive = true
        sensitivity.setAccessibilityLabel(NSLocalizedString("Continuous gesture sensitivity", comment: ""))
        stack.addArrangedSubview(row(text("Continuous sensitivity"), sensitivity, sensitivityValue))
        let directions = NSStackView(); directions.orientation = .vertical; directions.spacing = 5; directions.alignment = .leading
        for (index, direction) in GestureDirection.allCases.enumerated() {
            let label = text(direction.title); label.widthAnchor.constraint(equalToConstant: 64).isActive = true
            let popup = NSPopUpButton(); popup.tag = index; popup.target = self; popup.action = #selector(actionChanged(_:))
            popup.addItems(withTitles: CompanionAction.allCases.map(\.title))
            popup.selectItem(at: CompanionAction.allCases.firstIndex(of: config.action(for: direction)) ?? 0)
            popup.widthAnchor.constraint(equalToConstant: 220).isActive = true
            popup.setAccessibilityLabel(direction.title + " " + NSLocalizedString("gesture action", comment: ""))
            directionPopups.append(popup)
            directions.addArrangedSubview(row(label, popup))
        }
        stack.addArrangedSubview(directions)
        let threshold = NSSlider(value: config.gestureThreshold, minValue: 10, maxValue: 150, target: self, action: #selector(thresholdChanged(_:)))
        threshold.widthAnchor.constraint(equalToConstant: 180).isActive = true
        threshold.setAccessibilityLabel(NSLocalizedString("Gesture movement threshold", comment: ""))
        stack.addArrangedSubview(row(text("Movement threshold"), threshold, thresholdValue))
        stack.addArrangedSubview(text("A short press keeps the normal click. Continuous gestures follow your movement; reverse to cancel. Other actions trigger once per hold.", secondary: true))
        gestureStatus.font = .systemFont(ofSize: 11); gestureStatus.textColor = .secondaryLabelColor
        stack.addArrangedSubview(gestureStatus)
        let firstLine = separator(); stack.addArrangedSubview(firstLine); firstLine.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.addArrangedSubview(heading("Window sizing"))
        sizingMode.target = self; sizingMode.action = #selector(sizingChanged(_:))
        sizingMode.addItems(withTitles: [NSLocalizedString("Native sizing + gap correction", comment: ""), NSLocalizedString("Direct sizing", comment: "")])
        sizingMode.selectItem(at: config.windowSizingMode == .direct ? 1 : 0)
        sizingMode.setAccessibilityLabel(NSLocalizedString("Window sizing mode", comment: ""))
        stack.addArrangedSubview(row(text("Mode"), sizingMode))
        stack.addArrangedSubview(text("Direct sizing handles title-bar double-clicks and edge drags. It temporarily turns off matching macOS controls and restores them when paused or quit. Option-click on green stays native.", secondary: true))
        sizingStatus.font = .systemFont(ofSize: 11); sizingStatus.textColor = .secondaryLabelColor
        stack.addArrangedSubview(sizingStatus)
        let restore = NSButton(title: NSLocalizedString("Restore macOS Window Controls", comment: ""), target: self, action: #selector(restoreControls))
        stack.addArrangedSubview(restore)
        stack.addArrangedSubview(text("Fill, halves, quarters and Restore are available in the menu bar.", secondary: true))
        stack.addArrangedSubview(heading("Stage Manager space"))
        stack.addArrangedSubview(toggle("Keep space whenever Stage Manager is on", state: config.stageEnabled, action: #selector(stageChanged(_:))))
        let width = NSSlider(value: config.stageWidth, minValue: 40, maxValue: 500, target: self, action: #selector(widthChanged(_:)))
        width.widthAnchor.constraint(equalToConstant: 220).isActive = true
        width.setAccessibilityLabel(NSLocalizedString("Reserved Stage Manager width", comment: ""))
        stack.addArrangedSubview(row(text("Reserved width"), width, widthValue))
        stack.addArrangedSubview(text("Direct layouts calculate the reserved space before sizing. Native layouts are corrected after resizing. Floating windows and full-screen spaces are left alone.", secondary: true))
        stageStatus.font = .systemFont(ofSize: 11); stageStatus.textColor = .secondaryLabelColor
        stack.addArrangedSubview(stageStatus)
        let secondLine = separator(); stack.addArrangedSubview(secondLine); secondLine.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.addArrangedSubview(heading("Pause gestures, middle-click and window adjustments in"))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("application")); column.title = "Application"; column.width = 480
        column.isEditable = false
        table.addTableColumn(column); table.headerView = nil; table.dataSource = self; table.delegate = self; table.rowHeight = 22
        table.setAccessibilityLabel(NSLocalizedString("Excluded applications", comment: ""))
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true; scroll.heightAnchor.constraint(equalToConstant: 72).isActive = true
        let add = NSButton(title: NSLocalizedString("Add app…", comment: ""), target: self, action: #selector(addApp))
        removeButton.title = NSLocalizedString("Remove selected", comment: ""); removeButton.target = self
        removeButton.action = #selector(removeApp); removeButton.bezelStyle = .rounded; removeButton.isEnabled = false
        stack.addArrangedSubview(row(add, removeButton))
        stack.addArrangedSubview(text("Mac Companion · Based on Mos by Caldis · Updates installed manually", secondary: true))
        refreshStatus()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refreshStatus() }
    }
    override func viewDidDisappear() { super.viewDidDisappear(); refreshTimer?.invalidate(); refreshTimer = nil }
    deinit { refreshTimer?.invalidate() }
    private func refreshStatus() {
        gestureStatus.stringValue = CompanionGestureController.shared.lastEventDescription
        sensitivitySlider?.isEnabled = CompanionSettings.shared.configuration.gestureBackend == .continuous
        backendStatus.stringValue = ContinuousGestureEmitter.shared.status
        sizingStatus.stringValue = DirectWindowController.shared.status
        sensitivityValue.stringValue = String(format: "%.2f×", CompanionSettings.shared.configuration.gestureSensitivity)
        stageStatus.stringValue = StageManagerGuardian.shared.status
        thresholdValue.stringValue = String(format: "%.0f pt", CompanionSettings.shared.configuration.gestureThreshold)
        widthValue.stringValue = String(format: "%.0f pt", CompanionSettings.shared.configuration.stageWidth)
    }
    @objc private func backendChanged(_ sender: NSPopUpButton) {
        CompanionSettings.shared.update { $0.selectBackend(sender.indexOfSelectedItem == 1 ? .continuous : .actions) }
        let config = CompanionSettings.shared.configuration
        for (index, popup) in directionPopups.enumerated() {
            popup.selectItem(at: CompanionAction.allCases.firstIndex(of: config.action(for: GestureDirection.allCases[index])) ?? 0)
        }
        refreshStatus()
    }
    @objc private func sensitivityChanged(_ sender: NSSlider) { CompanionSettings.shared.update { $0.gestureSensitivity = sender.doubleValue }; refreshStatus() }
    @objc private func sizingChanged(_ sender: NSPopUpButton) { CompanionSettings.shared.update { $0.windowSizingMode = sender.indexOfSelectedItem == 1 ? .direct : .nativeCorrection }; refreshStatus() }
    @objc private func restoreControls() { DirectWindowController.shared.restoreNativeControls(); sizingMode.selectItem(at: 0); refreshStatus() }
    @objc private func gesturesChanged(_ sender: NSButton) { CompanionSettings.shared.update { $0.gesturesEnabled = sender.state == .on } }
    @objc private func stageChanged(_ sender: NSButton) { CompanionSettings.shared.update { $0.stageEnabled = sender.state == .on } }
    @objc private func buttonChanged(_ sender: NSPopUpButton) { CompanionSettings.shared.update { $0.gestureButton = sender.indexOfSelectedItem + 3 } }
    @objc private func thresholdChanged(_ sender: NSSlider) { CompanionSettings.shared.update { $0.gestureThreshold = sender.doubleValue }; refreshStatus() }
    @objc private func widthChanged(_ sender: NSSlider) { CompanionSettings.shared.update { $0.stageWidth = sender.doubleValue }; refreshStatus() }
    @objc private func actionChanged(_ sender: NSPopUpButton) {
        let direction = GestureDirection.allCases[sender.tag]
        let action = CompanionAction.allCases[sender.indexOfSelectedItem]
        CompanionSettings.shared.update { $0.setAction(action, for: direction) }
    }
    @objc private func addApp() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowedFileTypes = ["app"]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let path = panel.url?.path else { return }
        CompanionSettings.shared.update { $0.excludedPaths.append(path) }; table.reloadData()
        if let index = CompanionSettings.shared.configuration.excludedPaths.firstIndex(of: path) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        updateRemoveState()
    }
    @objc private func removeApp() {
        let index = table.selectedRow
        guard CompanionSettings.shared.configuration.excludedPaths.indices.contains(index) else { return }
        CompanionSettings.shared.update { $0.excludedPaths.remove(at: index) }; table.deselectAll(nil); table.reloadData(); updateRemoveState()
    }
    private func updateRemoveState() { removeButton.isEnabled = CompanionSettings.shared.configuration.excludedPaths.indices.contains(table.selectedRow) }
    func tableViewSelectionDidChange(_ notification: Notification) { updateRemoveState() }
    func numberOfRows(in tableView: NSTableView) -> Int { CompanionSettings.shared.configuration.excludedPaths.count }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let path = CompanionSettings.shared.configuration.excludedPaths[row]
        return FileManager.default.displayName(atPath: path)
    }
}
