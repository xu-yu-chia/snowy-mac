import Foundation

public final class SnowDrift {
    public internal(set) var surface: Surface
    public internal(set) var heights: [Float]
    let spacing: Float
    private var scratch: [Float]
    private var capacities: [Float]
    private var deposition: [Float]
    private var baseCapacities: [Float]
    private var baseDeposition: [Float]
    private var snowfallCapacities: [Float]
    private(set) var cornerWind: [CornerWindEffect]
    /// Untapered limits and the shoulder taper per sample, so an end can drop its taper when it
    /// joins the snow filling the slit beside it.
    private var fullCapacities: [Float]
    private var fullBaseCapacities: [Float]
    private var fullDeposition: [Float]
    private var taper: [Float]
    private var taperWidth: Float = 13
    /// Ends whose shoulder joins level snow in the slit beside them (set by the simulation).
    private(set) var joinedEnds: (start: Bool, end: Bool) = (false, false)
    /// A slit floor may fill above its own cap, up to the snow surface of the caps beside it.
    private var raisedLimits: [Float] = []
    /// Where another window's body stands on this top, snow may fill up to that window's top but
    /// never rise above it (it would show as a second layer over that window's own snow).
    /// `.infinity` means no window there.
    private var roomBelow: [Float] = []

    /// Exposed, with room for snow under any window standing on it.
    func isOpen(_ i: Int) -> Bool {
        surface.isExposed(at: Float(i) * spacing) && (roomBelow.isEmpty || roomBelow[i] > 0.5)
    }

    func setRoomBelow(_ room: [Float]) {
        let next = room.contains(where: \.isFinite) ? room : []
        guard next != roomBelow else { return }
        roomBelow = next
        rebuildLimits()
    }
    /// Depth (pt) of the level rain puddle on this top.
    public internal(set) var puddle: Float = 0
    /// Overflow water gathering at each end before it falls as a drop.
    var hanging: (start: Float, end: Float) = (0, 0)
    /// How far taller windows rise above this top right beside each visible end (nil: no wall).
    var containerWalls: (start: Float?, end: Float?) = (nil, nil)
    /// The windows forming those walls.
    var containerWallIDs: (start: UInt64?, end: UInt64?) = (nil, nil)
    /// Ripples on water collected in a container (a basin between windows).
    var waves: FloodField?

    init(surface: Surface, cellCount: Int, windEffects: [CornerWindEffect]? = nil) {
        self.surface = surface
        let count = max(2, cellCount)
        spacing = surface.width / Float(count - 1)
        heights = Array(repeating: 0, count: count)
        scratch = heights
        capacities = heights
        deposition = heights
        baseCapacities = heights
        baseDeposition = heights
        snowfallCapacities = heights
        fullCapacities = heights
        fullBaseCapacities = heights
        fullDeposition = heights
        taper = heights
        cornerWind = windEffects?.count == count ? windEffects! : Array(repeating: .neutral, count: count)
        let phase = Float(surface.id % 997) * 0.17
        // The shallow Dock ridge should reach its rounded shoulders before tapering.
        let taperWidth: Float = surface.isDock ? min(6, surface.width / 2)
            : (surface.width < 16 ? surface.width / 2 : 13)
        self.taperWidth = taperWidth
        let limit: Float
        if surface.id == DesktopSceneBuilder.groundID { limit = 28 }
        else if surface.isDock { limit = 13 }
        else if surface.releasesSnowWhenRemoved && !surface.isElevated {
            limit = min(18, max(4, surface.width * 0.32))
        } else { limit = 18 }
        for i in 0..<count {
            let x = Float(i) * spacing
            let edge = surface.id == DesktopSceneBuilder.groundID ? 1 : min(1, min(x, surface.width - x) / taperWidth)
            let taper = edge * edge * (3 - 2 * edge)
            // A tilted support holds snow up to a level line `limit` above its lowest point.
            let cap = max(0, limit - max(surface.slope * (surface.width - x), -surface.slope * x))
            // Fixed broad lobes: no shimmering noise or random per-frame bumps.
            let lobe = 0.68 + sin(x * 0.027 + phase) * 0.18
                + sin(x * 0.071 + phase * 2) * 0.09
                + sin(x * 0.13 + phase) * 0.05
            // The physical limit follows the same lobes (about 71-99%), so a pile filled by the
            // glove or by landing snow undulates like fresh snow instead of forming a flat
            // plateau, on the Dock ridge as on any window.
            let relief: Float = 0.85 + (lobe - 0.68) * 0.45
            self.taper[i] = taper
            fullCapacities[i] = cap * relief
            fullBaseCapacities[i] = cap * lobe
            fullDeposition[i] = 0.18 + lobe * 0.17
            capacities[i] = cap * taper * relief
            baseCapacities[i] = cap * lobe * taper
            snowfallCapacities[i] = baseCapacities[i]
            deposition[i] = (0.18 + lobe * 0.17) * taper
            // A sub-point dusting makes a discovered edge visible immediately, then builds gradually.
            heights[i] = surface.isSnowExposed(at: x) && !cornerWind[i].clear ? min(capacities[i], 0.6 * taper) : 0
        }
        baseDeposition = deposition
        applyCornerWind(cornerWind)
    }

