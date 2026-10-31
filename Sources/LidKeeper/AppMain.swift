// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import AppKit
import SwiftUI

@main
enum LidKeeperMain {
    static func main() {
        umask(0o077)
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: SleepModel!
    private var statusItem: NSStatusItem!
    private let panel = StatusPanelPresenter()
    private var helpWindow: NSWindow?
    private var previewWindow: NSWindow?
    private var stoppingForTermination = false
    private var screenObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second copy must not replace the first copy's lease/request files.
        if let id = Bundle.main.bundleIdentifier {
            let peers = NSRunningApplication.runningApplications(withBundleIdentifier: id)
                .filter { $0.processIdentifier != getpid() }
            if let existing = peers.first {
                existing.activate(options: [])
                NSApp.terminate(nil)
                return
            }
        }
        Brand.registerBundledFont()
        model = SleepModel()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("STILL")
        }
        // Recompute the anchor and available space on the next open after a
        // display is connected, removed, scaled, or moved.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.panel.dismiss()
                self?.model.refreshBrightness()
            }
        }
        model.didChange = { [weak self] in self?.updateStatus() }
        updateStatus()
        if CommandLine.arguments.contains("--show-window") {
            showPreviewWindow()
        } else if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showPanel() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        panel.dismiss()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        if model.busy { return .terminateCancel }
        model.prepareBrightnessForExit()
        guard model.hasSession else { return .terminateNow }
        guard !stoppingForTermination else { return .terminateLater }
        stoppingForTermination = true
        Task {
            let stopped = await model.stop()
            if !stopped { model.cancelBrightnessExit() }
            stoppingForTermination = false
            sender.reply(toApplicationShouldTerminate: stopped)
        }
        return .terminateLater
    }

    private func updateStatus() {
        guard let button = statusItem?.button else { return }
        let symbol = model.isAwake ? "sun.max" : "laptopcomputer"
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: model.title)?.withSymbolConfiguration(config)
        icon?.isTemplate = true
        button.image = icon
        button.toolTip = "STILL — \(model.title)"
        button.setAccessibilityValue(model.title)
    }

    @objc private func statusClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            panel.dismiss()
            let menu = NSMenu()
            let item = NSMenuItem(title: "打开 STILL", action: #selector(openPanel), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
            let quit = NSMenuItem(title: model.hasSession ? "恢复休眠并退出" : "退出 STILL", action: #selector(quitApp), keyEquivalent: "q")
            quit.target = self
            quit.isEnabled = !model.busy
            menu.addItem(quit)
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else if panel.isShown { panel.dismiss() }
        else { showPanel() }
    }

    @objc private func openPanel() { showPanel() }
    @objc private func quitApp() { model.quit() }

    private func showPanel() {
        guard let button = statusItem?.button, let anchorWindow = button.window else { return }
        model.refresh()
        let anchor = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = anchorWindow.screen
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) })
            ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        // A transparent borderless window needs only a small screen-edge gap.
        let availableHeight = min(visible.maxY, anchor.minY) - visible.minY - 16
        guard availableHeight > 0, visible.width > 32 else { return }
        let size = NSSize(width: min(350, visible.width - 32), height: min(420, availableHeight))
        let host = TransparentHostingView(rootView: PanelView(model: model, viewportSize: size) { [weak self] in self?.showHelp() })
        host.sizingOptions = []
        host.setFrameSize(size)
        let content = NSViewController()
        content.view = host
        content.preferredContentSize = size
        panel.show(content: content, size: size, anchor: anchor, visibleFrame: visible, statusButton: button)
    }

    private func showHelp() {
        panel.dismiss()
        if helpWindow == nil {
            let visible = statusItem.button?.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
            let size = NSSize(width: min(510, visible.width - 32), height: min(560, visible.height - 60))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            // Keep the original body viewport plus its native title bar when
            // extending only the background underneath the window chrome.
            let standardFrame = window.frame
            window.styleMask.insert(.fullSizeContentView)
            window.setFrame(standardFrame, display: false)
            window.title = "使用说明与关于"
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.backgroundColor = NSColor(white: 0.235, alpha: 1)
            window.appearance = NSAppearance(named: .darkAqua)
            // The initial placeholder content view can have zero bounds before
            // hosting is attached; full-size content fills the window frame.
            let fullSize = window.frame.size
            let normalContent = NSWindow.contentRect(forFrameRect: window.frame,
                styleMask: window.styleMask.subtracting(.fullSizeContentView))
            let fallbackInset = max(0, fullSize.height - normalContent.height)
            let layout = window.contentLayoutRect
            let measuredInset = fullSize.height - layout.maxY
            let titlebarHeight = layout.height > 0 && measuredInset > 0 && measuredInset < fullSize.height
                ? measuredInset : fallbackInset
            let host = NSHostingView(rootView: HelpView(model: model, viewportSize: fullSize, titlebarHeight: titlebarHeight))
            host.sizingOptions = []
            host.setFrameSize(fullSize)
            window.contentView = host
            window.isReleasedWhenClosed = false
            window.center()
            helpWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        helpWindow?.makeKeyAndOrderFront(nil)
    }

    private func showPreviewWindow() {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let size = NSSize(width: min(350, visible.width - 32), height: min(420, visible.height - 60))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "STILL"
        window.contentView = NSHostingView(rootView: PanelView(model: model, viewportSize: size) { [weak self] in self?.showHelp() })
        window.isReleasedWhenClosed = false
        window.center()
        previewWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
