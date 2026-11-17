import Foundation

/// Connected snow geometry for the shared desktop and Spotlight rendering passes.
extension SnowSimulation {
    public func rebuildMesh() {
        mesh.removeAll(keepingCapacity: true)
        elevatedMeshRanges.removeAll(keepingCapacity: true)
        for drift in drifts {
            let surface = drift.surface
            let start = mesh.count
            for span in surface.visibleSpans {
                let first = max(0, min(drift.heights.count - 2, Int(span.lower / drift.spacing)))
                let last = max(first, min(drift.heights.count - 2, Int(span.upper / drift.spacing)))
                for i in first...last {
                    let left = max(span.lower, Float(i) * drift.spacing)
                    let right = min(span.upper, Float(i + 1) * drift.spacing)
                    guard right > left else { continue }
                    let h0 = drift.height(at: left), h1 = drift.height(at: right)
                    guard max(h0, h1) > 0.025 else { continue }
                    // Bounds on mesh writes are independent of window count and supplied spans.
                    guard mesh.count + 12 <= budget.cells * 12 else { break }
                    let x0 = surface.x + left, x1 = surface.x + right
                    let y0 = surface.baseY(at: left), y1 = surface.baseY(at: right)
                    let bottom0 = SnowVertex(position: SIMD2(x0, y0 + 0.4), material: SIMD2(0, 0.88))
                    let bottom1 = SnowVertex(position: SIMD2(x1, y1 + 0.4), material: SIMD2(0, 0.88))
                    let top0 = SnowVertex(position: SIMD2(x0, y0 - h0), material: SIMD2(1, 1))
                    let top1 = SnowVertex(position: SIMD2(x1, y1 - h1), material: SIMD2(1, 1))
                    quad(bottom0, bottom1, top0, top1)
                    quad(top0, top1,
                         SnowVertex(position: top0.position - SIMD2(0, 0.8), material: SIMD2(1, 0)),
                         SnowVertex(position: top1.position - SIMD2(0, 0.8), material: SIMD2(1, 0)))
                }
            }
            if surface.isElevated, mesh.count > start {
                if let previous = elevatedMeshRanges.last, previous.upperBound == start {
                    elevatedMeshRanges[elevatedMeshRanges.count - 1] = previous.lowerBound..<mesh.count
                } else { elevatedMeshRanges.append(start..<mesh.count) }
            }
        }
        contour.append(field: looseSnow, to: &mesh, limit: budget.maximumSnowVertices)
        meshRevision &+= 1
        meshDirty = false
        interactionDirty = false
        geometryAge = 0
    }


    private func quad(_ a: SnowVertex, _ b: SnowVertex, _ c: SnowVertex, _ d: SnowVertex) {
        mesh.append(a)
        mesh.append(b)
        mesh.append(c)
        mesh.append(b)
        mesh.append(d)
        mesh.append(c)
    }
}

/// Water geometry, in the snow vertex layout: material.x is 0 at the bottom of a water body and 1
/// at its surface (the shader brightens the surface line), material.y is the alpha.
extension SnowSimulation {
    /// Upper bound of `waterMesh`: one quad per flood column plus one per puddle sample.
    public var maximumWaterVertices: Int { flood.heights.count * 6 + budget.cells * 6 }

    public func rebuildWaterMesh() {
        waterMesh.removeAll(keepingCapacity: true)
        let limit = maximumWaterVertices
        for drift in drifts where drift.puddle > 0.02 {
            let s = drift.surface
            for span in s.visibleSpans {
                let first = max(0, min(drift.heights.count - 2, Int(span.lower / drift.spacing)))
                let last = max(first, min(drift.heights.count - 2, Int(span.upper / drift.spacing)))
                for i in first...last {
                    let left = max(span.lower, Float(i) * drift.spacing)
                    let right = min(span.upper, Float(i + 1) * drift.spacing)
                    guard right > left, waterMesh.count + 6 <= limit else { continue }
                    // The water lies on whatever snow is still on the top.
                    let base0 = s.baseY(at: left) - drift.height(at: left)
                    let base1 = s.baseY(at: right) - drift.height(at: right)
                    waterQuad(SnowVertex(position: SIMD2(s.x + left, base0 + 0.3), material: SIMD2(0, 0.42)),
                              SnowVertex(position: SIMD2(s.x + right, base1 + 0.3), material: SIMD2(0, 0.42)),
                              SnowVertex(position: SIMD2(s.x + left, base0 - drift.puddle), material: SIMD2(1, 0.34)),
                              SnowVertex(position: SIMD2(s.x + right, base1 - drift.puddle), material: SIMD2(1, 0.34)))
                }
            }
        }
        if flood.level > 0.05 {
            let count = flood.heights.count
            for i in 0..<(count - 1) where waterMesh.count + 6 <= limit {
                let x0 = min(size.x, Float(i) * flood.spacing), x1 = min(size.x, Float(i + 1) * flood.spacing)
                guard x1 > x0 else { continue }
                let y0 = size.y - flood.level - flood.heights[i], y1 = size.y - flood.level - flood.heights[i + 1]
                waterQuad(SnowVertex(position: SIMD2(x0, size.y + 1), material: SIMD2(0, 0.46)),
                          SnowVertex(position: SIMD2(x1, size.y + 1), material: SIMD2(0, 0.46)),
                          SnowVertex(position: SIMD2(x0, y0), material: SIMD2(1, 0.34)),
                          SnowVertex(position: SIMD2(x1, y1), material: SIMD2(1, 0.34)))
            }
        }
        waterRevision &+= 1
    }

    private func waterQuad(_ a: SnowVertex, _ b: SnowVertex, _ c: SnowVertex, _ d: SnowVertex) {
        waterMesh.append(a)
        waterMesh.append(b)
        waterMesh.append(c)
        waterMesh.append(b)
        waterMesh.append(d)
        waterMesh.append(c)
    }
}
