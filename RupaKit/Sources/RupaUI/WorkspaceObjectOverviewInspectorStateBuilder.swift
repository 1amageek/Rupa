import Foundation
import RupaCore

struct WorkspaceObjectOverviewInspectorStateBuilder {
    var document: DesignDocument
    var objectRegistry: ObjectTypeRegistry
    var selectedTargetSummary: String
    var selectedTargetCount: Int

    func state(for nodes: [SceneNode]) -> WorkspaceObjectOverviewInspectorState {
        WorkspaceObjectOverviewInspectorState(
            selectionSection: selectionSection(for: nodes),
            referenceSection: referenceSection(for: nodes),
            hierarchySection: hierarchySection(for: nodes)
        )
    }

    private func selectionSection(for nodes: [SceneNode]) -> WorkspaceInspectorTextSection {
        let title = nodes.count == 1 ? "Selection" : "Selection Group"
        if nodes.count == 1, let node = nodes.first {
            return WorkspaceInspectorTextSection(
                title: title,
                rows: [
                    WorkspaceInspectorTextRow(title: "Name", value: node.name),
                    WorkspaceInspectorTextRow(title: "Object", value: objectTitle(for: node)),
                    WorkspaceInspectorTextRow(title: "Target", value: selectedTargetSummary),
                    WorkspaceInspectorTextRow(title: "Geometry", value: geometryTitle(for: node)),
                    WorkspaceInspectorTextRow(title: "Scene Node ID", value: shortID(node.id)),
                    WorkspaceInspectorTextRow(title: "Primary", value: "Yes"),
                ]
            )
        }
        return WorkspaceInspectorTextSection(
            title: title,
            rows: [
                WorkspaceInspectorTextRow(title: "Objects", value: "\(nodes.count)"),
                WorkspaceInspectorTextRow(title: "Targets", value: "\(selectedTargetCount)"),
                WorkspaceInspectorTextRow(title: "Primary", value: nodes.last?.name ?? "None"),
                WorkspaceInspectorTextRow(
                    title: "Object Types",
                    value: valueSummary(nodes.map { objectTitle(for: $0) })
                ),
                WorkspaceInspectorTextRow(
                    title: "Geometry",
                    value: valueSummary(nodes.map { geometryTitle(for: $0) })
                ),
                WorkspaceInspectorTextRow(
                    title: "Visible Objects",
                    value: "\(nodes.filter { $0.isVisible }.count)"
                ),
                WorkspaceInspectorTextRow(
                    title: "Locked Objects",
                    value: "\(nodes.filter { $0.isLocked }.count)"
                ),
            ]
        )
    }

    private func referenceSection(for nodes: [SceneNode]) -> WorkspaceInspectorTextSection {
        var rows: [WorkspaceInspectorTextRow] = []
        if nodes.count == 1, let node = nodes.first {
            if let object = node.object {
                rows += objectSourceRows(for: object)
            }
            rows.append(
                WorkspaceInspectorTextRow(
                    title: "Reference",
                    value: referenceTitle(for: node.reference)
                )
            )
            if let reference = node.reference {
                rows += referenceRows(for: reference)
            } else {
                rows.append(WorkspaceInspectorTextRow(title: "Role", value: "Group"))
            }
        } else {
            rows = [
                WorkspaceInspectorTextRow(title: "References", value: referenceSummary(for: nodes)),
                WorkspaceInspectorTextRow(
                    title: "Feature Links",
                    value: "\(nodes.compactMap { $0.reference?.featureID }.count)"
                ),
                WorkspaceInspectorTextRow(
                    title: "Component Links",
                    value: "\(nodes.compactMap { $0.reference?.componentInstanceID }.count)"
                ),
            ]
        }
        return WorkspaceInspectorTextSection(title: "Reference", rows: rows)
    }

    private func hierarchySection(for nodes: [SceneNode]) -> WorkspaceInspectorTextSection {
        if nodes.count == 1, let node = nodes.first {
            return WorkspaceInspectorTextSection(
                title: "Hierarchy",
                rows: [
                    WorkspaceInspectorTextRow(title: "Parent", value: parentTitle(for: node.id)),
                    WorkspaceInspectorTextRow(title: "Children", value: "\(node.childIDs.count)"),
                    WorkspaceInspectorTextRow(title: "Descendants", value: "\(descendantCount(for: node.id))"),
                ]
            )
        }
        return WorkspaceInspectorTextSection(
            title: "Hierarchy",
            rows: [
                WorkspaceInspectorTextRow(title: "Parents", value: parentSummary(for: nodes)),
                WorkspaceInspectorTextRow(
                    title: "Children",
                    value: "\(nodes.reduce(0) { $0 + $1.childIDs.count })"
                ),
                WorkspaceInspectorTextRow(
                    title: "Descendants",
                    value: "\(nodes.reduce(0) { $0 + descendantCount(for: $1.id) })"
                ),
            ]
        )
    }

