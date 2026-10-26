// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import AppKit
import Combine
import ServiceManagement

@MainActor
final class SleepModel: ObservableObject {
    @Published private(set) var isAwake = false
    @Published private(set) var recovering = false
    @Published private(set) var systemDisabled: Bool?
    @Published private(set) var busy = false
    @Published private(set) var busyText = ""
    @Published private(set) var helperReady = false
    @Published private(set) var remaining = ""
    @Published private(set) var battery = BatteryReading()
    @Published private(set) var notice: String?
    @Published var error: String?
    @Published var duration = UserDefaults.standard.object(forKey: "duration") as? Int ?? 3600 {
        didSet { UserDefaults.standard.set(duration, forKey: "duration") }
    }
    @Published var acOnly = UserDefaults.standard.object(forKey: "acOnly") as? Bool ?? true {
        didSet { UserDefaults.standard.set(acOnly, forKey: "acOnly") }
    }
    @Published private(set) var loginEnabled = false

    var didChange: (() -> Void)?
    private var sessionID: String?
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var renewLease = false

    var externallyDisabled: Bool { systemDisabled == true && !isAwake && !busy && !recovering }
    var title: String {
        if busy { return busyText }
        if recovering { return "正在恢复休眠" }
        if isAwake { return "合盖保持运行" }
        if externallyDisabled { return "系统已暂停休眠" }
        if systemDisabled == nil { return "无法确认休眠状态" }
        return "正常休眠"
    }
    var subtitle: String {
        if recovering { return "正在重试恢复，请勿放入包内" }
        if isAwake { return "保持运行中 · \(remaining)后恢复" }
        if externallyDisabled { return "另一个程序或系统设置正在阻止休眠" }
        if systemDisabled == nil { return "暂时无法读取电源状态，请稍后重试" }
        return "遵循 macOS 与外接显示器的休眠规则"
    }
    var powerDescription: String {
        let label = battery.onAC ? "已连接电源" : "使用电池"
        return battery.percentage.map { "\(label) · \($0)%" } ?? label
    }

    init() {
        refresh()
        loginEnabled = SMAppService.mainApp.status == .enabled
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func tick() {
        if renewLease, let sessionID {
            do { try PowerClient.writeHeartbeat(sessionID: sessionID) }
            catch { self.error = "无法维持与后台服务的连接。后台会尝试恢复休眠，请查看状态。" }
        }
        refresh()
    }

    func refresh() {
        battery = BatteryReading.current()
        systemDisabled = PowerClient.sleepDisabled()
        let state = PowerClient.status()
        helperReady = PowerClient.isInstalled
        let matches = state?.sessionID == sessionID && sessionID != nil && state?.ownerUID == getuid()
        let active = matches && state?.enabled == true && state?.isFresh == true && systemDisabled == true && renewLease
        if let state, matches, let deadline = state.expiresAt {
            let seconds = max(0, Int(ceil(deadline - Date().timeIntervalSince1970)))
            remaining = seconds >= 3600 ? "\(seconds / 3600)小时\((seconds % 3600) / 60)分" : "\(max(1, (seconds + 59) / 60))分钟"
        }
        if !busy, sessionID != nil, !active {
            if let state, state.isFresh,
               (systemDisabled == false && !state.enabled || state.sessionID != sessionID) {
                finishSession()
                notice = state.message
            } else {
                recovering = true
                renewLease = false
                PowerClient.clearHeartbeat()
                notice = "正在等待电源服务恢复，请暂勿将电脑放入包内。"
            }
        }
        if isAwake != active { isAwake = active }
        didChange?()
    }

    func toggle() {
        guard !busy else { return }
        Task {
            if isAwake || sessionID != nil { _ = await stop() }
            else { await start() }
        }
    }

    func setRunning(_ running: Bool) {
        Task {
            let state = RunSwitchState(busy: busy, recovering: recovering,
                                       hasSession: hasSession, isAwake: isAwake,
                                       systemDisabled: systemDisabled)
            guard state.accepts(running) else { return }
            if running { await start() }
            else { _ = await stop() }
        }
    }

    private func start() async {
        busy = true
        busyText = PowerClient.isInstalled ? "正在开启…" : "等待管理员授权…"
        notice = nil
        defer { busy = false; refresh() }
        do {
            guard PowerClient.sleepDisabled() == false else {
                throw ClientError.message("当前系统休眠已被其他设置暂停，或无法读取状态。请先关闭其他防休眠工具，再重试。")
            }
            let power = BatteryReading.current()
            guard !acOnly || power.onAC else {
                throw ClientError.message("请先连接电源，或在设置中关闭“仅接电源时运行”。")
            }
            if !PowerClient.isInstalled { try await PowerClient.authorizeInstall() }
            busyText = "正在开启…"
            let token = UUID().uuidString
            sessionID = token
            renewLease = true
            recovering = false
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                             reason: "维持 STILL 会话心跳")
            try PowerClient.writeHeartbeat(sessionID: token)
            let request = try PowerClient.writeRequest(command: "start", sessionID: token, seconds: duration, acOnly: acOnly)
            let result = try await awaitResponse(id: request)
            guard result.enabled, result.sessionID == token, PowerClient.sleepDisabled() == true else {
                throw ClientError.message(result.message)
            }
            isAwake = true
        } catch {
            // Removing the lease also covers the race where the daemon started
            // the session but its response could not be read by this process.
            if sessionID != nil, PowerClient.sleepDisabled() != false {
                renewLease = false
                recovering = true
                PowerClient.clearHeartbeat()
            } else { finishSession() }
            self.error = error.localizedDescription
        }
    }

