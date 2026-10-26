// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import SwiftUI

private enum Enamel {
    static let ink = Color(red: 0.20, green: 0.18, blue: 0.10)
    static let secondary = Color(red: 0.41, green: 0.33, blue: 0.15)
    static let yellow = Color(red: 0.93, green: 0.74, blue: 0.18)
    static let light = Color(red: 1.0, green: 0.88, blue: 0.43)
    static let shade = Color(red: 0.58, green: 0.42, blue: 0.10)
}

private enum PaintGrain {
    static let image: NSImage = {
        let side = 384
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        var seed: UInt32 = 0x91E10DA5
        for y in 0..<side {
            for x in 0..<side {
                seed = seed &* 1664525 &+ 1013904223
                let level = CGFloat((seed >> 24) & 255) / 255
                // Fine pigment flecks with a broader, low-amplitude orange-peel
                // pattern. Cached once; it does not shimmer on status updates.
                let relief = sin(Double(x) * 0.51 + sin(Double(y) * 0.37)) * cos(Double(y) * 0.43)
                let value = CGFloat(relief) * 0.15 + level - 0.5
                bitmap.setColor(NSColor(white: value > 0 ? 1 : 0, alpha: min(0.30, abs(value) * 0.48)), atX: x, y: y)
            }
        }
        let image = NSImage(size: NSSize(width: side / 2, height: side / 2))
        image.addRepresentation(bitmap)
        return image
    }()
}

private enum CaseMaterial {
    // Loaded once from the app bundle. The image is only a material layer;
    // labels, indicators, and controls remain live native views above it.
    static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "WornYellowMetal-v1", withExtension: "png", subdirectory: "Textures") else { return nil }
        return NSImage(contentsOf: url)
    }()
}

/// The same painted metal is used on the controls and the printed manual.
/// The manual softens wear behind its longer text, while retaining worn edges.
private struct PaintedMetalSurface: View {
    var readableCenter = false

