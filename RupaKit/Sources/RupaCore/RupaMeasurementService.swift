import Foundation
import SwiftCAD

public struct RupaMeasurementService {
    private let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance = .standard) {
        self.tolerance = tolerance
    }

    public func measure(document: RupaDocument) throws -> RupaMeasurementResult {
        try measure(
            document: document,
            selectedFeatureIDs: nil,
            scope: .document
        )
    }

    public func measure(
        document: RupaDocument,
        selection: SelectionModel
    ) throws -> RupaMeasurementResult {
        guard !selection.selectedSceneNodeIDs.isEmpty else {
            return try measure(document: document)
        }
        let selectedFeatureIDs = Set(
            selection.selectedSceneNodeReferences(in: document).compactMap(\.featureID)
        )
        return try measure(
            document: document,
            selectedFeatureIDs: selectedFeatureIDs,
            scope: .selection
        )
    }

    private func measure(
        document: RupaDocument,
        selectedFeatureIDs: Set<FeatureID>?,
        scope: RupaMeasurementResult.Scope
    ) throws -> RupaMeasurementResult {
        var counts = RupaMeasurementResult.Counts()
        var profiles: [RupaMeasurementResult.Profile] = []
        var solids: [RupaMeasurementResult.Solid] = []
        var totals = RupaMeasurementResult.Totals()
        var bounds = BoundsAccumulator()
        var profileCache: [FeatureID: MeasuredProfile] = [:]
        var includedProfileFeatureIDs: Set<FeatureID> = []
        var includedSketchFeatureIDs: Set<FeatureID> = []
        var includedSourceFeatureIDs: Set<FeatureID> = []
        var diagnostics: [RupaDiagnostic] = []

        func shouldMeasure(_ featureID: FeatureID) -> Bool {
            guard let selectedFeatureIDs else {
                return true
            }
            return selectedFeatureIDs.contains(featureID)
        }

        func includeProfile(
            _ profile: MeasuredProfile,
            featureID: FeatureID
        ) {
            guard includedProfileFeatureIDs.insert(featureID).inserted else {
                return
            }
            profiles.append(profile.result)
            totals.profileAreaSquareMeters += profile.result.areaSquareMeters
            bounds.include(profile.result.bounds)
        }

        func includeSketch(
            featureID: FeatureID,
            sketch: Sketch,
            sketchBounds: RupaMeasurementResult.Bounds?,
            profile: MeasuredProfile?
        ) {
            guard includedSketchFeatureIDs.insert(featureID).inserted else {
                return
            }
            includedSourceFeatureIDs.insert(featureID)
            counts.sketches += 1
            counts.sketchPrimitives += sketch.entities.count
            if let sketchBounds {
                bounds.include(sketchBounds)
            }
            if let profile {
                includeProfile(profile, featureID: featureID)
            }
        }

        for featureID in document.cadDocument.designGraph.order {
            guard let node = document.cadDocument.designGraph.nodes[featureID] else {
                continue
            }
            guard !node.isSuppressed else {
                continue
            }

            switch node.operation {
            case .sketch(let sketch):
                let sketchBounds = try boundsForSketch(
                    sketch,
                    parameters: document.cadDocument.parameters
                )
                let profile = try measureProfile(
                    featureID: featureID,
                    featureName: node.name,
                    sketch: sketch,
                    parameters: document.cadDocument.parameters
                )
                if let profile {
                    profileCache[featureID] = profile
                }
                if shouldMeasure(featureID) {
                    includeSketch(
                        featureID: featureID,
                        sketch: sketch,
                        sketchBounds: sketchBounds,
                        profile: profile
                    )
                }
            case .extrude(let extrude):
                guard shouldMeasure(featureID) else {
                    continue
                }
                includedSourceFeatureIDs.insert(featureID)
                guard let sourceNode = document.cadDocument.designGraph.nodes[extrude.profile.featureID],
                      case .sketch(let sourceSketch) = sourceNode.operation else {
                    diagnostics.append(
                        RupaDiagnostic(
                            severity: .warning,
                            message: "Measurement skipped an extrude feature with an unresolved profile reference."
                        )
                    )
                    continue
                }
                let sourceSketchBounds = try boundsForSketch(
                    sourceSketch,
                    parameters: document.cadDocument.parameters
                )
                let profile = try profileCache[extrude.profile.featureID] ?? measureProfile(
                    featureID: extrude.profile.featureID,
                    featureName: sourceNode.name,
                    sketch: sourceSketch,
                    parameters: document.cadDocument.parameters
                )
                guard let profile else {
                    diagnostics.append(
                        RupaDiagnostic(
                            severity: .warning,
                            message: "Measurement skipped an extrude feature with an unsupported profile."
                        )
                    )
                    continue
                }
                profileCache[extrude.profile.featureID] = profile
                includeSketch(
                    featureID: extrude.profile.featureID,
                    sketch: sourceSketch,
                    sketchBounds: sourceSketchBounds,
                    profile: profile
                )
                let solid = try measureSolid(
                    featureID: featureID,
                    featureName: node.name,
                    sourceFeatureID: extrude.profile.featureID,
                    sourceFeatureName: sourceNode.name,
                    profile: profile,
                    extrude: extrude,
                    parameters: document.cadDocument.parameters
                )
                counts.solids += 1
                solids.append(solid)
                totals.solidVolumeCubicMeters += solid.volumeCubicMeters
                bounds.include(solid.bounds)
            }
        }

        if scope == .document {
            counts.sourceFeatures = document.cadDocument.designGraph.order.count
        } else {
            counts.sourceFeatures = includedSourceFeatureIDs.count
            if selectedFeatureIDs?.isEmpty == true {
                diagnostics.append(
                    RupaDiagnostic(
                        severity: .info,
                        message: "Selection measurement found no measurable feature references."
                    )
                )
            } else if includedSourceFeatureIDs.isEmpty {
                diagnostics.append(
                    RupaDiagnostic(
                        severity: .warning,
                        message: "Selection measurement could not resolve any selected source features."
                    )
                )
            }
        }

        counts.profiles = profiles.count
        return RupaMeasurementResult(
            scope: scope,
            displayUnit: document.displayUnit,
            counts: counts,
            bounds: bounds.bounds,
            totals: totals,
            profiles: profiles,
            solids: solids,
            diagnostics: diagnostics
        )
    }

    private func measureProfile(
        featureID: FeatureID,
        featureName: String?,
        sketch: Sketch,
        parameters: ParameterTable
    ) throws -> MeasuredProfile? {
        let frame = try planeFrame(for: sketch.plane)
        let circles = sketch.entities.values.compactMap(\.circle)
        if circles.count == 1, sketch.entities.count == 1, let circle = circles.first {
            let center2D = try resolvedPoint(circle.center, parameters: parameters)
            let center3D = frame.map(center2D)
            let radius = try resolvedLength(circle.radius, parameters: parameters)
            guard radius > tolerance.distance else {
                return nil
            }
            let bounds = circleBounds(center: center3D, radius: radius, frame: frame)
            let result = RupaMeasurementResult.Profile(
                featureID: featureID.description,
                featureName: featureName,
                kind: .circle,
                areaSquareMeters: Double.pi * radius * radius,
                bounds: bounds
            )
            return MeasuredProfile(
                result: result,
                plane: sketch.plane,
                frame: frame,
                baseBounds: bounds
            )
        }

        let lines = try sketch.entities.values.compactMap { entity -> ResolvedLine? in
            guard case .line(let line) = entity else {
                return nil
            }
            return ResolvedLine(
                start: try resolvedPoint(line.start, parameters: parameters),
                end: try resolvedPoint(line.end, parameters: parameters)
            )
        }
        guard lines.count >= 3, lines.count == sketch.entities.count else {
            return nil
        }
        guard let loop = orderedClosedLineLoop(from: lines) else {
            return nil
        }
        let area = abs(polygonArea(loop))
        guard area > tolerance.distance * tolerance.distance else {
            return nil
        }
        var loopBounds = BoundsAccumulator()
        for point in loop {
            loopBounds.include(frame.map(point))
        }
        guard let bounds = loopBounds.bounds else {
            return nil
        }
        let result = RupaMeasurementResult.Profile(
            featureID: featureID.description,
            featureName: featureName,
            kind: .lineLoop,
            areaSquareMeters: area,
            bounds: bounds
        )
        return MeasuredProfile(
            result: result,
            plane: sketch.plane,
            frame: frame,
            baseBounds: bounds
        )
    }

    private func measureSolid(
        featureID: FeatureID,
        featureName: String?,
        sourceFeatureID: FeatureID,
        sourceFeatureName: String?,
        profile: MeasuredProfile,
        extrude: ExtrudeFeature,
        parameters: ParameterTable
    ) throws -> RupaMeasurementResult.Solid {
        let distance = try resolvedLength(extrude.distance, parameters: parameters)
        let extrusionDirection = try directionVector(
            for: extrude.direction,
            frame: profile.frame
        )
        let normalComponent = extrusionDirection.dot(profile.frame.normal)
        guard abs(normalComponent) > tolerance.angle else {
            throw RupaError(
                code: .commandFailed,
                message: "Measurement cannot compute volume for an extrude direction parallel to the profile plane."
            )
        }

        let bottomOffset: Vector3D
        let topOffset: Vector3D
        switch extrude.direction {
        case .symmetric:
            bottomOffset = extrusionDirection * (-distance / 2.0)
            topOffset = extrusionDirection * (distance / 2.0)
        case .normal, .vector:
            bottomOffset = .zero
            topOffset = extrusionDirection * distance
        }

        var bounds = BoundsAccumulator()
        bounds.include(profile.baseBounds.translated(by: bottomOffset))
        bounds.include(profile.baseBounds.translated(by: topOffset))
        guard let solidBounds = bounds.bounds else {
            throw RupaError(
                code: .commandFailed,
                message: "Measurement could not compute solid bounds."
            )
        }

        let height = abs(distance * normalComponent)
        return RupaMeasurementResult.Solid(
            featureID: featureID.description,
            featureName: featureName,
            sourceFeatureID: sourceFeatureID.description,
            sourceFeatureName: sourceFeatureName,
            heightMeters: height,
            volumeCubicMeters: profile.result.areaSquareMeters * height,
            bounds: solidBounds
        )
    }

    private func boundsForSketch(
        _ sketch: Sketch,
        parameters: ParameterTable
    ) throws -> RupaMeasurementResult.Bounds? {
        let frame = try planeFrame(for: sketch.plane)
        var bounds = BoundsAccumulator()
        for entity in sketch.entities.values {
            switch entity {
            case .point(let point):
                bounds.include(frame.map(try resolvedPoint(point, parameters: parameters)))
            case .line(let line):
                bounds.include(frame.map(try resolvedPoint(line.start, parameters: parameters)))
                bounds.include(frame.map(try resolvedPoint(line.end, parameters: parameters)))
            case .circle(let circle):
                let center = frame.map(try resolvedPoint(circle.center, parameters: parameters))
                let radius = try resolvedLength(circle.radius, parameters: parameters)
                bounds.include(circleBounds(center: center, radius: radius, frame: frame))
            }
        }
        return bounds.bounds
    }

    private func resolvedPoint(
        _ point: SketchPoint,
        parameters: ParameterTable
    ) throws -> Point2D {
        Point2D(
            x: try resolvedLength(point.x, parameters: parameters),
            y: try resolvedLength(point.y, parameters: parameters)
        )
    }

    private func resolvedLength(
        _ expression: CADExpression,
        parameters: ParameterTable
    ) throws -> Double {
        let quantity = try parameters.resolvedValue(for: expression)
        guard quantity.kind == .length else {
            throw RupaError(
                code: .commandFailed,
                message: "Measurement expected a length expression."
            )
        }
        return quantity.value
    }

    private func orderedClosedLineLoop(from lines: [ResolvedLine]) -> [Point2D]? {
        var remaining = lines
        guard let first = remaining.first else {
            return nil
        }
        remaining.removeFirst()
        var points = [first.start, first.end]
        var current = first.end

        while !remaining.isEmpty {
            guard let index = remaining.firstIndex(where: { line in
                isClose(line.start, current) || isClose(line.end, current)
            }) else {
                return nil
            }
            let line = remaining.remove(at: index)
            if isClose(line.start, current) {
                current = line.end
                points.append(line.end)
            } else {
                current = line.start
                points.append(line.start)
            }
        }

        guard isClose(current, points[0]) else {
            return nil
        }
        if let last = points.last, isClose(last, points[0]) {
            points.removeLast()
        }
        return points.count >= 3 ? points : nil
    }

    private func polygonArea(_ points: [Point2D]) -> Double {
        var twiceArea = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            twiceArea += current.x * next.y - next.x * current.y
        }
        return twiceArea / 2.0
    }

    private func isClose(_ lhs: Point2D, _ rhs: Point2D) -> Bool {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return (dx * dx + dy * dy).squareRoot() <= tolerance.distance
    }

    private func planeFrame(for plane: SketchPlane) throws -> PlaneFrame {
        switch plane {
        case .xy:
            return PlaneFrame(
                origin: .origin,
                normal: .unitZ,
                u: .unitX,
                v: .unitY
            )
        case .yz:
            return PlaneFrame(
                origin: .origin,
                normal: .unitX,
                u: .unitY,
                v: .unitZ
            )
        case .zx:
            return PlaneFrame(
                origin: .origin,
                normal: .unitY,
                u: .unitZ,
                v: .unitX
            )
        case .plane(let plane):
            let normal = try plane.normal.normalized(tolerance: tolerance.distance)
            let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
            let u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
            let v = normal.cross(u)
            return PlaneFrame(
                origin: plane.origin,
                normal: normal,
                u: u,
                v: v
            )
        }
    }

    private func directionVector(
        for direction: ExtrudeDirection,
        frame: PlaneFrame
    ) throws -> Vector3D {
        switch direction {
        case .normal, .symmetric:
            return frame.normal
        case .vector(let vector):
            return try vector.normalized(tolerance: tolerance.distance)
        }
    }

    private func circleBounds(
        center: Point3D,
        radius: Double,
        frame: PlaneFrame
    ) -> RupaMeasurementResult.Bounds {
        let xExtent = radius * hypot(frame.u.x, frame.v.x)
        let yExtent = radius * hypot(frame.u.y, frame.v.y)
        let zExtent = radius * hypot(frame.u.z, frame.v.z)
        return RupaMeasurementResult.Bounds(
            minX: center.x - xExtent,
            minY: center.y - yExtent,
            minZ: center.z - zExtent,
            maxX: center.x + xExtent,
            maxY: center.y + yExtent,
            maxZ: center.z + zExtent
        )
    }
}

