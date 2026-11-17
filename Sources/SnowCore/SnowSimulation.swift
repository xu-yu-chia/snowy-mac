import Foundation

public final class SnowSimulation {
    public let size: SIMD2<Float>
    public let budget: SimulationBudget
    public internal(set) var flakes: [SnowParticle] = []
    public internal(set) var looseSnow: GranularSnow
    var contour: GranularContour
    public internal(set) var drifts: [SnowDrift] = []
    public internal(set) var mesh: [SnowVertex] = []
    public internal(set) var elevatedMeshRanges: [Range<Int>] = []
    public internal(set) var meshRevision: UInt64 = 0
    public var snowfall: Snowfall = .steady
    public var melting: Melting = .off
    public var grainSize: GrainSize = .normal {
        didSet { if grainSize != oldValue { rebuildGranularField() } }
    }
    static let accumulationPace: Float = 0.3
    /// Mean ambient deposition (pt/s at full taper) and mean flake mass (radius² · 0.45 over a
    /// uniform depth), used to convert the ambient rate into snow carried per landing flake.
    static let meanDeposition: Float = 0.296
    static let meanFlakeMass: Float = 0.859
    /// Area (square points) each landing flake leaves, per unit of its own mass.
    var flakeMassScale: Float = 0
    /// Snow flung by a fast glove stroke, in flight. Each carries real area (`mass`).
    public internal(set) var clumps: [SnowParticle] = []
    public static let maximumClumps = 96

    /// Glove strokes faster than this (pt/s) fling the snow they brush off.
    static let flingSpeed: Float = 450

    /// Starts a clump in flight. When too many are already flying, the area joins the granular
    /// field instead, so nothing is lost.
    func launchClump(at position: SIMD2<Float>, velocity: SIMD2<Float>, mass: Float) {
        guard mass > 0.0001, position.x.isFinite, position.y.isFinite else { return }
        guard clumps.count < Self.maximumClumps else {
            let rest = looseSnow.add(mass: mass, at: position, direction: velocity)
            if rest > 0.0001 { retainRelease(SnowRelease(position: position, height: 4, mass: rest), in: &snowReleases) }
            return
        }
        clumps.append(SnowParticle(position: position, velocity: velocity,
                                   radius: max(1.6, min(4, sqrt(mass) * 0.55)), opacity: 0.95,
                                   phase: 0, remainingLife: 3, mass: mass))
    }

    /// Flies clumps under gravity and light drag. A clump that lands slides on along the top it
    /// hit (see `depositSliding`); one that runs out of time or leaves the screen settles into
    /// the granular field where it is.
    func stepClumps(dt: Float) {
        guard !clumps.isEmpty else { return }
        var flying: [SnowParticle] = []
        flying.reserveCapacity(clumps.count)
        for var clump in clumps {
            clump.velocity.y += 900 * dt
            clump.velocity *= max(0, 1 - 0.6 * dt)
            clump.remainingLife -= dt
            let landed = advanceParticle(&clump, dt: dt, slides: true)
            if landed || clump.mass <= 0.0001 { continue }
            let outside = clump.position.y > size.y + 4 || clump.position.x < -8 || clump.position.x > size.x + 8
            if clump.remainingLife <= 0 || outside {
                let point = SIMD2(max(1, min(size.x - 1, clump.position.x)), max(1, min(size.y - 1, clump.position.y)))
                let rest = looseSnow.add(mass: clump.mass, at: point)
                if rest > 0.0001 { retainRelease(SnowRelease(position: point, height: 4, mass: rest), in: &snowReleases) }
                continue
            }
            flying.append(clump)
        }
        clumps = flying
        meshDirty = true
    }

    /// Chosen so landed flakes build piles at the ambient mean rate whatever the flake count:
    /// rate · width · height / (flakes · mean fall speed · mean flake mass).
    func updateFlakeMassScale() {
        guard !flakes.isEmpty else { flakeMassScale = 0; return }
        let target = Self.meanDeposition * snowfall.density * Self.accumulationPace
        let fall = max(5, 41.5 + wind.velocity.y * 0.35)
        flakeMassScale = target * size.x * size.y / (Float(flakes.count) * fall * Self.meanFlakeMass)
    }
    public var reducedMotion = false
    public var particleScale: Float = 1
    public var wind = WindSettings() {
        didSet { if wind != oldValue { cornerWindDirty = true } }
    }
    public var tool: SnowTool = .glove

