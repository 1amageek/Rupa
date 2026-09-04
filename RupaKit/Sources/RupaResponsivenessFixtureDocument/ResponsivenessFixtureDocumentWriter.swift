import Foundation
import RupaCore
import RupaCoreTypes
import RupaGeometry
import RupaProject
import RupaProjectModel
import RupaProjectPackage
import RupaResponsivenessBaseline
import SwiftCAD

/// Writes the responsiveness fixture as a project package the signed
/// application opens, so an application-side measurement is taken against the
/// content the in-process harness measured rather than a similar scene.
///
/// The writer never reports success from the write alone. It reloads the
/// written package through the same store the application loads with and
/// compares the reloaded authored mesh assets, body count, vertex total, and
/// face total against the fixture; a difference is a typed failure.
public struct ResponsivenessFixtureDocumentWriter: Sendable {
    /// What the written package contains, read back from the written file.
    public struct WriteResult: Sendable, Equatable {
        public let url: URL
        public let fixtureContentDigest: String
        public let bodyCount: Int
        public let vertexCount: Int
        public let faceCount: Int
        public let byteCount: Int

        public init(
            url: URL,
            fixtureContentDigest: String,
            bodyCount: Int,
            vertexCount: Int,
            faceCount: Int,
            byteCount: Int
        ) {
            self.url = url
            self.fixtureContentDigest = fixtureContentDigest
            self.bodyCount = bodyCount
            self.vertexCount = vertexCount
            self.faceCount = faceCount
            self.byteCount = byteCount
        }
    }

    private let store: ProjectPackageStore
    private let productSourceCodec: JSONProjectProductSourceCodec

    public init(limits: ProjectPackageResourceLimits = .standard) {
        store = ProjectPackageStore(limits: limits)
        productSourceCodec = JSONProjectProductSourceCodec()
    }

    /// Builds the document, writes it, and reloads it to prove the written
    /// package reproduces the fixture.
    @discardableResult
    public func write(
        _ fixture: ResponsivenessFixture,
        to url: URL
    ) throws -> WriteResult {
        let document = try makeDocument(fixture)
        let package = try makePackage(document)
        do {
            _ = try store.save(package, to: url)
        } catch {
            throw ResponsivenessFixtureDocumentError(
                code: .packageWriteFailed,
                message: "The fixture package could not be written to \(url.path): \(error)."
            )
        }
        let reloaded = try reload(from: url)
        try verify(reloaded, against: fixture, document: document, url: url)
        return WriteResult(
            url: url,
            fixtureContentDigest: fixture.contentDigest,
            bodyCount: fixture.bodies.count,
            vertexCount: fixture.vertexCount,
            faceCount: fixture.faceCount,
            byteCount: try byteCount(of: url)
        )
    }

    // MARK: - Document

    private func makeDocument(
        _ fixture: ResponsivenessFixture
    ) throws -> DesignDocument {
        var document = DesignDocument.empty(named: fixture.parameters.name)
        guard let rootID = document.productMetadata.rootSceneNodeIDs.first,
            document.productMetadata.sceneNodes[rootID] != nil
        else {
            throw ResponsivenessFixtureDocumentError(
                code: .documentConstructionFailed,
                message: "An empty design document did not provide a root scene node."
            )
        }
        for (index, body) in fixture.bodies.enumerated() {
            let representationID = GeometryRepresentationID(
                rawValue: "representation.\(fixture.parameters.name).\(index)"
            )
            let source = GeometrySourceReference.authoredMesh(body.asset.id)
            let transform: Transform3D
            do {
                transform = Transform3D(
                    matrix: try Matrix4x4(values: body.worldTransform.values)
                )
            } catch {
                throw ResponsivenessFixtureDocumentError(
                    code: .documentConstructionFailed,
                    message: "Fixture body \(index) has an invalid placement: \(error)."
                )
            }
            let node = SceneNode(
                name: "Body \(index)",
                reference: .authoredMesh(body.asset.id),
                object: ObjectDescriptor(
                    category: .body,
                    geometryRole: .mesh,
                    geometryRepresentations: GeometryRepresentationSet(
                        representations: [
                            representationID: GeometryRepresentation(
                                id: representationID,
                                source: source
                            ),
                        ],
                        selection: GeometryRepresentationSelection(
                            modeling: representationID,
                            presentation: representationID
                        )
                    )
                ),
                localTransform: transform
            )
            document.authoredMeshAssets[body.asset.id] = body.asset
            document.productMetadata.sceneNodes[node.id] = node
            document.productMetadata.sceneNodes[rootID]?.childIDs.append(node.id)
        }
        do {
            _ = try document.validate()
        } catch {
            throw ResponsivenessFixtureDocumentError(
                code: .documentInvalid,
                message: "The fixture design document is not valid: \(error)."
            )
        }
        return document
    }

