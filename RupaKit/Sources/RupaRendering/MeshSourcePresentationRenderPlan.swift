import RupaCoreTypes
import RupaGeometry
import RupaProjectModel
import RupaViewportScene

/// A snapshot-owned traversal plan for MeshSource presentation rendering.
///
/// Construct one plan when a UniversalViewportScene snapshot changes and retain
/// it for the render owner's lifetime. The plan stores only bounded vertex-ID
/// indexes, ear-clipped triangle topology metadata, and immutable MeshSource
/// values; it does not duplicate GeometryBuffer storage or retain derived
/// position payloads.
public struct MeshSourcePresentationRenderPlan: Sendable {
    public let snapshotID: EvaluationSnapshotID
    public let projectID: ProjectID
    public let itemCount: Int
    public let triangleCount: Int
    private let entries: [Entry]

    private struct Entry: Sendable {
        let occurrenceID: SceneOccurrenceID
        let definitionID: ObjectDefinitionID
        let representationID: GeometryRepresentationID
        let sourceReference: GeometrySourceReference
        let mesh: MeshSource
        let worldTransform: GeometryTransform3D
        let vertexIndexByID: [MeshVertexID: Int]
        let triangles: [MeshTriangle]
        let triangleCount: Int

        init(item: UniversalViewportSceneItem) throws {
            do {
                try item.validate()
            } catch let error as UniversalViewportSceneError {
                throw MeshSourcePresentationRenderPlan.sceneItemError(error)
            }

            guard item.worldTransform.values.count == 16,
                  item.worldTransform.values.allSatisfy(\.isFinite) else {
                throw MeshSourcePresentationRenderError(
                    code: .invalidTransform,
                    message: "Presentation item \(item.occurrenceID.rawValue) has an invalid world transform."
                )
            }

            let mesh = item.mesh
            guard mesh.vertexIDs.count == mesh.vertexPositions.count else {
                throw MeshSourcePresentationRenderError(
                    code: .invalidVertexReference,
                    message: "Presentation MeshSource vertex IDs and positions have different counts."
                )
            }
            guard mesh.faceIDs.count == mesh.faceCornerRanges.count else {
                throw MeshSourcePresentationRenderError(
                    code: .invalidFaceRange,
                    message: "Presentation MeshSource face IDs and corner ranges have different counts."
                )
            }
            guard mesh.cornerIDs.count == mesh.cornerVertexIDs.count else {
                throw MeshSourcePresentationRenderError(
                    code: .invalidCornerReference,
                    message: "Presentation MeshSource corner IDs and vertex references have different counts."
                )
            }

            var vertexIndexByID: [MeshVertexID: Int] = [:]
            vertexIndexByID.reserveCapacity(mesh.vertexIDs.count)
            for index in mesh.vertexIDs.indices {
                let vertexID = mesh.vertexIDs[index]
                guard vertexIndexByID.updateValue(index, forKey: vertexID) == nil else {
                    throw MeshSourcePresentationRenderError(
                        code: .invalidVertexReference,
                        message: "Presentation MeshSource contains duplicate vertex IDs."
                    )
                }
            }

            var triangles: [MeshTriangle] = []
            for faceIndex in mesh.faceCornerRanges.indices {
                let range = mesh.faceCornerRanges[faceIndex]
                do {
                    try range.validate(upperBound: mesh.cornerVertexIDs.count)
                } catch let error as MeshSourceError {
                    throw MeshSourcePresentationRenderError(
                        code: .invalidFaceRange,
                        message: error.message
                    )
                }
                guard range.count >= 3 else {
                    throw MeshSourcePresentationRenderError(
                        code: .degenerateFace,
                        message: "Presentation MeshSource faces require at least three corners."
                    )
                }
                var cornerIndex = range.start
                while cornerIndex < range.end {
                    let vertexID = mesh.cornerVertexIDs[cornerIndex]
                    guard vertexIndexByID[vertexID] != nil else {
                        throw MeshSourcePresentationRenderError(
                            code: .invalidVertexReference,
                            message: "Presentation MeshSource corner references a missing vertex."
                        )
                    }
                    cornerIndex += 1
                }

                let faceID = mesh.faceIDs[faceIndex]
                let faceTriangles: [MeshTriangle]
                do {
                    faceTriangles = try mesh.triangulate(faceID: faceID)
                } catch let error as MeshTriangulationError {
                    throw MeshSourcePresentationRenderPlan.triangulationError(error)
                } catch {
                    throw MeshSourcePresentationRenderError(
                        code: .failed,
                        message: String(describing: error)
                    )
                }
                let addition = triangles.count.addingReportingOverflow(faceTriangles.count)
                guard !addition.overflow else {
                    throw MeshSourcePresentationRenderError(
                        code: .sizeOverflow,
                        message: "Presentation MeshSource triangle count exceeds the supported range."
                    )
                }
                triangles.append(contentsOf: faceTriangles)
            }

            self.occurrenceID = item.occurrenceID
            self.definitionID = item.definitionID
            self.representationID = item.representationID
            self.sourceReference = item.sourceReference
            self.mesh = mesh
            self.worldTransform = item.worldTransform
            self.vertexIndexByID = vertexIndexByID
            self.triangles = triangles
            self.triangleCount = triangles.count
        }

