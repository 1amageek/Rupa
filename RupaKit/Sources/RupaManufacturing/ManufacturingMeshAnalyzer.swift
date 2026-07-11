import Foundation
import RupaCore
import SwiftCAD

public struct ManufacturingMeshAnalyzer: Sendable {
    public init() {}

    public func analyze(
        evaluatedDocument: EvaluatedDocument,
        overhangLimitDegrees: Double
    ) throws -> ManufacturingMeshAnalysisResult {
        let meshArtifact = try meshArtifactReference(
            evaluatedDocument: evaluatedDocument
        )
        let threshold = -sin(overhangLimitDegrees * .pi / 180.0)
        var bodyAnalyses: [ManufacturingMeshAnalysisResult.BodyAnalysis] = []
        var totalSurfaceArea = 0.0
        var totalOverhangArea = 0.0
        var totalSupportContactArea = 0.0
        var bodyGeometries: [BodyGeometry] = []

        for (bodyID, mesh) in evaluatedDocument.meshes.sorted(by: { $0.key.description < $1.key.description }) {
            let bodyKind = evaluatedDocument.brep.bodies[bodyID]?.kind.rawValue
            let bodyOutput = try analyzeBody(
                bodyID: bodyID,
                bodyKind: bodyKind,
                mesh: mesh,
                meshArtifact: meshArtifact,
                overhangThreshold: threshold
            )
            let bodyAnalysis = bodyOutput.analysis
            totalSurfaceArea += bodyAnalysis.surfaceAreaSquareMeters
            totalOverhangArea += bodyAnalysis.overhangAreaSquareMeters
            totalSupportContactArea += bodyAnalysis.supportContactAreaSquareMeters
            bodyAnalyses.append(bodyAnalysis)
            bodyGeometries.append(bodyOutput.geometry)
        }

        let clearance = try minimumClearance(
            between: bodyGeometries,
            meshArtifact: meshArtifact
        )
        return ManufacturingMeshAnalysisResult(
            meshArtifact: meshArtifact,
            bodyAnalyses: bodyAnalyses,
            totalSurfaceAreaSquareMeters: totalSurfaceArea,
            totalOverhangAreaSquareMeters: totalOverhangArea,
            totalSupportContactAreaSquareMeters: totalSupportContactArea,
            minimumWallThicknessMeters: bodyAnalyses.compactMap(\.minimumWallThicknessMeters).min(),
            minimumBodyClearanceMeters: clearance?.distance,
            minimumBodyClearanceRegion: clearance?.region
        )
    }

    private func meshArtifactReference(
        evaluatedDocument: EvaluatedDocument
    ) throws -> MeshArtifactReference {
        let caches = evaluatedDocument.caches.brep == nil
            ? try DocumentCacheMaterializer().caches(for: evaluatedDocument)
            : evaluatedDocument.caches
        let bodyIDs = evaluatedDocument.meshes.keys.sorted {
            $0.description < $1.description
        }
        guard let firstBodyID = bodyIDs.first,
              let firstCache = caches.meshes[firstBodyID] else {
            throw ReferenceValidationError(
                code: .invalidIdentity,
                message: "Manufacturing analysis requires evaluated mesh cache provenance."
            )
        }

        for bodyID in bodyIDs {
            guard let cache = caches.meshes[bodyID] else {
                throw ReferenceValidationError(
                    code: .invalidIdentity,
                    message: "Manufacturing analysis is missing mesh artifact provenance for body \(bodyID.description)."
                )
            }
            guard cache.sourceFingerprint == firstCache.sourceFingerprint,
                  cache.kernelVersion == firstCache.kernelVersion,
                  cache.tolerance == firstCache.tolerance,
                  cache.tessellationOptions == firstCache.tessellationOptions else {
                throw ReferenceValidationError(
                    code: .invalidIdentity,
                    message: "Manufacturing analysis requires one consistent mesh artifact configuration."
                )
            }
        }

        let sourceDependency = try SourceDependencyIdentity(
            subject: .cadDocument(evaluatedDocument.document.id),
            contentFingerprint: .init(
                algorithm: firstCache.sourceFingerprint.algorithm,
                value: firstCache.sourceFingerprint.value
            )
        )
        let sourceDependencies = try SourceDependencySetIdentity(
            dependencies: [sourceDependency]
        )
        let configuration = try MeshArtifactConfiguration(
            kernelVersion: firstCache.kernelVersion,
            modelingTolerance: firstCache.tolerance,
            tessellationOptions: firstCache.tessellationOptions
        )
        let reference = try MeshArtifactReference(
            documentID: evaluatedDocument.document.id,
            sourceDependencies: sourceDependencies,
            producer: ArtifactProducerReference(
                id: "swift-cad.mesh-evaluator",
                version: "\(firstCache.kernelVersion.major).\(firstCache.kernelVersion.minor).\(firstCache.kernelVersion.patch)"
            ),
            configuration: configuration,
            contentFingerprint: MeshContentFingerprintService().fingerprint(
                for: evaluatedDocument.meshes
            )
        )
        try reference.validate()
        return reference
    }