    @discardableResult
    func stop() async -> Bool {
        guard let token = sessionID else { return true }
        busy = true
        busyText = "正在恢复休眠…"
        defer { busy = false; refresh() }
        do {
            let request = try PowerClient.writeRequest(command: "stop", sessionID: token, seconds: duration, acOnly: acOnly)
            let result = try await awaitResponse(id: request)
            if result.sessionID != token, result.reason != "restore_failed" {
                finishSession()
                isAwake = false
                notice = PowerClient.sleepDisabled() == false ? "已恢复正常休眠" : "本次会话已结束，其他设置仍在阻止休眠。"
                return true
            }
            guard !result.enabled, PowerClient.sleepDisabled() == false else {
                throw ClientError.message("尚未确认休眠恢复。\(result.message)")
            }
            finishSession()
            isAwake = false
            notice = "已恢复正常休眠"
            return true
        } catch {
            PowerClient.clearHeartbeat()
            self.error = "恢复尚未确认：\(error.localizedDescription)\n后台服务会重试，请保持应用打开并查看状态。"
            // Do not renew a failed stop's lease on the next timer tick.
            renewLease = false
            recovering = true
            return false
        }
    }

    private func awaitResponse(id: String) async throws -> HelperStatus {
        for _ in 0..<50 {
            if let state = PowerClient.status(), state.isFresh, state.lastRequestID == id { return state }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw ClientError.message("电源服务响应超时。请稍后重试。")
    }

    private func endActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    private func finishSession() {
        if sessionID != nil { PowerClient.clearHeartbeat() }
        sessionID = nil
        renewLease = false
        recovering = false
        endActivity()
    }

    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if enabled && !loginEnabled {
                notice = "请在系统设置 → 通用 → 登录项中允许 STILL。"
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch { self.error = "无法修改登录启动：\(error.localizedDescription)" }
    }

    /// Service upgrades can be authorized without starting a wake session.
    func prepareHelper() {
        Task {
            guard !busy, !hasSession, !recovering, PowerClient.sleepDisabled() == false else { return }
            busy = true
            busyText = "正在更新电源服务…"
            notice = nil
            defer { busy = false; refresh() }
            do {
                try await PowerClient.authorizeInstall()
                notice = "电源服务已就绪，可以开启保持运行。"
            } catch { self.error = error.localizedDescription }
        }
    }

    func uninstallHelper() {
        guard !busy, !hasSession else { return }
        Task {
            busy = true
            busyText = "正在卸载电源服务…"
            defer { busy = false; refresh() }
            do {
                try await PowerClient.authorizeUninstall()
                notice = "电源服务已卸载。再次开启时会重新请求授权。"
            } catch { self.error = error.localizedDescription }
        }
    }

    func quit() {
        guard !busy else { return }
        Task {
            if sessionID != nil, !(await stop()) { return }
            NSApp.terminate(nil)
        }
    }

    var hasSession: Bool { sessionID != nil }
}
