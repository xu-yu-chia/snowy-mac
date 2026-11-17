import Foundation
import XCTest
@testable import SnowCore

/// A slit between two windows whose bottom is a third window's top (exposed only inside the
/// slit) is a well: snow fills it and banks over its lower rim, but never grows into a pillar.
final class SlitWellTests: XCTestCase {
    func testSnowInAWellDoesNotGrowIntoAPillar() {
        let floor = Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 1080, width: 1920)
        let widget = SolidBody(id: 1, bounds: CGRect(x: 198, y: 38, width: 160, height: 170))
        let window = SolidBody(id: 2, bounds: CGRect(x: 380, y: 88, width: 1106, height: 721))
        let front = SolidBody(id: 3, bounds: CGRect(x: 327, y: 124, width: 1178, height: 610))
        let surfaces = [floor,
                        Surface(id: 1, x: 198, y: 38, width: 160, releasesSnowWhenRemoved: true),
                        Surface(id: 2, x: 380, y: 88, width: 1106),
                        Surface(id: 3, x: 327, y: 124, width: 1178, visibleSpans: [Span(31, 53)])]
        let simulation = SnowSimulation(size: SIMD2(1920, 1080), seed: 3)
        simulation.updateScene(surfaces: surfaces, bodies: [widget, window, front])
        simulation.snowfall = .flurry
        for _ in 0..<(90 * 30) { simulation.step(dt: 1 / 30, cursor: nil) }
        let bottom = simulation.drifts.first { $0.surface.id == 3 }!
        XCTAssertLessThanOrEqual(bottom.heights.max() ?? 0, 20, "The well's floor holds at most a full cap")
        let field = simulation.looseSnow
        let highest = field.active.filter { field.mass[$0] > 0.01 }.map { field.position(of: $0) }
            .filter { $0.x > 355 && $0.x < 385 }.map(\.y).min() ?? 1080
        XCTAssertGreaterThan(highest, 55, "Loose snow banks over the 88 pt rim, not up to the screen top")
    }
}
