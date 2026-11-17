import Foundation

/// A falling raindrop, drawn as a streak along its velocity.
public struct Raindrop: Sendable {
    public var position: SIMD2<Float>
    public var velocity: SIMD2<Float>
    /// 0 (far, slow, faint) … 1 (near, fast, bright).
    var depth: Float
}

/// Water on the move: runoff sliding down a wall or falling, or a splash droplet.
public struct WaterDrip: Sendable {
    public var position: SIMD2<Float>
    public var velocity: SIMD2<Float>
    /// Water carried (pt²); zero for purely visual splash droplets.
    public var area: Float
    /// Screen y where the wall this drip slides down ends; nil while it falls freely.
    var slideUntil: Float?
    /// Remaining seconds (splash droplets only).
    var life: Float = 0
}

/// Rain: drops fill puddles on tops and the flood at the bottom; runoff becomes drips that slide
/// down walls and fall into the flood. All water is conserved until the flood reaches its cap.
extension SnowSimulation {
    public static let maximumDrips = 64
    static let maximumSplashes = 160
    /// The flood reaches its cap in about this long at Steady on an open desktop.
    static let rainFillSeconds: Float = 300
    static let minimumDropSpeed: Float = 450
    static let dropSpeedRange: Float = 300
    static let dripSlideSpeed: Float = 120
    static let waterGravity: Float = 900
    static let dropRipple: Float = -6
    static let dripRipple: Float = -24

    /// Water (pt²/s) the rain brings to the whole display.
    var rainFlux: Float { flood.cap * size.x / Self.rainFillSeconds * snowfall.density }

    /// Water each landing drop carries, so `rainFlux` arrives whatever the drop count: each drop
    /// lands once per fall of about (height − level + mean spawn height) at the mean speed.
    var rainAreaPerDrop: Float {
        guard !raindrops.isEmpty else { return 0 }
        let meanSpeed = Self.minimumDropSpeed + Self.dropSpeedRange / 2
        let travel = max(40, size.y - flood.level + 20)
        return rainFlux * travel / (Float(raindrops.count) * meanSpeed)
    }

    func stepRain(dt: Float) {
        updateFloodCap()
        let desired = reducedMotion ? 0 : min(budget.flakes,
            Int(Float(budget.flakes) * min(1, snowfall.density / Snowfall.flurry.density) * max(0, min(1, particleScale))))
        if raindrops.count > desired { raindrops.removeLast(raindrops.count - desired) }
        while raindrops.count < desired { raindrops.append(newRaindrop(scattered: true)) }
        if raindrops.isEmpty {
            rainAmbient(dt: dt)
        } else {
            let area = rainAreaPerDrop
            for i in raindrops.indices { advanceRaindrop(i, area: area, dt: dt) }
        }
        releaseRunoff()
        stepDrips(dt: dt)
        stepSplashes(dt: dt)
        flood.step(dt: dt)
    }

    /// The flood stops at the Dock tray's top; without a bottom Dock it uses the fallback cap.
    func updateFloodCap() {
        let dock = drifts.first { $0.surface.isDock && $0.surface.y > size.y * 0.5 }
        flood.cap = dock.map { max(0, size.y - $0.surface.y) } ?? FloodField.fallbackCap
    }

    func floodSurfaceY(at x: Float) -> Float {
        flood.surfaceY(at: max(0, min(size.x, x)), bottom: size.y)
    }

    private func newRaindrop(scattered: Bool) -> Raindrop {
        let depth = random.unit()
        var position = SIMD2(random.value(0, size.x), -random.value(0, 40))
        if !scattered, let entry = upwindEntry(radius: 1, fall: Self.minimumDropSpeed + Self.dropSpeedRange / 2) {
            position = entry
        } else if scattered {
            for _ in 0..<4 {
                let candidate = SIMD2(random.value(0, size.x), random.value(0, size.y))
                let occupied = bodyBuckets[bucket(at: candidate.x)].contains { bodies[$0].contains(candidate, padding: 2) }
                if !occupied && candidate.y < floodSurfaceY(at: candidate.x) { position = candidate; break }
            }
        }
        return Raindrop(position: position,
                        velocity: SIMD2(wind.velocity.x, Self.minimumDropSpeed + depth * Self.dropSpeedRange),
                        depth: depth)
    }