    /// An end joined to level snow in the slit beside it keeps full depth to its edge, so the two
    /// read as one continuous drift instead of a lower layer beside a rounded shoulder.
    func setJoinedEnds(start: Bool, end: Bool) {
        guard start != joinedEnds.start || end != joinedEnds.end else { return }
        joinedEnds = (start, end)
        rebuildLimits()
    }

    /// Lets the samples in each local range hold snow up to `height` (a slit filling flush with
    /// the caps beside it). An empty list restores the ordinary limits.
    func setRaisedLimits(_ ranges: [(lower: Float, upper: Float, height: Float)]) {
        var limits = ranges.isEmpty ? [] : Array(repeating: Float(0), count: heights.count)
        for range in ranges {
            for i in heights.indices {
                let x = Float(i) * spacing
                if x >= range.lower, x <= range.upper { limits[i] = max(limits[i], range.height) }
            }
        }
        guard limits != raisedLimits else { return }
        raisedLimits = limits
        rebuildLimits()
    }

    /// Full capacity at the outermost sample of an end, before its shoulder taper.
    func edgeCapacity(atEnd: Bool) -> Float {
        let i = atEnd ? heights.count - 1 : 0
        return fullCapacities[i]
    }

    private func rebuildLimits() {
        for i in heights.indices {
            let x = Float(i) * spacing
            let untapered = (joinedEnds.start && x < taperWidth) || (joinedEnds.end && surface.width - x < taperWidth)
            let t = untapered ? 1 : taper[i]
            let raised = raisedLimits.isEmpty ? 0 : raisedLimits[i]
            capacities[i] = max(fullCapacities[i] * t, raised)
            baseCapacities[i] = max(fullBaseCapacities[i] * t, raised)
            baseDeposition[i] = raised > 0 ? max(fullDeposition[i], 0.3) : fullDeposition[i] * t
            if !roomBelow.isEmpty, roomBelow[i].isFinite {
                let room = max(0, roomBelow[i])
                capacities[i] = min(capacities[i], room)
                baseCapacities[i] = min(baseCapacities[i], room)
                heights[i] = min(heights[i], room)
            }
        }
        applyCornerWind(cornerWind)
    }

    func applyCornerWind(_ effects: [CornerWindEffect]) {
        guard effects.count == heights.count else { return }
        cornerWind = effects
        for i in heights.indices {
            // Wind changes incoming snowfall, never the physical space available to pushed snow.
            snowfallCapacities[i] = effects[i].clear ? 0 : min(capacities[i], baseCapacities[i] * effects[i].capacityScale)
            deposition[i] = baseDeposition[i] * effects[i].depositionScale
        }
    }

    public func height(at localX: Float) -> Float {
        guard localX >= 0, localX <= surface.width, spacing > 0 else { return 0 }
        let coordinate = localX / spacing
        let left = min(heights.count - 2, Int(coordinate))
        let t = coordinate - Float(left)
        return heights[left] + (heights[left + 1] - heights[left]) * t
    }

