// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import AppKit
import SwiftUI

/// Preserve alpha at the rounded case corners all the way to the window.
@MainActor
final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
}

/// A key-capable window without NSPopover's system background, border, or arrow.
@MainActor
private final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class StatusPanelPresenter: NSObject, NSWindowDelegate {
    private var window: StatusPanel?
    private weak var statusButton: NSStatusBarButton?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var trackingMenus: Set<ObjectIdentifier> = []
    private var focusCheck: DispatchWorkItem?
    private var outsideClickPending = false
    private var hasBecomeKey = false

    var isShown: Bool { window?.isVisible == true }

    func show(content: NSViewController, size: NSSize, anchor: NSRect,
              visibleFrame: NSRect, statusButton: NSStatusBarButton) {
        dismiss()
        self.statusButton = statusButton
        let margin: CGFloat = 8
        let x = min(max(anchor.midX - size.width / 2, visibleFrame.minX + margin),
                    visibleFrame.maxX - size.width - margin)
        let top = min(anchor.minY, visibleFrame.maxY) - margin
        let frame = NSRect(x: x, y: max(visibleFrame.minY + margin, top - size.height),
                           width: size.width, height: size.height)
        let panel = StatusPanel(contentRect: frame, styleMask: [.borderless],
                                backing: .buffered, defer: false)
        panel.title = Brand.name
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.animationBehavior = .none
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        content.view.wantsLayer = true
        content.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentViewController = content
        panel.setFrame(frame, display: false)
        panel.delegate = self
        window = panel
        installDismissalHandlers()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        focusCheck?.cancel()
        focusCheck = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        trackingMenus.removeAll()
        outsideClickPending = false
        hasBecomeKey = false
        statusButton = nil
        let oldWindow = window
        window = nil
        oldWindow?.delegate = nil
        oldWindow?.close()
    }

    func windowDidResignKey(_ notification: Notification) {
        scheduleFocusCheck()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        hasBecomeKey = true
    }

    func windowWillClose(_ notification: Notification) {
        dismiss()
    }

    private func installDismissalHandlers() {
        let mouseDownEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mouseUpEvents: NSEvent.EventTypeMask = [.leftMouseUp, .rightMouseUp, .otherMouseUp]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [mouseDownEvents, mouseUpEvents, .keyDown]) { [weak self] event in
            guard let self, let panel = self.window, panel.isVisible else { return event }
            // A menu owns its keyboard/mouse tracking loop. Let Escape dismiss
            // the menu first, and do not close the parent when its item is clicked.
            guard self.trackingMenus.isEmpty else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53, panel.isKeyWindow, !self.hasPresentedAlert {
                    self.dismiss()
                    return nil
                }
                return event
            }
            if mouseUpEvents.contains(NSEvent.EventTypeMask(rawValue: 1 << event.type.rawValue)) {
                self.scheduleFocusCheck()
                return event
            }
            if event.window === panel { return event }
            if let sheet = panel.attachedSheet, event.window === sheet { return event }
            // The status-item action handles its own toggle on mouse-up.
            if self.isInsideStatusButton(NSEvent.mouseLocation) { return event }
            if !self.hasPresentedAlert { self.dismiss() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [mouseDownEvents, mouseUpEvents]) { [weak self] event in
            guard let self, !self.hasPresentedAlert else { return }
            if mouseDownEvents.contains(NSEvent.EventTypeMask(rawValue: 1 << event.type.rawValue)) {
                self.outsideClickPending = true
            }
            self.scheduleFocusCheck()
        }
        observe(NSApplication.didResignActiveNotification) { [weak self] _ in self?.scheduleFocusCheck() }
        observe(NSMenu.didBeginTrackingNotification) { [weak self] notification in
            guard let self, let menu = notification.object as? NSMenu else { return }
            self.trackingMenus.insert(ObjectIdentifier(menu))
        }
        observe(NSMenu.didEndTrackingNotification) { [weak self] notification in
            guard let self, let menu = notification.object as? NSMenu else { return }
            self.trackingMenus.remove(ObjectIdentifier(menu))
            self.scheduleFocusCheck()
        }
        observe(NSWindow.didEndSheetNotification) { [weak self] notification in
            guard let self, notification.object as? NSWindow === self.window else { return }
            self.scheduleFocusCheck()
        }
    }

    private func observe(_ name: Notification.Name,
                         using handler: @escaping @MainActor @Sendable (Notification) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil,
                                                                 queue: .main) { notification in
            // This observer explicitly delivers on the main queue. Keep menu
            // tracking transitions synchronous with AppKit's notifications.
            MainActor.assumeIsolated { handler(notification) }
        })
    }

    private func isInsideStatusButton(_ point: NSPoint) -> Bool {
        guard let button = statusButton, let anchorWindow = button.window else { return false }
        return anchorWindow.convertToScreen(button.convert(button.bounds, to: nil)).contains(point)
    }

    private var hasPresentedAlert: Bool {
        window?.attachedSheet != nil || NSApp.modalWindow != nil
    }

    private func scheduleFocusCheck() {
        focusCheck?.cancel()
        // AppKit temporarily changes key-window state while opening or closing
        // native menus. Check after that transition, never inside its callback.
        let check = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.window, panel.isVisible,
                  self.trackingMenus.isEmpty, !self.hasPresentedAlert else { return }
            // A held status-item click must finish its mouse-up action before
            // deciding whether to hide; otherwise a long press can reopen it.
            if NSEvent.pressedMouseButtons != 0, self.isInsideStatusButton(NSEvent.mouseLocation) { return }
            // Activation can be asynchronous. Do not interpret the initial
            // not-yet-key state as a loss of focus immediately after opening.
            if self.outsideClickPending || (self.hasBecomeKey && (!NSApp.isActive || !panel.isKeyWindow)) {
                self.dismiss()
            }
        }
        focusCheck = check
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: check)
    }
}