    private func region(
        id: String,
        meshArtifact: MeshArtifactReference,
        selections: [ValidationMeshTriangleSelection]
    ) throws -> ValidationRegionReference? {
        guard !selections.isEmpty else {
            return nil
        }
        let reference = ValidationRegionReference(
            id: id,
            documentID: meshArtifact.documentID,
            target: .meshTriangles(
                artifact: meshArtifact,
                selections: selections
            )
        )
        try reference.validate()
        return reference
    }

    private func analyzeBody(
        bodyID: BodyID,
        bodyKind: String?,
        mesh: Mesh,
        meshArtifact: MeshArtifactReference,
        overhangThreshold: Double
    ) throws -> BodyAnalysisOutput {
        let validationErrorMessage = meshValidationErrorMessage(mesh)
        let minimumY = mesh.positions.map(\.y).min() ?? 0.0
        let meshSpan = finiteMeshSpan(mesh)
        let topologyTolerance = max(meshSpan * 1.0e-8, 1.0e-9)
        let buildContactTolerance = topologyTolerance
        var edgeUseCounts: [QuantizedMeshEdge: Int] = [:]
        var triangles: [MeshTriangle] = []
        var bounds = MeshBounds()
        var triangleCount = 0
        var surfaceArea = 0.0
        var overhangArea = 0.0
        var overhangTriangleCount = 0
        var supportContactArea = 0.0
        var degenerateTriangleCount = 0
        var invalidIndexCount = 0
        var minimumEdgeLength: Double?
        var overhangRanges = ValidationRangeAccumulator()

        var index = 0
        while index + 2 < mesh.indices.count {
            let sourceTriangleIndex = index / 3
            let firstIndex = mesh.indices[index]
            let secondIndex = mesh.indices[index + 1]
            let thirdIndex = mesh.indices[index + 2]
            index += 3

            guard let first = point(at: firstIndex, in: mesh),
                  let second = point(at: secondIndex, in: mesh),
                  let third = point(at: thirdIndex, in: mesh) else {
                invalidIndexCount += 1
                continue
            }

            updateMinimumEdgeLength(
                first,
                second,
                third,
                minimumEdgeLength: &minimumEdgeLength
            )

            let areaVector = vector(from: first, to: second).cross(vector(from: first, to: third))
            let areaVectorLength = areaVector.length
            guard areaVectorLength.isFinite,
                  areaVectorLength > 0.0 else {
                degenerateTriangleCount += 1
                continue
            }

            let area = areaVectorLength * 0.5
            let normal = scaled(areaVector, by: 1.0 / areaVectorLength)
            let triangle = MeshTriangle(
                sourceTriangleIndex: sourceTriangleIndex,
                first: first,
                second: second,
                third: third,
                normal: normal,
                area: area
            )
            triangles.append(triangle)
            bounds.include(first)
            bounds.include(second)
            bounds.include(third)
            recordEdge(first, second, tolerance: topologyTolerance, in: &edgeUseCounts)
            recordEdge(second, third, tolerance: topologyTolerance, in: &edgeUseCounts)
            recordEdge(third, first, tolerance: topologyTolerance, in: &edgeUseCounts)

            let centroidY = (first.y + second.y + third.y) / 3.0
            let touchesBuildPlate = centroidY <= minimumY + buildContactTolerance

            triangleCount += 1
            surfaceArea += area
            if touchesBuildPlate, normal.dot(.unitY) < -0.5 {
                supportContactArea += area
            } else if normal.dot(.unitY) < overhangThreshold {
                overhangArea += area
                overhangTriangleCount += 1
                overhangRanges.append(sourceTriangleIndex)
            }
        }

        let boundaryEdgeCount = edgeUseCounts.values.filter { $0 == 1 }.count
        let nonManifoldEdgeCount = edgeUseCounts.values.filter { $0 > 2 }.count
        let minimumWallThickness = bodyKind == "solid"
            ? minimumWallThickness(for: triangles, tolerance: topologyTolerance)
            : nil
        let overhangRegion = try region(
            id: "manufacturing.overhang:\(bodyID.description)",
            meshArtifact: meshArtifact,
            selections: overhangRanges.ranges.isEmpty
                ? []
                : [
                    ValidationMeshTriangleSelection(
                        bodyID: bodyID,
                        triangleRanges: overhangRanges.ranges
                    ),
                ]
        )
        let wallThicknessRegion = try minimumWallThickness.flatMap { measurement in
            try region(
                id: "manufacturing.wallThickness:\(bodyID.description)",
                meshArtifact: meshArtifact,
                selections: [
                    ValidationMeshTriangleSelection(
                        bodyID: bodyID,
                        triangleRanges: ValidationRangeAccumulator.ranges(
                            for: [
                                measurement.sourceTriangleIndex,
                                measurement.hitTriangleIndex,
                            ]
                        )
                    ),
                ]
            )
        }

        return BodyAnalysisOutput(
            analysis: ManufacturingMeshAnalysisResult.BodyAnalysis(
                bodyID: bodyID,
                bodyKind: bodyKind,
                triangleCount: triangleCount,
                surfaceAreaSquareMeters: surfaceArea,
                overhangAreaSquareMeters: overhangArea,
                overhangTriangleCount: overhangTriangleCount,
                supportContactAreaSquareMeters: supportContactArea,
                minimumWallThicknessMeters: minimumWallThickness?.distance,
                overhangRegion: overhangRegion,
                minimumWallThicknessRegion: wallThicknessRegion,
                boundaryEdgeCount: boundaryEdgeCount,
                nonManifoldEdgeCount: nonManifoldEdgeCount,
                degenerateTriangleCount: degenerateTriangleCount,
                invalidIndexCount: invalidIndexCount,
                minimumEdgeLengthMeters: minimumEdgeLength,
                validationErrorMessage: validationErrorMessage
            ),
            geometry: BodyGeometry(
                bodyID: bodyID,
                triangles: triangles,
                bounds: bounds.finalized
            )
        )
    }

