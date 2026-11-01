//
//  AdaptivePopover.swift
//  Mos
//  Popover tip view that auto-sizes based on content
//  Created by Caldis on 2025/10/03.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class AdaptivePopover: NSViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        updatePreferredContentSize()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updatePreferredContentSize()
    }

    func updatePreferredContentSize() {
        // Called from viewDidLayout: forcing another layout here re-enters AppKit.
        guard let contentView = view.subviews.first else { return }
        var contentSize = contentView.intrinsicContentSize
        if contentSize.width <= 0 || contentSize.height <= 0 {
            contentSize = contentView.fittingSize
        }
        guard contentSize.width.isFinite, contentSize.height.isFinite,
              contentSize.width > 0, contentSize.height > 0 else { return }

        // Add padding (12pt horizontal, 10pt vertical based on constraints)
        let width = contentSize.width + 24
        let height = contentSize.height + 20

        let size = NSSize(width: width, height: height)
        if preferredContentSize != size { preferredContentSize = size }
    }

}
