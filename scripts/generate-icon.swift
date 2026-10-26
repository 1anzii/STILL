// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import AppKit
import CoreText

// Original, resolution-independent artwork; the wordmark uses the unmodified
// OFL-licensed Michroma font bundled in Resources/Fonts.
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func rounded(_ rect: NSRect, _ radius: CGFloat, _ fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func shaded(_ rect: NSRect, _ radius: CGFloat, _ colors: [UInt32], angle: CGFloat = 90) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGradient(colors: colors.map { color($0) })!.draw(in: path, angle: angle)
}

func outline(_ rect: NSRect, _ radius: CGFloat, _ ink: NSColor, width: CGFloat = 2) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    ink.setStroke()
    path.lineWidth = width
    path.stroke()
}

func grain(in rect: NSRect, clip: NSBezierPath, count: Int, seed: UInt64,
           dark: NSColor, light: NSColor, maxDiameter: CGFloat) {
    // A fixed seed gives the molded shell the same fine, random surface
    // at every scale; no tiled stripes or photographic assets are involved.
    var state = seed
    func random() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(state >> 11) / CGFloat(UInt64.max >> 11)
    }
    let darkDots = NSBezierPath()
    let lightDots = NSBezierPath()
    for index in 0..<count {
        let x = rect.minX + random() * rect.width
        let y = rect.minY + random() * rect.height
        let size = 0.45 + random() * maxDiameter
        let dot = NSRect(x: x, y: y, width: size, height: size)
        if index % 2 == 0 { darkDots.appendOval(in: dot) }
        else { lightDots.appendOval(in: dot) }
    }
    NSGraphicsContext.saveGraphicsState()
    clip.addClip()
    dark.setFill()
    darkDots.fill()
    light.setFill()
    lightDots.fill()
    NSGraphicsContext.restoreGraphicsState()
}

func rubberDial() {
    let center = NSPoint(x: 512, y: 466)
    let radius: CGFloat = 218
    // Six marks correspond to the six real timer positions.
    for index in 0...5 {
        let theta = (225 - CGFloat(index) * 54) * .pi / 180
        let mark = NSBezierPath()
        mark.move(to: NSPoint(x: center.x + cos(theta) * 252, y: center.y + sin(theta) * 252))
        let outer: CGFloat = 269
        mark.line(to: NSPoint(x: center.x + cos(theta) * outer, y: center.y + sin(theta) * outer))
        mark.lineWidth = 5
        mark.lineCapStyle = .round
        color(0x433A27, 0.86).setStroke()
        mark.stroke()
    }

    // The molded sidewall extends just below the top face, giving real travel
    // without a chrome ring or an oversized blurred shadow.
    let side = NSRect(x: center.x - radius, y: center.y - radius,
                      width: radius * 2, height: radius * 2)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x57410E, 0.36)
    shadow.shadowBlurRadius = 12
    shadow.shadowOffset = NSSize(width: 5, height: -9)
    shadow.set()
    rounded(side.offsetBy(dx: 0, dy: -2), radius, color(0x1B1D1F))
    NSGraphicsContext.restoreGraphicsState()
    shaded(side, radius, [0x181A1C, 0x343638], angle: 125)
    outline(side, radius, color(0x151718, 0.9), width: 2)

    // Fine rubber grip ribs stay on the sidewall and do not become a gear icon.
    for index in 0..<72 {
        let theta = CGFloat(index) * 5 * .pi / 180
        let rib = NSBezierPath()
        rib.move(to: NSPoint(x: center.x + cos(theta) * 204, y: center.y + sin(theta) * 204))
        rib.line(to: NSPoint(x: center.x + cos(theta) * 216, y: center.y + sin(theta) * 216))
        rib.lineWidth = 2.6
        rib.lineCapStyle = .round
        color(index % 2 == 0 ? 0x090B0C : 0x626361, index % 2 == 0 ? 0.5 : 0.28).setStroke()
        rib.stroke()
    }

    let faceCenter = NSPoint(x: center.x, y: center.y + 17)
    let face = NSRect(x: faceCenter.x - 199, y: faceCenter.y - 199, width: 398, height: 398)
    shaded(face, 199, [0x282A2C, 0x3A3C3D], angle: 125)
    outline(face.insetBy(dx: 1, dy: 1), 198, color(0x121416, 0.28), width: 1.5)
    grain(in: face, clip: NSBezierPath(ovalIn: face), count: 14500, seed: 0x311D1A1,
          dark: color(0x111315, 0.15), light: color(0xB6B6AE, 0.06), maxDiameter: 1.15)

    // A short molded grip rises from the dial face. Its left/top plane receives
    // the same light as the shell; the narrow right/bottom contact shadow gives
    // it usable depth without a bright decorative ring.
    NSGraphicsContext.saveGraphicsState()
    let gripShadow = NSShadow()
    gripShadow.shadowColor = color(0x0B0D0F, 0.5)
    gripShadow.shadowBlurRadius = 5
    gripShadow.shadowOffset = NSSize(width: 5, height: -5)
    gripShadow.set()
    rounded(NSRect(x: 477, y: 407, width: 72, height: 153), 18, color(0x1E2122))
    NSGraphicsContext.restoreGraphicsState()
    shaded(NSRect(x: 477, y: 407, width: 72, height: 153), 18, [0x242728, 0x3E4141], angle: 125)
    shaded(NSRect(x: 477, y: 418, width: 63, height: 142), 15, [0x343738, 0x505251], angle: 125)
    let gripFace = NSRect(x: 477, y: 418, width: 63, height: 142)
    grain(in: gripFace, clip: NSBezierPath(roundedRect: gripFace, xRadius: 15, yRadius: 15),
          count: 850, seed: 0x611F, dark: color(0x141719, 0.12),
          light: color(0x999D96, 0.05), maxDiameter: 0.9)
    rounded(NSRect(x: 482, y: 438, width: 2, height: 104), 1, color(0x868781, 0.16))

    // Point exactly toward the third of the six printed detents.
    let theta = CGFloat(117) * .pi / 180
    let target = NSPoint(x: center.x + cos(theta) * 260, y: center.y + sin(theta) * 260)
    let dx = target.x - faceCenter.x
    let dy = target.y - faceCenter.y
    let length = hypot(dx, dy)
    let pointer = NSBezierPath()
    pointer.move(to: NSPoint(x: faceCenter.x + dx / length * 126,
                            y: faceCenter.y + dy / length * 126))
    pointer.line(to: NSPoint(x: faceCenter.x + dx / length * 173,
                            y: faceCenter.y + dy / length * 173))
    pointer.lineWidth = 12
    pointer.lineCapStyle = .round
    color(0xF4F2E9).setStroke()
    pointer.stroke()
}

