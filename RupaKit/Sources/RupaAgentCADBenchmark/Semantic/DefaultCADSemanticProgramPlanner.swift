import Foundation
import RupaAgentProtocol
import RupaCADDomain
import RupaCore
import RupaDomainFoundation

/// Lowers one typed candidate intent into the benchmark's portable semantic
/// program. The public challenge fixes declared sketch planes and compound
/// structure; submitted geometry, dimensions, and transforms come from the action.
struct DefaultCADSemanticProgramPlanner: CADSemanticProgramPlanning {
    func plan(
        for entry: CADCatalogEntry,
        action: CADCandidateAction
    ) throws -> CADSemanticProgramPlan {
        switch (entry.input, action) {
        case (.line, .automation(.sketch(.line(let name, let plane, let start, let end)))):
            try validateName(name, caseID: entry.challenge.id)
            let projection = try CADLineChallengeProjection.decode(entry.challenge)
            let frame = try validatedPlane(
                orientation: plane,
                expectedOrientation: projection.orientation,
                origin: projection.anchor,
                points: [("line.start", start), ("line.end", end)],
                caseID: entry.challenge.id
            )
            try validateLine(start, end, field: "line", caseID: entry.challenge.id)
            return linePlan(name: name, plane: frame, start: start, end: end)
        case (.rectangle, .automation(.sketch(.rectangle(let name, let plane, let center, let width, let height)))):
            try validateName(name, caseID: entry.challenge.id)
            try validateLength(width, field: "rectangle.width", caseID: entry.challenge.id)
            try validateLength(height, field: "rectangle.height", caseID: entry.challenge.id)
            let projection = try CADRectangleChallengeProjection.decode(entry.challenge)
            let frame = try validatedPlane(
                orientation: plane,
                expectedOrientation: projection.orientation,
                origin: projection.center,
                points: [("rectangle.center", center)],
                caseID: entry.challenge.id
            )
            return rectanglePlan(
                name: name,
                plane: frame,
                center: center,
                width: width,
                height: height
            )
        case (.circle, .automation(.sketch(.circle(let name, let plane, let center, let radius)))):
            try validateName(name, caseID: entry.challenge.id)
            try validateLength(radius, field: "circle.radius", caseID: entry.challenge.id)
            let projection = try CADCircleChallengeProjection.decode(entry.challenge)
            let frame = try validatedPlane(
                orientation: plane,
                expectedOrientation: projection.orientation,
                origin: projection.center,
                points: [("circle.center", center)],
                caseID: entry.challenge.id
            )
            return circlePlan(
                name: name,
                plane: frame,
                center: center,
                radius: radius
            )
        case (.angle, .automation(.sketch(.angle(
            let name,
            let plane,
            let firstStart,
            let firstEnd,
            let secondStart,
            let secondEnd
        )))):
            try validateName(name, caseID: entry.challenge.id)
            let projection = try CADAngleChallengeProjection.decode(entry.challenge)
            let frame = try validatedPlane(
                orientation: plane,
                expectedOrientation: projection.orientation,
                origin: projection.intersection,
                points: [
                    ("angle.firstStart", firstStart),
                    ("angle.firstEnd", firstEnd),
                    ("angle.secondStart", secondStart),
                    ("angle.secondEnd", secondEnd),
                ],
                caseID: entry.challenge.id
            )
            try validateLine(firstStart, firstEnd, field: "angle.first", caseID: entry.challenge.id)
            try validateLine(secondStart, secondEnd, field: "angle.second", caseID: entry.challenge.id)
            return anglePlan(
                name: name,
                plane: frame,
                firstStart: firstStart,
                firstEnd: firstEnd,
                secondStart: secondStart,
                secondEnd: secondEnd
            )
        case (.constraint, .automation(.sketch(.constraint(let action)))):
            guard !action.name.isEmpty else {
                throw invalid(entry, "A constraint action must have a non-empty name.")
            }
            let projection = try CADConstraintChallengeProjection.decode(entry.challenge)
            try validateConstraintGeometry(
                action.first,
                field: "constraint.first",
                caseID: entry.challenge.id
            )
            if let second = action.second {
                try validateConstraintGeometry(
                    second,
                    field: "constraint.second",
                    caseID: entry.challenge.id
                )
            }
            let frame = try validatedPlane(
                orientation: action.plane,
                expectedOrientation: projection.plane,
                origin: anchor(projection.first),
                points: geometryPoints(action.first, field: "constraint.first")
                    + (action.second.map { geometryPoints($0, field: "constraint.second") } ?? []),
                caseID: entry.challenge.id
            )
            return try constraintPlan(
                name: action.name,
                plane: frame,
                first: action.first,
                second: action.second,
                relation: action.relation,
                caseID: entry.challenge.id
            )
        case (.box, .automation(.solid(.box(let name, let origin, let width, let depth, let height)))):
            try validateBox(
                name: name,
                origin: origin,
                width: width,
                depth: depth,
                height: height,
                caseID: entry.challenge.id
            )
            return boxPlan(
                name: name,
                origin: origin,
                width: width,
                depth: depth,
                height: height
            )
        case (.cylinder, .automation(.solid(.cylinder(
            let name,
            let baseCenter,
            let axis,
            let radius,
            let depth
        )))):
            try validateCylinder(
                name: name,
                baseCenter: baseCenter,
                axis: axis,
                radius: radius,
                depth: depth,
                caseID: entry.challenge.id
            )
            return cylinderPlan(
                name: name,
                baseCenter: baseCenter,
                axis: axis,
                radius: radius,
                height: depth
            )
        case (.sphere, .automation(.solid(.sphere(let name, let center, let radius)))):
            try validateName(name, caseID: entry.challenge.id)
            try center.validate(caseID: entry.challenge.id, field: "sphere.center")
            try validateLength(radius, field: "sphere.radius", caseID: entry.challenge.id)
            return spherePlan(name: name, center: center, radius: radius)
        case (.transform, .automation(.transform(let action))):
            try validateTransformSource(action.source, caseID: entry.challenge.id)
            try CADTransformSubmission(
                translation: action.translation,
                axisPoint: action.axisPoint,
                rotationAxis: action.rotationAxis,
                rotation: action.rotation
            ).validate(caseID: entry.challenge.id)
            return try transformPlan(
                source: action.source,
                translation: action.translation,
                axisPoint: action.axisPoint,
                rotationAxis: action.rotationAxis,
                rotation: action.rotation,
                caseID: entry.challenge.id
            )
        case (.compound, .compound(let action)):
            let projection = try CADCompoundChallengeProjection.decode(entry.challenge)
            return try compoundPlan(
                members: action.members,
                expectedMembers: projection.members,
                caseID: entry.challenge.id
            )
        default:
            throw invalid(entry, "The action kind does not match the catalog category.")
        }
    }

