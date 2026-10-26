// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import Foundation
import Darwin

final class MockPower: PowerBackend {
    var disabled = false
    var commands: [Bool] = []
    var failEnable = false
    var failRestore = false
    var failHealth = false
    var alive = true
    var power = PowerHealth(onAC: true, batteryPercent: 80, thermalSerious: false)
    func sleepDisabled() throws -> Bool { disabled }
    func setSleepDisabled(_ value: Bool) throws {
        commands.append(value)
        if !value && failRestore { throw HelperError.system("mock restore failed") }
        disabled = value
        if value && failEnable { throw HelperError.system("mock enable failed after effect") }
    }
    func health() throws -> PowerHealth {
        if failHealth { throw HelperError.system("mock health failed") }
        return power
    }
    func processBelongsToUser(_ pid: Int32, uid: UInt32) -> Bool { alive }
}

final class MemoryStore: SessionStore {
    var record: OwnedSession?
    var status: HelperStatus?
    var writeFailed = false
    func loadSession() throws -> OwnedSession? { record }
    func saveSession(_ value: OwnedSession) throws {
        if writeFailed { throw HelperError.system("mock persistence failed") }
        record = value
    }
    func clearSession() throws { record = nil }
    func saveStatus(_ value: HelperStatus) throws { status = value }
}

