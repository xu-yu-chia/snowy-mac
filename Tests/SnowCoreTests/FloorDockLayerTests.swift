import Foundation
import XCTest
@testable import SnowCore

/// Loose snow (shed off windows or pushed by the glove) that lands on a full floor or a full Dock
/// ridge joins that pile instead of sitting on it as a separate layer.
final class FloorDockLayerTests: XCTestCase {
    private let floor = Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 800, width: 1000)
    private let dock = Surface(id: 9, x: 300, y: 740, width: 400, isDock: true)
    private let dockBody = SolidBody(id: 9, bounds: CGRect(x: 300, y: 740, width: 400, height: 60))

    private func world() -> SnowSimulation {
        let simulation = SnowSimulation(size: SIMD2(1000, 800), budget: SimulationBudget(flakes: 0, debris: 96), seed: 31)
        simulation.updateScene(surfaces: [floor, dock], bodies: [dockBody])
        simulation.clear()
        simulation.snowfall = .light
        for drift in simulation.drifts {
            for i in drift.heights.indices { _ = drift.depositMass(at: Float(i) * drift.spacing, mass: 1_000) }
        }
        return simulation
    }

    private func drift(_ simulation: SnowSimulation, _ id: UInt64) -> SnowDrift {
        simulation.drifts.first { $0.surface.id == id }!
    }

    private func stacked(_ simulation: SnowSimulation, x: ClosedRange<Float>, above y: Float) -> Int {
        simulation.looseSnow.active.filter {
            let p = simulation.looseSnow.position(of: $0)
            return x.contains(p.x) && p.y > y - 40 && p.y < y
        }.count
    }

    func testSnowLandingOnAFullFloorDoesNotStackAsALayer() {
        let simulation = world()
        _ = simulation.looseSnow.add(mass: 150, at: SIMD2(850, 740))
        for _ in 0..<60 { simulation.step(dt: 1 / 30, cursor: nil) }
        XCTAssertEqual(stacked(simulation, x: 760...960, above: 800), 0, "Grains stacked on the full floor")
    }

    func testSnowLandingOnAFullDockRidgeDoesNotStackAsALayer() {
        let simulation = world()
        _ = simulation.looseSnow.add(mass: 120, at: SIMD2(500, 700))
        for _ in 0..<60 { simulation.step(dt: 1 / 30, cursor: nil) }
        XCTAssertEqual(stacked(simulation, x: 320...680, above: 740), 0, "Grains stacked on the full Dock ridge")
    }

    func testFloorOverloadCompactsOverTimeWithoutGoingNegative() {
        let simulation = world()
        let ground = drift(simulation, DesktopSceneBuilder.groundID)
        let full = ground.heights.reduce(0, +) * ground.spacing
        ground.addOverload(at: 850, mass: 400)
        for _ in 0..<(60 * 30) { simulation.step(dt: 1 / 30, cursor: nil) }
        let after = ground.heights.reduce(0, +) * ground.spacing
        XCTAssertLessThan(after, full + 400 * 0.5, "Overload on the floor slowly compacts away")
        XCTAssertTrue(ground.heights.allSatisfy { $0 >= 0 })
    }
}
