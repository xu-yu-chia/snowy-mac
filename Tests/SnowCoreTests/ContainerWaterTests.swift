import Foundation
import XCTest
@testable import SnowCore

/// Water collected between windows behaves like water: rain lands on its surface (not on the
/// bottom of the basin) and rings it, and falling water never passes behind a window.
final class ContainerWaterTests: XCTestCase {
    private let floor = Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 1000, width: 1200)
    private let walls = [SolidBody(id: 1, bounds: CGRect(x: 400, y: 500, width: 400, height: 400)),
                         SolidBody(id: 2, bounds: CGRect(x: 200, y: 300, width: 250, height: 600)),
                         SolidBody(id: 3, bounds: CGRect(x: 750, y: 420, width: 250, height: 500))]

    private func basin(flakes: Int = 0, depth: Float = 40) -> (SnowSimulation, SnowDrift) {
        let simulation = SnowSimulation(size: SIMD2(1200, 1000), budget: SimulationBudget(flakes: flakes, debris: 96), seed: 5)
        let base = Surface(id: 1, x: 400, y: 500, width: 400, visibleSpans: [Span(50, 350)])
        simulation.updateScene(surfaces: [floor, base], bodies: walls)
        simulation.clear()
        simulation.weather = .rain
        let drift = simulation.drifts.first { $0.surface.id == 1 }!
        _ = drift.addWater(area: 300 * depth, at: 150)
        return (simulation, drift)
    }

    func testRainLandsOnTheBasinWaterSurface() {
        let (simulation, _) = basin()
        let hit = simulation.rainTopHit(from: SIMD2(600, 100), to: SIMD2(600, 520), includeProps: true)
        XCTAssertEqual(hit?.point.y ?? 0, 460, accuracy: 0.5, "40 pt of water above the top at y 500")
    }

    func testOverflowSpillsOntoTheWallsTopNotDownTheInside() {
        // The right wall (body 3) has its own exposed top; overflow goes there, never into the basin.
        let simulation = SnowSimulation(size: SIMD2(1200, 1000), budget: SimulationBudget(flakes: 0, debris: 96), seed: 5)
        let base = Surface(id: 1, x: 400, y: 500, width: 400, visibleSpans: [Span(50, 350)])
        let wallTop = Surface(id: 3, x: 750, y: 420, width: 250)
        simulation.updateScene(surfaces: [floor, base, wallTop], bodies: walls)
        simulation.clear()
        simulation.weather = .rain
        let drift = simulation.drifts.first { $0.surface.id == 1 }!
        _ = drift.addWater(area: 300 * 80, at: 150)
        for _ in 0..<5 { simulation.queueRunoff(drift.addWater(area: 50, at: 150), from: drift) }
        for _ in 0..<120 {
            simulation.step(dt: 1 / 60, cursor: nil)
            XCTAssertFalse(simulation.drips.contains { $0.position.x > 445 && $0.position.x < 755 && $0.position.y > 425 },
                           "No water runs down inside the basin")
        }
        XCTAssertGreaterThan(simulation.drifts.first { $0.surface.id == 3 }!.puddleArea, 0, "It landed on the wall's top")
    }

    func testLosingAWallPoursTheBasinOutWithoutAJump() {
        let (simulation, _) = basin(depth: 80)
        simulation.updateScene(surfaces: [floor, Surface(id: 1, x: 400, y: 500, width: 400, visibleSpans: [Span(50, 400)])],
                               bodies: Array(walls.prefix(2)))
        var last = simulation.flood.level
        var biggest: Float = 0
        for _ in 0..<(8 * 60) {
            simulation.step(dt: 1 / 60, cursor: nil)
            biggest = max(biggest, simulation.flood.level - last)
            last = simulation.flood.level
        }
        XCTAssertLessThan(biggest, 1, "The basin pours out over time; the flood never jumps")
        XCTAssertGreaterThan(simulation.flood.level, 5, "…and its water does reach the flood")
    }

    func testRainRingsTheBasinSurface() {
        let (simulation, drift) = basin(flakes: 400)
        for _ in 0..<60 { simulation.step(dt: 1 / 30, cursor: nil) }
        let waves = drift.waves?.heights.map(abs).max() ?? 0
        XCTAssertGreaterThan(waves, 0.2, "Drops make ripples on collected water")
        let mesh = simulation.waterMesh.filter { $0.position.x > 455 && $0.position.x < 745 && $0.material.x == 1 }
        XCTAssertGreaterThan(Set(mesh.map { ($0.position.y * 10).rounded() }).count, 3, "The drawn surface moves")
    }

    func testFallingWaterNeverPassesBehindAWindow() {
        // A window with no exposed top (fully covered): water falling onto it must not show below it.
        let simulation = SnowSimulation(size: SIMD2(1200, 1000), budget: SimulationBudget(flakes: 0, debris: 96), seed: 5)
        let hidden = SolidBody(id: 9, bounds: CGRect(x: 400, y: 500, width: 400, height: 300))
        simulation.updateScene(surfaces: [floor], bodies: [hidden])
        simulation.clear()
        simulation.weather = .rain
        let control = SnowSimulation(size: SIMD2(1200, 1000), budget: SimulationBudget(flakes: 0, debris: 96), seed: 5)
        control.updateScene(surfaces: [floor], bodies: [hidden])
        control.clear()
        control.weather = .rain
        simulation.pendingRunoff.append((SIMD2(600, 300), 50))
        for _ in 0..<120 {
            simulation.step(dt: 1 / 60, cursor: nil)
            control.step(dt: 1 / 60, cursor: nil)
            XCTAssertFalse(simulation.drips.contains { hidden.contains($0.position) }, "No drip behind the window")
            XCTAssertFalse(simulation.drips.contains { $0.position.y > 800 && $0.position.x > 401 && $0.position.x < 799 },
                           "Nothing leaks out from under it")
        }
        XCTAssertEqual(simulation.flood.level * 1200 - control.flood.level * 1200, 50, accuracy: 1, "Its water is kept")
    }

    func testDripSlidingIntoAnotherWindowIsHidden() {
        // A drip sliding down window A's left side runs behind window B in front of it.
        let simulation = SnowSimulation(size: SIMD2(1200, 1000), budget: SimulationBudget(flakes: 0, debris: 96), seed: 5)
        let a = SolidBody(id: 1, bounds: CGRect(x: 500, y: 300, width: 300, height: 600))
        let b = SolidBody(id: 2, bounds: CGRect(x: 300, y: 450, width: 400, height: 200))
        simulation.updateScene(surfaces: [floor], bodies: [a, b])
        simulation.clear()
        simulation.weather = .rain
        simulation.pendingRunoff.append((SIMD2(498.5, 320), 20))
        for _ in 0..<240 {
            simulation.step(dt: 1 / 60, cursor: nil)
            XCTAssertFalse(simulation.drips.contains { b.contains($0.position) || $0.position.y > 650 })
        }
    }
}