    private func linePlan(
        name: String,
        plane: CADPlaneFrame,
        start: CADPoint3D,
        end: CADPoint3D
    ) -> CADSemanticProgramPlan {
        let symbol = "line"
        let outputs = [
            output(symbol, "curve", .feature),
            output(symbol, "scene", .sceneNode),
        ]
        return makePlan(
            nodes: [semanticNode(
                symbol: symbol,
                operationID: RupaCADSemanticOperationID.sketchLine,
                arguments: [
                    "name": text(name),
                    "plane": linePlaneArgument(plane.orientation, anchor: plane.origin),
                    "start": point(start),
                    "end": point(end),
                ]
            )],
            steps: [step(symbol, RupaCADSemanticOperationID.sketchLine, outputs)],
            requestedOutputs: outputs
        )
    }

    private func rectanglePlan(
        name: String,
        plane: CADPlaneFrame,
        center: CADPoint3D,
        width: CADLength,
        height: CADLength
    ) -> CADSemanticProgramPlan {
        let symbol = "rectangle"
        let outputs = [
            output(symbol, "profile", .feature),
            output(symbol, "scene", .sceneNode),
        ]
        return makePlan(
            nodes: [semanticNode(
                symbol: symbol,
                operationID: RupaCADSemanticOperationID.sketchRectangle,
                arguments: [
                    "name": text(name),
                    "plane": planeArgument(plane),
                    "center": point(center),
                    "width": length(width),
                    "height": length(height),
                ]
            )],
            steps: [step(symbol, RupaCADSemanticOperationID.sketchRectangle, outputs)],
            requestedOutputs: outputs
        )
    }

