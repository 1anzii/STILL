// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import SwiftUI
import CoreText

/// Michroma has one weight. Fill and widen its actual outlines, then shade
/// clipped inner walls so the heavier letters read as recesses in the metal.
struct BrandWordmark: View {
    enum Finish {
        case darkMetal
        case brass
    }

    var size: CGFloat
    var tracking: CGFloat
    var finish: Finish = .darkMetal

    private var floorColors: [Color] {
        switch finish {
        case .darkMetal:
            return [
                Color(red: 0.13, green: 0.11, blue: 0.075),
                Color(red: 0.34, green: 0.29, blue: 0.19),
                Color(red: 0.19, green: 0.16, blue: 0.105)
            ]
        case .brass:
            // A brighter brass floor stays legible against the help panel's
            // dark metal; the same dark inner wall still defines its recess.
            return [
                Color(red: 0.55, green: 0.36, blue: 0.105),
                Color(red: 0.92, green: 0.70, blue: 0.27),
                Color(red: 0.65, green: 0.45, blue: 0.16)
            ]
        }
    }

    private var rimColor: Color {
        switch finish {
        case .darkMetal: return Color(red: 0.92, green: 0.73, blue: 0.34)
        case .brass: return Color(red: 0.98, green: 0.82, blue: 0.42)
        }
    }

    private final class Artwork: NSObject {
        let path: Path
        let size: CGSize
        let strokeWidth: CGFloat
        init(path: Path, size: CGSize, strokeWidth: CGFloat) {
            self.path = path
            self.size = size
            self.strokeWidth = strokeWidth
        }
    }
    private static let cache: NSCache<NSString, Artwork> = {
        let cache = NSCache<NSString, Artwork>()
        cache.countLimit = 24
        return cache
    }()

    private var artwork: Artwork {
        let key = "\(size)/\(tracking)" as NSString
        if let cached = Self.cache.object(forKey: key) { return cached }
        let font = CTFontCreateWithName(Brand.fontPostScriptName as CFString, size, nil)
        let text = NSAttributedString(string: Brand.name, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            .kern: tracking
        ])
        let line = CTLineCreateWithAttributedString(text)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        // A centered 0.11 em stroke expands each contour by 0.055 em.
        // Rounded joins preserve Michroma's open S rather than adding miter
        // spikes, and the filled core prevents a hollow-outline appearance.
        let strokeWidth = size * 0.11
        let inset = ceil(strokeWidth / 2 + max(0.75, size * 0.04))
        let outline = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            for index in 0..<count {
                guard let glyph = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
                let transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                                  tx: positions[index].x + inset, ty: ascent - positions[index].y + inset)
                outline.addPath(glyph, transform: transform)
            }
        }
        let result = Artwork(path: Path(outline),
                             size: CGSize(width: width + inset * 2, height: ceil(ascent + descent) + inset * 2),
                             strokeWidth: strokeWidth)
        Self.cache.setObject(result, forKey: key)
        return result
    }

    /// Opaque union of the glyph fill and its thickening stroke. Keeping these
    /// as composited alpha avoids changing winding rules in the font's paths.
    private func silhouette(_ drawing: Artwork) -> some View {
        ZStack(alignment: .topLeading) {
            drawing.path.fill(Color.white)
            drawing.path.stroke(Color.white,
                                style: StrokeStyle(lineWidth: drawing.strokeWidth,
                                                   lineCap: .round, lineJoin: .round))
        }
        .frame(width: drawing.size.width, height: drawing.size.height, alignment: .topLeading)
        .compositingGroup()
    }

    /// Difference of two silhouettes, not an exterior shadow. In downward-
    /// positive view coordinates, a positive offset exposes the top/left inner
    /// wall; a negative offset exposes the lower/right inner rim.
    private func innerEdge(_ drawing: Artwork, offset: CGFloat) -> some View {
        silhouette(drawing)
            .overlay {
                silhouette(drawing)
                    .offset(x: offset, y: offset)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
    }

    var body: some View {
        let drawing = artwork
        let wallDepth = max(0.70, size * 0.055)
        let rimWidth = max(0.45, size * 0.04)
        let edgeSoftness = max(0.12, size * 0.007)
        ZStack {
            // A solid metal floor remains visible between the inner walls.
            LinearGradient(colors: floorColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .mask { silhouette(drawing) }

            Color(red: 0.025, green: 0.021, blue: 0.015).opacity(0.88)
                .mask { innerEdge(drawing, offset: wallDepth).blur(radius: edgeSoftness) }

            // Warm reflected light catches only the lower/right inner edge.
            // No white halo or exterior drop shadow suggests raised lettering.
            rimColor.opacity(0.70)
                .mask { innerEdge(drawing, offset: -rimWidth).blur(radius: edgeSoftness) }
        }
        .frame(width: drawing.size.width, height: drawing.size.height)
        .mask { silhouette(drawing) }
        .compositingGroup()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Brand.name)
        .accessibilityAddTraits(.isStaticText)
    }
}