    private func advanceRaindrop(_ i: Int, area: Float, dt: Float) {
        var drop = raindrops[i]
        drop.velocity.x = wind.velocity.x
        let start = drop.position, end = start + drop.velocity * dt
        if let hit = rainTopHit(from: start, to: end, includeProps: true) {
            let drift = drifts[hit.index]
            if drift.surface.holdsWater {
                queueRunoff(drift.addWater(area: area, at: hit.localX), from: drift)
            } else {
                flood.add(area: area) // Props shed it; it reaches the flood behind them.
            }
            splash(at: hit.point)
            raindrops[i] = newRaindrop(scattered: false)
            return
        }
        switch rainWallHit(from: start, to: end) {
        case .wall(let point, let bottom):
            addDrip(at: point, area: area, slideUntil: bottom)
            raindrops[i] = newRaindrop(scattered: false)
            return
        case .hidden:
            flood.add(area: area)
            raindrops[i] = newRaindrop(scattered: false)
            return
        case .none:
            break
        }
        let surface = floodSurfaceY(at: end.x)
        if end.y >= surface {
            flood.add(area: area)
            flood.impulse(at: end.x, velocity: Self.dropRipple)
            splash(at: SIMD2(end.x, surface))
            raindrops[i] = newRaindrop(scattered: false)
            return
        }
        drop.position = end
        if drop.position.x < -8 { drop.position.x = size.x + 4 }
        if drop.position.x > size.x + 8 { drop.position.x = -4 }
        raindrops[i] = drop
    }

    /// Without visible drops (Reduce Motion) the same flux fills tops and the flood directly.
    private func rainAmbient(dt: Float) {
        let flux = rainFlux
        flood.add(area: flux * dt)
        for drift in drifts where holdsRain(drift.surface) {
            let area = flux / size.x * drift.exposedWidth * dt
            queueRunoff(drift.addWater(area: area, at: drift.surface.width / 2), from: drift)
        }
    }

    private func holdsRain(_ surface: Surface) -> Bool {
        surface.id != DesktopSceneBuilder.groundID && !surface.isElevated && surface.holdsWater
    }

    /// The first exposed top the segment crosses from above (snow surface included).
    func rainTopHit(from a: SIMD2<Float>, to b: SIMD2<Float>,
                    includeProps: Bool) -> (index: Int, localX: Float, point: SIMD2<Float>)? {
        guard b.y > a.y, !buckets.isEmpty else { return nil }
        var best: (index: Int, localX: Float, point: SIMD2<Float>)?
        var bestT = Float.infinity
        for k in bucket(at: min(a.x, b.x))...bucket(at: max(a.x, b.x)) {
            for index in buckets[k] {
                let drift = drifts[index], s = drift.surface
                guard s.id != DesktopSceneBuilder.groundID, !s.isElevated, includeProps || s.holdsWater else { continue }
                var t = (s.y - a.y) / (b.y - a.y)
                for _ in 0..<2 {
                    let x = a.x + (b.x - a.x) * max(0, min(1, t))
                    let local = max(0, min(s.width, x - s.x))
                    t = (s.baseY(at: local) - drift.height(at: local) - a.y) / (b.y - a.y)
                }
                guard t >= 0, t <= 1, t < bestT else { continue }
                let point = a + (b - a) * t
                let local = point.x - s.x
                guard local >= 0, local <= s.width, s.isExposed(at: local) else { continue }
                bestT = t
                best = (index, local, point)
            }
        }
        return best
    }

    enum WallContact { case wall(SIMD2<Float>, bottom: Float), hidden }

    /// A drop entering a window from the side becomes a drip on that wall; one that ends up inside
    /// a window any other way is hidden behind it.
    private func rainWallHit(from a: SIMD2<Float>, to b: SIMD2<Float>) -> WallContact? {
        for index in bodyBuckets[bucket(at: max(0, min(size.x, b.x)))] {
            let body = bodies[index]
            guard body.contains(b), !body.contains(a) else { continue }
            let minX = Float(body.bounds.minX), maxX = Float(body.bounds.maxX), maxY = Float(body.bounds.maxY)
            let side: Float? = a.x < minX ? minX : (a.x > maxX ? maxX : nil)
            guard let side, b.x != a.x else { return .hidden }
            let t = (side - a.x) / (b.x - a.x)
            let y = a.y + (b.y - a.y) * max(0, min(1, t))
            return .wall(SIMD2(side < (minX + maxX) / 2 ? minX - 1 : maxX + 1, y), bottom: maxY)
        }
        return nil
    }

    /// Queues water leaving `drift` at its ends; end runoff starts just outside the top.
    func queueRunoff(_ parts: [(localX: Float, area: Float)], from drift: SnowDrift) {
        let s = drift.surface
        for part in parts where part.area > 0 {
            let nudge: Float = part.localX <= 0.5 ? -1.5 : (part.localX >= s.width - 0.5 ? 1.5 : 0)
            pendingRunoff.append((SIMD2(s.x + part.localX + nudge, s.baseY(at: part.localX) - 1), part.area))
        }
    }

