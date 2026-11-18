import Foundation
import XCTest
@testable import SnowCore

/// Hollows between windows are containers of snow, even when several windows form them: one
/// shared surface fills up to the outlet (the shorter wall), then an ordinary cap, and only the
/// outlet overflows, onto that window's top or off it as loose snow. Nothing is lost.
final class SnowBasinTests: XCTestCase {
    private let ground = Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 800, width: 1600)

    private func make(_ surfaces: [Surface], _ bodies: [SolidBody]) -> SnowSimulation {
        let simulation = SnowSimulation(size: SIMD2(1600, 800), budget: SimulationBudget(flakes: 0, debris: 96), seed: 4)
        simulation.updateScene(surfaces: [ground] + surfaces, bodies: bodies)
        simulation.clear()
        simulation.snowfall = .light
        simulation.step(dt: 1 / 30, cursor: nil)
        return simulation
    }

    private func window(_ id: UInt64, x: Float, y: Float, width: Float, height: Float = 400,
                        visible: [Span]? = nil, sky: [Span]? = nil) -> (Surface, SolidBody) {
        (Surface(id: id, x: x, y: y, width: width, visibleSpans: visible, snowfallSpans: sky),
         SolidBody(id: id, bounds: CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))))
    }

    private func make(_ windows: [(Surface, SolidBody)]) -> SnowSimulation { make(windows.map(\.0), windows.map(\.1)) }
    private func drift(_ s: SnowSimulation, _ id: UInt64) -> SnowDrift { s.drifts.first { $0.surface.id == id }! }
    private func index(_ d: SnowDrift, x: Float) -> Int { Int(((x - d.surface.x) / d.spacing).rounded()) }
    private func basin(_ s: SnowSimulation, _ id: UInt64, x: Float) -> SnowSimulation.Basin? {
        let d = drift(s, id)
        return d.basin(at: index(d, x: x)).map { s.basins[$0] }
    }
    private func top(_ d: SnowDrift, _ i: Int) -> Float { d.surface.baseY(at: Float(i) * d.spacing) - d.heights[i] }
    private func total(_ s: SnowSimulation) -> Float {
        s.drifts.reduce(0) { $0 + $1.heights.reduce(0, +) * $1.spacing } + s.looseSnow.totalMass + s.pendingTransferMass
    }

    /// From a real desktop: the Reminders widget (54) and LINE (85) are the walls; the terminal's
    /// top (136) and Spotify's top (122) together floor the hollow between them.
    private func realDesktop() -> SnowSimulation {
        make([window(41, x: 196, y: 54, width: 164, height: 156),
              window(398, x: 321, y: 136, width: 1178, height: 535, visible: [Span(39, 87), Span(889, 1178)],
                     sky: [Span(39, 64), Span(1170, 1178)]),
              window(11627, x: 385, y: 122, width: 1106, height: 600, visible: [Span(0, 49), Span(799, 1106)],
                     sky: [Span(0, 23), Span(825, 1106)]),
              window(8328, x: 408, y: 85, width: 802, height: 700)])
    }

    func testSingleSlitFillsToItsShorterWall() {
        let s = make([window(1, x: 196, y: 54, width: 164, height: 156), window(2, x: 385, y: 122, width: 500),
                      window(3, x: 327, y: 138, width: 700, visible: [Span(33, 700)], sky: [Span(33, 58)])])
        let b = basin(s, 3, x: 372)
        XCTAssertEqual(b?.level ?? 0, 122, accuracy: 0.5)
        XCTAssertEqual(b?.wallID, 2)
        XCTAssertEqual(b?.outward, 1)
        XCTAssertNil(basin(s, 2, x: 500), "Spotify's open top is not a basin")
    }

    func testSeveralWindowsFormOneBasin() {
        let s = realDesktop()
        let low = basin(s, 398, x: 372), high = basin(s, 11627, x: 396)
        XCTAssertEqual(low?.level ?? 0, 85, accuracy: 0.5, "Filled up to LINE's top")
        XCTAssertEqual(high?.level ?? 0, 85, accuracy: 0.5)
        XCTAssertEqual(low?.wallID, 8328)
        XCTAssertEqual(drift(s, 398).basin(at: index(drift(s, 398), x: 372)), drift(s, 11627).basin(at: index(drift(s, 11627), x: 396)),
                       "One basin across both floors")
        XCTAssertNil(basin(s, 8328, x: 600))
    }

    func testSnowLandingOnOneFloorFillsTheWholeBasinAsOneSurface() {
        let s = realDesktop()
        let terminal = drift(s, 398), spotify = drift(s, 11627)
        for _ in 0..<(60 * 30) {
            _ = terminal.depositSnowfall(at: 372 - 321, mass: 6)
            s.step(dt: 1 / 30, cursor: nil)
        }
        let members = s.basins.flatMap(\.members).sorted { $0.x < $1.x }
        XCTAssertGreaterThan(spotify.heights[index(spotify, x: 396)], 5, "Snow landing on the terminal also fills Spotify's part")
        // Away from the outlet (where the cap eases down to LINE's own snow) the surface is level.
        let tops = members.filter { $0.x < 408 - 16 }.map { top($0.drift, $0.index) }
        // Filled, it is an ordinary top: the cap undulates a little, as on any window.
        XCTAssertLessThan((tops.max() ?? 0) - (tops.min() ?? 0), 6, "One shared snow surface")
    }

    func testAFlatHundredPointHollowIsOneBasin() {
        let s = make([window(1, x: 100, y: 100, width: 50), window(2, x: 250, y: 100, width: 50), window(3, x: 150, y: 200, width: 100)])
        let floor = drift(s, 3)
        for x in stride(from: Float(154), through: 246, by: 4) {
            XCTAssertNotNil(floor.basin(at: index(floor, x: x)), "x \(x) is in the hollow")
        }
    }

    func testAPlatformBelowTheLevelJoinsTheBasinAndOneAboveSplitsIt() {
        func scene(platform: Float) -> SnowSimulation {
            make([window(1, x: 50, y: 100, width: 50), window(2, x: 100, y: 200, width: 50), window(3, x: 150, y: platform, width: 30),
                  window(4, x: 180, y: 200, width: 50), window(5, x: 230, y: 120, width: 50)])
        }
        let joined = scene(platform: 150)
        XCTAssertNotNil(basin(joined, 2, x: 125))
        XCTAssertEqual(drift(joined, 2).basin(at: index(drift(joined, 2), x: 125)), drift(joined, 4).basin(at: index(drift(joined, 4), x: 205)))
        XCTAssertEqual(basin(joined, 2, x: 125)?.level ?? 0, 120, accuracy: 0.5)
        let split = scene(platform: 110)
        XCTAssertEqual(basin(split, 2, x: 125)?.level ?? 0, 110, accuracy: 0.5, "The left pool overflows onto the platform")
        XCTAssertEqual(basin(split, 4, x: 205)?.level ?? 0, 120, accuracy: 0.5, "The right pool overflows onto the right wall")
        XCTAssertNotEqual(drift(split, 2).basin(at: index(drift(split, 2), x: 125)), drift(split, 4).basin(at: index(drift(split, 4), x: 205)))
    }

    func testAGapDownToTheFloorIsNoContainer() {
        let s = make([window(1, x: 0, y: 100, width: 100), window(2, x: 101, y: 200, width: 99), window(3, x: 200, y: 100, width: 100)])
        XCTAssertNil(basin(s, 2, x: 150), "A 1 pt gap lets the snow fall to the floor")
    }

    func testAWideHollowIsNoContainer() {
        let s = make([window(1, x: 0, y: 100, width: 100), window(2, x: 100, y: 300, width: 300), window(3, x: 400, y: 100, width: 100)])
        XCTAssertNil(basin(s, 2, x: 250))
    }

    func testOverflowWithoutAWallTopFallsAsLooseSnowAndNothingIsLost() {
        // Spotify's body is there but it has no snow top of its own (past the surface budget).
        func scene() -> SnowSimulation {
            make([window(1, x: 196, y: 54, width: 164, height: 156).0, window(3, x: 327, y: 138, width: 700, visible: [Span(33, 700)], sky: [Span(33, 58)]).0],
                 [window(1, x: 196, y: 54, width: 164, height: 156).1, window(2, x: 385, y: 122, width: 500).1,
                  window(3, x: 327, y: 138, width: 700, visible: [Span(33, 700)], sky: [Span(33, 58)]).1])
        }
        let s = scene(), control = scene()
        XCTAssertNotNil(basin(s, 3, x: 372))
        drift(s, 3).addOverload(at: 45, mass: 3_000)
        for _ in 0..<(5 * 30) { s.step(dt: 1 / 30, cursor: nil); control.step(dt: 1 / 30, cursor: nil) }
        XCTAssertEqual(total(s) - total(control), 3_000, accuracy: 3_000 * 0.02, "Overflow becomes loose snow, not nothing")
        XCTAssertGreaterThan(s.looseSnow.totalMass + s.pendingTransferMass, 100)
    }

    func testTheFullBasinMeetsTheOutletWallsSnowWithoutAStep() {
        let s = realDesktop()
        let terminal = drift(s, 398)
        terminal.addOverload(at: 372 - 321, mass: 3_000)
        for _ in 0..<(10 * 30) { s.step(dt: 1 / 30, cursor: nil) }
        let members = s.basins.flatMap(\.members).sorted { $0.x < $1.x }
        var worst: Float = 0
        for (a, b) in zip(members, members.dropFirst()) where b.x - a.x < 6 {
            worst = max(worst, abs(top(a.drift, a.index) - top(b.drift, b.index)))
        }
        XCTAssertLessThanOrEqual(worst, 4, "No notch or step inside the basin")
        let line = drift(s, 8328)
        let lastMember = members.last!
        XCTAssertEqual(top(lastMember.drift, lastMember.index), top(line, 1), accuracy: 6, "The basin's snow meets LINE's snow")
    }

    func testRoundedCornersAtTheSeamLeaveNoNotch() {
        // From the latest real desktop dump: the Reminders widget (54), the terminal (144) as the
        // floor and Spotify (122) as the outlet, both windows with 26 pt rounded corners.
        let widget = (Surface(id: 41, x: 196, y: 54, width: 164, cornerRadius: 22),
                      SolidBody(id: 41, bounds: CGRect(x: 196, y: 54, width: 164, height: 156), cornerRadius: 22))
        let terminal = (Surface(id: 398, x: 325, y: 144, width: 1234, visibleSpans: [Span(35, 86), Span(1140, 1234)],
                                cornerRadius: 26, snowfallSpans: [Span(35, 60), Span(1166, 1234)]),
                        SolidBody(id: 398, bounds: CGRect(x: 325, y: 144, width: 1234, height: 535), cornerRadius: 26))
        let spotify = (Surface(id: 11627, x: 385, y: 122, width: 1106, cornerRadius: 26),
                       SolidBody(id: 11627, bounds: CGRect(x: 385, y: 122, width: 1106, height: 721), cornerRadius: 26))
        let s = make([widget.0, terminal.0, spotify.0], [widget.1, terminal.1, spotify.1])
        drift(s, 398).addOverload(at: 372 - 325, mass: 6_000)
        for _ in 0..<(20 * 30) { s.step(dt: 1 / 30, cursor: nil) }
        // The visible snow surface: at each x, the highest snow top of any top drawn there.
        func surface(at x: Float) -> Float {
            s.drifts.compactMap { d -> Float? in
                let local = x - d.surface.x
                guard local >= 0, local <= d.surface.width, d.surface.isExposed(at: local), d.surface.id != DesktopSceneBuilder.groundID else { return nil }
                return d.surface.baseY(at: local) - d.height(at: local)
            }.min() ?? 800
        }
        var worst: Float = 0, at: Float = 0
        for x in stride(from: Float(362), through: 430, by: 1) {
            let jump = abs(surface(at: x + 1) - surface(at: x))
            if jump > worst { worst = jump; at = x }
        }
        XCTAssertLessThanOrEqual(worst, 4, "A \(worst) pt notch at x \(at)")
    }

    func testABasinFillsInAStrongWindThatClearsCornersElsewhere() {
        // From the real desktop: a strong westward wind makes the walls' lee sides snow-free, but
        // snow still collects in the hollow.
        let s = make([window(1, x: 196, y: 54, width: 164, height: 156), window(2, x: 385, y: 122, width: 500),
                      window(3, x: 327, y: 138, width: 700, visible: [Span(33, 700)], sky: [Span(33, 58)])])
        s.wind = WindSettings(vector: SIMD2(-0.86, 0.5))
        let floor = drift(s, 3)
        for _ in 0..<(90 * 30) { s.step(dt: 1 / 30, cursor: nil) }
        XCTAssertGreaterThan(floor.heights[index(floor, x: 372)], 4, "Snow collects in the hollow despite the wind")
    }

    func testAWindowFarBelowTheHollowIsNotPartOfIt() {
        // A widget far below, at the same x as the hollow: its top must not be filled up to the
        // hollow's level as a pillar.
        let s = make([window(1, x: 196, y: 54, width: 164, height: 156), window(2, x: 385, y: 122, width: 500),
                      window(3, x: 327, y: 138, width: 700, visible: [Span(33, 700)], sky: [Span(33, 58)]),
                      window(4, x: 340, y: 585, width: 100, height: 100)])
        let low = drift(s, 4)
        XCTAssertTrue(low.heights.indices.allSatisfy { low.basin(at: $0) == nil }, "The low widget is no floor of the hollow above")
    }

    func testSnowBehindAnotherWindowNeverRisesAboveIt() {
        let s = make([window(1, x: 196, y: 54, width: 164, height: 156), window(2, x: 385, y: 122, width: 500),
                      window(3, x: 327, y: 138, width: 700, visible: [Span(33, 700)], sky: [Span(33, 58)])])
        let bottom = drift(s, 3)
        bottom.addOverload(at: 50, mass: 12_000)
        for _ in 0..<(20 * 30) { s.step(dt: 1 / 30, cursor: nil) }
        let inside = bottom.heights.indices.filter { Float($0) * bottom.spacing > 62 && Float($0) * bottom.spacing < 550 }
        XCTAssertLessThanOrEqual(inside.map { bottom.heights[$0] }.max() ?? 0, 138 - 122 + 0.01)
    }
}
