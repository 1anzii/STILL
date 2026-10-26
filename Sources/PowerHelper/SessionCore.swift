// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import Foundation

struct ControlRequest: Codable {
    let id: String
    let command: String
    let sessionID: String
    let pid: Int32
    let durationSeconds: Int
    let acOnly: Bool

    func validate() throws {
        guard UUID(uuidString: id) != nil, UUID(uuidString: sessionID) != nil,
              ["start", "stop"].contains(command), pid > 1,
              (60...86_400).contains(durationSeconds) else {
            throw HelperError.invalidRequest
        }
    }
}

struct Heartbeat: Codable { let sessionID: String }

struct OwnedSession: Codable {
    let sessionID: String
    let ownerUID: UInt32
    let pid: Int32
    let expiresAt: Double
    let durationSeconds: Int
    let acOnly: Bool
}

struct HelperStatus: Codable {
    var version = 1
    var helperVersion = "1.1.0"
    var enabled = false
    var sessionID: String?
    var ownerUID: UInt32?
    var expiresAt: Double?
    var lastRequestID: String?
    var reason = "ready"
    var message = "已恢复正常休眠。"
    var updatedAt: Double = Date().timeIntervalSince1970
}

struct PowerHealth {
    var onAC: Bool
    var batteryPercent: Int?
    var thermalSerious: Bool
}

enum HelperError: Error, CustomStringConvertible {
    case invalidRequest, unsafeFile(String), system(String), alreadyDisabled, busy, rootRequired
    var description: String {
        switch self {
        case .invalidRequest: return "请求格式不正确。"
        case .unsafeFile(let name): return "文件权限不安全：\(name)"
        case .system(let message): return message
        case .alreadyDisabled: return "其他程序已关闭系统休眠，请先在原程序中恢复。"
        case .busy: return "已有保持唤醒会话，请先结束该会话。"
        case .rootRequired: return "此操作需要管理员授权。"
        }
    }
}

protocol PowerBackend: AnyObject {
    func sleepDisabled() throws -> Bool
    func setSleepDisabled(_ disabled: Bool) throws
    func health() throws -> PowerHealth
    func processBelongsToUser(_ pid: Int32, uid: UInt32) -> Bool
}

protocol SessionStore: AnyObject {
    func loadSession() throws -> OwnedSession?
    func saveSession(_ value: OwnedSession) throws
    func clearSession() throws
    func saveStatus(_ value: HelperStatus) throws
}

/// All methods are called under the daemon's root-owned interprocess lock.
/// A durable ownership record is committed *before* changing pmset; it remains
/// until restoration has been read back successfully.
final class SessionController {
    let backend: PowerBackend
    let store: SessionStore
    private(set) var session: OwnedSession?
    private(set) var status = HelperStatus()
    private var deadline = 0.0
    private var lastHeartbeat = 0.0
    private var heartbeatRevision: Double?
    private var mustRestore = false

    init(backend: PowerBackend, store: SessionStore) {
        self.backend = backend
        self.store = store
    }

    func recoverOnLaunch() throws {
        session = try store.loadSession()
        if session != nil {
            mustRestore = true
            try restore(reason: "recovered", message: "已从上次中断恢复正常休眠。")
        } else {
            try publish(reason: "ready", message: "可以开始保持唤醒。")
        }
    }

