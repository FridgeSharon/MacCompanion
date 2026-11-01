//
//  UpdateManager.swift
//  Mos
//  Updates management via Sparkle
//

import Cocoa

final class UpdateManager: NSObject {

    static let shared = UpdateManager()

    private override init() {
        super.init()
        NSLog("Module initialized: UpdateManager")
    }
}

extension UpdateManager {

    func scheduleCheckOnAppStartIfNeeded() {
        // Private builds are updated manually. Never initialize the upstream updater.
    }

    func checkForUpdates() {
    }

    func checkForUpdatesInBackground() {
    }
}
