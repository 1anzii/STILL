// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import Foundation

/// Shared geometry for the six-position timer dial. Angles are in degrees,
/// measured clockwise from twelve o'clock; the bottom 120° is outside its arc.
enum TimerDialScale {
    static let durations: [Int] = [1_800, 3_600, 7_200, 14_400, 28_800, 86_400]
    static let angles: [Double] = [-120, -72, -24, 24, 72, 120]
    static let defaultDuration = 3_600
    static let centerDeadZone = 12.0

    /// Unknown durations select the closest supported duration, with ties
    /// choosing the shorter one. The comparisons also handle Int.min/max.
    static func angle(for seconds: Int) -> Double {
        guard seconds > durations[0] else { return angles[0] }
        guard seconds < durations[durations.count - 1] else { return angles[angles.count - 1] }
        let value = Double(seconds)
        var nearest = 0
        for index in durations.indices.dropFirst() {
            if abs(Double(durations[index]) - value) < abs(Double(durations[nearest]) - value) {
                nearest = index
            }
        }
        return angles[nearest]
    }

    /// Snap to the closest dial position. Midpoints choose the shorter duration.
    /// NaN uses the one-hour default; infinities and out-of-range angles clamp.
    static func nearestDuration(to angle: Double) -> Int {
        let value = clampedAngle(angle)
        var nearest = 0
        for index in angles.indices.dropFirst() {
            if abs(angles[index] - value) < abs(angles[nearest] - value) {
                nearest = index
            }
        }
        return durations[nearest]
    }

    /// Coordinates are relative to the dial center in a downward-positive
    /// screen coordinate system. Angle is undefined inside the center dead zone.
    static func touchAngle(x: Double, y: Double) -> Double? {
        guard x.isFinite, y.isFinite, hypot(x, y) > centerDeadZone else { return nil }
        return atan2(x, -y) * 180 / .pi
    }

    fileprivate static func clampedAngle(_ angle: Double) -> Double {
        guard !angle.isNaN else { return self.angle(for: defaultDuration) }
        return min(angles[angles.count - 1], max(angles[0], angle))
    }
}

/// Incremental drag state, independent of SwiftUI and of the sleep controller.
/// Starting at any point anchors the gesture without moving the selected value.
struct RotaryDialDrag {
    private(set) var angle: Double
    private var previousTouchAngle: Double?

    init(angle: Double, touchAngle: Double?) {
        self.angle = TimerDialScale.clampedAngle(angle)
        previousTouchAngle = Self.normalizedTouch(touchAngle)
    }

    /// Every valid touch refreshes the anchor, including at a limit. Thus
    /// overshooting a stop never creates hidden travel to undo before reversing.
    /// Entering the center or receiving an invalid angle breaks the anchor; the
    /// next valid point reanchors without introducing a discontinuity.
    @discardableResult
    mutating func update(touchAngle: Double?) -> Double {
        guard let current = Self.normalizedTouch(touchAngle) else {
            previousTouchAngle = nil
            return angle
        }
        defer { previousTouchAngle = current }
        guard let previous = previousTouchAngle else { return angle }
        var delta = current - previous
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        angle = TimerDialScale.clampedAngle(angle + delta)
        return angle
    }

    private static func normalizedTouch(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        var result = value.truncatingRemainder(dividingBy: 360)
        if result > 180 { result -= 360 }
        if result < -180 { result += 360 }
        return result
    }
}
