import Foundation
import RupaCore

/// Editable text and explicit operands, never a mutable source document.
struct ModelingOperationDraft: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case box = "Box"
        case cylinder = "Cylinder"
        case sphere = "Sphere"
        case extrude = "Extrude"
        case revolve = "Revolve"
        case sweep = "Sweep"
        case loft = "Loft"
        case boolean = "Boolean"
        case fillet = "Fillet"
        case chamfer = "Chamfer"

        var id: String { rawValue }
    }

    var kind: Kind
    var name: String
    var targets: [SelectionTarget]
    var unit: LengthDisplayUnit
    var distance: String
    var width: String
    var height: String
    var origin = ["0", "0", "0"]
    var axis = ["0", "1", "0"]
    var angle = "360"
    var symmetric = false
    var keepTools = false
    var booleanOperation = BooleanOperation.difference
    var sheet = false
    var smooth = false
    var closesSectionLoop = false
    var filletSegments = "12"

    init(kind: Kind, selection: SelectionModel, unit: LengthDisplayUnit, stepMeters: Double) {
        self.kind = kind
        self.name = kind.rawValue
        self.targets = selection.selectedTargets
        self.unit = unit
        let initial = workspaceLengthFieldPresentation(fromMeters: stepMeters, preferredUnit: unit)
        let text = initial.text + " " + initial.unit.symbol
        self.distance = text
        self.width = text
        self.height = text
    }

    func command(in document: DesignDocument) throws -> EditorCommand {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalid("Enter an operation name.")
        }
        if kind == .box || kind == .cylinder || kind == .sphere {
            let x = try length(origin[0], label: "Origin X")
            let y = try length(origin[1], label: "Origin Y")
            let z = try length(origin[2], label: "Origin Z")
            if kind == .sphere {
                return .createAnalyticSphere(name: name, center: Point3D(x: x, y: y, z: z), radius: try positiveLength(width, label: "Radius"))
            }
            if kind == .cylinder {
                return .createExtrudedCircle(
                    name: name, plane: .plane(Plane3D(origin: Point3D(x: x, y: y, z: z), normal: .unitZ)),
                    center: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
                    radius: .length(try positiveLength(width, label: "Radius"), .meter),
                    depth: .length(try positiveLength(distance, label: "Depth"), .meter), direction: .normal
                )
            }
            let w = try positiveLength(width, label: "Width")
            let h = try positiveLength(height, label: "Height")
            return .createExtrudedRectangle(
                name: name,
                plane: .plane(Plane3D(origin: Point3D(x: x + w / 2, y: y + h / 2, z: z), normal: .unitZ)),
                width: .length(w, .meter), height: .length(h, .meter),
                depth: .length(try positiveLength(distance, label: "Depth"), .meter),
                direction: .normal
            )
        }

        let nodes = try operandNodes(in: document)
        let features = try nodes.map { node -> FeatureID in
            guard let featureID = node.object?.sourceFeatureID,
                  node.reference?.featureID == featureID,
                  document.cadDocument.designGraph.nodes[featureID] != nil else {
                throw invalid("Select CAD source geometry. Authored Mesh uses Mesh editing.")
            }
            return featureID
        }
        switch kind {
        case .box, .cylinder, .sphere:
            throw invalid("Primitive planning reached an invalid operand route.")
        case .extrude, .revolve:
            guard features.count == 1, let feature = features.first else {
                throw invalid("Select exactly one sketch profile.")
            }
            if kind == .extrude {
                return .extrudeProfile(
                    name: name, profile: ProfileReference(featureID: feature),
                    distance: .length(try positiveLength(distance, label: "Distance"), .meter),
                    direction: symmetric ? .symmetric : .normal
                )
            }
            let degrees = try number(angle, label: "Angle")
            guard degrees != 0, abs(degrees) <= 360 else {
                throw invalid("Revolve angle must be non-zero and within -360…360 degrees.")
            }
            let direction = Vector3D(
                x: try number(axis[0], label: "Axis X"),
                y: try number(axis[1], label: "Axis Y"),
                z: try number(axis[2], label: "Axis Z")
            )
            let revolveAxis = RevolveAxis(
                origin: Point3D(
                    x: try length(origin[0], label: "Axis origin X"),
                    y: try length(origin[1], label: "Axis origin Y"),
                    z: try length(origin[2], label: "Axis origin Z")
                ), direction: direction
            )
            try revolveAxis.validate(tolerance: document.modelingSettings.tolerance)
            return .createRevolve(name: name, profile: ProfileReference(featureID: feature), axis: revolveAxis, angle: .angle(degrees, .degree))
        case .sweep:
            return try SweepSelectionPlanningService(
                document: document, selection: SelectionModel(selectedTargets: targets)
            ).command(name: name)
        case .loft:
            guard features.count >= 2 else { throw invalid("Select at least two ordered sketch profiles.") }
            return .createLoft(
                name: name,
                sections: features.map { LoftSectionReference(profile: ProfileReference(featureID: $0)) },
                options: LoftOptions(resultKind: sheet ? .sheet : .solid, closesSectionLoop: closesSectionLoop, surfaceMode: smooth ? .smooth : .ruled)
            )
        case .boolean:
            guard features.count >= 2, let tool = features.last,
                  nodes.allSatisfy({ $0.reference?.kind == .body }) else {
                throw invalid("Select target CAD bodies, then a separate tool body last.")
            }
            return .createBoolean(name: name, targets: features.dropLast().map { BooleanTargetReference(featureID: $0) }, tool: BooleanToolReference(featureID: tool), operation: booleanOperation, keepTools: keepTools)
        case .fillet, .chamfer:
            let edges = WorkspaceSelectionTargetClassification(targets: targets).edgeTargets
            guard !edges.isEmpty, edges.count == targets.count else {
                throw invalid("Select CAD edges for this operation.")
            }
            let amount = try positiveLength(distance, label: kind == .fillet ? "Radius" : "Distance")
            if kind == .chamfer { return .chamferBodyEdges(targets: edges, distance: .length(amount, .meter)) }
            guard let segments = Int(filletSegments), segments >= 1 else {
                throw invalid("Fillet segments must be a positive integer.")
            }
            return .filletBodyEdges(targets: edges, radius: .length(amount, .meter), segmentCount: segments)
        }
    }

    func operandTitle(at index: Int, in document: DesignDocument) -> String {
        let name = document.productMetadata.sceneNodes[targets[index].sceneNodeID]?.name ?? "Missing source"
        let role: String
        switch kind {
        case .boolean: role = index == targets.count - 1 ? "Tool" : "Target"
        case .loft: role = "Section \(index + 1)"
        case .sweep: role = index == targets.count - 1 ? "Path" : "Section / guide"
        case .fillet, .chamfer: role = "Edge \(index + 1)"
        default: role = "Profile"
        }
        return "\(role): \(name)"
    }

    private func operandNodes(in document: DesignDocument) throws -> [SceneNode] {
        var seen = Set<SceneNodeID>()
        var nodes: [SceneNode] = []
        for target in targets where seen.insert(target.sceneNodeID).inserted {
            guard let node = document.productMetadata.sceneNodes[target.sceneNodeID], !node.isLocked else {
                throw invalid("An operand is missing or locked. Select an editable source.")
            }
            var ancestors: Set<SceneNodeID> = [node.id]
            var current = node
            while true {
                guard current.localTransform == .identity else {
                    throw invalid("\(node.name) has an occurrence transform. This operation requires source-frame CAD geometry; its placement cannot be ignored.")
                }
                guard let parent = document.productMetadata.sceneNodes.values.first(where: { $0.childIDs.contains(current.id) }) else { break }
                guard ancestors.insert(parent.id).inserted else { throw invalid("The scene hierarchy contains a cycle.") }
                current = parent
            }
            nodes.append(node)
        }
        return nodes
    }

    private func length(_ text: String, label: String) throws -> Double {
        guard let value = workspaceLengthMeters(fromFieldText: text, defaultUnit: unit), value.isFinite else {
            throw invalid("\(label) must be a finite length with valid units.")
        }
        return value
    }

    private func positiveLength(_ text: String, label: String) throws -> Double {
        let value = try length(text, label: label)
        guard value > 0 else { throw invalid("\(label) must be greater than zero.") }
        return value
    }

    private func number(_ text: String, label: String) throws -> Double {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else {
            throw invalid("\(label) must be a finite number.")
        }
        return value
    }

    private func invalid(_ message: String) -> EditorError {
        EditorError(code: .commandInvalid, message: message)
    }
}
