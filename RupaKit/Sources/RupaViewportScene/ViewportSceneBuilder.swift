import CoreGraphics
import RupaCore
import SwiftCAD

public struct ViewportSceneBuilder {
    private let objectRegistry: ObjectTypeRegistry

    public init(objectRegistry: ObjectTypeRegistry = .builtIn) {
        self.objectRegistry = objectRegistry
    }

    public func build(
        document: DesignDocument,
        currentEvaluation: DocumentEvaluationContext? = nil,
        documentGeneration: DocumentGeneration? = nil,
        evaluationCache: EvaluatedDocumentCache? = nil
    ) -> ViewportScene {
        let graph = document.cadDocument.designGraph
        let designDisplaySnapshot = DesignDisplaySnapshotService().snapshot(document: document)
        let bodyDisplaySnapshots: [FeatureID: BodyDisplaySnapshot]
        if let evaluatedDocument = currentEvaluatedDocument(
            for: document,
            currentEvaluation: currentEvaluation,
            documentGeneration: documentGeneration,
            evaluationCache: evaluationCache
        ) {
            bodyDisplaySnapshots = BodyDisplaySnapshotService().snapshots(
                evaluatedDocument: evaluatedDocument
            )
        } else {
            do {
                bodyDisplaySnapshots = try BodyDisplaySnapshotService().snapshots(
                    document: document,
                    objectRegistry: objectRegistry
                )
            } catch {
                bodyDisplaySnapshots = [:]
            }
        }

        let surfaceControlPointDisplaysByFeatureID = visibleSurfaceControlPointDisplaysByFeatureID(
            in: document
        )
        let surfaceTrimEndpointDisplaysByFeatureID = surfaceTrimEndpointDisplaysByFeatureID(
            in: document
        )
        let surfaceTrimControlPointDisplaysByFeatureID = surfaceTrimControlPointDisplaysByFeatureID(
            in: document
        )
        let surfaceFrameDisplaysByFeatureID = visibleSurfaceFrameDisplaysByFeatureID(
            in: document,
            currentEvaluation: currentEvaluation,
            currentGeneration: documentGeneration
        )
        let effectivelyVisibleSceneNodeIDs = effectivelyVisibleSceneNodeIDs(in: document.productMetadata)
        let baseItems = graph.order.compactMap { featureID -> ViewportSceneItem? in
            guard let feature = graph.nodes[featureID] else {
                return nil
            }

            switch feature.operation {
            case .sketch:
                guard let sketchSnapshot = designDisplaySnapshot.sketches[featureID] else {
                    return nil
                }
                let bounds = viewportBounds(sketchSnapshot.bounds)
                return ViewportSceneItem(
                    id: featureID.description,
                    featureID: featureID,
                    modelBounds: bounds,
                    kind: .sketch(
                        primitives: viewportSketchPrimitives(sketchSnapshot.primitives)
                    ),
                    sketchRegions: viewportSketchRegions(sketchSnapshot.regions)
                )
            case .extrude:
                guard let extrudeSnapshot = designDisplaySnapshot.extrudes[featureID],
                      let sketchSnapshot = designDisplaySnapshot.sketches[extrudeSnapshot.profileFeatureID] else {
                    return nil
                }
                let bounds = viewportBounds(sketchSnapshot.bounds)
                let object = objectDescriptor(
                    featureID: featureID,
                    kind: .body,
                    document: document
                )
                let component = bodyComponent(
                    sketchSnapshot: sketchSnapshot,
                    bounds: bounds,
                    depthMeters: extrudeSnapshot.depthMeters,
                    direction: extrudeSnapshot.direction,
                    declaredObjectTypeID: object?.typeID,
                    declaredProperties: object?.properties ?? ObjectPropertySet()
                )
                return ViewportSceneItem(
                    id: featureID.description,
                    featureID: featureID,
                    sourceFeatureID: extrudeSnapshot.profileFeatureID,
                    modelBounds: bounds,
                    kind: .body(component: component)
                )
            case .revolve(let revolve):
                return evaluatedMeshBodyItem(
                    featureID: featureID,
                    sourceFeatureID: revolve.profile.featureID,
                    document: document,
                    surfaceControlPointDisplaysByFeatureID: surfaceControlPointDisplaysByFeatureID,
                    surfaceTrimEndpointDisplaysByFeatureID: surfaceTrimEndpointDisplaysByFeatureID,
                    surfaceTrimControlPointDisplaysByFeatureID: surfaceTrimControlPointDisplaysByFeatureID,
                    surfaceFrameDisplaysByFeatureID: surfaceFrameDisplaysByFeatureID,
                    bodyDisplaySnapshots: bodyDisplaySnapshots
                )
            case .sweep(let sweep):
                guard let section = sweep.sections.first else {
                    return nil
                }
                if let sweepSnapshot = designDisplaySnapshot.straightPrismSweeps[featureID],
                   let sketchSnapshot = designDisplaySnapshot.sketches[sweepSnapshot.profileFeatureID] {
                    let bounds = viewportBounds(sketchSnapshot.bounds)
                    let object = objectDescriptor(
                        featureID: featureID,
                        kind: .body,
                        document: document
                    )
                    let component = bodyComponent(
                        sketchSnapshot: sketchSnapshot,
                        bounds: bounds,
                        depthMeters: sweepSnapshot.depthMeters,
                        direction: sweepSnapshot.direction,
                        declaredObjectTypeID: object?.typeID,
                        declaredProperties: object?.properties ?? ObjectPropertySet()
                    )
                    return ViewportSceneItem(
                        id: featureID.description,
                        featureID: featureID,
                        sourceFeatureID: sweepSnapshot.profileFeatureID,
                        modelBounds: bounds,
                        kind: .body(component: component)
                    )
                }

                return evaluatedMeshBodyItem(
                    featureID: featureID,
                    sourceFeatureID: section.featureID,
                    document: document,
                    surfaceControlPointDisplaysByFeatureID: surfaceControlPointDisplaysByFeatureID,
                    surfaceTrimEndpointDisplaysByFeatureID: surfaceTrimEndpointDisplaysByFeatureID,
                    surfaceTrimControlPointDisplaysByFeatureID: surfaceTrimControlPointDisplaysByFeatureID,
                    surfaceFrameDisplaysByFeatureID: surfaceFrameDisplaysByFeatureID,
                    bodyDisplaySnapshots: bodyDisplaySnapshots
                )
            case .polySpline:
                return evaluatedMeshBodyItem(
                    featureID: featureID,
                    sourceFeatureID: nil,
                    document: document,
                    surfaceControlPointDisplaysByFeatureID: surfaceControlPointDisplaysByFeatureID,
                    surfaceTrimEndpointDisplaysByFeatureID: surfaceTrimEndpointDisplaysByFeatureID,
                    surfaceTrimControlPointDisplaysByFeatureID: surfaceTrimControlPointDisplaysByFeatureID,
                    surfaceFrameDisplaysByFeatureID: surfaceFrameDisplaysByFeatureID,
                    bodyDisplaySnapshots: bodyDisplaySnapshots
                )
            case .bSplineSurface:
                return evaluatedMeshBodyItem(
                    featureID: featureID,
                    sourceFeatureID: nil,
                    document: document,
                    surfaceControlPointDisplaysByFeatureID: surfaceControlPointDisplaysByFeatureID,
                    surfaceTrimEndpointDisplaysByFeatureID: surfaceTrimEndpointDisplaysByFeatureID,
                    surfaceTrimControlPointDisplaysByFeatureID: surfaceTrimControlPointDisplaysByFeatureID,
                    surfaceFrameDisplaysByFeatureID: surfaceFrameDisplaysByFeatureID,
                    bodyDisplaySnapshots: bodyDisplaySnapshots
                )
            case .faceLoopOffset:
                return evaluatedMeshBodyItem(
                    featureID: featureID,
                    sourceFeatureID: objectDescriptor(
                        featureID: featureID,
                        kind: .body,
                        document: document
                    )?.sourceSection?.featureID,
                    document: document,
                    surfaceControlPointDisplaysByFeatureID: surfaceControlPointDisplaysByFeatureID,
                    surfaceTrimEndpointDisplaysByFeatureID: surfaceTrimEndpointDisplaysByFeatureID,
                    surfaceTrimControlPointDisplaysByFeatureID: surfaceTrimControlPointDisplaysByFeatureID,
                    surfaceFrameDisplaysByFeatureID: surfaceFrameDisplaysByFeatureID,
                    bodyDisplaySnapshots: bodyDisplaySnapshots
                )
            case .edgeOffset:
                return evaluatedMeshBodyItem(
                    featureID: featureID,
                    sourceFeatureID: objectDescriptor(
                        featureID: featureID,
                        kind: .body,
                        document: document
                    )?.sourceSection?.featureID,
                    document: document,
                    surfaceControlPointDisplaysByFeatureID: surfaceControlPointDisplaysByFeatureID,
                    surfaceTrimEndpointDisplaysByFeatureID: surfaceTrimEndpointDisplaysByFeatureID,
                    surfaceTrimControlPointDisplaysByFeatureID: surfaceTrimControlPointDisplaysByFeatureID,
                    surfaceFrameDisplaysByFeatureID: surfaceFrameDisplaysByFeatureID,
                    bodyDisplaySnapshots: bodyDisplaySnapshots
                )
            case .faceKnife:
                return evaluatedMeshBodyItem(
                    featureID: featureID,
                    sourceFeatureID: objectDescriptor(
                        featureID: featureID,
                        kind: .body,
                        document: document
                    )?.sourceSection?.featureID,
                    document: document,
                    surfaceControlPointDisplaysByFeatureID: surfaceControlPointDisplaysByFeatureID,
                    surfaceTrimEndpointDisplaysByFeatureID: surfaceTrimEndpointDisplaysByFeatureID,
                    surfaceTrimControlPointDisplaysByFeatureID: surfaceTrimControlPointDisplaysByFeatureID,
                    bodyDisplaySnapshots: bodyDisplaySnapshots
                )
            case .bridgeCurve:
                return nil
            case .curveEdit:
                return nil
            case .curveOffset:
                return nil
            case .curveTrim:
                return nil
            }
        }
        let resolvedBaseItems = baseItems.map { item in
            itemWithSceneNodeIdentity(item, in: document)
        }
        let sceneTransformIndex = ViewportSceneTransformIndex(metadata: document.productMetadata)
        let rootItems = resolvedBaseItems.compactMap { resolvedItem -> ViewportSceneItem? in
            guard let sceneNodeID = resolvedItem.sceneNodeID else {
                return resolvedItem
            }
            guard effectivelyVisibleSceneNodeIDs.contains(sceneNodeID) else {
                return nil
            }
            return transformedSceneTreeItem(
                resolvedItem,
                transform: sceneTransformIndex.transform(for: sceneNodeID)
            )
        }
        let baseItemsBySceneNodeID = Dictionary(
            uniqueKeysWithValues: resolvedBaseItems.compactMap { item -> (SceneNodeID, ViewportSceneItem)? in
                guard let sceneNodeID = item.sceneNodeID else {
                    return nil
                }
                return (sceneNodeID, item)
            }
        )
        let instanceItems = componentInstanceItems(
            document: document,
            baseItemsBySceneNodeID: baseItemsBySceneNodeID,
            sceneTransformIndex: sceneTransformIndex,
            effectivelyVisibleSceneNodeIDs: effectivelyVisibleSceneNodeIDs
        )
        return ViewportScene(items: rootItems + instanceItems)
    }

