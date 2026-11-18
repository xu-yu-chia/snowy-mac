import Foundation
import XCTest
@testable import SnowCore

/// Once a basin is filled up to its outlet it is a raised flat top: snow builds on it like on any
/// window top (no fixed shape), can be dug with the glove, refills a dug hole gradually, and
/// only overflows at the outlet. Narrow slits between equal tops let snow fall through instead
/// of piling up at the facing ends.
final class RaisedFloorTests: XCTestCase {
    private let ground = Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 800, width: 1600)

    private func make(_ windows: [(Surface, SolidBody)], flakes: Int = 0) -> SnowSimulation {
        let s = SnowSimulation(size: SIMD2(1600, 800), budget: SimulationBudget(flakes: flakes, debris: 192), seed: 4)
        s.updateScene(surfaces: [ground] + windows.map(\.0), bodies: windows.map(\.1))
        s.clear()
        s.snowfall = .light
        s.step(dt: 1 / 30, cursor: nil)
        return s
    }

    private func window(_ id: UInt64, x: Float, y: Float, width: Float, height: Float = 400, radius: Float = 0) -> (Surface, SolidBody) {
        (Surface(id: id, x: x, y: y, width: width, cornerRadius: radius),
         SolidBody(id: id, bounds: CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height)), cornerRadius: radius))
    }

    private func drift(_ s: SnowSimulation, _ id: UInt64) -> SnowDrift { s.drifts.first { $0.surface.id == id }! }
    private func index(_ d: SnowDrift, x: Float) -> Int { Int(((x - d.surface.x) / d.spacing).rounded()) }
    private func top(_ d: SnowDrift, x: Float) -> Float { let i = index(d, x: x); return d.surface.baseY(at: Float(i) * d.spacing) - d.heights[i] }

    /// A 100 pt hollow: left wall top 100, floor top 200, right wall (the outlet) top 120.
    private func hollow() -> SnowSimulation {
        make([window(1, x: 100, y: 100, width: 50), window(2, x: 150, y: 200, width: 100), window(3, x: 250, y: 120, width: 300)])
    }

    private func fill(_ s: SnowSimulation) {
        let floor = drift(s, 2)
        for i in floor.heights.indices where floor.basin(at: i) != nil { floor.heights[i] = 80 }
    }

    func testAFullBasinBuildsAnOrdinaryCapThatIsNotAFixedShape() {
        let s = hollow()
        fill(s)
        let floor = drift(s, 2)
        var peak: Float = 0
        for _ in 0..<(180 * 30) {
            s.step(dt: 1 / 30, cursor: nil)
            for x in stride(from: Float(156), through: 244, by: 4) { peak = max(peak, 120 - top(floor, x: x)) }
        }
        let caps = stride(from: Float(156), through: 244, by: 4).map { 120 - top(floor, x: $0) }
        // The outlet window beside it is an ordinary top that got the same snowfall.
        let ordinary = drift(s, 3)
        let plain = stride(from: Float(300), through: 388, by: 4).map { 120 - top(ordinary, x: $0) }
        XCTAssertGreaterThan(caps.reduce(0, +) / Float(caps.count), 6, "Snow builds on the raised floor")
        XCTAssertLessThanOrEqual(peak, 18 + 4, "Never above an ordinary cap")
        XCTAssertGreaterThan((caps.max() ?? 0) - (caps.min() ?? 0), ((plain.max() ?? 0) - (plain.min() ?? 0)) * 0.5,
                             "It undulates like an ordinary top, not a fixed plateau")
    }

    func testADugHoleRefillsGraduallyAndFarSnowStays() {
        let s = hollow()
        fill(s)
        let floor = drift(s, 2)
        for _ in 0..<(5 * 30) { s.step(dt: 1 / 30, cursor: nil) }
        let far = top(floor, x: 160)
        let neighbours = top(floor, x: 230)
        for x in stride(from: Float(196), through: 204, by: 4) { floor.heights[index(floor, x: x)] = 50 }  // dug 30 pt below the rim
        let dug = top(floor, x: 200) - neighbours
        for _ in 0..<15 { s.step(dt: 1 / 30, cursor: nil) }
        XCTAssertGreaterThan(top(floor, x: 200) - top(floor, x: 230), dug * 0.3, "Half a second later the hole is still clearly there")
        for _ in 0..<(5 * 30) { s.step(dt: 1 / 30, cursor: nil) }
        XCTAssertLessThan(abs(top(floor, x: 200) - top(floor, x: 230)), 3, "Within a few seconds it has flowed level")
        XCTAssertEqual(top(floor, x: 160), far, accuracy: 4, "Snow far from the hole is not flattened")
    }

    func testOverflowFromFarAwayDoesNotBuildARidge() {
        let s = hollow()
        fill(s)
        let floor = drift(s, 2), outlet = drift(s, 3)
        let before = outlet.heights.reduce(0, +)
        var peak: Float = 0
        for _ in 0..<(30 * 30) {
            floor.addOverload(at: 160 - 150, mass: 6)
            s.step(dt: 1 / 30, cursor: nil)
            for x in stride(from: Float(156), through: 244, by: 4) { peak = max(peak, 120 - top(floor, x: x)) }
        }
        XCTAssertLessThanOrEqual(peak, 18 + 4, "No ridge on the way to the outlet")
        XCTAssertGreaterThan(outlet.heights.reduce(0, +) - before, 20, "The overflow reached the outlet wall's top")
    }

    func testTheGloveReachesARaisedSurface() {
        let s = make([window(1, x: 100, y: 100, width: 50), window(2, x: 150, y: 200, width: 100), window(3, x: 250, y: 100, width: 300)])
        let floor = drift(s, 2)
        for i in floor.heights.indices where floor.basin(at: i) != nil { floor.heights[i] = 110 }  // surface at y 90
        s.step(dt: 1 / 60, cursor: SIMD2(160, 86))
        let before = floor.heights[index(floor, x: 200)]
        for k in 1...30 { s.step(dt: 1 / 60, cursor: SIMD2(160 + Float(k) * 3, 86)) }
        XCTAssertLessThan(floor.heights[index(floor, x: 200)], before - 2, "The glove pushes snow off the raised surface")
    }

    func testASlitWhoseWallsStopAboveItsFloorLeaksSideways() {
        // From the real desktop: the Calendar and Reminders widgets (bottoms at y 210) side by side
        // above a large widget whose top is at y 234. The slit between them opens sideways under
        // both: no container, the snow spreads out along the large widget's top.
        let s = make([window(34, x: 16, y: 54, width: 164, height: 156, radius: 22),
                      window(41, x: 196, y: 54, width: 164, height: 156, radius: 22),
                      window(37, x: 16, y: 234, width: 344, height: 336, radius: 22)])
        XCTAssertTrue(s.basins.isEmpty, "No basin: \(s.basins.map { ($0.level, $0.members.count) })")
    }

    func testSnowFallsThroughANarrowSlitBetweenEqualTops() {
        let s = make([window(1, x: 16, y: 594, width: 164, height: 156, radius: 22),
                      window(2, x: 196, y: 594, width: 164, height: 156, radius: 22)], flakes: 300)
        s.snowfall = .flurry
        let left = drift(s, 1), right = drift(s, 2)
        var peak: Float = 0
        for _ in 0..<(180 * 30) {
            s.step(dt: 1 / 30, cursor: nil)
            for d in [left, right] {
                for i in d.heights.indices { peak = max(peak, d.surface.y - (d.surface.baseY(at: Float(i) * d.spacing) - d.heights[i])) }
            }
        }
        XCTAssertLessThanOrEqual(peak, 18 + 4, "The facing ends never pile up above an ordinary cap")
        let floor = drift(s, DesktopSceneBuilder.groundID)
        let under = floor.heights.indices.filter { let x = Float($0) * floor.spacing; return x > 170 && x < 206 }
        XCTAssertGreaterThan(under.map { floor.heights[$0] }.max() ?? 0, 0.5, "Snow falls through the slit to the floor")
    }
}