    private func circlePlan(
        name: String,
        plane: CADPlaneFrame,
        center: CADPoint3D,
        radius: CADLength
    ) -> CADSemanticProgramPlan {
        let symbol = "circle"
        let outputs = [
            output(symbol, "profile", .feature),
            output(symbol, "scene", .sceneNode),
        ]
        return makePlan(
            nodes: [semanticNode(
                symbol: symbol,
                operationID: RupaCADSemanticOperationID.sketchCircle,
                arguments: [
                    "name": text(name),
                    "plane": planeArgument(plane),
                    "center": point(center),
                    "radius": length(radius),
                ]
            )],
            steps: [step(symbol, RupaCADSemanticOperationID.sketchCircle, outputs)],
            requestedOutputs: outputs
        )
    }

    private func anglePlan(
        name: String,
        plane: CADPlaneFrame,
        firstStart: CADPoint3D,
        firstEnd: CADPoint3D,
        secondStart: CADPoint3D,
        secondEnd: CADPoint3D
    ) -> CADSemanticProgramPlan {
        let firstSymbol = "\(name).first-line"
        let secondSymbol = "\(name).second-line"
        let firstOutputs = [
            output(firstSymbol, "curve", .feature),
            output(firstSymbol, "scene", .sceneNode),
        ]
        let secondOutputs = [
            output(secondSymbol, "curve", .feature),
            output(secondSymbol, "scene", .sceneNode),
        ]
        return makePlan(
            nodes: [
                semanticNode(
                    symbol: firstSymbol,
                    operationID: RupaCADSemanticOperationID.sketchLine,
                    arguments: [
                        "name": text(firstSymbol),
                        "plane": planeArgument(plane),
                        "start": point(firstStart),
                        "end": point(firstEnd),
                    ]
                ),
                semanticNode(
                    symbol: secondSymbol,
                    operationID: RupaCADSemanticOperationID.sketchLine,
                    arguments: [
                        "name": text(secondSymbol),
                        "plane": planeArgument(plane),
                        "start": point(secondStart),
                        "end": point(secondEnd),
                    ]
                ),
            ],
            steps: [
                step(firstSymbol, RupaCADSemanticOperationID.sketchLine, firstOutputs),
                step(secondSymbol, RupaCADSemanticOperationID.sketchLine, secondOutputs),
            ],
            requestedOutputs: firstOutputs + secondOutputs
        )
    }

    private func boxPlan(
        name: String,
        origin: CADPoint3D,
        width: CADLength,
        depth: CADLength,
        height: CADLength
    ) -> CADSemanticProgramPlan {
        let symbol = "box"
        let outputs = solidOutputs(symbol)
        return makePlan(
            nodes: [semanticNode(
                symbol: symbol,
                operationID: RupaCADSemanticOperationID.solidBox,
                arguments: [
                    "name": text(name),
                    "origin": point(origin),
                    "width": length(width),
                    "depth": length(depth),
                    "height": length(height),
                ]
            )],
            steps: [step(symbol, RupaCADSemanticOperationID.solidBox, outputs)],
            requestedOutputs: outputs
        )
    }

    private func cylinderPlan(
        name: String,
        baseCenter: CADPoint3D,
        axis: CADDirection3D,
        radius: CADLength,
        height: CADLength
    ) -> CADSemanticProgramPlan {
        let symbol = "cylinder"
        let outputs = solidOutputs(symbol)
        return makePlan(
            nodes: [semanticNode(
                symbol: symbol,
                operationID: RupaCADSemanticOperationID.solidCylinder,
                arguments: [
                    "name": text(name),
                    "baseCenter": point(baseCenter),
                    "axis": direction(axis),
                    "radius": length(radius),
                    "height": length(height),
                ]
            )],
            steps: [step(symbol, RupaCADSemanticOperationID.solidCylinder, outputs)],
            requestedOutputs: outputs
        )
    }

    private func spherePlan(
        name: String,
        center: CADPoint3D,
        radius: CADLength
    ) -> CADSemanticProgramPlan {
        let symbol = "sphere"
        let outputs = [
            output(symbol, "body", .sourceBody(role: .body)),
            output(symbol, "scene", .sceneNode),
        ]
        return makePlan(
            nodes: [semanticNode(
                symbol: symbol,
                operationID: RupaCADSemanticOperationID.solidSphere,
                arguments: [
                    "name": text(name),
                    "center": point(center),
                    "radius": length(radius),
                ]
            )],
            steps: [step(symbol, RupaCADSemanticOperationID.solidSphere, outputs)],
            requestedOutputs: outputs
        )
    }