    private func effectivelyVisibleSceneNodeIDs(in metadata: ProductMetadata) -> Set<SceneNodeID> {
        var visibleIDs: Set<SceneNodeID> = []
        var visitedIDs: Set<SceneNodeID> = []
        for rootSceneNodeID in metadata.rootSceneNodeIDs {
            appendEffectivelyVisibleSceneNodeIDs(
                rootSceneNodeID,
                metadata: metadata,
                parentIsVisible: true,
                visibleIDs: &visibleIDs,
                visitedIDs: &visitedIDs
            )
        }
        return visibleIDs
    }

    private func appendEffectivelyVisibleSceneNodeIDs(
        _ sceneNodeID: SceneNodeID,
        metadata: ProductMetadata,
        parentIsVisible: Bool,
        visibleIDs: inout Set<SceneNodeID>,
        visitedIDs: inout Set<SceneNodeID>
    ) {
        guard visitedIDs.insert(sceneNodeID).inserted,
              let sceneNode = metadata.sceneNodes[sceneNodeID] else {
            return
        }
        let isVisible = parentIsVisible && sceneNode.isVisible
        if isVisible {
            visibleIDs.insert(sceneNodeID)
        }
        for childID in sceneNode.childIDs {
            appendEffectivelyVisibleSceneNodeIDs(
                childID,
                metadata: metadata,
                parentIsVisible: isVisible,
                visibleIDs: &visibleIDs,
                visitedIDs: &visitedIDs
            )
        }
    }

    private func itemWithSceneNodeIdentity(
        _ item: ViewportSceneItem,
        in document: DesignDocument
    ) -> ViewportSceneItem {
        var resolvedItem = item
        resolvedItem.sceneNodeID = sceneNodeID(
            featureID: item.featureID,
            kind: item.kind.selectableKind,
            in: document
        )
        return resolvedItem
    }

