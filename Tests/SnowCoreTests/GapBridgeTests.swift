import Foundation
import XCTest
@testable import SnowCore

/// Snow sliding off a cap toward a neighbouring top across a narrow slit (two widgets, a widget
/// and a window) crosses onto the neighbour instead of being swallowed by the slit.
final class GapBridgeTests: XCTestCase {
    private func world(gap: Float) -> (SnowSimulation, left: UInt64, right: UInt64) {
        let simulation = SnowSimulation(size: SIMD2(1000, 800),
                                        budget: SimulationBudget(flakes: 0, debris: 96), seed: 13)
        let left = Surface(id: 1, x: 100, y: 300, width: 300)
        let right = Surface(id: 2, x: 400 + gap, y: 304, width: 300)
        let bodies = [SolidBody(id: 1, bounds: CGRect(x: 100, y: 300, width: 300, height: 200)),
                      SolidBody(id: 2, bounds: CGRect(x: CGFloat(400 + gap), y: 304, width: 300, height: 200))]
        simulation.updateScene(surfaces: [left, right], bodies: bodies)
        simulation.clear()
        simulation.snowfall = .light
        // Overload the left cap so it sheds off both ends.
        let cap = simulation.drifts.first { $0.surface.id == 1 }!
        for i in cap.heights.indices { _ = cap.depositMass(at: Float(i) * cap.spacing, mass: 1_000) }
        cap.addOverload(at: 290, mass: 400)
        return (simulation, 1, 2)
    }

    private func grainsInSlit(_ simulation: SnowSimulation, from minX: Float, to maxX: Float) -> Int {
        simulation.looseSnow.active.filter {
            let p = simulation.looseSnow.position(of: $0)
            return p.x > minX && p.x < maxX
        }.count
    }

    private func area(_ simulation: SnowSimulation, _ id: UInt64) -> Float {
        let drift = simulation.drifts.first { $0.surface.id == id }!
        return drift.heights.reduce(0, +) * drift.spacing
    }

    func testNarrowSlitIsBridgedOntoTheNeighbouringTop() {
        let (simulation, _, right) = world(gap: 8)
        let before = area(simulation, right)
        var slitGrains = 0
        for _ in 0..<90 {
            simulation.step(dt: 1 / 30, cursor: nil)
            slitGrains = max(slitGrains, grainsInSlit(simulation, from: 398, to: 410))
        }
        XCTAssertEqual(slitGrains, 0, "Snow fell into the narrow slit")
        XCTAssertGreaterThan(area(simulation, right), before + 20, "The neighbour received the snow")
    }

    func testWideGapStillLetsSnowFallBetweenTheTops() {
        let (simulation, _, _) = world(gap: 60)
        var gapGrains = 0
        for _ in 0..<90 {
            simulation.step(dt: 1 / 30, cursor: nil)
            gapGrains = max(gapGrains, grainsInSlit(simulation, from: 398, to: 462))
        }
        XCTAssertGreaterThan(gapGrains, 0)
    }
}