    private func constraintPlan(
        name: String,
        plane: CADPlaneFrame,
        first: CADConstraintGeometry,
        second: CADConstraintGeometry?,
        relation: CADConstraintRelation,
        caseID: CADBenchmarkCaseID
    ) throws -> CADSemanticProgramPlan {
        let symbol = "constraint"
        let outputs = [
            output(symbol, "sketch", .feature),
            output(symbol, "scene", .sceneNode),
        ]
        var entities = [geometry(first)]
        if let second {
            entities.append(geometry(second))
        }
        let constrainedNode = semanticNode(
            symbol: symbol,
            operationID: RupaCADSemanticOperationID.sketchConstrained,
            arguments: [
                "name": text(name),
                "plane": linePlaneArgument(plane.orientation, anchor: plane.origin),
                "entities": .array(entities),
                "relations": .array([
                    try relationArgument(
                        relation: relation,
                        first: first,
                        second: second,
                        caseID: caseID
                    )
                ]),
            ]
        )
        return makePlan(
            nodes: [constrainedNode],
            steps: [step(symbol, RupaCADSemanticOperationID.sketchConstrained, outputs)],
            requestedOutputs: outputs
        )
    }

    private func transformPlan(
        source: CADTransformSourceAction,
        translation: CADPoint3D,
        axisPoint: CADPoint3D,
        rotationAxis: CADDirection3D,
        rotation: CADAngle,
        caseID: CADBenchmarkCaseID
    ) throws -> CADSemanticProgramPlan {
        let sourceSymbol = "transform-source"
        let transformSymbol = "transform"
        let sourceNode: SemanticProgramNode
        let sourceOutputs: [SemanticOutputReference]
        let sourceScene: SemanticOutputReference
        switch source {
        case .sketch(.line(let name, let plane, let start, let end)):
            sourceScene = output(sourceSymbol, "scene", .sceneNode)
            sourceOutputs = [output(sourceSymbol, "curve", .feature), sourceScene]
            sourceNode = semanticNode(
                symbol: sourceSymbol,
                operationID: RupaCADSemanticOperationID.sketchLine,
                arguments: [
                    "name": text(name),
                    "plane": linePlaneArgument(plane, anchor: start),
                    "start": point(start),
                    "end": point(end),
                ]
            )
        case .sketch(.rectangle(let name, let plane, let center, let width, let height)):
            sourceScene = output(sourceSymbol, "scene", .sceneNode)
            sourceOutputs = [output(sourceSymbol, "profile", .feature), sourceScene]
            sourceNode = semanticNode(
                symbol: sourceSymbol,
                operationID: RupaCADSemanticOperationID.sketchRectangle,
                arguments: [
                    "name": text(name),
                    "plane": planeArgument(plane, origin: center),
                    "center": point(center),
                    "width": length(width),
                    "height": length(height),
                ]
            )
        case .sketch(.circle(let name, let plane, let center, let radius)):
            sourceScene = output(sourceSymbol, "scene", .sceneNode)
            sourceOutputs = [output(sourceSymbol, "profile", .feature), sourceScene]
            sourceNode = semanticNode(
                symbol: sourceSymbol,
                operationID: RupaCADSemanticOperationID.sketchCircle,
                arguments: [
                    "name": text(name),
                    "plane": planeArgument(plane, origin: center),
                    "center": point(center),
                    "radius": length(radius),
                ]
            )
        case .solid(.box(let name, let origin, let width, let depth, let height)):
            sourceScene = output(sourceSymbol, "bodyScene", .sceneNode)
            sourceOutputs = solidOutputs(sourceSymbol)
            sourceNode = semanticNode(
                symbol: sourceSymbol,
                operationID: RupaCADSemanticOperationID.solidBox,
                arguments: [
                    "name": text(name),
                    "origin": point(origin),
                    "width": length(width),
                    "depth": length(depth),
                    "height": length(height),
                ]
            )
        case .solid(.cylinder(let name, let baseCenter, let axis, let radius, let depth)):
            sourceScene = output(sourceSymbol, "bodyScene", .sceneNode)
            sourceOutputs = solidOutputs(sourceSymbol)
            sourceNode = semanticNode(
                symbol: sourceSymbol,
                operationID: RupaCADSemanticOperationID.solidCylinder,
                arguments: [
                    "name": text(name),
                    "baseCenter": point(baseCenter),
                    "axis": direction(axis),
                    "radius": length(radius),
                    "height": length(depth),
                ]
            )
        default:
            throw invalid(caseID, "Transform source must be one typed line, rectangle, circle, box, or cylinder.")
        }

        let transformNode = semanticNode(
            symbol: transformSymbol,
            operationID: RupaCADSemanticOperationID.sceneTransform,
            arguments: [
                // This is deliberately a local reference to the source node in
                // this program; existing session identifiers are not portable.
                "scene": .local(sourceScene),
                "translation": point(translation),
                "axisPoint": point(axisPoint),
                "rotationAxis": direction(rotationAxis),
                "rotation": angle(rotation),
            ]
        )
        return makePlan(
            nodes: [sourceNode, transformNode],
            steps: [
                step(sourceSymbol, sourceNode.invocation.operationID, sourceOutputs),
                step(transformSymbol, RupaCADSemanticOperationID.sceneTransform, []),
            ],
            requestedOutputs: sourceOutputs
        )
    }

