import Foundation
import RupaCore
import RupaCoreTypes
import RupaKit
import SwiftCAD

/// Reads the source that existed before the placement command and checks its
/// semantic geometry independently from the requested transform.
enum CADTransformInitialSourceOracle {
    struct Observation: Sendable {
        let readCount: Int
    }

    static func evaluate(
        expected: CADTransformSource,
        caseID: CADBenchmarkCaseID,
        sceneNodeID: SceneNodeID,
        snapshot: ProjectViewSnapshot
    ) throws -> Observation {
        let document = snapshot.document.document
        let tolerance = try CADBenchmarkTolerancePolicy(
            modelingTolerance: document.modelingSettings.tolerance
        )
        guard let sourceNode = document.productMetadata.sceneNodes[sceneNodeID],
              let reference = sourceNode.reference,
              let sourceFeatureID = reference.featureID,
              let sourceFeature = document.cadDocument.designGraph.nodes[sourceFeatureID] else {
            throw CADTransformOracleError.mismatch(
                "The initial transform source node or feature is missing."
            )
        }

        let sourceKind: SourceKind
        switch expected {
        case .line, .rectangle, .circle:
            guard reference.kind == .sketch else {
                throw CADTransformOracleError.mismatch(
                    "A sketch transform source must bind to a sketch scene node."
                )
            }
            sourceKind = .sketch
        case .box, .cylinder:
            guard reference.kind == .body else {
                throw CADTransformOracleError.mismatch(
                    "A solid transform source must bind to a body scene node."
                )
            }
            sourceKind = .body
        }

        let sketchFeatureID: FeatureID
        let bodyFeatureID: FeatureID?
        let sketch: Sketch
        switch sourceKind {
        case .sketch:
            guard case .sketch(let sourceSketch) = sourceFeature.operation else {
                throw CADTransformOracleError.mismatch(
                    "The initial sketch scene node does not reference a sketch feature."
                )
            }
            guard document.cadDocument.designGraph.nodes.count == 1,
                  document.cadDocument.designGraph.order == [sourceFeatureID] else {
                throw CADTransformOracleError.mismatch(
                    "A sketch transform source must contain exactly one feature."
                )
            }
            sketchFeatureID = sourceFeatureID
            bodyFeatureID = nil
            sketch = sourceSketch
        case .body:
            guard case .extrude(let extrude) = sourceFeature.operation,
                  extrude.profile.profileIndex == 0,
                  extrude.direction == .normal,
                  extrude.operation == .newBody,
                  document.cadDocument.designGraph.order.last == sourceFeatureID,
                  document.cadDocument.designGraph.nodes.count == 2,
                  let sourceSketch = document.cadDocument.designGraph.nodes[extrude.profile.featureID],
                  case .sketch(let bodySketch) = sourceSketch.operation else {
                throw CADTransformOracleError.mismatch(
                    "The initial solid transform source is not one normal extrude of one sketch."
                )
            }
            guard sourceFeature.outputs.contains(where: { $0.role == .body }) else {
                throw CADTransformOracleError.mismatch(
                    "The initial solid transform source has no body output."
                )
            }
            sketchFeatureID = extrude.profile.featureID
            bodyFeatureID = sourceFeatureID
            sketch = bodySketch
        }

        let expectedPlane = try sourcePlane(
            expected: expected,
            modelingTolerance: tolerance.modelingTolerance,
            caseID: caseID
        )
        guard sketch.plane == expectedPlane else {
            throw CADTransformOracleError.mismatch(
                "The initial source sketch plane does not match the private expectation."
            )
        }

        // One read is the feature graph, and one is the immutable sketch/entity
        // summary. A body adds one exact B-rep read below.
        var readCount = 2
        let sourceSnapshot: SketchEntitySnapshot
        do {
            sourceSnapshot = try SketchEntitySnapshotService().snapshot(
                document: document,
                objectRegistry: snapshot.objectRegistry
            )
        } catch {
            throw CADTransformOracleError.mismatch(
                "The initial source sketch/entity snapshot could not be read: \(error)."
            )
        }

        guard sourceSnapshot.counts.sketchCount == 1,
              sourceSnapshot.sketches.count == 1,
              let sketchEntry = sourceSnapshot.sketches.first,
              sketchEntry.sourceFeatureID == sketchFeatureID.description,
              sketchEntry.plane == expectedPlane,
              let entries = sourceEntries(
                  in: sourceSnapshot,
                  featureID: sketchFeatureID
              ) else {
            throw CADTransformOracleError.mismatch(
                "The initial source sketch/entity summary has an unexpected feature binding."
            )
        }

        switch expected {
        case .line(let input):
            try validateLine(
                input,
                entries: entries,
                sourcePlane: expectedPlane,
                tolerance: tolerance,
                caseID: caseID
            )
        case .rectangle(let input):
            try validateRectangle(
                input,
                entries: entries,
                sourceSnapshot: sourceSnapshot,
                sourceFeatureID: sketchFeatureID,
                sourcePlane: expectedPlane,
                tolerance: tolerance,
                caseID: caseID
            )
        case .circle(let input):
            try validateCircle(
                input,
                entries: entries,
                sourceSnapshot: sourceSnapshot,
                sourceFeatureID: sketchFeatureID,
                sourcePlane: expectedPlane,
                tolerance: tolerance,
                caseID: caseID
            )
        case .box(let input):
            try validateBoxSketch(
                input,
                entries: entries,
                sourceSnapshot: sourceSnapshot,
                sourceFeatureID: sketchFeatureID,
                sourcePlane: expectedPlane,
                tolerance: tolerance,
                caseID: caseID
            )
            guard let bodyFeatureID else {
                throw CADTransformOracleError.mismatch(
                    "The initial box source has no body feature."
                )
            }
            try validateBoxFeature(
                input,
                bodyFeatureID: bodyFeatureID,
                document: document,
                tolerance: tolerance
            )
            readCount += 1
            try validateBoxTopology(
                input,
                bodyFeatureID: bodyFeatureID,
                document: document,
                snapshot: snapshot,
                tolerance: tolerance
            )
        case .cylinder(let input):
            try validateCylinderSketch(
                input,
                entries: entries,
                sourceSnapshot: sourceSnapshot,
                sourceFeatureID: sketchFeatureID,
                sourcePlane: expectedPlane,
                tolerance: tolerance,
                caseID: caseID
            )
            guard let bodyFeatureID else {
                throw CADTransformOracleError.mismatch(
                    "The initial cylinder source has no body feature."
                )
            }
            try validateCylinderFeature(
                input,
                bodyFeatureID: bodyFeatureID,
                document: document,
                tolerance: tolerance
            )
            readCount += 1
            try validateCylinderTopology(
                input,
                bodyFeatureID: bodyFeatureID,
                document: document,
                snapshot: snapshot,
                tolerance: tolerance,
                caseID: caseID
            )
        }

        return Observation(readCount: readCount)
    }

