import Foundation
import XCTest
@testable import SnowCore

/// A cap that keeps receiving snow after it is full sheds chunks off its ends, like snow sliding
/// off a roof, and optional melting thins every pile over time.
final class OverloadSheddingTests: XCTestCase {
    private let top = Surface(id: 1, x: 300, y: 300, width: 400)
    private let body = SolidBody(id: 1, bounds: CGRect(x: 300, y: 300, width: 400, height: 300))

    private func world() -> SnowSimulation {
        let simulation = SnowSimulation(size: SIMD2(1000, 800),
                                        budget: SimulationBudget(flakes: 0, debris: 96), seed: 11)
        simulation.updateScene(surfaces: [top], bodies: [body])
        simulation.clear()
        simulation.snowfall = .flurry
        return simulation
    }

    private func cap(_ simulation: SnowSimulation) -> SnowDrift {
        simulation.drifts.first { $0.surface.id == 1 }!
    }

    private func area(_ drift: SnowDrift) -> Float {
        drift.heights.reduce(0, +) * drift.spacing
    }

    private func fill(_ drift: SnowDrift, until ratio: Float) {
        for _ in 0..<10_000 where drift.fillRatio < ratio { drift.accumulate(dt: 0.5, intensity: 1) }
    }

    private func run(_ simulation: SnowSimulation, seconds: Float) {
        for _ in 0..<Int(seconds * 30) { simulation.step(dt: 1 / 30, cursor: nil) }
    }

    func testFullCapShedsChunksOffItsEndsOutsideTheWindow() {
        let simulation = world()
        fill(cap(simulation), until: 1)
        let before = area(cap(simulation))

        run(simulation, seconds: 6)

        let shed = simulation.looseSnow.totalMass + simulation.pendingTransferMass
        XCTAssertGreaterThan(shed, before * 0.02, "An overloaded cap sheds snow")
        let grains = simulation.looseSnow.active.map { simulation.looseSnow.position(of: $0) }
        XCTAssertFalse(grains.isEmpty)
        XCTAssertTrue(grains.allSatisfy { $0.x < 300 || $0.x > 700 || $0.y > 300 },
                      "Shed snow leaves over the ends, not through the window")
    }

    func testPartlyFilledCapDoesNotAvalanche() {
        let simulation = world()
        fill(cap(simulation), until: 0.5)

        run(simulation, seconds: 3)

        XCTAssertEqual(simulation.looseSnow.totalMass + simulation.pendingTransferMass, 0, accuracy: 0.0001)
    }

    func testMeltingThinsPilesComparedWithNoMelting() {
        // Start half full so neither pile sheds during the comparison.
        let melting = world(), control = world()
        fill(cap(melting), until: 0.5)
        fill(cap(control), until: 0.5)
        melting.melting = .fast

        run(melting, seconds: 10)
        run(control, seconds: 10)

        XCTAssertLessThan(area(cap(melting)), area(cap(control)) * 0.9)
    }

    func testMeltingIsOffByDefault() {
        XCTAssertEqual(SnowSimulation(size: SIMD2(100, 100)).melting, .off)
        XCTAssertEqual(Melting.off.rate, 0)
    }
}
