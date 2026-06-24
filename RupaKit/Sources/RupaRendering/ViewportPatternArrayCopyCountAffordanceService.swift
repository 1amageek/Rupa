import CoreGraphics
import RupaCore

struct ViewportPatternArrayCopyCountAffordanceService: Sendable {
    func candidates(
        document: DesignDocument,
        scene: ViewportScene,
        selection: SelectionModel,
        layout: ViewportLayout
    ) -> [ViewportPatternArrayCopyCountAffordanceCandidate] {
        let metadata = document.productMetadata
        let index = ViewportPatternArraySourceSelectionIndex(
            metadata: metadata,
            scene: scene,
            selection: selection
        )
        let sourceIDs = index.selectedSourceIDs()
        guard !sourceIDs.isEmpty else {
            return []
        }
        let expressionResolver = PatternArrayExpressionResolver(parameters: document.cadDocument.parameters)
        return sourceIDs.flatMap { sourceID in
            candidates(
                sourceID: sourceID,
                document: document,
                metadata: metadata,
                expressionResolver: expressionResolver,
                index: index,
                layout: layout
            )
        }
    }

    private func candidates(
        sourceID: PatternArraySourceID,
        document: DesignDocument,
        metadata: ProductMetadata,
        expressionResolver: PatternArrayExpressionResolver,
        index: ViewportPatternArraySourceSelectionIndex,
        layout: ViewportLayout
    ) -> [ViewportPatternArrayCopyCountAffordanceCandidate] {
        guard let source = metadata.patternArrays[sourceID] else {
            return []
        }
        switch source.distribution {
        case .rectangular(let rectangular):
            return rectangularCandidates(
                sourceID: sourceID,
                rectangular: rectangular,
                source: source,
                expressionResolver: expressionResolver,
                index: index,
                layout: layout
            )
        case .radial(let radial):
            return radialCandidates(
                sourceID: sourceID,
                radial: radial,
                source: source,
                expressionResolver: expressionResolver,
                index: index,
                layout: layout
            )
        case .curve(let curve):
            if let candidate = curveCandidate(
                sourceID: sourceID,
                curve: curve,
                document: document,
                layout: layout
            ) {
                return [candidate]
            }
            return []
        }
    }

    private func rectangularCandidates(
        sourceID: PatternArraySourceID,
        rectangular: RectangularPatternArray,
        source: PatternArraySource,
        expressionResolver: PatternArrayExpressionResolver,
        index: ViewportPatternArraySourceSelectionIndex,
        layout: ViewportLayout
    ) -> [ViewportPatternArrayCopyCountAffordanceCandidate] {
        guard let baseProjectedPoint = index.sourceBaseProjectedPoint(source: source, layout: layout) else {
            return []
        }
        var result: [ViewportPatternArrayCopyCountAffordanceCandidate] = []
        if let candidate = linearCandidate(
            sourceID: sourceID,
            slot: .rectangularFirst,
            axis: rectangular.firstAxis,
            expressionResolver: expressionResolver,
            baseProjectedPoint: baseProjectedPoint,
            layout: layout
        ) {
            result.append(candidate)
        }
        if let secondAxis = rectangular.secondAxis,
           let candidate = linearCandidate(
            sourceID: sourceID,
            slot: .rectangularSecond,
            axis: secondAxis,
            expressionResolver: expressionResolver,
            baseProjectedPoint: baseProjectedPoint,
            layout: layout
           ) {
            result.append(candidate)
        }
        return result
    }

    private func radialCandidates(
        sourceID: PatternArraySourceID,
        radial: RadialPatternArray,
        source: PatternArraySource,
        expressionResolver: PatternArrayExpressionResolver,
        index: ViewportPatternArraySourceSelectionIndex,
        layout: ViewportLayout
    ) -> [ViewportPatternArrayCopyCountAffordanceCandidate] {
        var result: [ViewportPatternArrayCopyCountAffordanceCandidate] = []
        if let referencePoint = index.sourceBaseModelPoint(source: source),
           let angleRadians = resolvedAngleRadians(radial.angularAxis.angle, expressionResolver: expressionResolver),
           let candidate = angularCandidate(
               sourceID: sourceID,
               angularAxis: radial.angularAxis,
               angleRadians: angleRadians,
               referencePoint: referencePoint,
               layout: layout
           ) {
            result.append(candidate)
        }
        if let radialAxis = radial.radialAxis,
           let baseProjectedPoint = index.sourceBaseProjectedPoint(source: source, layout: layout),
           let candidate = linearCandidate(
               sourceID: sourceID,
               slot: .radialAxis,
               axis: radialAxis,
               expressionResolver: expressionResolver,
               baseProjectedPoint: baseProjectedPoint,
               layout: layout
           ) {
            result.append(candidate)
        }
        return result
    }

