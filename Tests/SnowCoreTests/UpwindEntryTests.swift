import Foundation
import XCTest
@testable import SnowCore

/// With a crosswind, snow crosses the upwind screen edge as well as the top. Spawning only at
/// the top leaves an empty wedge along the upwind side.
final class UpwindEntryTests: XCTestCase {
    private let samples = 4_000

    private func world() -> SnowSimulation {
        SnowSimulation(size: SIMD2(1000, 800), budget: SimulationBudget(flakes: 0), seed: 9)
    }

    private func entries(_ simulation: SnowSimulation) -> (top: Int, left: Int, right: Int) {
        var result = (top: 0, left: 0, right: 0)
        for _ in 0..<samples {
            let p = simulation.newFlake(scattered: false).position
            if p.y < 0 { result.top += 1 }
            else if p.x < 0 { result.left += 1 }
            else if p.x > simulation.size.x { result.right += 1 }
            else { XCTFail("A new flake must enter from outside the screen, got \(p)") }
        }
        return result
    }

    func testCalmSnowEntersOnlyFromTheTop() {
        let counts = entries(world())
        XCTAssertEqual(counts.top, samples)
    }

    func testRightwardWindAlsoFeedsTheLeftEdge() {
        let simulation = world()
        simulation.wind = WindSettings(vector: SIMD2(1, 0))
        let counts = entries(simulation)
        let side = Double(counts.left) / Double(samples)
        // Flux share: H·|vx| / (W·vy + H·|vx|) = 800·80 / (1000·41.5 + 800·80) ≈ 0.61.
        XCTAssertGreaterThan(side, 0.45)
        XCTAssertLessThan(side, 0.75)
        XCTAssertEqual(counts.right, 0, "Snow never enters against the wind")
    }

    func testLeftwardWindFeedsTheRightEdge() {
        let simulation = world()
        simulation.wind = WindSettings(vector: SIMD2(-0.5, 0))
        let counts = entries(simulation)
        XCTAssertGreaterThan(counts.right, samples / 10)
        XCTAssertEqual(counts.left, 0)
    }

    func testSideEntryAvoidsWindowsTouchingTheUpwindEdge() {
        let simulation = world()
        simulation.wind = WindSettings(vector: SIMD2(1, 0))
        let edgeWindow = SolidBody(id: 5, bounds: CGRect(x: 0, y: 0, width: 300, height: 800))
        simulation.updateScene(surfaces: [], bodies: [edgeWindow])
        for _ in 0..<samples {
            let p = simulation.newFlake(scattered: false).position
            XCTAssertFalse(edgeWindow.contains(p, padding: 4), "Spawned inside a window at \(p)")
        }
    }
}
