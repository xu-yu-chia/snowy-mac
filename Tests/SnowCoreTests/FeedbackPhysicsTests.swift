import Foundation
import XCTest
@testable import SnowCore

/// Behaviour reported from real use: wall-sliding flakes vanished at rounded window corners,
/// settled snow grew far faster than the visible snowfall, and snow pushed onto a full cap sat
/// on it as a separate layer.
final class FeedbackPhysicsTests: XCTestCase {
    private let top = Surface(id: 1, x: 300, y: 300, width: 400)
    private let body = SolidBody(id: 1, bounds: CGRect(x: 300, y: 300, width: 400, height: 300))

    private func area(_ drift: SnowDrift) -> Float { drift.heights.reduce(0, +) * drift.spacing }

    // A. Rounded bottom corner of a real window.
    func testSlidingFlakeRoundsTheWindowCornerAndKeepsFalling() {
        let wall = SolidBody(id: 7, bounds: CGRect(x: 500, y: 100, width: 300, height: 600), cornerRadius: 12)
        let simulation = SnowSimulation(size: SIMD2(1000, 800), budget: SimulationBudget(flakes: 1), seed: 3)
        simulation.updateScene(surfaces: [], bodies: [wall])
        simulation.snowfall = .flurry
        simulation.wind = WindSettings(vector: SIMD2(1, 0))
        simulation.step(dt: 1 / 30, cursor: nil)
        simulation.flakes[0] = SnowParticle(position: SIMD2(497, 650), velocity: SIMD2(0, 40), radius: 1.5,
                                            opacity: 1, phase: 0, remainingLife: 100, mass: 1)
        var path: [SIMD2<Float>] = []
        for _ in 0..<300 {
            simulation.step(dt: 1 / 30, cursor: nil)
            path.append(simulation.flakes[0].position)
            if simulation.flakes[0].position.y > 740 { break }
        }
        XCTAssertTrue(zip(path, path.dropFirst()).allSatisfy { $1.y >= $0.y - 0.01 },
                      "The flake vanished (was recycled to the top) at the rounded corner")
        XCTAssertGreaterThan(path.last!.y, 700)
    }

    // B. Settled snow keeps pace with the visible snowfall.
    func testSteadySnowfallDoesNotFillACapWithinAMinute() {
        let simulation = SnowSimulation(size: SIMD2(1000, 800), budget: SimulationBudget(flakes: 0), seed: 2)
        simulation.updateScene(surfaces: [top], bodies: [body])
        simulation.clear()
        simulation.snowfall = .steady
        for _ in 0..<(60 * 30) { simulation.step(dt: 1 / 30, cursor: nil) }
        let cap = simulation.drifts.first { $0.surface.id == 1 }!
        XCTAssertLessThan(cap.fillRatio, 0.6)
        XCTAssertGreaterThan(cap.fillRatio, 0.1, "Snow must still visibly accumulate")
    }

    // C. Snow landing on a physically full cap joins it instead of stacking as a second layer.
    func testSnowLandingOnAFullCapDoesNotStackAsASeparateLayer() {
        let simulation = SnowSimulation(size: SIMD2(1000, 800), budget: SimulationBudget(flakes: 0, debris: 96), seed: 5)
        simulation.updateScene(surfaces: [top], bodies: [body])
        simulation.clear()
        let cap = simulation.drifts.first { $0.surface.id == 1 }!
        for i in cap.heights.indices { _ = cap.depositMass(at: Float(i) * cap.spacing, mass: 1_000) }
        let before = area(cap) + simulation.looseSnow.totalMass + simulation.pendingTransferMass
        let added = simulation.looseSnow.add(mass: 150, at: SIMD2(380, 270))
        let pushed = 150 - added
        XCTAssertGreaterThan(pushed, 100)

        for _ in 0..<60 { simulation.step(dt: 1 / 30, cursor: nil) }

        let stacked = simulation.looseSnow.active.filter {
            let p = simulation.looseSnow.position(of: $0)
            return p.x > 310 && p.x < 690 && p.y > 240 && p.y < 300
        }
        XCTAssertTrue(stacked.isEmpty, "\(stacked.count) grains still sit on the full cap as a layer")
        // Snowfall adds a little; nothing pushed may be lost.
        let after = area(cap) + simulation.looseSnow.totalMass + simulation.pendingTransferMass
        XCTAssertGreaterThanOrEqual(after, before + pushed - 1)
    }
}
