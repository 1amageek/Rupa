import RupaCore

struct PatternArrayInspectorState: Equatable, Sendable {
    enum SelectionRole: Equatable, Sendable {
        case sourceRoot
        case output
        case outputDescendant
        case mixed
    }

    struct LinearAxis: Equatable, Sendable {
        var copyCount: Int
        var distanceMeters: Double?
        var distanceMode: PatternArrayDistanceMode

        var distanceIsEditable: Bool {
            distanceMeters != nil
        }

        var distanceModeTitle: String {
            switch distanceMode {
            case .spacing:
                "Spacing"
            case .extent:
                "Extent"
            }
        }
    }

    struct AngularAxis: Equatable, Sendable {
        var center: Point3D
        var axis: Vector3D
        var copyCount: Int
        var angleRadians: Double?
        var angleMode: PatternArrayAngleMode

        var angleIsEditable: Bool {
            angleRadians != nil
        }

        var angleModeTitle: String {
            switch angleMode {
            case .spacing:
                "Spacing"
            case .extent:
                "Extent"
            }
        }
    }

    struct CurveDistribution: Equatable, Sendable {
        var pathTitle: String
        var copyCount: Int
        var twistRadians: Double?
        var endScale: Double?
        var alignment: PatternArrayCurveAlignment
        var extentMeters: Double?
        var extentRatio: Double?
        var extentMode: PatternArrayCurveExtentMode

        var twistIsEditable: Bool {
            twistRadians != nil
        }

        var endScaleIsEditable: Bool {
            endScale != nil
        }

        var extentIsEditable: Bool {
            switch extentMode {
            case .distance:
                extentMeters != nil
            case .ratio:
                extentRatio != nil
            }
        }

        var extentModeTitle: String {
            switch extentMode {
            case .distance:
                "Distance"
            case .ratio:
                "Ratio"
            }
        }
    }

    var sourceID: PatternArraySourceID
    var name: String
    var definitionID: ComponentDefinitionID
    var definitionName: String?
    var rootSceneNodeID: SceneNodeID
    var rootSceneNodeName: String?
    var distributionKind: PatternArraySummary.DistributionKind
    var outputMode: PatternArrayOutputMode
    var outputCount: Int
    var selectedRole: SelectionRole
    var selectedOutputIndices: [Int]
    var outputOwnership: PatternArraySummary.OutputOwnership
    var diagnostics: [PatternArraySummary.Diagnostic]
    var rectangularFirstAxis: LinearAxis?
    var rectangularSecondAxis: LinearAxis?
    var radialAngularAxis: AngularAxis?
    var radialAxis: LinearAxis?
    var curve: CurveDistribution?

    init?(
        selectedNodes: [SceneNode],
        sceneNodes: [SceneNodeID: SceneNode],
        patternArrays: [PatternArraySourceID: PatternArraySource] = [:],
        summaryResult: PatternArraySummaryResult
    ) {
        guard !selectedNodes.isEmpty else {
            return nil
        }

        let matches = selectedNodes.compactMap { node in
            Self.match(
                node: node,
                sceneNodes: sceneNodes,
                summaries: summaryResult.patternArrays
            )
        }
        guard matches.count == selectedNodes.count,
              let firstMatch = matches.first,
              matches.allSatisfy({ $0.summary.sourceID == firstMatch.summary.sourceID }) else {
            return nil
        }

        let summary = firstMatch.summary
        self.sourceID = summary.sourceID
        self.name = summary.name
        self.definitionID = summary.definitionID
        self.definitionName = summary.definitionName
        self.rootSceneNodeID = summary.rootSceneNodeID
        self.rootSceneNodeName = summary.rootSceneNodeName
        self.distributionKind = summary.distributionKind
        self.outputMode = summary.outputMode
        self.outputCount = summary.outputCount
        self.selectedRole = Self.selectedRole(for: matches.map(\.role))
        self.selectedOutputIndices = Self.selectedOutputIndices(from: matches)
        self.outputOwnership = summary.outputOwnership
        self.diagnostics = summary.diagnostics
        let source = patternArrays[summary.sourceID]
        self.rectangularFirstAxis = source.flatMap(Self.rectangularFirstAxis)
        self.rectangularSecondAxis = source.flatMap(Self.rectangularSecondAxis)
        self.radialAngularAxis = source.flatMap(Self.radialAngularAxis)
        self.radialAxis = source.flatMap(Self.radialAxis)
        self.curve = source.flatMap(Self.curveDistribution)
    }