    private func sceneNodeID(
        featureID: FeatureID,
        kind: ViewportSelectableKind,
        in document: DesignDocument
    ) -> SceneNodeID? {
        let referenceKind: SceneNodeReference.Kind = switch kind {
        case .sketch:
            .sketch
        case .body:
            .body
        }
        if let matchedNode = document.productMetadata.sceneNodes.first(where: { _, node in
            node.reference?.kind == referenceKind && node.reference?.featureID == featureID
        }) {
            return matchedNode.key
        }
        return document.productMetadata.sceneNodes.first { _, node in
            node.reference?.featureID == featureID
        }?.key
    }

    private func componentInstanceItems(
        document: DesignDocument,
        baseItemsBySceneNodeID: [SceneNodeID: ViewportSceneItem],
        sceneTransformIndex: ViewportSceneTransformIndex,
        effectivelyVisibleSceneNodeIDs: Set<SceneNodeID>
    ) -> [ViewportSceneItem] {
        var items: [ViewportSceneItem] = []
        for (sceneNodeID, sceneNode) in document.productMetadata.sceneNodes {
            guard effectivelyVisibleSceneNodeIDs.contains(sceneNodeID),
                  let componentInstanceID = sceneNode.reference?.componentInstanceID,
                  let instance = document.productMetadata.componentInstances[componentInstanceID],
                  instance.isVisible,
                  let definition = document.productMetadata.componentDefinitions[instance.definitionID] else {
                continue
            }
            let instanceTransform = sceneTransformIndex
                .transform(for: sceneNodeID)
                .concatenating(instance.localTransform)
            for rootSceneNodeID in definition.rootSceneNodeIDs {
                appendComponentDefinitionItems(
                    sourceSceneNodeID: rootSceneNodeID,
                    instanceSceneNodeID: sceneNodeID,
                    componentInstanceID: componentInstanceID,
                    transform: instanceTransform,
                    document: document,
                    baseItemsBySceneNodeID: baseItemsBySceneNodeID,
                    visitedSceneNodeIDs: [],
                    visitedDefinitionIDs: [definition.id],
                    items: &items
                )
            }
        }
        return items.sorted { $0.id < $1.id }
    }

    private func appendComponentDefinitionItems(
        sourceSceneNodeID: SceneNodeID,
        instanceSceneNodeID: SceneNodeID,
        componentInstanceID: ComponentInstanceID,
        transform: Transform3D,
        document: DesignDocument,
        baseItemsBySceneNodeID: [SceneNodeID: ViewportSceneItem],
        visitedSceneNodeIDs: Set<SceneNodeID>,
        visitedDefinitionIDs: Set<ComponentDefinitionID>,
        items: inout [ViewportSceneItem]
    ) {
        guard !visitedSceneNodeIDs.contains(sourceSceneNodeID),
              let sourceNode = document.productMetadata.sceneNodes[sourceSceneNodeID],
              sourceNode.isVisible else {
            return
        }
        var nextVisitedSceneNodeIDs = visitedSceneNodeIDs
        nextVisitedSceneNodeIDs.insert(sourceSceneNodeID)
        let nodeTransform = transform.concatenating(sourceNode.localTransform)
        if let baseItem = baseItemsBySceneNodeID[sourceSceneNodeID] {
            items.append(
                transformedComponentInstanceItem(
                    baseItem,
                    sourceSceneNodeID: sourceSceneNodeID,
                    instanceSceneNodeID: instanceSceneNodeID,
                    componentInstanceID: componentInstanceID,
                    transform: nodeTransform
                )
            )
        }
        if sourceNode.reference?.kind == .componentInstance,
           let nestedComponentInstanceID = sourceNode.reference?.componentInstanceID,
           let nestedInstance = document.productMetadata.componentInstances[nestedComponentInstanceID],
           nestedInstance.isVisible,
           let nestedDefinition = document.productMetadata.componentDefinitions[nestedInstance.definitionID],
           !visitedDefinitionIDs.contains(nestedDefinition.id) {
            var nextVisitedDefinitionIDs = visitedDefinitionIDs
            nextVisitedDefinitionIDs.insert(nestedDefinition.id)
            let nestedTransform = nodeTransform.concatenating(nestedInstance.localTransform)
            for nestedRootSceneNodeID in nestedDefinition.rootSceneNodeIDs {
                appendComponentDefinitionItems(
                    sourceSceneNodeID: nestedRootSceneNodeID,
                    instanceSceneNodeID: instanceSceneNodeID,
                    componentInstanceID: componentInstanceID,
                    transform: nestedTransform,
                    document: document,
                    baseItemsBySceneNodeID: baseItemsBySceneNodeID,
                    visitedSceneNodeIDs: nextVisitedSceneNodeIDs,
                    visitedDefinitionIDs: nextVisitedDefinitionIDs,
                    items: &items
                )
            }
        }
        for childID in sourceNode.childIDs {
            appendComponentDefinitionItems(
                sourceSceneNodeID: childID,
                instanceSceneNodeID: instanceSceneNodeID,
                componentInstanceID: componentInstanceID,
                transform: nodeTransform,
                document: document,
                baseItemsBySceneNodeID: baseItemsBySceneNodeID,
                visitedSceneNodeIDs: nextVisitedSceneNodeIDs,
                visitedDefinitionIDs: visitedDefinitionIDs,
                items: &items
            )
        }
    }

    private func transformedComponentInstanceItem(
        _ baseItem: ViewportSceneItem,
        sourceSceneNodeID: SceneNodeID,
        instanceSceneNodeID: SceneNodeID,
        componentInstanceID: ComponentInstanceID,
        transform: Transform3D
    ) -> ViewportSceneItem {
        var item = transformedSceneTreeItem(baseItem, transform: transform)
        item.id = "\(instanceSceneNodeID.description):\(sourceSceneNodeID.description):\(baseItem.id)"
        item.sceneNodeID = instanceSceneNodeID
        item.componentInstanceID = componentInstanceID
        return item
    }

    private func transformedSceneTreeItem(
        _ baseItem: ViewportSceneItem,
        transform: Transform3D
    ) -> ViewportSceneItem {
        var item = baseItem
        item.modelTransform = .identity

        switch baseItem.kind {
        case .sketch(let primitives):
            item.kind = .sketch(
                primitives: primitives.map { primitive in
                    transformedSketchPrimitive(primitive, transform: transform)
                }
            )
            item.sketchRegions = baseItem.sketchRegions.map { region in
                ViewportSketchRegion(
                    componentID: region.componentID,
                    points: region.points.map { transformedSketchPoint($0, transform: transform) }
                )
            }
            item.modelBounds = transformedPlanarBounds(baseItem.modelBounds, transform: transform)
        case .body(let component):
            let transformedBody = transformedBodyComponent(
                component,
                modelBounds: baseItem.modelBounds,
                transform: transform
            )
            item.kind = .body(component: transformedBody.component)
            item.modelTransform = transform
            item.modelBounds = transformedBody.modelBounds
        }
        return item
    }

