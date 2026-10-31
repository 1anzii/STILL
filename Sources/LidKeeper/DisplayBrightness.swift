// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import Foundation
import CoreGraphics
import ColorSync
import IOKit
import IOKit.pwr_mgt
import Darwin

struct BrightnessDisplay: Codable, Equatable {
    let identifier: String
    let displayID: UInt32
}

protocol LidBrightnessBackend: AnyObject {
    func lidClosed() -> Bool?
    func internalDisplay(matching identifier: String?) -> BrightnessDisplay?
    func brightness(of display: BrightnessDisplay) throws -> Double
    func setBrightness(_ value: Double, for display: BrightnessDisplay) throws
}

private enum DisplayBrightnessError: LocalizedError {
    case unavailable
    case displayUnavailable
    case invalidBrightness
    case readFailed(Int32)
    case writeFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "当前系统无法使用内置屏幕亮度接口。"
        case .displayUnavailable: return "暂时无法确认内置屏幕，请开盖后重试。"
        case .invalidBrightness: return "无法使用这个亮度值；调暗不会将亮度设为零。"
        case .readFailed(let code): return "无法读取内置屏幕亮度（\(code)）。"
        case .writeFailed(let code): return "无法调整内置屏幕亮度（\(code)）。"
        }
    }
}

/// Brightness belongs to the logged-in GUI session, never to the root helper.
/// Observation callbacks run on the main queue; the controller owns restoration.
final class SystemLidBrightnessBackend: LidBrightnessBackend {
    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32

    private let framework: UnsafeMutableRawPointer?
    private let getBrightness: GetBrightness?
    private let writeBrightness: SetBrightness?
    private let lock = NSRecursiveLock()
    // This cache is deliberately process-local. A saved restoration record does
    // not authorize a screen while starting the app with the lid already closed.
    private var verifiedInternalDisplay: BrightnessDisplay?
    private var observation: LidStateObservation?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                            RTLD_LAZY | RTLD_LOCAL)
        framework = handle
        getBrightness = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }
            .map { unsafeBitCast($0, to: GetBrightness.self) }
        writeBrightness = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }
            .map { unsafeBitCast($0, to: SetBrightness.self) }
    }

    deinit {
        // The IOKit callback's refcon stays alive until its main-queue source has
        // been disconnected, even if the last backend reference is released off-main.
        if let observation {
            if Thread.isMainThread { observation.stop() }
            else { DispatchQueue.main.async { observation.stop() } }
        }
        if let framework { dlclose(framework) }
    }

    func lidClosed() -> Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(root) }
        guard let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString,
                                                         kCFAllocatorDefault, 0)?.takeRetainedValue(),
              CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    func internalDisplay(matching identifier: String?) -> BrightnessDisplay? {
        lock.lock()
        defer { lock.unlock() }
        guard let closed = lidClosed() else { return nil }
        if closed {
            guard let cached = verifiedInternalDisplay,
                  identifier == nil || cached.identifier == identifier else { return nil }
            // A closed lid can make CGDisplayIsBuiltin return false. Only the
            // identity certified while open may bypass that check, never its ID
            // alone: IDs can be reused after a display configuration change.
            if Self.identifier(for: cached.displayID) == cached.identifier { return cached }
            guard let uuid = CFUUIDCreateFromString(kCFAllocatorDefault, cached.identifier as CFString) else { return nil }
            let currentID = CGDisplayGetDisplayIDFromUUID(uuid)
            guard currentID != kCGNullDirectDisplay,
                  Self.identifier(for: currentID) == cached.identifier else { return nil }
            let current = BrightnessDisplay(identifier: cached.identifier, displayID: currentID)
            verifiedInternalDisplay = current
            return current
        }

        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success,
              count > 0, count <= 256 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return nil }
        let candidates = ids.prefix(Int(count)).compactMap { id -> BrightnessDisplay? in
            guard CGDisplayIsBuiltin(id) == 1, CGDisplayIsOnline(id) == 1,
                  let uuid = Self.identifier(for: id), identifier == nil || uuid == identifier else { return nil }
            return BrightnessDisplay(identifier: uuid, displayID: id)
        }
        // Do not choose an arbitrary display if the system reports ambiguity.
        guard candidates.count == 1, let display = candidates.first,
              lidClosed() == false else { return nil }
        verifiedInternalDisplay = display
        return display
    }

    func brightness(of display: BrightnessDisplay) throws -> Double {
        lock.lock()
        defer { lock.unlock() }
        guard let getBrightness else { throw DisplayBrightnessError.unavailable }
        try validate(display)
        var value: Float = .nan
        let result = getBrightness(display.displayID, &value)
        guard result == 0 else { throw DisplayBrightnessError.readFailed(result) }
        guard value.isFinite, value >= 0, value <= 1 else { throw DisplayBrightnessError.invalidBrightness }
        return Double(value)
    }

    func setBrightness(_ value: Double, for display: BrightnessDisplay) throws {
        lock.lock()
        defer { lock.unlock() }
        // Check both representations: a positive Double may underflow to Float(0).
        let level = Float(value)
        guard value.isFinite, value > 0, value <= 1,
              level.isFinite, level > 0, level <= 1 else { throw DisplayBrightnessError.invalidBrightness }
        guard let writeBrightness, getBrightness != nil else { throw DisplayBrightnessError.unavailable }
        try validate(display)
        let result = writeBrightness(display.displayID, level)
        guard result == 0 else { throw DisplayBrightnessError.writeFailed(result) }
    }

    func startObserving(_ changed: @escaping () -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.startObserving(changed) }
            return
        }
        stopObserving()
        observation = LidStateObservation(changed: changed)
    }

    func stopObserving() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.stopObserving() }
            return
        }
        observation?.stop()
        observation = nil
    }

    private func validate(_ display: BrightnessDisplay) throws {
        guard let current = internalDisplay(matching: display.identifier), current == display else {
            throw DisplayBrightnessError.displayUnavailable
        }
    }

    private static func identifier(for displayID: UInt32) -> String? {
        guard displayID != kCGNullDirectDisplay,
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let text = CFUUIDCreateString(kCFAllocatorDefault, uuid) else { return nil }
        return text as String
    }
}

