import Foundation
import XCTest
@testable import SnowCore

final class OverlapTransferTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    private func window(_ id: UInt64, x: CGFloat, y: CGFloat,
                        width: CGFloat, height: CGFloat) -> DesktopWindowRecord {
        DesktopWindowRecord(id: id, bounds: CGRect(x: x, y: y, width: width, height: height),
                            layer: 0, role: .application)
    }

    private func scene(_ records: [DesktopWindowRecord]) -> DesktopScene {
        DesktopSceneBuilder.build(displayBounds: screen, menuInset: 24, windows: records)
    }

    private func apply(_ scene: DesktopScene, to simulation: SnowSimulation) {
        simulation.updateScene(surfaces: scene.surfaces, bodies: scene.bodies)
    }

    private func world(granular: Bool = true) -> SnowSimulation {
        SnowSimulation(size: SIMD2(1000, 800),
                       budget: SimulationBudget(flakes: 0, debris: granular ? 96 : 0), seed: 71)
    }

    private func drift(_ id: UInt64, in simulation: SnowSimulation) -> SnowDrift {
        simulation.drifts.first { $0.surface.id == id }!
    }

    private func area(_ drift: SnowDrift) -> Float {
        drift.heights.reduce(0, +) * drift.spacing
    }

    private func total(_ simulation: SnowSimulation) -> Float {
        simulation.drifts.reduce(0) { $0 + area($1) }
            + simulation.looseSnow.totalMass + simulation.pendingTransferMass
    }

    private func seed(_ drift: SnowDrift, height: Float = 6) {
        for i in drift.heights.indices {
            let x = Float(i) * drift.spacing
            drift.heights[i] = x >= 20 && x <= drift.surface.width - 20 ? height : 0
        }
    }


    func testRepeatedSnapshotDoesNotTransferTheSameSnowTwice() {
        let simulation = world()
        let lower = window(2, x: 100, y: 300, width: 500, height: 400)
        apply(scene([window(1, x: 200, y: 100, width: 200, height: 200), lower]), to: simulation)
        simulation.clear()
        seed(drift(1, in: simulation))
        let next = scene([window(1, x: 200, y: 320, width: 200, height: 200), lower])
        apply(next, to: simulation)
        let before = total(simulation)
        let received = area(drift(2, in: simulation))

        apply(next, to: simulation)
        apply(next, to: simulation)

        XCTAssertEqual(total(simulation), before, accuracy: 0.01)
        XCTAssertEqual(area(drift(2, in: simulation)), received, accuracy: 0.01)
    }


    func testFullReceivingCapPreservesOverflowWhenGranularStorageIsDisabled() {
        let simulation = world(granular: false)
        let lower = window(2, x: 100, y: 300, width: 500, height: 400)
        apply(scene([window(1, x: 200, y: 100, width: 200, height: 200), lower]), to: simulation)
        simulation.clear()
        seed(drift(1, in: simulation))
        let destination = drift(2, in: simulation)
        var exposed = destination.surface
        exposed.visibleSpans = [Span(0, exposed.width)]
        exposed.snowfallSpans = exposed.visibleSpans
        let filled = SnowDrift(surface: exposed, cellCount: destination.heights.count)
        filled.accumulate(dt: 100_000, intensity: 1)
        destination.heights = filled.heights
        // Saturate physical capacity, which is deliberately independent of the lower
        // atmospheric-filling envelope and its wind modifiers.
        for x in stride(from: Float(0), through: destination.surface.width, by: 40) {
            _ = destination.depositMass(at: x, mass: 100_000)
        }
        let before = total(simulation)

        apply(scene([window(1, x: 200, y: 320, width: 200, height: 200), lower]), to: simulation)

        XCTAssertGreaterThan(simulation.pendingTransferMass, 0)
        XCTAssertTrue(simulation.looseSnow.active.isEmpty)
        XCTAssertLessThan(area(drift(1, in: simulation)), 0.01)
        XCTAssertEqual(total(simulation), before, accuracy: before * 0.01)
    }
}