    private enum SourceKind {
        case sketch
        case body
    }

    private static func sourceEntries(
        in snapshot: SketchEntitySnapshot,
        featureID: FeatureID
    ) -> [SketchEntitySummaryResult.EntityEntry]? {
        let entries = snapshot.entries.filter {
            $0.sourceFeatureID == featureID.description
        }
        return entries.isEmpty ? nil : entries
    }

    private static func sourcePlane(
        expected: CADTransformSource,
        modelingTolerance: ModelingTolerance,
        caseID: CADBenchmarkCaseID
    ) throws -> SketchPlane {
        switch expected {
        case .line(let input):
            return try CADLineGeometryMapping.sourcePlane(
                orientation: input.plane,
                anchor: input.start,
                modelingTolerance: modelingTolerance,
                caseID: caseID
            )
        case .rectangle(let input):
            return try CADRectangleGeometryMapping.sourcePlane(
                orientation: input.plane,
                targetCenter: input.center,
                submittedCenter: input.center,
                modelingTolerance: modelingTolerance,
                caseID: caseID
            )
        case .circle(let input):
            return try CADCircleGeometryMapping.sourcePlane(
                orientation: input.plane,
                targetCenter: input.center,
                submittedCenter: input.center,
                modelingTolerance: modelingTolerance,
                caseID: caseID
            )
        case .box(let input):
            return try CADBoxGeometryMapping.sourcePlane(
                submittedOrigin: input.origin,
                submittedWidth: input.width,
                submittedDepth: input.depth,
                caseID: caseID
            )
        case .cylinder(let input):
            return try CADCylinderGeometryMapping.commandGeometry(
                baseCenter: input.baseCenter,
                axis: input.axis,
                caseID: caseID
            ).plane
        }
    }

