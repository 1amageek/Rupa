import SwiftCAD
import Testing
@testable import RupaCore

/// Place's placement math, surface normals and instance output.
@Suite struct ScenePlacementPlaceTests {
    private let tolerance = 1.0e-9

    private func close(_ a: Vector3D, _ b: Vector3D) -> Bool {
        abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance && abs(a.z - b.z) < tolerance
    }

    private func close(_ a: Point3D, _ b: Point3D) -> Bool {
        abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance && abs(a.z - b.z) < tolerance
    }

    @Test func theSourcePointLandsOnTheDestinationFaceToFace() throws {
        let source = Point3D(x: 1, y: 2, z: 3)
        let destination = Point3D(x: -4, y: 0, z: 5)

        let plain = try SceneNodePlacementSpec(sourcePoint: source, destinationPoint: destination).transform()
        #expect(close(try plain.applied(to: source), destination))
        #expect(close(try plain.applyingLinearPart(to: .unitX), .unitX))

        // The object's +X face is put down onto an upward destination face.
        let faceToFace = try SceneNodePlacementSpec(
            sourcePoint: source, sourceNormal: .unitX,
            destinationPoint: destination, destinationNormal: .unitZ
        ).transform()
        #expect(close(try faceToFace.applied(to: source), destination))
        #expect(close(try faceToFace.applyingLinearPart(to: .unitX), Vector3D(x: 0, y: 0, z: -1)))

        let flipped = try SceneNodePlacementSpec(
            sourcePoint: source, sourceNormal: .unitX,
            destinationPoint: destination, destinationNormal: .unitZ, flipsOrientation: true
        ).transform()
        #expect(close(try flipped.applyingLinearPart(to: .unitX), .unitZ))

        // Without a source normal the up axis stays up, then the spin turns about it.
        let spun = try SceneNodePlacementSpec(
            sourcePoint: source, destinationPoint: destination,
            destinationNormal: .unitZ, angleRadians: .pi / 2, scale: 2
        ).transform()
        #expect(close(try spun.applied(to: source), destination))
        #expect(close(try spun.applyingLinearPart(to: .unitX), Vector3D(x: 0, y: 2, z: 0)))
        #expect(throws: EditorError.self) {
            _ = try SceneNodePlacementSpec(sourcePoint: source, destinationPoint: destination, scale: 0).transform()
        }
    }

    @MainActor
    private func boxUnderMovedParent(_ session: EditorSession) throws -> (box: SceneNodeID, parent: SceneNodeID) {
        _ = try session.execute(.createExtrudedRectangle(
            name: "Box", plane: .xy,
            width: .length(0.1, .meter), height: .length(0.08, .meter),
            depth: .length(0.06, .meter), direction: .normal
        ))
        let box = try #require(session.document.productMetadata.sceneNodes.values.first { $0.reference?.kind == .body }).id
        let group = try session.execute(.groupSceneNodes(name: "Parent", memberIDs: [box], origin: nil))
        let parent = try #require(group.generatedIdentities.sceneNodeIDs.first)
        _ = try session.execute(.setSceneNodeTransform(
            id: parent,
            localTransform: try Transform3D.translation(Vector3D(x: 1, y: -2, z: 0.5))
                .composed(with: try Transform3D.rotation(axis: .unitZ, angleRadians: 0.3))
        ))
        return (box, parent)
    }

    @MainActor
    @Test func pickedSurfaceNormalsAreTheKernelFaceNormalsPlaced() throws {
        let session = EditorSession()
        let (box, _) = try boxUnderMovedParent(session)
        let document = session.document
        let topology = try TopologySnapshotService().snapshot(document: document)
        let hierarchy = try SceneNodeHierarchy(metadata: document.productMetadata)
        let occurrence = try #require(try hierarchy.resolvedOccurrences().first { $0.sourceSceneNodeID == box })
        let faces = topology.entries.filter { $0.kind == .face }
        #expect(faces.count == 6)
        for face in faces {
            let center = try #require(face.center)
            let normal = try #require(face.normal)
            let worldPoint = try occurrence.worldTransform.applied(to: Point3D(x: center.x, y: center.y, z: center.z))
            let expected = try occurrence.worldTransform
                .applyingNormal(to: Vector3D(x: normal.x, y: normal.y, z: normal.z))
                .normalized(tolerance: 1.0e-12)
            let resolved = try PlacedSurfaceNormalResolver().outwardNormal(
                at: worldPoint, on: occurrence.id, document: document, topology: topology
            )
            #expect(close(resolved, expected))
        }
    }

    @MainActor
    @Test func placedInstancesShowTheObjectsAtThePlacementAndShareOneDefinition() throws {
        let session = EditorSession()
        let (box, _) = try boxUnderMovedParent(session)
        let offset = try Transform3D.translation(Vector3D(x: 0.3, y: 0, z: 0))

        let first = try session.execute(.placeSceneNodes(ids: [box], placements: [offset], output: .componentInstance))
        let document = session.document
        #expect(document.productMetadata.componentDefinitions.count == 1)
        #expect(document.productMetadata.componentInstances.count == 1)
        let instanceNode = try #require(first.generatedIdentities.sceneNodeIDs.first {
            document.productMetadata.sceneNodes[$0]?.reference?.kind == .componentInstance
        })
        let hierarchy = try SceneNodeHierarchy(metadata: document.productMetadata)
        let occurrences = try hierarchy.resolvedOccurrences()
        let original = try #require(occurrences.first { $0.sourceSceneNodeID == box && $0.componentInstanceID == nil })
        let placed = try #require(occurrences.first { $0.sourceSceneNodeID == box && $0.sceneNodeID == instanceNode })
        let expected = try offset.composed(with: original.worldTransform)
        #expect(zip(placed.worldTransform.matrix.values, expected.matrix.values).allSatisfy { abs($0 - $1) < tolerance })

        _ = try session.execute(.placeSceneNodes(ids: [box], placements: [offset, offset], output: .componentInstance))
        #expect(session.document.productMetadata.componentDefinitions.count == 1)
        #expect(session.document.productMetadata.componentInstances.count == 3)
        let volume = try MeasurementService().measure(document: session.document, ruler: .standard(for: .meter))
            .totals.solidVolumeCubicMeters
        #expect(abs(volume - 4 * 0.1 * 0.08 * 0.06) < tolerance)
    }

    @MainActor
    @Test func instancesOfObjectsUnderDifferentParentsAreRefused() throws {
        let session = EditorSession()
        let (box, _) = try boxUnderMovedParent(session)
        _ = try session.execute(.createExtrudedRectangle(
            name: "Other", plane: .xy,
            width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(0.1, .meter), direction: .normal
        ))
        let other = try #require(session.document.productMetadata.sceneNodes.values.first {
            $0.reference?.kind == .body && $0.id != box
        }).id
        let before = session.document
        #expect(throws: (any Error).self) {
            _ = try session.execute(.placeSceneNodes(ids: [box, other], placements: [.identity], output: .componentInstance))
        }
        #expect(session.document.productMetadata == before.productMetadata)
    }
}