    private func referenceRows(for reference: SceneNodeReference) -> [WorkspaceInspectorTextRow] {
        var rows: [WorkspaceInspectorTextRow] = []
        switch reference.kind {
        case .feature, .body, .sketch:
            if let featureID = reference.featureID {
                rows.append(WorkspaceInspectorTextRow(title: "Feature ID", value: shortID(featureID)))
                if let feature = document.cadDocument.designGraph.nodes[featureID] {
                    rows += featureRows(for: feature)
                } else {
                    rows.append(WorkspaceInspectorTextRow(title: "Feature", value: "Missing"))
                }
            }
        case .componentInstance:
            if let componentInstanceID = reference.componentInstanceID {
                rows.append(WorkspaceInspectorTextRow(title: "Instance ID", value: shortID(componentInstanceID)))
                if let instance = document.productMetadata.componentInstances[componentInstanceID] {
                    rows.append(WorkspaceInspectorTextRow(title: "Instance", value: instance.name))
                    rows.append(
                        WorkspaceInspectorTextRow(
                            title: "Definition",
                            value: componentDefinitionName(for: instance.definitionID)
                        )
                    )
                    rows.append(WorkspaceInspectorTextRow(title: "Properties", value: "\(instance.properties.count)"))
                } else {
                    rows.append(WorkspaceInspectorTextRow(title: "Instance", value: "Missing"))
                }
            }
        case .construction:
            rows.append(WorkspaceInspectorTextRow(title: "Role", value: "Construction"))
        }
        return rows
    }

    private func featureRows(for feature: FeatureNode) -> [WorkspaceInspectorTextRow] {
        var rows = [
            WorkspaceInspectorTextRow(
                title: "Feature Name",
                value: feature.name ?? "Unnamed Feature"
            )
        ]
        rows += operationRows(for: feature.operation)
        rows.append(
            WorkspaceInspectorTextRow(
                title: "Inputs",
                value: valueSummary(feature.inputs.map { $0.role.rawValue })
            )
        )
        rows.append(
            WorkspaceInspectorTextRow(
                title: "Outputs",
                value: valueSummary(feature.outputs.map { $0.role.rawValue })
            )
        )
        rows.append(
            WorkspaceInspectorTextRow(
                title: "Suppressed",
                value: feature.isSuppressed ? "Yes" : "No"
            )
        )
        return rows
    }