        func forEachTriangle(
            _ visit: (MeshSourcePresentationTriangle) throws -> Void
        ) throws {
            for triangle in triangles {
                let firstVertexID = triangle.vertexIDs.0
                let secondVertexID = triangle.vertexIDs.1
                let thirdVertexID = triangle.vertexIDs.2
                let firstPositionIndex = try positionIndex(for: firstVertexID)
                let firstPosition = try transformed(mesh.vertexPositions[firstPositionIndex])
                let secondPosition = try transformed(
                    mesh.vertexPositions[try positionIndex(for: secondVertexID)]
                )
                let thirdPosition = try transformed(
                    mesh.vertexPositions[try positionIndex(for: thirdVertexID)]
                )
                try visit(
                    MeshSourcePresentationTriangle(
                        occurrenceID: occurrenceID,
                        definitionID: definitionID,
                        representationID: representationID,
                        sourceReference: sourceReference,
                        faceID: triangle.faceID,
                        firstVertexID: firstVertexID,
                        secondVertexID: secondVertexID,
                        thirdVertexID: thirdVertexID,
                        firstPosition: firstPosition,
                        secondPosition: secondPosition,
                        thirdPosition: thirdPosition
                    )
                )
            }
        }

        private func positionIndex(for vertexID: MeshVertexID) throws -> Int {
            guard let index = vertexIndexByID[vertexID],
                  index >= mesh.vertexPositions.startIndex,
                  index < mesh.vertexPositions.endIndex else {
                throw MeshSourcePresentationRenderError(
                    code: .invalidVertexReference,
                    message: "Presentation MeshSource vertex reference is outside its position buffer."
                )
            }
            return index
        }

        private func transformed(_ point: GeometryPoint3D) throws -> GeometryPoint3D {
            do {
                return try worldTransform.applying(to: point)
            } catch let error as MeshSourceError {
                throw MeshSourcePresentationRenderError(
                    code: .transformFailure,
                    message: error.message
                )
            } catch {
                throw MeshSourcePresentationRenderError(
                    code: .transformFailure,
                    message: String(describing: error)
                )
            }
        }
    }

    public init(scene: UniversalViewportScene) throws {
        var entries: [Entry] = []
        entries.reserveCapacity(scene.items.count)
        var triangleCount = 0
        for item in scene.items {
            let entry = try Entry(item: item)
            let addition = triangleCount.addingReportingOverflow(entry.triangleCount)
            guard !addition.overflow else {
                throw MeshSourcePresentationRenderError(
                    code: .sizeOverflow,
                    message: "Presentation scene triangle count exceeds the supported range."
                )
            }
            triangleCount = addition.partialValue
            entries.append(entry)
        }
        self.snapshotID = scene.snapshotID
        self.projectID = scene.projectID
        self.itemCount = entries.count
        self.triangleCount = triangleCount
        self.entries = entries
    }

    /// Traverses ear-clipped world-space triangles without retaining derived
    /// position payloads. The supplied consumer owns any output it chooses to
    /// retain.
    public func forEachTriangle(
        _ visit: (MeshSourcePresentationTriangle) throws -> Void
    ) throws {
        for entry in entries {
            try entry.forEachTriangle(visit)
        }
    }

    private static func sceneItemError(
        _ error: UniversalViewportSceneError
    ) -> MeshSourcePresentationRenderError {
        let code: MeshSourcePresentationRenderError.Code
        switch error.code {
        case .invalidIdentifier:
            code = .invalidIdentifier
        case .sourceMismatch, .sourceIdentityMismatch:
            code = .sourceAuthorityMismatch
        case .missingDefinition, .projectMismatch, .purposeMismatch, .occurrenceMismatch:
            code = .invalidSceneItem
        }
        return MeshSourcePresentationRenderError(code: code, message: error.message)
    }

    private static func triangulationError(
        _ error: MeshTriangulationError
    ) -> MeshSourcePresentationRenderError {
        let code: MeshSourcePresentationRenderError.Code
        switch error.code {
        case .missingFace:
            code = .missingFace
        case .nonPlanar:
            code = .nonPlanar
        case .degenerate:
            code = .degenerate
        case .failed:
            code = .failed
        }
        return MeshSourcePresentationRenderError(code: code, message: error.message)
    }
}