    private func meshValidationErrorMessage(_ mesh: Mesh) -> String? {
        do {
            try mesh.validate()
            return nil
        } catch {
            return String(describing: error)
        }
    }

    private func point(at index: UInt32, in mesh: Mesh) -> Point3D? {
        let positionIndex = Int(index)
        guard mesh.positions.indices.contains(positionIndex) else {
            return nil
        }
        return mesh.positions[positionIndex]
    }

    private func recordEdge(
        _ first: Point3D,
        _ second: Point3D,
        tolerance: Double,
        in counts: inout [QuantizedMeshEdge: Int]
    ) {
        let edge = QuantizedMeshEdge(first, second, tolerance: tolerance)
        counts[edge, default: 0] += 1
    }

    private func updateMinimumEdgeLength(
        _ first: Point3D,
        _ second: Point3D,
        _ third: Point3D,
        minimumEdgeLength: inout Double?
    ) {
        for length in [
            vector(from: first, to: second).length,
            vector(from: second, to: third).length,
            vector(from: third, to: first).length,
        ] where length.isFinite && length > 0.0 {
            if let current = minimumEdgeLength {
                minimumEdgeLength = min(current, length)
            } else {
                minimumEdgeLength = length
            }
        }
    }

    private func minimumWallThickness(
        for triangles: [MeshTriangle],
        tolerance: Double
    ) -> WallThicknessMeasurement? {
        var minimum: WallThicknessMeasurement?
        for (index, triangle) in triangles.enumerated() {
            for direction in [triangle.normal, scaled(triangle.normal, by: -1.0)] {
                guard let hit = nearestRayTriangleHit(
                    origin: triangle.centroid,
                    direction: direction,
                    excluding: index,
                    triangles: triangles,
                    tolerance: tolerance
                ) else {
                    continue
                }
                let measurement = WallThicknessMeasurement(
                    distance: hit.distance,
                    sourceTriangleIndex: triangle.sourceTriangleIndex,
                    hitTriangleIndex: hit.sourceTriangleIndex
                )
                if let current = minimum {
                    if measurement.distance < current.distance {
                        minimum = measurement
                    }
                } else {
                    minimum = measurement
                }
            }
        }
        return minimum
    }