    func accumulate(dt: Float, intensity: Float) {
        for i in heights.indices where surface.isSnowExposed(at: Float(i) * spacing) {
            if heights[i] < snowfallCapacities[i] {
                heights[i] = min(snowfallCapacities[i], heights[i] + deposition[i] * dt * intensity)
            }
        }
    }

    func deposit(at localX: Float, amount: Float) {
        let center = Int((localX / spacing).rounded())
        for offset in -2...2 {
            let i = center + offset
            guard heights.indices.contains(i), surface.isExposed(at: Float(i) * spacing) else { continue }
            let weight: Float = offset == 0 ? 0.44 : (abs(offset) == 1 ? 0.23 : 0.05)
            heights[i] = min(capacities[i], heights[i] + amount * weight)
        }
    }

    /// Area in square points, independent of profile resolution. Returns mass that could not fit.
    /// `reach` limits how many samples away from the landing point the area may settle.
    func depositMass(at localX: Float, mass: Float, direction: Float = 0, snowfall: Bool = false,
                     reach: Int = 24) -> Float {
        guard mass.isFinite, mass > 0 else { return 0 }
        guard localX >= 0, localX <= surface.width else { return mass }
        let coordinate = localX / spacing
        let center = max(0, min(heights.count - 1, Int(direction > 0 ? ceil(coordinate)
            : (direction < 0 ? floor(coordinate) : coordinate.rounded()))))
        if snowfall && (!surface.isSnowExposed(at: localX) || cornerWind[center].clear) { return mass }
        var remaining = mass
        for distance in 0...max(0, min(24, reach)) {
            for side in 0..<((distance == 0 || direction != 0) ? 1 : 2) {
                let i = center + (direction < 0 ? -distance : (side == 0 ? distance : -distance))
                guard heights.indices.contains(i), isOpen(i) else { continue }
                if snowfall && (!surface.isSnowExposed(at: Float(i) * spacing) || cornerWind[i].clear) { continue }
                let capacity = snowfall ? snowfallCapacities[i] : capacities[i]
                let accepted = min(remaining, max(0, capacity - heights[i]) * spacing)
                heights[i] += accepted / spacing
                remaining -= accepted
                if remaining <= 0.0001 { return 0 }
            }
        }
        return remaining
    }

    func settle() {
        // Pairwise transfers preserve volume, including when adjacent samples are full.
        for i in heights.indices { scratch[i] = heights[i] }
        for i in 0..<(heights.count - 1) {
            guard isOpen(i), isOpen(i + 1) else { continue }
            // A tilted support's base drop drives snow toward its lower end until the cap is level.
            // ponytail: no angle of repose and no spill off the low end; full low-end samples just stop.
            let flux = (heights[i] - heights[i + 1] + surface.slope * spacing) * 0.12
            let from = flux > 0 ? i : i + 1
            let to = flux > 0 ? i + 1 : i
            // Snow does not creep sideways along a flat top into a roofed slit that snowfall
            // cannot reach; only a slope steeper than about 37° slumps into it.
            if !surface.isSnowExposed(at: Float(to) * spacing),
               abs(heights[i] - heights[i + 1]) < 3 { continue }
            let transfer = min(abs(flux), min(scratch[from], max(0, capacities[to] - scratch[to])))
            scratch[from] -= transfer
            scratch[to] += transfer
        }
        swap(&heights, &scratch)
        creepOverload()
    }

