import Foundation
import XCTest
@testable import SnowCore

/// The screen edge is not a wall. While a window nearly fills the screen, its full cap sheds
/// down the thin strip beside the screen edge; that snow must drift off the screen, not build a
/// mountain on the floor behind the window that appears when the window is restored.
final class ScreenEdgeDriftTests: XCTestCase {
    func testAZoomedWindowDoesNotBuildAHiddenMountainAtTheEdge() {
        let floor = Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 800, width: 1200, visibleSpans: [Span(0, 15)])
        let top = Surface(id: 1, x: 15, y: 40, width: 1185)
        let simulation = SnowSimulation(size: SIMD2(1200, 800), budget: SimulationBudget(flakes: 400, debris: 96), seed: 6)
        simulation.updateScene(surfaces: [floor, top], bodies: [SolidBody(id: 1, bounds: CGRect(x: 15, y: 40, width: 1185, height: 740))])
        simulation.clear()
        simulation.snowfall = .flurry
        simulation.wind = WindSettings(vector: SIMD2(-0.86, 0.5))
        let cap = simulation.drifts.first { $0.surface.id == 1 }!
        for i in cap.heights.indices { _ = cap.depositSnowfall(at: Float(i) * cap.spacing, mass: 1_000) }
        for _ in 0..<(180 * 30) { simulation.step(dt: 1 / 30, cursor: nil) }
        let ground = simulation.drifts.first { $0.surface.id == DesktopSceneBuilder.groundID }!
        let edge = ground.heights.prefix(40).max() ?? 0
        XCTAssertLessThan(edge, 40, "No mountain against the edge behind the window")
    }
}
