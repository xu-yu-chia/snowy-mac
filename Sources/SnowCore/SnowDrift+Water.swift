/// Rain puddles: one level depth per top. Water is stored as `puddle × exposedWidth`; whatever
/// does not fit runs off the ends as (localX, area) pairs for the simulation to drop as drips.
extension SnowDrift {
    /// Deepest puddle a top holds before water runs off.
    var puddleLimit: Float { surface.isDock ? 2 : 3 }

    /// Width of the top that is not covered by other windows; the puddle lies only there.
    var exposedWidth: Float {
        surface.visibleSpans.reduce(0) { $0 + max(0, $1.upper - $1.lower) }
    }

    /// Water currently held on this top (pt²).
    var puddleArea: Float { puddle * exposedWidth }

    /// Adds `area` pt² of water landing at `localX`. Returns the water that runs off.
    func addWater(area: Float, at localX: Float) -> [(localX: Float, area: Float)] {
        guard area.isFinite, area > 0 else { return [] }
        let width = exposedWidth
        guard surface.holdsWater, width > 0.5 else {
            // Props and fully covered tops shed water where it hit.
            return [(max(0, min(surface.width, localX)), area)]
        }
        let room = max(0, puddleLimit - puddle) * width
        let kept = min(room, area)
        puddle += kept / width
        return area - kept > 0.0001 ? runoff(area - kept) : []
    }

    /// Empties the puddle at the ends (the window moved, resized or went away).
    func releasePuddle() -> [(localX: Float, area: Float)] {
        let area = puddleArea
        puddle = 0
        return area > 0.0001 ? runoff(area) : []
    }

    func evaporate(fraction: Float) {
        guard fraction.isFinite, fraction > 0 else { return }
        puddle = max(0, puddle * (1 - fraction))
    }

    /// Splits water leaving the top between the ends it can run off: a tilted top drains at its
    /// lower end; a level top drains equally to both exposed ends, and an end that is covered or
    /// faces a neighbouring top across a slit passes its share to the other end.
    private func runoff(_ area: Float) -> [(localX: Float, area: Float)] {
        if surface.slope > 0 { return [(surface.width, area)] }
        if surface.slope < 0 { return [(0, area)] }
        let spans = surface.visibleSpans
        let startOpen = spans.contains { $0.lower <= 0.5 } && !blockedEnds.start
        let endOpen = spans.contains { $0.upper >= surface.width - 0.5 } && !blockedEnds.end
        switch (startOpen, endOpen) {
        case (true, true): return [(0, area / 2), (surface.width, area / 2)]
        case (true, false): return [(0, area)]
        case (false, true): return [(surface.width, area)]
        case (false, false):
            // Both ends hidden: the water runs off the visible edges behind the covering windows.
            let lower = spans.map(\.lower).min() ?? 0, upper = spans.map(\.upper).max() ?? surface.width
            return [(lower, area / 2), (upper, area / 2)]
        }
    }
}
