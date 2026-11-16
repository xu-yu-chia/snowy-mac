import Foundation

/// How fast settled snow melts away. Off keeps every pile until it is swept or covered.
public enum Melting: String, CaseIterable, Sendable {
    case off = "Off"
    case slow = "Slow"
    case fast = "Fast"

    /// Fraction of each pile's height lost per second. Proportional melting lets snowfall and
    /// melt settle at a visible balance for every density instead of either winning outright:
    /// with Steady snowfall a cap levels off near 70% (slow) or 35% (fast) of a full pile.
    public var rate: Float {
        switch self {
        case .off: 0
        case .slow: 0.03
        case .fast: 0.08
        }
    }
}
