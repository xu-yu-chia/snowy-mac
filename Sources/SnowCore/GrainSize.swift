import Foundation

/// Size of the physical (granular) snow that the glove pushes and caps shed. Normal is the
/// finest grain the cell budget allows on the display; larger grains use fewer cells.
public enum GrainSize: String, CaseIterable, Sendable {
    case normal = "Normal"
    case large = "Large"
    case extraLarge = "Extra Large"

    public var scale: Float {
        switch self {
        case .normal: 1
        case .large: 1.5
        case .extraLarge: 2
        }
    }
}
