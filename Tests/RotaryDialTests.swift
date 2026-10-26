// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 1anzii

import Foundation

@main
struct RotaryDialTests {
    static var checks = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError("FAILED: \(message)") }
    }

    static func close(_ actual: Double, _ expected: Double, _ message: String) {
        expect(actual.isFinite && abs(actual - expected) < 0.000_001, "\(message): expected \(expected), got \(actual)")
    }

    static func main() {
        scaleTests()
        coordinateTests()
        dragTests()
        print("Rotary dial tests passed: \(checks) checks; no UI or power operations.")
    }

    static func scaleTests() {
        expect(TimerDialScale.durations == [1800, 3600, 7200, 14400, 28800, 86400], "duration order")
        expect(TimerDialScale.angles == [-120, -72, -24, 24, 72, 120], "dial positions")
        for (duration, angle) in zip(TimerDialScale.durations, TimerDialScale.angles) {
            close(TimerDialScale.angle(for: duration), angle, "duration maps to angle")
            expect(TimerDialScale.nearestDuration(to: angle) == duration, "angle round-trip")
        }
        for index in 0..<(TimerDialScale.angles.count - 1) {
            let middle = (TimerDialScale.angles[index] + TimerDialScale.angles[index + 1]) / 2
            expect(TimerDialScale.nearestDuration(to: middle - 0.01) == TimerDialScale.durations[index], "below midpoint")
            expect(TimerDialScale.nearestDuration(to: middle) == TimerDialScale.durations[index], "midpoint chooses shorter duration")
            expect(TimerDialScale.nearestDuration(to: middle + 0.01) == TimerDialScale.durations[index + 1], "above midpoint")
        }
        close(TimerDialScale.angle(for: 2700), -120, "unknown duration tie")
        close(TimerDialScale.angle(for: 2701), -72, "unknown duration nearest")
        close(TimerDialScale.angle(for: Int.min), -120, "minimum integer does not overflow")
        close(TimerDialScale.angle(for: Int.max), 120, "maximum integer clamps before floating conversion")
        expect(TimerDialScale.nearestDuration(to: .nan) == 3600, "NaN angle defaults to one hour")
        expect(TimerDialScale.nearestDuration(to: -.infinity) == 1800, "negative infinity clamps")
        expect(TimerDialScale.nearestDuration(to: .infinity) == 86400, "positive infinity clamps")
        expect(TimerDialScale.nearestDuration(to: -Double.greatestFiniteMagnitude) == 1800, "huge negative angle clamps")
        expect(TimerDialScale.nearestDuration(to: Double.greatestFiniteMagnitude) == 86400, "huge positive angle clamps")
    }

    static func coordinateTests() {
        close(TimerDialScale.touchAngle(x: 0, y: -100)!, 0, "top is zero")
        close(TimerDialScale.touchAngle(x: 100, y: 0)!, 90, "right is clockwise")
        close(TimerDialScale.touchAngle(x: -100, y: 0)!, -90, "left is negative")
        close(abs(TimerDialScale.touchAngle(x: 0, y: 100)!), 180, "bottom is angle branch cut")
        expect(TimerDialScale.touchAngle(x: 0, y: 0) == nil, "center undefined")
        expect(TimerDialScale.touchAngle(x: 7, y: 7) == nil, "inside radial dead zone")
        expect(TimerDialScale.touchAngle(x: 12, y: 0) == nil, "dead zone boundary excluded")
        expect(TimerDialScale.touchAngle(x: 12.01, y: 0) != nil, "outside dead zone accepted")
        for invalid in [Double.nan, Double.infinity, -Double.infinity] {
            expect(TimerDialScale.touchAngle(x: invalid, y: 40) == nil, "invalid x rejected")
            expect(TimerDialScale.touchAngle(x: 40, y: invalid) == nil, "invalid y rejected")
        }
        expect(TimerDialScale.touchAngle(x: .greatestFiniteMagnitude, y: .greatestFiniteMagnitude)?.isFinite == true,
               "large finite coordinates remain usable")
    }

    static func dragTests() {
        // Starting far from the marker must preserve the selected duration.
        var anchored = RotaryDialDrag(angle: -72, touchAngle: 140)
        close(anchored.angle, -72, "initial grab does not jump")
        close(anchored.update(touchAngle: 140), -72, "stationary first event does not jump")
        close(anchored.update(touchAngle: 150), -62, "drag follows relative movement")
        close(anchored.update(touchAngle: 130), -82, "reverse relative movement")

        // Crossing the six-o'clock branch cut must move two degrees, not 358.
        var clockwise = RotaryDialDrag(angle: -24, touchAngle: 179)
        close(clockwise.update(touchAngle: -179), -22, "clockwise across positive-to-negative 180")
        close(clockwise.update(touchAngle: 178), -25, "counterclockwise back across branch cut")
        var counterclockwise = RotaryDialDrag(angle: 24, touchAngle: -179)
        close(counterclockwise.update(touchAngle: 179), 22, "counterclockwise across negative-to-positive 180")
        var equivalent = RotaryDialDrag(angle: 0, touchAngle: 180)
        close(equivalent.update(touchAngle: -180), 0, "signed representations of same bottom point")
        close(equivalent.update(touchAngle: 540), 0, "wrapped representations of same point")

        // Overshooting either stop must not create hysteresis when reversing.
        var upper = RotaryDialDrag(angle: 110, touchAngle: 90)
        close(upper.update(touchAngle: 110), 120, "upper limit clamps")
        close(upper.update(touchAngle: 160), 120, "continued overshoot stays at upper limit")
        close(upper.update(touchAngle: 159), 119, "upper limit reverses immediately")
        var lower = RotaryDialDrag(angle: -110, touchAngle: -90)
        close(lower.update(touchAngle: -110), -120, "lower limit clamps")
        close(lower.update(touchAngle: -160), -120, "continued overshoot stays at lower limit")
        close(lower.update(touchAngle: -159), -119, "lower limit reverses immediately")

        // Entering the center suspends angular movement, then resets the anchor.
        var center = RotaryDialDrag(angle: 24, touchAngle: 20)
        close(center.update(touchAngle: TimerDialScale.touchAngle(x: 0, y: 0)), 24, "center ignores movement")
        close(center.update(touchAngle: -150), 24, "leaving center only establishes a new anchor")
        close(center.update(touchAngle: -140), 34, "movement resumes from new anchor")
        var unanchored = RotaryDialDrag(angle: 72, touchAngle: nil)
        close(unanchored.update(touchAngle: -170), 72, "gesture starting in center does not jump")
        close(unanchored.update(touchAngle: -160), 82, "gesture starting in center later rotates")

        for invalid in [Double.nan, Double.infinity, -Double.infinity] {
            var drag = RotaryDialDrag(angle: 24, touchAngle: 10)
            close(drag.update(touchAngle: invalid), 24, "non-finite movement is ignored")
            close(drag.update(touchAngle: 170), 24, "invalid movement resets anchor")
            close(drag.update(touchAngle: 175), 29, "rotation resumes after invalid movement")
        }
        close(RotaryDialDrag(angle: .nan, touchAngle: nil).angle, -72, "NaN initial angle defaults")
        close(RotaryDialDrag(angle: .infinity, touchAngle: nil).angle, 120, "infinite initial angle upper limit")
        close(RotaryDialDrag(angle: -.infinity, touchAngle: nil).angle, -120, "infinite initial angle lower limit")

        // Two complete forward and reverse revolutions using repeated branch
        // crossings preserves bounds and remains responsive at both stops.
        var sweep = RotaryDialDrag(angle: -120, touchAngle: -170)
        for touch in stride(from: -165, through: 550, by: 5) {
            let before = sweep.angle
            let after = sweep.update(touchAngle: Double(touch))
            expect(after >= -120 && after <= 120 && after >= before && after - before <= 5.000_001,
                   "forward sweep remains bounded and incremental")
        }
        for touch in stride(from: 545, through: -170, by: -5) {
            let before = sweep.angle
            let after = sweep.update(touchAngle: Double(touch))
            expect(after >= -120 && after <= 120 && after <= before && before - after <= 5.000_001,
                   "reverse sweep remains bounded and incremental")
        }
        close(sweep.angle, -120, "reverse sweep reaches lower stop")
    }
}