    private func compoundPlan(
        members: [CADCompoundMemberAction],
        expectedMembers: [CADCompoundChallengeProjection.Member],
        caseID: CADBenchmarkCaseID
    ) throws -> CADSemanticProgramPlan {
        guard members.count == expectedMembers.count else {
            throw invalid(caseID, "A compound action must contain the declared public members.")
        }
        var nodes: [SemanticProgramNode] = []
        var steps: [CADSemanticProgramPlan.Step] = []
        var requested: [SemanticOutputReference] = []
        for (index, member) in members.enumerated() {
            let expected = expectedMembers[index]
            guard member.role == expected.role,
                  member.primitive == expected.primitive else {
                throw invalid(caseID, "Compound members must preserve public role and primitive order.")
            }
            let symbol = "member-\(index)"
            let outputs = solidOutputs(symbol)
            let operationID: DomainCapabilityID
            let memberNode: SemanticProgramNode
            switch member.solid {
            case .box(let name, let origin, let width, let depth, let height):
                try validateBox(
                    name: name,
                    origin: origin,
                    width: width,
                    depth: depth,
                    height: height,
                    caseID: caseID
                )
                operationID = RupaCADSemanticOperationID.solidBox
                memberNode = semanticNode(
                    symbol: symbol,
                    operationID: operationID,
                    arguments: [
                        "name": text(name),
                        "origin": point(origin),
                        "width": length(width),
                        "depth": length(depth),
                        "height": length(height),
                    ]
                )
            case .cylinder(let name, let baseCenter, let axis, let radius, let depth):
                try validateCylinder(
                    name: name,
                    baseCenter: baseCenter,
                    axis: axis,
                    radius: radius,
                    depth: depth,
                    caseID: caseID
                )
                operationID = RupaCADSemanticOperationID.solidCylinder
                memberNode = semanticNode(
                    symbol: symbol,
                    operationID: operationID,
                    arguments: [
                        "name": text(name),
                        "baseCenter": point(baseCenter),
                        "axis": direction(axis),
                        "radius": length(radius),
                        "height": length(depth),
                    ]
                )
            case .sphere:
                throw invalid(caseID, "Compound members must be boxes or cylinders.")
            }
            nodes.append(memberNode)
            steps.append(step(symbol, operationID, outputs))
            requested.append(contentsOf: outputs)
        }
        return makePlan(nodes: nodes, steps: steps, requestedOutputs: requested)
    }

    private func solidOutputs(_ symbol: String) -> [SemanticOutputReference] {
        [
            output(symbol, "profile", .feature),
            output(symbol, "body", .sourceBody(role: .body)),
            output(symbol, "profileScene", .sceneNode),
            output(symbol, "bodyScene", .sceneNode),
        ]
    }

    private func makePlan(
        nodes: [SemanticProgramNode],
        steps: [CADSemanticProgramPlan.Step],
        requestedOutputs: [SemanticOutputReference]
    ) -> CADSemanticProgramPlan {
        CADSemanticProgramPlan(
            request: AgentSemanticProgramRequest(
                SemanticProgram(
                    schemaVersion: .current,
                    nodes: nodes,
                    requestedOutputs: requestedOutputs
                )
            ),
            steps: steps
        )
    }

