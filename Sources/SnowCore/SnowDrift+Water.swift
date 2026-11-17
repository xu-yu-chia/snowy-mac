/// Rain puddles: one level depth per top. Water is stored as `puddle × exposedWidth` plus the drops
/// hanging at the overflow points; whatever does not fit runs off as (localX, area) pairs for the
/// simulation to drop as drips.
extension SnowDrift {
    /// Water gathered at an overflow point falls once it holds this much (surface tension).
    static let hangingDropArea: Float = 12

    /// Deepest the water gets before it overflows: the rim (3 pt, Dock 2 pt), or, for a top walled
    /// in by taller windows on both sides, the shorter wall.
    var puddleLimit: Float {
        let rim: Float = surface.isDock ? 2 : 3
        guard let start = containerWalls.start, let end = containerWalls.end else { return rim }
        return max(rim, min(start, end))
    }

    var isContainer: Bool { containerWalls.start != nil && containerWalls.end != nil }

    /// Width of the top that is not covered by other windows; the puddle lies only there.
    var exposedWidth: Float {
        surface.visibleSpans.reduce(0) { $0 + max(0, $1.upper - $1.lower) }
    }

    /// Water currently held on this top (pt²), including drops hanging at its edges.
    var puddleArea: Float { puddle * exposedWidth + hanging.start + hanging.end }

    /// Adds `area` pt² of water landing at `localX`. Returns the water that falls off. Once the
    /// top is full its surface stays at the overflow level; the excess gathers at the overflow
    /// point and falls a drop at a time.
    func addWater(area: Float, at localX: Float) -> [(localX: Float, area: Float)] {
        guard area.isFinite, area > 0 else { return [] }
        let width = exposedWidth
        guard surface.holdsWater, width > 0.5 else {
            // Props and fully covered tops shed water where it hit.
            return [(max(0, min(surface.width, localX)), area)]
        }
        let kept = min(max(0, puddleLimit - puddle) * width, area)
        puddle += kept / width
        let excess = area - kept
        guard excess > 0.0001 else { return [] }
        var falling: [(localX: Float, area: Float)] = []
        for part in runoff(excess) {
            if part.localX <= surface.width / 2 {
                hanging.start += part.area
                if hanging.start >= Self.hangingDropArea { falling.append((part.localX, hanging.start)); hanging.start = 0 }
            } else {
                hanging.end += part.area
                if hanging.end >= Self.hangingDropArea { falling.append((part.localX, hanging.end)); hanging.end = 0 }
            }
        }
        return falling
    }

    /// Empties the puddle at its overflow ends (the window moved, resized or went away).
    func releasePuddle() -> [(localX: Float, area: Float)] {
        let area = puddleArea
        puddle = 0
        hanging = (0, 0)
        return area > 0.0001 ? runoff(area) : []
    }

    /// Takes up to `area` pt² off the top (brushed by the glove) and returns what was taken.
    func removeWater(_ area: Float) -> Float {
        let total = puddleArea
        let taken = max(0, min(area, total))
        let width = exposedWidth
        hanging = (0, 0)
        puddle = width > 0 ? max(0, (total - taken) / width) : 0
        return taken
    }

    func evaporate(fraction: Float) {
        guard fraction.isFinite, fraction > 0 else { return }
        let keep = max(0, 1 - fraction)
        puddle *= keep
        hanging = (hanging.start * keep, hanging.end * keep)
    }

    /// Splits water leaving the top between the ends it can run off. A container spills over its
    /// shorter wall; a tilted top drains at its lower end; a level top drains equally to both
    /// exposed ends, and an end that is covered or faces a neighbouring top across a slit passes
    /// its share to the other end.
    private func runoff(_ area: Float) -> [(localX: Float, area: Float)] {
        let spans = surface.visibleSpans
        let lower = spans.map(\.lower).min() ?? 0, upper = spans.map(\.upper).max() ?? surface.width
        if let start = containerWalls.start, let end = containerWalls.end {
            if start < end { return [(lower, area)] }
            if end < start { return [(upper, area)] }
            return [(lower, area / 2), (upper, area / 2)]
        }
        if surface.slope > 0 { return [(surface.width, area)] }
        if surface.slope < 0 { return [(0, area)] }
        let startOpen = spans.contains { $0.lower <= 0.5 } && !blockedEnds.start
        let endOpen = spans.contains { $0.upper >= surface.width - 0.5 } && !blockedEnds.end
        switch (startOpen, endOpen) {
        case (true, true): return [(0, area / 2), (surface.width, area / 2)]
        case (true, false): return [(0, area)]
        case (false, true): return [(surface.width, area)]
        case (false, false):
            // Both ends hidden: the water runs off the visible edges behind the covering windows.
            return [(lower, area / 2), (upper, area / 2)]
        }
    }
}