/// Only observes lid changes; it neither acknowledges nor requests system sleep.
private final class LidStateObservation {
    // IOPM.h: iokit_family_msg(sub_iokit_powermanagement, 0x100).
    // Swift cannot import this function-like C macro: (0x38 << 26) | (13 << 14) | 0x100.
    private static let clamshellStateChanged: UInt32 = 0xe0034100
    private var changed: (() -> Void)?
    private var port: IONotificationPortRef?
    private var notification: io_object_t = IO_OBJECT_NULL

    init?(changed: @escaping () -> Void) {
        self.changed = changed
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(root) }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return nil }
        self.port = port
        let result = IOServiceAddInterestNotification(port, root, kIOGeneralInterest, Self.receive,
                                                      Unmanaged.passUnretained(self).toOpaque(), &notification)
        guard result == KERN_SUCCESS else {
            stop()
            return nil
        }
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
    }

    deinit { stop() }

    func stop() {
        changed = nil
        if let port { IONotificationPortSetDispatchQueue(port, nil) }
        if notification != IO_OBJECT_NULL {
            IOObjectRelease(notification)
            notification = IO_OBJECT_NULL
        }
        if let port {
            IONotificationPortDestroy(port)
            self.port = nil
        }
    }

    private static let receive: IOServiceInterestCallback = { context, _, message, _ in
        guard message == clamshellStateChanged, let context else { return }
        let observation = Unmanaged<LidStateObservation>.fromOpaque(context).takeUnretainedValue()
        // Do not infer lid state from a possibly stale notification argument.
        // The controller reads AppleClamshellState and decides whether to act.
        observation.changed?()
    }
}
