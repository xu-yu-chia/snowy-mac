import Foundation
import XCTest
@testable import SnowCore

/// Two full widgets side by side: snow at their facing ends must not be handed back and forth
/// across the slit, piling into tall spikes at the tapered ends.
final class BridgedEndTests: XCTestCase {
    private let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    /// How far the snow surface stands above the top's flat edge, at its highest.
    private func rise(_ cap: SnowDrift) -> Float {
        cap.heights.indices.map { cap.surface.y - (cap.surface.baseY(at: Float($0) * cap.spacing) - cap.heights[$0]) }.max() ?? 0
    }

    private func widget(_ id: UInt64, x: CGFloat) -> DesktopWindowRecord {
        DesktopWindowRecord(id: id, bounds: CGRect(x: x, y: 38, width: 180, height: 180),
                            layer: -2_147_483_601, role: .widget)
    }

    func testFacingEndsOfSideBySideWidgetsDoNotGrowSpikes() {
        let scene = DesktopSceneBuilder.build(displayBounds: display, menuInset: 30,
                                              windows: [widget(1, x: 8), widget(2, x: 188)])
        let simulation = SnowSimulation(size: SIMD2(1920, 1080), budget: SimulationBudget(flakes: 0), seed: 6)
        simulation.updateScene(surfaces: scene.surfaces, bodies: scene.bodies)
        simulation.snowfall = .flurry
        simulation.wind = WindSettings(vector: SIMD2(0.28, 0.55))
        for _ in 0..<(360 * 30) { simulation.step(dt: 1 / 30, cursor: nil) }
        for id: UInt64 in [1, 2] {
            let cap = simulation.drifts.first { $0.surface.id == id }!
            // Measured from the widget's flat top: snow filling the V between the two rounded
            // corners is deep from the corner's base but level with the rest, not a spike.
            let tallest = rise(cap)
            XCTAssertLessThan(tallest, 20, "Widget \(id) grew a \(tallest) pt spike")
        }
    }

    /// The glove pushes extra snow against the slit between two full widgets.
    func testPushedSnowAtFacingEndsDoesNotPileIntoSpikes() {
        let scene = DesktopSceneBuilder.build(displayBounds: display, menuInset: 30,
                                              windows: [widget(1, x: 8), widget(2, x: 188)])
        let simulation = SnowSimulation(size: SIMD2(1920, 1080), budget: SimulationBudget(flakes: 0), seed: 6)
        simulation.updateScene(surfaces: scene.surfaces, bodies: scene.bodies)
        simulation.snowfall = .flurry
        let left = simulation.drifts.first { $0.surface.id == 1 }!
        let right = simulation.drifts.first { $0.surface.id == 2 }!
        for cap in [left, right] {
            for i in cap.heights.indices { _ = cap.depositMass(at: Float(i) * cap.spacing, mass: 1_000) }
        }
        left.addOverload(at: left.surface.width - 10, mass: 300)
        right.addOverload(at: 10, mass: 300)
        var worst: Float = 0
        for _ in 0..<(60 * 30) {
            simulation.step(dt: 1 / 30, cursor: nil)
            worst = max(worst, left.heights.max() ?? 0, right.heights.max() ?? 0)
        }
        XCTAssertLessThan(rise(left), 20)
        XCTAssertLessThan(rise(right), 20)
    }

    /// A full-size window covers both widgets for a while, then goes away.
    func testCoveredOverloadDoesNotCollectIntoSpikesUnderAFullSizeWindow() {
        let widgets = [widget(1, x: 8), widget(2, x: 188)]
        // An existing window, away from the widgets, that is then zoomed to full size.
        let small = DesktopWindowRecord(id: 50, bounds: CGRect(x: 700, y: 400, width: 600, height: 400),
                                        layer: 0, role: .application)
        let open = DesktopSceneBuilder.build(displayBounds: display, menuInset: 30, windows: [small] + widgets)
        let simulation = SnowSimulation(size: SIMD2(1920, 1080), budget: SimulationBudget(flakes: 0), seed: 6)
        simulation.updateScene(surfaces: open.surfaces, bodies: open.bodies)
        simulation.snowfall = .flurry
        for id: UInt64 in [1, 2] {
            let cap = simulation.drifts.first { $0.surface.id == id }!
            for i in cap.heights.indices { _ = cap.depositMass(at: Float(i) * cap.spacing, mass: 1_000) }
            cap.addOverload(at: cap.surface.width / 2, mass: 120)
        }
        let full = DesktopWindowRecord(id: 50, bounds: CGRect(x: 0, y: 30, width: 1920, height: 1000),
                                       layer: 0, role: .application)
        let covered = DesktopSceneBuilder.build(displayBounds: display, menuInset: 30, windows: [full] + widgets)
        simulation.updateScene(surfaces: covered.surfaces, bodies: covered.bodies, userMotion: false)
        for _ in 0..<(20 * 30) { simulation.step(dt: 1 / 30, cursor: nil) }
        simulation.updateScene(surfaces: open.surfaces, bodies: open.bodies, userMotion: false)
        simulation.step(dt: 1 / 30, cursor: nil)
        // The moment the window goes away, neither end has collected a spike.
        for id: UInt64 in [1, 2] {
            let h = simulation.drifts.first { $0.surface.id == id }!.heights
            XCTAssertLessThanOrEqual(h[0], h[1] + 4, "Widget \(id) shows a spike at its start")
            XCTAssertLessThanOrEqual(h[h.count - 1], h[h.count - 2] + 4, "Widget \(id) shows a spike at its end")
        }
        // The pushed hump that was covered spreads and sheds normally once it is visible again.
        for _ in 0..<(10 * 30) { simulation.step(dt: 1 / 30, cursor: nil) }
        for id: UInt64 in [1, 2] {
            let cap = simulation.drifts.first { $0.surface.id == id }!
            XCTAssertLessThan(cap.heights.max() ?? 0, 20, "Widget \(id) still has a tall pile")
        }
    }
}
