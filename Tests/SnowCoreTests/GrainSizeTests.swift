import Foundation
import XCTest
@testable import SnowCore

/// The physical (granular) snow can use larger grains. Switching keeps every existing grain's
/// area and the simulation keeps working at the new size.
final class GrainSizeTests: XCTestCase {
    private func world() -> SnowSimulation {
        let simulation = SnowSimulation(size: SIMD2(1920, 1080), budget: SimulationBudget(flakes: 0), seed: 4)
        simulation.updateScene(surfaces: [Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 1080, width: 1920)],
                               bodies: [])
        return simulation
    }

    func testNormalIsTheDefaultAndKeepsTheBudgetedPitch() {
        let simulation = world()
        XCTAssertEqual(simulation.grainSize, .normal)
        let reference = GranularSnow(size: SIMD2(1920, 1080), maxCells: SimulationBudget(flakes: 0).cells * 32,
                                     maxActive: SimulationBudget(flakes: 0).maximumGranules)
        XCTAssertEqual(simulation.looseSnow.cellSize, reference.cellSize, accuracy: 0.0001)
    }

    func testLargerGrainSizesScaleTheGrainPitch() {
        let simulation = world()
        let normal = simulation.looseSnow.cellSize
        simulation.grainSize = .large
        XCTAssertEqual(simulation.looseSnow.cellSize, normal * 1.5, accuracy: normal * 0.05)
        simulation.grainSize = .extraLarge
        XCTAssertEqual(simulation.looseSnow.cellSize, normal * 2, accuracy: normal * 0.05)
        simulation.grainSize = .normal
        XCTAssertEqual(simulation.looseSnow.cellSize, normal, accuracy: 0.0001)
    }

    func testSwitchingKeepsExistingGrainsAndTheyStillFall() {
        let simulation = world()
        _ = simulation.looseSnow.add(mass: 200, at: SIMD2(600, 300))
        _ = simulation.looseSnow.add(mass: 120, at: SIMD2(1200, 500))
        let before = simulation.looseSnow.totalMass + simulation.pendingTransferMass
        XCTAssertGreaterThan(before, 300)

        simulation.grainSize = .extraLarge
        XCTAssertEqual(simulation.looseSnow.totalMass + simulation.pendingTransferMass, before, accuracy: before * 0.01)

        let highest = { simulation.looseSnow.active.map { simulation.looseSnow.position(of: $0).y }.min() ?? 0 }
        let start = highest()
        for _ in 0..<30 { simulation.step(dt: 1 / 30, cursor: nil) }
        XCTAssertGreaterThan(highest(), start, "Grains keep falling at the new size")
    }
}