    /// Snow above capacity creeps one sample toward the nearer end per settle, so an
    /// overloaded hump drifts to the edge where `shedEnds` lets it slide off. The floor has no
    /// edge to shed over: its overload spreads out to both sides and slowly compacts away.
    private func creepOverload() {
        guard heights.count >= 2 else { return }
        let isFloor = surface.id == DesktopSceneBuilder.groundID
        let middle = Float(heights.count - 1) / 2
        for i in heights.indices { scratch[i] = heights[i] }
        for i in heights.indices where heights[i] > capacities[i] + 0.001 {
            let over = heights[i] - capacities[i]
            if isFloor {
                // 0.5% compaction per settle (about 5% per second), then spread sideways.
                scratch[i] -= over * 0.005
                let share = over * 0.12
                for j in [i - 1, i + 1] where heights.indices.contains(j) {
                    scratch[i] -= share
                    scratch[j] += share
                }
                continue
            }
            // Overload can only shed at an end its exposed stretch reaches. A stretch that
            // reaches neither (between covering windows) packs it away rather than letting it
            // stand as a tower; otherwise it creeps toward a reachable end, the nearer one
            // unless that end faces a neighbour across a slit.
            let (startOpen, endOpen) = reachableEnds(from: i)
            guard startOpen || endOpen else {
                scratch[i] -= over * 0.05
                continue
            }
            var towardStart = (Float(i) < middle && startOpen) || !endOpen
            if towardStart && blockedEnds.start && !blockedEnds.end && endOpen { towardStart = false }
            if !towardStart && blockedEnds.end && !blockedEnds.start && startOpen { towardStart = true }
            if blockedEnds.start && blockedEnds.end { continue }
            let j = towardStart ? i - 1 : i + 1
            // Only creep toward an end that can shed: under a covering window nothing moves,
            // so the overload cannot collect in the end sample while the edge is hidden.
            guard heights.indices.contains(j), isFree(j) else { continue }
            let excess = over * 0.3
            scratch[i] -= excess
            scratch[j] += excess
        }
        for i in heights.indices { heights[i] = max(0, scratch[i]) }
        if !isFloor { relieveOverloadSpikes() }
        clampToRoom()
    }

    /// Exposed and clear of any window standing on this top: overload may travel through it.
    private func isFree(_ i: Int) -> Bool {
        surface.isExposed(at: Float(i) * spacing) && (roomBelow.isEmpty || !roomBelow[i].isFinite)
    }

    /// Which ends of this top the free stretch around sample `i` reaches.
    private func reachableEnds(from i: Int) -> (start: Bool, end: Bool) {
        guard isFree(i) else { return (false, false) }
        var lower = i, upper = i
        while lower > 0, isFree(lower - 1) { lower -= 1 }
        while upper < heights.count - 1, isFree(upper + 1) { upper += 1 }
        return (lower == 0, upper == heights.count - 1)
    }

    /// Snow pushed under a window standing on this top packs away above that window's top.
    private func clampToRoom() {
        guard !roomBelow.isEmpty else { return }
        for i in heights.indices where roomBelow[i].isFinite { heights[i] = min(heights[i], max(0, roomBelow[i])) }
    }

    /// An overloaded sample standing more than 4 pt above its inner neighbour slumps inward, so
    /// overload can never pile into a spike at an end (or anywhere else). Samples within their
    /// capacity are untouched, so ordinary piles keep their shape.
    private func relieveOverloadSpikes() {
        guard heights.count >= 2 else { return }
        for _ in 0..<2 {
            for i in heights.indices where heights[i] > capacities[i] + 0.001 {
                for j in [i - 1, i + 1] where heights.indices.contains(j) && isFree(j) {
                    let step = heights[i] - heights[j]
                    guard step > 4 else { continue }
                    let move = min(max(0, heights[i] - capacities[i]), (step - 4) * 0.5)
                    heights[i] -= move
                    heights[j] += move
                }
            }
        }
    }

    /// Highest sample, refreshed once per frame; lets particle hit tests reach tall pushed piles.
    var peak: Float = 0

    /// Which ends overload should not creep toward, because they face a neighbouring top
    /// across a narrow slit (set by the simulation before each settle).
    var blockedEnds: (start: Bool, end: Bool) = (false, false)

    /// Whether overload added at `localX` can creep to an exposed end of this top and shed. A
    /// stretch exposed only between covering windows (the floor of a slit) has no such end:
    /// overload there could only pile up into a pillar.
    func canShedOverload(at localX: Float) -> Bool {
        let i = max(0, min(heights.count - 1, Int((localX / spacing).rounded())))
        let ends = reachableEnds(from: i)
        return ends.start || ends.end
    }

    var isOverloaded: Bool {
        heights.indices.contains { heights[$0] > capacities[$0] + 0.001 }
    }