    func process(_ request: ControlRequest, uid: UInt32, now: Double, monotonic: Double,
                 heartbeat: (Heartbeat, Double)?) throws {
        try request.validate()
        status.lastRequestID = request.id
        if request.command == "stop" {
            guard let current = session else {
                try publish(reason: "stopped", message: "已恢复正常休眠。")
                return
            }
            guard current.ownerUID == uid, current.sessionID == request.sessionID else {
                try publish(reason: "not_owner", message: "当前会话属于其他用户或其他窗口。")
                return
            }
            try restore(reason: "stopped", message: "已恢复正常休眠。")
            return
        }

        guard session == nil else {
            try publish(reason: "busy", message: "已有保持唤醒会话，请先结束。")
            return
        }
        guard try !backend.sleepDisabled() else {
            try publish(reason: "external_override", message: HelperError.alreadyDisabled.description)
            return
        }
        guard backend.processBelongsToUser(request.pid, uid: uid),
              let heartbeat, heartbeat.0.sessionID == request.sessionID,
              now - heartbeat.1 >= -5, now - heartbeat.1 <= 15 else {
            try publish(reason: "client_unavailable", message: "未收到应用心跳，请重新打开应用。")
            return
        }
        let health = try backend.health()
        if let reason = safetyReason(health, acOnly: request.acOnly) {
            try publish(reason: reason.0, message: reason.1)
            return
        }
        let owned = OwnedSession(sessionID: request.sessionID, ownerUID: uid, pid: request.pid,
                                 expiresAt: now + Double(request.durationSeconds),
                                 durationSeconds: request.durationSeconds, acOnly: request.acOnly)
        try store.saveSession(owned)
        session = owned
        deadline = monotonic + Double(request.durationSeconds)
        lastHeartbeat = monotonic
        heartbeatRevision = heartbeat.1
        do {
            try backend.setSleepDisabled(true)
            guard try backend.sleepDisabled() else { throw HelperError.system("系统未启用保持唤醒。") }
            try publish(reason: "active", message: "保持唤醒中，合盖后仍继续运行。")
        } catch {
            mustRestore = true
            try restore(reason: "start_failed", message: "启动失败，已恢复正常休眠。")
        }
    }

    func tick(now: Double, monotonic: Double, heartbeat: (Heartbeat, Double)?) throws {
        guard let current = session else { return }
        if mustRestore {
            try restore(reason: "recovered", message: "已恢复正常休眠。")
            return
        }
        if monotonic >= deadline {
            try restore(reason: "expired", message: "设定时间已到，已恢复正常休眠。")
            return
        }
        guard backend.processBelongsToUser(current.pid, uid: current.ownerUID) else {
            try restore(reason: "app_closed", message: "应用已退出，已恢复正常休眠。")
            return
        }
        if let heartbeat, heartbeat.0.sessionID == current.sessionID,
           now - heartbeat.1 >= -5, now - heartbeat.1 <= 15,
           heartbeat.1 != heartbeatRevision {
            heartbeatRevision = heartbeat.1
            lastHeartbeat = monotonic
        }
        if monotonic - lastHeartbeat >= 15 {
            try restore(reason: "heartbeat_lost", message: "应用连接中断，已恢复正常休眠。")
            return
        }
        do {
            if let reason = safetyReason(try backend.health(), acOnly: current.acOnly) {
                try restore(reason: reason.0, message: reason.1)
                return
            }
            if try !backend.sleepDisabled() {
                try store.clearSession()
                session = nil
                try publish(reason: "external_change", message: "系统设置已被其他程序更改，保持唤醒已结束。")
            }
        } catch {
            try restore(reason: "monitor_failed", message: "无法确认电源状态，已恢复正常休眠。")
        }
    }

    func restore(reason: String, message: String) throws {
        guard session != nil else { return }
        mustRestore = true
        do {
            try backend.setSleepDisabled(false)
            guard try !backend.sleepDisabled() else { throw HelperError.system("系统仍禁止休眠。") }
            try store.clearSession()
            session = nil
            mustRestore = false
            try publish(reason: reason, message: message)
        } catch {
            try? publish(reason: "restore_failed", message: "恢复休眠尚未成功，后台正在重试。请保持通风。")
            throw error
        }
    }

    func refreshStatus() throws {
        status.updatedAt = Date().timeIntervalSince1970
        try store.saveStatus(status)
    }

    func reportRequestFailure(id: String, error: Error) throws {
        status.lastRequestID = id
        if session == nil {
            status.reason = "request_failed"
            status.message = "请求未能完成：\(error)"
        }
        try refreshStatus()
    }

    private func safetyReason(_ health: PowerHealth, acOnly: Bool) -> (String, String)? {
        if health.thermalSerious { return ("thermal", "设备温度偏高，已恢复正常休眠。") }
        if acOnly && !health.onAC { return ("power_disconnected", "电源已断开，已恢复正常休眠。") }
        if !health.onAC && health.batteryPercent == nil {
            return ("battery_unknown", "无法读取电池电量，已恢复正常休眠。")
        }
        return nil
    }

    private func publish(reason: String, message: String) throws {
        status.enabled = session != nil && !mustRestore
        status.sessionID = session?.sessionID
        status.ownerUID = session?.ownerUID
        status.expiresAt = session?.expiresAt
        status.reason = reason
        status.message = message
        status.updatedAt = Date().timeIntervalSince1970
        try store.saveStatus(status)
    }
}
