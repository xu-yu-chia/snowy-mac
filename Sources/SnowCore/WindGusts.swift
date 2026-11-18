import Foundation

/// Gusts around the set wind: the heading swings within ±30° and the strength between 60% and
/// 130% (capped at full), a gust every few seconds. Summed sines of unrelated periods keep it
/// irregular without state, so every display evaluating the same clock gusts in step.
public enum WindGusts {
    public static func wind(base: WindSettings, at time: Double) -> WindSettings {
        guard base.speedFraction >= 0.01, time.isFinite else { return base }
        let t = time.truncatingRemainder(dividingBy: 86_400)
        func wave(_ period: Double, _ phase: Double) -> Double { sin(t * 2 * .pi / period + phase) }
        // Each sum's weights add to 1, so it stays in [-1, 1].
        let swing = wave(9.7, 0) * 0.6 + wave(5.3, 1.3) * 0.3 + wave(3.1, 2.1) * 0.1
        let surge = wave(6.1, 0.7) * 0.6 + wave(4.3, 2.9) * 0.4
        let heading = base.headingDegrees + Float(swing * 30)
        let speed = min(1, base.speedFraction * Float(0.95 + surge * 0.35))
        return WindSettings(headingDegrees: heading < 0 ? heading + 360 : heading, speedFraction: speed)
    }
}