    private func nearestRayTriangleHit(
        origin: Point3D,
        direction: Vector3D,
        excluding excludedIndex: Int,
        triangles: [MeshTriangle],
        tolerance: Double
    ) -> RayTriangleHit? {
        var nearest: RayTriangleHit?
        for (index, triangle) in triangles.enumerated() where index != excludedIndex {
            guard let distance = rayTriangleIntersectionDistance(
                origin: origin,
                direction: direction,
                triangle: triangle,
                tolerance: tolerance
            ) else {
                continue
            }
            if let current = nearest {
                if distance < current.distance {
                    nearest = RayTriangleHit(
                        distance: distance,
                        sourceTriangleIndex: triangle.sourceTriangleIndex
                    )
                }
            } else {
                nearest = RayTriangleHit(
                    distance: distance,
                    sourceTriangleIndex: triangle.sourceTriangleIndex
                )
            }
        }
        return nearest
    }

    private func rayTriangleIntersectionDistance(
        origin: Point3D,
        direction: Vector3D,
        triangle: MeshTriangle,
        tolerance: Double
    ) -> Double? {
        let edge1 = vector(from: triangle.first, to: triangle.second)
        let edge2 = vector(from: triangle.first, to: triangle.third)
        let determinantVector = direction.cross(edge2)
        let determinant = edge1.dot(determinantVector)
        guard abs(determinant) > tolerance else {
            return nil
        }

        let inverseDeterminant = 1.0 / determinant
        let originOffset = vector(from: triangle.first, to: origin)
        let u = originOffset.dot(determinantVector) * inverseDeterminant
        guard u >= -tolerance, u <= 1.0 + tolerance else {
            return nil
        }

        let q = originOffset.cross(edge1)
        let v = direction.dot(q) * inverseDeterminant
        guard v >= -tolerance, u + v <= 1.0 + tolerance else {
            return nil
        }

        let distance = edge2.dot(q) * inverseDeterminant
        guard distance.isFinite, distance > tolerance else {
            return nil
        }
        return distance
    }

