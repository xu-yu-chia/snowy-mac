import Foundation
import XCTest
@testable import SnowCore

/// A slit filled with snow up to the neighbouring cap's top joins that cap: the cap keeps full
/// depth to its edge instead of a rounded shoulder above a lower layer.
final class JoinedSlitTests: XCTestCase {
    private func world(slitFilled: Bool, slitY: Float = 138) -> SnowDrift {
        let floor = Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 800, width: 1200)
        let cap = Surface(id: 2, x: 385, y: 122, width: 500)
        let slitFloor = Surface(id: 3, x: 327, y: slitY, width: 700, visibleSpans: [Span(33, 700)])
        let simulation = SnowSimulation(size: SIMD2(1200, 800), budget: SimulationBudget(flakes: 0, debris: 96), seed: 4)
        simulation.updateScene(surfaces: [floor, cap, slitFloor],
                               bodies: [SolidBody(id: 1, bounds: CGRect(x: 196, y: 54, width: 164, height: 156)),
                                        SolidBody(id: 2, bounds: CGRect(x: 385, y: 122, width: 500, height: 500)),
                                        SolidBody(id: 3, bounds: CGRect(x: 327, y: CGFloat(slitY), width: 700, height: 400))])
        simulation.clear()
        let bottom = simulation.drifts.first { $0.surface.id == 3 }!
        let top = simulation.drifts.first { $0.surface.id == 2 }!
        if slitFilled { for i in bottom.heights.indices { bottom.heights[i] = 17 } }
        for _ in 0..<(60 * 30) {
            top.accumulate(dt: 1 / 30, intensity: 1)
            simulation.step(dt: 1 / 30, cursor: nil)
            if slitFilled { for i in bottom.heights.indices { bottom.heights[i] = 17 } }
        }
        return top
    }

    func testCapJoinsAFilledSlit() {
        let top = world(slitFilled: true)
        let middle = top.height(at: 250)
        XCTAssertGreaterThan(middle, 5)
        XCTAssertGreaterThan(top.height(at: 2), middle * 0.6, "Full depth to the edge beside the filled slit")
    }

    func testCapBesideADeepSlitKeepsItsShoulder() {
        // Snow shed into a deep slit cannot fill it up to the cap's top.
        let top = world(slitFilled: false, slitY: 300)
        XCTAssertLessThan(top.height(at: 2), top.height(at: 250) * 0.3, "Rounded shoulder above an open slit")
    }
}
