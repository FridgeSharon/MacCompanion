//
//  StatusItemManager.swift
//  Mos
//  管理状态栏图标以及初始化
//  Created by Caldis on 2018/3/7.
//  Copyright © 2018年 Caldis. All rights reserved.
//
import Cocoa

class StatusItemManager: NSMenu, NSMenuDelegate {
    
    // 状态栏引用
    static let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let item = StatusItemManager.statusItem
    
    private static func companionIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let body = NSBezierPath(roundedRect: NSRect(x: 4, y: 1.5, width: 10, height: 15), xRadius: 5, yRadius: 5)
            body.lineWidth = 1.5; body.stroke()
            let wheel = NSBezierPath(); wheel.move(to: NSPoint(x: 9, y: 11)); wheel.line(to: NSPoint(x: 9, y: 14))
            wheel.lineWidth = 1.7; wheel.lineCapStyle = .round; wheel.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
    // 初始化
    override func awakeFromNib() {
        NSLog("Module initialized: StatusItemManager")
        // 设置图标/行为
        item.button?.image = Self.companionIcon()
        item.button?.toolTip = "Mac Companion"
        // 设置事件响应
        item.menu = self
        item.menu?.delegate = self
    }
    
}

/**
 * 菜单响应
 **/
extension StatusItemManager {
    // 打开菜单
    func menuWillOpen(_ menu: NSMenu) {
        onMenuClick()
    }
    @objc func onMenuClick()  {
        if let event = NSApp.currentEvent {
            // 无辅助功能选项显示要求权限菜单
            guard AXIsProcessTrusted() else {
                buildRequireAccessibilityMenu()
                return
            }
            // 当按下 option 键显示特殊菜单
            guard !event.modifierFlags.contains(.option) else {
                buildOptionMenu()
                return
            }
            // 弹出菜单
            buildNormalMenu()
        }
    }
}

/**
 * 菜单构建
 **/
extension StatusItemManager {
    // 无辅助功能访问权限菜单
    @objc func buildRequireAccessibilityMenu() {
        if let menu = item.menu {
            menu.removeAllItems()
            menu.addItem(withTitle: NSLocalizedString("Needs access to Accessibility controls", comment: ""), action: #selector(accessibilityRequire), keyEquivalent: "").target = self
            addAWDLMenu(to: menu)
            addWindowMenu(to: menu)
            // Quit
            Utils.addMenuItemWithSeparator(to: menu, title: NSLocalizedString("Quit", comment: ""), icon: #imageLiteral(resourceName: "SF.escape"), action: #selector(quitClick))
        }
    }
    @objc func accessibilityRequire() {
        Utils.requireAccessibilityPermissions()
    }
    // 按下 Option 按钮的菜单
    @objc func buildOptionMenu() { buildNormalMenu() }
    // 常规菜单
    @objc func buildNormalMenu() {
        if let menu = item.menu {
            // Reset
            menu.removeAllItems()
            // Preferences
            Utils.addMenuItem(to: menu, title: NSLocalizedString("Preferences", comment: ""), icon: #imageLiteral(resourceName: "SF.gauge"), action: #selector(preferencesClick))
            addAWDLMenu(to: menu)
            addWindowMenu(to: menu)
            // Quit
            Utils.addMenuItemWithSeparator(to: menu, title: NSLocalizedString("Quit", comment: ""), icon: #imageLiteral(resourceName: "SF.escape"), action: #selector(quitClick))
        }
    }
    private func addWindowMenu(to menu: NSMenu) {
        let parent = NSMenuItem(title: NSLocalizedString("Window layouts", comment: ""), action: nil, keyEquivalent: "")
        let submenu = NSMenu(); submenu.autoenablesItems = false
        for (index, layout) in CompanionWindowLayout.allCases.enumerated() {
            let item = NSMenuItem(title: layout.title, action: #selector(windowLayoutClick(_:)), keyEquivalent: "")
            item.target = self; item.tag = index
            item.isEnabled = CompanionSettings.shared.configuration.windowSizingMode == .direct
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let restore = NSMenuItem(title: NSLocalizedString("Restore macOS Window Controls", comment: ""), action: #selector(restoreWindowControls), keyEquivalent: "")
        restore.target = self; submenu.addItem(restore)
        parent.submenu = submenu; menu.addItem(parent)
    }
    @objc private func windowLayoutClick(_ item: NSMenuItem) { DirectWindowController.shared.perform(CompanionWindowLayout.allCases[item.tag]) }
    @objc private func restoreWindowControls() { DirectWindowController.shared.restoreNativeControls() }
    private func addAWDLMenu(to menu: NSMenu) {
        let controller = AWDLController.shared
        let parent = NSMenuItem(title: NSLocalizedString("AWDL", comment: ""), action: nil, keyEquivalent: "")
        let submenu = NSMenu(); submenu.autoenablesItems = false
        let status = NSMenuItem(title: controller.status, action: nil, keyEquivalent: ""); status.isEnabled = false
        submenu.addItem(status); submenu.addItem(.separator())
        for mode in AWDLMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(awdlModeChanged(_:)), keyEquivalent: "")
            item.target = self; item.tag = mode.rawValue
            item.state = controller.mode == mode && controller.enabled ? .on : .off
            item.isEnabled = controller.enabled
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let settings = NSMenuItem(title: NSLocalizedString("AWDL Settings…", comment: ""), action: #selector(awdlSettingsClick), keyEquivalent: "")
        settings.target = self; submenu.addItem(settings)
        parent.submenu = submenu; menu.addItem(parent)
    }
    @objc private func awdlSettingsClick() {
        let manager = WindowManager.shared
        manager.showWindow(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController)
        if let tabs = manager.refs[WINDOW_IDENTIFIER.preferencesWindowController]?.contentViewController as? PreferencesTabViewController,
           let index = tabs.tabViewItems.firstIndex(where: { $0.viewController is AWDLPreferencesViewController }) {
            tabs.selectedTabViewItemIndex = index
        }
    }
    @objc private func awdlModeChanged(_ item: NSMenuItem) {
        if let mode = AWDLMode(rawValue: item.tag) { AWDLController.shared.setMode(mode) }
    }



    @objc func preferencesClick() {
        WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController)
    }
    @objc func quitClick() {
        NSApplication.shared.terminate(self)
    }
}

/**
 * 图标显示
 **/
extension StatusItemManager {
    // 显示状态栏图标
    class func showStatusItem() {
        if #available(OSX 10.12, *) {
            self.statusItem.isVisible = true
        } else {
            self.statusItem.length = NSStatusItem.variableLength
        }
    }
    // 隐藏状态栏图标
    class func hideStatusItem() {
        if #available(OSX 10.12, *) {
            self.statusItem.isVisible = false
        } else {
            self.statusItem.length = 0.0
        }
    }
}
