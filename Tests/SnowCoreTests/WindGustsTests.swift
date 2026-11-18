import Foundation
import XCTest
@testable import SnowCore

/// Gusts swing the set wind within ±30° and 60–130% strength (capped at full), irregularly, and
/// only moving material follows them: corner wind keeps the set wind.
final class WindGustsTests: XCTestCase {
    private let base = WindSettings(headingDegrees: 90, speedFraction: 0.5)

    private func angle(_ a: Float, from b: Float) -> Float {
        var d = (a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    func testGustsStayAroundTheSetWindAndVary() {
        var headings: [Float] = [], speeds: [Float] = []
        for step in 0..<(60 * 20) {
            let gust = WindGusts.wind(base: base, at: Double(step) / 20)
            let offset = angle(gust.headingDegrees, from: base.headingDegrees)
            XCTAssertLessThanOrEqual(abs(offset), 30.01)
            XCTAssertGreaterThanOrEqual(gust.speedFraction, 0.6 * 0.5 - 0.001)
            XCTAssertLessThanOrEqual(gust.speedFraction, 1.3 * 0.5 + 0.001)
            headings.append(offset)
            speeds.append(gust.speedFraction)
        }
        XCTAssertGreaterThan((headings.max() ?? 0) - (headings.min() ?? 0), 15, "The direction swings")
        XCTAssertGreaterThan((speeds.max() ?? 0) - (speeds.min() ?? 0), 0.15, "The strength rises and falls")
    }

    func testFullWindIsCappedAtFullStrength() {
        let full = WindSettings(headingDegrees: 270, speedFraction: 1)
        for step in 0..<600 {
            XCTAssertLessThanOrEqual(WindGusts.wind(base: full, at: Double(step) / 10).speedFraction, 1.0001)
        }
    }

    func testCalmNeverGusts() {
        for step in 0..<100 { XCTAssertEqual(WindGusts.wind(base: WindSettings(), at: Double(step)), WindSettings()) }
    }

    func testFiniteForHugeTimes() {
        let gust = WindGusts.wind(base: base, at: 1e9)
        XCTAssertTrue(gust.vector.x.isFinite && gust.vector.y.isFinite)
        XCTAssertGreaterThan(gust.speedFraction, 0.25)
    }

    private func world() -> SnowSimulation {
        let simulation = SnowSimulation(size: SIMD2(1200, 800), budget: SimulationBudget(flakes: 300, debris: 96), seed: 2)
        simulation.updateScene(surfaces: [Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 800, width: 1200)], bodies: [])
        simulation.wind = WindSettings(headingDegrees: 90, speedFraction: 0.6)
        simulation.step(dt: 1 / 30, cursor: nil)
        return simulation
    }

    func testFlakesFollowAirflowButCornerWindKeepsTheSetWind() {
        let gusting = world(), steady = world()
        XCTAssertFalse(gusting.cornerWindDirty)
        gusting.airflow = WindSettings(headingDegrees: 270, speedFraction: 0.6)
        XCTAssertFalse(gusting.cornerWindDirty, "Gusts never rebuild corner wind")
        let start = gusting.flakes.map(\.position.x)
        XCTAssertEqual(start, steady.flakes.map(\.position.x))
        for _ in 0..<15 {
            gusting.step(dt: 1 / 30, cursor: nil)
            steady.step(dt: 1 / 30, cursor: nil)
        }
        let mean = { (s: SnowSimulation) in s.flakes.reduce(0) { $0 + $1.position.x } / Float(max(1, s.flakes.count)) }
        XCTAssertLessThan(mean(gusting), mean(steady) - 10, "Flakes blow with the gusting airflow, not the set wind")
    }
}
