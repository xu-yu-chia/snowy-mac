import Foundation
import XCTest
@testable import SnowCore

/// Water geometry: the flood as one quad per wave column from its surface to the screen bottom,
/// and puddles as bands on the visible part of each top (on top of any snow still there).
final class WaterMeshTests: XCTestCase {
    private let floor = Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 1080, width: 1920)

    private func world(_ surfaces: [Surface] = []) -> SnowSimulation {
        let simulation = SnowSimulation(size: SIMD2(1920, 1080), budget: SimulationBudget(flakes: 0, debris: 96), seed: 9)
        simulation.updateScene(surfaces: [floor] + surfaces, bodies: [])
        simulation.clear()
        simulation.weather = .rain
        return simulation
    }

    func testFloodMeshSpansWidthAtLevel() {
        let simulation = world()
        simulation.flood.add(area: 30 * 1920)
        simulation.rebuildWaterMesh()
        let xs = simulation.waterMesh.map(\.position.x)
        XCTAssertEqual(xs.min() ?? -1, 0, accuracy: 0.5)
        XCTAssertEqual(xs.max() ?? -1, 1920, accuracy: 0.5)
        let surface = simulation.waterMesh.filter { $0.material.x == 1 }.map(\.position.y)
        XCTAssertFalse(surface.isEmpty)
        XCTAssertTrue(surface.allSatisfy { abs($0 - 1050) <= 12.01 })
        XCTAssertLessThanOrEqual(simulation.waterMesh.count, simulation.flood.heights.count * 6)
    }

    func testNoWaterNoMesh() {
        let simulation = world()
        simulation.rebuildWaterMesh()
        XCTAssertTrue(simulation.waterMesh.isEmpty)
    }

    func testPuddleMeshOnlyOnVisibleSpans() {
        let top = Surface(id: 1, x: 600, y: 400, width: 400, visibleSpans: [Span(0, 200)])
        let simulation = world([top])
        _ = simulation.drifts.first { $0.surface.id == 1 }!.addWater(area: 400, at: 100)
        simulation.rebuildWaterMesh()
        XCTAssertFalse(simulation.waterMesh.isEmpty)
        XCTAssertTrue(simulation.waterMesh.allSatisfy { $0.position.x >= 599.9 && $0.position.x <= 800.1 })
    }

    func testPuddleSitsOnRemainingSnow() {
        let top = Surface(id: 1, x: 600, y: 400, width: 400)
        let simulation = world([top])
        let drift = simulation.drifts.first { $0.surface.id == 1 }!
        for i in drift.heights.indices { drift.heights[i] = 6 }
        _ = drift.addWater(area: 800, at: 200)
        simulation.rebuildWaterMesh()
        let middle = simulation.waterMesh.filter { abs($0.position.x - 800) < 3 }
        XCTAssertFalse(middle.isEmpty)
        let topY = middle.filter { $0.material.x == 1 }.map(\.position.y).min() ?? 0
        let bottomY = middle.filter { $0.material.x == 0 }.map(\.position.y).max() ?? 0
        XCTAssertEqual(topY, 400 - 6 - 2, accuracy: 0.05, "The water surface is on the snow")
        XCTAssertEqual(bottomY, 400 - 6 + 0.3, accuracy: 0.05)
    }

    func testWaterMeshBounded() {
        let tops = (0..<40).map { Surface(id: UInt64($0 + 1), x: Float($0) * 45, y: 300 + Float($0 % 7) * 40, width: 40) }
        let simulation = world(tops)
        simulation.flood.add(area: 50 * 1920)
        for drift in simulation.drifts { _ = drift.addWater(area: 500, at: 10) }
        simulation.rebuildWaterMesh()
        XCTAssertLessThanOrEqual(simulation.waterMesh.count, simulation.maximumWaterVertices)
    }

    func testStepKeepsWaterMeshCurrent() {
        let simulation = world()
        simulation.flood.add(area: 30 * 1920)
        simulation.flood.impulse(at: 900, velocity: -200)
        simulation.step(dt: 1 / 60, cursor: nil)
        let first = simulation.waterMesh.map(\.position.y)
        simulation.step(dt: 1 / 60, cursor: nil)
        XCTAssertNotEqual(first, simulation.waterMesh.map(\.position.y), "Waves move every frame")
    }
}
