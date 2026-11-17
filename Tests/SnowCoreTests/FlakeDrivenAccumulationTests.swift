import Foundation
import XCTest
@testable import SnowCore

/// Settled snow is built by the flakes that actually land, so it only grows where snow can
/// fall, keeps pace with the visible snowfall, and stays smooth. Without visible flakes (Reduce
/// Motion) the ambient rate takes over so snow still settles.
final class FlakeDrivenAccumulationTests: XCTestCase {
    private let top = Surface(id: 1, x: 300, y: 600, width: 400)
    private let body = SolidBody(id: 1, bounds: CGRect(x: 300, y: 600, width: 400, height: 150))

    private func world(flakes: Int = 350, extraBodies: [SolidBody] = []) -> SnowSimulation {
        let simulation = SnowSimulation(size: SIMD2(1000, 800), budget: SimulationBudget(flakes: flakes), seed: 17)
        simulation.updateScene(surfaces: [top], bodies: [body] + extraBodies)
        simulation.clear()
        simulation.snowfall = .steady
        return simulation
    }

    private func cap(_ simulation: SnowSimulation) -> SnowDrift {
        simulation.drifts.first { $0.surface.id == 1 }!
    }

    private func run(_ simulation: SnowSimulation, seconds: Int) {
        for _ in 0..<(seconds * 30) { simulation.step(dt: 1 / 30, cursor: nil) }
    }

    func testTopThatFlakesCannotReachDoesNotGrow() {
        // A solid roof just above the top stops every flake before it can land.
        let roof = SolidBody(id: 2, bounds: CGRect(x: 200, y: 520, width: 600, height: 60))
        let simulation = world(extraBodies: [roof])
        run(simulation, seconds: 60)
        XCTAssertLessThan(cap(simulation).fillRatio, 0.02, "Snow appeared where no flake could land")
    }

    func testLandedFlakesBuildSnowAtTheFamiliarPace() {
        let simulation = world()
        run(simulation, seconds: 60)
        let fill = cap(simulation).fillRatio
        XCTAssertGreaterThan(fill, 0.1, "Landed flakes must visibly build the pile")
        XCTAssertLessThan(fill, 0.6, "A Steady cap must not fill within a minute")
    }

    func testWithoutVisibleFlakesSnowStillSettles() {
        let simulation = world()
        simulation.reducedMotion = true
        run(simulation, seconds: 60)
        XCTAssertGreaterThan(cap(simulation).fillRatio, 0.1)
    }

    func testLandingSnowBuildsASmoothSurface() {
        let simulation = world()
        run(simulation, seconds: 60)
        // The tapered shoulders at both ends slope down by design; judge the open middle.
        let all = cap(simulation).heights
        let h = Array(all[(all.count / 5)..<(all.count * 4 / 5)])
        let roughest = zip(h, h.dropFirst()).map { abs($0 - $1) }.max() ?? 0
        XCTAssertLessThan(roughest, 2.5, "Individual landings left a lumpy surface")
    }
}
