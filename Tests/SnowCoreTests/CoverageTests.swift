import Foundation
import XCTest
@testable import SnowCore

/// How much of the usable desktop (below the menu bar, above the Dock reservation) ordinary
/// windows cover. A zoomed window that fills the screen without entering full screen covers
/// nearly all of it, so the snow is almost entirely hidden and rendering can slow down.
final class CoverageTests: XCTestCase {
    private let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private func app(_ rect: CGRect) -> DesktopWindowRecord {
        DesktopWindowRecord(id: UInt64(rect.minX * 7 + rect.minY + 1), bounds: rect, layer: 0, role: .application)
    }

    private func coverage(_ windows: [DesktopWindowRecord]) -> Float {
        DesktopSceneBuilder.coveredFraction(displayBounds: display, menuInset: 30, dockBottomInset: 82, windows: windows)
    }

    func testZoomedWindowCoversNearlyTheWholeDesktop() {
        let zoomed = app(CGRect(x: 0, y: 30, width: 1920, height: 968))
        XCTAssertGreaterThanOrEqual(coverage([zoomed]), 0.97)
    }

    func testHalfScreenWindowCoversAboutHalf() {
        let half = app(CGRect(x: 0, y: 30, width: 960, height: 968))
        XCTAssertEqual(coverage([half]), 0.5, accuracy: 0.03)
    }

    func testOverlappingWindowsAreNotCountedTwice() {
        let a = app(CGRect(x: 0, y: 30, width: 960, height: 968))
        let b = app(CGRect(x: 480, y: 30, width: 960, height: 968))
        XCTAssertEqual(coverage([a, b]), 0.75, accuracy: 0.03)
    }

    func testWidgetsDockAndNoWindowsCoverNothing() {
        XCTAssertEqual(coverage([]), 0)
        let widget = DesktopWindowRecord(id: 9, bounds: CGRect(x: 0, y: 30, width: 1920, height: 968),
                                         layer: -2_147_483_601, role: .widget)
        let dock = DesktopWindowRecord(id: 10, bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                       layer: 20, role: .dock)
        XCTAssertEqual(coverage([widget, dock]), 0)
    }

    func testMostlyCoveredDesktopRendersAtALowerRateWithFewerFlakes() {
        let normal = RenderPolicy(lowPower: false, thermalLevel: 0, reducedMotion: false)
        let covered = normal.forMostlyCoveredDesktop()
        XCTAssertEqual(covered.framesPerSecond, 20)
        XCTAssertEqual(covered.particleScale, 0.5)
        XCTAssertFalse(covered.suspended, "The Dock strip and edges stay alive")
    }

    func testMostlyCoveredNeverRaisesAnAlreadyLowerPolicy() {
        let hot = RenderPolicy(lowPower: false, thermalLevel: 2, reducedMotion: false)
        let covered = hot.forMostlyCoveredDesktop()
        XCTAssertEqual(covered.framesPerSecond, 15, "A hot Mac's 15 fps stays 15")
        XCTAssertEqual(covered.particleScale, hot.particleScale, "0.35 stays 0.35")
        let calm = RenderPolicy(lowPower: false, thermalLevel: 0, reducedMotion: true).forMostlyCoveredDesktop()
        XCTAssertEqual(calm.particleScale, 0)
    }
}
