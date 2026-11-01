//
//  PreferencesTabViewController.swift
//  Mos
//  偏好设置的 TabViewController 容器
//  Created by Caldis on 2017/1/20.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

/// Each tab presents the same outer size; individual forms keep their natural layout.
/// This prevents AppKit from resizing the window to the selected child's constraints.
private final class PreferencesPaneContainer: NSViewController {
    let content: NSViewController

    init(content: NSViewController) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
        title = content.title
        preferredContentSize = PreferencesTabViewController.contentSize
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: PreferencesTabViewController.contentSize))
        addChild(content)
        let form = content.view
        let naturalSize = form.frame.size
        form.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(form)
        // Legacy forms determine their height through internal constraints. A weak
        // fallback also sizes the newer panes whose content does not pin both edges.
        let height = form.heightAnchor.constraint(equalToConstant: naturalSize.height)
        height.priority = .defaultLow
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: PreferencesTabViewController.contentSize.width),
            root.heightAnchor.constraint(equalToConstant: PreferencesTabViewController.contentSize.height),
            form.widthAnchor.constraint(equalToConstant: naturalSize.width),
            form.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            form.topAnchor.constraint(equalTo: root.topAnchor),
            form.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor),
            height
        ])
        view = root
    }
}

class PreferencesTabViewController: NSTabViewController {
    static let contentSize = NSSize(width: 820, height: 650)

    override func viewDidLoad() {
        super.viewDidLoad()
        let companion = NSTabViewItem(viewController: CompanionPreferencesViewController())
        companion.label = NSLocalizedString("Gestures & Space", comment: "Private utility preferences tab")
        companion.image = NSImage(named: NSImage.actionTemplateName)
        insertTabViewItem(companion, at: min(2, tabViewItems.count))
        let awdl = NSTabViewItem(viewController: AWDLPreferencesViewController())
        awdl.label = NSLocalizedString("AWDL", comment: "AWDL preferences tab")
        awdl.image = NSImage(systemSymbolName: "wifi", accessibilityDescription: nil)
        insertTabViewItem(awdl, at: min(3, tabViewItems.count))
        let trackpad = NSTabViewItem(viewController: TrackpadPreferencesViewController())
        trackpad.label = NSLocalizedString("Middle Click", comment: "Preferences tab")
        trackpad.image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: nil)
        insertTabViewItem(trackpad, at: min(4, tabViewItems.count))
        let about = NSTabViewItem(viewController: CompanionAboutViewController())
        about.label = NSLocalizedString("About", comment: "Preferences tab")
        about.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        addTabViewItem(about)

        let originalItems = tabViewItems
        originalItems.forEach(removeTabViewItem)
        let panes = originalItems.compactMap { item -> NSTabViewItem? in
            guard let controller = item.viewController else { return nil }
            let pane = NSTabViewItem(viewController: PreferencesPaneContainer(content: controller))
            pane.identifier = item.identifier
            pane.label = item.label
            pane.image = item.image
            pane.toolTip = item.toolTip
            return pane
        }
        panes.forEach(addTabViewItem)
        transitionOptions = []
        preferredContentSize = Self.contentSize
        selectedTabViewItemIndex = 2
    }
}
