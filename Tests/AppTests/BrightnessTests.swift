// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import Foundation

private enum ProbeError: Error { case read, write }

private final class MockBrightness: LidBrightnessBackend {
    var lid: Bool? = false
    var display: BrightnessDisplay? = BrightnessDisplay(identifier: "built-in-A", displayID: 11)
    var value = 0.75
    var authenticatedOpenDisplay = false
    var openDiscoveries = 0
    var failReads = false
    var failedWritesRemaining = 0
    var throwAfterWritingTarget = false
    var roundedTarget: Double?
    var beforeRead: (() -> Void)?
    var beforeWrite: ((Double) -> Void)?
    var writes: [(Double, UInt32)] = []

    func lidClosed() -> Bool? { lid }
    func internalDisplay(matching identifier: String?) -> BrightnessDisplay? {
        if lid == false {
            openDiscoveries += 1
            authenticatedOpenDisplay = display != nil
        }
        guard let display, identifier == nil || identifier == display.identifier,
              lid == false || authenticatedOpenDisplay else { return nil }
        return display
    }
    func brightness(of display: BrightnessDisplay) throws -> Double {
        beforeRead?()
        guard !failReads, display == self.display else { throw ProbeError.read }
        return value
    }
    func setBrightness(_ value: Double, for display: BrightnessDisplay) throws {
        precondition(value.isFinite && value > 0 && value <= 1, "Never set zero or an invalid brightness")
        guard display == self.display else { throw ProbeError.write }
        writes.append((value, display.displayID))
        beforeWrite?(value)
        if failedWritesRemaining > 0 {
            failedWritesRemaining -= 1
            throw ProbeError.write
        }
        let target = LidBrightnessController.dimmedBrightness
        self.value = value == target ? (roundedTarget ?? value) : value
        if value == target && throwAfterWritingTarget { throw ProbeError.write }
    }
}