    private func transformedSketchPrimitive(
        _ primitive: ViewportSketchPrimitive,
        transform: Transform3D
    ) -> ViewportSketchPrimitive {
        switch primitive {
        case .point(let entityID, let point):
            return .point(entityID: entityID, point: transformedSketchPoint(point, transform: transform))
        case .line(let entityID, let start, let end):
            return .line(
                entityID: entityID,
                start: transformedSketchPoint(start, transform: transform),
                end: transformedSketchPoint(end, transform: transform)
            )
        case .circle(let entityID, let center, let radiusMeters):
            return .circle(
                entityID: entityID,
                center: transformedSketchPoint(center, transform: transform),
                radiusMeters: transformedSketchRadius(
                    center: center,
                    radiusMeters: radiusMeters,
                    transform: transform
                )
            )
        case .arc(let entityID, let center, let radiusMeters, let startAngleRadians, let endAngleRadians):
            let transformedArc = transformedSketchArc(
                center: center,
                radiusMeters: radiusMeters,
                startAngleRadians: startAngleRadians,
                endAngleRadians: endAngleRadians,
                transform: transform
            )
            return .arc(
                entityID: entityID,
                center: transformedArc.center,
                radiusMeters: transformedArc.radiusMeters,
                startAngleRadians: transformedArc.startAngleRadians,
                endAngleRadians: transformedArc.endAngleRadians
            )
        case .spline(let entityID, let points, let controlPoints, let sketchPlane):
            return .spline(
                entityID: entityID,
                points: points.map { transformedSketchPoint($0, transform: transform) },
                controlPoints: controlPoints.map { transformedSketchPoint($0, transform: transform) },
                sketchPlane: sketchPlane
            )
        }
    }

    private func transformedSketchPoint(
        _ point: CGPoint,
        transform: Transform3D
    ) -> CGPoint {
        let transformedPoint = transformedPoint(
            Point3D(x: Double(point.x), y: 0.0, z: Double(point.y)),
            transform: transform
        )
        return CGPoint(x: transformedPoint.x, y: transformedPoint.z)
    }

    private func transformedSketchRadius(
        center: CGPoint,
        radiusMeters: Double,
        transform: Transform3D
    ) -> Double {
        let radius = max(radiusMeters, 1.0e-12)
        let centerPoint = transformedSketchPoint(center, transform: transform)
        let xPoint = transformedSketchPoint(
            CGPoint(x: center.x + CGFloat(radius), y: center.y),
            transform: transform
        )
        let zPoint = transformedSketchPoint(
            CGPoint(x: center.x, y: center.y + CGFloat(radius)),
            transform: transform
        )
        let xScale = planarDistance(from: centerPoint, to: xPoint) / radius
        let zScale = planarDistance(from: centerPoint, to: zPoint) / radius
        let scale = (xScale + zScale) * 0.5
        guard scale.isFinite,
              scale > 1.0e-12 else {
            return radius
        }
        return radius * scale
    }

    private func transformedSketchArc(
        center: CGPoint,
        radiusMeters: Double,
        startAngleRadians: Double,
        endAngleRadians: Double,
        transform: Transform3D
    ) -> (center: CGPoint, radiusMeters: Double, startAngleRadians: Double, endAngleRadians: Double) {
        let radius = max(radiusMeters, 1.0e-12)
        let transformedCenter = transformedSketchPoint(center, transform: transform)
        let transformedStart = transformedSketchPoint(
            sketchArcPoint(center: center, radiusMeters: radius, angleRadians: startAngleRadians),
            transform: transform
        )
        let transformedEnd = transformedSketchPoint(
            sketchArcPoint(center: center, radiusMeters: radius, angleRadians: endAngleRadians),
            transform: transform
        )
        let startRadius = planarDistance(from: transformedCenter, to: transformedStart)
        let endRadius = planarDistance(from: transformedCenter, to: transformedEnd)
        let transformedRadius = max((startRadius + endRadius) * 0.5, 1.0e-12)
        return (
            transformedCenter,
            transformedRadius,
            sketchAngle(from: transformedCenter, to: transformedStart),
            sketchAngle(from: transformedCenter, to: transformedEnd)
        )
    }

    private func sketchArcPoint(
        center: CGPoint,
        radiusMeters: Double,
        angleRadians: Double
    ) -> CGPoint {
        CGPoint(
            x: center.x + CGFloat(cos(angleRadians) * radiusMeters),
            y: center.y + CGFloat(sin(angleRadians) * radiusMeters)
        )
    }

    private func sketchAngle(
        from center: CGPoint,
        to point: CGPoint
    ) -> Double {
        Double(atan2(point.y - center.y, point.x - center.x))
    }

    private func planarDistance(
        from start: CGPoint,
        to end: CGPoint
    ) -> Double {
        Double(hypot(end.x - start.x, end.y - start.y))
    }

    private func transformedBodyComponent(
        _ component: ViewportBodyComponent,
        modelBounds: CGRect,
        transform: Transform3D
    ) -> (component: ViewportBodyComponent, modelBounds: CGRect) {
        var resolvedComponent = component
        let bounds = transformedPointBounds(
            modelBounds: modelBounds,
            yMinMeters: component.yMinMeters,
            yMaxMeters: component.yMaxMeters,
            transform: transform
        )
        resolvedComponent.sizeXMeters = max(bounds.maxX - bounds.minX, 1.0e-9)
        resolvedComponent.sizeYMeters = max(bounds.maxY - bounds.minY, 1.0e-9)
        resolvedComponent.sizeZMeters = max(bounds.maxZ - bounds.minZ, 1.0e-9)
        resolvedComponent.yMinMeters = bounds.minY
        resolvedComponent.yMaxMeters = bounds.maxY
        return (
            resolvedComponent,
            CGRect(
                x: bounds.minX,
                y: bounds.minZ,
                width: max(bounds.maxX - bounds.minX, 1.0e-9),
                height: max(bounds.maxZ - bounds.minZ, 1.0e-9)
            )
        )
    }

    private func transformedPlanarBounds(
        _ bounds: CGRect,
        transform: Transform3D
    ) -> CGRect {
        let points = [
            CGPoint(x: bounds.minX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.maxY),
            CGPoint(x: bounds.minX, y: bounds.maxY),
        ].map { transformedSketchPoint($0, transform: transform) }
        return planarBounds(points)
    }

