// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

/// A confirmed switch position and the safe actions for one controller snapshot.
/// This type neither changes power settings nor assumes that a requested action
/// has succeeded. `nil` is an indeterminate/transition position, not another mode.
struct RunSwitchState {
    let busy: Bool
    let recovering: Bool
    let hasSession: Bool
    let isAwake: Bool
    let systemDisabled: Bool?

    var position: Bool? {
        guard !busy, !recovering else { return nil }
        switch (systemDisabled, hasSession, isAwake) {
        case (false?, false, false): return false
        case (true?, true, true): return true
        default: return nil
        }
    }

    var canStart: Bool {
        // A contradictory awake flag must never authorize a second start.
        !busy && !recovering && !hasSession && !isAwake && systemDisabled == false
    }

    var canStop: Bool {
        // Retain the recovery action even when the system state is unknown or
        // already reads false but the controller still owns a pending session.
        !busy && hasSession
    }

    /// Select a destination, rather than toggling whatever state happens to be
    /// current. Re-selecting either confirmed destination is a no-op.
    func accepts(_ running: Bool) -> Bool {
        guard position != running else { return false }
        return running ? canStart : canStop
    }
}
