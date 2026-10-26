// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import AppKit

/// One fixed-size image keeps the native Menu label from expanding its layout.
/// Like BrandWordmark, the gear is a solid recess with light only on inner edges.
enum EngravedSettingsIcon {
    static let image: NSImage = makeImage()

    private static let size = CGSize(width: 25, height: 25)
    private static let bounds = CGRect(origin: .zero, size: size)
    private static let scale: CGFloat = 4

    private static func bitmap() -> CGContext? {
        guard let context = CGContext(
            data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.setShouldAntialias(true)
        return context
    }

    private static func makeImage() -> NSImage {
        let empty = NSImage(size: size)
        empty.isTemplate = false
        guard let symbol = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 20, weight: .bold)),
              let silhouette = bitmap(), let result = bitmap(),
              symbol.size.width > 0, symbol.size.height > 0 else { return empty }

        // Preserve the SF Symbol's filled contour and center opening. The 2.5pt
        // margin leaves room for antialiasing without cropping the outer teeth.
        let fit = min(20 / symbol.size.width, 20 / symbol.size.height)
        let glyphSize = CGSize(width: symbol.size.width * fit, height: symbol.size.height * fit)
        let glyphBounds = CGRect(x: (size.width - glyphSize.width) / 2,
                                 y: (size.height - glyphSize.height) / 2,
                                 width: glyphSize.width, height: glyphSize.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: silhouette, flipped: false)
        symbol.draw(in: glyphBounds, from: .zero, operation: .copy, fraction: 1,
                    respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        guard let mask = silhouette.makeImage() else { return empty }

        func innerEdge(offset: CGSize) -> CGImage? {
            guard let edge = bitmap() else { return nil }
            edge.draw(mask, in: bounds)
            edge.setBlendMode(.destinationOut)
            edge.draw(mask, in: bounds.offsetBy(dx: offset.width, dy: offset.height))
            return edge.makeImage()
        }

        // Core Graphics' y axis points upward: shifting the subtracting mask
        // down/right exposes the upper/left inner wall, never an outer shadow.
        guard let shadow = innerEdge(offset: CGSize(width: 1, height: -1)),
              let rim = innerEdge(offset: CGSize(width: -0.75, height: 0.75)),
              let floor = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [
                    CGColor(red: 0.13, green: 0.11, blue: 0.075, alpha: 1),
                    CGColor(red: 0.34, green: 0.29, blue: 0.19, alpha: 1),
                    CGColor(red: 0.19, green: 0.16, blue: 0.105, alpha: 1)
                ] as CFArray, locations: [0, 0.5, 1]
              ) else { return empty }

        result.saveGState()
        result.clip(to: bounds, mask: mask)
        result.drawLinearGradient(floor,
                                  start: CGPoint(x: glyphBounds.minX, y: glyphBounds.maxY),
                                  end: CGPoint(x: glyphBounds.maxX, y: glyphBounds.minY),
                                  options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        result.restoreGState()

        func shade(_ edge: CGImage, color: CGColor) {
            result.saveGState()
            // Edge difference is already inside the silhouette. Clipping once
            // more prevents any interpolation fringe from coloring the panel.
            result.clip(to: bounds, mask: mask)
            result.clip(to: bounds, mask: edge)
            result.setFillColor(color)
            result.fill(bounds)
            result.restoreGState()
        }
        shade(shadow, color: CGColor(red: 0.025, green: 0.021, blue: 0.015, alpha: 0.88))
        shade(rim, color: CGColor(red: 0.92, green: 0.73, blue: 0.34, alpha: 0.70))

        guard let rendered = result.makeImage() else { return empty }
        let image = NSImage(cgImage: rendered, size: size)
        image.isTemplate = false
        return image
    }
}