    private static func validateLine(
        _ input: CADLineChallengeInput,
        entries: [SketchEntitySummaryResult.EntityEntry],
        sourcePlane: SketchPlane,
        tolerance: CADBenchmarkTolerancePolicy,
        caseID: CADBenchmarkCaseID
    ) throws {
        guard entries.count == 1,
              let entry = entries.first,
              entry.entityKind == "line",
              let localStart = entry.start,
              let localEnd = entry.end else {
            throw CADTransformOracleError.mismatch(
                "The initial line source is not exactly one finite line entity."
            )
        }
        let observedStart: Point3D
        let observedEnd: Point3D
        do {
            observedStart = try CADLineGeometryMapping.worldPoint(
                from: localStart,
                sourcePlane: sourcePlane,
                modelingTolerance: tolerance.modelingTolerance
            )
            observedEnd = try CADLineGeometryMapping.worldPoint(
                from: localEnd,
                sourcePlane: sourcePlane,
                modelingTolerance: tolerance.modelingTolerance
            )
        } catch {
            throw CADTransformOracleError.mismatch(
                "The initial line endpoints could not be mapped to world space: \(error)."
            )
        }
        guard accepts(input.start.meters, observed: observedStart, tolerance: tolerance),
              accepts(input.end.meters, observed: observedEnd, tolerance: tolerance),
              tolerance.acceptsLinear(
                  expected: input.length.meters,
                  observed: (observedEnd - observedStart).length
              ) else {
            throw CADTransformOracleError.mismatch(
                "The initial line endpoints or length do not match the private expectation."
            )
        }
    }

    private static func validateRectangle(
        _ input: CADRectangleChallengeInput,
        entries: [SketchEntitySummaryResult.EntityEntry],
        sourceSnapshot: SketchEntitySnapshot,
        sourceFeatureID: FeatureID,
        sourcePlane: SketchPlane,
        tolerance: CADBenchmarkTolerancePolicy,
        caseID: CADBenchmarkCaseID
    ) throws {
        try validateRectangleProfile(
            entries: entries,
            sourceSnapshot: sourceSnapshot,
            sourceFeatureID: sourceFeatureID,
            width: input.width.meters,
            height: input.height.meters,
            sourcePlane: sourcePlane,
            tolerance: tolerance,
            caseID: caseID,
            expectedCenter: input.center
        )
    }

    private static func validateBoxSketch(
        _ input: CADBoxChallengeInput,
        entries: [SketchEntitySummaryResult.EntityEntry],
        sourceSnapshot: SketchEntitySnapshot,
        sourceFeatureID: FeatureID,
        sourcePlane: SketchPlane,
        tolerance: CADBenchmarkTolerancePolicy,
        caseID: CADBenchmarkCaseID
    ) throws {
        try validateRectangleProfile(
            entries: entries,
            sourceSnapshot: sourceSnapshot,
            sourceFeatureID: sourceFeatureID,
            width: input.width.meters,
            height: input.depth.meters,
            sourcePlane: sourcePlane,
            tolerance: tolerance,
            caseID: caseID,
            expectedCenter: CADBoxGeometryMapping.bottomCenter(
                origin: input.origin,
                width: input.width,
                depth: input.depth
            )
        )
    }

