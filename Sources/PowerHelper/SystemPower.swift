// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import Foundation
import Darwin
import IOKit
import IOKit.ps

struct CommandFailure: Error, CustomStringConvertible {
    let status: Int32
    var description: String { "系统命令未能完成（\(status)）。" }
}

enum FixedCommand {
    /// Only fixed system executables are invoked. There is no shell interpreter.
    static func run(_ executable: String, _ arguments: [String], timeout: Double = 8) throws -> String {
        try autoreleasepool {
            guard ["/usr/bin/pmset", "/bin/launchctl"].contains(executable) else { throw HelperError.invalidRequest }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = arguments
            task.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C", "LC_ALL": "C", "HOME": "/var/root"]
            let output = Pipe()
            // The daemon has no application run loop to drain autoreleased
            // FileHandles. Close both ends on every exit, including run errors.
            defer {
                try? output.fileHandleForReading.close()
                try? output.fileHandleForWriting.close()
            }
            task.standardOutput = output
            task.standardError = output
            try task.run()
            let until = monotonicSeconds() + timeout
            while task.isRunning && monotonicSeconds() < until { usleep(50_000) }
            if task.isRunning {
                task.terminate()
                usleep(200_000)
                if task.isRunning { _ = kill(task.processIdentifier, SIGKILL) }
                task.waitUntilExit()
                throw HelperError.system("系统电源命令超时。")
            }
            task.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            guard task.terminationStatus == 0 else { throw CommandFailure(status: task.terminationStatus) }
            return String(data: data, encoding: .utf8) ?? ""
        }
    }
}

func monotonicSeconds() -> Double {
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    return Double(mach_continuous_time()) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
}

final class SystemPowerBackend: PowerBackend {
    static func parseSleepDisabled(_ output: String) -> Bool? {
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if fields.count == 2 && fields[0] == "SleepDisabled" {
                if fields[1] == "0" { return false }
                if fields[1] == "1" { return true }
            }
        }
        return nil
    }

    private func kernelSleepDisabled(allowDefault: Bool = false) -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let values = properties?.takeRetainedValue() as? [String: Any] else { return nil }
        guard let property = values["SleepDisabled"] else { return allowDefault ? false : nil }
        guard let number = property as? NSNumber else { return nil }
        return number.boolValue
    }

    func sleepDisabled() throws -> Bool {
        let output = try FixedCommand.run("/usr/bin/pmset", ["-g"], timeout: 2)
        guard let value = Self.parseSleepDisabled(output) else {
            if !output.contains("SleepDisabled"),
               let kernel = kernelSleepDisabled(allowDefault: true), !kernel { return false }
            throw HelperError.system("此系统未提供可确认的 SleepDisabled 状态。")
        }
        return value
    }

    func setSleepDisabled(_ disabled: Bool) throws {
        // Apple's pmset code can print an error and return exit status 0.
        // Read preferences back AND wait for powerd's kernel update.
        var commandError: Error?
        do { _ = try FixedCommand.run("/usr/bin/pmset", ["-a", "disablesleep", disabled ? "1" : "0"], timeout: 5) }
        catch { commandError = error }
        let readbackDeadline = monotonicSeconds() + 3
        while monotonicSeconds() < readbackDeadline {
            if let preference = try? sleepDisabled(), preference == disabled,
               let kernel = kernelSleepDisabled(), kernel == disabled { return }
            usleep(200_000)
        }
        throw commandError ?? HelperError.system("系统未确认电源设置已生效。")
    }

    func health() throws -> PowerHealth {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            throw HelperError.system("无法读取电源状态。")
        }
        let sourceType = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let onAC = sourceType == kIOPSACPowerValue
        var level: Int?
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            level = max(0, min(100, Int(Double(current) * 100.0 / Double(maximum))))
        }
        return PowerHealth(onAC: onAC, batteryPercent: level,
                           thermalSerious: ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue)
    }

    func processBelongsToUser(_ pid: Int32, uid: UInt32) -> Bool {
        var info = proc_bsdinfo()
        let expected = Int32(MemoryLayout<proc_bsdinfo>.size)
        let actual = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expected)
        return actual == expected && info.pbi_uid == uid && info.pbi_status != UInt32(SZOMB)
    }
}