    /// Snow that no longer fits (pushed or landed onto a full cap) joins the profile above
    /// capacity instead of sitting on it as separate grains.
    func addOverload(at localX: Float, mass: Float) {
        guard mass.isFinite, mass > 0, !heights.isEmpty else { return }
        let center = max(0, min(heights.count - 1, Int((localX / spacing).rounded())))
        var placed: Float = 0
        for (offset, weight) in [(0, Float(0.4)), (-1, 0.2), (1, 0.2), (-2, 0.1), (2, 0.1)] {
            let i = center + offset
            guard heights.indices.contains(i) else { continue }
            heights[i] += mass * weight / spacing
            placed += weight
        }
        heights[center] += mass * (1 - placed) / spacing
    }

    /// How full the pile is relative to what snowfall alone can build (1 = snowfall has stopped).
    var fillRatio: Float {
        let full = snowfallCapacities.reduce(0, +)
        return full > 0.0001 ? heights.reduce(0, +) / full : 0
    }

    /// Removes the same fraction of every sample, so deep piles melt faster than thin ones.
    func melt(fraction: Float) {
        guard fraction > 0 else { return }
        let keep = max(0, 1 - fraction)
        for i in heights.indices { heights[i] *= keep }
    }

    /// Snow a landing flake brings, spread in a bell around where it touched (±3 samples), on visible
    /// samples and up to the snowfall limit. The flake really arrived, so the ambient snowfall shadow
    /// under an overhanging window does not apply (a flake blown in underneath still settles); the
    /// wind wake at a corner still does. Returns the area that did not fit.
    func depositSnowfall(at localX: Float, mass: Float) -> Float {
        guard mass.isFinite, mass > 0, localX >= 0, localX <= surface.width, spacing > 0 else { return mass }
        let center = max(0, min(heights.count - 1, Int((localX / spacing).rounded())))
        let weights: [Float] = [0.22, 0.18, 0.12, 0.09]
        var total: Float = 0
        var rest = mass
        for offset in -3...3 {
            let i = center + offset
            guard heights.indices.contains(i), surface.isExposed(at: Float(i) * spacing),
                  !cornerWind[i].clear else { continue }
            let share = mass * weights[abs(offset)]
            let accepted = min(share, max(0, snowfallCapacities[i] - heights[i]) * spacing)
            heights[i] += accepted / spacing
            rest -= accepted
            total += weights[abs(offset)]
        }
        return max(0, rest)
    }

    /// A flung clump landing at `localX` and sliding `distance` points in `direction` (±1).
    /// The area is laid evenly along the path, filling up to capacity and carrying any excess as
    /// a low, even overload rather than a hill at the landing point. The share of the path that
    /// runs past an exposed end is returned: that snow leaves over the edge.
    func depositSliding(at localX: Float, mass: Float, direction: Float, distance: Float) -> Float {
        guard mass.isFinite, mass > 0, spacing > 0, distance > 0 else { return 0 }
        let start = max(0, min(surface.width, localX))
        let finish = start + direction * distance
        let clipped = max(0, min(surface.width, finish))
        let onTop = abs(clipped - start)
        let endLocal: Float = direction > 0 ? surface.width : 0
        let endOpen = surface.isExposed(at: direction > 0 ? max(0, surface.width - spacing) : min(surface.width, spacing))
        var over = endOpen ? mass * max(0, distance - onTop) / distance : 0
        var lay = mass - over
        var path: [Int] = []
        let first = Int((min(start, clipped) / spacing).rounded())
        let last = Int((max(start, clipped) / spacing).rounded())
        for i in max(0, first)...min(heights.count - 1, max(first, last))
        where surface.isExposed(at: Float(i) * spacing) { path.append(i) }
        // Nowhere visible to land on (the path is covered): the whole clump flies on.
        guard !path.isEmpty else { _ = endLocal; return mass }
        let share = lay / Float(path.count)
        var excess: Float = 0
        for i in path {
            let room = max(0, capacities[i] - heights[i]) * spacing
            let accepted = min(share, room)
            heights[i] += accepted / spacing
            excess += share - accepted
        }
        lay = 0
        // Whatever did not fit rides on as a thin, even layer over the same path.
        if excess > 0.0001 {
            for i in path { heights[i] += excess / Float(path.count) / spacing }
        }
        if !endOpen { over = 0 }
        return over
    }