    private static func validateRectangleProfile(
        entries: [SketchEntitySummaryResult.EntityEntry],
        sourceSnapshot: SketchEntitySnapshot,
        sourceFeatureID: FeatureID,
        width: Double,
        height: Double,
        sourcePlane: SketchPlane,
        tolerance: CADBenchmarkTolerancePolicy,
        caseID: CADBenchmarkCaseID,
        expectedCenter: CADPoint3D
    ) throws {
        guard entries.count == 4,
              entries.allSatisfy({ $0.entityKind == "line" }),
              sourceSnapshot.counts.entityCount == 4,
              sourceSnapshot.counts.regionCount == 1,
              let region = sourceSnapshot.regions.first,
              region.sourceFeatureID == sourceFeatureID.description,
              region.plane == sourcePlane,
              region.boundaryPointCount == 4,
              region.boundarySegmentCount == 4,
              tolerance.acceptsLinear(expected: 0, observed: region.center.x),
              tolerance.acceptsLinear(expected: 0, observed: region.center.y) else {
            throw CADTransformOracleError.mismatch(
                "The initial rectangle source is not one closed four-edge profile."
            )
        }

        let points = entries.flatMap { entry in
            [entry.start, entry.end].compactMap { $0 }
        }
        guard points.count == 8,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw CADTransformOracleError.mismatch(
                "The initial rectangle source has incomplete or non-finite endpoints."
            )
        }
        let minX = points.map(\.x).min()!
        let maxX = points.map(\.x).max()!
        let minY = points.map(\.y).min()!
        let maxY = points.map(\.y).max()!
        guard tolerance.acceptsLinear(expected: width, observed: maxX - minX),
              tolerance.acceptsLinear(expected: height, observed: maxY - minY),
              tolerance.acceptsLinear(expected: -width / 2, observed: minX),
              tolerance.acceptsLinear(expected: width / 2, observed: maxX),
              tolerance.acceptsLinear(expected: -height / 2, observed: minY),
              tolerance.acceptsLinear(expected: height / 2, observed: maxY) else {
            throw CADTransformOracleError.mismatch(
                "The initial rectangle dimensions do not match the private expectation."
            )
        }

