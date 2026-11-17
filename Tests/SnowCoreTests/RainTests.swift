import Foundation
import XCTest
@testable import SnowCore

/// Rain: streak drops fill puddles on tops and a flood at the bottom that reaches its cap (the
/// Dock top, 60 pt without one) in about 5 minutes at Steady. Drops never build snow.
final class RainTests: XCTestCase {
    private let floor = Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 1080, width: 1920)

    private func world(_ snowfall: Snowfall = .steady, flakes: Int = 400,
                       window: (Surface, SolidBody)? = nil) -> SnowSimulation {
        let simulation = SnowSimulation(size: SIMD2(1920, 1080), budget: SimulationBudget(flakes: flakes, debris: 96), seed: 11)
        simulation.updateScene(surfaces: [floor] + (window.map { [$0.0] } ?? []),
                               bodies: window.map { [$0.1] } ?? [])
        simulation.clear()
        simulation.snowfall = snowfall
        simulation.weather = .rain
        return simulation
    }

    private func window(x: Float = 600, y: Float = 400, width: Float = 400, height: Float = 400) -> (Surface, SolidBody) {
        (Surface(id: 1, x: x, y: y, width: width),
         SolidBody(id: 1, bounds: CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))))
    }

    private func run(_ simulation: SnowSimulation, seconds: Float, dt: Float = 1 / 30) {
        for _ in 0..<Int(seconds / dt) { simulation.step(dt: dt, cursor: nil) }
    }

    func testRainFillsFloodToCapInAboutFiveMinutesAtSteady() {
        let simulation = world()
        XCTAssertEqual(simulation.flood.cap, FloodField.fallbackCap, "No Dock: the fallback cap")
        run(simulation, seconds: 150)
        let half = simulation.flood.level / simulation.flood.cap
        XCTAssertGreaterThan(half, 0.35)
        XCTAssertLessThan(half, 0.65)
        run(simulation, seconds: 180)
        XCTAssertEqual(simulation.flood.level, simulation.flood.cap, accuracy: 0.001)
    }

    func testDensityOrdersFillRate() {
        let levels = [Snowfall.light, .steady, .flurry].map { density -> Float in
            let simulation = world(density)
            run(simulation, seconds: 60)
            return simulation.flood.level
        }
        XCTAssertLessThan(levels[0], levels[1])
        XCTAssertLessThan(levels[1], levels[2])
    }

    func testDropsNeverSettleAsSnow() {
        let simulation = world(window: window())
        run(simulation, seconds: 20)
        XCTAssertTrue(simulation.drifts.allSatisfy { $0.heights.allSatisfy { $0 == 0 } })
        XCTAssertTrue(simulation.flakes.isEmpty)
        XCTAssertFalse(simulation.raindrops.isEmpty)
    }

    func testDropOnTopFillsItsPuddle() {
        let simulation = world(window: window())
        run(simulation, seconds: 5)
        XCTAssertGreaterThan(simulation.drifts.first { $0.surface.id == 1 }!.puddle, 0)
    }

    func testDropOnWallBecomesADrip() {
        let simulation = world(window: window(height: 600))
        simulation.wind = WindSettings(vector: SIMD2(1, 0))
        var sawWallDrip = false
        for _ in 0..<60 {
            simulation.step(dt: 1 / 30, cursor: nil)
            // Too early for the puddle to overflow, so drips at the left wall came from drops.
            if simulation.drips.contains(where: { abs($0.position.x - 599) < 1.5 && $0.position.y > 420 }) {
                sawWallDrip = true
            }
        }
        XCTAssertTrue(sawWallDrip)
    }

    private func floodArea(_ simulation: SnowSimulation) -> Float {
        simulation.flood.level * simulation.flood.width
    }

    func testDripsReachTheFloodAndAddWater() {
        let wet = world(flakes: 0), dry = world(flakes: 0)
        wet.pendingRunoff.append((SIMD2(300, 500), 5_000))
        run(wet, seconds: 3)
        run(dry, seconds: 3)
        XCTAssertTrue(wet.drips.isEmpty)
        XCTAssertEqual(floodArea(wet) - floodArea(dry), 5_000, accuracy: 50)
    }

    func testDripBudgetBoundedAndWaterConserved() {
        let wet = world(flakes: 0), dry = world(flakes: 0)
        for i in 0..<500 { wet.pendingRunoff.append((SIMD2(Float(i * 3 + 20), 200), 10)) }
        wet.step(dt: 1 / 30, cursor: nil)
        dry.step(dt: 1 / 30, cursor: nil)
        XCTAssertLessThanOrEqual(wet.drips.count, SnowSimulation.maximumDrips)
        let dripWater = wet.drips.reduce(0) { $0 + $1.area }
        XCTAssertEqual(floodArea(wet) - floodArea(dry) + dripWater, 5_000, accuracy: 50)
    }

    func testReducedMotionRainStillFillsFlood() {
        let moving = world(), still = world()
        still.reducedMotion = true
        run(moving, seconds: 60)
        run(still, seconds: 60)
        XCTAssertTrue(still.raindrops.isEmpty)
        XCTAssertEqual(still.flood.level, moving.flood.level, accuracy: moving.flood.level * 0.2)
    }

    func testWindSlantsDrops() {
        let simulation = world()
        simulation.wind = WindSettings(vector: SIMD2(1, 0))
        run(simulation, seconds: 1)
        let mean = simulation.raindrops.reduce(0) { $0 + $1.velocity.x } / Float(simulation.raindrops.count)
        XCTAssertGreaterThan(mean, 40)
    }

    func testFloodCapFollowsTheDockTop() {
        let dock = Surface(id: DesktopSceneBuilder.dockID, x: 500, y: 1000, width: 900, isDock: true)
        let simulation = world()
        simulation.updateScene(surfaces: [floor, dock], bodies: [])
        simulation.step(dt: 1 / 30, cursor: nil)
        XCTAssertEqual(simulation.flood.cap, 80, accuracy: 0.001)
    }

    func testStreakInstancesCoverDropsAndDrips() {
        let simulation = world()
        simulation.pendingRunoff.append((SIMD2(300, 500), 100))
        simulation.step(dt: 1 / 30, cursor: nil)
        let streaks = simulation.streakInstances()
        XCTAssertEqual(streaks.count, simulation.raindrops.count + simulation.drips.count + simulation.splashes.count)
        XCTAssertEqual(MemoryLayout<StreakInstance>.stride, 24)
    }
}
