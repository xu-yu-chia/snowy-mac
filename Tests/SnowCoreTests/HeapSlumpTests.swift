import Foundation
import XCTest
@testable import SnowCore

/// A heap pushed together with the glove slumps like snow: its sides settle to about 35° and it
/// spreads out, instead of standing as a 45° pyramid.
final class HeapSlumpTests: XCTestCase {
    func testAPushedHeapSlumpsToARestingSlope() {
        let simulation = SnowSimulation(size: SIMD2(1600, 800), budget: SimulationBudget(flakes: 0, debris: 192), seed: 3)
        let top = Surface(id: 1, x: 300, y: 300, width: 600)
        simulation.updateScene(surfaces: [Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 800, width: 1600), top],
                               bodies: [SolidBody(id: 1, bounds: CGRect(x: 300, y: 300, width: 600, height: 300))])
        simulation.clear()
        let cap = simulation.drifts.first { $0.surface.id == 1 }!
        for i in cap.heights.indices { _ = cap.depositMass(at: Float(i) * cap.spacing, mass: 1_000) }
        cap.addOverload(at: 300, mass: 4_000)
        let peakBefore = cap.heights.max() ?? 0
        for _ in 0..<(10 * 30) { simulation.step(dt: 1 / 30, cursor: nil) }
        var steepest: Float = 0
        for i in 0..<(cap.heights.count - 1) where Float(i) * cap.spacing > 40 && Float(i) * cap.spacing < 560 {
            steepest = max(steepest, abs(cap.heights[i + 1] - cap.heights[i]) / cap.spacing)
        }
        XCTAssertLessThanOrEqual(steepest, 0.75, "The heap's sides rest at about 35°, not 45°")
        XCTAssertLessThan(cap.heights.max() ?? 0, peakBefore * 0.5, "The heap slumps and spreads out")
    }

    func testAHeapBesideAContainerSlumpsOntoItsTop() {
        // The container between the Reminders widget and Spotify, filled; a heap pushed onto
        // Spotify right beside it must slump onto the container's top too.
        func world() -> SnowSimulation {
            let s = SnowSimulation(size: SIMD2(1600, 800), budget: SimulationBudget(flakes: 0, debris: 192), seed: 3)
            let windows = [(Surface(id: 1, x: 196, y: 54, width: 164, cornerRadius: 22),
                            SolidBody(id: 1, bounds: CGRect(x: 196, y: 54, width: 164, height: 156), cornerRadius: 22)),
                           (Surface(id: 2, x: 385, y: 122, width: 600, cornerRadius: 26),
                            SolidBody(id: 2, bounds: CGRect(x: 385, y: 122, width: 600, height: 500), cornerRadius: 26)),
                           (Surface(id: 3, x: 327, y: 138, width: 700, visibleSpans: [Span(33, 700)], cornerRadius: 26,
                                    snowfallSpans: [Span(33, 58)]),
                            SolidBody(id: 3, bounds: CGRect(x: 327, y: 138, width: 700, height: 500), cornerRadius: 26))]
            s.updateScene(surfaces: [Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 800, width: 1600)] + windows.map(\.0),
                          bodies: windows.map(\.1))
            s.clear()
            s.step(dt: 1 / 30, cursor: nil)
            for basin in s.basins { for m in basin.members { m.drift.heights[m.index] = m.drift.capacity(at: m.index) } }
            return s
        }
        let heaped = world(), calm = world()
        let spotify = heaped.drifts.first { $0.surface.id == 2 }!
        spotify.addOverload(at: 440 - 385, mass: 4_000)
        for _ in 0..<(10 * 30) { heaped.step(dt: 1 / 30, cursor: nil); calm.step(dt: 1 / 30, cursor: nil) }
        func basinSnow(_ s: SnowSimulation) -> Float {
            s.basins.flatMap(\.members).reduce(0) { $0 + $1.drift.heights[$1.index] * $1.drift.spacing } + s.basins.reduce(0) { $0 + $1.pending }
        }
        // Snow that slumped into the full container also leaves by its outlet, so look at the
        // container's surface: it rises toward the heap instead of the heap standing as a cliff.
        let edge = heaped.basins.flatMap(\.members).max { $0.x < $1.x }!
        let edgeTop = edge.drift.surface.baseY(at: Float(edge.index) * edge.drift.spacing) - edge.drift.heights[edge.index]
        let calmEdge = calm.basins.flatMap(\.members).max { $0.x < $1.x }!
        let calmTop = calmEdge.drift.surface.baseY(at: Float(calmEdge.index) * calmEdge.drift.spacing) - calmEdge.drift.heights[calmEdge.index]
        XCTAssertLessThan(edgeTop, calmTop - 3, "The heap slumped onto the container's top")
        XCTAssertGreaterThanOrEqual(basinSnow(heaped), basinSnow(calm) - 1)
        // The visible snow surface from the container across onto the heap: no cliff.
        func surface(_ x: Float) -> Float {
            heaped.drifts.compactMap { d -> Float? in
                let local = x - d.surface.x
                guard local >= 0, local <= d.surface.width, d.surface.isExposed(at: local), d.surface.id != DesktopSceneBuilder.groundID else { return nil }
                return d.surface.baseY(at: local) - d.height(at: local)
            }.min() ?? 800
        }
        var steepest: Float = 0
        var at: Float = 0
        for x in stride(from: Float(364), through: 540, by: 4) {
            let slope = abs(surface(x + 4) - surface(x)) / 4
            if slope > steepest { steepest = slope; at = x }
        }
        XCTAssertLessThanOrEqual(steepest, 0.9, "No cliff where the heap meets the container")
    }
}