@main
struct HelperTests {
    static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !value() { fatalError("FAILED: \(message)") }
    }
    static func request(_ command: String = "start", session: String = UUID().uuidString, acOnly: Bool = true) -> ControlRequest {
        ControlRequest(id: UUID().uuidString, command: command, sessionID: session, pid: 123,
                       durationSeconds: 60, acOnly: acOnly)
    }
    static func start(_ power: MockPower = MockPower(), store: MemoryStore = MemoryStore(), acOnly: Bool = true) throws -> (SessionController, ControlRequest, MockPower, MemoryStore) {
        let controller = SessionController(backend: power, store: store)
        try controller.recoverOnLaunch()
        let value = request(acOnly: acOnly)
        try controller.process(value, uid: 501, now: 100, monotonic: 1000, heartbeat: (Heartbeat(sessionID: value.sessionID), 100))
        return (controller, value, power, store)
    }
    static func main() throws {
        expect(HelperStatus().helperVersion == "1.1.0", "status identifies helper without battery cutoff")
        do {
            let (c, r, p, s) = try start()
            expect(p.disabled && s.record != nil && c.status.enabled, "enable owns persistent record")
            try c.process(request("stop", session: r.sessionID), uid: 502, now: 101, monotonic: 1001, heartbeat: nil)
            expect(p.disabled && c.status.reason == "not_owner", "other user cannot stop")
            try c.process(request("stop", session: r.sessionID), uid: 501, now: 101, monotonic: 1001, heartbeat: nil)
            expect(!p.disabled && s.record == nil && c.status.reason == "stopped", "stop restores and clears")
        }
        do {
            let p = MockPower(); p.disabled = true
            let (c, _, _, s) = try start(p)
            expect(c.status.reason == "external_override" && p.commands.isEmpty && s.record == nil, "external override is untouched")
        }
        do {
            let p = MockPower(); p.failEnable = true
            let (c, _, _, s) = try start(p)
            expect(!p.disabled && s.record == nil && p.commands == [true, false] && c.status.reason == "start_failed", "partial enable failure rolls back")
        }
        do {
            let p = MockPower(); let s = MemoryStore(); s.writeFailed = true
            do { _ = try start(p, store: s); fatalError("expected persistence failure") } catch {}
            expect(p.commands.isEmpty && !p.disabled, "no mutation before durable write")
        }
        do {
            let (c, _, p, s) = try start(); p.failRestore = true
            do { try c.restore(reason: "stopped", message: "stop"); fatalError("expected restore failure") } catch {}
            expect(p.disabled && s.record != nil && c.status.reason == "restore_failed", "restore failure keeps recovery record")
            p.failRestore = false
            try c.tick(now: 101, monotonic: 1001, heartbeat: nil)
            expect(!p.disabled && s.record == nil, "watchdog retries restore")
        }
        do {
            let (c, r, p, _) = try start()
            try c.tick(now: 114, monotonic: 1014, heartbeat: (Heartbeat(sessionID: r.sessionID), 114))
            expect(p.disabled, "fresh heartbeat keeps session")
            try c.tick(now: 129, monotonic: 1029, heartbeat: (Heartbeat(sessionID: r.sessionID), 114))
            expect(!p.disabled && c.status.reason == "heartbeat_lost", "unchanged heartbeat expires")
        }
        do {
            let (c, r, p, _) = try start()
            try c.tick(now: 102, monotonic: 1015, heartbeat: (Heartbeat(sessionID: UUID().uuidString), 102))
            expect(!p.disabled && c.status.reason == "heartbeat_lost", "wrong-session heartbeat rejected")
            expect(r.sessionID != "", "session identifier present")
        }
        do {
            let (c, r, p, _) = try start()
            try c.tick(now: -5000, monotonic: 1060, heartbeat: (Heartbeat(sessionID: r.sessionID), -5000))
            expect(!p.disabled && c.status.reason == "expired", "wall clock rollback cannot extend deadline")
        }
        do {
            let (c, _, p, _) = try start(); p.alive = false
            try c.tick(now: 101, monotonic: 1001, heartbeat: nil)
            expect(!p.disabled && c.status.reason == "app_closed", "app exit restores immediately")
        }
        for (power, reason) in [
            (PowerHealth(onAC: false, batteryPercent: 80, thermalSerious: false), "power_disconnected"),
            (PowerHealth(onAC: true, batteryPercent: 80, thermalSerious: true), "thermal")
        ] {
            let (c, _, p, _) = try start(); p.power = power
            try c.tick(now: 101, monotonic: 1001, heartbeat: nil)
            expect(!p.disabled && c.status.reason == reason, "safety cutoff \(reason)")
        }
        for percent in [15, 14, 1, 0] {
            let p = MockPower()
            p.power = PowerHealth(onAC: false, batteryPercent: percent, thermalSerious: false)
            let (c, r, _, s) = try start(p, acOnly: false)
            expect(p.disabled && c.status.enabled && s.record != nil && c.status.reason == "active",
                   "battery \(percent)% permits starting")
            try c.tick(now: 114, monotonic: 1014, heartbeat: (Heartbeat(sessionID: r.sessionID), 114))
            expect(p.disabled && c.status.enabled && s.record != nil && p.commands == [true],
                   "battery \(percent)% permits continuing with fresh heartbeat")
        }
        do {
            let p = MockPower()
            p.power = PowerHealth(onAC: false, batteryPercent: 80, thermalSerious: false)
            let (c, r, _, s) = try start(p, acOnly: false)
            for (index, percent) in [16, 15, 14, 1, 0].enumerated() {
                p.power.batteryPercent = percent
                let elapsed = Double(index + 1) * 3
                try c.tick(now: 100 + elapsed, monotonic: 1000 + elapsed,
                           heartbeat: (Heartbeat(sessionID: r.sessionID), 100 + elapsed))
                expect(p.disabled && c.status.enabled && s.record != nil && p.commands == [true],
                       "crossing to \(percent)% does not restore or replace the session")
            }
        }
        do {
            let p = MockPower()
            p.power = PowerHealth(onAC: false, batteryPercent: nil, thermalSerious: false)
            let (c, _, _, s) = try start(p, acOnly: false)
            expect(!p.disabled && s.record == nil && p.commands.isEmpty && c.status.reason == "battery_unknown",
                   "unknown battery still blocks starting on battery")
        }
        do {
            let (c, _, p, s) = try start(acOnly: false)
            p.power = PowerHealth(onAC: false, batteryPercent: nil, thermalSerious: false)
            try c.tick(now: 101, monotonic: 1001, heartbeat: nil)
            expect(!p.disabled && s.record == nil && c.status.reason == "battery_unknown",
                   "unknown battery still restores while on battery")
        }
        do {
            let p = MockPower()
            p.power = PowerHealth(onAC: true, batteryPercent: nil, thermalSerious: false)
            let (c, r, _, s) = try start(p, acOnly: false)
            try c.tick(now: 101, monotonic: 1001, heartbeat: (Heartbeat(sessionID: r.sessionID), 101))
            expect(p.disabled && s.record != nil && c.status.enabled,
                   "AC operation still allows an absent battery reading")
        }
        for (power, acOnly, reason) in [
            (PowerHealth(onAC: false, batteryPercent: 0, thermalSerious: false), true, "power_disconnected"),
            (PowerHealth(onAC: false, batteryPercent: 0, thermalSerious: true), false, "thermal")
        ] {
            let p = MockPower(); p.power = power
            let (c, _, _, s) = try start(p, acOnly: acOnly)
            expect(!p.disabled && s.record == nil && p.commands.isEmpty && c.status.reason == reason,
                   "low battery does not bypass startup protection \(reason)")
            let (active, _, runningPower, runningStore) = try start(acOnly: acOnly)
            runningPower.power = power
            try active.tick(now: 101, monotonic: 1001, heartbeat: nil)
            expect(!runningPower.disabled && runningStore.record == nil && active.status.reason == reason,
                   "low battery does not bypass running protection \(reason)")
        }
        do {
            let (c, _, p, _) = try start(); p.failHealth = true
            try c.tick(now: 101, monotonic: 1001, heartbeat: nil)
            expect(!p.disabled && c.status.reason == "monitor_failed", "health failure restores")
        }
        do {
            let (_, _, p, s) = try start()
            let replacement = SessionController(backend: p, store: s)
            try replacement.recoverOnLaunch()
            expect(!p.disabled && s.record == nil && replacement.status.reason == "recovered", "daemon restart restores recorded ownership")
        }
        do {
            let (c, _, p, s) = try start(); p.disabled = false
            let before = p.commands.count
            try c.tick(now: 101, monotonic: 1001, heartbeat: nil)
            expect(s.record == nil && p.commands.count == before && c.status.reason == "external_change", "external restore ends ownership without rewriting")
        }
        expect(SystemPowerBackend.parseSleepDisabled("System-wide power settings:\n SleepDisabled\t\t0\n") == false, "parse system-only output")
        expect(SystemPowerBackend.parseSleepDisabled(" SleepDisabled 1\n") == true, "parse enabled output")
        expect(SystemPowerBackend.parseSleepDisabled(" SleepDisabled invalid\n") == nil, "invalid value stays unknown")
        expect(SystemPowerBackend.parseSleepDisabled("nothing") == nil, "missing value stays unknown in parser")
        try schemaCompatibilityTests()
        try fileTests()
        print("Helper tests passed: \(checks) checks; no privileged commands executed.")
    }

    static func schemaCompatibilityTests() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for legacy in [false, true] {
            let value = request(acOnly: false)
            var payload = try JSONSerialization.jsonObject(with: encoder.encode(value)) as! [String: Any]
            expect(payload["batteryFloor"] == nil, "new requests omit batteryFloor")
            if legacy { payload["batteryFloor"] = 15 }
            let decoded = try decoder.decode(ControlRequest.self, from: JSONSerialization.data(withJSONObject: payload))
            try decoded.validate()
            expect(decoded.sessionID == value.sessionID && decoded.pid == value.pid && !decoded.acOnly,
                   "\(legacy ? "legacy" : "new") request preserves ownership and AC policy")
            let p = MockPower()
            p.power = PowerHealth(onAC: false, batteryPercent: 0, thermalSerious: false)
            let s = MemoryStore()
            let c = SessionController(backend: p, store: s)
            try c.recoverOnLaunch()
            try c.process(decoded, uid: 501, now: 100, monotonic: 1000,
                          heartbeat: (Heartbeat(sessionID: value.sessionID), 100))
            expect(p.disabled && c.status.enabled && s.record != nil,
                   "\(legacy ? "legacy" : "new") request starts at 0%; old floor has no effect")

            payload["id"] = UUID().uuidString
            payload["command"] = "stop"
            let stop = try decoder.decode(ControlRequest.self, from: JSONSerialization.data(withJSONObject: payload))
            try c.process(stop, uid: 501, now: 101, monotonic: 1001, heartbeat: nil)
            expect(!p.disabled && s.record == nil && c.status.reason == "stopped",
                   "\(legacy ? "legacy" : "new") stop request restores owned session")
        }
        for legacy in [false, true] {
            let (_, original, p, s) = try start(acOnly: false)
            var payload = try JSONSerialization.jsonObject(with: encoder.encode(s.record!)) as! [String: Any]
            expect(payload["batteryFloor"] == nil, "new persisted sessions omit batteryFloor")
            if legacy { payload["batteryFloor"] = 15 }
            let persisted = try decoder.decode(OwnedSession.self, from: JSONSerialization.data(withJSONObject: payload))
            expect(persisted.sessionID == original.sessionID && persisted.ownerUID == 501 && !persisted.acOnly,
                   "\(legacy ? "legacy" : "new") persisted session retains restoration ownership")
            s.record = persisted
            let replacement = SessionController(backend: p, store: s)
            p.failRestore = true
            do { try replacement.recoverOnLaunch(); fatalError("expected restoration failure") } catch {}
            expect(p.disabled && s.record != nil && replacement.status.reason == "restore_failed",
                   "\(legacy ? "legacy" : "new") persisted session survives failed restart restoration")
            p.failRestore = false
            try replacement.tick(now: 101, monotonic: 1001, heartbeat: nil)
            expect(!p.disabled && s.record == nil && replacement.status.reason == "recovered",
                   "\(legacy ? "legacy" : "new") persisted session restores on retry")
        }
    }

    static func fileTests() throws {
        let path = "/private/tmp/LidKeeper-tests-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(atPath: path) }
        let fd = try SecureFiles.directory(path, owner: getuid(), privateMode: true)
        defer { close(fd) }
        try SecureFiles.atomicWrite(Data("safe".utf8), directory: fd, name: "regular", mode: 0o600)
        let regular = try SecureFiles.read(directory: fd, name: "regular", owner: getuid())
        expect(regular?.0 == Data("safe".utf8), "regular owned IPC accepted")
        symlink(path + "/regular", path + "/symlink")
        link(path + "/regular", path + "/hardlink")
        mkfifo(path + "/fifo", 0o600)
        try SecureFiles.atomicWrite(Data(repeating: 1, count: 5000), directory: fd, name: "oversize", mode: 0o600)
        try SecureFiles.atomicWrite(Data("bad".utf8), directory: fd, name: "worldwrite", mode: 0o666)
        for name in ["symlink", "hardlink", "fifo", "oversize", "worldwrite"] {
            var rejected = false
            do { _ = try SecureFiles.read(directory: fd, name: name, owner: getuid()) } catch { rejected = true }
            expect(rejected, "reject unsafe IPC \(name)")
        }
        let missing = try SecureFiles.read(directory: fd, name: "missing", owner: getuid())
        expect(missing == nil, "missing IPC is benign")
    }
}
