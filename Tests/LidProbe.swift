// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import Foundation
import IOKit
import Darwin

@main
struct LidProbe {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { exit(2) }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let log = directory.appendingPathComponent("samples.jsonl")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        try Data(String(getpid()).utf8).write(to: directory.appendingPathComponent("probe.pid"), options: .atomic)
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ratio = Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
        let limit = Date().addingTimeInterval(45 * 60)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        while Date() < limit && !FileManager.default.fileExists(atPath: directory.appendingPathComponent("stop").path) {
            var entry: [String: Any] = ["time": formatter.string(from: Date()), "unix": Date().timeIntervalSince1970,
                                         "continuous": Double(mach_continuous_time()) * ratio,
                                         "awakeClock": Double(mach_absolute_time()) * ratio]
            let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
            if root != IO_OBJECT_NULL {
                for (key, output) in [("AppleClamshellState", "lidClosed"), ("SleepDisabled", "sleepDisabled")] {
                    if let value = IORegistryEntryCreateCFProperty(root, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber {
                        entry[output] = value.boolValue
                    }
                }
                IOObjectRelease(root)
            }
            entry["phase"] = (try? String(contentsOf: directory.appendingPathComponent("phase.txt"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "baseline"
            var data = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
            data.append(0x0a)
            try handle.write(contentsOf: data)
            Thread.sleep(forTimeInterval: 1)
        }
    }
}