func twoPositionLever() {
    // A two-stop slider in a shallow molded recess, with one small graspable tab.
    let track = NSRect(x: 414, y: 145, width: 196, height: 66)
    rounded(track.offsetBy(dx: 0, dy: -2), 33, color(0xFFDA65, 0.35))
    shaded(track, 33, [0xD7A421, 0xAC7D16], angle: 125)
    shaded(NSRect(x: 423, y: 155, width: 178, height: 46), 23,
           [0xC9961C, 0xB98719], angle: 125)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x5F4813, 0.37)
    shadow.shadowBlurRadius = 5
    shadow.shadowOffset = NSSize(width: 3, height: -4)
    shadow.set()
    rounded(NSRect(x: 524, y: 155, width: 73, height: 52), 13, color(0x202324))
    NSGraphicsContext.restoreGraphicsState()
    shaded(NSRect(x: 524, y: 155, width: 73, height: 52), 13, [0x202324, 0x373A3B], angle: 125)
    shaded(NSRect(x: 524, y: 164, width: 67, height: 43), 11, [0x303435, 0x4B4E4D], angle: 125)
    rounded(NSRect(x: 544, y: 183, width: 26, height: 4), 2, color(0xDCDDD3))
}

func runningLED(isOn: Bool) {
    // A tiny seated glass lens beside the switch. Its dark olive off palette
    // matches the real device indicator; the static App icon shows it lit.
    let socket = NSRect(x: 662, y: 152, width: 52, height: 52)
    NSGraphicsContext.saveGraphicsState()
    let contactShadow = NSShadow()
    contactShadow.shadowColor = color(0x594817, 0.3)
    contactShadow.shadowBlurRadius = 3
    contactShadow.shadowOffset = NSSize(width: 1.5, height: -2)
    contactShadow.set()
    rounded(socket, 26, color(0x695C25))
    NSGraphicsContext.restoreGraphicsState()
    shaded(socket, 26, [0x564A20, 0xB99B35], angle: 125)
    let lens = socket.insetBy(dx: 5, dy: 5)
    shaded(lens, 21,
           isOn ? [0x174C25, 0x459B4A, 0x86BF65] : [0x34391D, 0x4C5429, 0x6D7541],
           angle: 125)
    outline(lens, 21, color(0x25361D, 0.65), width: 1.5)
    // A modest upper-left reflection gives glass depth without a neon halo.
    color(isOn ? 0xE9F3CE : 0xB7BD91, isOn ? 0.62 : 0.22).setFill()
    NSBezierPath(ovalIn: NSRect(x: 674, y: 186, width: 13, height: 6)).fill()
}