    var body: some View {
        LinearGradient(colors: [Color(red: 0.96, green: 0.78, blue: 0.25), Enamel.yellow,
                                Color(red: 0.89, green: 0.67, blue: 0.13)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(RadialGradient(colors: [Enamel.light.opacity(0.24), .clear],
                                    center: .topLeading, startRadius: 15, endRadius: 420))
            .overlay {
                if let material = CaseMaterial.image {
                    GeometryReader { geometry in
                        Image(nsImage: material).resizable().interpolation(.high).scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                            .opacity(0.60)
                            .mask {
                                if readableCenter {
                                    LinearGradient(stops: [
                                        .init(color: .white, location: 0),
                                        .init(color: .white.opacity(0.48), location: 0.12),
                                        .init(color: .white.opacity(0.48), location: 0.88),
                                        .init(color: .white, location: 1)
                                    ], startPoint: .leading, endPoint: .trailing)
                                } else {
                                    Color.white
                                }
                            }
                    }
                }
            }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// A flush metal fastener with a recessed slot. It belongs to the casing,
/// not the control layer, so it never receives input or accessibility focus.
private struct CaseScrew: View {
    var slotAngle: Double

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Enamel.ink.opacity(0.8), Enamel.light.opacity(0.85)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(Color(red: 0.29, green: 0.27, blue: 0.21)).padding(0.9)
            Circle()
                .fill(LinearGradient(stops: [
                    .init(color: Color(red: 0.87, green: 0.85, blue: 0.75), location: 0),
                    .init(color: Color(red: 0.65, green: 0.64, blue: 0.56), location: 0.35),
                    .init(color: Color(red: 0.76, green: 0.75, blue: 0.65), location: 0.61),
                    .init(color: Color(red: 0.43, green: 0.42, blue: 0.35), location: 1)
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Image(nsImage: PaintGrain.image).resizable(resizingMode: .tile)
                    .opacity(0.16).clipShape(Circle()))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.65), .black.opacity(0.35)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.45))
                .padding(1.3)
            Capsule().fill(Color(red: 0.21, green: 0.21, blue: 0.17))
                .frame(width: 7, height: 1.7).rotationEffect(.degrees(slotAngle))
                .shadow(color: Color(red: 0.95, green: 0.92, blue: 0.78).opacity(0.8), radius: 0, y: 0.6)
        }
        .frame(width: 12, height: 12)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private enum ManualFinish {
    static let ink = Color(red: 0.91, green: 0.90, blue: 0.86)
    static let secondary = Color(red: 0.76, green: 0.75, blue: 0.72)
    static let muted = Color(red: 0.67, green: 0.67, blue: 0.64)
    static let yellow = Color(red: 0.91, green: 0.76, blue: 0.35)
}

/// The instruction plate shares the knob's graphite finish. Hardware belongs
/// to the fixed casing rather than the scrolling printed instructions.
private struct ManualCase: View {
    var titlebarHeight: CGFloat

    var body: some View {
        LinearGradient(colors: [Color(white: 0.285), Color(white: 0.235), Color(white: 0.20)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                if let material = CaseMaterial.image {
                    GeometryReader { geometry in
                        Image(nsImage: material).resizable().interpolation(.high).scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                            .saturation(0).blendMode(.softLight).opacity(0.22)
                    }
                }
            }
            .overlay(Image(nsImage: PaintGrain.image).resizable(resizingMode: .tile).opacity(0.22))
            .overlay {
                RoundedRectangle(cornerRadius: 15).strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.20), .black.opacity(0.38)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7)
            }
            .overlay {
                GeometryReader { geometry in
                    // Keep the top screws below the native title/traffic lights,
                    // and all four outside the 44-point printed-content margin.
                    let top = titlebarHeight + 16
                    let bottom = geometry.size.height - 16
                    CaseScrew(slotAngle: -24).saturation(0.25).position(x: 16, y: top)
                    CaseScrew(slotAngle: 32).saturation(0.25).position(x: geometry.size.width - 16, y: top)
                    CaseScrew(slotAngle: 18).saturation(0.25).position(x: 16, y: bottom)
                    CaseScrew(slotAngle: -35).saturation(0.25).position(x: geometry.size.width - 16, y: bottom)
                }
            }
            .compositingGroup()
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct MachineCase: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 25)
                .fill(LinearGradient(colors: [Enamel.shade, Color(red: 0.46, green: 0.32, blue: 0.06)], startPoint: .top, endPoint: .bottom))
            PaintedMetalSurface()
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(
                    LinearGradient(colors: [Enamel.light.opacity(0.85), Enamel.shade.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Enamel.shade.opacity(0.20), lineWidth: 0.6).padding(2))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 1).padding(.top, 1).padding(.bottom, 5)
        }
        .overlay {
            GeometryReader { geometry in
                CaseScrew(slotAngle: -32).position(x: geometry.size.width - 16, y: geometry.size.height - 21)
                CaseScrew(slotAngle: 21).position(x: 16, y: geometry.size.height - 21)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 25))
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// A small resin lens in a recessed brass seat. The light only follows the
/// confirmed system state; moving the switch never lights it optimistically.
private struct StatusLamp: View {
    var state: PanelStatus.LED
    private var lit: Bool { state != .off }
    private var center: Color {
        switch state {
        case .off: return Color(red: 0.38, green: 0.42, blue: 0.23)
        case .green: return Color(red: 0.77, green: 0.97, blue: 0.46)
        case .amber: return Color(red: 1.0, green: 0.74, blue: 0.23)
        }
    }
    private var edge: Color {
        switch state {
        case .off: return Color(red: 0.16, green: 0.20, blue: 0.10)
        case .green: return Color(red: 0.14, green: 0.43, blue: 0.13)
        case .amber: return Color(red: 0.67, green: 0.30, blue: 0.04)
        }
    }
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Enamel.shade, Enamel.light.opacity(0.9)], startPoint: .top, endPoint: .bottom))
            Circle().fill(Color(red: 0.22, green: 0.18, blue: 0.07)).padding(1)
            Circle().fill(RadialGradient(colors: [center, edge], center: .init(x: 0.38, y: 0.30), startRadius: 0, endRadius: 6))
                .padding(2).shadow(color: lit ? center.opacity(0.55) : .clear, radius: 2)
            Ellipse().fill(.white.opacity(lit ? 0.65 : 0.25)).frame(width: 3.3, height: 1.7).rotationEffect(.degrees(-30)).offset(x: -1.3, y: -2)
        }.frame(width: 13, height: 13).accessibilityHidden(true)
    }
}

