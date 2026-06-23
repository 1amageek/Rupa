import Foundation
import SwiftCAD

public struct EdgeOffsetSupportFaceResolution: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case supported
        case unavailable
        case ambiguous
        case notApplicable
    }

    public enum Source: String, Equatable, Sendable {
        case selectedFace
        case inferredCapFace
    }

    public var status: Status
    public var supportTarget: SelectionTarget?
    public var source: Source?
    public var diagnosticMessage: String?

    public init(
        status: Status,
        supportTarget: SelectionTarget? = nil,
        source: Source? = nil,
        diagnosticMessage: String? = nil
    ) {
        self.status = status
        self.supportTarget = supportTarget
        self.source = source
        self.diagnosticMessage = diagnosticMessage
    }

    public var isSupported: Bool {
        status == .supported && supportTarget != nil
    }

    public static func supported(
        _ target: SelectionTarget,
        source: Source
    ) -> EdgeOffsetSupportFaceResolution {
        EdgeOffsetSupportFaceResolution(
            status: .supported,
            supportTarget: target,
            source: source
        )
    }

    public static func unavailable(_ message: String) -> EdgeOffsetSupportFaceResolution {
        EdgeOffsetSupportFaceResolution(status: .unavailable, diagnosticMessage: message)
    }

    public static func ambiguous(_ message: String) -> EdgeOffsetSupportFaceResolution {
        EdgeOffsetSupportFaceResolution(status: .ambiguous, diagnosticMessage: message)
    }

    public static func notApplicable(_ message: String) -> EdgeOffsetSupportFaceResolution {
        EdgeOffsetSupportFaceResolution(status: .notApplicable, diagnosticMessage: message)
    }
}

public struct EdgeOffsetSupportFaceResolver: Sendable {
    public static let ambiguousSelectedSupportFaceMessage =
        "Offset Edge support face inference requires exactly one selected generated support face on the same body."
    public static let ambiguousCapSupportFaceMessage =
        "Offset Edge cap support face inference requires exactly one generated start or end face containing the selected edge."
    public static let missingSupportFaceMessage =
        "Offset Edge requires a selected generated support face or an inferable generated start/end cap face."

    public init() {}

    public func resolve(
        edgeTarget: SelectionTarget,
        selection: SelectionModel,
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> EdgeOffsetSupportFaceResolution {
        guard case .edge(let edgeComponentID) = edgeTarget.component else {
            return .notApplicable("Offset Edge support face inference requires an edge target.")
        }
        guard selection.containsTarget(edgeTarget) else {
            return .unavailable("Offset Edge support face inference requires the edge target to be selected.")
        }
        if let selectedSupportFace = selectedSupportFaceTarget(
            for: edgeTarget,
            selection: selection
        ) {
            return selectedSupportFace
        }
        guard edgeComponentID.generatedTopologyPersistentName != nil else {
            return .unavailable("Offset Edge requires a generated topology edge target.")
        }
        return try inferredCapSupportFaceTarget(
            for: edgeTarget,
            in: document,
            objectRegistry: objectRegistry
        )
    }

    private func selectedSupportFaceTarget(
        for edgeTarget: SelectionTarget,
        selection: SelectionModel
    ) -> EdgeOffsetSupportFaceResolution? {
        guard case .edge = edgeTarget.component else {
            return nil
        }

        let candidates = selection.selectedTargets.filter { target in
            guard target.sceneNodeID == edgeTarget.sceneNodeID,
                  target != edgeTarget,
                  case .face(let componentID) = target.component,
                  componentID.generatedTopologyPersistentName != nil else {
                return false
            }
            return true
        }

        guard candidates.count <= 1 else {
            return .ambiguous(Self.ambiguousSelectedSupportFaceMessage)
        }
        guard let candidate = candidates.first else {
            return nil
        }
        return .supported(candidate, source: .selectedFace)
    }

    private func inferredCapSupportFaceTarget(
        for edgeTarget: SelectionTarget,
        in document: DesignDocument,
        objectRegistry: ObjectTypeRegistry
    ) throws -> EdgeOffsetSupportFaceResolution {
        guard case .edge(let edgeComponentID) = edgeTarget.component,
              let edgePersistentName = edgeComponentID.generatedTopologyPersistentName else {
            return .unavailable("Offset Edge requires a generated topology edge target.")
        }

        let topology = try TopologySummaryService().summarize(
            document: document,
            objectRegistry: objectRegistry
        )
        guard let edgeEntry = topology.entries.first(where: { entry in
            entry.kind == .edge &&
                entry.sceneNodeID == edgeTarget.sceneNodeID.description &&
                entry.persistentName == edgePersistentName
        }) else {
            return .unavailable("Offset Edge generated topology edge was not found in the current evaluation.")
        }
        guard edgeEntry.curveKind == "line",
              let start = edgeEntry.start,
              let end = edgeEntry.end else {
            return .unavailable("Offset Edge currently supports generated line edges with resolvable endpoints.")
        }

        let candidates = topology.entries.compactMap { entry -> SelectionTarget? in
            guard entry.kind == .face,
                  entry.sceneNodeID == edgeTarget.sceneNodeID.description,
                  entry.generatedRole == "startFace" || entry.generatedRole == "endFace",
                  edgeEndpoints(start, end, lieOnPlaneOf: entry),
                  let target = entry.selectionTarget() else {
                return nil
            }
            return target
        }

        guard candidates.count <= 1 else {
            return .ambiguous(Self.ambiguousCapSupportFaceMessage)
        }
        guard let candidate = candidates.first else {
            return .unavailable(Self.missingSupportFaceMessage)
        }
        return .supported(candidate, source: .inferredCapFace)
    }

    private func edgeEndpoints(
        _ start: TopologySummaryResult.Entry.Point,
        _ end: TopologySummaryResult.Entry.Point,
        lieOnPlaneOf face: TopologySummaryResult.Entry
    ) -> Bool {
        guard face.surfaceKind == "plane",
              let origin = face.surfaceOrigin,
              let normal = face.surfaceNormal else {
            return false
        }
        let tolerance = 1.0e-8
        return point(start, liesOnPlaneOrigin: origin, normal: normal, tolerance: tolerance) &&
            point(end, liesOnPlaneOrigin: origin, normal: normal, tolerance: tolerance)
    }

    private func point(
        _ point: TopologySummaryResult.Entry.Point,
        liesOnPlaneOrigin origin: TopologySummaryResult.Entry.Point,
        normal: TopologySummaryResult.Entry.Point,
        tolerance: Double
    ) -> Bool {
        let normalLength = sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z)
        guard normalLength > tolerance else {
            return false
        }
        let signedDistanceNumerator =
            (point.x - origin.x) * normal.x +
            (point.y - origin.y) * normal.y +
            (point.z - origin.z) * normal.z
        return abs(signedDistanceNumerator) <= tolerance * normalLength
    }
}