private final class Fixture {
    let directory: URL
    let journal: URL
    let backend = MockBrightness()
    var clock: TimeInterval = 100
    lazy var controller = makeController()

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("STILL-brightness-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        journal = directory.appendingPathComponent("brightness-recovery.json")
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
    func makeController() -> LidBrightnessController {
        LidBrightnessController(backend: backend, recoveryURL: journal, now: { [unowned self] in self.clock })
    }
    func closeAndDim() {
        backend.lid = false
        controller.refresh(enabled: true)
        backend.lid = true
        controller.refresh(enabled: true)
    }
    var hasJournal: Bool { FileManager.default.fileExists(atPath: journal.path) }
}

@main
struct BrightnessTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ description: String) {
        precondition(condition(), description)
        checks += 1
    }
    static func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.00001 }

    static func main() throws {
        try normalCycle()
        try untouchedInputs()
        try externalAdjustments()
        try persistenceAndRestart()
        try failedOperations()
        try identityAndExit()
        try rapidLidChanges()
        print("Brightness tests passed: \(checks) checks; mock displays only, no real brightness or power writes.")
    }

    static func normalCycle() throws {
        let f = try Fixture()
        f.controller.refresh(enabled: true)
        expect(f.backend.openDiscoveries > 0, "Open preflight authenticates the built-in display without changing brightness")
        expect(f.backend.writes.isEmpty && !f.hasJournal, "Open lid alone causes no hardware or recovery write")
        f.backend.beforeWrite = { value in
            if value == LidBrightnessController.dimmedBrightness {
                expect(f.hasJournal, "Recovery intent exists before dimming")
                let json = try! JSONSerialization.jsonObject(with: Data(contentsOf: f.journal)) as! [String: Any]
                expect(json["originalBrightness"] as? Double == 0.75, "Original brightness is durably recorded before setter")
            }
        }
        f.backend.lid = true
        f.controller.refresh(enabled: true)
        expect(near(f.backend.value, 1.0 / 64), "Close dims to nonzero target")
        expect(f.controller.hasPendingRestoration && f.hasJournal, "Owned dimming retains recovery intent")
        expect(f.controller.statusText?.contains("已调低") == true, "Confirmed dimming has an accurate status")
        for _ in 0..<50 { f.controller.refresh(enabled: true) }
        expect(f.backend.writes.count == 1, "Repeated closed polls do not rewrite or replace original brightness")
        let attributes = try FileManager.default.attributesOfItem(atPath: f.journal.path)
        expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Recovery file remains private")
        f.backend.lid = false
        f.controller.refresh(enabled: true)
        expect(near(f.backend.value, 0.75) && f.backend.writes.count == 2, "Opening restores the original exactly once")
        expect(!f.controller.hasPendingRestoration && !f.hasJournal, "Verified restoration removes recovery responsibility")
        for _ in 0..<10 { f.controller.refresh(enabled: true) }
        expect(f.backend.writes.count == 2, "Open polls remain idempotent")
        f.backend.beforeWrite = nil
    }

    static func untouchedInputs() throws {
        for original in [0.0, 1.0 / 128, 1.0 / 64] {
            let f = try Fixture()
            f.backend.value = original
            f.closeAndDim()
            expect(f.backend.writes.isEmpty && !f.hasJournal, "Already dim or zero brightness is untouched")
            expect(f.backend.value == original, "Closing never brightens a dark display")
        }
        for original in [Double.nan, Double.infinity, -0.1, 1.1] {
            let f = try Fixture()
            f.backend.value = original
            f.closeAndDim()
            expect(f.backend.writes.isEmpty && !f.hasJournal, "Invalid brightness cannot create an ownership record or a write")
            expect(f.controller.statusText != nil, "An invalid reading is not reported as successful dimming")
        }
        do {
            let f = try Fixture()
            f.backend.lid = nil
            f.controller.refresh(enabled: true)
            expect(f.backend.writes.isEmpty && !f.hasJournal, "Unknown lid state is read-only")
            f.backend.lid = true
            f.controller.refresh(enabled: true)
            expect(f.backend.writes.isEmpty, "Starting closed without an authenticated open display does not guess")
            f.backend.lid = false
            f.controller.refresh(enabled: true)
            f.backend.lid = true
            f.controller.refresh(enabled: false)
            expect(f.backend.writes.isEmpty, "Disabled option never starts dimming")
        }
        do {
            let f = try Fixture()
            f.backend.display = nil
            f.closeAndDim()
            expect(f.backend.writes.isEmpty && !f.hasJournal, "No supported built-in display means no write")
        }
    }

    static func externalAdjustments() throws {
        for changed in [0.0, 0.4, 1.0] {
            let f = try Fixture()
            f.closeAndDim()
            f.backend.value = changed
            f.controller.refresh(enabled: true)
            for _ in 0..<10 { f.controller.refresh(enabled: true) }
            expect(f.backend.value == changed && f.backend.writes.count == 1, "External changes are preserved without closed-lid fighting")
            expect(!f.controller.hasPendingRestoration && !f.hasJournal, "External changes release restoration ownership")
            f.backend.lid = false
            f.controller.refresh(enabled: true)
            expect(f.backend.value == changed && f.backend.writes.count == 1, "Opening cannot undo the user's new brightness")
        }
        do {
            let f = try Fixture()
            f.closeAndDim()
            f.backend.value = 0.5
            f.controller.refresh(enabled: true)
            f.backend.lid = false
            f.controller.refresh(enabled: true)
            f.backend.lid = true
            f.controller.refresh(enabled: true)
            f.backend.lid = false
            f.controller.refresh(enabled: true)
            expect(near(f.backend.value, 0.5), "A later lid cycle captures the new original rather than the older session's value")
        }
        do {
            let f = try Fixture()
            f.controller.refresh(enabled: true)
            f.backend.lid = true
            var reads = 0
            f.backend.beforeRead = {
                reads += 1
                if reads == 2 { f.backend.value = 0.55 }
            }
            f.controller.refresh(enabled: true)
            expect(f.backend.writes.isEmpty && near(f.backend.value, 0.55), "A brightness change while persisting the intent is not overwritten")
            expect(!f.hasJournal, "Unapplied intent is released after a conflicting adjustment")
            f.backend.beforeRead = nil
        }
    }

    static func persistenceAndRestart() throws {
        do {
            let f = try Fixture()
            f.closeAndDim()
            f.backend.authenticatedOpenDisplay = false
            let restarted = f.makeController()
            restarted.refresh(enabled: true)
            restarted.refresh(enabled: false)
            restarted.restoreBeforeExit()
            expect(f.backend.writes.count == 1 && restarted.hasPendingRestoration, "A previous process's closed-lid record waits even when disabled or exiting")
            f.backend.lid = false
            restarted.refresh(enabled: false)
            expect(near(f.backend.value, 0.75) && f.backend.writes.count == 2, "Opening after restart restores the authenticated internal display")
            expect(!restarted.hasPendingRestoration && !f.hasJournal, "Restart recovery clears only after verification")
        }
        for changed in [false, true] {
            let f = try Fixture()
            f.closeAndDim()
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: f.journal)) as! [String: Any]
            json.removeValue(forKey: "appliedBrightness")
            try JSONSerialization.data(withJSONObject: json).write(to: f.journal)
            f.backend.value = changed ? LidBrightnessController.dimmedBrightness : 0.75
            let count = f.backend.writes.count
            let restarted = f.makeController()
            f.backend.lid = false
            restarted.refresh(enabled: true)
            expect(near(f.backend.value, 0.75), "Prepared intent recovers whether the crash preceded or followed the setter")
            expect(f.backend.writes.count == count + (changed ? 1 : 0), "A pre-write crash does not cause a needless restoration write")
            expect(!f.hasJournal, "Prepared-intent recovery is finalized")
        }
        do {
            let f = try Fixture()
            try Data("invalid-json".utf8).write(to: f.journal)
            let blocked = f.makeController()
            f.backend.lid = true
            blocked.refresh(enabled: true)
            blocked.restoreBeforeExit()
            expect(f.backend.writes.isEmpty && blocked.hasPendingRestoration, "Corrupt recovery data fails closed without guessing original brightness")
            expect(try! String(contentsOf: f.journal, encoding: .utf8) == "invalid-json", "Corrupt records are not silently overwritten")
        }
        do {
            let f = try Fixture()
            let blocker = f.directory.appendingPathComponent("not-a-directory")
            try Data("block".utf8).write(to: blocker)
            let blocked = LidBrightnessController(backend: f.backend, recoveryURL: blocker.appendingPathComponent("record.json"))
            blocked.refresh(enabled: true)
            f.backend.lid = true
            blocked.refresh(enabled: true)
            expect(f.backend.writes.isEmpty, "Persistence failure prevents all brightness writes")
            expect(blocked.statusText?.contains("无法保存") == true, "Persistence failure is visible and is not called success")
        }
    }

    static func failedOperations() throws {
        do {
            let f = try Fixture()
            f.backend.failedWritesRemaining = 1
            f.closeAndDim()
            expect(near(f.backend.value, 0.75) && !f.hasJournal, "A setter failure before a change clears an unused intent")
            for _ in 0..<20 { f.controller.refresh(enabled: true) }
            expect(f.backend.writes.count == 1, "Failed dimming does not spam the setter in the same lid cycle")
        }
        do {
            let f = try Fixture()
            f.backend.throwAfterWritingTarget = true
            f.closeAndDim()
            expect(near(f.backend.value, 0.75) && f.backend.writes.count == 2, "A setter throwing after a change rolls back the owned target")
            expect(!f.controller.hasPendingRestoration && !f.hasJournal, "Confirmed rollback clears recovery")
        }
        do {
            let f = try Fixture()
            f.backend.roundedTarget = 0
            f.closeAndDim()
            expect(near(f.backend.value, 0.75), "A driver rounding the requested nonzero target to zero is rolled back")
            expect(f.backend.writes.allSatisfy { $0.0 > 0 }, "Rollback never uses zero as a setter value")
            expect(f.controller.statusText?.contains("已调低") != true, "A zero readback never claims successful dimming")
        }
        do {
            let f = try Fixture()
            f.closeAndDim()
            f.backend.lid = false
            f.backend.failedWritesRemaining = 1
            f.controller.refresh(enabled: true)
            expect(f.controller.hasPendingRestoration && f.hasJournal, "A failed restoration retains durable responsibility")
            let count = f.backend.writes.count
            for _ in 0..<20 { f.controller.refresh(enabled: true) }
            expect(f.backend.writes.count == count, "Restoration retries cannot repeatedly call the setter within the backoff interval")
            f.clock += 1
            f.controller.refresh(enabled: true)
            expect(near(f.backend.value, 0.75) && !f.hasJournal, "Transient restoration failure is retried after backoff")
        }
        do {
            let f = try Fixture()
            f.closeAndDim()
            f.backend.lid = false
            f.backend.failReads = true
            for _ in 0..<20 { f.controller.refresh(enabled: true) }
            expect(f.controller.hasPendingRestoration && f.backend.writes.count == 1, "Unknown current brightness never authorizes a restoration write")
            f.backend.failReads = false
            f.controller.refresh(enabled: true)
            expect(near(f.backend.value, 0.75), "Recovered readings allow immediate restoration without artificial write backoff")
        }
        do {
            let f = try Fixture()
            f.closeAndDim()
            f.backend.lid = nil
            f.controller.refresh(enabled: false)
            f.controller.restoreBeforeExit()
            expect(f.backend.writes.count == 1 && f.hasJournal, "Unknown lid state retains recovery but performs no writes")
        }
    }

    static func identityAndExit() throws {
        do {
            let f = try Fixture()
            f.closeAndDim()
            f.backend.display = BrightnessDisplay(identifier: "built-in-A", displayID: 99)
            f.backend.lid = false
            f.controller.refresh(enabled: true)
            expect(f.backend.writes.last?.1 == 99 && near(f.backend.value, 0.75), "Stable identity resolves a changed numeric display ID")
        }
        do {
            let f = try Fixture()
            f.closeAndDim()
            f.backend.display = BrightnessDisplay(identifier: "different-screen", displayID: 11)
            f.backend.lid = false
            f.controller.refresh(enabled: true)
            expect(f.backend.writes.count == 1 && f.hasJournal, "A reused numeric ID never restores a different physical display")
            f.backend.display = nil
            f.controller.restoreBeforeExit()
            expect(f.backend.writes.count == 1 && f.hasJournal, "Missing display on exit retains recovery data")
        }
        for exiting in [false, true] {
            let f = try Fixture()
            f.closeAndDim()
            if exiting { f.controller.restoreBeforeExit() }
            else { f.controller.refresh(enabled: false) }
            expect(near(f.backend.value, 0.75) && !f.hasJournal, "Disable and quit restore this process's owned brightness even while closed")
            f.controller.refresh(enabled: true)
            expect(f.backend.writes.count == 2, "A canceled exit cannot immediately re-dim the same closed-lid cycle")
        }
    }

    static func rapidLidChanges() throws {
        for changedOnRead in [1, 2] {
            let f = try Fixture()
            f.controller.refresh(enabled: true)
            f.backend.lid = true
            var reads = 0
            f.backend.beforeRead = {
                reads += 1
                if reads == changedOnRead { f.backend.lid = false }
            }
            f.controller.refresh(enabled: true)
            expect(f.backend.writes.isEmpty, "Opening during sampling or persistence prevents a late dimming write")
            f.backend.beforeRead = nil
            f.controller.refresh(enabled: true)
            expect(!f.hasJournal && near(f.backend.value, 0.75), "An unapplied intent is cleared safely on the next open refresh")
        }
        do {
            let f = try Fixture()
            f.backend.beforeWrite = { value in
                if value == LidBrightnessController.dimmedBrightness { f.backend.lid = false }
            }
            f.closeAndDim()
            expect(f.backend.writes.count == 2 && near(f.backend.value, 0.75), "An opening concurrent with the hardware write is immediately restored")
            expect(!f.hasJournal && !f.controller.hasPendingRestoration, "Immediate open rollback leaves no stale ownership")
            f.backend.beforeWrite = nil
        }
    }
}