private struct MeasuredProfile {
    var result: RupaMeasurementResult.Profile
    var plane: SketchPlane
    var frame: PlaneFrame
    var baseBounds: RupaMeasurementResult.Bounds
}

private struct PlaneFrame {
    var origin: Point3D
    var normal: Vector3D
    var u: Vector3D
    var v: Vector3D

    func map(_ point: Point2D) -> Point3D {
        origin + (u * point.x) + (v * point.y)
    }
}

private struct ResolvedLine {
    var start: Point2D
    var end: Point2D
}

private struct Point2D: Equatable {
    var x: Double
    var y: Double
}

private struct BoundsAccumulator {
    private(set) var bounds: RupaMeasurementResult.Bounds?

    mutating func include(_ point: Point3D) {
        include(
            RupaMeasurementResult.Bounds(
                minX: point.x,
                minY: point.y,
                minZ: point.z,
                maxX: point.x,
                maxY: point.y,
                maxZ: point.z
            )
        )
    }

    mutating func include(_ next: RupaMeasurementResult.Bounds) {
        guard let current = bounds else {
            bounds = next
            return
        }
        bounds = RupaMeasurementResult.Bounds(
            minX: min(current.minX, next.minX),
            minY: min(current.minY, next.minY),
            minZ: min(current.minZ, next.minZ),
            maxX: max(current.maxX, next.maxX),
            maxY: max(current.maxY, next.maxY),
            maxZ: max(current.maxZ, next.maxZ)
        )
    }
}

private extension RupaMeasurementResult.Bounds {
    func translated(by vector: Vector3D) -> RupaMeasurementResult.Bounds {
        RupaMeasurementResult.Bounds(
            minX: minX + vector.x,
            minY: minY + vector.y,
            minZ: minZ + vector.z,
            maxX: maxX + vector.x,
            maxY: maxY + vector.y,
            maxZ: maxZ + vector.z
        )
    }
}

private extension SketchEntity {
    var circle: SketchCircle? {
        if case .circle(let circle) = self {
            return circle
        }
        return nil
    }
}
