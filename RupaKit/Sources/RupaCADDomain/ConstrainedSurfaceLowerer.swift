import RupaAutomation
import RupaCore
import RupaDomainFoundation

struct ConstrainedSurfaceLowerer: SemanticOperationLowerer {
    let replacing: Bool
    var operationID: DomainCapabilityID {
        replacing ? RupaCADSemanticOperationID.surfaceConstrainedReplace : RupaCADSemanticOperationID.surfaceConstrained
    }
    let operationVersion = RupaCADDomain.operationVersion
    let resultEstimate = CADSemanticLoweringSupport.resultEstimate

    static func registration(replacing: Bool) -> SemanticOperationRegistration {
        let lowerer = Self(replacing: replacing)
        return .init(descriptor: lowerer.descriptor, lowerer: lowerer)
    }

    var descriptor: SemanticOperationDescriptor {
        .init(operationID: operationID, version: operationVersion, inputs: [
            replacing ? .init(id: "body", type: .sourceBody(role: .sheet)) : .init(id: "name", type: .text),
            .init(id: "points", type: .array(element: .object)),
            .init(id: "tolerance", type: .number(unit: .meter)),
            .init(id: "angularTolerance", type: .number(unit: .degree)),
            .init(id: "optimization", type: .text),
        ], outputs: replacing ? [] : [
            .init(id: "body", type: .sourceBody(role: .sheet), selector: .sourceBody(role: .sheet, index: 0)),
            .init(id: "scene", type: .sceneNode, selector: .sceneNode(index: 0)),
        ], route: .source, effect: .sourceMutation,
            estimatedExpandedSourceWork: 1, resultEstimate: resultEstimate)
    }

    func lower(_ request: SemanticLoweringRequest) throws -> SemanticLoweredOperation {
        let target = replacing ? try CADSemanticLoweringSupport.preparedSlot("body", in: request) : nil
        let name = replacing ? nil : try CADSemanticLoweringSupport.text("name", in: request)
        let points = try CADSemanticLoweringSupport.array("points", in: request).enumerated().map { index, argument in
            let owner = "points[\(index)]"
            let fields = try CADSemanticLoweringSupport.object(argument, owner: owner)
            guard Set(fields.keys).isSubset(of: ["position"]) else {
                throw CADSemanticLoweringSupport.invalidArgument("\(owner) accepts position only.")
            }
            let point = try CADSemanticLoweringSupport.literalPoint("position", in: fields, owner: owner)
            return ConstrainedSurfaceFeature.PointConstraint(
                position: Point3D(x: point.x, y: point.y, z: point.z))
        }
        let mode = try CADSemanticLoweringSupport.text("optimization", in: request)
        guard let optimization = ConstrainedSurfaceFeature.Optimization(rawValue: mode) else {
            throw CADSemanticLoweringSupport.invalidArgument("Optimization must be performance or smoothness.")
        }
        let source = ConstrainedSurfaceFeature(points: points,
            positionTolerance: try CADSemanticLoweringSupport.number("tolerance", unit: .meter, in: request),
            angularTolerance: try CADSemanticLoweringSupport.number("angularTolerance", unit: .degree, in: request) * .pi / 180,
            optimization: optimization)
        try source.validate(tolerance: .standard)
        return SemanticLoweredOperation(step: PreparedAutomationStep(
            inputs: request.preparedInputs, outputs: request.preparedOutputs,
            estimatedGeneratedSourceWork: request.descriptor.estimatedExpandedSourceWork,
            commandBuilder: PreparedAutomationCommandBuilder(name: operationID.rawValue) { inputs in
                if let target {
                    let body = try inputs.sourceBody(for: target)
                    guard body.role == .sheet else {
                        throw CADSemanticLoweringSupport.invalidArgument("Constrained Surface replacement requires a sheet.")
                    }
                    return try ContextResolvedEditorCommand(validating: .setConstrainedSurface(featureID: body.featureID, source: source))
                }
                guard let name else { throw CADSemanticLoweringSupport.invalidArgument("Surface creation requires a name.") }
                return try ContextResolvedEditorCommand(validating: .createConstrainedSurface(name: name, source: source))
            }))
    }
}
