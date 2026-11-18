import Foundation
import XCTest
@testable import SnowCore

/// Snow pushed above a cap (the shovel) must find an end it can shed from, and a flake must land
/// on top of a tall pile instead of falling through it to the support underneath.
final class OverloadReachTests: XCTestCase {
    private func world(_ top: Surface) -> SnowSimulation {
        let simulation = SnowSimulation(size: SIMD2(1200, 800), budget: SimulationBudget(flakes: 0, debris: 96), seed: 8)
        simulation.updateScene(surfaces: [Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 800, width: 1200), top],
                               bodies: [SolidBody(id: top.id, bounds: CGRect(x: CGFloat(top.x), y: CGFloat(top.y), width: CGFloat(top.width), height: 300))])
        simulation.clear()
        return simulation
    }

    func testOverloadNearAHiddenEndCreepsToTheOpenEnd() {
        // Exposed from 33 pt on: the nearer (start) end is hidden behind another window.
        let simulation = world(Surface(id: 1, x: 300, y: 300, width: 400, visibleSpans: [Span(33, 400)]))
        let drift = simulation.drifts.first { $0.surface.id == 1 }!
        drift.addOverload(at: 40, mass: 2_000)
        for _ in 0..<(60 * 30) { simulation.step(dt: 1 / 30, cursor: nil) }
        XCTAssertLessThan(drift.heights.max() ?? 0, 30, "The pushed pile drains toward the open end instead of standing as a spike")
    }

    func testOverloadWithNoOpenEndPacksAway() {
        let simulation = world(Surface(id: 1, x: 300, y: 300, width: 400, visibleSpans: [Span(150, 250)]))
        let drift = simulation.drifts.first { $0.surface.id == 1 }!
        drift.addOverload(at: 200, mass: 2_000)
        for _ in 0..<(60 * 30) { simulation.step(dt: 1 / 30, cursor: nil) }
        XCTAssertLessThan(drift.heights.max() ?? 0, 30, "Overload that cannot reach an end does not stay as a tower")
    }

    func testOverloadUnderAHigherWindowIsNotAnOpenEnd() {
        // From a real desktop: the terminal's top counts as visible behind Spotify (Spotify is
        // only 16 pt higher), but only the slit is open sky. Its far end lies under Spotify's
        // body, so overload there must pack away rather than pile up in the slit.
        let simulation = world(Surface(id: 1, x: 327, y: 138, width: 700, visibleSpans: [Span(33, 700)],
                                       snowfallSpans: [Span(33, 58)]))
        let drift = simulation.drifts.first { $0.surface.id == 1 }!
        // Snow keeps falling into the slit (shed off both neighbouring caps).
        for _ in 0..<(120 * 30) {
            drift.addOverload(at: 45, mass: 3)
            simulation.step(dt: 1 / 30, cursor: nil)
        }
        XCTAssertLessThan(drift.heights.max() ?? 0, 25, "No mountain grows out of the slit")
    }

    func testFlakeLandsOnTopOfATallPile() {
        let simulation = world(Surface(id: 1, x: 300, y: 300, width: 400))
        let drift = simulation.drifts.first { $0.surface.id == 1 }!
        for i in drift.heights.indices { drift.heights[i] = 100 }
        simulation.step(dt: 1 / 60, cursor: nil)
        for i in drift.heights.indices { drift.heights[i] = 100 }
        var flake = SnowParticle(position: SIMD2(500, 300 - 108), velocity: SIMD2(0, 600), radius: 2,
                                 opacity: 1, phase: 0, remainingLife: 100, mass: 1)
        XCTAssertTrue(simulation.advanceParticle(&flake, dt: 1 / 30, recycleOnContact: true), "It lands on the pile")
        XCTAssertEqual(flake.position.y, 300 - 100 - 2, accuracy: 1.5)
    }
}