private struct PhysicalPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.offset(y: configuration.isPressed ? 0.8 : 0)
    }
}

private struct QuietDialFocus: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) { content.focusEffectDisabled() }
        else { content }
    }
}

private struct MachineLever: View {
    var position: Bool?
    var dragOffset: CGFloat?
    private var offset: CGFloat { dragOffset ?? position.map { $0 ? 21 : -21 } ?? 0 }
    // Color follows the confirmed position, never the drag or requested state.
    private var indicatorColors: [Color] {
        switch position {
        case false?: return [Color(red: 0.42, green: 0.15, blue: 0.12), Color(red: 0.76, green: 0.32, blue: 0.23)]
        case true?: return [Color(red: 0.13, green: 0.30, blue: 0.18), Color(red: 0.33, green: 0.54, blue: 0.26)]
        case nil: return [Enamel.shade.opacity(0.9), Enamel.shade.opacity(0.5)]
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(LinearGradient(colors: [Enamel.shade.opacity(0.9), Enamel.shade.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Enamel.ink.opacity(0.4), lineWidth: 0.7))
                .shadow(color: Enamel.light.opacity(0.8), radius: 0, y: 1)
            RoundedRectangle(cornerRadius: 7)
                .fill(LinearGradient(colors: indicatorColors, startPoint: .top, endPoint: .bottom))
                .overlay(Image(nsImage: PaintGrain.image).resizable(resizingMode: .tile)
                    .opacity(0.15).clipShape(RoundedRectangle(cornerRadius: 7)))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(
                    LinearGradient(colors: [.black.opacity(0.35), .white.opacity(0.18)],
                                   startPoint: .top, endPoint: .bottom), lineWidth: 0.7))
                .padding(2)
            if let position {
                Text(position ? "I" : "O")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.98, green: 0.95, blue: 0.83).opacity(0.8))
                    .shadow(color: .black.opacity(0.35), radius: 0, y: -0.5)
                    .offset(x: position ? -23 : 23).accessibilityHidden(true)
            }
            RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.08))
                .frame(width: 33, height: 29).offset(x: offset, y: 1.7)
                .shadow(color: Enamel.ink.opacity(0.3), radius: 1.8, x: 0.7, y: 2)
            RoundedRectangle(cornerRadius: 5)
                .fill(LinearGradient(colors: [Color(white: 0.34), Color(white: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.18), .black.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7))
                .overlay(Image(nsImage: PaintGrain.image).resizable(resizingMode: .tile).opacity(0.24).clipShape(RoundedRectangle(cornerRadius: 5)))
                .overlay {
                    HStack(spacing: 3) {
                        ForEach(0..<4, id: \.self) { _ in
                            Capsule().fill(.black.opacity(0.25)).frame(width: 0.8, height: 12)
                                .shadow(color: .white.opacity(0.15), radius: 0, x: 0.8)
                        }
                    }
                }
                .frame(width: 33, height: 28).offset(x: offset)
        }.frame(width: 80, height: 36)
    }
}

struct PanelView: View {
    @ObservedObject var model: SleepModel
    var viewportSize: CGSize = CGSize(width: 350, height: 420)
    var showHelp: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dialDrag: RotaryDialDrag?
    @State private var knobHovered = false
    @GestureState private var knobDragging = false
    @FocusState private var knobFocused: Bool
    @State private var switchDragOffset: CGFloat?
    @GestureState private var switchDragging = false

