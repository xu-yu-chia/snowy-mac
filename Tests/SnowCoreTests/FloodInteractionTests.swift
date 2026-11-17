import Foundation
import XCTest
@testable import SnowCore

/// The flood reacts like a fluid: the pointer moving through it leaves a wake, fast strokes splash
/// water that falls back, windows moving in it push waves, and the glove brushes puddles off tops.
final class FloodInteractionTests: XCTestCase {
    private let floor = Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 1080, width: 1920)

    /// No visible drops, so the only waves are the ones the test makes.
    private func world(window: (Surface, SolidBody)? = nil, level: Float = 40) -> SnowSimulation {
        let simulation = SnowSimulation(size: SIMD2(1920, 1080), budget: SimulationBudget(flakes: 0, debris: 96), seed: 3)
        simulation.updateScene(surfaces: [floor] + (window.map { [$0.0] } ?? []), bodies: window.map { [$0.1] } ?? [])
        simulation.clear()
        simulation.weather = .rain
        simulation.flood.add(area: level * 1920)
        return simulation
    }

    private func stroke(_ simulation: SnowSimulation, from start: SIMD2<Float>, velocity: SIMD2<Float>, frames: Int) {
        var cursor = start
        simulation.step(dt: 1 / 60, cursor: cursor)
        for _ in 0..<frames {
            cursor += velocity / 60
            simulation.step(dt: 1 / 60, cursor: cursor)
        }
    }

    private func maxWave(_ simulation: SnowSimulation) -> Float {
        simulation.flood.heights.map(abs).max() ?? 0
    }

    func testPointerMovingThroughWaterMakesAWake() {
        let simulation = world()
        stroke(simulation, from: SIMD2(900, 1060), velocity: SIMD2(300, 0), frames: 6)
        let x: Float = 930
        XCTAssertLessThan(simulation.flood.height(at: x + 20), 0, "Water ahead of the pointer is pushed down")
        XCTAssertGreaterThan(simulation.flood.height(at: x - 20), 0, "Water behind it rises")
    }

    func testPointerAboveWaterDoesNothing() {
        let simulation = world()
        stroke(simulation, from: SIMD2(900, 500), velocity: SIMD2(300, 0), frames: 6)
        XCTAssertEqual(maxWave(simulation), 0)
    }

    private func volume(_ simulation: SnowSimulation) -> Float {
        simulation.flood.level * simulation.flood.width
            + simulation.splashes.reduce(0) { $0 + $1.area } + simulation.drips.reduce(0) { $0 + $1.area }
    }

    func testFastStrokeSplashesDropletsThatReturnTheirWater() {
        let simulation = world(), control = world()
        stroke(simulation, from: SIMD2(700, 1060), velocity: SIMD2(900, 0), frames: 6)
        stroke(control, from: SIMD2(700, 500), velocity: SIMD2(900, 0), frames: 6)
        XCTAssertTrue(simulation.splashes.contains { $0.area > 0 }, "A fast stroke throws water")
        for _ in 0..<180 {
            simulation.step(dt: 1 / 60, cursor: nil)
            control.step(dt: 1 / 60, cursor: nil)
        }
        XCTAssertFalse(simulation.splashes.contains { $0.area > 0 }, "The water has fallen back")
        XCTAssertEqual(volume(simulation), volume(control), accuracy: volume(control) * 0.01)
    }

    func testThrownWaterDoesNotPassThroughWindows() {
        let wall = (Surface(id: 1, x: 1000, y: 700, width: 300),
                    SolidBody(id: 1, bounds: CGRect(x: 1000, y: 700, width: 300, height: 380)))
        let simulation = world(window: wall), control = world(window: wall)
        stroke(simulation, from: SIMD2(820, 1060), velocity: SIMD2(900, 0), frames: 6)
        stroke(control, from: SIMD2(820, 500), velocity: SIMD2(900, 0), frames: 6)
        XCTAssertTrue(simulation.splashes.contains { $0.area > 0 })
        for _ in 0..<180 {
            simulation.step(dt: 1 / 60, cursor: nil)
            control.step(dt: 1 / 60, cursor: nil)
            XCTAssertFalse(simulation.splashes.contains { wall.1.contains($0.position) }, "No droplet inside the window")
        }
        let held = simulation.drifts.reduce(0) { $0 + $1.puddleArea } - control.drifts.reduce(0) { $0 + $1.puddleArea }
        XCTAssertEqual(volume(simulation) + held, volume(control), accuracy: volume(control) * 0.01, "Water is conserved")
    }

    func testSlowStrokeDoesNotSplash() {
        let simulation = world()
        stroke(simulation, from: SIMD2(900, 1060), velocity: SIMD2(200, 0), frames: 6)
        XCTAssertFalse(simulation.splashes.contains { $0.area > 0 })
    }

    func testShovelPushesHarderThanGlove() {
        let glove = world(), shovel = world()
        shovel.tool = .shovel
        stroke(glove, from: SIMD2(900, 1060), velocity: SIMD2(300, 0), frames: 6)
        stroke(shovel, from: SIMD2(900, 1060), velocity: SIMD2(300, 0), frames: 6)
        XCTAssertGreaterThan(maxWave(shovel), maxWave(glove) * 1.3)
    }

    private func window(x: Float, y: Float = 700, height: Float = 370) -> (Surface, SolidBody) {
        (Surface(id: 1, x: x, y: y, width: 300),
         SolidBody(id: 1, bounds: CGRect(x: CGFloat(x), y: CGFloat(y), width: 300, height: CGFloat(height))))
    }

    func testWindowSlidingInWaterPushesAWave() {
        let simulation = world(window: window(x: 400))
        let moved = window(x: 600)
        simulation.updateScene(surfaces: [floor, moved.0], bodies: [moved.1])
        for _ in 0..<3 { simulation.step(dt: 1 / 60, cursor: nil) }
        XCTAssertGreaterThan(simulation.flood.height(at: 910), 0.05, "Water rises ahead of the leading side")
    }

    func testWindowAboveWaterMakesNoWave() {
        let simulation = world(window: window(x: 400, y: 300, height: 300))
        let moved = window(x: 600, y: 300, height: 300)
        simulation.updateScene(surfaces: [floor, moved.0], bodies: [moved.1])
        simulation.step(dt: 1 / 60, cursor: nil)
        XCTAssertEqual(maxWave(simulation), 0)
    }

    func testWindowsDoNotChangeFloodVolume() {
        let simulation = world(window: window(x: 400)), control = world(window: window(x: 400))
        let moved = window(x: 600)
        simulation.updateScene(surfaces: [floor, moved.0], bodies: [moved.1])
        simulation.step(dt: 1 / 60, cursor: nil)
        control.step(dt: 1 / 60, cursor: nil)
        XCTAssertEqual(simulation.flood.level, control.flood.level, accuracy: 0.0001)
    }

    func testGlovePushesPuddleOffTheBrushedEnd() {
        let top = (Surface(id: 1, x: 600, y: 300, width: 400),
                   SolidBody(id: 1, bounds: CGRect(x: 600, y: 300, width: 400, height: 300)))
        let simulation = world(window: top)
        let drift = simulation.drifts.first { $0.surface.id == 1 }!
        _ = drift.addWater(area: 1_000, at: 200)
        stroke(simulation, from: SIMD2(700, 298), velocity: SIMD2(150, 0), frames: 6)
        XCTAssertEqual(drift.puddle, 0, accuracy: 0.05, "Surface tension pulls the whole puddle along")
        let pushed = simulation.drips.filter { $0.position.x > 1000 }.reduce(0) { $0 + $1.area }
        XCTAssertGreaterThan(pushed, 900, "It runs off the end the stroke points to, in one go")
        XCTAssertFalse(simulation.drips.contains { $0.position.x < 600 })
    }
}