    private func operationRows(for operation: FeatureOperation) -> [WorkspaceInspectorTextRow] {
        switch operation {
        case .sketch:
            return [WorkspaceInspectorTextRow(title: "Operation", value: "Sketch")]
        case .extrude(let extrude):
            return [
                WorkspaceInspectorTextRow(title: "Operation", value: "Extrude"),
                WorkspaceInspectorTextRow(
                    title: "Profile Source",
                    value: shortID(extrude.profile.featureID)
                ),
            ]
        case .revolve(let revolve):
            return [
                WorkspaceInspectorTextRow(title: "Operation", value: "Revolve"),
                WorkspaceInspectorTextRow(
                    title: "Profile Source",
                    value: shortID(revolve.profile.featureID)
                ),
                WorkspaceInspectorTextRow(title: "Axis Origin", value: pointSummary(revolve.axis.origin)),
                WorkspaceInspectorTextRow(title: "Axis Direction", value: vectorSummary(revolve.axis.direction)),
            ]
        case .sweep(let sweep):
            var rows = [
                WorkspaceInspectorTextRow(title: "Operation", value: "Sweep"),
                WorkspaceInspectorTextRow(
                    title: "Sections",
                    value: valueSummary(sweep.sections.map(sweepSectionSummary))
                ),
                WorkspaceInspectorTextRow(title: "Path Source", value: shortID(sweep.path.featureID)),
            ]
            if sweep.guides.isEmpty == false {
                rows.append(
                    WorkspaceInspectorTextRow(
                        title: "Guides",
                        value: valueSummary(sweep.guides.map { shortID($0.featureID) })
                    )
                )
            }
            return rows
        case .loft(let loft):
            return [
                WorkspaceInspectorTextRow(title: "Operation", value: "Loft"),
                WorkspaceInspectorTextRow(
                    title: "Sections",
                    value: valueSummary(loft.sections.map(loftSectionSummary))
                ),
                WorkspaceInspectorTextRow(
                    title: "Result",
                    value: loft.options.resultKind.rawValue.capitalized
                ),
                WorkspaceInspectorTextRow(
                    title: "Matching",
                    value: loft.options.sectionMatching.rawValue.capitalized
                ),
            ]
        case .boolean(let boolean):
            return [
                WorkspaceInspectorTextRow(title: "Operation", value: "Boolean"),
                WorkspaceInspectorTextRow(
                    title: "Targets",
                    value: valueSummary(boolean.targets.map { shortID($0.featureID) })
                ),
                WorkspaceInspectorTextRow(title: "Tool", value: shortID(boolean.tool.featureID)),
                WorkspaceInspectorTextRow(
                    title: "Boolean Operation",
                    value: boolean.operation.rawValue.capitalized
                ),
                WorkspaceInspectorTextRow(
                    title: "Keep Tools",
                    value: boolean.keepTools ? "Yes" : "No"
                ),
            ]
        case .polySpline(let polySpline):
            return [
                WorkspaceInspectorTextRow(title: "Operation", value: "PolySpline"),
                WorkspaceInspectorTextRow(
                    title: "Mesh Vertices",
                    value: "\(polySpline.sourceMesh.positions.count)"
                ),
                WorkspaceInspectorTextRow(
                    title: "Mesh Triangles",
                    value: "\(polySpline.sourceMesh.indices.count / 3)"
                ),
            ]
        case .bSplineSurface(let surfaceFeature):
            return [
                WorkspaceInspectorTextRow(title: "Operation", value: "B-spline Surface"),
                WorkspaceInspectorTextRow(
                    title: "U Degree",
                    value: "\(surfaceFeature.surface.uDegree)"
                ),
                WorkspaceInspectorTextRow(
                    title: "V Degree",
                    value: "\(surfaceFeature.surface.vDegree)"
                ),
                WorkspaceInspectorTextRow(
                    title: "Control Points",
                    value: "\(surfaceFeature.surface.uControlPointCount) x \(surfaceFeature.surface.vControlPointCount)"
                ),
                WorkspaceInspectorTextRow(
                    title: "Rational",
                    value: surfaceFeature.surface.isRational ? "Yes" : "No"
                ),
            ]
        case .faceLoopOffset(let faceLoopOffset):
            return [
                WorkspaceInspectorTextRow(title: "Operation", value: "Offset Face Loop"),
                WorkspaceInspectorTextRow(title: "Target", value: shortID(faceLoopOffset.target.featureID)),
                WorkspaceInspectorTextRow(
                    title: "Gap Fill",
                    value: faceLoopOffset.gapFill.rawValue.capitalized
                ),
            ]
        case .edgeOffset(let edgeOffset):
            return [
                WorkspaceInspectorTextRow(title: "Operation", value: "Offset Edge"),
                WorkspaceInspectorTextRow(title: "Target", value: shortID(edgeOffset.target.featureID)),
                WorkspaceInspectorTextRow(
                    title: "Support Face",
                    value: "\(edgeOffset.supportFacePersistentName.components.count) components"
                ),
                WorkspaceInspectorTextRow(
                    title: "Gap Fill",
                    value: edgeOffset.gapFill.rawValue.capitalized
                ),
            ]
        case .faceKnife(let faceKnife):
            return [
                WorkspaceInspectorTextRow(title: "Operation", value: "Face Knife"),
                WorkspaceInspectorTextRow(title: "Target", value: shortID(faceKnife.target.featureID)),
                WorkspaceInspectorTextRow(title: "Loop Points", value: "\(faceKnife.loop.count)"),
            ]
        case .faceDelete(let faceDelete):
            return [
                WorkspaceInspectorTextRow(title: "Operation", value: "Delete Face"),
                WorkspaceInspectorTextRow(title: "Target", value: shortID(faceDelete.target.featureID)),
                WorkspaceInspectorTextRow(
                    title: "Faces",
                    value: "\(faceDelete.facePersistentNames.count)"
                ),
            ]
        case .faceDraft(let faceDraft):
            return [
                WorkspaceInspectorTextRow(title: "Operation", value: "Draft Face"),
                WorkspaceInspectorTextRow(title: "Target", value: shortID(faceDraft.target.featureID)),
                WorkspaceInspectorTextRow(
                    title: "Faces",
                    value: "\(faceDraft.facePersistentNames.count)"
                ),
                WorkspaceInspectorTextRow(
                    title: "Neutral Face",
                    value: "\(faceDraft.neutralFacePersistentName.components.count) components"
                ),
                WorkspaceInspectorTextRow(title: "Angle", value: String(describing: faceDraft.angle)),
            ]
        case .bridgeCurve(let bridgeCurve):
            return [
                WorkspaceInspectorTextRow(title: "Operation", value: "Bridge Curve"),
                WorkspaceInspectorTextRow(
                    title: "Start Continuity",
                    value: String(describing: bridgeCurve.start.requiredLevel).capitalized
                ),
                WorkspaceInspectorTextRow(
                    title: "End Continuity",
                    value: String(describing: bridgeCurve.end.requiredLevel).capitalized
                ),
                WorkspaceInspectorTextRow(title: "Samples", value: "\(bridgeCurve.sampleCount)"),
            ]
        case .curveEdit(let curveEdit):
            return [
                WorkspaceInspectorTextRow(title: "Operation", value: "Curve Edit"),
                WorkspaceInspectorTextRow(title: "Source", value: shortID(curveEdit.source.featureID)),
                WorkspaceInspectorTextRow(title: "Curve Index", value: "\(curveEdit.source.curveIndex)"),
                WorkspaceInspectorTextRow(title: "Edits", value: "\(curveEdit.edits.count)"),
            ]
        case .curveOffset(let curveOffset):
            return [
                WorkspaceInspectorTextRow(title: "Operation", value: "Curve Offset"),
                WorkspaceInspectorTextRow(title: "Source", value: shortID(curveOffset.source.featureID)),
                WorkspaceInspectorTextRow(title: "Curve Index", value: "\(curveOffset.source.curveIndex)"),
                WorkspaceInspectorTextRow(title: "Side", value: curveOffset.side.rawValue.capitalized),
                WorkspaceInspectorTextRow(title: "Samples", value: "\(curveOffset.sampleCount)"),
            ]
        case .curveTrim(let curveTrim):
            return [
                WorkspaceInspectorTextRow(title: "Operation", value: "Curve Trim"),
                WorkspaceInspectorTextRow(title: "Source", value: shortID(curveTrim.source.featureID)),
                WorkspaceInspectorTextRow(title: "Curve Index", value: "\(curveTrim.source.curveIndex)"),
                WorkspaceInspectorTextRow(title: "Samples", value: "\(curveTrim.sampleCount)"),
            ]
        }
    }