    private let durations = TimerDialScale.durations
    private var dialSize: CGFloat { min(256, viewportSize.width - 48) }
    private var knobSize: CGFloat { dialSize * 0.55 }
    private var selectedAngle: Double { TimerDialScale.angle(for: model.duration) }
    private var pointerAngle: Double { dialDrag?.angle ?? selectedAngle }
    private var canAdjustDial: Bool { !model.busy && !model.hasSession }
    private var switchState: RunSwitchState {
        RunSwitchState(busy: model.busy, recovering: model.recovering, hasSession: model.hasSession,
                       isAwake: model.isAwake, systemDisabled: model.systemDisabled)
    }
    private var canOperateSwitch: Bool { switchState.canStart || switchState.canStop }
    private var panelStatus: PanelStatus {
        PanelStatus(state: switchState, busyText: model.busyText, remaining: model.remaining, notice: model.notice)
    }
    private var warning: Bool { panelStatus.led == .amber }
    private var actionTitle: String {
        model.busy ? model.busyText : model.recovering ? "重试恢复休眠" : model.isAwake ? "恢复正常休眠" : "开启合盖保持运行"
    }
    private var confirmedState: String {
        switch switchState.position {
        case true: return "保持运行已开启"
        case false: return "正常休眠"
        default: return panelStatus.title
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 25).padding(.top, 15).padding(.bottom, 1)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.vertical) {
                selector.padding(.top, 3).padding(.bottom, 5)
                    .frame(maxWidth: .infinity)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            operatingSwitch.padding(.bottom, 13)
            statusLine.padding(.horizontal, 22).padding(.bottom, 18)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: viewportSize.width, height: viewportSize.height, alignment: .top)
        .foregroundStyle(Enamel.ink).background { MachineCase() }
        .preferredColorScheme(.light)
        .onChange(of: canAdjustDial) { enabled in
            if !enabled { dialDrag = nil; NSCursor.arrow.set() }
        }
        .onChange(of: knobDragging) { dragging in if !dragging { finishDialDrag() } }
        .onChange(of: switchDragging) { dragging in if !dragging { switchDragOffset = nil } }
        .onChange(of: model.busy) { busy in if busy { switchDragOffset = nil } }
        .onDisappear { dialDrag = nil; switchDragOffset = nil; NSCursor.arrow.set() }
        .alert("未能完成操作", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("知道了", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var header: some View {
        HStack {
            BrandWordmark(size: 20, tracking: 1.8)
            Spacer()
            Menu {
                Text(model.powerDescription)
                Toggle("仅接电源时运行", isOn: $model.acOnly).disabled(!canAdjustDial)
                Toggle("登录时启动", isOn: Binding(get: { model.loginEnabled }, set: model.setLoginEnabled))
                Divider()
                Button("使用说明与关于…", action: showHelp)
                Button(model.hasSession ? "恢复休眠并退出" : "退出 STILL", action: model.quit)
                    .keyboardShortcut("q").disabled(model.busy)
            } label: {
                Image(nsImage: EngravedSettingsIcon.image).renderingMode(.original).resizable().interpolation(.high)
                    .frame(width: 25, height: 25).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("设置与帮助").help("电源设置、使用说明与退出")
        }
    }

    private var selector: some View {
        ZStack {
            ForEach(0..<41, id: \.self) { tick in
                Capsule().fill(Enamel.ink.opacity(tick % 8 == 0 ? 0.85 : 0.45))
                    .frame(width: tick % 8 == 0 ? 1.5 : 0.7, height: tick % 8 == 0 ? 7 : 2.5)
                    .shadow(color: Enamel.light.opacity(0.65), radius: 0, y: 0.6)
                    .offset(y: -dialSize * 0.345).rotationEffect(.degrees(Double(tick) * 6 - 120))
            }.allowsHitTesting(false).accessibilityHidden(true)
            ForEach(durations, id: \.self) { seconds in
                let angle = TimerDialScale.angle(for: seconds) * .pi / 180
                let selected = model.duration == seconds
                Button { selectDuration(seconds) } label: {
                    MachineLabel(text: seconds == 1800 ? "30 MIN" : "\(seconds / 3600) H",
                                 size: seconds == 1800 ? 8.5 : 9, emphasized: selected)
                        .foregroundStyle(selected ? Enamel.ink : Enamel.secondary)
                        .shadow(color: Enamel.light.opacity(0.5), radius: 0, y: 0.5)
                        .frame(width: 52, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(PhysicalPress())
                .accessibilityLabel(seconds == 1800 ? "30 分钟" : "\(seconds / 3600) 小时")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .disabled(!canAdjustDial)
                .offset(x: sin(angle) * dialSize * 0.42, y: -cos(angle) * dialSize * 0.42)
            }
            dialControl
            Text(canAdjustDial ? "转动定时" : "定时已锁定")
                .font(.system(size: 9, weight: .medium)).tracking(1.5).foregroundStyle(Enamel.secondary)
                .offset(y: dialSize * 0.39).allowsHitTesting(false)
        }.frame(width: dialSize, height: dialSize)
    }

    private var dialControl: some View {
        knob
            .contentShape(Circle())
            .focusable(canAdjustDial).focused($knobFocused).modifier(QuietDialFocus())
            .highPriorityGesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .local)
                    .updating($knobDragging) { _, dragging, _ in dragging = true }
                    .onChanged(updateDialDrag)
                    .onEnded { _ in finishDialDrag() }
            )
            .onHover { hovering in
                knobHovered = hovering
                if canAdjustDial {
                    (hovering ? (dialDrag == nil ? NSCursor.openHand : NSCursor.closedHand) : NSCursor.arrow).set()
                }
            }
            .onMoveCommand { direction in
                switch direction {
                case .up, .right: stepDial(by: 1)
                case .down, .left: stepDial(by: -1)
                default: break
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("保持运行时间旋钮")
            .accessibilityValue(durationTitle)
            .accessibilityHint("拖动旋转，或用上下方向调整；也可点击周围刻度")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: stepDial(by: 1)
                case .decrement: stepDial(by: -1)
                @unknown default: break
                }
            }
            .help("转动旋钮或点击周围刻度选择时长")
            .disabled(!canAdjustDial)
    }

    private var gripShape: some View {
        Capsule().frame(width: knobSize * 0.235, height: knobSize * 0.67)
            .rotationEffect(.degrees(pointerAngle))
            .frame(width: knobSize, height: knobSize)
    }

    private var knob: some View {
        ZStack {
            Circle().fill(Enamel.shade.opacity(0.4)).blur(radius: 5)
                .frame(width: knobSize * 0.96, height: knobSize * 0.96).offset(x: 1, y: 6)
            Circle().fill(Color(white: 0.08)).frame(width: knobSize * 0.97, height: knobSize * 0.97).offset(y: 3)
            Circle().stroke(Enamel.shade.opacity(0.4), lineWidth: 1.2)
                .frame(width: knobSize + 3, height: knobSize + 3).offset(y: 2)
            Circle().fill(LinearGradient(colors: [Color(white: 0.32), Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: knobSize * 0.97, height: knobSize * 0.97)
            ForEach(0..<72, id: \.self) { tooth in
                Capsule().fill(Color.black.opacity(0.19)).frame(width: 0.7, height: 2.8)
                    .shadow(color: .white.opacity(0.12), radius: 0, x: 0.6)
                    .offset(y: -knobSize * 0.465).rotationEffect(.degrees(Double(tooth) * 5))
            }
            Circle().fill(LinearGradient(colors: [Color(white: 0.285), Color(white: 0.20)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: knobSize * 0.88, height: knobSize * 0.88)
                .overlay(Image(nsImage: PaintGrain.image).resizable(resizingMode: .tile).opacity(0.34).clipShape(Circle()))
                .overlay(Circle().strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.17), .black.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7))
            Color.black.opacity(0.4).mask(gripShape).blur(radius: 2).offset(x: 1.4, y: 3.5)
            // Rotate the grip geometry under a fixed light, rather than rotating
            // the highlight with the pointer. Its short shadow stays below it.
            LinearGradient(colors: [Color(white: 0.44), Color(white: 0.27), Color(white: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .mask(gripShape)
            Image(nsImage: PaintGrain.image).resizable(resizingMode: .tile).opacity(0.25).mask(gripShape)
            VStack(spacing: 3.3) {
                ForEach(0..<5, id: \.self) { _ in
                    Capsule().fill(.black.opacity(0.12)).frame(width: knobSize * 0.13, height: 0.8)
                        .shadow(color: .white.opacity(0.14), radius: 0, y: 0.7)
                }
            }.rotationEffect(.degrees(pointerAngle))
            Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.7)
                .frame(width: knobSize * 0.235, height: knobSize * 0.67)
                .rotationEffect(.degrees(pointerAngle))
            Capsule().fill(Color.black.opacity(0.6))
                .frame(width: 4.8, height: 14.8).offset(y: -knobSize * 0.36)
                .rotationEffect(.degrees(pointerAngle))
            Capsule().fill(LinearGradient(colors: [Color(red: 0.98, green: 0.93, blue: 0.78), Color(red: 0.79, green: 0.76, blue: 0.61)], startPoint: .top, endPoint: .bottom))
                .frame(width: 3, height: 13).offset(y: -knobSize * 0.36)
                .rotationEffect(.degrees(pointerAngle))
            Circle().stroke(Enamel.ink.opacity(knobFocused ? 0.35 : 0), style: StrokeStyle(lineWidth: 0.7, dash: [1, 3]))
                .frame(width: knobSize + 9, height: knobSize + 9)
        }.frame(width: knobSize, height: knobSize)
            .animation(dialDrag != nil || reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.78), value: pointerAngle)
    }

    private var operatingSwitch: some View {
        HStack(spacing: 14) {
            Button { requestRunning(false) } label: {
                MachineLabel(text: "SLEEP", size: 9.5, tracking: 0.5, emphasized: switchState.position == false)
                    .foregroundStyle(switchState.position == false ? Enamel.ink : Enamel.secondary)
                    .frame(width: 54, height: 36).contentShape(Rectangle())
            }
            .disabled(!switchState.canStop && switchState.position != false)
            .accessibilityLabel("恢复正常休眠")
            .accessibilityAddTraits(switchState.position == false ? .isSelected : [])
            Button { requestRunning(switchState.canStart) } label: {
                MachineLever(position: switchState.position, dragOffset: switchDragOffset)
            }
            .disabled(!canOperateSwitch)
            .highPriorityGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .local)
                    .updating($switchDragging) { _, dragging, _ in dragging = true }
                    .onChanged { value in
                        guard canOperateSwitch else { return }
                        switchDragOffset = leverTargetOffset(value.translation.width)
                    }
                    .onEnded { value in
                        let offset = leverTargetOffset(value.translation.width)
                        switchDragOffset = nil
                        guard abs(offset) > 4 else { return }
                        requestRunning(offset > 0)
                    }
            )
            .accessibilityLabel(actionTitle).accessibilityValue(confirmedState)
            .help("点击或左右拖动拨杆，切换正常休眠与保持运行")
            .keyboardShortcut(.return, modifiers: [])
            .animation(switchDragOffset != nil || reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.82), value: switchState.position)
            Button { requestRunning(true) } label: {
                MachineLabel(text: "RUN", size: 9.5, tracking: 0.5, emphasized: switchState.position == true)
                    .foregroundStyle(switchState.position == true ? Enamel.ink : Enamel.secondary)
                    .frame(width: 54, height: 36).contentShape(Rectangle())
            }
            .disabled(!switchState.canStart && switchState.position != true)
            .accessibilityLabel("开启合盖保持运行")
            .accessibilityAddTraits(switchState.position == true ? .isSelected : [])
        }.buttonStyle(PhysicalPress())
    }

    private var statusLine: some View {
        VStack(spacing: 5) {
            HStack(spacing: 7) {
                StatusLamp(state: panelStatus.led)
                Text(panelStatus.title)
                    .font(.system(size: 10.5, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(Enamel.ink)
            }
            if let detail = panelStatus.detail {
                statusDetail(detail)
            }
            if let notice = panelStatus.notice, notice != panelStatus.detail {
                statusDetail(notice)
            }
            if panelStatus.detail == nil && panelStatus.notice == nil {
                statusDetail(model.acOnly ? "仅接电源时运行" : "允许使用电池")
            }
        }.frame(maxWidth: .infinity).frame(minHeight: 34)
            .accessibilityElement(children: .combine)
    }

    private func statusDetail(_ text: String) -> some View {
        Text(text).font(.system(size: 9.5, weight: .medium))
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(warning ? Enamel.ink : Enamel.secondary)
    }

    private func leverTargetOffset(_ translation: CGFloat) -> CGFloat {
        let origin: CGFloat = switchState.position.map { $0 ? 21 : -21 } ?? 0
        return min(21, max(-21, origin + translation))
    }

    private func requestRunning(_ running: Bool) {
        switchDragOffset = nil
        guard switchState.accepts(running) else { return }
        model.setRunning(running)
    }

    private func selectDuration(_ seconds: Int) {
        guard canAdjustDial, model.duration != seconds else { return }
        dialDrag = nil
        model.duration = seconds
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private var durationTitle: String {
        model.duration == 1800 ? "30 分钟" : "\(model.duration / 3600) 小时"
    }

    private func stepDial(by step: Int) {
        guard canAdjustDial else { return }
        let index = durations.firstIndex(of: model.duration) ?? 1
        dialDrag = nil
        model.duration = durations[min(durations.count - 1, max(0, index + step))]
    }

    private func finishDialDrag() {
        guard dialDrag != nil else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.78)) {
            dialDrag = nil
        }
        (knobHovered && canAdjustDial ? NSCursor.openHand : NSCursor.arrow).set()
    }

    private func updateDialDrag(_ value: DragGesture.Value) {
        guard canAdjustDial else { dialDrag = nil; return }
        // The touch anchor is relative to the current selection. Grabbing a
        // different edge never jumps the dial to the pointer's absolute angle.
        var motion = dialDrag ?? RotaryDialDrag(
            angle: selectedAngle,
            touchAngle: TimerDialScale.touchAngle(x: Double(value.startLocation.x - knobSize / 2), y: Double(value.startLocation.y - knobSize / 2))
        )
        let angle = motion.update(touchAngle: TimerDialScale.touchAngle(
            x: Double(value.location.x - knobSize / 2), y: Double(value.location.y - knobSize / 2)
        ))
        dialDrag = motion
        let duration = TimerDialScale.nearestDuration(to: angle)
        if duration != model.duration {
            model.duration = duration
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        NSCursor.closedHand.set()
    }

}

struct HelpView: View {
    @ObservedObject var model: SleepModel
    var viewportSize: CGSize = CGSize(width: 510, height: 560)
    var titlebarHeight: CGFloat = 0
    @State private var confirmUninstall = false
    @State private var showLicense = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        BrandWordmark(size: 27, tracking: 2, finish: .brass)
                        Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.9.4")")
                            .font(.system(size: 12)).foregroundStyle(ManualFinish.muted)
                    }
                }
                if !model.helperReady {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("请授权安装或更新电源服务；完成后不会自动开启运行。")
                            .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                        Button("安装或更新电源服务…") { model.prepareHelper() }
                            .disabled(model.busy || model.hasSession || model.recovering || model.systemDisabled != false)
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    guideStep("01", title: "选时间", text: "转动旋钮，或点击刻度。")
                    guideStep("02", title: "开启运行", text: "拨到 RUN，绿灯亮后再合盖。首次需管理员授权。")
                    guideStep("03", title: "恢复休眠", text: "拨回 SLEEP，确认显示“正常休眠”。")
                }
                Text("保持通风，入包前先确认已恢复休眠。")
                    .font(.system(size: 12, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Capsule().fill(ManualFinish.yellow).frame(width: 2)
                    }
                Divider()
                DisclosureGroup("设置与保护") {
                    VStack(alignment: .leading, spacing: 14) {
                        section("电源与启动", text: "默认仅接电源运行，拔电会恢复休眠；关闭此项可用电池，不设最低电量限制。登录时启动不会自动开启运行。")
                        section("状态与保护", text: "红 O 关闭，绿 I 开启；黄灯表示处理中或需检查。到时、退出、失联、读电源失败或温度过高时，后台会尝试恢复休眠，以界面状态为准。")
                        section("休眠范围", text: "RUN 暂停整机休眠；SLEEP 恢复 macOS 正常规则，并非立即睡着。外接显示器或其他程序仍可能保持唤醒。")
                    }
                    .padding(.top, 10)
                }
                DisclosureGroup("安装与分享") {
                    VStack(alignment: .leading, spacing: 14) {
                        section("", text: "支持 macOS 13 及以上、Apple 芯片与 Intel。打开 DMG 或解压 ZIP，将 STILL.app 拖入“应用程序”。\n\n此版本未经过 Apple 公证。确认来源可信后，可在“系统设置 → 隐私与安全性”选择“仍要打开”；公司 Mac 可能需要 IT 允许。")
                        section("许可与免责声明", text: "© 2026 1anzii · GPL-3.0-only\n可按许可使用、修改与分发。软件按现状提供，不作担保；兼容性及运行效果因设备而异。请自行评估使用风险，责任范围以适用法律及许可条款为准。")
                        Button("查看开源许可") { showLicense = true }
                            .font(.system(size: 11)).buttonStyle(.link)
                    }.padding(.top, 10)
                }
                DisclosureGroup("故障恢复与卸载") {
                    VStack(alignment: .leading, spacing: 14) {
                        section("无法恢复休眠", text: "保持应用打开，按状态提示处理。仍失败时可在终端执行下列命令；需管理员密码，也会影响其他防休眠工具。")
                        HStack {
                            Text("sudo pmset -a disablesleep 0").font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            Spacer()
                            Button("复制命令") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("sudo pmset -a disablesleep 0", forType: .string)
                            }
                        }
                        section("卸载 STILL", text: "先恢复休眠、关闭“登录时启动”，再卸载电源服务，最后退出并删除 STILL。服务由本机已授权用户共用。")
                        Button("卸载电源服务…") { confirmUninstall = true }
                            .disabled(model.busy || model.hasSession || !FileManager.default.fileExists(atPath: PowerClient.installedHelper))
                    }.padding(.top, 10)
                }
                Spacer(minLength: 4)
                HStack {
                    Text("无需联网 · 不收集数据")
                        .font(.system(size: 11)).foregroundStyle(ManualFinish.muted)
                    Spacer()
                    Text("1anzii")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(ManualFinish.muted.opacity(0.75))
                }
            }
            .frame(maxWidth: .infinity, minHeight: max(0, viewportSize.height - titlebarHeight - 76), alignment: .topLeading)
            .padding(.horizontal, 44).padding(.top, 36).padding(.bottom, 40)
        }
        .frame(width: viewportSize.width, height: max(1, viewportSize.height - titlebarHeight))
        .clipped()
        .padding(.top, titlebarHeight)
        .frame(width: viewportSize.width, height: viewportSize.height)
        .foregroundStyle(ManualFinish.ink)
        .background {
            // One fixed surface extends behind the native title bar. Only the
            // scroll viewport is inset, so no second material creates a seam.
            ManualCase(titlebarHeight: titlebarHeight)
        }
        .preferredColorScheme(.dark)
        .tint(ManualFinish.yellow)
        // AppKit's measured titlebarHeight already reserves the chrome area.
        .ignoresSafeArea()
        .sheet(isPresented: $showLicense) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("开源许可").font(.headline)
                    Spacer()
                    Button("完成") { showLicense = false }.keyboardShortcut(.defaultAction)
                }
                ScrollView {
                    Text(licenseText)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20).frame(width: 470, height: 460)
            .preferredColorScheme(.dark)
        }
        .confirmationDialog("卸载这台 Mac 上的 STILL 电源服务？其他已授权用户也将无法使用，直到重新安装。", isPresented: $confirmUninstall) {
            Button("卸载电源服务", role: .destructive) { model.uninstallHelper() }
            Button("取消", role: .cancel) {}
        }
        .alert("未能完成操作", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("知道了", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt", subdirectory: "Licenses"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "未能读取随附许可。完整 GPL-3.0 条款：\nhttps://www.gnu.org/licenses/gpl-3.0.html"
        }
        return "STILL · © 2026 1anzii · GPL-3.0-only\n\n" + text
    }

    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty { Text(title).font(.system(size: 13, weight: .semibold)) }
            Text(text).font(.system(size: 12)).foregroundStyle(ManualFinish.secondary).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }

    private func guideStep(_ number: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.custom(Brand.fontPostScriptName, size: 11))
                .foregroundStyle(ManualFinish.yellow).frame(width: 25, alignment: .leading).padding(.top, 2)
            section(title, text: text)
        }
    }
}
