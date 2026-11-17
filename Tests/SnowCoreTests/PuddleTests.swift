import Foundation
import XCTest
@testable import SnowCore

/// In rain each top holds one level puddle (3 pt, Dock 2 pt). Once full its surface stays at the
/// rim; the excess gathers at the overflow point into a hanging drop (surface tension) that falls
/// once it holds ~12 pt², from the exposed ends, and a top that moves or disappears lets its puddle fall instead of carrying it.
final class PuddleTests: XCTestCase {
    private func drift(_ surface: Surface) -> SnowDrift {
        SnowDrift(surface: surface, cellCount: Int(surface.width / 4) + 1)
    }

    private func total(_ runoff: [(localX: Float, area: Float)]) -> Float {
        runoff.reduce(0) { $0 + $1.area }
    }

    func testPuddleFillsLevelUpToThreePoints() {
        let top = drift(Surface(id: 1, x: 100, y: 300, width: 100))
        XCTAssertTrue(top.addWater(area: 200, at: 50).isEmpty)
        XCTAssertEqual(top.puddle, 2, accuracy: 0.0001)
        XCTAssertTrue(top.addWater(area: 100, at: 50).isEmpty, "Full to the rim is still held")
        XCTAssertEqual(top.puddle, 3, accuracy: 0.0001)
        XCTAssertTrue(top.addWater(area: 10, at: 50).isEmpty, "The excess hangs at the rim first")
        XCTAssertEqual(top.puddle, 3, accuracy: 0.0001, "The surface stays at the overflow level")
        XCTAssertEqual(top.puddleArea, 310, accuracy: 0.001, "The hanging water is still on the top")
        let runoff = top.addWater(area: 20, at: 50)
        XCTAssertEqual(top.puddle, 3, accuracy: 0.0001)
        XCTAssertEqual(total(runoff), 30, accuracy: 0.001, "Grown big enough, the drops fall")
    }

