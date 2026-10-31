// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import Foundation
import IOKit
import IOKit.ps

struct HelperStatus: Decodable {
    let version: Int
    let enabled: Bool
    let sessionID: String?
    let ownerUID: UInt32?
    let expiresAt: Double?
    let lastRequestID: String?
    let reason: String
    let message: String
    let updatedAt: Double
    let helperVersion: String

    var isFresh: Bool { abs(Date().timeIntervalSince1970 - updatedAt) < 12 }
}

struct PowerRequest: Encodable {
    let id: String
    let command: String
    let sessionID: String
    let pid: Int32
    let durationSeconds: Int
    let acOnly: Bool
}

struct BatteryReading {
    var percentage: Int?
    var onAC = true

    static func current() -> BatteryReading {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return BatteryReading() }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        var reading = BatteryReading(onAC: providing == kIOPSACPowerValue)
        for source in sources {
            guard let data = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  data[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let capacity = data[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = data[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            reading.percentage = capacity * 100 / maximum
            break
        }
        return reading
    }
}

enum ClientError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

enum PowerClient {
    static let helperVersion = "1.1.1"
    static let installedHelper = "/Library/PrivilegedHelperTools/com.yeonza.LidKeeper.helper"
    static let statusURL = URL(fileURLWithPath: "/Library/Application Support/LidKeeper/status.json")
    static let ipcURL = URL(fileURLWithPath: "/var/run/LidKeeper/\(getuid())", isDirectory: true)

    static func status() -> HelperStatus? {
        guard let data = try? Data(contentsOf: statusURL) else { return nil }
        return try? JSONDecoder().decode(HelperStatus.self, from: data)
    }

    /// Read the kernel's effective setting; a successful pmset exit alone is insufficient.
    static func sleepDisabled() -> Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(root) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(root, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let values = properties?.takeRetainedValue() as? [String: Any] else { return nil }
        // A Mac whose setting has never been changed has no key; the kernel's
        // default is false. Distinguish that from an unreadable registry.
        guard let value = values["SleepDisabled"] else { return false }
        return (value as? NSNumber)?.boolValue
    }

    static var isInstalled: Bool {
        guard let state = status(), state.isFresh, state.helperVersion == helperVersion else { return false }
        return FileManager.default.isWritableFile(atPath: ipcURL.path)
    }

    static func writeHeartbeat(sessionID: String) throws {
        try write(["sessionID": sessionID], name: "heartbeat.json")
    }

    static func writeRequest(command: String, sessionID: String, seconds: Int, acOnly: Bool) throws -> String {
        let id = UUID().uuidString
        let request = PowerRequest(id: id, command: command, sessionID: sessionID,
                                   pid: getpid(), durationSeconds: seconds, acOnly: acOnly)
        try write(request, name: "request.json")
        return id
    }

    private static func write<T: Encodable>(_ value: T, name: String) throws {
        let data = try JSONEncoder().encode(value)
        // Atomic replacement ensures the root helper can never read a partial request.
        let destination = ipcURL.appendingPathComponent(name)
        try data.write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }

    static func clearHeartbeat() {
        try? FileManager.default.removeItem(at: ipcURL.appendingPathComponent("heartbeat.json"))
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptQuote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r") + "\""
    }

    static func authorizeInstall() async throws {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchServices/com.yeonza.LidKeeper.helper")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw ClientError.message("应用文件不完整，请重新解压安装包。")
        }
        try await authorize(command: "\(shellQuote(helper.path)) install \(getuid())")
        for _ in 0..<40 {
            if isInstalled { return }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw ClientError.message("电源服务未能启动，请稍后重试。")
    }

    static func authorizeUninstall() async throws {
        guard FileManager.default.isExecutableFile(atPath: installedHelper) else { return }
        try await authorize(command: "\(shellQuote(installedHelper)) uninstall")
    }

    private static func authorize(command: String) async throws {
        let script = "do shell script \(appleScriptQuote(command)) with administrator privileges"
        let result = try await Task.detached(priority: .userInitiated) {
            try run(executable: "/usr/bin/osascript", arguments: ["-e", script])
        }.value
        guard result.code == 0 else {
            if result.output.contains("-128") {
                throw ClientError.message("已取消授权，休眠设置没有改变。")
            }
            throw ClientError.message("电源服务操作未完成。\n\(result.output.prefix(500))")
        }
    }

    static func run(executable: String, arguments: [String]) throws -> (code: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