    private func objectSourceRows(for object: ObjectDescriptor) -> [WorkspaceInspectorTextRow] {
        var rows = [
            WorkspaceInspectorTextRow(title: "Object Role", value: object.category.title)
        ]
        if let geometryRole = object.geometryRole {
            rows.append(WorkspaceInspectorTextRow(title: "Geometry Role", value: geometryRole.title))
        }
        if let typeID = object.typeID {
            rows.append(WorkspaceInspectorTextRow(title: "Object Type ID", value: typeID.rawValue))
            if let definition = objectDefinition(for: typeID) {
                rows.append(WorkspaceInspectorTextRow(title: "Source", value: definition.sourceRepresentation.title))
                rows.append(
                    WorkspaceInspectorTextRow(
                        title: "Generated",
                        value: definition.generatedRepresentation(for: object.properties).title
                    )
                )
            }
            rows.append(WorkspaceInspectorTextRow(title: "Properties", value: "\(object.properties.values.count)"))
        }
        if let sourceFeatureID = object.sourceFeatureID {
            rows.append(WorkspaceInspectorTextRow(title: "Source Feature", value: shortID(sourceFeatureID)))
        }
        if let sourceSection = object.sourceSection {
            rows.append(
                WorkspaceInspectorTextRow(
                    title: "Source Section",
                    value: bodySourceSectionSummary(sourceSection)
                )
            )
        }
        if let componentInstanceID = object.componentInstanceID {
            rows.append(WorkspaceInspectorTextRow(title: "Component Instance", value: shortID(componentInstanceID)))
        }
        return rows
    }

    private func objectTitle(for node: SceneNode) -> String {
        if let definition = objectDefinition(for: node.object?.typeID) {
            return definition.title
        }
        if let category = node.object?.category {
            return category.title
        }
        return sceneNodeKindTitle(for: node.reference)
    }