    func testOverflowSplitsEquallyOnALevelTop() {
        let top = drift(Surface(id: 1, x: 100, y: 300, width: 100))
        let runoff = top.addWater(area: 500, at: 30)
        XCTAssertEqual(runoff.count, 2)
        let start = runoff.first { $0.localX == 0 }, end = runoff.first { $0.localX == 100 }
        XCTAssertEqual(start?.area ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(end?.area ?? 0, 100, accuracy: 0.001)
    }

    func testTiltedTopRunsOffTheLowerEnd() {
        let top = drift(Surface(id: 1, x: 100, y: 300, width: 100, slope: 0.1))
        let runoff = top.addWater(area: 500, at: 30)
        XCTAssertEqual(runoff.count, 1)
        XCTAssertEqual(runoff.first?.localX ?? -1, 100)
        XCTAssertEqual(total(runoff), 200, accuracy: 0.001)
    }

    func testCoveredEndSendsRunoffToTheOtherEnd() {
        let top = drift(Surface(id: 1, x: 100, y: 300, width: 100, visibleSpans: [Span(0, 60)]))
        let runoff = top.addWater(area: 300, at: 30)
        XCTAssertEqual(top.puddle, 3, accuracy: 0.0001)
        XCTAssertEqual(runoff.count, 1)
        XCTAssertEqual(runoff.first?.localX ?? -1, 0)
        XCTAssertEqual(total(runoff), 120, accuracy: 0.001)
    }

    func testDockPuddleLimitIsTwo() {
        let dock = drift(Surface(id: 7, x: 100, y: 700, width: 400, isDock: true))
        XCTAssertEqual(dock.puddleLimit, 2)
        _ = dock.addWater(area: 10_000, at: 100)
        XCTAssertEqual(dock.puddle, 2, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(dock.puddle, dock.puddleLimit)
    }

    func testPropsHoldNoWater() {
        let prop = drift(Surface(id: 9, x: 100, y: 300, width: 40, holdsWater: false))
        let runoff = prop.addWater(area: 20, at: 12)
        XCTAssertEqual(prop.puddle, 0)
        XCTAssertEqual(runoff.count, 1)
        XCTAssertEqual(runoff.first?.localX ?? -1, 12)
        XCTAssertEqual(total(runoff), 20, accuracy: 0.0001)
    }

    func testMovingTopReleasesItsHangingDropsToo() {
        let top = drift(Surface(id: 1, x: 100, y: 300, width: 100))
        _ = top.addWater(area: 310, at: 50)
        XCTAssertEqual(total(top.releasePuddle()), 310, accuracy: 0.001)
        XCTAssertEqual(top.puddleArea, 0)
    }

    func testPuddleNeverNegative() {
        let top = drift(Surface(id: 1, x: 100, y: 300, width: 100))
        _ = top.addWater(area: 200, at: 50)
        top.evaporate(fraction: 1.5)
        XCTAssertEqual(top.puddle, 0)
    }

    // MARK: Scene changes

    private let floor = Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 800, width: 1000)

    private func window(x: Float) -> (Surface, SolidBody) {
        (Surface(id: 1, x: x, y: 300, width: 100),
         SolidBody(id: 1, bounds: CGRect(x: CGFloat(x), y: 300, width: 100, height: 200)))
    }

    private func wetWorld() -> SnowSimulation {
        let simulation = SnowSimulation(size: SIMD2(1000, 800), budget: SimulationBudget(flakes: 0, debris: 96), seed: 5)
        let w = window(x: 200)
        simulation.updateScene(surfaces: [floor, w.0], bodies: [w.1])
        simulation.clear()
        let top = simulation.drifts.first { $0.surface.id == 1 }!
        _ = top.addWater(area: 300, at: 50)
        XCTAssertEqual(top.puddle, 3, accuracy: 0.0001)
        return simulation
    }

    func testMovingAWindowReleasesItsPuddle() {
        let simulation = wetWorld()
        let w = window(x: 400)
        simulation.updateScene(surfaces: [floor, w.0], bodies: [w.1], userMotion: false)
        let top = simulation.drifts.first { $0.surface.id == 1 }!
        XCTAssertEqual(top.puddle, 0, "A moved window does not carry its water")
        XCTAssertEqual(simulation.pendingRunoff.reduce(0) { $0 + $1.area }, 300, accuracy: 0.01)
        XCTAssertTrue(simulation.pendingRunoff.allSatisfy { $0.position.x >= 198 && $0.position.x <= 302 },
                      "The water falls at the window's old ends")
    }

    func testClosingAWindowReleasesItsPuddle() {
        let simulation = wetWorld()
        simulation.updateScene(surfaces: [floor], bodies: [], userMotion: false)
        XCTAssertEqual(simulation.pendingRunoff.reduce(0) { $0 + $1.area }, 300, accuracy: 0.01)
    }

    /// A top walled in by taller windows on both sides is a container: it fills like the flood, up
    /// to the shorter wall, and overflows over that wall.
    private func basin() -> (SnowSimulation, SnowDrift) {
        let simulation = SnowSimulation(size: SIMD2(1200, 1000), budget: SimulationBudget(flakes: 0, debris: 96), seed: 5)
        let base = Surface(id: 1, x: 400, y: 500, width: 400, visibleSpans: [Span(50, 350)])
        let bodies = [SolidBody(id: 1, bounds: CGRect(x: 400, y: 500, width: 400, height: 400)),
                      SolidBody(id: 2, bounds: CGRect(x: 200, y: 300, width: 250, height: 600)),
                      SolidBody(id: 3, bounds: CGRect(x: 750, y: 420, width: 250, height: 500))]
        simulation.updateScene(surfaces: [Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 1000, width: 1200), base],
                               bodies: bodies)
        simulation.clear()
        return (simulation, simulation.drifts.first { $0.surface.id == 1 }!)
    }

    func testWalledTopFillsUpToTheShorterWall() {
        let (_, drift) = basin()
        XCTAssertEqual(drift.puddleLimit, 80, accuracy: 0.001, "The right wall rises 80 pt above the top")
        XCTAssertTrue(drift.addWater(area: 300 * 79, at: 150).isEmpty, "Far deeper than a rim puddle")
        XCTAssertEqual(drift.puddle, 79, accuracy: 0.001)
    }

    func testWalledTopOverflowsOverTheShorterWall() {
        let (simulation, drift) = basin()
        _ = drift.addWater(area: 300 * 80, at: 150)
        simulation.queueRunoff(drift.addWater(area: 600, at: 150), from: drift)
        XCTAssertEqual(drift.puddle, 80, accuracy: 0.001, "The surface stays at the wall's top")
        XCTAssertFalse(simulation.pendingRunoff.isEmpty)
        XCTAssertTrue(simulation.pendingRunoff.allSatisfy { $0.position.x > 750 && abs($0.position.y - 419) < 1.5 },
                      "It spills over the right wall's top")
    }

    func testUnchangedWindowKeepsItsPuddle() {
        let simulation = wetWorld()
        let w = window(x: 200)
        simulation.updateScene(surfaces: [floor, w.0], bodies: [w.1], userMotion: false)
        XCTAssertEqual(simulation.drifts.first { $0.surface.id == 1 }!.puddle, 3, accuracy: 0.0001)
        XCTAssertTrue(simulation.pendingRunoff.isEmpty)
    }
}