    /// Turns queued runoff into drips (sliding down the wall below when there is one). Without
    /// motion, or past the drip budget, the water goes straight to the flood.
    func releaseRunoff() {
        guard !pendingRunoff.isEmpty else { return }
        for (position, area) in pendingRunoff {
            if reducedMotion || weather == .snow {
                flood.add(area: area)
            } else {
                let wall = wallBelow(position)
                addDrip(at: wall.map { SIMD2($0.x, position.y) } ?? position, area: area, slideUntil: wall?.bottom)
            }
        }
        pendingRunoff.removeAll(keepingCapacity: true)
    }

    private func wallBelow(_ p: SIMD2<Float>) -> (x: Float, bottom: Float)? {
        for index in bodyBuckets[bucket(at: max(0, min(size.x, p.x)))] {
            let b = bodies[index].bounds
            let minX = Float(b.minX), maxX = Float(b.maxX)
            guard p.y >= Float(b.minY) - 3, p.y < Float(b.maxY) else { continue }
            if abs(p.x - minX) < 2.5 { return (minX - 1, Float(b.maxY)) }
            if abs(p.x - maxX) < 2.5 { return (maxX + 1, Float(b.maxY)) }
        }
        return nil
    }

    private func addDrip(at position: SIMD2<Float>, area: Float, slideUntil: Float?) {
        guard drips.count < Self.maximumDrips else { flood.add(area: area); return }
        drips.append(WaterDrip(position: position, velocity: SIMD2(0, Self.dripSlideSpeed), area: area,
                               slideUntil: slideUntil))
    }

    private func stepDrips(dt: Float) {
        guard !drips.isEmpty else { return }
        var kept: [WaterDrip] = []
        kept.reserveCapacity(drips.count)
        for var drip in drips {
            let start = drip.position
            if let bottom = drip.slideUntil, start.y < bottom {
                drip.velocity = SIMD2(0, Self.dripSlideSpeed)
            } else {
                drip.slideUntil = nil
                drip.velocity.y += Self.waterGravity * dt
            }
            let end = start + drip.velocity * dt
            if drip.slideUntil == nil, let hit = rainTopHit(from: start, to: end, includeProps: false) {
                let drift = drifts[hit.index]
                queueRunoff(drift.addWater(area: drip.area, at: hit.localX), from: drift)
                continue
            }
            let surface = floodSurfaceY(at: end.x)
            if end.y >= surface {
                flood.add(area: drip.area)
                flood.impulse(at: end.x, velocity: Self.dripRipple)
                splash(at: SIMD2(end.x, surface))
                continue
            }
            drip.position = end
            kept.append(drip)
        }
        drips = kept
    }

    /// 1–3 visual droplets thrown up where water lands.
    func splash(at point: SIMD2<Float>) {
        guard !reducedMotion else { return }
        let count = 1 + Int(random.unit() * 2.99)
        for _ in 0..<count where splashes.count < Self.maximumSplashes {
            splashes.append(WaterDrip(position: point,
                                      velocity: SIMD2(random.value(-70, 70), -random.value(60, 150)),
                                      area: 0, slideUntil: nil, life: random.value(0.15, 0.3)))
        }
    }

    private func stepSplashes(dt: Float) {
        guard !splashes.isEmpty else { return }
        for i in splashes.indices {
            splashes[i].life -= dt
            splashes[i].velocity.y += Self.waterGravity * dt
            splashes[i].position += splashes[i].velocity * dt
            guard splashes[i].area > 0 else { continue }
            // Thrown water returns to the flood where it comes down (or when it times out).
            let x = splashes[i].position.x
            if (splashes[i].velocity.y > 0 && splashes[i].position.y >= floodSurfaceY(at: x)) || splashes[i].life <= 0 {
                flood.add(area: splashes[i].area)
                flood.impulse(at: max(0, min(size.x, x)), velocity: Self.dropRipple * 2)
                splashes[i].area = 0
                splashes[i].life = 0
            }
        }
        splashes.removeAll { $0.life <= 0 }
    }

    // MARK: Interaction

    static let wakeHalfWidth: Float = 24
    static let wakeStrength: Float = 0.05