    private func planarBounds(_ points: [CGPoint]) -> CGRect {
        var bounds = CGRect.null
        for point in points {
            bounds = bounds.union(CGRect(x: point.x, y: point.y, width: 0.0, height: 0.0))
        }
        if bounds.isNull {
            return CGRect(x: 0.0, y: 0.0, width: 1.0e-9, height: 1.0e-9)
        }
        return CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: max(bounds.width, 1.0e-9),
            height: max(bounds.height, 1.0e-9)
        )
    }

    private func transformedBodyBoundsPoints(
        modelBounds: CGRect,
        yMinMeters: Double,
        yMaxMeters: Double,
        transform: Transform3D
    ) -> [Point3D] {
        let xValues = [Double(modelBounds.minX), Double(modelBounds.maxX)]
        let yValues = [yMinMeters, yMaxMeters]
        let zValues = [Double(modelBounds.minY), Double(modelBounds.maxY)]
        return xValues.flatMap { x in
            yValues.flatMap { y in
                zValues.map { z in
                    transformedPoint(Point3D(x: x, y: y, z: z), transform: transform)
                }
            }
        }
    }

    private func transformedPointBounds(
        modelBounds: CGRect,
        yMinMeters: Double,
        yMaxMeters: Double,
        transform: Transform3D
    ) -> (minX: Double, minY: Double, minZ: Double, maxX: Double, maxY: Double, maxZ: Double) {
        let points = transformedBodyBoundsPoints(
            modelBounds: modelBounds,
            yMinMeters: yMinMeters,
            yMaxMeters: yMaxMeters,
            transform: transform
        )
        return pointBounds(points) ?? (
            minX: Double(modelBounds.minX),
            minY: yMinMeters,
            minZ: Double(modelBounds.minY),
            maxX: Double(modelBounds.maxX),
            maxY: yMaxMeters,
            maxZ: Double(modelBounds.maxY)
        )
    }

    private func pointBounds(
        _ points: [Point3D]
    ) -> (minX: Double, minY: Double, minZ: Double, maxX: Double, maxY: Double, maxZ: Double)? {
        guard let first = points.first else {
            return nil
        }
        var bounds = (
            minX: first.x,
            minY: first.y,
            minZ: first.z,
            maxX: first.x,
            maxY: first.y,
            maxZ: first.z
        )
        for point in points.dropFirst() {
            bounds.minX = min(bounds.minX, point.x)
            bounds.minY = min(bounds.minY, point.y)
            bounds.minZ = min(bounds.minZ, point.z)
            bounds.maxX = max(bounds.maxX, point.x)
            bounds.maxY = max(bounds.maxY, point.y)
            bounds.maxZ = max(bounds.maxZ, point.z)
        }
        return bounds
    }

    private func transformedPoint(
        _ point: Point3D,
        transform: Transform3D
    ) -> Point3D {
        let values = transform.matrix.values
        guard values.count == 16 else {
            return point
        }
        let w = values[3] * point.x
            + values[7] * point.y
            + values[11] * point.z
            + values[15]
        let scale = abs(w) > 1.0e-12 ? 1.0 / w : 1.0
        return Point3D(
            x: (values[0] * point.x + values[4] * point.y + values[8] * point.z + values[12]) * scale,
            y: (values[1] * point.x + values[5] * point.y + values[9] * point.z + values[13]) * scale,
            z: (values[2] * point.x + values[6] * point.y + values[10] * point.z + values[14]) * scale
        )
    }

    private func visibleSurfaceControlPointDisplaysByFeatureID(
        in document: DesignDocument
    ) -> [FeatureID: [ViewportSurfaceControlPointDisplay]] {
        guard document.productMetadata.surfaceControlPointDisplays.values.contains(where: { $0.isVisible }) else {
            return [:]
        }
        let featureIDsByDescription = Dictionary(
            uniqueKeysWithValues: document.cadDocument.designGraph.order.map { featureID in
                (featureID.description, featureID)
            }
        )
        do {
            let summary = try SurfaceSourceSummaryService().summarize(document: document)
            var displaysByFeatureID: [FeatureID: [ViewportSurfaceControlPointDisplay]] = [:]
            for source in summary.sources {
                guard let featureID = featureIDsByDescription[source.featureID] else {
                    continue
                }
                var displays: [ViewportSurfaceControlPointDisplay] = []
                for patch in source.patches {
                    for controlPoint in patch.controlPoints where controlPoint.isPointDisplayVisible {
                        displays.append(ViewportSurfaceControlPointDisplay(
                            selectionReference: controlPoint.selectionReference,
                            point: Point3D(
                                x: controlPoint.point.x,
                                y: controlPoint.point.y,
                                z: controlPoint.point.z
                            ),
                            uIndex: controlPoint.uIndex,
                            vIndex: controlPoint.vIndex,
                            isBoundary: controlPoint.isBoundary
                        ))
                    }
                }
                if displays.isEmpty == false {
                    displaysByFeatureID[featureID, default: []].append(contentsOf: displays)
                }
            }
            return displaysByFeatureID
        } catch {
            return [:]
        }
    }

    private func surfaceTrimEndpointDisplaysByFeatureID(
        in document: DesignDocument
    ) -> [FeatureID: [ViewportSurfaceTrimEndpointDisplay]] {
        var displaysByFeatureID: [FeatureID: [ViewportSurfaceTrimEndpointDisplay]] = [:]
        for featureID in document.cadDocument.designGraph.order {
            guard let feature = document.cadDocument.designGraph.nodes[featureID],
                  case let .bSplineSurface(surfaceFeature) = feature.operation,
                  surfaceFeature.trimLoops.isEmpty == false else {
                continue
            }
            do {
                let surfaceReference = SurfaceReference(faceName: PersistentName(components: [
                    .feature(featureID),
                    .generated("bSplineSurface"),
                    .subshape("patch:0:face"),
                ]))
                var displays: [ViewportSurfaceTrimEndpointDisplay] = []
                for (loopIndex, trimLoop) in surfaceFeature.trimLoops.enumerated() {
                    for (edgeIndex, edge) in trimLoop.edges.enumerated() {
                        let selectionReference = SelectionReference.surface(.trim(SurfaceTrimReference(
                            surface: surfaceReference,
                            loopIndex: loopIndex,
                            edgeIndex: edgeIndex
                        )))
                        let start = try edge.startParameter()
                        let startGeometry = try surfaceFeature.surface.differentialGeometry(atU: start.u, v: start.v)
                        displays.append(ViewportSurfaceTrimEndpointDisplay(
                            selectionReference: selectionReference,
                            endpoint: .start,
                            point: startGeometry.position,
                            u: start.u,
                            v: start.v,
                            tangentU: startGeometry.tangentU,
                            tangentV: startGeometry.tangentV
                        ))
                        let end = try edge.endParameter()
                        let endGeometry = try surfaceFeature.surface.differentialGeometry(atU: end.u, v: end.v)
                        displays.append(ViewportSurfaceTrimEndpointDisplay(
                            selectionReference: selectionReference,
                            endpoint: .end,
                            point: endGeometry.position,
                            u: end.u,
                            v: end.v,
                            tangentU: endGeometry.tangentU,
                            tangentV: endGeometry.tangentV
                        ))
                    }
                }
                if displays.isEmpty == false {
                    displaysByFeatureID[featureID] = displays
                }
            } catch {
                continue
            }
        }
        return displaysByFeatureID
    }

    private func surfaceTrimControlPointDisplaysByFeatureID(
        in document: DesignDocument
    ) -> [FeatureID: [ViewportSurfaceTrimControlPointDisplay]] {
        var displaysByFeatureID: [FeatureID: [ViewportSurfaceTrimControlPointDisplay]] = [:]
        for featureID in document.cadDocument.designGraph.order {
            guard let feature = document.cadDocument.designGraph.nodes[featureID],
                  case let .bSplineSurface(surfaceFeature) = feature.operation,
                  surfaceFeature.trimLoops.isEmpty == false else {
                continue
            }
            do {
                let surfaceReference = SurfaceReference(faceName: PersistentName(components: [
                    .feature(featureID),
                    .generated("bSplineSurface"),
                    .subshape("patch:0:face"),
                ]))
                var displays: [ViewportSurfaceTrimControlPointDisplay] = []
                for (loopIndex, trimLoop) in surfaceFeature.trimLoops.enumerated() {
                    for (edgeIndex, edge) in trimLoop.edges.enumerated() {
                        let selectionReference = SelectionReference.surface(.trim(SurfaceTrimReference(
                            surface: surfaceReference,
                            loopIndex: loopIndex,
                            edgeIndex: edgeIndex
                        )))
                        for controlPoint in surfaceTrimControlPointParameters(edge.parameterCurve) {
                            let geometry = try surfaceFeature.surface.differentialGeometry(
                                atU: controlPoint.parameter.u,
                                v: controlPoint.parameter.v
                            )
                            displays.append(ViewportSurfaceTrimControlPointDisplay(
                                selectionReference: selectionReference,
                                controlPointIndex: controlPoint.index,
                                point: geometry.position,
                                u: controlPoint.parameter.u,
                                v: controlPoint.parameter.v,
                                tangentU: geometry.tangentU,
                                tangentV: geometry.tangentV
                            ))
                        }
                    }
                }
                if displays.isEmpty == false {
                    displaysByFeatureID[featureID] = displays
                }
            } catch {
                continue
            }
        }
        return displaysByFeatureID
    }

    private func surfaceTrimControlPointParameters(
        _ curve: SurfaceParameterCurve
    ) -> [(index: Int, parameter: SurfaceParameter)] {
        switch curve {
        case .constantU, .constantV:
            return []
        case let .polyline(points):
            guard points.count > 2 else {
                return []
            }
            return points.indices.dropFirst().dropLast().map { index in
                (index, points[index])
            }
        case let .bSpline(curve):
            guard curve.controlPoints.count > 2 else {
                return []
            }
            return curve.controlPoints.indices.dropFirst().dropLast().map { index in
                let point = curve.controlPoints[index]
                return (index, SurfaceParameter(u: point.x, v: point.y))
            }
        }
    }

    private func visibleSurfaceFrameDisplaysByFeatureID(
        in document: DesignDocument,
        currentEvaluation: DocumentEvaluationContext?,
        currentGeneration: DocumentGeneration?
    ) -> [FeatureID: [ViewportSurfaceFrameDisplay]] {
        let displays = document.productMetadata.surfaceFrameDisplays.values
            .filter(\.isVisible)
            .sorted { $0.id.rawValue < $1.id.rawValue }
        guard displays.isEmpty == false else {
            return [:]
        }
        do {
            let result = try SurfaceFrameService().resolve(
                document: document,
                queries: displays.map(\.query),
                currentEvaluation: currentEvaluation,
                currentGeneration: currentGeneration
            )
            let featureIDsByDescription = Dictionary(
                uniqueKeysWithValues: document.cadDocument.designGraph.order.map { featureID in
                    (featureID.description, featureID)
                }
            )
            var displaysByFeatureID: [FeatureID: [ViewportSurfaceFrameDisplay]] = [:]
            for (display, frame) in zip(displays, result.frames) {
                guard let sourceFeatureID = frame.sourceFeatureID,
                      let featureID = featureIDsByDescription[sourceFeatureID] else {
                    continue
                }
                displaysByFeatureID[featureID, default: []].append(
                    ViewportSurfaceFrameDisplay(
                        id: display.id,
                        query: display.query,
                        position: point3D(frame.position),
                        uAxis: vector3D(frame.uAxis),
                        vAxis: vector3D(frame.vAxis),
                        normal: vector3D(frame.normal),
                        u: frame.u,
                        v: frame.v,
                        facePersistentNames: frame.facePersistentNames
                    )
                )
            }
            return displaysByFeatureID
        } catch {
            return [:]
        }
    }

    private func point3D(_ point: SurfaceAnalysisResult.Point) -> Point3D {
        Point3D(x: point.x, y: point.y, z: point.z)
    }

    private func vector3D(_ vector: SurfaceAnalysisResult.Vector) -> Vector3D {
        Vector3D(x: vector.x, y: vector.y, z: vector.z)
    }

    private func currentEvaluatedDocument(
        for document: DesignDocument,
        currentEvaluation: DocumentEvaluationContext?,
        documentGeneration: DocumentGeneration?,
        evaluationCache: EvaluatedDocumentCache?
    ) -> EvaluatedDocument? {
        if let currentEvaluation {
            do {
                guard try currentEvaluation.matches(
                    document: document,
                    generation: documentGeneration
                ) else {
                    return nil
                }
            } catch {
                return nil
            }
            return currentEvaluation.evaluatedDocument
        }

        guard let documentGeneration,
              let evaluationCache else {
            return nil
        }
        do {
            guard try evaluationCache.matches(
                document: document,
                generation: documentGeneration
            ) else {
                return nil
            }
            return evaluationCache.evaluatedDocument
        } catch {
            return nil
        }
    }

    private func evaluatedMeshBodyItem(
        featureID: FeatureID,
        sourceFeatureID: FeatureID?,
        document: DesignDocument,
        surfaceControlPointDisplaysByFeatureID: [FeatureID: [ViewportSurfaceControlPointDisplay]] = [:],
        surfaceTrimEndpointDisplaysByFeatureID: [FeatureID: [ViewportSurfaceTrimEndpointDisplay]] = [:],
        surfaceTrimControlPointDisplaysByFeatureID: [FeatureID: [ViewportSurfaceTrimControlPointDisplay]] = [:],
        surfaceFrameDisplaysByFeatureID: [FeatureID: [ViewportSurfaceFrameDisplay]] = [:],
        bodyDisplaySnapshots: [FeatureID: BodyDisplaySnapshot]
    ) -> ViewportSceneItem? {
        guard let snapshot = bodyDisplaySnapshots[featureID] else {
            return nil
        }
        let object = objectDescriptor(
            featureID: featureID,
            kind: .body,
            document: document
        )
        let resolvedTypeID = object?.typeID ?? .cube
        let properties = resolvedProperties(
            typeID: resolvedTypeID,
            declaredProperties: object?.properties ?? ObjectPropertySet()
        )
        let component = ViewportBodyComponent(
            typeID: resolvedTypeID,
            properties: properties,
            sizeXMeters: max(snapshot.bounds.maxX - snapshot.bounds.minX, 1.0e-9),
            sizeYMeters: max(snapshot.bounds.maxY - snapshot.bounds.minY, 1.0e-9),
            sizeZMeters: max(snapshot.bounds.maxZ - snapshot.bounds.minZ, 1.0e-9),
            yMinMeters: snapshot.bounds.minY,
            yMaxMeters: snapshot.bounds.maxY,
            mesh: snapshot.mesh,
            topology: ViewportBodyTopology(snapshot.topology),
            surfaceControlPointDisplays: surfaceControlPointDisplaysByFeatureID[featureID] ?? [],
            surfaceTrimEndpointDisplays: surfaceTrimEndpointDisplaysByFeatureID[featureID] ?? [],
            surfaceTrimControlPointDisplays: surfaceTrimControlPointDisplaysByFeatureID[featureID] ?? [],
            surfaceFrameDisplays: surfaceFrameDisplaysByFeatureID[featureID] ?? []
        )
        return ViewportSceneItem(
            id: featureID.description,
            featureID: featureID,
            sourceFeatureID: sourceFeatureID,
            modelBounds: CGRect(
                x: snapshot.bounds.minX,
                y: snapshot.bounds.minZ,
                width: max(snapshot.bounds.maxX - snapshot.bounds.minX, 1.0e-9),
                height: max(snapshot.bounds.maxZ - snapshot.bounds.minZ, 1.0e-9)
            ),
            kind: .body(component: component)
        )
    }

    private func bodyComponent(
        sketchSnapshot: SketchDisplaySnapshot,
        bounds: CGRect,
        depthMeters: Double,
        direction: ExtrudeDirection,
        declaredObjectTypeID: ObjectTypeID?,
        declaredProperties: ObjectPropertySet
    ) -> ViewportBodyComponent {
        let sizeY = abs(depthMeters)
        let yExtents = bodyYExtents(depthMeters: depthMeters, direction: direction)
        let rawCylinder = sketchSnapshot.singleCircleProfileRadiusMeters.map { radius in
            ViewportCylinderComponent(
                topRadiusMeters: radius,
                bottomRadiusMeters: radius
            )
        }
        let resolvedTypeID = declaredObjectTypeID ?? (rawCylinder == nil ? .cube : .cylinder)
        let properties = resolvedProperties(
            typeID: resolvedTypeID,
            declaredProperties: declaredProperties
        )
        let cylinder = rawCylinder.map {
            cylinderComponent($0, properties: properties)
        }
        if let cylinder {
            return ViewportBodyComponent(
                typeID: resolvedTypeID,
                properties: properties,
                sizeXMeters: Double(bounds.width),
                sizeYMeters: sizeY,
                sizeZMeters: Double(bounds.height),
                yMinMeters: yExtents.min,
                yMaxMeters: yExtents.max,
                cylinder: cylinder
            )
        }
        return ViewportBodyComponent(
            typeID: resolvedTypeID,
            properties: properties,
            sizeXMeters: Double(bounds.width),
            sizeYMeters: sizeY,
            sizeZMeters: Double(bounds.height),
            yMinMeters: yExtents.min,
            yMaxMeters: yExtents.max
        )
    }

    private func resolvedProperties(
        typeID: ObjectTypeID?,
        declaredProperties: ObjectPropertySet
    ) -> ObjectPropertySet {
        guard let definition = objectRegistry.definition(for: typeID) else {
            return declaredProperties
        }
        var values = definition.defaultProperties.values
        for (propertyID, value) in declaredProperties.values {
            values[propertyID] = value
        }
        return ObjectPropertySet(values: values)
    }

    private func objectDescriptor(
        featureID: FeatureID,
        kind: SceneNodeReference.Kind,
        document: DesignDocument
    ) -> ObjectDescriptor? {
        document.productMetadata.sceneNodes.values.first { node in
            node.reference?.kind == kind && node.reference?.featureID == featureID
        }?.object
    }

    private func viewportBounds(_ bounds: SketchDisplaySnapshot.Bounds) -> CGRect {
        CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: max(bounds.width, 0.001),
            height: max(bounds.height, 0.001)
        )
    }

    private func viewportSketchPrimitives(
        _ primitives: [SketchDisplaySnapshot.Primitive]
    ) -> [ViewportSketchPrimitive] {
        primitives.map { primitive in
            switch primitive {
            case .point(let entityID, let point):
                return .point(entityID: entityID, point: viewportPoint(point))
            case .line(let entityID, let start, let end):
                return .line(
                    entityID: entityID,
                    start: viewportPoint(start),
                    end: viewportPoint(end)
                )
            case .circle(let entityID, let center, let radiusMeters):
                return .circle(
                    entityID: entityID,
                    center: viewportPoint(center),
                    radiusMeters: radiusMeters
                )
            case .arc(let entityID, let center, let radiusMeters, let startAngleRadians, let endAngleRadians):
                return .arc(
                    entityID: entityID,
                    center: viewportPoint(center),
                    radiusMeters: radiusMeters,
                    startAngleRadians: startAngleRadians,
                    endAngleRadians: endAngleRadians
                )
            case .spline(let entityID, let points, let controlPoints, let sketchPlane):
                return .spline(
                    entityID: entityID,
                    points: points.map(viewportPoint),
                    controlPoints: controlPoints.map(viewportPoint),
                    sketchPlane: sketchPlane
                )
            }
        }
    }

    private func viewportSketchRegions(
        _ regions: [SketchDisplaySnapshot.Region]
    ) -> [ViewportSketchRegion] {
        regions.map { region in
            ViewportSketchRegion(
                componentID: region.componentID,
                points: region.points.map(viewportPoint)
            )
        }
    }

    private func viewportPoint(_ point: Point2D) -> CGPoint {
        CGPoint(x: point.x, y: point.y)
    }

    private func bodyYExtents(
        depthMeters: Double,
        direction: ExtrudeDirection
    ) -> (min: Double, max: Double) {
        let size = abs(depthMeters)
        switch direction {
        case .symmetric:
            return (-size / 2.0, size / 2.0)
        case .normal, .vector(_):
            if depthMeters >= 0.0 {
                return (0.0, size)
            }
            return (-size, 0.0)
        }
    }

    private func cylinderComponent(
        _ component: ViewportCylinderComponent,
        properties: ObjectPropertySet
    ) -> ViewportCylinderComponent {
        let radius = lengthProperty("radius", properties: properties) ?? component.topRadiusMeters
        return ViewportCylinderComponent(
            topRadiusMeters: max(radius, 1.0e-9),
            bottomRadiusMeters: max(radius, 1.0e-9),
            sideSegments: max(integerProperty("sides.x", properties: properties) ?? component.sideSegments, 3),
            verticalSegments: max(integerProperty("sides.y", properties: properties) ?? component.verticalSegments, 1),
            angleDegrees: angleProperty("angle", properties: properties) ?? component.angleDegrees,
            hasCaps: booleanProperty("caps", properties: properties) ?? component.hasCaps,
            hollowMeters: max(lengthProperty("hollow", properties: properties) ?? component.hollowMeters, 0.0),
            cornerRadiusMeters: max(lengthProperty("corner.radius", properties: properties) ?? component.cornerRadiusMeters, 0.0),
            cornerSideSegments: max(integerProperty("corner.sides", properties: properties) ?? component.cornerSideSegments, 1)
        )
    }

    private func lengthProperty(
        _ id: ObjectPropertyID,
        properties: ObjectPropertySet
    ) -> Double? {
        guard case .length(let meters) = properties[id] else {
            return nil
        }
        return meters.isFinite ? meters : nil
    }

    private func integerProperty(
        _ id: ObjectPropertyID,
        properties: ObjectPropertySet
    ) -> Int? {
        guard case .integer(let value) = properties[id] else {
            return nil
        }
        return value
    }

    private func angleProperty(
        _ id: ObjectPropertyID,
        properties: ObjectPropertySet
    ) -> Double? {
        guard case .angle(let value) = properties[id] else {
            return nil
        }
        return value.isFinite ? value : nil
    }

    private func booleanProperty(
        _ id: ObjectPropertyID,
        properties: ObjectPropertySet
    ) -> Bool? {
        guard case .boolean(let value) = properties[id] else {
            return nil
        }
        return value
    }

}

