import Foundation

/// Containers of snow. Window top edges across the desktop form a terrain; a hollow in it that
/// cannot drain to the floor or a screen edge is a basin, possibly floored by several windows.
/// A basin holds one shared snow surface: it fills up to its outlet (the lower of the two highest
/// points between it and a drain), then an ordinary undulating cap, and overflows only at that
/// outlet onto the window there, or off it as loose snow.
extension SnowSimulation {
    struct Basin {
        /// Screen y of the outlet: the basin fills up to here before its cap.
        var level: Float
        /// The window at the outlet, +1 if it lies to the right, and the display x of its edge.
        var wallID: UInt64
        var outward: Float
        var outletX: Float
        var members: [(drift: SnowDrift, index: Int, floorY: Float, x: Float)] = []
    }

    static let terrainStep: Float = 2
    /// Wider hollows are no container: snow does not fill a broad stretch between distant walls.
    static let maximumBasinWidth: Float = 160
    static let basinCap: Float = 18

    /// Rebuilds basins when the scene changes. Snow on samples leaving a basin that no longer
    /// fits an ordinary cap falls from there as loose snow (never deleted).
    func refreshBasins() {
        let step = Self.terrainStep
        let columns = max(1, Int((size.x / step).rounded(.up)))
        let walls = bodies.filter { !$0.isElevated && $0.id != DesktopSceneBuilder.dockID }
        // Terrain: the topmost outline over each column, or the floor where any part of the
        // column is open (a gap narrower than a column still drains).
        var terrain = [Float](repeating: size.y, count: columns)
        var owner = [UInt64?](repeating: nil, count: columns)
        for c in 0..<columns {
            let lower = Float(c) * step, upper = lower + step, center = lower + step / 2
            let spans = walls.filter { Float($0.bounds.minX) < upper && Float($0.bounds.maxX) > lower }
                .map { (Float($0.bounds.minX), Float($0.bounds.maxX)) }.sorted { $0.0 < $1.0 }
            var reached = lower
            for span in spans where span.0 <= reached + 0.001 { reached = max(reached, span.1) }
            guard reached >= upper - 0.001 else { continue }
            for body in walls where Float(body.bounds.minX) <= center && Float(body.bounds.maxX) >= center {
                let y = body.contour(at: center)
                if y < terrain[c] { terrain[c] = y; owner[c] = body.id }
            }
        }
        // Water level: the lower of the highest points on the way to a drain (an open column, or
        // past a screen edge) on each side. Screen y: smaller is higher.
        var leftHigh = [Float](repeating: .infinity, count: columns), rightHigh = leftHigh
        var running = Float.infinity
        for c in 0..<columns {
            running = owner[c] == nil ? .infinity : min(running, terrain[c])
            leftHigh[c] = running
        }
        running = .infinity
        for c in stride(from: columns - 1, through: 0, by: -1) {
            running = owner[c] == nil ? .infinity : min(running, terrain[c])
            rightHigh[c] = running
        }
        var trapped = [Bool](repeating: false, count: columns)
        var water = [Float](repeating: 0, count: columns)
        for c in 0..<columns where owner[c] != nil {
            water[c] = max(leftHigh[c], rightHigh[c])
            trapped[c] = terrain[c] > water[c] + 0.5
        }
        let oldMembership = drifts.map { drift in drift.heights.indices.map { drift.basin(at: $0) != nil } }
        basins.removeAll(keepingCapacity: true)
        var basinOfColumn = [Int?](repeating: nil, count: columns)
        var c = 0
        while c < columns {
            guard trapped[c] else { c += 1; continue }
            var b = c
            while b + 1 < columns, trapped[b + 1] { b += 1 }
            defer { c = b + 1 }
            let level = water[c]
            guard c > 0, b + 1 < columns, let leftID = owner[c - 1], let rightID = owner[b + 1],
                  Float(b - c + 1) * step <= Self.maximumBasinWidth else { continue }
            // Both walls must reach down to the basin floor; a hanging window leaks underneath.
            let deepest = (c...b).map { terrain[$0] }.max() ?? level
            guard let leftWall = walls.first(where: { $0.id == leftID }), let rightWall = walls.first(where: { $0.id == rightID }),
                  Float(leftWall.bounds.maxY) >= deepest - 1, Float(rightWall.bounds.maxY) >= deepest - 1 else { continue }
            let towardRight = abs(terrain[b + 1] - level) <= abs(terrain[c - 1] - level)
            basins.append(Basin(level: level, wallID: towardRight ? rightID : leftID, outward: towardRight ? 1 : -1,
                                outletX: towardRight ? Float(b + 1) * step : Float(c) * step))
            for k in c...b { basinOfColumn[k] = basins.count - 1 }
        }
        for drift in drifts {
            var membership = [Int?](repeating: nil, count: drift.heights.count)
            if drift.surface.id != DesktopSceneBuilder.groundID, !drift.surface.isDock, !drift.surface.isElevated {
                for i in drift.heights.indices where drift.isFree(i) {
                    let local = Float(i) * drift.spacing
                    let x = drift.surface.x + local
                    let column = max(0, min(columns - 1, Int(x / step)))
                    guard let index = basinOfColumn[column] else { continue }
                    let floorY = drift.surface.baseY(at: local)
                    guard floorY > basins[index].level + 0.5,
                          !walls.contains(where: { $0.id != drift.surface.id && x >= Float($0.bounds.minX)
                              && x < Float($0.bounds.maxX) && $0.contour(at: x) < floorY - 0.5 }) else { continue }
                    membership[i] = index
                    basins[index].members.append((drift, i, floorY, x))
                }
            }
            drift.setBasins(membership)
        }
        // Snow that sat in a basin but now only has an ordinary cap falls from there.
        for (d, drift) in drifts.enumerated() where d < oldMembership.count && oldMembership[d].count == drift.heights.count {
            for i in drift.heights.indices where oldMembership[d][i] && drift.basin(at: i) == nil {
                let excess = drift.heights[i] - drift.ordinaryCapacity(at: i)
                guard excess > 0.0001 else { continue }
                drift.heights[i] -= excess
                let local = Float(i) * drift.spacing
                retainRelease(SnowRelease(position: SIMD2(drift.surface.x + local, drift.surface.baseY(at: local) - drift.heights[i] - 2),
                                          height: 4, mass: excess * drift.spacing), in: &snowReleases)
            }
        }
        meshDirty = true
    }