    private func linearCandidate(
        sourceID: PatternArraySourceID,
        slot: ViewportPatternArrayCopyCountSlot,
        axis: PatternArrayLinearAxis,
        expressionResolver: PatternArrayExpressionResolver,
        baseProjectedPoint: CGPoint,
        layout: ViewportLayout
    ) -> ViewportPatternArrayCopyCountAffordanceCandidate? {
        guard let distanceMeters = resolvedLengthMeters(axis.distance, expressionResolver: expressionResolver) else {
            return nil
        }
        let geometry: ViewportPatternArrayCopyCountAffordanceGeometry
        switch axis.distanceMode {
        case .spacing:
            guard let spacingGeometry = ViewportPatternArrayCopyCountLinearGeometry(
                baseProjectedPoint: baseProjectedPoint,
                axisDirection: axis.direction,
                distanceMeters: distanceMeters,
                copyCount: axis.copyCount,
                layout: layout
            ) else {
                return nil
            }
            geometry = .linear(spacingGeometry)
        case .extent:
            guard let densityGeometry = ViewportPatternArrayCopyCountLinearDensityGeometry(
                baseProjectedPoint: baseProjectedPoint,
                axisDirection: axis.direction,
                extentDistanceMeters: distanceMeters,
                copyCount: axis.copyCount,
                layout: layout
            ) else {
                return nil
            }
            geometry = .linearDensity(densityGeometry)
        }
        let target = ViewportPatternArrayCopyCountHandleTarget(
            sourceID: sourceID,
            slot: slot,
            geometry: geometry
        )
        return ViewportPatternArrayCopyCountAffordanceCandidate(target: target, geometry: target.geometry)
    }

    private func angularCandidate(
        sourceID: PatternArraySourceID,
        angularAxis: PatternArrayAngularAxis,
        angleRadians: Double,
        referencePoint: Point3D,
        layout: ViewportLayout
    ) -> ViewportPatternArrayCopyCountAffordanceCandidate? {
        let geometry: ViewportPatternArrayCopyCountAffordanceGeometry
        switch angularAxis.angleMode {
        case .spacing:
            guard let spacingGeometry = ViewportPatternArrayCopyCountAngularGeometry(
                center: angularAxis.center,
                axis: angularAxis.axis,
                referencePoint: referencePoint,
                stepAngleRadians: angleRadians,
                copyCount: angularAxis.copyCount,
                layout: layout
            ) else {
                return nil
            }
            geometry = .angular(spacingGeometry)
        case .extent:
            guard let densityGeometry = ViewportPatternArrayCopyCountAngularDensityGeometry(
                center: angularAxis.center,
                axis: angularAxis.axis,
                referencePoint: referencePoint,
                extentAngleRadians: angleRadians,
                copyCount: angularAxis.copyCount,
                layout: layout
            ) else {
                return nil
            }
            geometry = .angularDensity(densityGeometry)
        }
        let target = ViewportPatternArrayCopyCountHandleTarget(
            sourceID: sourceID,
            slot: .radialAngular,
            geometry: geometry
        )
        return ViewportPatternArrayCopyCountAffordanceCandidate(target: target, geometry: target.geometry)
    }

    private func curveCandidate(
        sourceID: PatternArraySourceID,
        curve: CurvePatternArray,
        document: DesignDocument,
        layout: ViewportLayout
    ) -> ViewportPatternArrayCopyCountAffordanceCandidate? {
        do {
            let distributionGeometry = try PatternArrayCurvePathGeometryService().distributionGeometry(
                for: curve,
                parameters: document.cadDocument.parameters,
                cadDocument: document.cadDocument
            )
            guard let geometry = ViewportPatternArrayCopyCountCurveGeometry(
                path: distributionGeometry.path,
                distributionLength: distributionGeometry.distributionLength,
                copyCount: curve.copyCount,
                layout: layout
            ) else {
                return nil
            }
            let target = ViewportPatternArrayCopyCountHandleTarget(
                sourceID: sourceID,
                slot: .curve,
                geometry: .curve(geometry)
            )
            return ViewportPatternArrayCopyCountAffordanceCandidate(target: target, geometry: target.geometry)
        } catch {
            return nil
        }
    }

    private func resolvedLengthMeters(
        _ expression: CADExpression,
        expressionResolver: PatternArrayExpressionResolver
    ) -> Double? {
        do {
            let value = try expressionResolver.lengthMeters(for: expression)
            guard value.isFinite, value > 0.0 else {
                return nil
            }
            return value
        } catch {
            return nil
        }
    }

    private func resolvedAngleRadians(
        _ expression: CADExpression,
        expressionResolver: PatternArrayExpressionResolver
    ) -> Double? {
        do {
            let value = try expressionResolver.angleRadians(for: expression)
            guard value.isFinite else {
                return nil
            }
            return value
        } catch {
            return nil
        }
    }
}

struct ViewportPatternArrayCopyCountAffordanceCandidate: Equatable {
    var target: ViewportPatternArrayCopyCountHandleTarget
    var geometry: ViewportPatternArrayCopyCountAffordanceGeometry
}

struct ViewportPatternArrayCopyCountHandleTarget: Equatable {
    var sourceID: PatternArraySourceID
    var slot: ViewportPatternArrayCopyCountSlot
    var geometry: ViewportPatternArrayCopyCountAffordanceGeometry

    var identity: ViewportPatternArrayCopyCountHandleIdentity {
        ViewportPatternArrayCopyCountHandleIdentity(
            sourceID: sourceID,
            slot: slot
        )
    }

    var title: String {
        switch slot {
        case .rectangularFirst:
            "Axis 1 Count"
        case .rectangularSecond:
            "Axis 2 Count"
        case .radialAngular:
            "Radial Count"
        case .radialAxis:
            "Radius Count"
        case .curve:
            "Curve Count"
        }
    }
}

struct ViewportPatternArrayCopyCountHandleIdentity: Equatable {
    var sourceID: PatternArraySourceID
    var slot: ViewportPatternArrayCopyCountSlot
}
