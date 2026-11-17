import Foundation
import XCTest
@testable import SnowCore

/// Snow pushed toward an open edge (no neighbouring top) falls over it. It must never pile up
/// against the edge as if leaning on an invisible wall.
final class OpenEdgeTests: XCTestCase {
    private let top = Surface(id: 1, x: 300, y: 300, width: 300, cornerRadius: 22)
    private let body = SolidBody(id: 1, bounds: CGRect(x: 300, y: 300, width: 300, height: 200), cornerRadius: 22)

    func testPushedSnowDoesNotLeanAgainstAnOpenEdge() {
        let simulation = SnowSimulation(size: SIMD2(1000, 800), budget: SimulationBudget(flakes: 0), seed: 23)
        simulation.updateScene(surfaces: [top], bodies: [body])
        simulation.clear()
        let cap = simulation.drifts.first { $0.surface.id == 1 }!
        for i in cap.heights.indices { _ = cap.depositMass(at: Float(i) * cap.spacing, mass: 1_000) }
        // The glove shoves a heap of extra snow toward the left edge.
        cap.addOverload(at: 30, mass: 400)
        for _ in 0..<(5 * 30) { simulation.step(dt: 1 / 30, cursor: nil) }

        // Snow 40 pt in from the edge versus the outer 16 pt: the edge must not stand taller.
        let inner = cap.height(at: 40)
        let edgeBand = cap.heights.indices.filter { Float($0) * cap.spacing <= 16 }.map { cap.heights[$0] }
        XCTAssertLessThanOrEqual(edgeBand.max() ?? 0, inner + 0.5,
                                 "Snow rises toward the open edge, as if against an invisible wall")
        XCTAssertFalse(cap.isOverloaded, "The pushed heap should have spilled over the edge")
    }
}
