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
        /// Neighbouring members (indices into `members`) that trade snow by surface height.
        var pairs: [(Int, Int)] = []
        /// The outlet wall's first sample past the basin, which trades snow with `edgeMember`.
        var outletSample: (drift: SnowDrift, index: Int)?
        var edgeMember: Int?
        /// Snow waiting to fill the basin or leave by the outlet (pt²).
        var pending: Float = 0
    }

    struct BasinKey: Equatable {
        var bodies: [SolidBody]
        var drifts: [ObjectIdentifier]
        var surfaces: [Surface]
    }

    static let terrainStep: Float = 2
    /// Wider hollows are no container: snow does not fill a broad stretch between distant walls.
    static let maximumBasinWidth: Float = 160
    static let basinCap: Float = 18

    /// Rebuilds basins when the scene changes. Snow on samples leaving a basin that no longer
    /// fits an ordinary cap falls from there as loose snow (never deleted).
    func refreshBasins() {
        // Wind changes refresh corner wind too; basins only depend on geometry.
        let key = BasinKey(bodies: bodies, drifts: drifts.map { ObjectIdentifier($0) }, surfaces: drifts.map(\.surface))
        guard key != basinKey else { return }
        basinKey = key
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
            // Sealed only if every window shaping the hollow (its walls and any higher floor)
            // reaches down to its deepest floor; otherwise snow leaks out sideways underneath,
            // as from a slit between two widgets above a lower one.
            let deepest = (c...b).map { terrain[$0] }.max() ?? level
            let shaping = Set((c - 1...b + 1).compactMap { k -> UInt64? in
                guard let id = owner[k], terrain[k] < deepest - 1 else { return nil }
                return id
            })
            guard shaping.allSatisfy({ id in walls.first(where: { $0.id == id }).map { Float($0.bounds.maxY) >= deepest - 1 } ?? false })
            else { continue }
            let towardRight = abs(terrain[b + 1] - level) <= abs(terrain[c - 1] - level)
            basins.append(Basin(level: level, wallID: towardRight ? rightID : leftID, outward: towardRight ? 1 : -1,
                                outletX: towardRight ? Float(b + 1) * step : Float(c) * step))
            for k in c...b { basinOfColumn[k] = basins.count - 1 }
        }
        for drift in drifts {
            var membership = [Int?](repeating: nil, count: drift.heights.count)
            var depths = [Float](repeating: 0, count: drift.heights.count)
            if drift.surface.id != DesktopSceneBuilder.groundID, !drift.surface.isDock, !drift.surface.isElevated {
                for i in drift.heights.indices where drift.surface.isExposed(at: Float(i) * drift.spacing) {
                    let local = Float(i) * drift.spacing
                    let x = drift.surface.x + local
                    let column = max(0, min(columns - 1, Int(x / step)))
                    guard let index = basinOfColumn[column] else { continue }
                    let floorY = drift.surface.baseY(at: local)
                    // Another window above this spot roofs it only if it rises above the level;
                    // one below the level is just another floor of the same basin.
                    let level = basins[index].level
                    // Only the hollow's own floor: the topmost outline here, or a rounded corner
                    // dipping just under it, never a window far below at the same x.
                    guard floorY > level + 0.5, floorY <= terrain[column] + drift.surface.cornerRadius + 1,
                          !walls.contains(where: { $0.id != drift.surface.id && x >= Float($0.bounds.minX)
                              && x < Float($0.bounds.maxX) && $0.contour(at: x) < floorY - 0.5 && $0.contour(at: x) <= level + 0.5 })
                    else { continue }
                    membership[i] = index
                    depths[i] = floorY - level
                    basins[index].members.append((drift, i, floorY, x))
                }
            }
            drift.setBasins(membership, depths: depths)
        }
        for b in basins.indices {
            let order = basins[b].members.indices.sorted { basins[b].members[$0].x < basins[b].members[$1].x }
            for (p, q) in zip(order, order.dropFirst()) {
                let a = basins[b].members[p], c = basins[b].members[q]
                if c.x - a.x <= max(a.drift.spacing, c.drift.spacing) + 1 { basins[b].pairs.append((p, q)) }
            }
            // The outlet wall's first non-basin sample trades with the member nearest the outlet.
            let basin = basins[b]
            // The member nearest the outlet is the basin's open edge, with or without a snow top
            // on the outlet window to trade with.
            basins[b].edgeMember = basin.members.indices.min { abs(basin.members[$0].x - basin.outletX) < abs(basin.members[$1].x - basin.outletX) }
            if let wall = drifts.first(where: { $0.surface.id == basin.wallID }),
               let edge = basins[b].edgeMember {
                var index = max(0, min(wall.heights.count - 1, Int(((basin.outletX - wall.surface.x) / wall.spacing).rounded())))
                while wall.heights.indices.contains(index), wall.basin(at: index) != nil { index += basin.outward > 0 ? 1 : -1 }
                if wall.heights.indices.contains(index), abs(wall.surface.x + Float(index) * wall.spacing - basin.members[edge].x) < 3 * wall.spacing + 1 {
                    basins[b].outletSample = (wall, index)
                    basins[b].edgeMember = edge
                }
            }
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

    /// Share of the surface difference two neighbouring basin samples even out per second, so
    /// a dug hole flows level over a few seconds.
    static let basinFlowPerSecond: Float = 6
    /// Fastest a basin's waiting snow leaves by its outlet (pt² per second).
    static let basinOutflowPerSecond: Float = 600

    /// Every settle: snow above a basin sample's limit joins the basin's waiting snow; neighbours
    /// trade snow by surface height (also across windows and with the outlet's top), the waiting
    /// snow tops up the lowest spots, and the rest leaves by the outlet. A full basin trickles a
    /// little off at its outlet like any full top sheds at its edge.
    func settleBasins(interval: Float) {
        let share = min(0.5, Self.basinFlowPerSecond * interval)
        for b in basins.indices where !basins[b].members.isEmpty {
            let members = basins[b].members
            // A full basin is an ordinary top: snow above its limit stays on it as overload,
            // slumps (below) and leaves only over its one open edge, the outlet, a little each
            // settle, as overload creeps off any top's edge.
            if let edge = basins[b].edgeMember {
                let m = members[edge]
                let over = m.drift.heights[m.index] - m.drift.capacity(at: m.index)
                if over > 0.0001 {
                    m.drift.heights[m.index] -= over * 0.3
                    basins[b].pending += over * 0.3 * m.drift.spacing
                }
            }
            // Snow flows into the hollow below the outlet level (a dug hole, an unfilled floor);
            // above that level a basin is an ordinary top and its cap is left to build naturally.
            func fillRoom(_ d: SnowDrift, _ k: Int) -> Float {
                d.basin(at: k) != nil ? max(0, (d.basinDepth.indices.contains(k) ? d.basinDepth[k] : 0) - d.heights[k])
                                      : max(0, d.capacity(at: k) - d.heights[k])
            }
            func trade(_ a: SnowDrift, _ i: Int, _ c: SnowDrift, _ j: Int) {
                let topA = a.surface.baseY(at: Float(i) * a.spacing) - a.heights[i]
                let topC = c.surface.baseY(at: Float(j) * c.spacing) - c.heights[j]
                let difference = topC - topA
                guard abs(difference) > 0.05 else { return }
                let (from, f, to, t) = difference > 0 ? (a, i, c, j) : (c, j, a, i)
                let width = min(from.spacing, to.spacing)
                // Into a spot below the outlet level snow pours quickly; above it, the cap settles
                // like any top's (12% of the step per settle, up to the spot's own limit).
                let filling = fillRoom(to, t) > 0.01 && to.basin(at: t) != nil
                let rate = filling ? share : 0.12
                let room = filling ? fillRoom(to, t) : max(0, to.capacity(at: t) - to.heights[t])
                var area = min(abs(difference) * 0.5 * rate * width, from.heights[f] * from.spacing, room * to.spacing)
                // A step steeper than the angle of repose slumps right away, also across a seam
                // between windows and onto or off the outlet's top.
                let repose = SnowDrift.reposeSlope * width
                if abs(difference) > repose {
                    area = max(area, min(from.heights[f] * from.spacing, (abs(difference) - repose) * 0.5 * width))
                }
                guard area > 0 else { return }
                from.heights[f] -= area / from.spacing
                to.heights[t] += area / to.spacing
            }
            for (p, q) in basins[b].pairs { trade(members[p].drift, members[p].index, members[q].drift, members[q].index) }
            if let outlet = basins[b].outletSample, let edge = basins[b].edgeMember {
                trade(members[edge].drift, members[edge].index, outlet.drift, outlet.index)
            }
            // A full basin trickles off at its outlet, as a full top sheds at its edge.
            let held = members.reduce(Float(0)) { $0 + $1.drift.heights[$1.index] * $1.drift.spacing }
            let room = members.reduce(Float(0)) { $0 + $1.drift.capacity(at: $1.index) * $1.drift.spacing }
            if room > 0, held / room >= 0.95, let edge = basins[b].edgeMember {
                let m = members[edge]
                let cap = max(0, m.drift.heights[m.index] - (m.drift.capacity(at: m.index) - Self.basinCapLayer(m.drift, m.index)))
                let trickle = cap * 0.05
                m.drift.heights[m.index] -= trickle
                basins[b].pending += trickle * m.drift.spacing
            }
            // Waiting snow tops up spots below the outlet level, lowest first and gradually (a
            // freshly dug hole stays a hole for a moment).
            if basins[b].pending > 0.0001 {
                for m in members.sorted(by: { $0.drift.surface.baseY(at: Float($0.index) * $0.drift.spacing) - $0.drift.heights[$0.index]
                                               > $1.drift.surface.baseY(at: Float($1.index) * $1.drift.spacing) - $1.drift.heights[$1.index] }) {
                    let room = fillRoom(m.drift, m.index) * share * m.drift.spacing
                    let add = min(room, basins[b].pending)
                    m.drift.heights[m.index] += add / m.drift.spacing
                    basins[b].pending -= add
                    if basins[b].pending <= 0.0001 { break }
                }
            }
            let leaving = min(basins[b].pending, Self.basinOutflowPerSecond * interval)
            if leaving > 0.0001 {
                basins[b].pending -= leaving
                release(overflow: leaving, from: basins[b])
            }
        }
        if !basins.isEmpty { meshDirty = true }
    }

    /// The ordinary-cap part of a basin sample's limit.
    static func basinCapLayer(_ drift: SnowDrift, _ i: Int) -> Float {
        drift.capacity(at: i) - (drift.basinDepth.indices.contains(i) ? drift.basinDepth[i] : 0)
    }

    /// Lands overflow on the outlet window's top, just outside the basin; what it cannot hold
    /// falls from there as loose snow. Nothing is deleted.
    private func release(overflow mass: Float, from basin: Basin) {
        var rest = mass
        if let wall = drifts.first(where: { $0.surface.id == basin.wallID }) {
            // The first sample past the outlet that is not part of any basin (a rounded outlet
            // corner is itself in the basin).
            var index = max(0, min(wall.heights.count - 1, Int(((basin.outletX - wall.surface.x) / wall.spacing).rounded())))
            while wall.heights.indices.contains(index), wall.basin(at: index) != nil { index += basin.outward > 0 ? 1 : -1 }
            if wall.heights.indices.contains(index) {
                let local = Float(index) * wall.spacing
                rest = wall.depositMass(at: local, mass: rest, direction: basin.outward)
                // Extra snow joins the wall top's overload a little further out, and only if that
                // top can shed it at an end that is not an outlet.
                let further = max(0, min(wall.surface.width, local + basin.outward * 3 * wall.spacing))
                if rest > 0.0001, wall.hasOpenExit(at: further) {
                    wall.addOverload(at: further, mass: rest)
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