    /// The pointer moving below the water line pushes the surface (down ahead, up behind); a fast
    /// stroke throws water up and forward. Brushing a top pushes its puddle off the stroke's end.
    func stirWater(from start: SIMD2<Float>, to end: SIMD2<Float>, dt: Float) {
        let delta = end - start
        guard abs(delta.x) > 0.25, dt > 0 else { return }
        let speed = min(1_200, hypot(delta.x, delta.y) / dt)
        let direction: Float = delta.x > 0 ? 1 : -1
        let fast = speed >= Self.flingSpeed
        if end.y > floodSurfaceY(at: end.x) {
            let push = speed * Self.wakeStrength * dt * 60 * (tool == .shovel ? 2 : 1)
            flood.impulse(from: end.x, to: end.x + direction * Self.wakeHalfWidth, velocity: -push)
            flood.impulse(from: end.x - direction * Self.wakeHalfWidth, to: end.x, velocity: push)
            if fast {
                throwWater(flood.take(area: 30), from: end, direction: direction, speed: speed)
            }
        }
        let radius = tool.radius
        for drift in drifts where drift.puddle > 0.0001 {
            let s = drift.surface
            guard max(start.x, end.x) + radius >= s.x, min(start.x, end.x) - radius <= s.x + s.width,
                  max(start.y, end.y) + radius >= s.y - 4, min(start.y, end.y) - radius <= s.y + 4 else { continue }
            // Surface tension: once the glove sets part of the puddle moving, the rest follows.
            let area = drift.removeWater(drift.puddleArea)
            guard area > 0 else { continue }
            if fast {
                throwWater(area, from: SIMD2(max(s.x, min(s.x + s.width, end.x)), s.y - 2), direction: direction, speed: speed)
            } else {
                queueRunoff([(direction > 0 ? s.width : 0, area)], from: drift)
            }
        }
    }

    /// Splash droplets carrying `area` pt² of water, flung along the stroke with some lift.
    private func throwWater(_ area: Float, from point: SIMD2<Float>, direction: Float, speed: Float) {
        guard area > 0 else { return }
        let count = 5
        let room = max(0, Self.maximumSplashes - splashes.count)
        guard room > 0 else { flood.add(area: area); return }
        let n = min(count, room)
        for _ in 0..<n {
            let velocity = SIMD2(direction * min(500, speed * 0.5) + random.value(-60, 60), -random.value(160, 280))
            splashes.append(WaterDrip(position: point, velocity: velocity, area: area / Float(n),
                                      slideUntil: nil, life: 4))
        }
    }

    /// A window moving in the flood pushes a wave from its leading side; one lowered into it
    /// raises a bow wave on both sides. Water volume is unchanged.
    func pushFlood(with motion: BodyMotion) {
        let old = motion.old.bounds, new = motion.new.bounds
        let waterLine = size.y - flood.level
        guard flood.level > 0.5, Float(new.maxY) > waterLine || Float(old.maxY) > waterLine else { return }
        let dx = Float(new.minX - old.minX), dy = Float(new.maxY - old.maxY)
        let reach: Float = 30
        if abs(dx) > 0.5 {
            let direction: Float = dx > 0 ? 1 : -1
            let strength = min(240, abs(dx) * 3)
            let lead = Float(dx > 0 ? new.maxX : new.minX), trail = Float(dx > 0 ? new.minX : new.maxX)
            flood.impulse(from: lead, to: lead + direction * reach, velocity: strength)
            flood.impulse(from: trail - direction * reach, to: trail, velocity: -strength)
        }
        if dy > 0.5, Float(new.maxY) > waterLine {
            let strength = min(240, dy * 3)
            flood.impulse(from: Float(new.minX) - reach, to: Float(new.minX), velocity: strength)
            flood.impulse(from: Float(new.maxX), to: Float(new.maxX) + reach, velocity: strength)
        }
    }

    /// Streaks for drops, drips and splash droplets, in that order.
    public func streakInstances() -> [StreakInstance] {
        var out: [StreakInstance] = []
        out.reserveCapacity(raindrops.count + drips.count + splashes.count)
        for drop in raindrops {
            let v = drop.velocity
            let speed = max(1, (v.x * v.x + v.y * v.y).squareRoot())
            let length = 8 + 12 * drop.depth
            out.append(StreakInstance(position: drop.position, vector: v / speed * length,
                                      width: 1 + 0.5 * drop.depth, opacity: 0.35 + 0.35 * drop.depth))
        }
        for drip in drips {
            out.append(StreakInstance(position: drip.position, vector: SIMD2(0, 6), width: 1.6, opacity: 0.6))
        }
        for splash in splashes {
            out.append(StreakInstance(position: splash.position, vector: splash.velocity * 0.02, width: 1,
                                      opacity: 0.5 * min(1, splash.life / 0.15)))
        }
        return out
    }
}
