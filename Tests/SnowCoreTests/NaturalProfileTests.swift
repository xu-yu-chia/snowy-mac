import Foundation
import XCTest
@testable import SnowCore

/// Settled snow keeps a natural, uneven surface: a full or glove-pushed cap is not a flat
/// plateau, a pushed mound keeps its shape instead of being smeared flat, and an overloaded cap
/// lets snow slide off its edges gradually rather than in sudden chunks.
final class NaturalProfileTests: XCTestCase {
    private let top = Surface(id: 1, x: 300, y: 300, width: 400)
    private let body = SolidBody(id: 1, bounds: CGRect(x: 300, y: 300, width: 400, height: 300))

    private func world() -> (SnowSimulation, SnowDrift) {
        let simulation = SnowSimulation(size: SIMD2(1000, 800),
                                        budget: SimulationBudget(flakes: 0, debris: 96), seed: 21)
        simulation.updateScene(surfaces: [top], bodies: [body])
        simulation.clear()
        simulation.snowfall = .light
        return (simulation, simulation.drifts.first { $0.surface.id == 1 }!)
    }

    private func middle(_ drift: SnowDrift) -> ArraySlice<Float> {
        drift.heights[(drift.heights.count / 5)..<(drift.heights.count * 4 / 5)]
    }

    private func variation(_ values: ArraySlice<Float>) -> Float {
        let mean = values.reduce(0, +) / Float(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(values.count)
        return sqrt(variance) / max(0.0001, mean)
    }

    func testPhysicallyFullCapIsNotAFlatPlateau() {
        let (_, cap) = world()
        for i in cap.heights.indices { _ = cap.depositMass(at: Float(i) * cap.spacing, mass: 1_000) }
        XCTAssertGreaterThan(variation(middle(cap)), 0.05, "A full cap should undulate, not sit flat")
    }

    func testPushedMoundKeepsItsShapeWhileSettling() {
        let (simulation, cap) = world()
        // A gentle mound, well under the angle of repose, as the glove leaves it.
        let center = cap.heights.count / 2
        for i in cap.heights.indices {
            cap.heights[i] = max(0, 9 - Float(abs(i - center)) * cap.spacing * 0.15)
        }
        let peak = cap.heights[center]
        for _ in 0..<(5 * 30) { simulation.step(dt: 1 / 30, cursor: nil) }
        XCTAssertGreaterThan(cap.heights[center], peak * 0.8, "Settling smeared the mound flat")
    }

    func testSteepCliffStillSlumps() {
        let (simulation, cap) = world()
        let center = cap.heights.count / 2
        for i in cap.heights.indices { cap.heights[i] = i < center ? 12 : 0 }
        for _ in 0..<(5 * 30) { simulation.step(dt: 1 / 30, cursor: nil) }
        // Snow beyond the angle of repose flows down the cliff face.
        XCTAssertGreaterThan(cap.heights[center + 1], 1)
    }

    func testOverloadedCapShedsGraduallyNotInChunks() {
        let (simulation, cap) = world()
        for i in cap.heights.indices { _ = cap.depositMass(at: Float(i) * cap.spacing, mass: 1_000) }
        cap.addOverload(at: 200, mass: 300)
        var largestDrop: Float = 0, totalShed: Float = 0
        var previous = cap.heights.reduce(0, +) * cap.spacing
        for _ in 0..<(6 * 30) {
            simulation.step(dt: 1 / 30, cursor: nil)
            let now = cap.heights.reduce(0, +) * cap.spacing
            largestDrop = max(largestDrop, previous - now)
            totalShed += max(0, previous - now)
            previous = now
        }
        XCTAssertGreaterThan(totalShed, 50, "The overload still slides off")
        XCTAssertLessThan(largestDrop, previous * 0.01, "Shedding should trickle, not drop chunks")
    }
}
