import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    @discardableResult
    public mutating func extrudeProfile(
        name: String,
        profile: ProfileReference,
        distance: CADExpression,
        direction: ExtrudeDirection,
        typeID: ObjectTypeID? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        try profile.validate()
        guard let source = cadDocument.designGraph.nodes[profile.featureID],
              source.outputs.contains(where: { $0.role == .profile }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Extrude profile must reference an existing sketch profile feature."
            )
        }
        guard try containsSupportedExtrudeProfile(source) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Extrude profile must reference a supported closed sketch profile."
            )
        }

        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: name,
            operation: .extrude(
                ExtrudeFeature(
                    profile: profile,
                    distance: distance,
                    direction: direction,
                    operation: .newBody
                )
            ),
            inputs: [FeatureInput(featureID: profile.featureID, role: .profile)],
            outputs: [FeatureOutput(role: .body)]
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitExtrude = false
        defer {
            if didCommitExtrude == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }

        try appendFeature(feature)
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: name,
            reference: .body(featureID),
            object: .body(
                featureID: featureID,
                sourceSection: .profile(profile),
                typeID: typeID,
                ruler: ruler,
                objectRegistry: objectRegistry
            )
        )
        try synchronizeObjectPropertiesFromSource(
            featureID: featureID,
            objectRegistry: objectRegistry
        )
        didCommitExtrude = true
        return featureID
    }

    @discardableResult
    public mutating func createRevolve(
        name: String,
        profile: ProfileReference,
        axis: RevolveAxis,
        angle: CADExpression = .constant(.angle(360.0, unit: .degree)),
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let trimmedName = try normalizedMetadataName(name, owner: "Revolve")
        let revolve = RevolveFeature(
            profile: profile,
            axis: axis,
            angle: angle,
            operation: .newBody
        )
        try revolve.validate()
        guard let source = cadDocument.designGraph.nodes[profile.featureID],
              source.outputs.contains(where: { $0.role == .profile }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Revolve profile must reference an existing sketch profile feature."
            )
        }
        guard try containsSupportedExtrudeProfile(source) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Revolve profile must reference a supported closed sketch profile."
            )
        }

        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: trimmedName,
            operation: .revolve(revolve),
            inputs: [FeatureInput(featureID: profile.featureID, role: .profile)],
            outputs: [FeatureOutput(role: .body)]
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitRevolve = false
        defer {
            if didCommitRevolve == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }

        try appendFeature(feature)
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: trimmedName,
            reference: .body(featureID),
            object: .body(
                featureID: featureID,
                sourceSection: .profile(profile),
                typeID: nil,
                ruler: ruler,
                objectRegistry: objectRegistry
            )
        )
        try cadDocument.validate()
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        do {
            _ = try CADPipeline
                .modelingDefault(for: self, objectRegistry: objectRegistry)
                .evaluate(cadDocument)
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Revolve produced unsupported or invalid geometry: \(error)."
            )
        }
        didCommitRevolve = true
        return featureID
    }

    @discardableResult
    public mutating func createSweep(
        name: String,
        sections: [SweepSectionReference],
        path: SweepPathReference,
        guides: [SweepGuideReference] = [],
        targets: [SweepTargetReference] = [],
        options: SweepOptions = SweepOptions(),
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let trimmedName = try normalizedMetadataName(name, owner: "Sweep")
        let sweep = SweepFeature(
            sections: sections,
            path: path,
            guides: guides,
            targets: targets,
            options: options
        )
        do {
            try sweep.validate()
            try validateSweepOptionQuantities(options)
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Sweep command is invalid: \(error)."
            )
        }
        for section in sections {
            switch section {
            case .profile(let profile):
                try requireSweepSourceProfileFeature(profile.featureID, owner: "Sweep profile")
            case .curve(let curve):
                try requireSweepSourceCurveFeature(curve.featureID, owner: "Sweep curve section")
            }
        }
        try requireSweepSourceCurveFeature(path.featureID, owner: "Sweep path")
        for guide in guides {
            try requireSweepSourceCurveFeature(guide.featureID, owner: "Sweep guide")
        }
        for target in targets {
            try requireSweepTargetBodyFeature(target.featureID, owner: "Sweep target")
        }

        let featureID = FeatureID()
        let inputs = sections.map { section in
            FeatureInput(featureID: section.featureID, role: section.inputRole)
        } + [
            FeatureInput(featureID: path.featureID, role: .path)
        ] + guides.map { guide in
            FeatureInput(featureID: guide.featureID, role: .guide)
        } + targets.map { target in
            FeatureInput(featureID: target.featureID, role: .target)
        }
        let feature = FeatureNode(
            id: featureID,
            name: trimmedName,
            operation: .sweep(sweep),
            inputs: inputs,
            outputs: [FeatureOutput(role: options.resultKind.featureOutputRole)]
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitSweep = false
        defer {
            if didCommitSweep == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }

        try appendFeature(feature)
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: trimmedName,
            reference: .body(featureID),
            object: .body(
                featureID: featureID,
                sourceSection: sections.first.map(BodySourceSectionReference.init(sweepSection:)),
                typeID: nil,
                geometryRole: options.resultKind.objectGeometryRole,
                ruler: ruler,
                objectRegistry: objectRegistry
            )
        )
        try cadDocument.validate()
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        do {
            _ = try CADPipeline
                .modelingDefault(for: self, objectRegistry: objectRegistry)
                .evaluate(cadDocument)
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Sweep produced unsupported or invalid geometry: \(error)."
            )
        }
        didCommitSweep = true
        return featureID
    }

    @discardableResult
    public mutating func createLoft(
        name: String,
        sections: [LoftSectionReference],
        guides: [LoftGuideReference] = [],
        options: LoftOptions = LoftOptions(),
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let trimmedName = try normalizedMetadataName(name, owner: "Loft")
        let loft = LoftFeature(sections: sections, guides: guides, options: options)
        do {
            try loft.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Loft command is invalid: \(error)."
            )
        }
        for section in sections {
            try requireLoftSourceProfileFeature(section.featureID, owner: "Loft profile")
        }
        for guide in guides {
            try requireSweepSourceCurveFeature(guide.featureID, owner: "Loft guide")
        }

        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: trimmedName,
            operation: .loft(loft),
            inputs: sections.map { section in
                FeatureInput(featureID: section.featureID, role: .profile)
            } + guides.map { guide in
                FeatureInput(featureID: guide.featureID, role: .guide)
            },
            outputs: [FeatureOutput(role: options.resultKind.featureOutputRole)]
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitLoft = false
        defer {
            if didCommitLoft == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }

        try appendFeature(feature)
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: trimmedName,
            reference: .body(featureID),
            object: .body(
                featureID: featureID,
                sourceSection: sections.first.map { .profile($0.profile) },
                typeID: nil,
                geometryRole: options.resultKind.objectGeometryRole,
                ruler: ruler,
                objectRegistry: objectRegistry
            )
        )
        try cadDocument.validate()
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        do {
            _ = try CADPipeline
                .modelingDefault(for: self, objectRegistry: objectRegistry)
                .evaluate(cadDocument)
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Loft produced unsupported or invalid geometry: \(error)."
            )
        }
        didCommitLoft = true
        return featureID
    }

    @discardableResult
    public mutating func createBoolean(
        name: String,
        targets: [BooleanTargetReference],
        tool: BooleanToolReference,
        operation: BooleanOperation,
        keepTools: Bool = false,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let trimmedName = try normalizedMetadataName(name, owner: "Boolean")
        let boolean = BooleanFeature(
            targets: targets,
            tool: tool,
            operation: operation,
            keepTools: keepTools
        )
        do {
            try boolean.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Boolean command is invalid: \(error)."
            )
        }
        for target in targets {
            try requireBodyFeature(target.featureID, owner: "Boolean target")
        }
        try requireBodyFeature(tool.featureID, owner: "Boolean tool")

        let featureID = FeatureID()
        let inputs = targets.map { target in
            FeatureInput(featureID: target.featureID, role: .target)
        } + [
            FeatureInput(featureID: tool.featureID, role: .body),
        ]
        let feature = FeatureNode(
            id: featureID,
            name: trimmedName,
            operation: .boolean(boolean),
            inputs: inputs,
            outputs: [FeatureOutput(role: .body)]
        )

        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitBoolean = false
        defer {
            if didCommitBoolean == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }

        try appendFeature(feature)
        _ = try productMetadata.appendSceneNodeToFirstRoot(
            name: trimmedName,
            reference: .body(featureID),
            object: .body(
                featureID: featureID,
                sourceSection: nil,
                typeID: nil,
                geometryRole: .solid,
                ruler: ruler,
                objectRegistry: objectRegistry
            )
        )
        try cadDocument.validate()
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        do {
            _ = try CADPipeline
                .modelingDefault(for: self, objectRegistry: objectRegistry)
                .evaluate(cadDocument)
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Boolean produced unsupported or invalid geometry: \(error)."
            )
        }
        didCommitBoolean = true
        return featureID
    }

    private func containsSupportedExtrudeProfile(_ source: FeatureNode) throws -> Bool {
        guard case .sketch(let sketch) = source.operation else {
            return false
        }
        let parameters = try ParameterResolver().resolve(cadDocument.parameters)
        let tolerance = ModelingTolerance.workspaceScaleAware(for: self)
        do {
            return try SketchProfileExtractor(tolerance: tolerance)
                .extractProfiles(
                    from: sketch,
                    sourceFeatureID: source.id,
                    parameters: parameters
                )
                .isEmpty == false
        } catch is SketchError {
            return false
        } catch is GeometryError {
            return false
        } catch is UnitError {
            return false
        }
    }

    private func requireSweepSourceProfileFeature(
        _ featureID: FeatureID,
        owner: String
    ) throws {
        guard let source = cadDocument.designGraph.nodes[featureID],
              source.outputs.contains(where: { $0.role == .profile }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) must reference an existing sketch profile or curve feature."
            )
        }
        guard try containsSupportedExtrudeProfile(source) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) must reference a supported closed sketch profile."
            )
        }
    }

    private func requireLoftSourceProfileFeature(
        _ featureID: FeatureID,
        owner: String
    ) throws {
        try requireSweepSourceProfileFeature(featureID, owner: owner)
    }

    private func requireSweepSourceCurveFeature(
        _ featureID: FeatureID,
        owner: String
    ) throws {
        guard let source = cadDocument.designGraph.nodes[featureID],
              source.outputs.contains(where: { $0.role == .curve }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) must reference an existing curve-producing feature."
            )
        }
    }

    private func requireBodyFeature(
        _ featureID: FeatureID,
        owner: String
    ) throws {
        guard let source = cadDocument.designGraph.nodes[featureID],
              source.outputs.contains(where: { $0.role == .body }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) must reference an existing body-producing feature."
            )
        }
    }

    private func requireSweepTargetBodyFeature(
        _ featureID: FeatureID,
        owner: String
    ) throws {
        try requireBodyFeature(featureID, owner: owner)
    }

    /// Nests the consumed profile sketch scene node under the body scene node
    /// and hides it, so combined primitives (box, cylinder) read as one object
    /// in the browser and viewport while the parametric sketch source remains
    /// selectable and editable through the body workflows.
    private mutating func nestConsumedProfileSketch(
        sketchFeatureID: FeatureID,
        bodyFeatureID: FeatureID
    ) throws {
        guard
            let sketchNodeID = productMetadata.sceneNodes.first(
                where: { $0.value.reference == .sketch(sketchFeatureID) }
            )?.key,
            let bodyNodeID = productMetadata.sceneNodes.first(
                where: { $0.value.reference == .body(bodyFeatureID) }
            )?.key
        else {
            throw DocumentValidationError.invalidProductMetadata(
                "Combined primitive creation expected sketch and body scene nodes."
            )
        }
        try productMetadata.nestSceneNode(sketchNodeID, under: bodyNodeID)
        productMetadata.sceneNodes[sketchNodeID]?.isVisible = false
    }

    public mutating func createExtrudedRectangle(
        name: String,
        plane: SketchPlane,
        width: CADExpression,
        height: CADExpression,
        depth: CADExpression,
        direction: ExtrudeDirection,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let sketchFeatureID = try createRectangleSketch(
            name: "\(name) Sketch",
            plane: plane,
            width: width,
            height: height,
            objectRegistry: objectRegistry
        )
        let bodyFeatureID = try extrudeProfile(
            name: name,
            profile: ProfileReference(featureID: sketchFeatureID),
            distance: depth,
            direction: direction,
            typeID: .cube,
            objectRegistry: objectRegistry
        )
        try nestConsumedProfileSketch(
            sketchFeatureID: sketchFeatureID,
            bodyFeatureID: bodyFeatureID
        )
        return bodyFeatureID
    }

    @discardableResult
    public mutating func createExtrudedRectangleFromCorners(
        name: String,
        plane: SketchPlane,
        firstCorner: SketchPoint,
        oppositeCorner: SketchPoint,
        depth: CADExpression,
        direction: ExtrudeDirection,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let sketchFeatureID = try createRectangleSketchFromCorners(
            name: "\(name) Sketch",
            plane: plane,
            firstCorner: firstCorner,
            oppositeCorner: oppositeCorner,
            objectRegistry: objectRegistry
        )
        let bodyFeatureID = try extrudeProfile(
            name: name,
            profile: ProfileReference(featureID: sketchFeatureID),
            distance: depth,
            direction: direction,
            typeID: .cube,
            objectRegistry: objectRegistry
        )
        try nestConsumedProfileSketch(
            sketchFeatureID: sketchFeatureID,
            bodyFeatureID: bodyFeatureID
        )
        return bodyFeatureID
    }

    @discardableResult
    public mutating func createExtrudedCircle(
        name: String,
        plane: SketchPlane,
        center: SketchPoint,
        radius: CADExpression,
        depth: CADExpression,
        direction: ExtrudeDirection,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let sketchFeatureID = try createCircleSketch(
            name: "\(name) Sketch",
            plane: plane,
            center: center,
            radius: radius,
            objectRegistry: objectRegistry
        )
        let bodyFeatureID = try extrudeProfile(
            name: name,
            profile: ProfileReference(featureID: sketchFeatureID),
            distance: depth,
            direction: direction,
            typeID: .cylinder,
            objectRegistry: objectRegistry
        )
        try nestConsumedProfileSketch(
            sketchFeatureID: sketchFeatureID,
            bodyFeatureID: bodyFeatureID
        )
        return bodyFeatureID
    }
}

private extension SweepResultKind {
    var featureOutputRole: FeaturePort {
        switch self {
        case .solid:
            .body
        case .sheet:
            .sheet
        }
    }

    var objectGeometryRole: ObjectDescriptor.GeometryRole {
        switch self {
        case .solid:
            .solid
        case .sheet:
            .surface
        }
    }
}

private extension LoftResultKind {
    var featureOutputRole: FeaturePort {
        switch self {
        case .solid:
            .body
        case .sheet:
            .sheet
        }
    }

    var objectGeometryRole: ObjectDescriptor.GeometryRole {
        switch self {
        case .solid:
            .solid
        case .sheet:
            .surface
        }
    }
}
