import Foundation
import XCTest
@testable import SnowCore

/// Snow → Rain melts settled snow into water (10:1) within ~40 s; Rain → Snow drains the flood and
/// dries puddles within ~20 s, and flakes landing on water melt into it until it is gone.
final class WeatherTransitionTests: XCTestCase {
    private let floor = Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 1080, width: 1920)
    private let top = (Surface(id: 1, x: 600, y: 400, width: 400),
                       SolidBody(id: 1, bounds: CGRect(x: 600, y: 400, width: 400, height: 300)))

    private func world(flakes: Int = 0, snowy: Bool = true) -> SnowSimulation {
        let simulation = SnowSimulation(size: SIMD2(1920, 1080), budget: SimulationBudget(flakes: flakes, debris: 96), seed: 21)
        simulation.updateScene(surfaces: [floor, top.0], bodies: [top.1])
        simulation.clear()
        if snowy {
            for drift in simulation.drifts {
                for i in drift.heights.indices { _ = drift.depositSnowfall(at: Float(i) * drift.spacing, mass: 1_000) }
            }
        }
        return simulation
    }

    private func run(_ simulation: SnowSimulation, seconds: Float, dt: Float = 1 / 30) {
        for _ in 0..<Int((seconds / dt).rounded()) { simulation.step(dt: dt, cursor: nil) }
    }

    private func snowArea(_ simulation: SnowSimulation) -> Float {
        simulation.drifts.reduce(0) { $0 + $1.heights.reduce(0, +) * $1.spacing }
    }

    private func water(_ simulation: SnowSimulation) -> Float {
        simulation.flood.level * simulation.flood.width
            + simulation.drifts.reduce(0) { $0 + $1.puddleArea }
            + simulation.drips.reduce(0) { $0 + $1.area } + simulation.splashes.reduce(0) { $0 + $1.area }
            + simulation.pendingRunoff.reduce(0) { $0 + $1.area }
    }

    func testSnowMeltsWithinFortySecondsAtTenToOne() {
        let snowy = world(), bare = world(snowy: false)
        let melted = snowArea(snowy)
        XCTAssertGreaterThan(melted, 10_000)
        snowy.weather = .rain
        bare.weather = .rain
        run(snowy, seconds: 41)
        run(bare, seconds: 41)
        XCTAssertLessThan(snowy.drifts.flatMap(\.heights).max() ?? 0, 0.01, "All snow is gone")
        XCTAssertEqual(water(snowy) - water(bare), melted / SnowSimulation.meltRatio, accuracy: melted / SnowSimulation.meltRatio * 0.02)
    }

    func testMeltedCapWaterFillsItsPuddleFirst() {
        let snowy = world(), bare = world(snowy: false)
        snowy.weather = .rain
        bare.weather = .rain
        run(snowy, seconds: 5)
        run(bare, seconds: 5)
        let wet = snowy.drifts.first { $0.surface.id == 1 }!.puddle
        XCTAssertGreaterThan(wet, bare.drifts.first { $0.surface.id == 1 }!.puddle)
    }

    func testFloodDrainsWithinTwentySecondsAfterRain() {
        let simulation = world(snowy: false)
        simulation.weather = .rain
        simulation.flood.add(area: 50 * 1920)
        simulation.weather = .snow
        run(simulation, seconds: 10)
        XCTAssertGreaterThan(simulation.flood.level, 5, "It drains gradually")
        run(simulation, seconds: 10.5)
        XCTAssertEqual(simulation.flood.level, 0)
    }

    func testPuddlesEvaporateAfterRain() {
        let simulation = world(snowy: false)
        simulation.weather = .rain
        let drift = simulation.drifts.first { $0.surface.id == 1 }!
        _ = drift.addWater(area: 1_200, at: 200)
        simulation.weather = .snow
        run(simulation, seconds: 20.5)
        XCTAssertEqual(drift.puddle, 0)
    }

    func testFlakesOnWaterMeltIntoIt() {
        let simulation = world(flakes: 400, snowy: false)
        simulation.snowfall = .flurry
        simulation.weather = .rain
        simulation.flood.add(area: 50 * 1920)
        simulation.weather = .snow
        let ground = simulation.drifts.first { $0.surface.id == DesktopSceneBuilder.groundID }!
        for _ in 0..<(8 * 30) {
            simulation.step(dt: 1 / 30, cursor: nil)
            XCTAssertLessThan(ground.heights.max() ?? 0, 0.5, "No floor snow while water is there")
        }
        XCTAssertGreaterThan(simulation.flood.level, 0)
    }

    func testSwitchingBackMidTransitionContinues() {
        let simulation = world()
        simulation.weather = .rain
        run(simulation, seconds: 10)
        let before = simulation.drifts.map(\.heights)
        XCTAssertGreaterThan(snowArea(simulation), 1_000, "Still melting")
        simulation.weather = .snow
        simulation.step(dt: 1 / 30, cursor: nil)
        for (old, drift) in zip(before, simulation.drifts) {
            for (a, b) in zip(old, drift.heights) { XCTAssertLessThan(abs(a - b), 1, "No jump") }
        }
        let level = simulation.flood.level
        simulation.weather = .rain
        simulation.step(dt: 1 / 30, cursor: nil)
        XCTAssertGreaterThanOrEqual(simulation.flood.level, level - 0.1, "Water is not reset")
    }

    func testFallingFlakesFinishWhenRainStarts() {
        let simulation = world(flakes: 400, snowy: false)
        run(simulation, seconds: 1)
        let count = simulation.flakes.count
        XCTAssertGreaterThan(count, 0)
        simulation.weather = .rain
        simulation.step(dt: 1 / 30, cursor: nil)
        XCTAssertGreaterThan(simulation.flakes.count, count / 2, "Flakes in the air keep falling")
        run(simulation, seconds: 70)
        XCTAssertTrue(simulation.flakes.isEmpty, "…and are not replaced")
    }

    func testClearEmptiesPuddlesAndFlood() {
        let simulation = world(snowy: false)
        simulation.weather = .rain
        simulation.flood.add(area: 30 * 1920)
        _ = simulation.drifts.first { $0.surface.id == 1 }!.addWater(area: 600, at: 100)
        simulation.pendingRunoff.append((SIMD2(10, 10), 50))
        simulation.clear()
        XCTAssertEqual(simulation.flood.level, 0)
        XCTAssertTrue(simulation.drifts.allSatisfy { $0.puddle == 0 })
        XCTAssertTrue(simulation.pendingRunoff.isEmpty && simulation.drips.isEmpty)
    }

    func testSnowModeWithoutWaterMeltsNothing() {
        let simulation = world()
        let before = snowArea(simulation)
        run(simulation, seconds: 5)
        XCTAssertGreaterThanOrEqual(snowArea(simulation), before * 0.99)
    }
}