    // Shared only by SnowCore implementation extensions; none of this state is public.
    var random: RandomSource
    private var previousCursor: SIMD2<Float>?
    var buckets: [[Int]]
    var bodyBuckets: [[Int]]
    var bodies: [SolidBody] = []
    let bucketWidth: Float = 96
    var meshDirty = true
    var interactionDirty = false
    var geometryAge: Float = 0
    private var settleAge: Float = 0
    private var elapsed: Float = 0
    var lastSurfaces: [Surface] = []
    var pendingAppearances: [SolidBody] = []
    var batchingScene = false
    /// False while applying a scene whose motion came from the system (minimize, tiling,
    /// app-driven moves) rather than a pointer drag.
    var ploughsSupportedSnow = true
    struct SupportTransfer {
        var targetID: UInt64
        var x: Float
        var baseY: Float
        var mass: Float
    }
    var supportTransfers: [SupportTransfer] = []
    struct SnowRelease {
        var position: SIMD2<Float>
        var height: Float
        var mass: Float
    }
    var snowReleases: [SnowRelease] = []
    /// Rain water that left a top (overflow, a moved or closed window) and still has to fall.
    var pendingRunoff: [(position: SIMD2<Float>, area: Float)] = []
    var carriedContacts: [SnowRelease] = []
    var releaseScratch: [SnowRelease] = []
    var releaseIntervals: [Span] = []
    var intervalScratch: [Span] = []
    public var pendingTransferMass: Float {
        supportTransfers.reduce(0) { $0 + $1.mass } + snowReleases.reduce(0) { $0 + $1.mass }
            + carriedContacts.reduce(0) { $0 + $1.mass }
    }
    var cornerWindDirty = true

    public init(size: SIMD2<Float>, budget: SimulationBudget = SimulationBudget(), seed: UInt64 = 1) {
        let width = size.x.isFinite ? max(1, min(65_536, size.x)) : 1
        let height = size.y.isFinite ? max(1, min(65_536, size.y)) : 1
        self.size = SIMD2(width, height)
        self.budget = budget
        let field = GranularSnow(size: SIMD2(width, height), maxCells: budget.cells * 32,
                                maxActive: budget.maximumGranules)
        looseSnow = field
        contour = GranularContour(field: field)
        random = RandomSource(seed: seed)
        buckets = Array(repeating: [], count: max(1, Int(ceil(width / bucketWidth))))
        bodyBuckets = Array(repeating: [], count: buckets.count)
        flakes.reserveCapacity(budget.flakes)
        mesh.reserveCapacity(budget.maximumSnowVertices)
        elevatedMeshRanges.reserveCapacity(budget.surfaces)
        supportTransfers.reserveCapacity(budget.cells)
        snowReleases.reserveCapacity(budget.cells)
        carriedContacts.reserveCapacity(budget.cells)
        releaseScratch.reserveCapacity(budget.cells)
        releaseIntervals.reserveCapacity(DesktopSceneBuilder.maximumBodies + 1)
        intervalScratch.reserveCapacity(DesktopSceneBuilder.maximumBodies + 1)
    }

    public func resetPointer() { previousCursor = nil }

    public func clear() {
        for drift in drifts { drift.clear() }
        looseSnow.clear()
        supportTransfers.removeAll(keepingCapacity: true)
        snowReleases.removeAll(keepingCapacity: true)
        carriedContacts.removeAll(keepingCapacity: true)
        releaseScratch.removeAll(keepingCapacity: true)
        meshDirty = true
        resetPointer()
        if !batchingScene { rebuildMesh() }
    }

    /// Attached supports move first; then their boundaries displace the surrounding snow.
    public func updateScene(surfaces: [Surface], bodies: [SolidBody], userMotion: Bool = true) {
        looseSnow.beginFrame()
        batchingScene = true
        pendingAppearances.removeAll(keepingCapacity: true)
        let motions = persistentBodyMotions(to: bodies)
        // Window and widget snow is no longer carried along with its support (see `SnowDrift.carry`),
        // so there is no carried cap to hand over or scrape; a moving window only ploughs
        // the snow it runs into (below, and only for pointer drags).
        _ = motions
        updateSurfaces(surfaces, windBodies: bodies)
        ploughsSupportedSnow = userMotion
        updateBodies(bodies)
        ploughsSupportedSnow = true
        refreshCornerWind()
        applySupportTransfers()
        // Contacts were captured before attachment transforms. Insert them only after
        // boundary pushes, so their carrier cannot sweep the detached material twice.
        if !carriedContacts.isEmpty {
            for release in carriedContacts { retainRelease(release, in: &snowReleases) }
            carriedContacts.removeAll(keepingCapacity: true)
            eraseReleasedSnow(inside: pendingAppearances)
        }
        applySnowReleases()
        batchingScene = false
        rebuildMesh()
    }

