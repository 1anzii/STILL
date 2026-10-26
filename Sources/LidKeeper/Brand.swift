// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import AppKit
import CoreText

enum Brand {
    static let name = "STILL"
    static let fontPostScriptName = "Michroma-Regular"

    // Registration is scoped to this process. Colleagues do not need to install
    // a system font; the unmodified font and its OFL travel with the app.
    @discardableResult
    static func registerBundledFont(in bundle: Bundle = .main) -> Bool {
        guard let url = bundle.url(forResource: "Michroma-Regular", withExtension: "ttf", subdirectory: "Fonts") else {
            NSLog("STILL: bundled brand font is missing")
            return false
        }
        var error: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        let failure = error?.takeRetainedValue()
        let available = NSFont(name: fontPostScriptName, size: 17)?.fontName == fontPostScriptName
        if !registered && !available {
            NSLog("STILL: unable to register brand font: %@", failure.map { CFErrorCopyDescription($0) as String } ?? "unknown error")
        }
        return available
    }
}