    /// Settled snow is not glued to its support: it stays where it is on screen when the support
    /// moves or resizes. Samples still above the support keep their snow (a support moving up
    /// lifts it); everything else is returned at its old position so it can fall. A support that
    /// moved down drops out from under all of its snow. Starts from bare, so moving a support
    /// never creates snow.
    func carry(from previous: SnowDrift) -> [(position: SIMD2<Float>, height: Float, mass: Float)] {
        for i in heights.indices { heights[i] = 0 }
        let old = previous.surface
        let lowered = surface.y > old.y + 0.5
        if !lowered {
            for i in heights.indices {
                let oldLocal = surface.x + Float(i) * spacing - old.x
                guard oldLocal >= 0, oldLocal <= old.width else { continue }
                heights[i] = min(capacities[i], previous.height(at: oldLocal))
            }
        }
        var released: [(position: SIMD2<Float>, height: Float, mass: Float)] = []
        for j in previous.heights.indices where previous.heights[j] > 0.0001 {
            let oldLocal = Float(j) * previous.spacing
            let worldX = old.x + oldLocal
            let newLocal = worldX - surface.x
            var lost = previous.heights[j]
            if !lowered, newLocal >= 0, newLocal <= surface.width {
                // Still supported: only what exceeds the capacity here (a tapered end) falls.
                let i = max(0, min(heights.count - 1, Int((newLocal / spacing).rounded())))
                lost = max(0, previous.heights[j] - capacities[i])
            }
            guard lost > 0.0001 else { continue }
            let base = old.baseY(at: oldLocal)
            released.append((SIMD2(worldX, base - previous.heights[j] + lost * 0.5), lost, lost * previous.spacing))
        }
        return released
    }

    /// Room left (area, square points) within `band` points of `localX`.
    func spareArea(near localX: Float, band: Float) -> Float {
        heights.indices.reduce(Float(0)) { sum, i in
            abs(Float(i) * spacing - localX) <= band ? sum + max(0, capacities[i] - heights[i]) * spacing : sum
        }
    }

    /// Takes a chunk off each exposed end, like overloaded snow sliding off a roof edge.
    /// Returns the end (local x) and the area removed there; covered ends keep their snow.
    func shedEnds(fraction: Float, band: Float,
                  skipping skip: (start: Bool, end: Bool) = (false, false)) -> [(localX: Float, mass: Float)] {
        guard heights.count >= 2, fraction > 0 else { return [] }
        let cells = max(1, min(heights.count / 2, Int(band / spacing)))
        var result: [(localX: Float, mass: Float)] = []
        for side in 0..<2 {
            if side == 0 ? skip.start : skip.end { continue }
            let probe = side == 0 ? min(surface.width, spacing) : max(0, surface.width - spacing)
            guard surface.isExposed(at: probe) else { continue }
            var mass: Float = 0
            for k in 0..<cells {
                let i = side == 0 ? k : heights.count - 1 - k
                // Snow above capacity cannot stand at an edge: all of it goes over. Within
                // capacity only a small trickle leaves, so a full pile creeps off gradually.
                let over = max(0, heights[i] - capacities[i])
                let take = over + (heights[i] - over) * fraction
                heights[i] -= take
                mass += take * spacing
            }
            if mass > 0.0001 { result.append((side == 0 ? 0 : surface.width, mass)) }
        }
        return result
    }

    func copySnow(from previous: SnowDrift) {
        for i in heights.indices {
            heights[i] = min(capacities[i], previous.height(at: Float(i) * spacing))
        }
    }

    func clear() {
        for i in heights.indices { heights[i] = 0 }
        puddle = 0
        hanging = (0, 0)
    }

    /// Lowers every sample by up to `amount` pt and returns the melted area (pt²).
    func meltDown(by amount: Float) -> Float {
        guard amount > 0 else { return 0 }
        var melted: Float = 0
        for i in heights.indices where heights[i] > 0 {
            let loss = min(heights[i], amount)
            heights[i] -= loss
            melted += loss
        }
        return melted * spacing
    }
}