    private func semanticNode(
        symbol: String,
        operationID: DomainCapabilityID,
        arguments: [String: SemanticArgument]
    ) -> SemanticProgramNode {
        SemanticProgramNode(
            symbol: ProgramNodeSymbol(symbol),
            invocation: SemanticOperationInvocation(
                operationID: operationID,
                operationVersion: RupaCADDomain.operationVersion,
                arguments: Dictionary(uniqueKeysWithValues: arguments.map {
                    (SemanticArgumentID($0.key), $0.value)
                })
            )
        )
    }

    private func step(
        _ symbol: String,
        _ operationID: DomainCapabilityID,
        _ outputs: [SemanticOutputReference]
    ) -> CADSemanticProgramPlan.Step {
        CADSemanticProgramPlan.Step(
            symbol: symbol,
            operationID: operationID,
            outputs: outputs.map(AgentSemanticOutputReference.init)
        )
    }

    private func output(
        _ symbol: String,
        _ name: String,
        _ kind: SemanticReferenceKind
    ) -> SemanticOutputReference {
        SemanticOutputReference(
            node: ProgramNodeSymbol(symbol),
            output: SemanticOutputID(name),
            kind: kind
        )
    }

    private func text(_ value: String) -> SemanticArgument {
        .literal(.text(value))
    }

    private func point(_ value: CADPoint3D) -> SemanticArgument {
        let meters = value.meters
        return .literal(.point(SemanticPoint3D(
            x: meters.x,
            y: meters.y,
            z: meters.z,
            unit: .meter
        )))
    }

    private func direction(_ value: CADDirection3D) -> SemanticArgument {
        .literal(.direction(SemanticDirection3D(x: value.x, y: value.y, z: value.z)))
    }

    private func length(_ value: CADLength) -> SemanticArgument {
        .literal(.number(value.meters, unit: .meter))
    }

    private func angle(_ value: CADAngle) -> SemanticArgument {
        .literal(.number(value.radians * 180.0 / .pi, unit: .degree))
    }

    private func planeArgument(
        _ orientation: CADSketchPlane,
        origin: CADPoint3D
    ) -> SemanticArgument {
        let normal = orientation.normal
        let point = origin.meters
        return .literal(.plane(SemanticPlane(
            origin: SemanticPoint3D(x: point.x, y: point.y, z: point.z, unit: .meter),
            normal: SemanticDirection3D(x: normal.x, y: normal.y, z: normal.z)
        )))
    }

    private func planeArgument(_ frame: CADPlaneFrame) -> SemanticArgument {
        planeArgument(frame.orientation, origin: frame.origin)
    }

    private func validatedPlane(
        orientation: CADSketchPlane,
        expectedOrientation: CADSketchPlane,
        origin: CADPoint3D,
        points: [(field: String, point: CADPoint3D)],
        caseID: CADBenchmarkCaseID
    ) throws -> CADPlaneFrame {
        guard orientation == expectedOrientation else {
            throw invalid(caseID, "The action must use the public challenge plane orientation.")
        }
        let frame = expectedOrientation.frame(anchor: origin)
        try frame.validate(caseID: caseID)
        for (field, point) in points {
            try point.validate(caseID: caseID, field: field)
            let distance = frame.signedNormalDistance(to: point)
            guard distance.isFinite, abs(distance) <= ModelingTolerance.standard.distance else {
                throw invalid(caseID, "\(field) is outside the public challenge plane.")
            }
        }
        return frame
    }

    private func linePlaneArgument(
        _ orientation: CADSketchPlane,
        anchor: CADPoint3D
    ) -> SemanticArgument {
        let point = anchor.meters
        let normalOffset = switch orientation {
        case .xy: point.z
        case .xz: point.y
        case .yz: point.x
        }
        guard abs(normalOffset) <= ModelingTolerance.standard.distance else {
            return planeArgument(orientation, origin: anchor)
        }
        return .literal(.plane(SemanticPlane(
            origin: SemanticPoint3D(x: 0, y: 0, z: 0, unit: .meter),
            normal: SemanticDirection3D(
                x: orientation.normal.x,
                y: orientation.normal.y,
                z: orientation.normal.z
            )
        )))
    }

    private func geometry(_ value: CADConstraintGeometry) -> SemanticArgument {
        switch value {
        case .line(let start, let end):
            return object([
                ("kind", text("line")),
                ("start", point(start)),
                ("end", point(end)),
            ])
        case .circle(let center, let radius):
            return object([
                ("kind", text("circle")),
                ("center", point(center)),
                ("radius", length(radius)),
            ])
        }
    }

