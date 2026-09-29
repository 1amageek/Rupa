import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    public func explicitModelingSectionReference(
        for featureID: FeatureID, sceneNodeID: SceneNodeID, selectedTargets: [SelectionTarget]
    ) throws -> SectionReference? {
        var sections: Set<SectionReference> = []
        for target in selectedTargets where target.sceneNodeID == sceneNodeID {
            switch target.component {
            case .region(let component):
                guard let region = component.profileRegionReference, region.featureID == featureID else {
                    throw EditorError(code: .commandInvalid, message: "Region selection does not belong to its source.")
                }
                sections.insert(.profile(ProfileReference(featureID: featureID, profileIndex: region.profileIndex)))
            case .sketchEntity(let component):
                guard let entity = component.sketchEntityReference, entity.featureID == featureID,
                      case .sketch(let sketch) = cadDocument.designGraph.nodes[featureID]?.operation,
                      sketch.entities[entity.entityID] != nil else {
                    throw EditorError(code: .commandInvalid, message: "Curve selection does not belong to its source.")
                }
                sections.insert(.curve(CurveSectionReference(featureID: featureID)))
            default: break
            }
        }
        guard sections.count <= 1 else {
            throw EditorError(code: .commandInvalid, message: "Select only one section from each source feature.")
        }
        if let section = sections.first { try section.validate() }
        return sections.first
    }

    public func modelingSectionReference(for featureID: FeatureID) throws -> SectionReference {
        guard let source = cadDocument.designGraph.nodes[featureID] else {
            throw EditorError(code: .referenceUnresolved, message: "Section source no longer exists.")
        }
        if source.outputs.contains(where: { $0.role == .profile }),
           case .sketch(let sketch) = source.operation {
            let parameters = try ParameterResolver().resolve(cadDocument.parameters)
            do {
                let profiles = try SketchProfileExtractor(tolerance: modelingSettings.tolerance)
                    .extractProfiles(from: sketch, sourceFeatureID: featureID, parameters: parameters)
                if !profiles.isEmpty { return .profile(ProfileReference(featureID: featureID)) }
            } catch SketchError.openProfile {
                // An open sketch is a curve section, not a failed closed-region extrusion.
            }
        }
        guard source.outputs.contains(where: { $0.role == .curve }) else {
            throw EditorError(code: .referenceUnresolved, message: "Source has no profile or curve section output.")
        }
        return .curve(CurveSectionReference(featureID: featureID))
    }

    @discardableResult
    public mutating func extrudeProfile(
        name: String,
        profile: ProfileReference,
        distance: CADExpression,
        direction: ExtrudeDirection,
        resultKind: ExtrudeResultKind = .solid,
        typeID: ObjectTypeID? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        try extrudeSection(name: name, section: .profile(profile), distance: distance,
            direction: direction, resultKind: resultKind, typeID: typeID, objectRegistry: objectRegistry)
    }

    @discardableResult
    public mutating func extrudeSection(
        name: String,
        section: SectionReference,
        distance: CADExpression,
        startDistance: CADExpression? = nil,
        direction: ExtrudeDirection,
        resultKind: ExtrudeResultKind,
        operation: SolidOperation = .newBody,
        targets: [BooleanTargetReference] = [],
        keepTools: Bool = false,
        typeID: ObjectTypeID? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let operation = ExtrudeFeature(section: section, distance: distance, startDistance: startDistance,
            direction: direction, operation: operation, targets: targets, keepTools: keepTools, resultKind: resultKind)
        try operation.validate()
        guard let source = cadDocument.designGraph.nodes[section.featureID],
              source.outputs.contains(where: { $0.role == section.inputRole }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Extrude section must reference an existing output of the selected kind."
            )
        }
        if section.isProfile, try containsSupportedExtrudeProfile(source) == false {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Extrude profile must reference a supported closed sketch profile."
            )
        }

        let featureID = FeatureID()
        let feature = FeatureNode(
            id: featureID,
            name: name,
            operation: .extrude(operation),
            inputs: [FeatureInput(featureID: section.featureID, role: section.inputRole)]
                + targets.map { FeatureInput(featureID: $0.featureID, role: .target) },
            outputs: [FeatureOutput(role: resultKind.featureOutputRole)]
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
                documentID: cadDocument.id,
                sourceSection: BodySourceSectionReference(section: section),
                typeID: typeID,
                geometryRole: resultKind.objectGeometryRole,
                objectRegistry: objectRegistry
            )
        )
        if section.isProfile {
            try synchronizeObjectPropertiesFromSource(
                featureID: featureID,
                objectRegistry: objectRegistry
            )
            try synchronizeCylinderCapsObjectProperty(
                featureID: featureID,
                resultKind: resultKind,
                objectRegistry: objectRegistry
            )
        }
        try cadDocument.validate(tolerance: modelingSettings.tolerance)
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommitExtrude = true
        return featureID
    }

    public mutating func setExtrusion(
        featureID: FeatureID, source: ExtrudeFeature,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard var feature = cadDocument.designGraph.nodes[featureID],
              case .extrude(let previous) = feature.operation,
              previous.section == source.section, previous.resultKind == source.resultKind else {
            throw EditorError(code: .commandInvalid,
                message: "Extrusion editing must retain the existing section and output kind.")
        }
        try source.validate()
        feature.operation = .extrude(source)
        feature.inputs = [FeatureInput(featureID: source.section.featureID, role: source.section.inputRole)]
            + source.targets.map { FeatureInput(featureID: $0.featureID, role: .target) }
        var candidate = self
        try candidate.cadDocument.replaceFeature(feature, tolerance: modelingSettings.tolerance)
        _ = try candidate.validate(objectRegistry: objectRegistry)
        self = candidate
    }

    @discardableResult
    public mutating func createRevolve(
        name: String,
        profile: ProfileReference,
        axis: RevolveAxis,
        angle: CADExpression = .constant(.angle(360.0, unit: .degree)),
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        try revolveSection(name: name, section: .profile(profile), axis: axis, angle: angle,
            resultKind: .solid, objectRegistry: objectRegistry)
    }

    @discardableResult
    public mutating func revolveSection(
        name: String, section: SectionReference, axis: RevolveAxis,
        angle: CADExpression, resultKind: BodyKind,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let trimmedName = try normalizedMetadataName(name, owner: "Revolve")
        let revolve = RevolveFeature(
            section: section,
            axis: axis,
            angle: angle,
            operation: .newBody,
            resultKind: resultKind
        )
        try revolve.validate(tolerance: modelingSettings.tolerance)
        guard let source = cadDocument.designGraph.nodes[section.featureID],
              source.outputs.contains(where: { $0.role == section.inputRole }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Revolve section must reference an output of the selected kind."
            )
        }
        if section.isProfile, try !containsSupportedExtrudeProfile(source) {
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
            inputs: [FeatureInput(featureID: section.featureID, role: section.inputRole)],
            outputs: [FeatureOutput(role: resultKind == .solid ? .body : .sheet)]
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
                documentID: cadDocument.id,
                sourceSection: BodySourceSectionReference(section: section),
                typeID: nil,
                geometryRole: resultKind == .solid ? .solid : .surface,
                objectRegistry: objectRegistry
            )
        )
        try cadDocument.validate(tolerance: modelingSettings.tolerance)
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommitRevolve = true
        return featureID
    }

    @discardableResult
    public mutating func createSweep(
        name: String,
        sections: [SectionReference],
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
                documentID: cadDocument.id,
                sourceSection: sections.first.map(BodySourceSectionReference.init(section:)),
                typeID: nil,
                geometryRole: options.resultKind.objectGeometryRole,
                objectRegistry: objectRegistry
            )
        )
        try cadDocument.validate(tolerance: modelingSettings.tolerance)
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
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
            switch section.section {
            case .profile:
                try requireLoftSourceProfileFeature(section.featureID, owner: "Loft profile")
            case .curve:
                try requireSweepSourceCurveFeature(section.featureID, owner: "Loft curve")
            }
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
                FeatureInput(featureID: section.featureID, role: section.section.inputRole)
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
                documentID: cadDocument.id,
                sourceSection: sections.first.map { BodySourceSectionReference(section: $0.section) },
                typeID: nil,
                geometryRole: options.resultKind.objectGeometryRole,
                objectRegistry: objectRegistry
            )
        )
        try cadDocument.validate(tolerance: modelingSettings.tolerance)
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommitLoft = true
        return featureID
    }

    public mutating func setLoft(
        featureID: FeatureID,
        loft: LoftFeature,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard let previous = cadDocument.designGraph.nodes[featureID],
              case .loft(let original) = previous.operation else {
            throw EditorError(code: .referenceUnresolved, message: "Loft source no longer exists.")
        }
        guard loft.options.resultKind == original.options.resultKind else {
            throw EditorError(code: .commandInvalid, message: "Loft editing must preserve its published Sheet or Solid output kind.")
        }
        var replacement = try FeatureNodeFactory.make(operation: .loft(loft), id: featureID,
            name: previous.name, in: cadDocument, tolerance: modelingSettings.tolerance)
        replacement.isSuppressed = previous.isSuppressed
        var candidate = self
        try candidate.cadDocument.replaceFeature(replacement, tolerance: modelingSettings.tolerance)
        for (id, var node) in candidate.productMetadata.sceneNodes where node.object?.sourceFeatureID == featureID {
            node.object?.sourceSection = loft.sections.first.map { BodySourceSectionReference(section: $0.section) }
            candidate.productMetadata.sceneNodes[id] = node
        }
        _ = try candidate.validate(objectRegistry: objectRegistry)
        self = candidate
    }

    /// Combines the target bodies with the tool bodies, solids or sheets, where they are
    /// displayed. The result lives in the first target's frame and is shown where that target is;
    /// every other operand is handed to the kernel with its rigid placement relative to it, and
    /// kept tools stay where they are. Placements are Core's to derive, so references must arrive
    /// without one. The materials say how each side's material is taken; the result is a sheet or
    /// a solid as Swift-CAD's `resultPort` says. A slice or a region shows each piece as an object of
    /// its own.
    @discardableResult
    public mutating func createBoolean(
        name: String,
        targets: [BooleanTargetReference],
        tools: [BooleanToolReference],
        operation: BooleanOperation,
        keepTools: Bool = false,
        targetMaterial: BooleanMaterial = .default,
        toolMaterial: BooleanMaterial = .default,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let trimmedName = try normalizedMetadataName(name, owner: "Boolean")
        guard targets.allSatisfy({ $0.placement == nil }), tools.allSatisfy({ $0.placement == nil }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Boolean operand placements come from where the bodies are displayed; references must not carry one."
            )
        }
        let previousCADDocument = cadDocument
        let previousProductMetadata = productMetadata
        var didCommitBoolean = false
        defer {
            if didCommitBoolean == false {
                cadDocument = previousCADDocument
                productMetadata = previousProductMetadata
            }
        }
        let boolean = try appendBooleanFeature(
            name: trimmedName,
            targets: targets.map(\.featureID),
            tools: tools.map(\.featureID),
            operation: operation,
            keepTools: keepTools,
            targetMaterial: targetMaterial,
            toolMaterial: toolMaterial
        )
        try publishBooleanResult(
            boolean,
            name: trimmedName,
            asPieces: operation == .slice || operation == .region,
            besideTarget: boolean.firstTarget,
            objectRegistry: objectRegistry
        )
        try cadDocument.validate(tolerance: modelingSettings.tolerance)
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        didCommitBoolean = true
        return boolean.featureID
    }

    /// A Boolean appended to the graph, not yet shown.
    struct AppendedBoolean {
        let featureID: FeatureID
        let resultPort: FeaturePort
        let firstTarget: FeatureID
    }

    /// Appends a Boolean of the bodies `targets` and `tools` where they are displayed, each
    /// operand placed relative to the first target, and shows nothing.
    mutating func appendBooleanFeature(
        name: String,
        targets: [FeatureID],
        tools: [FeatureID],
        operation: BooleanOperation,
        keepTools: Bool,
        targetMaterial: BooleanMaterial,
        toolMaterial: BooleanMaterial
    ) throws -> AppendedBoolean {
        let hierarchy = try SceneNodeHierarchy(metadata: productMetadata)
        func placement(of featureID: FeatureID) throws -> Transform3D {
            try hierarchy.presentingSceneNodeID(for: featureID).map { try hierarchy.worldTransform(of: $0) } ?? .identity
        }
        guard let first = targets.first else {
            throw EditorError(code: .commandInvalid, message: "Boolean requires at least one target body.")
        }
        let resultPlacement = try placement(of: first)
        func relativePlacement(of featureID: FeatureID, owner: String) throws -> RigidTransform3D? {
            let relative = try resultPlacement.inverse().composed(with: try placement(of: featureID))
            guard relative.isApproximatelyIdentity() == false else { return nil }
            do {
                return try relative.rigidPlacement()
            } catch {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) must be displayed at a rigid placement relative to the first target to be combined: \(error)."
                )
            }
        }
        let boolean = BooleanFeature(
            targets: try targets.map {
                BooleanTargetReference(featureID: $0, placement: try relativePlacement(of: $0, owner: "A Boolean target"))
            },
            tools: try tools.map {
                BooleanToolReference(featureID: $0, placement: try relativePlacement(of: $0, owner: "A Boolean tool"))
            },
            operation: operation,
            keepTools: keepTools,
            targetMaterial: targetMaterial,
            toolMaterial: toolMaterial
        )
        do {
            try boolean.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Boolean command is invalid: \(error)."
            )
        }
        let targetPorts = try targets.map { try bodyOrSheetPort(of: $0, owner: "Boolean target") }
        for tool in tools {
            _ = try bodyOrSheetPort(of: tool, owner: "Boolean tool")
        }
        let resultPort: FeaturePort
        do {
            resultPort = try boolean.resultPort(targetPorts: targetPorts)
        } catch {
            throw EditorError(code: .commandInvalid, message: "Boolean command is invalid: \(error).")
        }
        let featureID = FeatureID()
        try appendFeature(FeatureNode(
            id: featureID,
            name: name,
            operation: .boolean(boolean),
            inputs: targets.map { FeatureInput(featureID: $0, role: .target) }
                + tools.map { FeatureInput(featureID: $0, role: .body) },
            outputs: [FeatureOutput(role: resultPort)]
        ))
        return AppendedBoolean(featureID: featureID, resultPort: resultPort, firstTarget: first)
    }

    /// Shows an appended Boolean's result beside `target`'s object: as one object, or, as pieces,
    /// one Swift-CAD extraction and object per component of the evaluated result, the
    /// multi-component result itself shown by none.
    mutating func publishBooleanResult(
        _ boolean: AppendedBoolean,
        name: String,
        asPieces: Bool,
        besideTarget target: FeatureID,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let hierarchy = try SceneNodeHierarchy(metadata: productMetadata)
        let geometryRole: ObjectDescriptor.GeometryRole = boolean.resultPort == .sheet ? .surface : .solid
        let targetNodeID = hierarchy.presentingSceneNodeID(for: target)
        guard asPieces else {
            try insertBooleanResultNode(
                name: name, featureID: boolean.featureID, geometryRole: geometryRole,
                besideTargetNode: targetNodeID, hierarchy: hierarchy, objectRegistry: objectRegistry
            )
            return
        }
        let pieceCount = try bodyComponentCount(of: boolean.featureID, objectRegistry: objectRegistry, owner: name)
        for index in 0..<pieceCount {
            let pieceID = FeatureID()
            let pieceName = "\(name) \(index + 1)"
            try appendFeature(FeatureNode(
                id: pieceID,
                name: pieceName,
                operation: .extract(ExtractFeature(
                    target: PatternTargetReference(featureID: boolean.featureID),
                    selection: .component(index: index, count: pieceCount)
                )),
                inputs: [FeatureInput(featureID: boolean.featureID, role: .target)],
                outputs: [FeatureOutput(role: boolean.resultPort)]
            ))
            try insertBooleanResultNode(
                name: pieceName, featureID: pieceID, geometryRole: geometryRole,
                besideTargetNode: targetNodeID, hierarchy: try SceneNodeHierarchy(metadata: productMetadata),
                objectRegistry: objectRegistry
            )
        }
    }

    private func containsSupportedExtrudeProfile(_ source: FeatureNode) throws -> Bool {
        guard case .sketch(let sketch) = source.operation else {
            return false
        }
        let parameters = try ParameterResolver().resolve(cadDocument.parameters)
        let tolerance = modelingSettings.tolerance
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

    /// A Boolean result's object, inserted beside the first target with its local transform so it
    /// appears where the target was, or at the first root when the target is not shown.
    mutating func insertBooleanResultNode(
        name: String,
        featureID: FeatureID,
        geometryRole: ObjectDescriptor.GeometryRole,
        besideTargetNode targetNodeID: SceneNodeID?,
        hierarchy: SceneNodeHierarchy,
        isVisible: Bool = true,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let object = ObjectDescriptor.body(
            featureID: featureID,
            documentID: cadDocument.id,
            sourceSection: nil,
            typeID: nil,
            geometryRole: geometryRole,
            objectRegistry: objectRegistry
        )
        if let targetNodeID,
           let targetNode = productMetadata.sceneNodes[targetNodeID],
           let parentID = hierarchy.parentID(of: targetNodeID),
           let index = productMetadata.sceneNodes[parentID]?.childIDs.firstIndex(of: targetNodeID) {
            try productMetadata.insertSceneNode(
                SceneNode(
                    name: name, reference: .body(featureID), object: object,
                    isVisible: isVisible, localTransform: targetNode.localTransform
                ),
                under: parentID,
                at: index + 1
            )
        } else {
            let nodeID = try productMetadata.appendSceneNodeToFirstRoot(name: name, reference: .body(featureID), object: object)
            productMetadata.sceneNodes[nodeID]?.isVisible = isVisible
        }
    }

    /// How many components (solids with their voids, or sheet shells) the body `featureID`
    /// evaluates to now.
    func bodyComponentCount(of featureID: FeatureID, objectRegistry: ObjectTypeRegistry, owner: String) throws -> Int {
        let evaluated = try DocumentEvaluationContextResolver().evaluatedDocument(
            document: self,
            objectRegistry: objectRegistry,
            failurePrefix: "\(owner) requires its result evaluated"
        )
        guard case let .body(bodyID) = evaluated.subshapes[SubshapeID(featureID: featureID, role: GeneratedSubshapeRole.body.rawValue, ordinal: 0)],
              let body = evaluated.brep.bodies[bodyID] else {
            throw EditorError(code: .referenceUnresolved, message: "\(owner) result has no evaluated body.")
        }
        switch body.topology {
        case let .solid(components): return components.count
        case let .sheet(shellIDs): return shellIDs.count
        }
    }

    /// Whether a Boolean operand's source publishes a solid (`body`) or a sheet.
    func bodyOrSheetPort(of featureID: FeatureID, owner: String) throws -> FeaturePort {
        guard let port = cadDocument.designGraph.nodes[featureID]?.bodyOrSheetOutput else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) must reference an existing solid- or sheet-producing feature."
            )
        }
        return port
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
