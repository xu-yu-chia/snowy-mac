import Foundation

/// A JSON-ready dump of the scene and settled snow, so a state seen on a real desktop can be
/// rebuilt exactly in a test.
extension SnowSimulation {
    public func debugSnapshot() -> [String: Any] {
        func spans(_ list: [Span]) -> [[Float]] { list.map { [$0.lower, $0.upper] } }
        let surfaces: [[String: Any]] = drifts.map { drift in
            let s = drift.surface
            return ["id": String(s.id), "x": s.x, "y": s.y, "width": s.width, "visibleSpans": spans(s.visibleSpans),
                    "snowfallSpans": spans(s.snowfallSpans), "isDock": s.isDock, "cornerRadius": s.cornerRadius,
                    "releasesSnowWhenRemoved": s.releasesSnowWhenRemoved, "isElevated": s.isElevated,
                    "slope": s.slope, "holdsWater": s.holdsWater, "spacing": drift.spacing,
                    "blockedEnds": [drift.blockedEnds.start, drift.blockedEnds.end],
                    "heights": drift.heights, "puddle": drift.puddle]
        }
        let bodies: [[String: Any]] = self.bodies.map { body in
            ["id": String(body.id), "x": Double(body.bounds.minX), "y": Double(body.bounds.minY),
             "width": Double(body.bounds.width), "height": Double(body.bounds.height),
             "cornerRadius": body.cornerRadius, "isElevated": body.isElevated,
             "topSlope": body.topSlope, "bottomSlope": body.bottomSlope]
        }
        let loose: [[Float]] = looseSnow.active.filter { looseSnow.mass[$0] > 0.01 }.map {
            let p = looseSnow.position(of: $0)
            return [p.x, p.y, looseSnow.mass[$0]]
        }
        return ["size": [size.x, size.y], "wind": [wind.vector.x, wind.vector.y],
                "airflow": [air.vector.x, air.vector.y], "snowfall": snowfall.rawValue,
                "weather": weather.rawValue, "cellSize": looseSnow.cellSize, "flood": flood.level,
                "surfaces": surfaces, "bodies": bodies, "loose": loose]
    }
}
