import Foundation
import XCTest
@testable import SnowCore

/// Settled snow is not glued to its window. It stays where it is on screen: when the window
/// slides away the unsupported snow falls, a window moving down drops out from under its snow,
/// a window moving up lifts it, and a closed or minimized window lets its snow fall instead of
/// deleting it.
///
/// This replaces the earlier design in which a window's snow rode along with it. The tests that
/// pinned that behaviour (carried caps, hand-offs to a lower window, caps following tiling and
/// minimize, carried-cap wall contacts) were removed with it.
final class AnchoredSnowTests: XCTestCase {
    private let floor = Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 800, width: 1000)

    private func window(x: Float, y: Float, width: Float) -> (Surface, SolidBody) {
        (Surface(id: 1, x: x, y: y, width: width),
         SolidBody(id: 1, bounds: CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: 200)))
    }

    private func world(at w: (Surface, SolidBody)) -> SnowSimulation {
        let simulation = SnowSimulation(size: SIMD2(1000, 800), budget: SimulationBudget(flakes: 0, debris: 96), seed: 37)
        simulation.updateScene(surfaces: [floor, w.0], bodies: [w.1])
        simulation.clear()
        let cap = simulation.drifts.first { $0.surface.id == 1 }!
        for i in cap.heights.indices { _ = cap.depositSnowfall(at: Float(i) * cap.spacing, mass: 1_000) }
        return simulation
    }

    private func move(_ simulation: SnowSimulation, to w: (Surface, SolidBody)?) {
        simulation.updateScene(surfaces: [floor] + (w.map { [$0.0] } ?? []), bodies: w.map { [$0.1] } ?? [],
                               userMotion: false)
    }

    private func cap(_ simulation: SnowSimulation) -> SnowDrift? {
        simulation.drifts.first { $0.surface.id == 1 }
    }

    private func height(_ simulation: SnowSimulation, worldX: Float) -> Float {
        guard let cap = cap(simulation) else { return 0 }
        return cap.height(at: worldX - cap.surface.x)
    }

    private func released(_ simulation: SnowSimulation) -> Float {
        simulation.looseSnow.totalMass + simulation.pendingTransferMass
    }

    private func area(_ drift: SnowDrift?) -> Float {
        guard let drift else { return 0 }
        return drift.heights.reduce(0, +) * drift.spacing
    }

    func testSlidingAWindowLeavesSnowWhereItWas() {
        let simulation = world(at: window(x: 300, y: 400, width: 400))
        let before = height(simulation, worldX: 600)
        move(simulation, to: window(x: 500, y: 400, width: 400))
        XCTAssertEqual(height(simulation, worldX: 600), before, accuracy: before * 0.2,
                       "Snow over the part still under it stays in place")
        XCTAssertLessThan(height(simulation, worldX: 820), 1, "The newly covered part starts bare")
        XCTAssertGreaterThan(released(simulation), 100, "Snow over the part that slid away falls")
    }

    func testLoweringAWindowDropsItsSnowWhichLandsBackOnTop() {
        let simulation = world(at: window(x: 300, y: 400, width: 400))
        let before = area(cap(simulation))
        move(simulation, to: window(x: 300, y: 500, width: 400))
        XCTAssertLessThan(area(cap(simulation)), before * 0.1, "The window drops out from under its snow")
        for _ in 0..<(3 * 30) { simulation.step(dt: 1 / 30, cursor: nil) }
        XCTAssertGreaterThan(area(cap(simulation)), before * 0.5, "The snow falls back onto the lowered top")
    }

    func testRaisingAWindowLiftsItsSnow() {
        let simulation = world(at: window(x: 300, y: 400, width: 400))
        let before = area(cap(simulation))
        move(simulation, to: window(x: 300, y: 350, width: 400))
        XCTAssertEqual(area(cap(simulation)), before, accuracy: before * 0.05)
    }

    func testClosingAWindowLetsItsSnowFall() {
        let simulation = world(at: window(x: 300, y: 400, width: 400))
        let before = area(cap(simulation))
        move(simulation, to: nil)
        XCTAssertGreaterThan(released(simulation), before * 0.9, "Snow falls instead of being deleted")
    }

    func testShrinkingLikeMinimizeKeepsTheSnow() {
        let simulation = world(at: window(x: 300, y: 400, width: 400))
        let before = area(cap(simulation))
        move(simulation, to: window(x: 600, y: 650, width: 100))
        XCTAssertGreaterThan(area(cap(simulation)) + released(simulation), before * 0.9,
                             "Shrinking into the Dock must not delete the snow")
    }
}
