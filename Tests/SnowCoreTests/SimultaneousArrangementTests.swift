import Foundation
import XCTest
@testable import SnowCore

/// Window tiling and other programmatic arrangements move several windows within one
/// metadata snapshot. Their relative paths between snapshots are unknown, so one moving
/// window must not scrape or take over another moving window's cap.
final class SimultaneousArrangementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    private func window(_ id: UInt64, x: CGFloat, y: CGFloat,
                        width: CGFloat, height: CGFloat) -> DesktopWindowRecord {
        DesktopWindowRecord(id: id, bounds: CGRect(x: x, y: y, width: width, height: height),
                            layer: 0, role: .application)
    }

    private func apply(_ records: [DesktopWindowRecord], to simulation: SnowSimulation) {
        let scene = DesktopSceneBuilder.build(displayBounds: screen, menuInset: 24, windows: records)
        simulation.updateScene(surfaces: scene.surfaces, bodies: scene.bodies)
    }

    private func world() -> SnowSimulation {
        SnowSimulation(size: SIMD2(1000, 800), budget: SimulationBudget(flakes: 0, debris: 96), seed: 71)
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

    func testSimultaneouslyArrangedWindowKeepsItsOwnCap() {
        let simulation = world()
        let front = window(1, x: 600, y: 300, width: 300, height: 300)
        let back = window(2, x: 50, y: 100, width: 400, height: 400)
        apply([front, back], to: simulation)
        simulation.clear()
        seed(drift(1, in: simulation))
        let before = area(drift(1, in: simulation))
        let totalBefore = total(simulation)

        // One snapshot of a tiling animation: both windows jump, and the front window's
        // cap now lies inside the other window's new bounds.
        let movedFront = window(1, x: 300, y: 200, width: 300, height: 300)
        let movedBack = window(2, x: 250, y: 120, width: 500, height: 500)
        apply([movedFront, movedBack], to: simulation)

        XCTAssertEqual(area(drift(1, in: simulation)), before, accuracy: before * 0.02)
        XCTAssertLessThan(simulation.looseSnow.totalMass, before * 0.02)
        XCTAssertEqual(total(simulation), totalBefore, accuracy: totalBefore * 0.01)

        // The arrangement finishes with both windows apart again; the cap is still there.
        apply([front, back], to: simulation)
        XCTAssertEqual(area(drift(1, in: simulation)), before, accuracy: before * 0.02)
    }
}
