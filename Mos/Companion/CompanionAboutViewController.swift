import Cocoa

final class CompanionAboutViewController: NSViewController {
    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 380))
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        let icon = NSImageView(image: NSImage(named: NSImage.applicationIconName) ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 80).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 80).isActive = true
        stack.addArrangedSubview(icon)
        let title = NSTextField(labelWithString: "Mac Companion"); title.font = .boldSystemFont(ofSize: 19)
        stack.addArrangedSubview(title)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        stack.addArrangedSubview(NSTextField(labelWithString: version))
        let credits = NSTextField(wrappingLabelWithString: NSLocalizedString(
            "Based on Mos by Caldis and contributors. Includes adaptations from Mac Mouse Fix, Rectangle/Spectacle and AWDLControl, and uses LoginServiceKit. Free for noncommercial use under the included licenses.", comment: "About credits"))
        credits.alignment = .center; stack.addArrangedSubview(credits)
        let licenses = NSButton(title: NSLocalizedString("Credits and licenses…", comment: "About button"), target: self, action: #selector(showCredits))
        let quit = NSButton(title: NSLocalizedString("Quit", comment: "Quit app"), target: NSApp, action: #selector(NSApplication.terminate(_:)))
        let actions = NSStackView(views: [licenses, quit]); actions.spacing = 12
        stack.addArrangedSubview(actions)
        root.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor)])
        view = root
    }
    @objc private func showCredits() {
        if let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt") { NSWorkspace.shared.open(url) }
    }
}