    private func relationArgument(
        relation: CADConstraintRelation,
        first: CADConstraintGeometry,
        second: CADConstraintGeometry?,
        caseID: CADBenchmarkCaseID
    ) throws -> SemanticArgument {
        switch relation {
        case .horizontal, .vertical:
            guard second == nil, case .line = first else {
                throw invalid(caseID, "A single-line relation must carry one line only.")
            }
            return object([
                ("kind", text(relation.rawValue)),
                ("entity", .literal(.integer(0))),
            ])
        case .parallel, .perpendicular, .equalLength, .concentric, .equalRadius:
            guard second != nil else {
                throw invalid(caseID, "A two-entity relation has no second geometry.")
            }
            return object([
                ("kind", text(relation.rawValue)),
                ("firstEntity", .literal(.integer(0))),
                ("secondEntity", .literal(.integer(1))),
            ])
        case .coincident:
            guard case .line = first, let second else {
                throw invalid(caseID, "Coincident relations require two lines.")
            }
            guard case .line = second else {
                throw invalid(caseID, "Coincident relations require two lines.")
            }
            let endpoints = try coincidentEndpoints(first: first, second: second, caseID: caseID)
            return object([
                ("kind", text(relation.rawValue)),
                ("firstEntity", .literal(.integer(0))),
                ("firstEndpoint", text(endpoints.first)),
                ("secondEntity", .literal(.integer(1))),
                ("secondEndpoint", text(endpoints.second)),
            ])
        }
    }

    private func object(_ entries: [(String, SemanticArgument)]) -> SemanticArgument {
        .object(entries.sorted { $0.0 < $1.0 }.map {
            SemanticArgumentObjectEntry(key: $0.0, value: $0.1)
        })
    }

    private func anchor(_ geometry: CADConstraintGeometry) -> CADPoint3D {
        switch geometry {
        case .line(let start, _): start
        case .circle(let center, _): center
        }
    }

    private func geometryPoints(
        _ geometry: CADConstraintGeometry,
        field: String
    ) -> [(field: String, point: CADPoint3D)] {
        switch geometry {
        case .line(let start, let end):
            [("\(field).start", start), ("\(field).end", end)]
        case .circle(let center, _):
            [("\(field).center", center)]
        }
    }

    private func coincidentEndpoints(
        first: CADConstraintGeometry,
        second: CADConstraintGeometry,
        caseID: CADBenchmarkCaseID
    ) throws -> (first: String, second: String) {
        guard case .line(let firstStart, let firstEnd) = first,
              case .line(let secondStart, let secondEnd) = second else {
            throw invalid(caseID, "Coincident relations require line endpoints.")
        }
        let firstEndpoints = [("start", firstStart), ("end", firstEnd)]
        let secondEndpoints = [("start", secondStart), ("end", secondEnd)]
        let matches = firstEndpoints.flatMap { lhs in
            secondEndpoints.compactMap { rhs -> (String, String)? in
                guard pointDistance(lhs.1, rhs.1) <= ModelingTolerance.standard.distance else {
                    return nil
                }
                return (lhs.0, rhs.0)
            }
        }
        guard matches.count == 1, let match = matches.first else {
            throw invalid(caseID, "Coincident input must have exactly one shared endpoint.")
        }
        return match
    }