        let observedCenter: Point3D
        do {
            observedCenter = try CADRectangleGeometryMapping.worldPoint(
                from: SketchEntitySummaryResult.Point(x: 0, y: 0),
                sourcePlane: sourcePlane,
                modelingTolerance: tolerance.modelingTolerance
            )
        } catch {
            throw CADTransformOracleError.mismatch(
                "The initial rectangle center could not be mapped to world space: \(error)."
            )
        }
        guard accepts(expectedCenter.meters, observed: observedCenter, tolerance: tolerance) else {
            throw CADTransformOracleError.mismatch(
                "The initial rectangle center does not match the private expectation."
            )
        }
    }

    private static func validateCircle(
        _ input: CADCircleChallengeInput,
        entries: [SketchEntitySummaryResult.EntityEntry],
        sourceSnapshot: SketchEntitySnapshot,
        sourceFeatureID: FeatureID,
        sourcePlane: SketchPlane,
        tolerance: CADBenchmarkTolerancePolicy,
        caseID: CADBenchmarkCaseID
    ) throws {
        guard entries.count == 1,
              let entry = entries.first,
              entry.entityKind == "circle",
              let localCenter = entry.center,
              let radius = entry.radius,
              sourceSnapshot.counts.entityCount == 1,
              sourceSnapshot.counts.regionCount == 1,
              let region = sourceSnapshot.regions.first,
              region.sourceFeatureID == sourceFeatureID.description,
              region.plane == sourcePlane,
              tolerance.acceptsLinear(expected: 0, observed: region.center.x),
              tolerance.acceptsLinear(expected: 0, observed: region.center.y) else {
            throw CADTransformOracleError.mismatch(
                "The initial circle source is not exactly one analytic circle profile."
            )
        }
        let observedCenter: Point3D
        do {
            observedCenter = try CADCircleGeometryMapping.worldPoint(
                from: localCenter,
                sourcePlane: sourcePlane,
                modelingTolerance: tolerance.modelingTolerance
            )
        } catch {
            throw CADTransformOracleError.mismatch(
                "The initial circle center could not be mapped to world space: \(error)."
            )
        }
        guard accepts(input.center.meters, observed: observedCenter, tolerance: tolerance),
              tolerance.acceptsLinear(expected: input.radius.meters, observed: radius) else {
            throw CADTransformOracleError.mismatch(
                "The initial circle center or radius does not match the private expectation."
            )
        }
    }

    private static func validateCylinderSketch(
        _ input: CADCylinderChallengeInput,
        entries: [SketchEntitySummaryResult.EntityEntry],
        sourceSnapshot: SketchEntitySnapshot,
        sourceFeatureID: FeatureID,
        sourcePlane: SketchPlane,
        tolerance: CADBenchmarkTolerancePolicy,
        caseID: CADBenchmarkCaseID
    ) throws {
        try validateCircle(
            CADCircleChallengeInput(
                center: input.baseCenter,
                radius: input.radius,
                plane: .xy
            ),
            entries: entries,
            sourceSnapshot: sourceSnapshot,
            sourceFeatureID: sourceFeatureID,
            sourcePlane: sourcePlane,
            tolerance: tolerance,
            caseID: caseID
        )
    }

    private static func validateBoxFeature(
        _ input: CADBoxChallengeInput,
        bodyFeatureID: FeatureID,
        document: DesignDocument,
        tolerance: CADBenchmarkTolerancePolicy
    ) throws {
        guard let bodyFeature = document.cadDocument.designGraph.nodes[bodyFeatureID],
              case .extrude(let extrude) = bodyFeature.operation else {
            throw CADTransformOracleError.mismatch(
                "The initial box body feature is not an extrude."
            )
        }
        let distance = try document.cadDocument.parameters.resolvedValue(for: extrude.distance)
        guard distance.kind == .length,
              tolerance.acceptsLinear(expected: input.height.meters, observed: distance.value),
              let bodyNode = document.productMetadata.sceneNodes.values.first(where: {
                  $0.reference == .body(bodyFeatureID)
              }),
              bodyNode.object?.typeID == .cube else {
            throw CADTransformOracleError.mismatch(
                "The initial box feature or body metadata has the wrong height or type."
            )
        }
    }

    private static func validateCylinderFeature(
        _ input: CADCylinderChallengeInput,
        bodyFeatureID: FeatureID,
        document: DesignDocument,
        tolerance: CADBenchmarkTolerancePolicy
    ) throws {
        guard let bodyFeature = document.cadDocument.designGraph.nodes[bodyFeatureID],
              case .extrude(let extrude) = bodyFeature.operation else {
            throw CADTransformOracleError.mismatch(
                "The initial cylinder body feature is not an extrude."
            )
        }
        let distance = try document.cadDocument.parameters.resolvedValue(for: extrude.distance)
        guard distance.kind == .length,
              tolerance.acceptsLinear(expected: input.depth.meters, observed: distance.value),
              let bodyNode = document.productMetadata.sceneNodes.values.first(where: {
                  $0.reference == .body(bodyFeatureID)
              }),
              bodyNode.object?.typeID == .cylinder else {
            throw CADTransformOracleError.mismatch(
                "The initial cylinder feature or body metadata has the wrong depth or type."
            )
        }
    }

    private static func validateBoxTopology(
        _ input: CADBoxChallengeInput,
        bodyFeatureID: FeatureID,
        document: DesignDocument,
        snapshot: ProjectViewSnapshot,
        tolerance: CADBenchmarkTolerancePolicy
    ) throws {
        let topology = try topology(
            document: document,
            snapshot: snapshot
        )
        guard topology.counts.bodyCount == 1,
              topology.counts.faceCount == 6,
              topology.counts.edgeCount == 12,
              topology.counts.vertexCount == 8 else {
            throw CADTransformOracleError.mismatch(
                "The initial box B-rep does not have one closed analytic solid."
            )
        }
        let vertices = topology.entries.filter {
            $0.sourceFeatureID == bodyFeatureID.description && $0.kind == .vertex
        }.compactMap(\.start)
        let origin = input.origin.meters
        let maximum = (
            x: origin.x + input.width.meters,
            y: origin.y + input.depth.meters,
            z: origin.z + input.height.meters
        )
        guard vertices.count == 8,
              vertices.allSatisfy({ point in
                  (tolerance.acceptsLinear(expected: origin.x, observed: point.x)
                      || tolerance.acceptsLinear(expected: maximum.x, observed: point.x))
                      && (tolerance.acceptsLinear(expected: origin.y, observed: point.y)
                          || tolerance.acceptsLinear(expected: maximum.y, observed: point.y))
                      && (tolerance.acceptsLinear(expected: origin.z, observed: point.z)
                          || tolerance.acceptsLinear(expected: maximum.z, observed: point.z))
              }) else {
            throw CADTransformOracleError.mismatch(
                "The initial box B-rep vertices do not match the private dimensions."
            )
        }
    }

    private static func validateCylinderTopology(
        _ input: CADCylinderChallengeInput,
        bodyFeatureID: FeatureID,
        document: DesignDocument,
        snapshot: ProjectViewSnapshot,
        tolerance: CADBenchmarkTolerancePolicy,
        caseID: CADBenchmarkCaseID
    ) throws {
        let topology = try topology(
            document: document,
            snapshot: snapshot
        )
        guard topology.counts.bodyCount == 1,
              topology.counts.faceCount == 6,
              topology.counts.edgeCount == 12,
              topology.counts.vertexCount == 8 else {
            throw CADTransformOracleError.mismatch(
                "The initial cylinder B-rep does not have one closed analytic solid."
            )
        }
        let geometry = try CADCylinderGeometryMapping.commandGeometry(
            baseCenter: input.baseCenter,
            axis: input.axis,
            caseID: caseID
        )
        let entries = topology.entries.filter {
            $0.sourceFeatureID == bodyFeatureID.description
        }
        let cylinderFaces = entries.filter {
            $0.kind == .face && $0.surfaceKind == "cylinder"
        }
        let planarFaces = entries.filter {
            $0.kind == .face && $0.surfaceKind == "plane"
        }
        let baseCenter = input.baseCenter.meters
        let base = (x: baseCenter.x, y: baseCenter.y, z: baseCenter.z)
        let axis = geometry.normalizedAxis
        let endpoint = (
            x: base.x + axis.x * input.depth.meters,
            y: base.y + axis.y * input.depth.meters,
            z: base.z + axis.z * input.depth.meters
        )
        guard cylinderFaces.count == 4,
              planarFaces.count == 2,
              cylinderFaces.allSatisfy({ face in
                  guard let radius = face.surfaceRadius,
                        let observedAxis = face.surfaceAxis else { return false }
                  return tolerance.acceptsLinear(expected: input.radius.meters, observed: radius)
                      && parallel(observedAxis, axis: axis, tolerance: tolerance)
              }),
              planarFaces.allSatisfy({ face in
                  guard let center = face.center else { return false }
                  return samePoint(center, base, tolerance: tolerance)
                      || samePoint(center, endpoint, tolerance: tolerance)
              }) else {
            throw CADTransformOracleError.mismatch(
                "The initial cylinder B-rep does not match the private axis, radius, or depth."
            )
        }
    }

    private static func topology(
        document: DesignDocument,
        snapshot: ProjectViewSnapshot
    ) throws -> TopologySnapshot {
        do {
            return try TopologySnapshotService().snapshot(
                document: document,
                objectRegistry: snapshot.objectRegistry,
                currentEvaluation: snapshot.cadInteraction,
                currentGeneration: snapshot.documentGeneration
            )
        } catch {
            throw CADTransformOracleError.mismatch(
                "The initial exact B-rep could not be read: \(error)."
            )
        }
    }

    private static func accepts(
        _ expected: CADPoint3D,
        observed: Point3D,
        tolerance: CADBenchmarkTolerancePolicy
    ) -> Bool {
        tolerance.acceptsLinear(expected: expected.x, observed: observed.x)
            && tolerance.acceptsLinear(expected: expected.y, observed: observed.y)
            && tolerance.acceptsLinear(expected: expected.z, observed: observed.z)
    }

    private static func samePoint(
        _ point: TopologySummaryResult.Entry.Point,
        _ expected: (x: Double, y: Double, z: Double),
        tolerance: CADBenchmarkTolerancePolicy
    ) -> Bool {
        tolerance.acceptsLinear(expected: expected.x, observed: point.x)
            && tolerance.acceptsLinear(expected: expected.y, observed: point.y)
            && tolerance.acceptsLinear(expected: expected.z, observed: point.z)
    }

    private static func parallel(
        _ observed: TopologySummaryResult.Entry.Point,
        axis: CADDirection3D,
        tolerance: CADBenchmarkTolerancePolicy
    ) -> Bool {
        let length = sqrt(
            observed.x * observed.x
                + observed.y * observed.y
                + observed.z * observed.z
        )
        guard length.isFinite, length > 0 else { return false }
        let dot = abs(
            observed.x * axis.x
                + observed.y * axis.y
                + observed.z * axis.z
        ) / length / axis.length
        return tolerance.acceptsLinear(expected: 1, observed: dot)
    }
}