func viewportSceneProjectedArcPoints(
    center: CGPoint,
    radiusMeters: Double,
    startAngleRadians: Double,
    endAngleRadians: Double,
    layout: ViewportLayout,
    segmentCount: Int
) -> [CGPoint] {
    viewportSceneArcSamplePoints(
        center: center,
        radiusMeters: radiusMeters,
        startAngleRadians: startAngleRadians,
        endAngleRadians: endAngleRadians,
        segmentCount: segmentCount
    ).map { layout.project($0) }
}

func viewportSceneArcSamplePoints(
    center: CGPoint,
    radiusMeters: Double,
    startAngleRadians: Double,
    endAngleRadians: Double,
    segmentCount: Int
) -> [CGPoint] {
    let radius = max(CGFloat(radiusMeters), 1.0e-12)
    let span = viewportSceneNormalizedArcSpan(startAngle: startAngleRadians, endAngle: endAngleRadians)
    let count = max(segmentCount, 2)
    return (0 ... count).map { index in
        let ratio = Double(index) / Double(count)
        let angle = startAngleRadians + span * ratio
        return CGPoint(
            x: center.x + cos(CGFloat(angle)) * radius,
            y: center.y + sin(CGFloat(angle)) * radius
        )
    }
}

func viewportSceneArcBoundsPoints(
    center: CGPoint,
    radiusMeters: Double,
    startAngleRadians: Double,
    endAngleRadians: Double
) -> [CGPoint] {
    let radius = max(CGFloat(radiusMeters), 1.0e-12)
    let span = viewportSceneNormalizedArcSpan(startAngle: startAngleRadians, endAngle: endAngleRadians)
    let angles = viewportSceneArcBoundsAngles(startAngle: startAngleRadians, span: span)
    return angles.map { angle in
        CGPoint(
            x: center.x + cos(CGFloat(angle)) * radius,
            y: center.y + sin(CGFloat(angle)) * radius
        )
    }
}

