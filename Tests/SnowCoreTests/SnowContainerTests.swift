import Foundation
import XCTest
@testable import SnowCore

/// A hollow between taller windows is a container, even when several windows form it: snow fills
/// it up to the shorter wall with an ordinary cap over that, and what does not fit spills over the
/// shorter wall onto that window's top, never over the taller one.
final class SnowContainerTests: XCTestCase {
    private let floor = Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 800, width: 1600)

    private func make(_ surfaces: [Surface], _ bodies: [SolidBody]) -> SnowSimulation {
        let simulation = SnowSimulation(size: SIMD2(1600, 800), budget: SimulationBudget(flakes: 0, debris: 96), seed: 4)
        simulation.updateScene(surfaces: [floor] + surfaces, bodies: bodies)
        simulation.clear()
        simulation.step(dt: 1 / 30, cursor: nil)
        return simulation
    }

    /// From a real desktop: the Reminders widget (top 54) and LINE (top 85) are the walls; the
    /// terminal's top (136) and Spotify's top (122) together form the floor between them.
    private func multiWindow() -> SnowSimulation {
        make([Surface(id: 41, x: 196, y: 54, width: 164),
              Surface(id: 398, x: 321, y: 136, width: 1178, visibleSpans: [Span(39, 87), Span(889, 1178)],
                      snowfallSpans: [Span(39, 64), Span(1170, 1178)]),
              Surface(id: 11627, x: 385, y: 122, width: 1106, visibleSpans: [Span(0, 49), Span(799, 1106)],
                      snowfallSpans: [Span(0, 23), Span(825, 1106)]),
              Surface(id: 8328, x: 408, y: 85, width: 802)],
             [SolidBody(id: 41, bounds: CGRect(x: 196, y: 54, width: 164, height: 156)),
              SolidBody(id: 398, bounds: CGRect(x: 321, y: 136, width: 1178, height: 535)),
              SolidBody(id: 11627, bounds: CGRect(x: 385, y: 122, width: 1106, height: 600)),
              SolidBody(id: 8328, bounds: CGRect(x: 408, y: 85, width: 802, height: 700))])
    }

    private func drift(_ simulation: SnowSimulation, _ id: UInt64) -> SnowDrift { simulation.drifts.first { $0.surface.id == id }! }
    private func area(_ drift: SnowDrift) -> Float { drift.heights.reduce(0, +) * drift.spacing }
    private func sample(_ drift: SnowDrift, x: Float) -> Int { Int(((x - drift.surface.x) / drift.spacing).rounded()) }

    func testSeveralWindowsFormOneContainerFilledToTheShorterWall() {
        let simulation = multiWindow()
        let terminal = drift(simulation, 398), spotify = drift(simulation, 11627)
        let low = terminal.container(at: sample(terminal, x: 372))
        let high = spotify.container(at: sample(spotify, x: 396))
        XCTAssertEqual(low?.depth ?? 0, 136 - 85, accuracy: 1, "The terminal's part fills up to LINE's top")
        XCTAssertEqual(high?.depth ?? 0, 122 - 85, accuracy: 1, "Spotify's part fills up to LINE's top too")
        XCTAssertEqual(low?.wallID, 8328, "It overflows over LINE, the shorter wall")
        XCTAssertEqual(high?.wallID, 8328)
        XCTAssertNil(drift(simulation, 8328).container(at: 20), "LINE's own top is not in the hollow")
    }

    func testTheFilledContainerIsOneSurfaceAndSpillsOverTheShorterWall() {
        let simulation = multiWindow(), control = multiWindow()
        let terminal = drift(simulation, 398), spotify = drift(simulation, 11627)
        for _ in 0..<(90 * 30) {
            terminal.addOverload(at: 372 - 321, mass: 3)
            spotify.addOverload(at: 396 - 385, mass: 3)
            simulation.step(dt: 1 / 30, cursor: nil)
            control.step(dt: 1 / 30, cursor: nil)
        }
        func meanTop(_ d: SnowDrift) -> Float {
            let inside = d.heights.indices.filter { d.container(at: $0) != nil }
            return inside.map { d.surface.baseY(at: Float($0) * d.spacing) - d.heights[$0] }.reduce(0, +) / Float(max(1, inside.count))
        }
        XCTAssertLessThan(meanTop(terminal), 86, "The terminal's part is filled past LINE's top")
        XCTAssertEqual(meanTop(terminal), meanTop(spotify), accuracy: 6, "One snow surface across both floors")
        let junction = terminal.heights.indices.filter { let x = terminal.surface.x + Float($0) * terminal.spacing; return x > 380 && x < 385 }
        XCTAssertTrue(junction.allSatisfy { terminal.container(at: $0) != nil }, "No dip where the two floors meet")
        XCTAssertGreaterThan(area(drift(simulation, 8328)) - area(drift(control, 8328)), 300, "The overflow lands on LINE")
        XCTAssertEqual(area(drift(simulation, 41)), area(drift(control, 41)), accuracy: 1, "Nothing climbs the taller wall")
        XCTAssertLessThanOrEqual(terminal.heights.max() ?? 0, 136 - 85 + 18 + 8, "No tower over the container")
    }

    func testASingleSlitFillsToItsShorterWall() {
        let simulation = make([Surface(id: 1, x: 196, y: 54, width: 164), Surface(id: 2, x: 385, y: 122, width: 500),
                               Surface(id: 3, x: 327, y: 138, width: 700, visibleSpans: [Span(33, 700)], snowfallSpans: [Span(33, 58)])],
                              [SolidBody(id: 1, bounds: CGRect(x: 196, y: 54, width: 164, height: 156)),
                               SolidBody(id: 2, bounds: CGRect(x: 385, y: 122, width: 500, height: 500)),
                               SolidBody(id: 3, bounds: CGRect(x: 327, y: 138, width: 700, height: 500))])
        let floor = drift(simulation, 3)
        XCTAssertEqual(floor.container(at: sample(floor, x: 372))?.depth ?? 0, 16, accuracy: 1)
        XCTAssertNil(drift(simulation, 2).container(at: 100), "Spotify's open top is not a container")
    }

    func testAWideGapBetweenTallWindowsIsNotAContainer() {
        let simulation = make([Surface(id: 1, x: 100, y: 100, width: 100), Surface(id: 2, x: 500, y: 100, width: 100),
                               Surface(id: 3, x: 0, y: 300, width: 800)],
                              [SolidBody(id: 1, bounds: CGRect(x: 100, y: 100, width: 100, height: 600)),
                               SolidBody(id: 2, bounds: CGRect(x: 500, y: 100, width: 100, height: 600)),
                               SolidBody(id: 3, bounds: CGRect(x: 0, y: 300, width: 800, height: 400))])
        let low = drift(simulation, 3)
        XCTAssertNil(low.container(at: sample(low, x: 350)), "300 pt apart: snow does not fill the whole gap")
    }
}