    private func minimumClearance(
        between bodies: [BodyGeometry],
        meshArtifact: MeshArtifactReference
    ) throws -> ClearanceResult? {
        let measurableBodies = bodies.filter { !$0.triangles.isEmpty }
        guard measurableBodies.count > 1 else {
            return nil
        }

        var minimum: ClearanceMeasurement?
        for firstIndex in measurableBodies.indices {
            for secondIndex in measurableBodies.index(after: firstIndex)..<measurableBodies.endIndex {
                let first = measurableBodies[firstIndex]
                let second = measurableBodies[secondIndex]
                if let current = minimum,
                   let firstBounds = first.bounds,
                   let secondBounds = second.bounds,
                   firstBounds.distanceLowerBound(to: secondBounds) >= current.distance {
                    continue
                }
                guard let triangleMeasurement = minimumTriangleDistance(
                    first.triangles,
                    second.triangles
                ) else {
                    continue
                }
                let measurement = ClearanceMeasurement(
                    distance: triangleMeasurement.distance,
                    firstBodyID: first.bodyID,
                    firstTriangleIndex: triangleMeasurement.firstTriangleIndex,
                    secondBodyID: second.bodyID,
                    secondTriangleIndex: triangleMeasurement.secondTriangleIndex
                )
                if let current = minimum {
                    if measurement.distance < current.distance {
                        minimum = measurement
                    }
                } else {
                    minimum = measurement
                }
            }
        }
        guard let minimum else {
            return nil
        }
        let clearanceRegion = try region(
            id: "manufacturing.clearance:\(minimum.firstBodyID.description):\(minimum.secondBodyID.description)",
            meshArtifact: meshArtifact,
            selections: [
                ValidationMeshTriangleSelection(
                    bodyID: minimum.firstBodyID,
                    triangleRanges: ValidationRangeAccumulator.ranges(
                        for: [minimum.firstTriangleIndex]
                    )
                ),
                ValidationMeshTriangleSelection(
                    bodyID: minimum.secondBodyID,
                    triangleRanges: ValidationRangeAccumulator.ranges(
                        for: [minimum.secondTriangleIndex]
                    )
                ),
            ]
        )
        guard let clearanceRegion else {
            return nil
        }
        return ClearanceResult(
            distance: minimum.distance,
            region: clearanceRegion
        )
    }

    private func minimumTriangleDistance(
        _ first: [MeshTriangle],
        _ second: [MeshTriangle]
    ) -> TriangleDistanceMeasurement? {
        var minimum: TriangleDistanceMeasurement?
        for firstTriangle in first {
            for secondTriangle in second {
                let distance = triangleDistance(firstTriangle, secondTriangle)
                let measurement = TriangleDistanceMeasurement(
                    distance: distance,
                    firstTriangleIndex: firstTriangle.sourceTriangleIndex,
                    secondTriangleIndex: secondTriangle.sourceTriangleIndex
                )
                if let current = minimum {
                    if measurement.distance < current.distance {
                        minimum = measurement
                    }
                } else {
                    minimum = measurement
                }
                if distance == 0.0 {
                    return measurement
                }
            }
        }
        return minimum
    }

    private func triangleDistance(
        _ first: MeshTriangle,
        _ second: MeshTriangle
    ) -> Double {
        var minimum = Double.greatestFiniteMagnitude
        for point in first.vertices {
            minimum = min(minimum, pointTriangleDistance(point, second))
        }
        for point in second.vertices {
            minimum = min(minimum, pointTriangleDistance(point, first))
        }
        for firstEdge in first.edges {
            for secondEdge in second.edges {
                minimum = min(
                    minimum,
                    segmentSegmentDistance(
                        firstStart: firstEdge.start,
                        firstEnd: firstEdge.end,
                        secondStart: secondEdge.start,
                        secondEnd: secondEdge.end
                    )
                )
            }
        }
        return minimum.isFinite ? minimum : 0.0
    }

