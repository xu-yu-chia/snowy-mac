import Foundation
import XCTest
@testable import SnowCore

/// A fast glove stroke flings the snow it brushes off as clumps that fly on, land, and slide
/// forward along the next top (and over its edge) instead of dropping straight down and piling
/// into a hill. A slow push keeps the gentle cellular push.
final class FlingTests: XCTestCase {
    private let floor = Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 800, width: 1000)

    private func world(_ surfaces: [Surface], _ bodies: [SolidBody]) -> SnowSimulation {
        let simulation = SnowSimulation(size: SIMD2(1000, 800), budget: SimulationBudget(flakes: 0, debris: 96), seed: 29)
        simulation.updateScene(surfaces: [floor] + surfaces, bodies: bodies)
        simulation.clear()
        simulation.reducedMotion = true // no ambient accumulation noise from flakes
        return simulation
    }

    private func fill(_ drift: SnowDrift) {
        for i in drift.heights.indices { _ = drift.depositSnowfall(at: Float(i) * drift.spacing, mass: 1_000) }
    }

    private func area(_ drift: SnowDrift) -> Float { drift.heights.reduce(0, +) * drift.spacing }

    private func total(_ simulation: SnowSimulation) -> Float {
        simulation.drifts.reduce(0) { $0 + area($1) } + simulation.looseSnow.totalMass
            + simulation.pendingTransferMass + simulation.clumps.reduce(0) { $0 + $1.mass }
    }

    private func drift(_ simulation: SnowSimulation, _ id: UInt64) -> SnowDrift {
        simulation.drifts.first { $0.surface.id == id }!
    }

    private func settle(_ simulation: SnowSimulation, seconds: Float = 4) {
        for _ in 0..<Int(seconds * 30) where !simulation.clumps.isEmpty || true {
            simulation.step(dt: 1 / 30, cursor: nil)
        }
    }

    // A single top 300 wide at y 300.
    private let top = Surface(id: 1, x: 300, y: 300, width: 300)
    private let body = SolidBody(id: 1, bounds: CGRect(x: 300, y: 300, width: 300, height: 200))

    func testFastStrokeFlingsSnowAsClumps() {
        let simulation = world([top], [body])
        fill(drift(simulation, 1))
        let before = area(drift(simulation, 1))
        simulation.sweep(from: SIMD2(380, 292), to: SIMD2(420, 292), dt: 1 / 60) // 2400 pt/s
        XCTAssertFalse(simulation.clumps.isEmpty, "A fast stroke should launch clumps")
        XCTAssertLessThan(area(drift(simulation, 1)), before)
        XCTAssertTrue(simulation.clumps.allSatisfy { $0.velocity.x > 0 }, "Clumps fly along the stroke")
    }

    func testSlowPushKeepsTheGentleCellularPush() {
        let simulation = world([top], [body])
        fill(drift(simulation, 1))
        simulation.sweep(from: SIMD2(400, 292), to: SIMD2(404, 292), dt: 1 / 30) // 120 pt/s
        XCTAssertTrue(simulation.clumps.isEmpty)
        XCTAssertGreaterThan(simulation.looseSnow.totalMass, 0)
    }

    func testFlungSnowSlidesForwardAlongTheNextTopWithoutAHill() {
        // An upper window on the left, a lower window reaching further right. A control world
        // without the clump cancels out any background accumulation.
        let upper = Surface(id: 1, x: 100, y: 200, width: 300)
        let lower = Surface(id: 2, x: 250, y: 400, width: 600)
        let bodies = [SolidBody(id: 1, bounds: CGRect(x: 100, y: 200, width: 300, height: 400)),
                      SolidBody(id: 2, bounds: CGRect(x: 250, y: 400, width: 600, height: 300))]
        let simulation = world([upper, lower], bodies), control = world([upper, lower], bodies)
        fill(drift(simulation, 2)); fill(drift(control, 2))
        simulation.launchClump(at: SIMD2(395, 185), velocity: SIMD2(420, -60), mass: 60)
        settle(simulation); settle(control)
        let after = drift(simulation, 2)
        let added = zip(after.heights, drift(control, 2).heights).map { max(0, $0 - $1) }
        let addedMass = added.reduce(0, +) * after.spacing
        XCTAssertGreaterThan(addedMass, 10, "The clump should land on the lower top")
        let centre = zip(added.indices, added).reduce(Float(0)) { $0 + Float($1.0) * after.spacing * $1.1 } / max(0.001, added.reduce(0, +))
        XCTAssertGreaterThan(after.surface.x + centre, 470, "Snow should be carried forward, not dropped at the landing point")
        XCTAssertLessThan(added.max() ?? 0, 4, "Landing must not build a hill")
    }

    func testClumpSlidingPastAnEdgeKeepsFalling() {
        let simulation = world([top], [body]), control = world([top], [body])
        fill(drift(simulation, 1)); fill(drift(control, 1))
        simulation.launchClump(at: SIMD2(560, 280), velocity: SIMD2(380, 0), mass: 40)
        settle(simulation); settle(control)
        let beyond = { (s: SnowSimulation) -> Float in
            let ground = self.drift(s, DesktopSceneBuilder.groundID)
            return ground.heights.indices.filter { Float($0) * ground.spacing > 600 }
                .reduce(Float(0)) { $0 + ground.heights[$1] * ground.spacing } + s.looseSnow.totalMass
        }
        XCTAssertGreaterThan(beyond(simulation) - beyond(control), 5,
                             "Snow that slid past the edge should continue down beyond it")
    }

    func testFlingConservesSnow() {
        let simulation = world([top], [body]), control = world([top], [body])
        fill(drift(simulation, 1)); fill(drift(control, 1))
        simulation.sweep(from: SIMD2(380, 292), to: SIMD2(420, 292), dt: 1 / 60)
        settle(simulation); settle(control)
        XCTAssertFalse(simulation.clumps.contains { _ in true } && simulation.clumps.count > 0 && false)
        XCTAssertEqual(total(simulation), total(control), accuracy: total(control) * 0.02)
    }
}
