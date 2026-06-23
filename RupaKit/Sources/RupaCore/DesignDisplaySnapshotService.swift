import SwiftCAD

public struct DesignDisplaySnapshotService: Sendable {
    private let sketchService: SketchDisplaySnapshotService
    private let bodyService: BodyDisplaySnapshotService

    public init(
        sketchService: SketchDisplaySnapshotService = SketchDisplaySnapshotService(),
        bodyService: BodyDisplaySnapshotService = BodyDisplaySnapshotService()
    ) {
        self.sketchService = sketchService
        self.bodyService = bodyService
    }

    public func snapshot(document: DesignDocument) -> DesignDisplaySnapshot {
        snapshot(document: document, bodies: [:])
    }

    public func evaluatedSnapshot(
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> DesignDisplaySnapshot {
        let bodies = try bodyService.snapshots(
            document: document,
            objectRegistry: objectRegistry
        )
        return snapshot(document: document, bodies: bodies)
    }

    private func snapshot(
        document: DesignDocument,
        bodies: [FeatureID: BodyDisplaySnapshot]
    ) -> DesignDisplaySnapshot {
        let sketches = sketchService.snapshots(document: document)
        var extrudes: [FeatureID: ExtrudeDisplaySnapshot] = [:]
        var straightPrismSweeps: [FeatureID: StraightPrismSweepDisplaySnapshot] = [:]
        let graph = document.cadDocument.designGraph
        let parameters = document.cadDocument.parameters

        for featureID in graph.order {
            guard let feature = graph.nodes[featureID] else {
                continue
            }
            switch feature.operation {
            case .extrude(let extrude):
                guard let depthMeters = sketchService.resolvedLength(
                    extrude.distance,
                    parameters: parameters
                ) else {
                    continue
                }
                extrudes[featureID] = ExtrudeDisplaySnapshot(
                    featureID: featureID,
                    profileFeatureID: extrude.profile.featureID,
                    depthMeters: depthMeters,
                    direction: extrude.direction
                )
            case .sweep(let sweep):
                guard let snapshot = straightPrismSweepSnapshot(
                    featureID: featureID,
                    sweep: sweep,
                    sketches: sketches,
                    parameters: parameters
                ) else {
                    continue
                }
                straightPrismSweeps[featureID] = snapshot
            default:
                continue
            }
        }

        return DesignDisplaySnapshot(
            sketches: sketches,
            extrudes: extrudes,
            straightPrismSweeps: straightPrismSweeps,
            bodies: bodies
        )
    }

    public func result(
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        generation: DocumentGeneration,
        dirty: Bool
    ) throws -> DesignDisplaySnapshotResult {
        let snapshot = try evaluatedSnapshot(
            document: document,
            objectRegistry: objectRegistry
        )
        let order = document.cadDocument.designGraph.order
        return DesignDisplaySnapshotResult(
            generation: generation,
            dirty: dirty,
            sketches: order.compactMap { snapshot.sketches[$0] },
            extrudes: order.compactMap { snapshot.extrudes[$0] },
            straightPrismSweeps: order.compactMap { snapshot.straightPrismSweeps[$0] },
            bodies: order.compactMap { snapshot.bodies[$0] }
        )
    }

    private func straightPrismSweepSnapshot(
        featureID: FeatureID,
        sweep: SweepFeature,
        sketches: [FeatureID: SketchDisplaySnapshot],
        parameters: ParameterTable
    ) -> StraightPrismSweepDisplaySnapshot? {
        guard sweep.profiles.count == 1,
              let profile = sweep.profiles.first,
              sweep.guides.isEmpty,
              sweep.options.resultKind == .solid,
              sweep.options.booleanOperation == .newBody,
              sweep.options.keepTools == false,
              let twistAngle = sketchService.resolvedAngle(
                  sweep.options.twistAngle,
                  parameters: parameters
              ),
              twistAngle.isFinite,
              abs(twistAngle) <= 1.0e-9,
              let endScale = sketchService.resolvedScalar(
                  sweep.options.endScale,
                  parameters: parameters
              ),
              endScale.isFinite,
              abs(endScale - 1.0) <= 1.0e-9,
              let distanceFraction = sketchService.resolvedScalar(
                  sweep.options.distanceFraction,
                  parameters: parameters
              ),
              distanceFraction > 0.0,
              distanceFraction <= 1.0,
              let pathVector = sketches[sweep.path.featureID]?.straightOpenPathVector else {
            return nil
        }

        let pathLength = pathVector.length
        guard pathLength > 1.0e-9 else {
            return nil
        }

        return StraightPrismSweepDisplaySnapshot(
            featureID: featureID,
            profileFeatureID: profile.featureID,
            pathFeatureID: sweep.path.featureID,
            depthMeters: pathLength * distanceFraction,
            direction: .vector(Vector3D(
                x: pathVector.x / pathLength,
                y: pathVector.y / pathLength,
                z: pathVector.z / pathLength
            ))
        )
    }
}