    var selectionRoleTitle: String {
        switch selectedRole {
        case .sourceRoot:
            "Source Root"
        case .output:
            "Output"
        case .outputDescendant:
            "Output Descendant"
        case .mixed:
            "Mixed"
        }
    }

    var selectedOutputTitle: String {
        guard !selectedOutputIndices.isEmpty else {
            return "None"
        }
        let visibleIndices = selectedOutputIndices
            .prefix(3)
            .map { "#\($0 + 1)" }
            .joined(separator: ", ")
        if selectedOutputIndices.count > 3 {
            return "\(visibleIndices), +\(selectedOutputIndices.count - 3)"
        }
        return visibleIndices
    }

    var distributionTitle: String {
        switch distributionKind {
        case .rectangular:
            "Rectangular"
        case .radial:
            "Radial"
        case .curve:
            "Curve"
        }
    }

    var outputModeTitle: String {
        switch outputMode {
        case .componentInstance:
            "Component Instance"
        case .independentCopy:
            "Independent Copy"
        }
    }

    var ownershipTitle: String {
        switch outputOwnership.kind {
        case .sourceOwnedComponentInstances:
            "Source-owned Component Instances"
        case .sourceOwnedIndependentCopies:
            "Source-owned Independent Copies"
        }
    }

    var directEditTitle: String {
        outputOwnership.directOutputEditingAllowed ? "Allowed" : "Source Controlled"
    }

    var sourceEditTitle: String {
        actionTitle(outputOwnership.sourceEditAction)
    }

    var detachTitle: String {
        actionTitle(outputOwnership.detachAction)
    }

    var diagnosticsTitle: String {
        guard !diagnostics.isEmpty else {
            return "None"
        }
        let errors = diagnostics.filter { $0.severity == .error }.count
        let warnings = diagnostics.filter { $0.severity == .warning }.count
        var parts: [String] = []
        if errors > 0 {
            parts.append("\(errors) \(errors == 1 ? "error" : "errors")")
        }
        if warnings > 0 {
            parts.append("\(warnings) \(warnings == 1 ? "warning" : "warnings")")
        }
        return parts.joined(separator: ", ")
    }

    private struct Match {
        var summary: PatternArraySummary
        var role: SelectionRole
        var outputIndex: Int?
    }

    private static func match(
        node: SceneNode,
        sceneNodes: [SceneNodeID: SceneNode],
        summaries: [PatternArraySummary]
    ) -> Match? {
        for summary in summaries {
            if node.id == summary.rootSceneNodeID {
                return Match(summary: summary, role: .sourceRoot, outputIndex: nil)
            }
            if let componentInstanceID = node.reference?.componentInstanceID,
               let outputIndex = summary.componentInstanceOutputIDs.firstIndex(of: componentInstanceID) {
                return Match(summary: summary, role: .output, outputIndex: outputIndex)
            }
            if let outputIndex = summary.outputSceneNodeIDs.firstIndex(of: node.id) {
                return Match(summary: summary, role: .output, outputIndex: outputIndex)
            }
            if let outputIndex = outputDescendantIndex(
                nodeID: node.id,
                outputSceneNodeIDs: summary.outputSceneNodeIDs,
                sceneNodes: sceneNodes
            ) {
                return Match(summary: summary, role: .outputDescendant, outputIndex: outputIndex)
            }
        }
        return nil
    }

    private static func outputDescendantIndex(
        nodeID: SceneNodeID,
        outputSceneNodeIDs: [SceneNodeID],
        sceneNodes: [SceneNodeID: SceneNode]
    ) -> Int? {
        for (index, outputSceneNodeID) in outputSceneNodeIDs.enumerated() {
            var visitedSceneNodeIDs: Set<SceneNodeID> = []
            if sceneSubtree(
                outputSceneNodeID,
                contains: nodeID,
                sceneNodes: sceneNodes,
                visitedSceneNodeIDs: &visitedSceneNodeIDs
            ) {
                return index
            }
        }
        return nil
    }

    private static func sceneSubtree(
        _ rootSceneNodeID: SceneNodeID,
        contains targetSceneNodeID: SceneNodeID,
        sceneNodes: [SceneNodeID: SceneNode],
        visitedSceneNodeIDs: inout Set<SceneNodeID>
    ) -> Bool {
        guard visitedSceneNodeIDs.insert(rootSceneNodeID).inserted,
              let sceneNode = sceneNodes[rootSceneNodeID] else {
            return false
        }
        if rootSceneNodeID == targetSceneNodeID {
            return true
        }
        for childID in sceneNode.childIDs {
            if sceneSubtree(
                childID,
                contains: targetSceneNodeID,
                sceneNodes: sceneNodes,
                visitedSceneNodeIDs: &visitedSceneNodeIDs
            ) {
                return true
            }
        }
        return false
    }

