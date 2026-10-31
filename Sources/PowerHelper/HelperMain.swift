// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import Foundation
import Darwin

private var stopping: sig_atomic_t = 0

struct InstallationConfig: Codable { var allowedUIDs: [UInt32] }

@main
struct HelperMain {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments == ["status"] {
                let url = URL(fileURLWithPath: HelperPaths.state + "/status.json")
                FileHandle.standardOutput.write(try Data(contentsOf: url))
                print("")
                return
            }
            if arguments == ["check"] {
                let backend = SystemPowerBackend()
                let health = try backend.health()
                let result: [String: Any] = ["sleepDisabled": try backend.sleepDisabled(), "onAC": health.onAC,
                                             "batteryPercent": health.batteryPercent.map { $0 as Any } ?? NSNull(),
                                             "thermalSerious": health.thermalSerious]
                FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
                print("")
                return
            }
            guard geteuid() == 0 else { throw HelperError.rootRequired }
            umask(0o077)
            if arguments.count == 2, arguments[0] == "install", let uid = UInt32(arguments[1]), uid >= 501 {
                try install(uid: uid)
            } else if arguments == ["daemon"] {
                try runDaemon()
            } else if arguments == ["uninstall"] {
                try uninstall()
            } else {
                throw HelperError.system("用法：helper install <uid> | daemon | status | check | uninstall")
            }
        } catch {
            FileHandle.standardError.write(Data("LidKeeper: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func prepareDirectories() throws {
        try SecureFiles.ensureDirectory(HelperPaths.state, owner: 0, mode: 0o755)
        try SecureFiles.ensureDirectory(HelperPaths.runtime, owner: 0, mode: 0o755)
    }

    private static func stopService() throws {
        let target = "system/" + HelperPaths.label
        do { _ = try FixedCommand.run("/bin/launchctl", ["print", target]) }
        catch let error as CommandFailure where error.status == 113 { return }
        _ = try FixedCommand.run("/bin/launchctl", ["bootout", target])
        do {
            _ = try FixedCommand.run("/bin/launchctl", ["print", target])
            throw HelperError.system("后台服务尚未退出，操作已取消。")
        } catch let error as CommandFailure where error.status == 113 { return }
    }

    private static func config(store: FileSessionStore) throws -> InstallationConfig {
        guard let data = try SecureFiles.read(directory: store.fd, name: "config.json", owner: 0) else {
            return InstallationConfig(allowedUIDs: [])
        }
        let value = try JSONDecoder().decode(InstallationConfig.self, from: data.0)
        guard !value.allowedUIDs.isEmpty, value.allowedUIDs.allSatisfy({ $0 >= 501 }) else {
            throw HelperError.system("助手配置不完整，请重新安装。")
        }
        return value
    }

    private static func install(uid: UInt32) throws {
        guard getpwuid(uid) != nil else { throw HelperError.invalidRequest }
        try prepareDirectories()
        let store = try FileSessionStore()
        let lock = try RootLock(directory: store.fd)
        try lock.acquire()
        defer { lock.release() }
        guard try store.loadSession() == nil else { throw HelperError.busy }
        var configuration = try config(store: store)
        if !configuration.allowedUIDs.contains(uid) { configuration.allowedUIDs.append(uid) }

        // Read this authenticated executable without following a final symlink.
        // Only the installing user or root may own it; group/world write is rejected.
        let sourcePath = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
        let source = open(sourcePath, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard source >= 0 else { throw HelperError.unsafeFile("helper") }
        defer { close(source) }
        var info = stat()
        guard fstat(source, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == uid || info.st_uid == 0, info.st_mode & 0o022 == 0,
              info.st_nlink == 1, info.st_size > 0, info.st_size <= 64 * 1024 * 1024 else {
            throw HelperError.unsafeFile("helper")
        }
        let binary = try FileHandle(fileDescriptor: source, closeOnDealloc: false).read(upToCount: Int(info.st_size) + 1) ?? Data()
        guard binary.count == info.st_size else { throw HelperError.unsafeFile("helper") }

        // Holding the same operation lock as the daemon rules out an enable
        // racing with this update. A loaded daemon has no owned session here.
        try stopService()
        for path in ["/Library/PrivilegedHelperTools", "/Library/LaunchDaemons"] {
            let created = mkdir(path, 0o755) == 0
            if !created && errno != EEXIST { throw HelperError.unsafeFile(path) }
            if created {
                let parent = try SecureFiles.directory(path, owner: 0)
                defer { close(parent) }
                guard fchmod(parent, 0o755) == 0 else { throw HelperError.unsafeFile(path) }
            }
        }
        let helpers = try SecureFiles.directory("/Library/PrivilegedHelperTools", owner: 0)
        defer { close(helpers) }
        try SecureFiles.atomicWrite(binary, directory: helpers, name: HelperPaths.label, mode: 0o755)
        try SecureFiles.atomicWrite(JSONEncoder().encode(configuration), directory: store.fd, name: "config.json", mode: 0o600)
        for enrolled in configuration.allowedUIDs {
            try SecureFiles.ensureDirectory(HelperPaths.runtime + "/\(enrolled)", owner: enrolled, mode: 0o700)
        }
        let plist: [String: Any] = ["Label": HelperPaths.label,
                                  "ProgramArguments": [HelperPaths.executable, "daemon"],
                                  "RunAtLoad": true, "KeepAlive": true, "ThrottleInterval": 5,
                                  "ExitTimeOut": 5, "ProcessType": "Background"]
        let daemons = try SecureFiles.directory("/Library/LaunchDaemons", owner: 0)
        defer { close(daemons) }
        try SecureFiles.atomicWrite(PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0),
                                    directory: daemons, name: HelperPaths.label + ".plist", mode: 0o644)
        // Clear the status before bootstrap so the UI waits for fresh readiness.
        _ = unlinkat(store.fd, "status.json", 0)
        _ = try FixedCommand.run("/bin/launchctl", ["bootstrap", "system", HelperPaths.plist])
        print("Installed")
    }

    private static func readIPC<T: Decodable>(_ type: T.Type, name: String, uid: UInt32) throws -> (T, Double)? {
        let directory = try SecureFiles.directory(HelperPaths.runtime + "/\(uid)", owner: uid, privateMode: true)
        defer { close(directory) }
        guard let value = try SecureFiles.read(directory: directory, name: name, owner: uid) else { return nil }
        return (try JSONDecoder().decode(T.self, from: value.0), value.1)
    }

    private static func runDaemon() throws {
        let launchedAt = Date().timeIntervalSince1970
        try prepareDirectories()
        let store = try FileSessionStore()
        let singleton = try RootLock(directory: store.fd, name: "daemon.lock")
        try singleton.acquire(nonblocking: true)
        let lock = try RootLock(directory: store.fd)
        let controller = SessionController(backend: SystemPowerBackend(), store: store)
        var seen: [UInt32: String] = [:]
        signal(SIGTERM) { _ in stopping = 1 }
        signal(SIGINT) { _ in stopping = 1 }
        try lock.acquire()
        do { try controller.recoverOnLaunch() }
        catch {
            // If ownership could be loaded, retain it and retry restoration.
            // A corrupt root state is surfaced instead of guessing ownership.
            if controller.session == nil {
                var status = HelperStatus()
                status.reason = "recovery_record_error"
                status.message = "恢复记录无法读取，请使用卸载助手恢复休眠。"
                try? store.saveStatus(status)
                lock.release()
                throw error
            }
        }
        lock.release()
        // Root-owned recovery runs before reading any user-controlled IPC path.
        let configuration = try config(store: store)
        guard !configuration.allowedUIDs.isEmpty else { throw HelperError.system("尚未安装助手。") }
        for uid in configuration.allowedUIDs {
            try? SecureFiles.ensureDirectory(HelperPaths.runtime + "/\(uid)", owner: uid, mode: 0o700)
            // Ignore requests that predate this daemon; a new request arriving
            // during startup is preserved instead of getting swallowed.
            if let request = try? readIPC(ControlRequest.self, name: "request.json", uid: uid), request.1 <= launchedAt {
                seen[uid] = request.0.id
            }
        }
        try controller.refreshStatus()
        while true {
            if stopping != 0 && controller.session == nil { return }
            do {
                // Bound Foundation's temporary objects in this long-lived loop.
                // Return a flag so stopping still exits the daemon, not just the pool.
                let shouldStop = try autoreleasepool { () throws -> Bool in
                    try lock.acquire(nonblocking: true)
                    defer { lock.release() }
                    if stopping != 0 {
                        try controller.restore(reason: "service_stopped", message: "后台服务已退出，已恢复正常休眠。")
                        return true
                    }
                    let now = Date().timeIntervalSince1970
                    let monotonic = monotonicSeconds()
                    let heartbeat = controller.session.flatMap {
                        try? readIPC(Heartbeat.self, name: "heartbeat.json", uid: $0.ownerUID)
                    }
                    try controller.tick(now: now, monotonic: monotonic, heartbeat: heartbeat)
                    for uid in configuration.allowedUIDs {
                        guard let (request, modified) = try? readIPC(ControlRequest.self, name: "request.json", uid: uid),
                              request.id != seen[uid] else { continue }
                        seen[uid] = request.id
                        // Requests older than 30 seconds are never activated.
                        guard now - modified >= -5, now - modified <= 30 else { continue }
                        let heartbeat = try? readIPC(Heartbeat.self, name: "heartbeat.json", uid: uid)
                        do { try controller.process(request, uid: uid, now: now, monotonic: monotonic, heartbeat: heartbeat) }
                        catch {
                            try? controller.reportRequestFailure(id: request.id, error: error)
                        }
                    }
                    try controller.refreshStatus()
                    return false
                }
                if shouldStop { return }
            } catch {
                // Keep the durable ownership record and retry at the next tick.
                // No terminal output path is writable by unprivileged users.
            }
            usleep(1_000_000)
        }
    }

    private static func uninstall() throws {
        try prepareDirectories()
        let store = try FileSessionStore()
        let lock = try RootLock(directory: store.fd)
        try lock.acquire()
        defer { lock.release() }
        // A root-owned record (even if corrupted) proves this installation wrote
        // an ownership intent. No record means an external override is untouched.
        if try SecureFiles.read(directory: store.fd, name: "session.json", owner: 0) != nil {
            let backend = SystemPowerBackend()
            try backend.setSleepDisabled(false)
            guard try !backend.sleepDisabled() else { throw HelperError.system("恢复休眠失败，卸载已取消。") }
            try store.clearSession()
        }
        try stopService()
        guard unlink(HelperPaths.plist) == 0 || errno == ENOENT else { throw HelperError.system("无法移除后台服务配置。") }
        guard unlink(HelperPaths.executable) == 0 || errno == ENOENT else { throw HelperError.system("无法移除后台服务。") }
        // Remove only fixed root-owned files. Do not recursively traverse user IPC.
        for name in ["config.json", "status.json"] { _ = unlinkat(store.fd, name, 0) }
        print("Uninstalled; owned sleep override restored")
    }
}
