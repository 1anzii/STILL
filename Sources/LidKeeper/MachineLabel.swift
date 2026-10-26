// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import SwiftUI
import CoreText

/// Solid silkscreen lettering. Michroma has one weight, so a small contour
/// expansion provides two legible weights without changing the bundled font.
struct MachineLabel: View {
    let text: String
    var size: CGFloat = 9
    var tracking: CGFloat = 0.4
    var emphasized = false

    private final class Artwork: NSObject {
        let path: Path
        let size: CGSize
        init(path: Path, size: CGSize) { self.path = path; self.size = size }
    }
    private static let cache: NSCache<NSString, Artwork> = {
        let cache = NSCache<NSString, Artwork>()
        cache.countLimit = 32
        return cache
    }()

    private var artwork: Artwork {
        let key = "\(text)/\(size)/\(tracking)" as NSString
        if let cached = Self.cache.object(forKey: key) { return cached }
        let font = CTFontCreateWithName(Brand.fontPostScriptName as CFString, size, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font, .kern: tracking
        ]))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        // Fixed padding for the heaviest stroke keeps the label in place when
        // selection changes and leaves room for antialiasing at small sizes.
        let inset = ceil(size * 0.065 / 2 + 0.5)
        let outline = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            for index in 0..<count {
                guard let glyph = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
                outline.addPath(glyph, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                    tx: positions[index].x + inset, ty: ascent - positions[index].y + inset))
            }
        }
        let result = Artwork(path: Path(outline), size: CGSize(width: ceil(width) + inset * 2,
                                                              height: ceil(ascent + descent) + inset * 2))
        Self.cache.setObject(result, forKey: key)
        return result
    }

    var body: some View {
        let drawing = artwork
        ZStack(alignment: .topLeading) {
            drawing.path.fill()
            drawing.path.stroke(style: StrokeStyle(lineWidth: size * (emphasized ? 0.065 : 0.035),
                                                    lineCap: .round, lineJoin: .round))
        }
        .frame(width: drawing.size.width, height: drawing.size.height)
        .compositingGroup()
        .accessibilityHidden(true)
    }
}
