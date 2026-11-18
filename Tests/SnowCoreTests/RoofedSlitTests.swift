import Foundation
import XCTest
@testable import SnowCore

/// Stacked widgets leave a slit between the upper tile and the top of the one below. Snow that
/// slides off the upper tile and lands at the slit's mouth must not be drawn deep into the slit,
/// and settled snow must not creep sideways into it over time.
final class RoofedSlitTests: XCTestCase {
    private let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let widgetLayer = -2_147_483_601

    private func widget(_ id: UInt64, y: CGFloat) -> DesktopWindowRecord {
        DesktopWindowRecord(id: id, bounds: CGRect(x: 1552, y: y, width: 360, height: 180),
                            layer: widgetLayer, role: .widget)
    }

    private func world() -> SnowSimulation {
        let scene = DesktopSceneBuilder.build(displayBounds: display, menuInset: 30,
                                              windows: [widget(1, y: 38), widget(2, y: 218)])
        let simulation = SnowSimulation(size: SIMD2(1920, 1080), budget: SimulationBudget(flakes: 0), seed: 8)
        simulation.updateScene(surfaces: scene.surfaces, bodies: scene.bodies, userMotion: false)
        simulation.snowfall = .flurry
        // The user's wind: rightward and down, which pushes loose snow along into the slit.
        simulation.wind = WindSettings(vector: SIMD2(0.28, 0.55))
        // The upper tile is full, so it keeps trickling snow off both ends.
        let upper = simulation.drifts.first { $0.surface.id == 1 }!
        for i in upper.heights.indices { _ = upper.depositMass(at: Float(i) * upper.spacing, mass: 1_000) }
        return simulation
    }

    private func deepMass(_ drift: SnowDrift, beyond inset: Float) -> Float {
        drift.heights.indices.reduce(Float(0)) { sum, i in
            let x = Float(i) * drift.spacing
            return x > inset && x < drift.surface.width - inset ? sum + drift.heights[i] * drift.spacing : sum
        }
    }

    func testSnowAtTheSlitMouthIsNotDrawnDeepIntoTheRoofedSlit() {
        let simulation = world()
        for _ in 0..<(120 * 30) { simulation.step(dt: 1 / 30, cursor: nil) }
        let lower = simulation.drifts.first { $0.surface.id == 2 }!
        XCTAssertLessThan(deepMass(lower, beyond: 40), 20,
                          "Snow was drawn more than 40 pt into the slit under the upper widget")
    }

    func testSettledSnowAtTheMouthDoesNotCreepUnderTheRoof() {
        let simulation = world()
        let lower = simulation.drifts.first { $0.surface.id == 2 }!
        // A small drift that already formed at the slit's mouth.
        for i in lower.heights.indices where Float(i) * lower.spacing < 24 { lower.heights[i] = 6 }
        for _ in 0..<(60 * 30) { simulation.step(dt: 1 / 30, cursor: nil) }
        XCTAssertLessThan(deepMass(lower, beyond: 48), 40, "Settling spread the mouth drift under the roof")
    }

    /// Two small widgets side by side over a large one: snowfall reaches the large widget's top
    /// only through the vertical slit between them. What lands there spills out to both sides
    /// along the large widget's top (2026-11-19 request), as a thin layer, never a pile.
    func testSnowFallingThroughAVerticalSlitSpillsOutAsAThinLayer() {
        let small = { (id: UInt64, x: CGFloat) in
            DesktopWindowRecord(id: id, bounds: CGRect(x: x, y: 38, width: 180, height: 180),
                                layer: self.widgetLayer, role: .widget)
        }
        let large = DesktopWindowRecord(id: 3, bounds: CGRect(x: 8, y: 218, width: 360, height: 360),
                                        layer: widgetLayer, role: .widget)
        let scene = DesktopSceneBuilder.build(displayBounds: display, menuInset: 30,
                                              windows: [small(1, 8), small(2, 188), large])
        let simulation = SnowSimulation(size: SIMD2(1920, 1080), budget: SimulationBudget(flakes: 0), seed: 9)
        simulation.updateScene(surfaces: scene.surfaces, bodies: scene.bodies, userMotion: false)
        simulation.snowfall = .flurry
        for _ in 0..<(180 * 30) { simulation.step(dt: 1 / 30, cursor: nil) }
        let cap = simulation.drifts.first { $0.surface.id == 3 }!
        // The slit is centred at x = 188 on screen; measure snow more than 40 pt from it.
        let slitLocal = 188 - cap.surface.x
        let far = cap.heights.indices.filter { abs(Float($0) * cap.spacing - slitLocal) > 40 }.map { cap.heights[$0] }
        XCTAssertLessThan(far.max() ?? 0, 18, "Snow spreading under the roofing widgets stays within an ordinary cap")
        XCTAssertTrue(simulation.basins.isEmpty, "The slit leaks sideways under the small widgets: no container")
    }
}
