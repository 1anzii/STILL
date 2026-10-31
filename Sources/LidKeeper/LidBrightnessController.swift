// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import Foundation
import Darwin

/// Called serially by the application. This controller never changes sleep state.
final class LidBrightnessController {
    static let dimmedBrightness = 1.0 / 64.0
    private static let tolerance = 1.0 / 1024.0

    private struct Recovery: Codable {
        var version = 1
        let displayIdentifier: String
        let originalBrightness: Double
        let targetBrightness: Double
        var appliedBrightness: Double?
        var abandoned = false
    }

    private let backend: LidBrightnessBackend
    private let recoveryURL: URL
    private let now: () -> TimeInterval
    private var recovery: Recovery?
    private var loadFailed = false
    private var fromPreviousProcess = false
    private var restorationRequested = false
    private var suppressUntilOpen = false
    private var nextRestoreWrite: TimeInterval = 0
    private var restoreFailures = 0

    private(set) var statusText: String?
    var hasPendingRestoration: Bool { loadFailed || recovery.map { !$0.abandoned } == true }

    init(backend: LidBrightnessBackend, recoveryURL: URL,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.backend = backend
        self.recoveryURL = recoveryURL
        self.now = now
        do {
            guard recoveryURL.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
            if FileManager.default.fileExists(atPath: recoveryURL.path) {
                let attributes = try FileManager.default.attributesOfItem(atPath: recoveryURL.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular,
                      let size = attributes[.size] as? NSNumber, size.intValue <= 4096 else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let record = try JSONDecoder().decode(Recovery.self, from: Data(contentsOf: recoveryURL))
                guard Self.valid(record) else { throw CocoaError(.fileReadCorruptFile) }
                recovery = record
                fromPreviousProcess = true
                restorationRequested = true
                suppressUntilOpen = true
                statusText = "等待开盖恢复屏幕亮度。"
            }
        } catch {
            loadFailed = true
            statusText = "亮度恢复记录无法读取，未调节屏幕。"
        }
    }

    func refresh(enabled: Bool) {
        guard !loadFailed else { return }
        if recovery?.abandoned == true {
            finishRecovery(message: statusText)
            guard recovery == nil else { return }
        }
        let closed = backend.lidClosed()
        if closed == false {
            suppressUntilOpen = false
            // The backend only trusts a closed-lid display after observing
            // the physical built-in display while the lid was open.
            _ = backend.internalDisplay(matching: nil)
        }

        if recovery != nil {
            if !enabled || closed == false { restorationRequested = true }
            guard let closed else {
                statusText = "等待确认开盖状态后恢复屏幕亮度。"
                return
            }
            if fromPreviousProcess && closed {
                statusText = "等待开盖恢复屏幕亮度。"
                return
            }
            if restorationRequested {
                restore()
            } else {
                observeOwnedBrightness()
            }
            return
        }

        guard enabled else { statusText = nil; return }
        guard let closed else {
            statusText = "暂时无法读取合盖状态，未调节亮度。"
            return
        }
        guard closed else { statusText = nil; return }
        guard !suppressUntilOpen else { return }
        dimOnce()
    }

    func restoreBeforeExit() {
        guard !loadFailed, recovery != nil else { return }
        suppressUntilOpen = true
        restorationRequested = true
        if recovery?.abandoned == true { finishRecovery(message: nil); return }
        guard let closed = backend.lidClosed(), !(fromPreviousProcess && closed) else {
            statusText = "亮度恢复记录已保留，请开盖后重新打开 STILL。"
            return
        }
        // A final exit attempt may bypass the ordinary retry delay, but still
        // requires the same display identity and an unchanged owned value.
        nextRestoreWrite = 0
        restore()
    }

    private func dimOnce() {
        guard let display = backend.internalDisplay(matching: nil), !display.identifier.isEmpty else {
            statusText = "暂时无法识别内置屏幕，未调节亮度。"
            return
        }
        let original: Double
        do { original = try checkedBrightness(display) }
        catch { statusText = "暂时无法读取屏幕亮度，稍后重试。"; return }
        guard original > Self.dimmedBrightness else {
            // Do not brighten an already dark screen, including an original 0.
            suppressUntilOpen = true
            statusText = nil
            return
        }
        let record = Recovery(displayIdentifier: display.identifier,
                              originalBrightness: original, targetBrightness: Self.dimmedBrightness)
        suppressUntilOpen = true
        do { try persist(record) }
        catch {
            // A failed fsync can leave an atomic intent on disk, but no display
            // write has happened. Keep that intent recoverable if it exists.
            if FileManager.default.fileExists(atPath: recoveryURL.path) {
                recovery = record
                restorationRequested = true
            }
            statusText = "无法保存亮度恢复记录，未调节屏幕。"
            return
        }
        recovery = record
        fromPreviousProcess = false
        restorationRequested = false
        do {
            // Persistence can take time. Recheck the lid and the sampled
            // brightness before making the first hardware change.
            guard backend.lidClosed() == true else {
                restorationRequested = true
                statusText = "合盖状态已变化，未调节屏幕。"
                return
            }
            let current = try checkedBrightness(display)
            guard Self.matches(current, original) else {
                finishRecovery(message: "亮度已由其他设置调整，保留当前值。")
                return
            }
            guard backend.lidClosed() == true else {
                restorationRequested = true
                statusText = "合盖状态已变化，未调节屏幕。"
                return
            }
            try backend.setBrightness(record.targetBrightness, for: display)
            let actual = try checkedBrightness(display)
            guard Self.matches(actual, record.targetBrightness), actual > 0 else {
                // The immediate readback belongs to this write transaction.
                // Remember even a rounded-to-zero result solely for rollback;
                // it is never used as a setter argument.
                recovery?.appliedBrightness = actual
                if let recovery { try persist(recovery) }
                restorationRequested = true
                statusText = "屏幕未确认调暗，正在恢复原亮度。"
                restore()
                if !hasPendingRestoration { statusText = "屏幕未确认调暗，已恢复原亮度。" }
                return
            }
            recovery?.appliedBrightness = actual
            if let recovery { try persist(recovery) }
            if backend.lidClosed() != true {
                restorationRequested = true
                restore()
                return
            }
            statusText = "合盖时已调低内置屏幕亮度。"
        } catch {
            restorationRequested = true
            statusText = "亮度调整尚未确认，正在检查恢复。"
            // A setter can throw after changing the hardware. The durable
            // intent lets restore inspect the value before deciding to write.
            restore()
            if !hasPendingRestoration { statusText = "未能完成调暗，已结束本次亮度调整。" }
        }
    }

    private func observeOwnedBrightness() {
        guard let record = recovery else { return }
        do {
            let display = try matchingDisplay(record)
            let current = try checkedBrightness(display)
            guard Self.matches(current, record.appliedBrightness ?? record.targetBrightness) else {
                finishRecovery(message: "亮度已由其他设置调整，保留当前值。")
                return
            }
            statusText = "合盖时已调低内置屏幕亮度。"
        } catch {
            statusText = "暂时无法确认屏幕亮度，恢复记录已保留。"
        }
    }

    private func restore() {
        guard let record = recovery, !record.abandoned else { return }
        var attemptedWrite = false
        do {
            let display = try matchingDisplay(record)
            let current = try checkedBrightness(display)
            if Self.matches(current, record.originalBrightness) {
                finishRecovery(message: nil)
                return
            }
            guard Self.matches(current, record.appliedBrightness ?? record.targetBrightness) else {
                finishRecovery(message: "亮度已由其他设置调整，保留当前值。")
                return
            }
            guard now() >= nextRestoreWrite else { return }
            guard let closed = backend.lidClosed(), !(fromPreviousProcess && closed) else {
                statusText = "等待开盖恢复屏幕亮度。"
                return
            }
            attemptedWrite = true
            try backend.setBrightness(record.originalBrightness, for: display)
            let restored = try checkedBrightness(display)
            guard Self.matches(restored, record.originalBrightness) else {
                throw CocoaError(.fileReadUnknown)
            }
            finishRecovery(message: nil)
        } catch {
            if attemptedWrite {
                restoreFailures = min(restoreFailures + 1, 5)
                nextRestoreWrite = now() + min(pow(2, Double(restoreFailures - 1)), 16)
            }
            statusText = "屏幕亮度恢复尚未确认，稍后重试。"
        }
    }

    private func matchingDisplay(_ record: Recovery) throws -> BrightnessDisplay {
        guard let display = backend.internalDisplay(matching: record.displayIdentifier),
              display.identifier == record.displayIdentifier else { throw CocoaError(.fileReadNoSuchFile) }
        return display
    }

    private func checkedBrightness(_ display: BrightnessDisplay) throws -> Double {
        let value = try backend.brightness(of: display)
        guard value.isFinite, (0...1).contains(value) else { throw CocoaError(.fileReadCorruptFile) }
        return value
    }

    private func finishRecovery(message: String?) {
        guard var record = recovery else { return }
        // Once restored or externally changed, a cleanup failure must not
        // authorize another brightness write during this process or on restart.
        record.abandoned = true
        recovery = record
        do {
            if FileManager.default.fileExists(atPath: recoveryURL.path) {
                try FileManager.default.removeItem(at: recoveryURL)
            }
            recovery = nil
            fromPreviousProcess = false
            restorationRequested = false
            restoreFailures = 0
            nextRestoreWrite = 0
            statusText = message
        } catch {
            try? persist(record)
            statusText = "亮度无需恢复，恢复记录暂未清理。"
        }
    }

    private static func matches(_ first: Double, _ second: Double) -> Bool {
        first.isFinite && second.isFinite && abs(first - second) <= tolerance
    }

    private static func valid(_ record: Recovery) -> Bool {
        record.version == 1 && !record.displayIdentifier.isEmpty && record.displayIdentifier.utf8.count <= 256
            && record.originalBrightness.isFinite && record.originalBrightness > dimmedBrightness
            && record.originalBrightness <= 1 && record.targetBrightness == dimmedBrightness
            && record.appliedBrightness.map { $0.isFinite && (0...1).contains($0) } != false
    }

    private func persist(_ record: Recovery) throws {
        let directory = recoveryURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let temporary = directory.appendingPathComponent(".brightness-\(UUID().uuidString).tmp")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(fd); unlink(temporary.path) }
        let bytes = try JSONEncoder().encode(record)
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { throw CocoaError(.fileWriteUnknown) }
                offset += written
            }
        }
        guard fsync(fd) == 0, rename(temporary.path, recoveryURL.path) == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        let folderFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard folderFD >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(folderFD) }
        guard fsync(folderFD) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}