    public func step(dt rawDT: Float, cursor: SIMD2<Float>?) {
        guard rawDT.isFinite, rawDT > 0 else { return }
        looseSnow.beginFrame()
        refreshCornerWind()
        applySupportTransfers()
        applySnowReleases()
        let dt = min(rawDT, 0.05) // Never catch up a backlog after sleep, stalls, or resizing.
        elapsed += dt
        geometryAge += dt
        settleAge += dt
        if let cursor, cursor.x.isFinite, cursor.y.isFinite {
            if tool == .shovel {
                sweep(from: rawDT < 0.2 ? (previousCursor ?? cursor) : cursor, to: cursor, dt: dt)
            } else if rawDT < 0.2, let previousCursor {
                let delta = cursor - previousCursor
                if delta.x * delta.x + delta.y * delta.y > 0.25 {
                    sweep(from: previousCursor, to: cursor, dt: dt)
                }
            }
            previousCursor = cursor
        } else { previousCursor = nil }

        // Settled snow is built by the flakes that actually land (see `flakeMassScale`), so it only
        // grows where snow can fall. Without visible flakes (Reduce Motion) the ambient rate keeps
        // snow settling. Either way a Steady cap takes minutes, not ~40 s, to fill.
        if flakes.isEmpty {
            for drift in drifts { drift.accumulate(dt: dt, intensity: snowfall.density * Self.accumulationPace) }
        }
        if melting.rate > 0 {
            for drift in drifts { drift.melt(fraction: melting.rate * dt) }
            meshDirty = true
        }
        if settleAge >= 0.1 {
            for drift in drifts { drift.settle() }
            shedOverloadedCaps()
            settleAge = 0
            meshDirty = true
        }
        let desired = reducedMotion ? 0 : min(budget.flakes,
            Int(Float(budget.flakes) * min(1, snowfall.density / Snowfall.flurry.density) * max(0, min(1, particleScale))))
        if flakes.count > desired { flakes.removeLast(flakes.count - desired) }
        while flakes.count < desired { flakes.append(newFlake(scattered: true)) }
        updateFlakeMassScale()

        let wind = sin(elapsed * 0.23) * 7 + sin(elapsed * 0.071) * 5
        for i in flakes.indices {
            var particle = flakes[i]
            particle.phase += dt * 0.8
            if particle.phase > .pi * 2 { particle.phase -= .pi * 2 }
            let gust = SIMD2(wind + sin(particle.phase) * 9 + self.wind.velocity.x,
                             self.wind.velocity.y * 0.35)
            let wasSliding = particle.isSliding
            let free = particle.velocity
            particle.isSliding = false
            particle.velocity += gust
            let deposited = advanceParticle(&particle, dt: dt, recycleOnContact: true)
            particle.velocity -= gust
            if particle.isSliding {
                // Remember the free-fall velocity from before the wall, not the cling state.
                if !wasSliding { particle.freeVelocity = free }
                // Keep the horizontal drift so the wind keeps pressing the flake to the wall
                // next frame; only the vertical speed is the slower slide.
                particle.velocity.x = (particle.freeVelocity ?? free).x
            } else if wasSliding, let resume = particle.freeVelocity {
                // Past the wall's end (or blown off it): fall and drift with the wind again.
                particle.velocity = resume
                particle.freeVelocity = nil
            }
            if deposited || particle.position.y > size.y + 8 || particle.position.y < -40 {
                particle = newFlake(scattered: false)
            }
            if particle.position.x < -8 { particle.position.x = size.x + 4 }
            if particle.position.x > size.x + 8 { particle.position.x = -4 }
            flakes[i] = particle
        }
        stepClumps(dt: dt)
        let looseRevision = looseSnow.revision
        looseSnow.step(dt: dt, wind: self.wind.velocity) { [unowned self] from, to, mass in
            self.landGranularSnow(from: from, to: to, mass: mass)
        }
        if tool == .shovel, let cursor {
            sweep(from: cursor, to: cursor, dt: dt)
        }
        if looseRevision != looseSnow.revision { meshDirty = true; interactionDirty = true }
        if meshDirty && (geometryAge >= 0.1 || interactionDirty) { rebuildMesh() }
    }

}