    // MARK: - Package

    private func makePackage(
        _ document: DesignDocument
    ) throws -> ProjectPackageDocument {
        let productSource: ProjectPackageProductSource
        do {
            productSource = try productSourceCodec.encode(document)
        } catch {
            throw ResponsivenessFixtureDocumentError(
                code: .productSourceEncodingFailed,
                message: "The fixture Product source could not be encoded: \(error)."
            )
        }
        do {
            // The fixture carries no CAD features, so the document has no
            // authoritative CAD source and the package records none.
            return try ProjectPackageDocument(
                documentID: document.projectID,
                productSource: productSource,
                cadSource: nil,
                authoredMeshAssets: document.authoredMeshAssets
            )
        } catch {
            throw ResponsivenessFixtureDocumentError(
                code: .packageConstructionFailed,
                message: "The fixture package could not be assembled: \(error)."
            )
        }
    }

    // MARK: - Verification

    private func reload(from url: URL) throws -> ProjectPackageDocument {
        do {
            return try store.load(from: url)
        } catch {
            throw ResponsivenessFixtureDocumentError(
                code: .writtenPackageDiffersFromFixture,
                message: "The written fixture package could not be reloaded: \(error)."
            )
        }
    }

    private func verify(
        _ reloaded: ProjectPackageDocument,
        against fixture: ResponsivenessFixture,
        document: DesignDocument,
        url: URL
    ) throws {
        guard reloaded.authoredMeshAssets == document.authoredMeshAssets else {
            throw ResponsivenessFixtureDocumentError(
                code: .writtenPackageDiffersFromFixture,
                message: "The reloaded authored mesh assets are not the fixture's assets."
            )
        }
        for (index, body) in fixture.bodies.enumerated() {
            guard let asset = reloaded.authoredMeshAssets[body.asset.id] else {
                throw ResponsivenessFixtureDocumentError(
                    code: .writtenPackageDiffersFromFixture,
                    message: "The reloaded package does not carry fixture body \(index)."
                )
            }
            guard asset == body.asset else {
                throw ResponsivenessFixtureDocumentError(
                    code: .writtenPackageDiffersFromFixture,
                    message: "Reloaded fixture body \(index) is not the mesh the fixture built."
                )
            }
        }
        let reloadedVertexCount = reloaded.authoredMeshAssets.values.reduce(0) {
            $0 + $1.source.vertexIDs.count
        }
        let reloadedFaceCount = reloaded.authoredMeshAssets.values.reduce(0) {
            $0 + $1.source.faceIDs.count
        }
        guard reloadedVertexCount == fixture.vertexCount,
            reloadedFaceCount == fixture.faceCount
        else {
            throw ResponsivenessFixtureDocumentError(
                code: .writtenPackageDiffersFromFixture,
                message: """
                    The reloaded package carries \(reloadedVertexCount) vertices and \
                    \(reloadedFaceCount) faces, but the fixture carries \
                    \(fixture.vertexCount) and \(fixture.faceCount).
                    """
            )
        }
        let product: ProjectProductSourceModel
        do {
            product = try productSourceCodec.decode(reloaded.productSource)
        } catch {
            throw ResponsivenessFixtureDocumentError(
                code: .writtenPackageDiffersFromFixture,
                message: "The reloaded Product source could not be decoded: \(error)."
            )
        }
        let bodyNodeCount = product.productMetadata.sceneNodes.values.count {
            $0.reference?.kind == .authoredMesh
        }
        guard bodyNodeCount == fixture.bodies.count else {
            throw ResponsivenessFixtureDocumentError(
                code: .writtenPackageDiffersFromFixture,
                message: """
                    The reloaded document at \(url.path) presents \(bodyNodeCount) mesh \
                    bodies, but the fixture has \(fixture.bodies.count).
                    """
            )
        }
    }

    private func byteCount(of url: URL) throws -> Int {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize else {
                throw ResponsivenessFixtureDocumentError(
                    code: .packageWriteFailed,
                    message: "The written fixture package reported no size."
                )
            }
            return size
        } catch let error as ResponsivenessFixtureDocumentError {
            throw error
        } catch {
            throw ResponsivenessFixtureDocumentError(
                code: .packageWriteFailed,
                message: "The written fixture package size could not be read: \(error)."
            )
        }
    }
}