    private func geometryTitle(for node: SceneNode) -> String {
        guard let object = node.object else {
            return "None"
        }
        if let definition = objectDefinition(for: object.typeID),
           let geometryRole = object.geometryRole {
            return "\(geometryRole.title) / \(definition.title)"
        }
        if let geometryRole = object.geometryRole {
            return geometryRole.title
        }
        return object.category.title
    }

    private func objectDefinition(for typeID: ObjectTypeID?) -> ObjectTypeDefinition? {
        objectRegistry.definition(for: typeID)
    }

    private func referenceTitle(for reference: SceneNodeReference?) -> String {
        guard let reference else {
            return "Group"
        }
        return sceneNodeKindTitle(for: reference)
    }

    private func referenceSummary(for nodes: [SceneNode]) -> String {
        valueSummary(nodes.map { referenceTitle(for: $0.reference) })
    }

    private func sceneNodeKindTitle(for reference: SceneNodeReference?) -> String {
        guard let reference else {
            return "Group"
        }
        switch reference.kind {
        case .feature:
            return "Feature"
        case .body:
            return "Body"
        case .sketch:
            return "Sketch"
        case .componentInstance:
            return "Component Instance"
        case .construction:
            return "Construction"
        }
    }

    private func parentTitle(for id: SceneNodeID) -> String {
        guard let parent = parentSceneNode(for: id) else {
            return "Root"
        }
        return parent.name
    }

    private func parentSummary(for nodes: [SceneNode]) -> String {
        valueSummary(nodes.map { parentTitle(for: $0.id) })
    }

    private func parentSceneNode(for id: SceneNodeID) -> SceneNode? {
        document.productMetadata.sceneNodes.values.first { node in
            node.childIDs.contains(id)
        }
    }

    private func descendantCount(for id: SceneNodeID) -> Int {
        guard let node = document.productMetadata.sceneNodes[id] else {
            return 0
        }
        return node.childIDs.reduce(node.childIDs.count) { count, childID in
            count + descendantCount(for: childID)
        }
    }

    private func componentDefinitionName(for id: ComponentDefinitionID) -> String {
        document.productMetadata.componentDefinitions[id]?.name ?? "Missing Definition"
    }

    private func sweepSectionSummary(_ section: SweepSectionReference) -> String {
        switch section {
        case .profile(let profile):
            return "Profile \(shortID(profile.featureID))"
        case .curve(let curve):
            return "Curve \(shortID(curve.featureID))"
        }
    }

    private func loftSectionSummary(_ section: LoftSectionReference) -> String {
        if let startSampleIndex = section.startSampleIndex {
            return "Profile \(shortID(section.featureID)) start \(startSampleIndex)"
        }
        return "Profile \(shortID(section.featureID))"
    }

    private func bodySourceSectionSummary(_ section: BodySourceSectionReference) -> String {
        switch section {
        case .profile(let profile):
            return "Profile \(shortID(profile.featureID))"
        case .curve(let featureID):
            return "Curve \(shortID(featureID))"
        }
    }

    private func pointSummary(_ point: Point3D) -> String {
        "x \(formatted(point.x)), y \(formatted(point.y)), z \(formatted(point.z))"
    }

    private func vectorSummary(_ vector: Vector3D) -> String {
        let x = vector.x.formatted(.number.precision(.fractionLength(0...3)))
        let y = vector.y.formatted(.number.precision(.fractionLength(0...3)))
        let z = vector.z.formatted(.number.precision(.fractionLength(0...3)))
        return "x \(x), y \(y), z \(z)"
    }

    private func formatted(_ meters: Double) -> String {
        let unit = document.displayUnit
        let value = unit.value(fromMeters: meters)
        return "\(value.formatted(.number.precision(.fractionLength(0...4)))) \(unit.symbol)"
    }

    private func valueSummary(_ values: [String]) -> String {
        var uniqueValues: [String] = []
        var seenValues: Set<String> = []
        for value in values {
            guard seenValues.insert(value).inserted else {
                continue
            }
            uniqueValues.append(value)
        }
        guard !uniqueValues.isEmpty else {
            return "None"
        }
        if uniqueValues.count == 1 {
            return uniqueValues[0]
        }
        let visibleValues = uniqueValues.prefix(3).joined(separator: ", ")
        if uniqueValues.count > 3 {
            return "\(visibleValues), +\(uniqueValues.count - 3)"
        }
        return visibleValues
    }

    private func shortID<T: CustomStringConvertible>(_ id: T) -> String {
        String(id.description.prefix(8))
    }
}
