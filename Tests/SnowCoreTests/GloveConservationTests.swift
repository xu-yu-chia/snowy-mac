import Foundation
import XCTest
@testable import SnowCore

/// Snow brushed with the glove goes somewhere (other tops, loose grains, the floor); it never
/// vanishes. From a real desktop: Spotify's deep rounded corners dip behind the terminal in front.
final class GloveConservationTests: XCTestCase {
    private func world() -> SnowSimulation {
        let ground = Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 1080, width: 1920)
        let windows = [(Surface(id: 41, x: 196, y: 54, width: 164, cornerRadius: 22),
                        SolidBody(id: 41, bounds: CGRect(x: 196, y: 54, width: 164, height: 156), cornerRadius: 22)),
                       (Surface(id: 398, x: 325, y: 144, width: 1234, visibleSpans: [Span(35, 86), Span(1140, 1234)], cornerRadius: 26,
                                snowfallSpans: [Span(35, 60), Span(1166, 1234)]),
                        SolidBody(id: 398, bounds: CGRect(x: 325, y: 144, width: 1234, height: 535), cornerRadius: 26)),
                       (Surface(id: 11627, x: 385, y: 122, width: 1106, cornerRadius: 26),
                        SolidBody(id: 11627, bounds: CGRect(x: 385, y: 122, width: 1106, height: 721), cornerRadius: 26))]
        let simulation = SnowSimulation(size: SIMD2(1920, 1080), budget: SimulationBudget(flakes: 0, debris: 192), seed: 9)
        simulation.updateScene(surfaces: [ground] + windows.map(\.0), bodies: windows.map(\.1))
        simulation.snowfall = .light
        for drift in simulation.drifts where drift.surface.id != DesktopSceneBuilder.groundID {
            for i in drift.heights.indices { _ = drift.depositSnowfall(at: Float(i) * drift.spacing, mass: 1_000) }
        }
        return simulation
    }

    private func total(_ s: SnowSimulation) -> Float {
        s.drifts.reduce(0) { $0 + $1.heights.reduce(0, +) * $1.spacing } + s.looseSnow.totalMass + s.pendingTransferMass
            + s.clumps.reduce(0) { $0 + $1.mass }
    }

    func testBrushedSnowOnARoundedWindowIsNeverDeleted() {
        let glove = world(), calm = world()
        var t: Float = 0
        for _ in 0..<(3 * 60) {
            t += 1 / 60
            glove.step(dt: 1 / 60, cursor: SIMD2(700 + 300 * sin(t * 2), 112))
            calm.step(dt: 1 / 60, cursor: nil)
        }
        for _ in 0..<(10 * 60) {
            glove.step(dt: 1 / 60, cursor: nil)
            calm.step(dt: 1 / 60, cursor: nil)
        }
        XCTAssertEqual(total(glove), total(calm), accuracy: 150, "Brushed snow must not vanish")
    }
}
