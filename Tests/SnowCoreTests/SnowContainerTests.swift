import Foundation
import XCTest
@testable import SnowCore

/// A stretch of a top walled in by taller windows on both sides is a container: snow fills it up
/// to the shorter wall with an ordinary undulating cap over that, and what does not fit spills
/// over the shorter wall onto that window's top, never over the taller one.
final class SnowContainerTests: XCTestCase {
    private func world() -> SnowSimulation {
        // A widget (top 54) on the left, Spotify (top 122) on the right, the terminal's top (138)
        // as the container floor, exposed only in the 22 pt between them.
        let floor = Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 800, width: 1200)
        let widget = Surface(id: 1, x: 196, y: 54, width: 164)
        let spotify = Surface(id: 2, x: 385, y: 122, width: 500)
        let terminal = Surface(id: 3, x: 327, y: 138, width: 700, visibleSpans: [Span(33, 700)], snowfallSpans: [Span(33, 58)])
        let simulation = SnowSimulation(size: SIMD2(1200, 800), budget: SimulationBudget(flakes: 0, debris: 96), seed: 4)
        simulation.updateScene(surfaces: [floor, widget, spotify, terminal],
                               bodies: [SolidBody(id: 1, bounds: CGRect(x: 196, y: 54, width: 164, height: 156)),
                                        SolidBody(id: 2, bounds: CGRect(x: 385, y: 122, width: 500, height: 500)),
                                        SolidBody(id: 3, bounds: CGRect(x: 327, y: 138, width: 700, height: 500))])
        simulation.clear()
        return simulation
    }

    private func area(_ drift: SnowDrift) -> Float { drift.heights.reduce(0, +) * drift.spacing }

    func testOverflowSpillsOntoTheShorterWallOnly() {
        let simulation = world(), control = world()
        let container = simulation.drifts.first { $0.surface.id == 3 }!
        let widget = simulation.drifts.first { $0.surface.id == 1 }!
        let spotify = simulation.drifts.first { $0.surface.id == 2 }!
        let calmSpotify = control.drifts.first { $0.surface.id == 2 }!, calmWidget = control.drifts.first { $0.surface.id == 1 }!
        XCTAssertEqual(container.basins.count, 1)
        XCTAssertEqual(container.basins.first?.rim ?? 0, 16, accuracy: 0.5, "Filled up to the shorter wall (Spotify)")
        for _ in 0..<(60 * 30) {
            container.addOverload(at: 45, mass: 4)
            simulation.step(dt: 1 / 30, cursor: nil)
            control.step(dt: 1 / 30, cursor: nil)
        }
        XCTAssertGreaterThan(area(spotify) - area(calmSpotify), 500, "The overflow landed on Spotify's top")
        XCTAssertEqual(area(widget), area(calmWidget), accuracy: 1, "Nothing climbs over the taller wall")
        XCTAssertLessThanOrEqual(container.heights.max() ?? 0, 16 + 18 + 8, "No tower over the container")
    }

    func testAFilledContainerUndulatesInsteadOfAFlatLine() {
        let simulation = world()
        let container = simulation.drifts.first { $0.surface.id == 3 }!
        for i in container.heights.indices { _ = container.depositMass(at: Float(i) * container.spacing, mass: 1_000, reach: 0) }
        for _ in 0..<(30 * 30) { simulation.step(dt: 1 / 30, cursor: nil) }
        let inside = container.heights.indices.filter { container.basin(containing: $0) != nil }.map { container.heights[$0] }
        XCTAssertGreaterThan(inside.min() ?? 0, 16, "Filled past the rim")
        XCTAssertGreaterThan((inside.max() ?? 0) - (inside.min() ?? 0), 2, "The snow banks against the taller wall, not a straight line")
    }
}