struct EngravedWordmark {
    let bounds: CGRect
    let mask: CGImage
    let innerShadow: CGImage
    let innerRim: CGImage

    init(font: NSFont) {
        let ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        let outline = CGMutablePath()
        let strokeWidth = font.pointSize * 0.11
        let scale: CGFloat = 4
        let wordmark = NSAttributedString(string: "STILL", attributes: [.font: font, .kern: 3.2])
        let line = CTLineCreateWithAttributedString(wordmark)
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            for index in 0..<count {
                guard let glyph = CTFontCreatePathForGlyph(ctFont, glyphs[index], nil) else { continue }
                outline.addPath(glyph, transform: CGAffineTransform(translationX: positions[index].x,
                                                                   y: positions[index].y))
            }
        }
        let rawBounds = outline.boundingBoxOfPath.insetBy(dx: -strokeWidth, dy: -strokeWidth)
        let local = CGRect(origin: .zero, size: rawBounds.size)
        let pixelsWide = Int(ceil(rawBounds.width * scale))
        let pixelsHigh = Int(ceil(rawBounds.height * scale))
        func bitmapContext() -> CGContext {
            guard let result = CGContext(data: nil, width: pixelsWide, height: pixelsHigh,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                fatalError("Cannot create engraved wordmark mask")
            }
            result.scaleBy(x: CGFloat(pixelsWide) / local.width,
                           y: CGFloat(pixelsHigh) / local.height)
            return result
        }
        let glyphContext = bitmapContext()
        glyphContext.translateBy(x: -rawBounds.minX, y: -rawBounds.minY)
        glyphContext.setFillColor(NSColor.white.cgColor)
        glyphContext.setStrokeColor(NSColor.white.cgColor)
        glyphContext.setLineWidth(strokeWidth)
        glyphContext.setLineJoin(.round)
        glyphContext.addPath(outline)
        glyphContext.drawPath(using: .fillStroke)
        guard let glyphMask = glyphContext.makeImage() else { fatalError("Cannot finish wordmark mask") }
        func edgeMask(offset: CGSize) -> CGImage {
            let edge = bitmapContext()
            edge.draw(glyphMask, in: local)
            edge.setBlendMode(.destinationOut)
            edge.draw(glyphMask, in: local.offsetBy(dx: offset.width, dy: offset.height))
            guard let result = edge.makeImage() else { fatalError("Cannot finish engraving edge mask") }
            return result
        }
        bounds = CGRect(x: 512 - local.width / 2, y: 841 - local.height / 2,
                        width: local.width, height: local.height)
        mask = glyphMask
        let depth = max(0.70, font.pointSize * 0.055)
        innerShadow = edgeMask(offset: CGSize(width: depth, height: -depth))
        let rim = max(0.45, font.pointSize * 0.04)
        innerRim = edgeMask(offset: CGSize(width: -rim, height: rim))
    }
}

func drawWordmark(_ artwork: EngravedWordmark) {
    // A visibly heavier original Michroma outline with a recessed dark brass
    // floor. Only inner edges catch light: no outer glow or raised-letter drop.
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    let floor = NSGradient(colors: [color(0x211C13), color(0x574A30), color(0x30291B)])!
    context.saveGState()
    context.clip(to: artwork.bounds, mask: artwork.mask)
    floor.draw(in: artwork.bounds, angle: -45)
    context.restoreGState()
    context.saveGState()
    context.clip(to: artwork.bounds, mask: artwork.innerShadow)
    context.setFillColor(color(0x060504, 0.88).cgColor)
    context.fill(artwork.bounds)
    context.restoreGState()
    context.saveGState()
    context.clip(to: artwork.bounds, mask: artwork.innerRim)
    context.setFillColor(color(0xEBBA57, 0.70).cgColor)
    context.fill(artwork.bounds)
    context.restoreGState()
}


