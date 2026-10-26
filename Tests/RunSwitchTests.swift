// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

@main
struct RunSwitchTests {
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError("FAILED: \(message)") }
    }

    struct Fixture {
        let name: String
        let hasSession: Bool
        let isAwake: Bool
        let systemDisabled: Bool?
        let position: Bool?
        let start: Bool
        let stop: Bool
    }

    static func main() {
        fullStateTable()
        lifecycleTests()
        panelStatusTests()
        print("Run switch tests passed: \(checks) checks; no UI or power operations.")
    }

    static func fullStateTable() {
        // Explicit expected states distinguish confirmed ownership from a
        // disabled system setting that belongs to another app. The table also
        // includes every inconsistent combination of ownership/awake/kernel.
        let fixtures: [Fixture] = [
            .init(name: "normal idle", hasSession: false, isAwake: false, systemDisabled: false, position: false, start: true, stop: false),
            .init(name: "external disabled", hasSession: false, isAwake: false, systemDisabled: true, position: nil, start: false, stop: false),
            .init(name: "unknown idle", hasSession: false, isAwake: false, systemDisabled: nil, position: nil, start: false, stop: false),
            .init(name: "owned active", hasSession: true, isAwake: true, systemDisabled: true, position: true, start: false, stop: true),
            .init(name: "owned active flag with sleep allowed", hasSession: true, isAwake: true, systemDisabled: false, position: nil, start: false, stop: true),
            .init(name: "owned active flag with unreadable kernel", hasSession: true, isAwake: true, systemDisabled: nil, position: nil, start: false, stop: true),
            .init(name: "owned inactive with disabled kernel", hasSession: true, isAwake: false, systemDisabled: true, position: nil, start: false, stop: true),
            .init(name: "owned inactive awaiting cleanup", hasSession: true, isAwake: false, systemDisabled: false, position: nil, start: false, stop: true),
            .init(name: "owned inactive with unreadable kernel", hasSession: true, isAwake: false, systemDisabled: nil, position: nil, start: false, stop: true),
            .init(name: "awake without ownership and disabled kernel", hasSession: false, isAwake: true, systemDisabled: true, position: nil, start: false, stop: false),
            .init(name: "awake without ownership and sleep allowed", hasSession: false, isAwake: true, systemDisabled: false, position: nil, start: false, stop: false),
            .init(name: "awake without ownership and unreadable kernel", hasSession: false, isAwake: true, systemDisabled: nil, position: nil, start: false, stop: false)
        ]
        for fixture in fixtures {
            for busy in [false, true] {
                for recovering in [false, true] {
                    let state = RunSwitchState(busy: busy, recovering: recovering,
                        hasSession: fixture.hasSession, isAwake: fixture.isAwake,
                        systemDisabled: fixture.systemDisabled)
                    let name = "\(fixture.name), busy=\(busy), recovering=\(recovering)"
                    let position = busy || recovering ? nil : fixture.position
                    let start = busy || recovering ? false : fixture.start
                    let stop = busy ? false : fixture.stop
                    expect(state.position == position, "\(name): confirmed position")
                    expect(state.canStart == start, "\(name): start permission")
                    expect(state.canStop == stop, "\(name): stop permission")
                    expect(state.accepts(true) == start, "\(name): choose running")
                    expect(state.accepts(false) == stop, "\(name): choose normal sleep")
                }
            }
        }
    }

    static func lifecycleTests() {
        let idle = RunSwitchState(busy: false, recovering: false, hasSession: false, isAwake: false, systemDisabled: false)
        expect(!idle.accepts(false), "clicking the current sleep side must not start a session")
        expect(idle.accepts(true), "running side may start from confirmed idle")

        let authorizing = RunSwitchState(busy: true, recovering: false, hasSession: false, isAwake: false, systemDisabled: false)
        expect(authorizing.position == nil, "authorization must not move to a confirmed running position")
        expect(!authorizing.accepts(true) && !authorizing.accepts(false), "no second action during authorization")

        let active = RunSwitchState(busy: false, recovering: false, hasSession: true, isAwake: true, systemDisabled: true)
        expect(!active.accepts(true), "clicking the current running side must not stop or restart")
        expect(active.accepts(false), "sleep side ends the owned session")

        let stopping = RunSwitchState(busy: true, recovering: false, hasSession: true, isAwake: true, systemDisabled: true)
        expect(stopping.position == nil, "a stop request is not confirmation of sleep restoration")
        expect(!stopping.accepts(false), "stop cannot be submitted twice while busy")

        let failedStop = RunSwitchState(busy: false, recovering: true, hasSession: true, isAwake: false, systemDisabled: true)
        expect(failedStop.position == nil, "failed restoration must not show normal sleep")
        expect(failedStop.accepts(false) && !failedStop.accepts(true), "failed stop permits only a recovery retry")

        let unreadable = RunSwitchState(busy: false, recovering: true, hasSession: true, isAwake: false, systemDisabled: nil)
        expect(unreadable.accepts(false), "an unreadable kernel must not block ending an owned session")

        let awaitingCleanup = RunSwitchState(busy: false, recovering: true, hasSession: true, isAwake: false, systemDisabled: false)
        expect(awaitingCleanup.position == nil && awaitingCleanup.accepts(false), "kernel restoration alone does not finish session cleanup")

        expect(idle.position == false && !idle.accepts(false), "after confirmed cleanup, selecting sleep again is a no-op")

        let external = RunSwitchState(busy: false, recovering: false, hasSession: false, isAwake: false, systemDisabled: true)
        expect(external.position == nil, "external disabled sleep is not our running position")
        expect(!external.accepts(false) && !external.accepts(true), "neither side may take over an external sleep setting")
    }

    static func panelStatusTests() {
        // LED safety holds for every combination, including stale or
        // contradictory flags; only one complete combination may show green.
        for busy in [false, true] {
            for recovering in [false, true] {
                for hasSession in [false, true] {
                    for isAwake in [false, true] {
                        for disabled: Bool? in [false, true, nil] {
                            let state = RunSwitchState(busy: busy, recovering: recovering,
                                                       hasSession: hasSession, isAwake: isAwake,
                                                       systemDisabled: disabled)
                            let status = PanelStatus(state: state)
                            let confirmedActive = !busy && !recovering && hasSession && isAwake && disabled == true
                            let confirmedIdle = !busy && !recovering && !hasSession && !isAwake && disabled == false
                            expect((status.led == .green) == confirmedActive, "LED green requires complete confirmed ownership")
                            expect((status.led == .off) == confirmedIdle, "LED off requires complete confirmed idle")
                            expect((status.led == .amber) == (!confirmedActive && !confirmedIdle), "uncertainty is always amber")
                        }
                    }
                }
            }
        }

        let idle = RunSwitchState(busy: false, recovering: false, hasSession: false, isAwake: false, systemDisabled: false)
        let active = RunSwitchState(busy: false, recovering: false, hasSession: true, isAwake: true, systemDisabled: true)
        let external = RunSwitchState(busy: false, recovering: false, hasSession: false, isAwake: false, systemDisabled: true)
        let recovering = RunSwitchState(busy: false, recovering: true, hasSession: true, isAwake: false, systemDisabled: nil)
        let unknown = RunSwitchState(busy: false, recovering: false, hasSession: false, isAwake: false, systemDisabled: nil)
        expect(PanelStatus(state: idle).title == "正常休眠", "idle does not claim the computer is asleep")
        expect(PanelStatus(state: idle).detail == nil, "idle leaves room for the selected power-source policy")
        expect(PanelStatus(state: active).title == "合盖保持运行", "confirmed active title")
        expect(PanelStatus(state: external).title == "其他程序阻止休眠", "external override is not our running session")
        expect(PanelStatus(state: unknown).title == "无法确认状态", "unknown title is explicit")
        let restoration = PanelStatus(state: recovering)
        expect(restoration.title == "正在恢复休眠", "pending recovery title")
        expect(restoration.detail?.contains("勿放入包内") == true && restoration.detail?.contains("保持通风") == true,
               "recovery keeps the transport and ventilation warnings")
        let mismatch = RunSwitchState(busy: false, recovering: false, hasSession: true, isAwake: true, systemDisabled: false)
        expect(PanelStatus(state: mismatch).title == "正在确认状态", "contradictory flags do not claim running or restoration")

        for (source, expected) in [("1小时0分", "剩余1小时 · 勿放入包内"), ("2小时15分", "剩余2小时15分 · 勿放入包内"),
                                   ("30分钟", "剩余30分钟 · 勿放入包内"), ("1分钟", "剩余1分钟 · 勿放入包内"),
                                   ("24小时0分", "剩余24小时 · 勿放入包内")] {
            expect(PanelStatus(state: active, remaining: source).detail == expected, "known remaining format \(source)")
        }
        expect(PanelStatus(state: active).detail == "勿放入包内", "missing countdown keeps the warning without inventing a time")
        expect(PanelStatus(state: active, remaining: "稍后").detail == "剩余稍后 · 勿放入包内", "unknown countdown is preserved")
        expect(PanelStatus(state: active, remaining: "1小时99分").detail == "剩余1小时99分 · 勿放入包内", "invalid minute range is not reinterpreted")
        expect(PanelStatus(state: active, remaining: "999999999999999999999分钟").detail == "剩余999999999999999999999分钟 · 勿放入包内", "overflowing countdown remains diagnostic text")

        let busy = RunSwitchState(busy: true, recovering: false, hasSession: true, isAwake: true, systemDisabled: true)
        for (source, expected, action) in [("正在开启…", "正在开启", "等待系统确认"),
                                          ("等待管理员授权…", "等待授权", "请在系统弹窗中授权"),
                                          ("正在恢复休眠…", "正在恢复休眠", "请稍候，勿放入包内"),
                                          ("正在卸载电源服务…", "正在卸载服务", "请稍候")] {
            let status = PanelStatus(state: busy, busyText: source)
            expect(status.title == expected && status.led == .amber, "busy status \(source) never shows confirmed green")
            expect(status.detail == action, "busy detail preserves the required action or safety warning")
        }
        let futureBusy = "等待自定义恢复步骤：错误码 71"
        expect(PanelStatus(state: busy, busyText: futureBusy).detail == futureBusy, "unknown busy diagnostics are retained verbatim")

        for redundant in ["已恢复正常休眠", "已恢复正常休眠。", "可以开始保持唤醒。"] {
            expect(PanelStatus(state: idle, notice: redundant).notice == nil, "confirmed idle omits only a redundant reason-free notice")
            expect(PanelStatus(state: unknown, notice: redundant).notice != nil, "unconfirmed state must not suppress the same diagnostic")
        }
        expect(PanelStatus(state: recovering, notice: "已恢复正常休眠。").notice == "已恢复休眠", "recovery keeps helper feedback until independently confirmed")
        let runningNotice = "保持唤醒中，合盖后仍继续运行。"
        let runningDisplay = PanelStatus(state: active, remaining: "30分钟", notice: runningNotice)
        expect(runningDisplay.notice == nil && runningDisplay.detail == "剩余30分钟 · 勿放入包内", "confirmed running favors countdown and safety reminder over duplicate status")
        expect(PanelStatus(state: external, notice: runningNotice).notice == "合盖后继续运行", "external state does not discard unmatched helper feedback")

        for (source, expected) in [
            ("设定时间已到，已恢复正常休眠。", "时间已到，已恢复休眠"),
            ("设备温度偏高，已恢复正常休眠。", "温度偏高，已恢复休眠"),
            ("电源已断开，已恢复正常休眠。", "电源已断开，已恢复休眠"),
            ("电池电量低于保护阈值，已恢复正常休眠。", "电量不高于 15%，已恢复休眠"),
            ("恢复休眠尚未成功，后台正在重试。请保持通风。", "恢复尚未成功，正在重试。请保持通风"),
            ("正在等待电源服务恢复，请暂勿将电脑放入包内。", "正在恢复休眠，勿放入包内"),
            ("本次会话已结束，其他设置仍在阻止休眠。", "本次运行已结束，其他设置仍阻止休眠"),
            ("未收到应用心跳，请重新打开应用。", "应用连接中断，请重新打开 STILL"),
            ("恢复记录无法读取，请使用卸载助手恢复休眠。", "恢复记录无法读取，请在“使用说明与关于”的“故障恢复与卸载”中查看恢复方法。")
        ] {
            expect(PanelStatus(state: idle, notice: source).notice == expected, "notice keeps distinct cause and action: \(source)")
        }
        let newWarning = "恢复休眠尚未成功，后台正在重试。请保持通风。 新诊断：错误码 42"
        expect(PanelStatus(state: recovering, notice: newWarning).notice == newWarning, "partial warning matches must not erase appended diagnostics")
        let newNotice = "管理员要求暂停操作\n请联系 IT"
        expect(PanelStatus(state: active, notice: newNotice).notice == newNotice, "an active state does not hide an important notice")
        expect(PanelStatus(state: idle, notice: "  \n").notice == nil, "empty notices do not displace useful detail")
    }
}
