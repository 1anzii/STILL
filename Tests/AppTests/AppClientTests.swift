// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import Foundation
import Darwin

@main
struct AppClientTests {
    static func main() throws {
        var passed = 0
        let samples = ["plain", "带空格的 路径", "a'b\"c", "$HOME $(uname) `uname`", "line\none\ttwo", "back\\slash"]
        for sample in samples {
            let result = try PowerClient.run(executable: "/bin/sh", arguments: ["-c", "printf %s " + PowerClient.shellQuote(sample)])
            precondition(result.code == 0 && result.output == sample, "Shell argument escaping failed")
            let script = "return " + PowerClient.appleScriptQuote(sample)
            let appleResult = try PowerClient.run(executable: "/usr/bin/osascript", arguments: ["-e", script])
            precondition(appleResult.code == 0 && appleResult.output == sample + "\n", "AppleScript escaping failed: \(sample)")
            passed += 2
        }
        let request = PowerRequest(id: UUID().uuidString, command: "start", sessionID: UUID().uuidString,
                                   pid: getpid(), durationSeconds: 3600, acOnly: true)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        precondition(json["acOnly"] as? Bool == true && json["durationSeconds"] as? Int == 3600)
        passed += 1
        precondition(json["batteryFloor"] == nil, "Requests must not impose a minimum battery level")
        passed += 1
        let payload: [String: Any] = ["version": 1, "enabled": false, "reason": "ready", "message": "准备就绪", "updatedAt": Date().timeIntervalSince1970, "helperVersion": PowerClient.helperVersion]
        let state = try JSONDecoder().decode(HelperStatus.self, from: JSONSerialization.data(withJSONObject: payload))
        precondition(state.isFresh && state.sessionID == nil && state.ownerUID == nil)
        passed += 1
        let stalePayload = payload.merging(["updatedAt": Date().timeIntervalSince1970 - 20]) { _, new in new }
        let stale = try JSONDecoder().decode(HelperStatus.self, from: JSONSerialization.data(withJSONObject: stalePayload))
        precondition(!stale.isFresh)
        passed += 1
        // Read-only smoke check; never installs the service or changes pmset.
        precondition(PowerClient.sleepDisabled() != nil, "Unable to read kernel sleep state")
        passed += 1
        print("App client: \(passed) checks passed (no administrator actions).")
    }
}
