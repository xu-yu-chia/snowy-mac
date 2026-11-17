/// Water collecting at the bottom of a display in rain.
///
/// The volume lives in `level` (pt above the screen bottom), which only rises with water that
/// arrives and never above `cap`. The surface on top of it is a damped 1D wave field `heights`
/// (deviation from `level`, positive = up) whose mean is kept at zero, so waves never change the
/// amount of water.
public final class FloodField {
    /// Cap used when the display has no Dock along its bottom edge.
    public static let fallbackCap: Float = 60

    static let waveSpeed: Float = 260
    static let damping: Float = 1.6
    static let maximumAmplitude: Float = 12
    /// Seconds over which the level eases down after the cap drops below it.
    static let capEaseDuration: Float = 2
    /// Fixed integration step. 1/120 s keeps the Courant number (c·dt/dx ≈ 0.54) stable at 4 pt.
    static let substep: Float = 1 / 120

    public let width: Float
    public let spacing: Float
    public private(set) var level: Float = 0
    /// Highest allowed level, refreshed from the scene (the Dock tray's top above the bottom edge).
    public var cap: Float = FloodField.fallbackCap
    public private(set) var heights: [Float]
    private var velocities: [Float]
    private var easeRate: Float = 0

    public init(width: Float, spacing: Float = 4) {
        self.width = max(width, 1)
        self.spacing = max(spacing, 1)
        let count = Int((self.width / self.spacing).rounded(.up)) + 1
        heights = Array(repeating: 0, count: count)
        velocities = Array(repeating: 0, count: count)
    }

    /// Adds `area` pt² of water: the level rises by `area / width`, and anything above the cap is
    /// discarded. While the level is easing down to a lowered cap, new water does not raise it.
    func add(area: Float) {
        guard area > 0 else { return }
        level = max(level, min(cap, level + area / width))
    }

    /// Kicks the surface at `x` (pt from the display's left edge); negative pushes the water down.
    func impulse(at x: Float, velocity: Float) {
        guard velocity.isFinite else { return }
        velocities[index(at: x)] += velocity
    }

    func step(dt: Float) {
        guard dt > 0 else { return }
        easeTowardCap(dt: dt)
        // Fixed substeps; a long frame is not caught up (at most 3 frames' worth).
        let count = min(6, max(1, Int((dt / Self.substep).rounded())))
        for _ in 0..<count { integrate(Self.substep) }
    }

    /// Lowers the level at `rate` pt/s (after the rain stops), never below zero.
    func drain(rate: Float, dt: Float) {
        guard rate > 0, dt > 0 else { return }
        level = max(0, level - rate * dt)
    }

    func clear() {
        level = 0
        easeRate = 0
        for i in heights.indices { heights[i] = 0; velocities[i] = 0 }
    }

    /// Wave height at `x`, linearly interpolated between samples.
    public func height(at x: Float) -> Float {
        let position = min(max(x / spacing, 0), Float(heights.count - 1))
        let lower = Int(position)
        let upper = min(lower + 1, heights.count - 1)
        let t = position - Float(lower)
        return heights[lower] * (1 - t) + heights[upper] * t
    }

    /// Screen y (top-left origin) of the water surface at `x` for a display whose bottom edge is at
    /// `bottom`.
    public func surfaceY(at x: Float, bottom: Float) -> Float {
        bottom - level - height(at: x)
    }

    private func index(at x: Float) -> Int {
        min(max(Int((x / spacing).rounded()), 0), heights.count - 1)
    }

    private func easeTowardCap(dt: Float) {
        guard level > cap else { easeRate = 0; return }
        // Drain the excess over ~2 s from when the cap dropped; a further drop speeds it up.
        easeRate = max(easeRate, (level - cap) / Self.capEaseDuration)
        level = max(cap, level - easeRate * dt)
    }

    private func integrate(_ dt: Float) {
        let count = heights.count
        guard count > 2 else { return }
        let stiffness = Self.waveSpeed * Self.waveSpeed / (spacing * spacing)
        for i in 0..<count {
            // Reflecting ends: the missing neighbour mirrors the edge sample.
            let left = heights[max(i - 1, 0)]
            let right = heights[min(i + 1, count - 1)]
            let laplacian = left + right - 2 * heights[i]
            velocities[i] += (stiffness * laplacian - Self.damping * velocities[i]) * dt
        }
        var sum: Float = 0
        for i in 0..<count {
            heights[i] += velocities[i] * dt
            sum += heights[i]
        }
        // Waves move water around; the volume stays in `level`.
        let mean = sum / Float(count)
        for i in 0..<count {
            heights[i] -= mean
            if abs(heights[i]) > Self.maximumAmplitude {
                heights[i] = heights[i] < 0 ? -Self.maximumAmplitude : Self.maximumAmplitude
                velocities[i] = 0
            }
        }
    }
}
