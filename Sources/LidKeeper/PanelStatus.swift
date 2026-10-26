// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import Foundation

/// Presentation only: confirmed switch state drives the LED; display strings
/// cannot turn an unconfirmed or external sleep override into our active state.
struct PanelStatus {
    enum LED: Equatable { case off, green, amber }

    let led: LED
    let title: String
    let detail: String?
    let notice: String?

    init(state: RunSwitchState, busyText: String = "", remaining: String = "", notice: String? = nil) {
        self.notice = Self.displayNotice(notice, state: state)
        switch state.position {
        case true?: led = .green
        case false?: led = .off
        case nil: led = .amber
        }

        if state.busy {
            if let copy = Self.busyMessages[busyText] {
                title = copy.title
                detail = copy.detail
            } else {
                title = "正在处理"
                detail = Self.nonempty(busyText)
            }
        } else if state.recovering {
            title = "正在恢复休眠"
            detail = "请保持通风，勿放入包内"
        } else if state.position == true {
            title = "合盖保持运行"
            detail = Self.remainingText(remaining).map { "剩余\($0) · 勿放入包内" } ?? "勿放入包内"
        } else if state.position == false {
            // This confirms sleep is allowed, not that the computer is asleep.
            title = "正常休眠"
            detail = nil
        } else if state.systemDisabled == nil {
            title = "无法确认状态"
            detail = "暂时无法读取休眠状态"
        } else if state.systemDisabled == true && !state.hasSession {
            title = "其他程序阻止休眠"
            detail = "请先在原程序中恢复休眠"
        } else {
            title = "正在确认状态"
            detail = "请稍候，等待系统确认"
        }
    }

    /// Only known messages are shortened. Unknown text is returned verbatim,
    /// including new helper errors, so a generic status never erases diagnostics.
    private static func displayNotice(_ value: String?, state: RunSwitchState) -> String? {
        guard let value = nonempty(value) else { return nil }
        // Suppress only redundant, reason-free confirmations whose state is
        // independently confirmed. Safety causes and pending recovery stay visible.
        if state.position == false && ["已恢复正常休眠", "已恢复正常休眠。", "可以开始保持唤醒。"].contains(value) {
            return nil
        }
        if state.position == true && value == "保持唤醒中，合盖后仍继续运行。" { return nil }
        return noticeMessages[value] ?? value
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    /// SleepModel emits either H小时M分 or M分钟. Anything else is preserved;
    /// partial replacements must not silently misinterpret a future format.
    private static func remainingText(_ value: String) -> String? {
        guard nonempty(value) != nil else { return nil }
        if value.hasSuffix("分钟"), let minutes = unsignedInteger(value.dropLast(2)) {
            return "\(minutes)分钟"
        }
        if let separator = value.range(of: "小时"), value.hasSuffix("分"),
           let hours = unsignedInteger(value[..<separator.lowerBound]),
           let minutes = unsignedInteger(value[separator.upperBound...].dropLast()), minutes < 60 {
            return minutes == 0 ? "\(hours)小时" : "\(hours)小时\(minutes)分"
        }
        return value
    }

    private static func unsignedInteger(_ value: Substring) -> Int? {
        guard !value.isEmpty, value.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
        return Int(value)
    }

    private static let busyMessages: [String: (title: String, detail: String)] = [
        "正在开启…": ("正在开启", "等待系统确认"),
        "等待管理员授权…": ("等待授权", "请在系统弹窗中授权"),
        "正在恢复休眠…": ("正在恢复休眠", "请稍候，勿放入包内"),
        "正在更新电源服务…": ("正在更新服务", "请在系统弹窗中授权"),
        "正在卸载电源服务…": ("正在卸载服务", "请稍候")
    ]

    // Exact strings emitted by SleepModel and current/legacy power helpers.
    // Warnings retain both the reason and any action the user needs to take.
    private static let noticeMessages: [String: String] = [
        "已恢复正常休眠": "已恢复休眠",
        "已恢复正常休眠。": "已恢复休眠",
        "可以开始保持唤醒。": "可以开始保持运行",
        "已从上次中断恢复正常休眠。": "上次运行中断，已恢复休眠",
        "当前会话属于其他用户或其他窗口。": "当前运行属于其他用户或窗口",
        "已有保持唤醒会话，请先结束。": "请先结束当前运行",
        "其他程序已关闭系统休眠，请先在原程序中恢复。": "其他程序禁用了休眠，请在原程序中恢复",
        "未收到应用心跳，请重新打开应用。": "应用连接中断，请重新打开 STILL",
        "保持唤醒中，合盖后仍继续运行。": "合盖后继续运行",
        "启动失败，已恢复正常休眠。": "开启失败，已恢复休眠",
        "设定时间已到，已恢复正常休眠。": "时间已到，已恢复休眠",
        "应用已退出，已恢复正常休眠。": "应用已退出，已恢复休眠",
        "应用连接中断，已恢复正常休眠。": "应用连接中断，已恢复休眠",
        "系统设置已被其他程序更改，保持唤醒已结束。": "其他程序更改了设置，本次运行已结束",
        "无法确认电源状态，已恢复正常休眠。": "无法确认电源状态，已恢复休眠",
        "恢复休眠尚未成功，后台正在重试。请保持通风。": "恢复尚未成功，正在重试。请保持通风",
        "设备温度偏高，已恢复正常休眠。": "温度偏高，已恢复休眠",
        "电源已断开，已恢复正常休眠。": "电源已断开，已恢复休眠",
        "无法读取电池电量，已恢复正常休眠。": "无法读取电量，已恢复休眠",
        "电池电量低于保护阈值，已恢复正常休眠。": "电量不高于 15%，已恢复休眠",
        "后台服务已退出，已恢复正常休眠。": "后台服务已退出，已恢复休眠",
        "恢复记录无法读取，请使用卸载助手恢复休眠。": "恢复记录无法读取，请在“使用说明与关于”的“故障恢复与卸载”中查看恢复方法。",
        "正在等待电源服务恢复，请暂勿将电脑放入包内。": "正在恢复休眠，勿放入包内",
        "本次会话已结束，其他设置仍在阻止休眠。": "本次运行已结束，其他设置仍阻止休眠",
        "请在系统设置 → 通用 → 登录项中允许 STILL。": "请在系统设置的“通用 → 登录项”中允许 STILL",
        "电源服务已卸载。再次开启时会重新请求授权。": "服务已卸载，再次开启时需要授权"
    ]
}