func drawArtwork(wordmark: EngravedWordmark, texture: NSImage) {
    // A palm-sized coated timer with one dial, a two-position lever and an LED.
    let shell = NSRect(x: 58, y: 50, width: 908, height: 922)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x67500F, 0.21)
    shadow.shadowBlurRadius = 12
    shadow.shadowOffset = NSSize(width: 4, height: -6)
    shadow.set()
    rounded(shell, 184, color(0xAF8013))
    NSGraphicsContext.restoreGraphicsState()
    shaded(shell, 184, [0xB88A18, 0xDFAC22, 0xEBC037], angle: 125)

    // A small sidewall supplies depth; the front has no ornamental border.
    let front = NSRect(x: 67, y: 72, width: 890, height: 890)
    shaded(front, 176, [0xE8B51B, 0xF2C437], angle: 125)
    outline(front, 176, color(0xBC901C, 0.26), width: 1)
    let frontClip = NSBezierPath(roundedRect: front, xRadius: 176, yRadius: 176)
    // The same worn yellow coating is shared with the UI. Blend it into the
    // existing shell light instead of adding isolated artificial scratch lines.
    NSGraphicsContext.saveGraphicsState()
    frontClip.addClip()
    texture.draw(in: front, from: .zero, operation: .sourceOver, fraction: 0.60)
    NSGraphicsContext.restoreGraphicsState()

    drawWordmark(wordmark)
    rubberDial()
    twoPositionLever()
    runningLED(isOn: true)
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources"
let fm = FileManager.default
let resources = URL(fileURLWithPath: output, isDirectory: true)
let fontURL = resources.appendingPathComponent("Fonts/Michroma-Regular.ttf")
var fontRegistrationError: Unmanaged<CFError>?
guard CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &fontRegistrationError) else {
    let reason = fontRegistrationError?.takeRetainedValue().localizedDescription ?? "Unknown font error"
    fatalError("Cannot register bundled Michroma font: \(reason)")
}
guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor],
      let descriptor = descriptors.first else { fatalError("Cannot read bundled Michroma font") }
let postScriptName = CTFontCopyPostScriptName(CTFontCreateWithFontDescriptor(descriptor, 92, nil)) as String
guard let wordmarkFont = NSFont(name: postScriptName, size: 92) else {
    fatalError("Bundled font is unavailable: \(postScriptName)")
}
let wordmarkArtwork = EngravedWordmark(font: wordmarkFont)
let textureURL = resources.appendingPathComponent("Textures/WornYellowMetal-v1.png")
guard let metalTexture = NSImage(contentsOf: textureURL) else {
    fatalError("Cannot read shared worn yellow metal texture: \(textureURL.path)")
}
let iconset = resources.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ pixels: Int, to url: URL) throws {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot create icon bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let scale = NSAffineTransform()
    scale.scale(by: CGFloat(pixels) / 1024)
    scale.concat()
    drawArtwork(wordmark: wordmarkArtwork, texture: metalTexture)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

for size in [16, 32, 128, 256, 512] {
    try render(size, to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2, to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(1024, to: resources.appendingPathComponent("AppIcon.png"))
// Modern ICNS stores PNG payloads in length-prefixed, big-endian chunks.
// Write the documented container directly so generation also works when the
// sandboxed iconutil service cannot encode an otherwise valid iconset.
func integer(_ value: Int) -> Data {
    var bigEndian = UInt32(value).bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
}
let variants = [
    ("icp4", "icon_16x16.png"), ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"), ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"), ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"), ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")
]
var payload = Data()
for (type, filename) in variants {
    let png = try Data(contentsOf: iconset.appendingPathComponent(filename))
    payload.append(Data(type.utf8))
    payload.append(integer(png.count + 8))
    payload.append(png)
}
var icns = Data("icns".utf8)
icns.append(integer(payload.count + 8))
icns.append(payload)
let iconURL = resources.appendingPathComponent("AppIcon.icns")
try icns.write(to: iconURL)
guard let decoded = NSImage(contentsOf: iconURL), !decoded.representations.isEmpty else {
    fatalError("Generated ICNS cannot be decoded")
}
try fm.removeItem(at: iconset)
print("AppIcon.icns + AppIcon.png 已生成；字体 PostScript 名：\(postScriptName)")