    private func pointTriangleDistance(
        _ point: Point3D,
        _ triangle: MeshTriangle
    ) -> Double {
        let ab = vector(from: triangle.first, to: triangle.second)
        let ac = vector(from: triangle.first, to: triangle.third)
        let ap = vector(from: triangle.first, to: point)
        let d1 = ab.dot(ap)
        let d2 = ac.dot(ap)
        if d1 <= 0.0, d2 <= 0.0 {
            return distance(point, triangle.first)
        }

        let bp = vector(from: triangle.second, to: point)
        let d3 = ab.dot(bp)
        let d4 = ac.dot(bp)
        if d3 >= 0.0, d4 <= d3 {
            return distance(point, triangle.second)
        }

        let vc = d1 * d4 - d3 * d2
        if vc <= 0.0, d1 >= 0.0, d3 <= 0.0 {
            let v = d1 / (d1 - d3)
            return distance(point, offset(triangle.first, by: scaled(ab, by: v)))
        }

        let cp = vector(from: triangle.third, to: point)
        let d5 = ab.dot(cp)
        let d6 = ac.dot(cp)
        if d6 >= 0.0, d5 <= d6 {
            return distance(point, triangle.third)
        }

        let vb = d5 * d2 - d1 * d6
        if vb <= 0.0, d2 >= 0.0, d6 <= 0.0 {
            let w = d2 / (d2 - d6)
            return distance(point, offset(triangle.first, by: scaled(ac, by: w)))
        }

        let va = d3 * d6 - d5 * d4
        if va <= 0.0, (d4 - d3) >= 0.0, (d5 - d6) >= 0.0 {
            let bc = vector(from: triangle.second, to: triangle.third)
            let w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
            return distance(point, offset(triangle.second, by: scaled(bc, by: w)))
        }

        let denominator = 1.0 / (va + vb + vc)
        let v = vb * denominator
        let w = vc * denominator
        let projection = offset(
            triangle.first,
            by: add(scaled(ab, by: v), scaled(ac, by: w))
        )
        return distance(point, projection)
    }

    private func segmentSegmentDistance(
        firstStart: Point3D,
        firstEnd: Point3D,
        secondStart: Point3D,
        secondEnd: Point3D
    ) -> Double {
        let firstDirection = vector(from: firstStart, to: firstEnd)
        let secondDirection = vector(from: secondStart, to: secondEnd)
        let offsetVector = vector(from: secondStart, to: firstStart)
        let firstLengthSquared = firstDirection.dot(firstDirection)
        let secondLengthSquared = secondDirection.dot(secondDirection)
        let secondProjection = secondDirection.dot(offsetVector)
        let epsilon = 1.0e-18
        var firstParameter: Double
        var secondParameter: Double

        if firstLengthSquared <= epsilon, secondLengthSquared <= epsilon {
            return distance(firstStart, secondStart)
        }
        if firstLengthSquared <= epsilon {
            firstParameter = 0.0
            secondParameter = clamped(secondProjection / secondLengthSquared, lower: 0.0, upper: 1.0)
        } else {
            let firstProjection = firstDirection.dot(offsetVector)
            if secondLengthSquared <= epsilon {
                secondParameter = 0.0
                firstParameter = clamped(-firstProjection / firstLengthSquared, lower: 0.0, upper: 1.0)
            } else {
                let crossProjection = firstDirection.dot(secondDirection)
                let denominator = firstLengthSquared * secondLengthSquared - crossProjection * crossProjection
                if denominator != 0.0 {
                    firstParameter = clamped(
                        (crossProjection * secondProjection - firstProjection * secondLengthSquared) / denominator,
                        lower: 0.0,
                        upper: 1.0
                    )
                } else {
                    firstParameter = 0.0
                }

                let secondNumerator = crossProjection * firstParameter + secondProjection
                if secondNumerator < 0.0 {
                    secondParameter = 0.0
                    firstParameter = clamped(-firstProjection / firstLengthSquared, lower: 0.0, upper: 1.0)
                } else if secondNumerator > secondLengthSquared {
                    secondParameter = 1.0
                    firstParameter = clamped(
                        (crossProjection - firstProjection) / firstLengthSquared,
                        lower: 0.0,
                        upper: 1.0
                    )
                } else {
                    secondParameter = secondNumerator / secondLengthSquared
                }
            }
        }

        let firstPoint = offset(firstStart, by: scaled(firstDirection, by: firstParameter))
        let secondPoint = offset(secondStart, by: scaled(secondDirection, by: secondParameter))
        return distance(firstPoint, secondPoint)
    }