    private static func selectedRole(for roles: [SelectionRole]) -> SelectionRole {
        guard let firstRole = roles.first,
              roles.allSatisfy({ $0 == firstRole }) else {
            return .mixed
        }
        return firstRole
    }

    private static func selectedOutputIndices(from matches: [Match]) -> [Int] {
        var indices: [Int] = []
        var seenIndices: Set<Int> = []
        for match in matches {
            guard let outputIndex = match.outputIndex,
                  seenIndices.insert(outputIndex).inserted else {
                continue
            }
            indices.append(outputIndex)
        }
        return indices.sorted()
    }

    private static func rectangularFirstAxis(
        for source: PatternArraySource
    ) -> LinearAxis? {
        guard case .rectangular(let rectangular) = source.distribution else {
            return nil
        }
        return linearAxis(from: rectangular.firstAxis)
    }

    private static func rectangularSecondAxis(
        for source: PatternArraySource
    ) -> LinearAxis? {
        guard case .rectangular(let rectangular) = source.distribution,
              let secondAxis = rectangular.secondAxis else {
            return nil
        }
        return linearAxis(from: secondAxis)
    }

    private static func radialAngularAxis(
        for source: PatternArraySource
    ) -> AngularAxis? {
        guard case .radial(let radial) = source.distribution else {
            return nil
        }
        return AngularAxis(
            center: radial.angularAxis.center,
            axis: radial.angularAxis.axis,
            copyCount: radial.angularAxis.copyCount,
            angleRadians: constantAngleRadians(radial.angularAxis.angle),
            angleMode: radial.angularAxis.angleMode
        )
    }

    private static func radialAxis(
        for source: PatternArraySource
    ) -> LinearAxis? {
        guard case .radial(let radial) = source.distribution,
              let radialAxis = radial.radialAxis else {
            return nil
        }
        return linearAxis(from: radialAxis)
    }

    private static func curveDistribution(
        for source: PatternArraySource
    ) -> CurveDistribution? {
        guard case .curve(let curve) = source.distribution else {
            return nil
        }
        let extentMeters: Double?
        let extentRatio: Double?
        switch curve.extentMode {
        case .distance:
            extentMeters = constantLengthMeters(curve.extent)
            extentRatio = nil
        case .ratio:
            extentMeters = nil
            extentRatio = constantScalar(curve.extent)
        }
        return CurveDistribution(
            pathTitle: pathTitle(for: curve.path),
            copyCount: curve.copyCount,
            twistRadians: constantAngleRadians(curve.twist),
            endScale: constantScalar(curve.endScale),
            alignment: curve.alignment,
            extentMeters: extentMeters,
            extentRatio: extentRatio,
            extentMode: curve.extentMode
        )
    }

    private static func linearAxis(from axis: PatternArrayLinearAxis) -> LinearAxis {
        return LinearAxis(
            copyCount: axis.copyCount,
            distanceMeters: constantLengthMeters(axis.distance),
            distanceMode: axis.distanceMode
        )
    }

    private static func constantLengthMeters(_ expression: CADExpression) -> Double? {
        guard case .constant(let quantity) = expression,
              quantity.kind == .length,
              quantity.value.isFinite else {
            return nil
        }
        return quantity.value
    }

    private static func constantAngleRadians(_ expression: CADExpression) -> Double? {
        guard case .constant(let quantity) = expression,
              quantity.kind == .angle,
              quantity.value.isFinite else {
            return nil
        }
        return quantity.value
    }

    private static func constantScalar(_ expression: CADExpression) -> Double? {
        guard case .constant(let quantity) = expression,
              quantity.kind == .scalar,
              quantity.value.isFinite else {
            return nil
        }
        return quantity.value
    }

    private static func pathTitle(for path: PatternArrayCurvePath) -> String {
        switch path {
        case .polyline(let points, _):
            "\(points.count) Point Polyline"
        case .sketchEntity:
            "Sketch Entity"
        }
    }

    private func actionTitle(_ action: PatternArraySummary.LifecycleAction) -> String {
        switch action {
        case .updatePatternArray:
            "Update Pattern Array"
        case .explodePatternArray:
            "Explode Pattern Array"
        }
    }
}