func viewportSceneArcBoundsAngles(startAngle: Double, span: Double) -> [Double] {
    let fullCircle = Double.pi * 2.0
    let tolerance = 1.0e-12
    var angles = [startAngle, startAngle + span]
    for baseAngle in [0.0, Double.pi / 2.0, Double.pi, Double.pi * 1.5, fullCircle] {
        var angle = baseAngle
        while angle < startAngle - tolerance {
            angle += fullCircle
        }
        if angle <= startAngle + span + tolerance {
            angles.append(angle)
        }
    }
    return angles
}

func viewportSceneNormalizedArcSpan(startAngle: Double, endAngle: Double) -> Double {
    let fullCircle = Double.pi * 2.0
    let tolerance = 1.0e-12
    var span = endAngle - startAngle
    while span <= tolerance {
        span += fullCircle
    }
    while span > fullCircle + tolerance {
        span -= fullCircle
    }
    return min(span, fullCircle)
}

func viewportSceneCubicBezierSamplePoints(
    controlPoints: [Point2D],
    segmentCount: Int
) -> [CGPoint] {
    guard controlPoints.count == 4 else {
        return []
    }
    let count = max(segmentCount, 2)
    return (0 ... count).map { index in
        let t = Double(index) / Double(count)
        let inverse = 1.0 - t
        let first = inverse * inverse * inverse
        let second = 3.0 * inverse * inverse * t
        let third = 3.0 * inverse * t * t
        let fourth = t * t * t
        return CGPoint(
            x: CGFloat(controlPoints[0].x * first
                + controlPoints[1].x * second
                + controlPoints[2].x * third
                + controlPoints[3].x * fourth),
            y: CGFloat(controlPoints[0].y * first
                + controlPoints[1].y * second
                + controlPoints[2].y * third
                + controlPoints[3].y * fourth)
        )
    }
}