    private func vector(from first: Point3D, to second: Point3D) -> Vector3D {
        Vector3D(
            x: second.x - first.x,
            y: second.y - first.y,
            z: second.z - first.z
        )
    }

    private func scaled(_ vector: Vector3D, by scale: Double) -> Vector3D {
        Vector3D(
            x: vector.x * scale,
            y: vector.y * scale,
            z: vector.z * scale
        )
    }

    private func add(_ first: Vector3D, _ second: Vector3D) -> Vector3D {
        Vector3D(
            x: first.x + second.x,
            y: first.y + second.y,
            z: first.z + second.z
        )
    }

    private func offset(_ point: Point3D, by vector: Vector3D) -> Point3D {
        Point3D(
            x: point.x + vector.x,
            y: point.y + vector.y,
            z: point.z + vector.z
        )
    }

    private func distance(_ first: Point3D, _ second: Point3D) -> Double {
        vector(from: first, to: second).length
    }

    private func clamped(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    private func finiteMeshSpan(_ mesh: Mesh) -> Double {
        guard let first = mesh.positions.first(where: { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else {
            return 0.0
        }
        var minX = first.x
        var minY = first.y
        var minZ = first.z
        var maxX = first.x
        var maxY = first.y
        var maxZ = first.z
        for point in mesh.positions where point.x.isFinite && point.y.isFinite && point.z.isFinite {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            minZ = min(minZ, point.z)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
            maxZ = max(maxZ, point.z)
        }
        let span = max(maxX - minX, max(maxY - minY, maxZ - minZ))
        return span.isFinite && span > 0.0 ? span : 0.0
    }
}

private struct BodyAnalysisOutput {
    var analysis: ManufacturingMeshAnalysisResult.BodyAnalysis
    var geometry: BodyGeometry
}

private struct BodyGeometry {
    var bodyID: BodyID
    var triangles: [MeshTriangle]
    var bounds: MeshBounds?
}

private struct MeshTriangle {
    var sourceTriangleIndex: Int
    var first: Point3D
    var second: Point3D
    var third: Point3D
    var normal: Vector3D
    var area: Double

    var centroid: Point3D {
        Point3D(
            x: (first.x + second.x + third.x) / 3.0,
            y: (first.y + second.y + third.y) / 3.0,
            z: (first.z + second.z + third.z) / 3.0
        )
    }

    var vertices: [Point3D] {
        [first, second, third]
    }

    var edges: [(start: Point3D, end: Point3D)] {
        [
            (first, second),
            (second, third),
            (third, first),
        ]
    }
}

private struct WallThicknessMeasurement {
    var distance: Double
    var sourceTriangleIndex: Int
    var hitTriangleIndex: Int
}

private struct RayTriangleHit {
    var distance: Double
    var sourceTriangleIndex: Int
}

private struct TriangleDistanceMeasurement {
    var distance: Double
    var firstTriangleIndex: Int
    var secondTriangleIndex: Int
}

private struct ClearanceMeasurement {
    var distance: Double
    var firstBodyID: BodyID
    var firstTriangleIndex: Int
    var secondBodyID: BodyID
    var secondTriangleIndex: Int
}

private struct ClearanceResult {
    var distance: Double
    var region: ValidationRegionReference
}

private struct ValidationRangeAccumulator {
    private(set) var ranges: [ValidationElementRange] = []

    mutating func append(_ index: Int) {
        if let lastIndex = ranges.indices.last,
           ranges[lastIndex].endIndex == index {
            ranges[lastIndex].count += 1
            return
        }
        ranges.append(ValidationElementRange(startIndex: index, count: 1))
    }

    static func ranges(for indexes: [Int]) -> [ValidationElementRange] {
        var accumulator = ValidationRangeAccumulator()
        for index in Set(indexes).sorted() {
            accumulator.append(index)
        }
        return accumulator.ranges
    }
}

private struct MeshBounds {
    private var minX: Double?
    private var minY: Double?
    private var minZ: Double?
    private var maxX: Double?
    private var maxY: Double?
    private var maxZ: Double?

    var finalized: MeshBounds? {
        guard minX != nil else {
            return nil
        }
        return self
    }

    mutating func include(_ point: Point3D) {
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite else {
            return
        }
        minX = min(minX ?? point.x, point.x)
        minY = min(minY ?? point.y, point.y)
        minZ = min(minZ ?? point.z, point.z)
        maxX = max(maxX ?? point.x, point.x)
        maxY = max(maxY ?? point.y, point.y)
        maxZ = max(maxZ ?? point.z, point.z)
    }

    func distanceLowerBound(to other: MeshBounds) -> Double {
        sqrt(
            squaredAxisGap(minValue: minX, maxValue: maxX, otherMin: other.minX, otherMax: other.maxX)
                + squaredAxisGap(minValue: minY, maxValue: maxY, otherMin: other.minY, otherMax: other.maxY)
                + squaredAxisGap(minValue: minZ, maxValue: maxZ, otherMin: other.minZ, otherMax: other.maxZ)
        )
    }

    private func squaredAxisGap(
        minValue: Double?,
        maxValue: Double?,
        otherMin: Double?,
        otherMax: Double?
    ) -> Double {
        guard let minValue,
              let maxValue,
              let otherMin,
              let otherMax else {
            return 0.0
        }
        if maxValue < otherMin {
            let gap = otherMin - maxValue
            return gap * gap
        }
        if otherMax < minValue {
            let gap = minValue - otherMax
            return gap * gap
        }
        return 0.0
    }
}

private struct QuantizedMeshPoint: Comparable, Hashable {
    var x: Int64
    var y: Int64
    var z: Int64

    init(_ point: Point3D, tolerance: Double) {
        x = Self.quantized(point.x, tolerance: tolerance)
        y = Self.quantized(point.y, tolerance: tolerance)
        z = Self.quantized(point.z, tolerance: tolerance)
    }

    static func < (lhs: QuantizedMeshPoint, rhs: QuantizedMeshPoint) -> Bool {
        if lhs.x != rhs.x {
            return lhs.x < rhs.x
        }
        if lhs.y != rhs.y {
            return lhs.y < rhs.y
        }
        return lhs.z < rhs.z
    }

    private static func quantized(_ value: Double, tolerance: Double) -> Int64 {
        guard value.isFinite else {
            return value.sign == .minus ? Int64.min : Int64.max
        }
        let scaled = (value / tolerance).rounded()
        if scaled >= Double(Int64.max) {
            return Int64.max
        }
        if scaled <= Double(Int64.min) {
            return Int64.min
        }
        return Int64(scaled)
    }
}

private struct QuantizedMeshEdge: Hashable {
    var first: QuantizedMeshPoint
    var second: QuantizedMeshPoint

    init(_ first: Point3D, _ second: Point3D, tolerance: Double) {
        let firstPoint = QuantizedMeshPoint(first, tolerance: tolerance)
        let secondPoint = QuantizedMeshPoint(second, tolerance: tolerance)
        if firstPoint <= secondPoint {
            self.first = firstPoint
            self.second = secondPoint
        } else {
            self.first = secondPoint
            self.second = firstPoint
        }
    }
}
