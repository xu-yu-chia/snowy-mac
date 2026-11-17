import Foundation
import XCTest
@testable import SnowCore

/// The flood at the bottom of a display: a mean water level that rises with incoming water up to a
/// cap (the Dock top), plus a damped 1D wave field on its surface.
final class FloodFieldTests: XCTestCase {
    private func run(_ flood: FloodField, seconds: Float) {
        for _ in 0..<Int(seconds * 60) { flood.step(dt: 1 / 60) }
    }

    func testAddedAreaRaisesLevelByAreaOverWidth() {
        let flood = FloodField(width: 1000)
        flood.cap = 82
        flood.add(area: 4000)
        XCTAssertEqual(flood.level, 4, accuracy: 0.0001)
    }

    func testLevelNeverExceedsCap() {
        let flood = FloodField(width: 1000)
        flood.cap = 82
        flood.add(area: 1e6)
        XCTAssertEqual(flood.level, 82, accuracy: 0.0001)
    }

    func testImpulseSpreadsBothWaysAndDecays() {
        let flood = FloodField(width: 1000)
        flood.cap = 82
        flood.add(area: 40_000)
        flood.impulse(at: 500, velocity: -200)
        run(flood, seconds: 0.2)
        XCTAssertNotEqual(flood.height(at: 400), 0, accuracy: 0.0001)
        XCTAssertNotEqual(flood.height(at: 600), 0, accuracy: 0.0001)
        run(flood, seconds: 6)
        XCTAssertLessThan(flood.heights.map(abs).max() ?? 0, 0.05)
    }

    func testWavesKeepMeanLevel() {
        let flood = FloodField(width: 1000)
        flood.cap = 82
        flood.add(area: 40_000)
        flood.impulse(at: 200, velocity: -300)
        flood.impulse(at: 700, velocity: 150)
        run(flood, seconds: 1)
        XCTAssertEqual(flood.heights.reduce(0, +), 0, accuracy: 1e-3)
        XCTAssertEqual(flood.level, 40, accuracy: 0.0001)
    }

    func testAmplitudeClampedAt12() {
        let flood = FloodField(width: 1000)
        flood.cap = 82
        flood.add(area: 40_000)
        flood.impulse(at: 500, velocity: 1e5)
        run(flood, seconds: 0.5)
        XCTAssertLessThanOrEqual(flood.heights.map(abs).max() ?? 0, 12.0001)
    }

    func testLoweredCapEasesDownWithinTwoSeconds() {
        let flood = FloodField(width: 1000)
        flood.cap = 82
        flood.add(area: 80_000)
        XCTAssertEqual(flood.level, 80, accuracy: 0.0001)
        flood.cap = 40
        flood.step(dt: 1 / 60)
        XCTAssertGreaterThan(flood.level, 70, "No pop when the cap drops")
        run(flood, seconds: 2.1)
        XCTAssertEqual(flood.level, 40, accuracy: 0.0001)
    }

    func testDrainReachesZero() {
        let flood = FloodField(width: 1000)
        flood.cap = 82
        flood.add(area: 60_000)
        let rate = flood.level / 20
        for _ in 0..<(20 * 60) { flood.drain(rate: rate, dt: 1 / 60) }
        XCTAssertEqual(flood.level, 0, accuracy: 0.001)
    }

    func testSurfaceYFollowsLevelAndWaves() {
        let flood = FloodField(width: 1000)
        flood.cap = 82
        flood.add(area: 30_000)
        XCTAssertEqual(flood.surfaceY(at: 300, bottom: 800), 770, accuracy: 0.0001)
        XCTAssertEqual(FloodField.fallbackCap, 60)
        flood.clear()
        XCTAssertEqual(flood.level, 0)
    }
}
