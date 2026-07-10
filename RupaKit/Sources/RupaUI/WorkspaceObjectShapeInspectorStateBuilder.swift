import RupaCore
import RupaRendering

struct WorkspaceObjectShapeInspectorStateBuilder {
    var document: DesignDocument
    var currentEvaluation: DocumentEvaluationContext?
    var documentGeneration: DocumentGeneration
    var objectRegistry: ObjectTypeRegistry
    var ruler: RulerConfiguration

    func shapes(for nodes: [SceneNode]) -> [InspectorObjectShape]? {
        let scene = ViewportSceneBuilder(objectRegistry: objectRegistry).build(
            document: document,
            ruler: ruler,
            currentEvaluation: currentEvaluation,
            documentGeneration: documentGeneration
        )
        let shapes = nodes.map { objectShape(for: $0, in: scene) }
        return shapes.allSatisfy({ $0 != nil }) ? shapes.compactMap { $0 } : nil
    }

    private func objectShape(
        for node: SceneNode,
        in scene: ViewportScene
    ) -> InspectorObjectShape? {
        guard let object = node.object,
              object.typeID != nil else {
            return nil
        }
        guard let featureID = node.reference?.featureID else {
            return nil
        }
        guard let item = scene.items.first(where: { $0.featureID == featureID }) else {
            return nil
        }
        let translation = WorkspaceTransformMatrix.translation(for: node)
        let sourceCenter: InspectorVector3D
        let size: InspectorVector3D
        let cylinder: InspectorCylinderShape?
        switch item.kind {
        case .body(let component):
            sourceCenter = InspectorVector3D(
                x: Double(item.modelBounds.midX),
                y: (component.yMinMeters + component.yMaxMeters) / 2.0,
                z: Double(item.modelBounds.midY)
            )
            size = InspectorVector3D(
                x: component.sizeXMeters,
                y: component.sizeYMeters,
                z: component.sizeZMeters
            )
            cylinder = component.cylinder.map { cylinder in
                InspectorCylinderShape(
                    topRadius: cylinder.topRadiusMeters,
                    bottomRadius: cylinder.bottomRadiusMeters,
                    sideSegments: cylinder.sideSegments,
                    verticalSegments: cylinder.verticalSegments,
                    angleDegrees: cylinder.angleDegrees,
                    hasCaps: cylinder.hasCaps,
                    hollow: cylinder.hollowMeters,
                    cornerRadius: cylinder.cornerRadiusMeters,
                    cornerSideSegments: cylinder.cornerSideSegments
                )
            }
        case .sketch:
            sourceCenter = InspectorVector3D(
                x: Double(item.modelBounds.midX),
                y: 0.0,
                z: Double(item.modelBounds.midY)
            )
            size = InspectorVector3D(
                x: Double(item.modelBounds.width),
                y: 0.0,
                z: Double(item.modelBounds.height)
            )
            cylinder = nil
        }
        return InspectorObjectShape(
            id: node.id,
            featureID: featureID,
            typeID: object.typeID,
            definition: objectRegistry.definition(for: object.typeID),
            properties: object.properties,
            sourceCenter: sourceCenter,
            center: InspectorVector3D(
                x: sourceCenter.x + translation.x,
                y: sourceCenter.y + translation.y,
                z: sourceCenter.z + translation.z
            ),
            size: size,
            cylinder: cylinder
        )
    }
}