    /// Spreads each basin's total snow into one shared surface (every settle). Whatever entered
    /// it (snowfall, landing grains, pushed snow) is simply part of the total. Snow beyond a full
    /// basin and its cap overflows at the outlet.
    func solveBasins() {
        for basin in basins where !basin.members.isEmpty {
            let members = basin.members
            var volume: Float = 0
            for m in members { volume += m.drift.heights[m.index] * m.drift.spacing }
            let rimVolume = members.reduce(Float(0)) { $0 + ($1.floorY - basin.level) * $1.drift.spacing }
            if volume <= rimVolume {
                // Fill from the bottom: one water-like surface L.
                var low = basin.level, high = members.map(\.floorY).max() ?? basin.level
                for _ in 0..<40 {
                    let mid = (low + high) / 2
                    let held = members.reduce(Float(0)) { $0 + max(0, $1.floorY - mid) * $1.drift.spacing }
                    if held > volume { low = mid } else { high = mid }
                }
                let surface = (low + high) / 2
                for m in members { m.drift.heights[m.index] = max(0, m.floorY - surface) }
                continue
            }
            // Full to the outlet: the rest forms a cap that also fills from the bottom, each spot
            // up to its own limit (lobes in screen space, and the wall's own snow at the outlet).
            let extra = volume - rimVolume
            let wall = drifts.first { $0.surface.id == basin.wallID }
            let wallSnow = wall.map { $0.height(at: max(0, min($0.surface.width, basin.outletX + basin.outward * 2 - $0.surface.x))) }
            let limits = members.map { m -> Float in
                let lobe = 0.75 + (sin(m.x * 0.027) * 0.18 + sin(m.x * 0.071) * 0.09 + sin(m.x * 0.13) * 0.05) * 0.6
                let cap = Self.basinCap * lobe
                let distance = abs(m.x - basin.outletX)
                guard let wallSnow, distance < 16 else { return cap }
                return wallSnow + (cap - wallSnow) * distance / 16
            }
            let capVolume = zip(members, limits).reduce(Float(0)) { $0 + $1.1 * $1.0.drift.spacing }
            var overflow: Float = 0
            var thickness = limits.max() ?? 0
            if extra < capVolume {
                var low: Float = 0, high = thickness
                for _ in 0..<40 {
                    let mid = (low + high) / 2
                    let held = zip(members, limits).reduce(Float(0)) { $0 + min($1.1, mid) * $1.0.drift.spacing }
                    if held < extra { low = mid } else { high = mid }
                }
                thickness = (low + high) / 2
            } else {
                overflow = extra - capVolume
            }
            for (m, limit) in zip(members, limits) {
                m.drift.heights[m.index] = (m.floorY - basin.level) + min(limit, thickness)
            }
            if overflow > 0.0001 { release(overflow: overflow, from: basin) }
        }
        if !basins.isEmpty { meshDirty = true }
    }

    /// Lands overflow on the outlet window's top, just outside the basin; what it cannot hold
    /// falls from there as loose snow. Nothing is deleted.
    private func release(overflow mass: Float, from basin: Basin) {
        var rest = mass
        if let wall = drifts.first(where: { $0.surface.id == basin.wallID }) {
            let local = max(0, min(wall.surface.width, basin.outletX + basin.outward * wall.spacing - wall.surface.x))
            let index = max(0, min(wall.heights.count - 1, Int((local / wall.spacing).rounded())))
            if wall.basin(at: index) == nil {
                rest = wall.depositMass(at: local, mass: rest, direction: basin.outward)
                if rest > 0.0001, wall.canShedOverload(at: local) {
                    wall.addOverload(at: local, mass: rest)
                    rest = 0
                }
            }
        }
        guard rest > 0.0001 else { return }
        // Well clear of the outlet, so the grains do not roll straight back in.
        let x = max(1, min(size.x - 1, basin.outletX + basin.outward * 24))
        let top = bodies.first { $0.id == basin.wallID }.map { $0.contour(at: x) } ?? basin.level
        retainRelease(SnowRelease(position: SIMD2(x, max(1, top - 3)), height: 4, mass: rest), in: &snowReleases)
    }
}