    private func validateName(
        _ name: String,
        caseID: CADBenchmarkCaseID
    ) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalid(caseID, "CAD operation names must not be empty.")
        }
    }

    private func validateLength(
        _ length: CADLength,
        field: String,
        caseID: CADBenchmarkCaseID
    ) throws {
        try length.validate(caseID: caseID, field: field)
        guard length.meters > ModelingTolerance.standard.distance else {
            throw invalid(caseID, "\(field) is degenerate under the modeling tolerance.")
        }
    }

    private func validateLine(
        _ start: CADPoint3D,
        _ end: CADPoint3D,
        field: String,
        caseID: CADBenchmarkCaseID
    ) throws {
        try start.validate(caseID: caseID, field: "\(field).start")
        try end.validate(caseID: caseID, field: "\(field).end")
        guard pointDistance(start, end) > ModelingTolerance.standard.distance else {
            throw invalid(caseID, "\(field) is degenerate under the modeling tolerance.")
        }
    }

    private func validateConstraintGeometry(
        _ geometry: CADConstraintGeometry,
        field: String,
        caseID: CADBenchmarkCaseID
    ) throws {
        switch geometry {
        case .line(let start, let end):
            try validateLine(start, end, field: field, caseID: caseID)
        case .circle(let center, let radius):
            try center.validate(caseID: caseID, field: "\(field).center")
            try validateLength(radius, field: "\(field).radius", caseID: caseID)
        }
    }

    private func validateBox(
        name: String,
        origin: CADPoint3D,
        width: CADLength,
        depth: CADLength,
        height: CADLength,
        caseID: CADBenchmarkCaseID
    ) throws {
        try validateName(name, caseID: caseID)
        try origin.validate(caseID: caseID, field: "box.origin")
        try validateLength(width, field: "box.width", caseID: caseID)
        try validateLength(depth, field: "box.depth", caseID: caseID)
        try validateLength(height, field: "box.height", caseID: caseID)
        let point = origin.meters
        guard (point.x + width.meters).isFinite,
              (point.y + depth.meters).isFinite,
              (point.z + height.meters).isFinite else {
            throw invalid(caseID, "The box extent is not finite.")
        }
    }

    private func validateCylinder(
        name: String,
        baseCenter: CADPoint3D,
        axis: CADDirection3D,
        radius: CADLength,
        depth: CADLength,
        caseID: CADBenchmarkCaseID
    ) throws {
        try validateName(name, caseID: caseID)
        try baseCenter.validate(caseID: caseID, field: "cylinder.baseCenter")
        try axis.validate(caseID: caseID, field: "cylinder.axis")
        try validateLength(radius, field: "cylinder.radius", caseID: caseID)
        try validateLength(depth, field: "cylinder.depth", caseID: caseID)
        let base = baseCenter.meters
        let scale = depth.meters / axis.length
        guard (base.x + axis.x * scale).isFinite,
              (base.y + axis.y * scale).isFinite,
              (base.z + axis.z * scale).isFinite else {
            throw invalid(caseID, "The cylinder extent is not finite.")
        }
    }

    private func validateTransformSource(
        _ source: CADTransformSourceAction,
        caseID: CADBenchmarkCaseID
    ) throws {
        switch source {
        case .sketch(.line(let name, _, let start, let end)):
            try validateName(name, caseID: caseID)
            try validateLine(start, end, field: "transform.source.line", caseID: caseID)
        case .sketch(.rectangle(let name, _, let center, let width, let height)):
            try validateName(name, caseID: caseID)
            try center.validate(caseID: caseID, field: "transform.source.rectangle.center")
            try validateLength(width, field: "transform.source.rectangle.width", caseID: caseID)
            try validateLength(height, field: "transform.source.rectangle.height", caseID: caseID)
        case .sketch(.circle(let name, _, let center, let radius)):
            try validateName(name, caseID: caseID)
            try center.validate(caseID: caseID, field: "transform.source.circle.center")
            try validateLength(radius, field: "transform.source.circle.radius", caseID: caseID)
        case .solid(.box(let name, let origin, let width, let depth, let height)):
            try validateBox(
                name: name,
                origin: origin,
                width: width,
                depth: depth,
                height: height,
                caseID: caseID
            )
        case .solid(.cylinder(let name, let center, let axis, let radius, let depth)):
            try validateCylinder(
                name: name,
                baseCenter: center,
                axis: axis,
                radius: radius,
                depth: depth,
                caseID: caseID
            )
        case .sketch(.angle), .sketch(.constraint), .solid(.sphere):
            throw invalid(caseID, "Transform source must be a line, rectangle, circle, box, or cylinder.")
        }
    }

    private func pointDistance(_ first: CADPoint3D, _ second: CADPoint3D) -> Double {
        let lhs = first.meters
        let rhs = second.meters
        return hypot(hypot(rhs.x - lhs.x, rhs.y - lhs.y), rhs.z - lhs.z)
    }

    private func invalid(_ entry: CADCatalogEntry, _ reason: String) -> CADBenchmarkError {
        invalid(entry.challenge.id, reason)
    }

    private func invalid(_ caseID: CADBenchmarkCaseID, _ reason: String) -> CADBenchmarkError {
        CADBenchmarkError.invalidInput(caseID: caseID.rawValue, reason: reason)
    }
}
