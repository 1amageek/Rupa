import Foundation
import SwiftCAD

/// Resolves every anchor of a persistent measurement annotation, or reports why it cannot.
///
/// An annotation is all-or-nothing: a distance drawn from one of its two anchors would show a
/// different measurement than the one saved. Viewport display and drawing projection both consume
/// this result, so a stale annotation is reported by each of them instead of being drawn partially
/// or dropped without a trace.
public struct MeasurementAnnotationResolver: Sendable {
    public struct Resolution: Equatable, Sendable {
        public var measurementID: MeasurementAnnotationID
        public var name: String
        public var kind: MeasurementAnnotation.Kind
        public var outcome: Outcome

        public init(
            measurementID: MeasurementAnnotationID,
            name: String,
            kind: MeasurementAnnotation.Kind,
            outcome: Outcome
        ) {
            self.measurementID = measurementID
            self.name = name
            self.kind = kind
            self.outcome = outcome
        }
    }

    public enum Outcome: Equatable, Sendable {
        case resolved([MeasurementAnchorWorldPointResolver.ResolvedAnchor])
        case unresolved(EditorError)
    }

    private let anchorResolver: MeasurementAnchorWorldPointResolver

    public init(anchorResolver: MeasurementAnchorWorldPointResolver = MeasurementAnchorWorldPointResolver()) {
        self.anchorResolver = anchorResolver
    }

    /// Whether resolving the document's annotations needs a topology snapshot.
    public static func requiresTopology(_ document: DesignDocument) -> Bool {
        document.productMetadata.measurements.values.contains { measurement in
            measurement.anchors.contains(where: anchorsToTopology)
        }
    }

    /// Resolves every annotation in the document, ordered by name and then ID.
    ///
    /// `topology` is requested only when some annotation anchors to generated topology. If it
    /// cannot be produced, each annotation that needs it is reported with that failure; the
    /// others still resolve.
    public func resolveAll(
        in document: DesignDocument,
        topology: () throws -> TopologySnapshot?
    ) -> [Resolution] {
        let annotations = document.productMetadata.measurements.values.sorted {
            if $0.name != $1.name {
                return $0.name < $1.name
            }
            return $0.id.description < $1.id.description
        }
        var snapshot: TopologySnapshot?
        var topologyFailure: EditorError?
        if Self.requiresTopology(document) {
            do {
                snapshot = try topology()
            } catch let error as EditorError {
                topologyFailure = error
            } catch {
                topologyFailure = EditorError(code: .evaluationFailed, message: String(describing: error))
            }
        }
        return annotations.map { annotation in
            if let topologyFailure, annotation.anchors.contains(where: Self.anchorsToTopology) {
                return Resolution(
                    measurementID: annotation.id,
                    name: annotation.name,
                    kind: annotation.kind,
                    outcome: .unresolved(EditorError(
                        code: topologyFailure.code,
                        message: "Measurement \"\(annotation.name)\" needs generated topology: \(topologyFailure.message)"
                    ))
                )
            }
            return resolve(annotation, in: document, topology: snapshot)
        }
    }

    private static func anchorsToTopology(_ anchor: MeasurementAnchor) -> Bool {
        anchor.kind == .topologyReference || anchor.kind == .topologyEdgeParameter
    }

    public func resolve(
        _ annotation: MeasurementAnnotation,
        in document: DesignDocument,
        topology: TopologySnapshot?
    ) -> Resolution {
        Resolution(
            measurementID: annotation.id,
            name: annotation.name,
            kind: annotation.kind,
            outcome: outcome(for: annotation, in: document, topology: topology)
        )
    }

    private func outcome(
        for annotation: MeasurementAnnotation,
        in document: DesignDocument,
        topology: TopologySnapshot?
    ) -> Outcome {
        var anchors: [MeasurementAnchorWorldPointResolver.ResolvedAnchor] = []
        anchors.reserveCapacity(annotation.anchors.count)
        for (index, anchor) in annotation.anchors.enumerated() {
            let resolved: MeasurementAnchorWorldPointResolver.ResolvedAnchor?
            do {
                resolved = try anchorResolver.resolvedAnchor(anchor, in: document, topology: topology)
            } catch let error as EditorError {
                return .unresolved(EditorError(
                    code: error.code,
                    message: "Measurement \"\(annotation.name)\" anchor \(index + 1): \(error.message)"
                ))
            } catch {
                return .unresolved(EditorError(
                    code: .referenceUnresolved,
                    message: "Measurement \"\(annotation.name)\" anchor \(index + 1): \(error)"
                ))
            }
            guard let resolved else {
                let reason = Self.anchorsToTopology(anchor) && topology == nil
                    ? "its topology snapshot is unavailable"
                    : "its \(anchor.kind.rawValue) reference no longer resolves"
                return .unresolved(EditorError(
                    code: .referenceUnresolved,
                    message: "Measurement \"\(annotation.name)\" anchor \(index + 1) cannot be placed: \(reason)."
                ))
            }
            anchors.append(resolved)
        }
        return .resolved(anchors)
    }
}
